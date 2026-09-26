extends Node
## 《拯救鄱阳湖》主场景：2.5D 沙盘 + 四区 UI。逻辑在 GameState 单例。

const METRIC_COLORS := {
	"water_level": Color(0.30, 0.58, 0.95),
	"vegetation": Color(0.40, 0.76, 0.38),
	"water_quality": Color(0.30, 0.80, 0.80),
	"fish": Color(0.40, 0.50, 0.88),
	"birds": Color(0.88, 0.88, 0.92),
	"community": Color(0.96, 0.68, 0.32),
}
const CATEGORY_NAMES := {"ecology": "生态", "social": "社会", "manage": "管理"}
const CATEGORY_COLORS := {
	"ecology": Color(0.42, 0.75, 0.46),
	"social": Color(0.95, 0.70, 0.36),
	"manage": Color(0.56, 0.66, 0.90),
}
const SEASONS := ["春", "夏", "秋", "冬"]

# UI 节点
var left_panel: PanelContainer
var turn_label: Label
var season_label: Label
var funds_label: Label
var spent_label: Label
var research_label: Label
var event_label: Label
var right_panel: PanelContainer
var metric_bars: Dictionary = {}
var hand_panel: PanelContainer
var end_turn_btn: Button
var bottom_right: VBoxContainer
var card_box: Control
var selected_label: Label
var current_hand: Array = []   # 当前手牌（card dict 数组）
var card_infos: Array = []     # {panel, card_id, base_pos, theta, radial, selected}
var _fan_layout_size: Vector2 = Vector2.ZERO  # 上次布局时的容器尺寸
var play_deal_anim: bool = false              # 下次布局时播放发牌入场动画
var popup_root: Control
var dim: ColorRect
var popup_center: CenterContainer
var popup_panel: PanelContainer
var popup_title: Label
var popup_body: RichTextLabel
var popup_button: Button
var _popup_continue: Callable = Callable()
var _current_event: String = ""

# 主菜单
var menu_root: Control
var menu_title_panel: PanelContainer
var menu_difficulty_panel: PanelContainer
var menu_seed_panel: PanelContainer
var menu_mode_label: Label
var seed_input: LineEdit
var menu_hint: Label
var menu_talent_panel: PanelContainer
var talent_points_label: Label
var talent_list: VBoxContainer
var talent_unlock_btn: Button

# 3D 表现节点
var lake_mesh: MeshInstance3D
var lake_mat: ShaderMaterial
var lake_color: Color = Color(0.62, 0.80, 0.86, 0.88)
var grass_nodes: Array = []
var grass_mats: Array = []
var bird_nodes: Array = []
var fish_nodes: Array = []
var island_nodes: Array = []      # 人工浮岛节点
var house_slots: Array = []       # 每项 {"house": Node3D, "reeds": Node3D, "mats": Array}
var species_views: Dictionary = {}  # sid -> {rigs[], bases[], states[], timers[], targets[]}
var plant_views: Dictionary = {}    # pid -> {meshes[], kind}
var plant_positions: Dictionary = {} # pid -> Array[Vector3]  每局随机散落的位置
var _plant_pos_seed: int = -1        # 已生成位置对应的种子，换局时重新散落


func _ready() -> void:
	_setup_pixel_font()
	_setup_camera()
	_build_3d()
	_build_pixelate_layer()
	_build_ui()
	GameState.metrics_changed.connect(_update_hud)
	GameState.metrics_changed.connect(_update_3d)
	GameState.funds_changed.connect(_update_hud)
	GameState.event_triggered.connect(_on_event)
	GameState.game_ended.connect(_on_game_end)
	# 先显示主菜单：玩家输入种子后点“开始游戏”才真正开局
	_show_menu()
	# 窗口尺寸/全屏变化时自适应相机，避免全屏后沙盘被裁或留黑边
	get_viewport().size_changed.connect(_fit_camera_to_window)
	_fit_camera_to_window()


## 根据窗口宽高比调整正交相机尺寸：让沙盘占满屏幕主体，不因宽屏被推远
func _fit_camera_to_window() -> void:
	var cam := get_node("../Camera3D") as Camera3D
	if cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	var aspect := vp.x / vp.y
	# 沙盘在 45° 俯视下的垂直投影约 29 世界单位，留边距 → 垂直视野 31
	const VIEW_H := 31.0
	# 窄屏时保证水平也能容纳沙盘宽度
	const NEED_W := 50.0
	cam.size = maxf(VIEW_H, NEED_W / aspect)


# ==================== 相机 ====================
func _setup_camera() -> void:
	var cam := get_node("../Camera3D") as Camera3D
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 26.0  # 更大的正交尺寸 = 视野更广，能看全沙盘
	# 2.5D 等距俯视：方位角 45°、俯角 45°（视野开阔，地形一览无余）
	cam.position = Vector3(14, 14, 14)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)

	# 沙盘地面：与远景布景协调的草绿（替代场景里的深绿盒子观感）
	var ground_mesh := get_node_or_null("../Ground/GroundMesh") as MeshInstance3D
	if ground_mesh:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.66, 0.74, 0.52)
		gm.roughness = 1.0
		ground_mesh.material_override = gm

	# 柔白方向光（明亮通透，粉彩感）
	var light := get_node("../DirectionalLight3D") as DirectionalLight3D
	light.light_color = Color(1.0, 0.97, 0.92)
	light.light_energy = 1.15
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.shadow_enabled = true

	# 提亮环境光，画面更柔和明亮
	var env_node := get_node("../WorldEnvironment") as WorldEnvironment
	if env_node and env_node.environment:
		var env := env_node.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.76, 0.78, 0.72)
		env.ambient_light_energy = 0.95
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC


# ==================== 3D 表现 ====================
func _build_3d() -> void:
	var lake_view := Node3D.new()
	lake_view.name = "LakeView"

	# 湖面（鄱阳湖形不规则多边形 + 注入河流）
	lake_mat = ShaderMaterial.new()
	lake_mat.shader = _make_water_shader()
	lake_mat.set_shader_parameter("water_color", lake_color)
	_build_lake_shape(lake_view)

	# 棋盘网格线（生息演算式棋盘感）
	_build_grid(lake_view)

	# 草洲（8 块，主湖区中的草岛，避开河流入湖口）
	var grass_positions := [
		Vector3(-5, 0.05, -1.5), Vector3(-1, 0.05, -2), Vector3(3.5, 0.05, -1.5),
		Vector3(6, 0.05, 0.5), Vector3(1.5, 0.05, 1.5), Vector3(4.5, 0.05, 3.5),
		Vector3(0, 0.05, 5), Vector3(-3.5, 0.05, 4.5),
	]
	for p in grass_positions:
		var mi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(3.0, 0.25, 3.0)
		mi.mesh = cm
		mi.position = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.64, 0.76, 0.50)
		mi.material_override = mat
		lake_view.add_child(mi)
		grass_nodes.append(mi)
		grass_mats.append(mat)

	# 湿地泥滩（浅水与草洲之间的过渡带，暖褐色）
	_build_mudflats(lake_view)

	# 鸟群（8 只白鹤占位）—— 替换为多物种动态个体系统
	_build_species_views(lake_view)

	# 植物（不同湿地植物）
	_build_plant_views(lake_view)

	# 鱼群（8 条占位，水下）
	for i in 8:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.35
		mi.mesh = sm
		mi.position = Vector3(-5 + i * 1.6, -0.15, 2 - (i % 3) * 1.8)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.70, 0.76, 0.82)
		mi.material_override = mat
		lake_view.add_child(mi)
		fish_nodes.append(mi)

	# 人工浮岛（初始隐藏，打出「人工浮岛」牌后显示）
	_build_floating_islands(lake_view)

	# 渔村（湖边一排房子）
	_build_village(lake_view)

	# 远景布景草地（环绕沙盘的低多边形起伏草原，不参与游戏交互）
	_build_backdrop_grass(lake_view)

	# 延迟挂到场景，避免父节点初始化期 add_child 冲突
	var root := get_parent() as Node3D
	root.add_child.call_deferred(lake_view)


## 构建鄱阳湖形水面：南宽北狭的「宝葫芦」形，北部狭长入江水道连长江
func _build_lake_shape(parent: Node3D) -> void:
	# 鄱阳湖轮廓（XZ 平面多边形，北为 -z，南为 +z；北窄为入江水道，南宽为主湖区）
	var outline: PackedVector2Array = [
		Vector2(-1.4, -14.0), Vector2(1.4, -14.0),
		Vector2(1.8, -11.0), Vector2(2.2, -8.0), Vector2(2.8, -5.5),
		Vector2(6.5, -5.0), Vector2(8.5, -3.0), Vector2(9.4, 0.0),
		Vector2(9.0, 3.0), Vector2(7.6, 5.5),
		Vector2(5.8, 7.6), Vector2(3.4, 8.4), Vector2(0.0, 8.9),
		Vector2(-3.4, 8.4), Vector2(-5.8, 7.6),
		Vector2(-7.6, 5.5), Vector2(-9.0, 3.0), Vector2(-9.4, 0.0),
		Vector2(-8.5, -3.0), Vector2(-6.5, -5.0),
		Vector2(-2.8, -5.5), Vector2(-2.2, -8.0), Vector2(-1.8, -11.0),
	]
	lake_mesh = _make_flat_polygon(outline, 0.08, lake_mat)
	lake_mesh.name = "PoyangLake"
	parent.add_child(lake_mesh)
	_build_rivers(parent)


## 由中心线生成河流轮廓（两侧各偏移半宽，中心线可弯曲）
func _river_outline(center: PackedVector2Array, width: float) -> PackedVector2Array:
	var left: PackedVector2Array = []
	var right: PackedVector2Array = []
	var n := center.size()
	for i in n:
		var prev: Vector2 = center[clampi(i - 1, 0, n - 1)]
		var nxt: Vector2 = center[clampi(i + 1, 0, n - 1)]
		var dir: Vector2 = (nxt - prev)
		if dir.length() < 0.0001:
			dir = Vector2(1, 0)
		dir = dir.normalized()
		var normal := Vector2(-dir.y, dir.x)  # 垂直方向
		var half := width * 0.5
		left.append(center[i] + normal * half)
		right.append(center[i] - normal * half)
	var outline := left.duplicate()
	for i in range(n - 1, -1, -1):
		outline.append(right[i])
	return outline


## 河流：长江（北，蜿蜒自西向东）+ 赣江（南，自南向北，与之垂直）+ 修水/饶河
func _build_rivers(parent: Node3D) -> void:
	# 长江：北侧蜿蜒大河，湖体北口（入江水道 z=-14）汇入其中
	var yangtze_center := PackedVector2Array([
		Vector2(-18.0, -14.0), Vector2(-13.0, -15.5), Vector2(-8.0, -13.5),
		Vector2(-3.0, -15.0), Vector2(2.0, -13.8), Vector2(7.0, -15.2),
		Vector2(12.0, -13.6), Vector2(18.0, -14.8),
	])
	var yangtze := _make_flat_polygon(_river_outline(yangtze_center, 2.6), 0.08, lake_mat)
	yangtze.name = "Yangtze"
	parent.add_child(yangtze)

	# 赣江：南侧，自南向北注入湖体南部（第一大支流，与长江近垂直）
	var gan_center := PackedVector2Array([
		Vector2(0.0, 8.0), Vector2(0.0, 13.0), Vector2(0.0, 18.0), Vector2(0.0, 22.0),
	])
	var gan := _make_flat_polygon(_river_outline(gan_center, 1.8), 0.08, lake_mat)
	gan.name = "GanRiver"
	parent.add_child(gan)

	# 修水：西北注入
	var xiu_center := PackedVector2Array([
		Vector2(-6.0, -3.5), Vector2(-9.5, -6.0), Vector2(-12.5, -8.0), Vector2(-15.0, -10.5),
	])
	var xiu := _make_flat_polygon(_river_outline(xiu_center, 1.1), 0.08, lake_mat)
	xiu.name = "XiuRiver"
	parent.add_child(xiu)

	# 饶河：东侧注入
	var rao_center := PackedVector2Array([
		Vector2(8.0, 1.5), Vector2(11.0, 0.5), Vector2(14.0, 1.5), Vector2(16.5, 2.5),
	])
	var rao := _make_flat_polygon(_river_outline(rao_center, 1.0), 0.08, lake_mat)
	rao.name = "RaoRiver"
	parent.add_child(rao)


## 用多边形构建一块平面水面（在 y 平面，unshaded 水面材质）
func _make_flat_polygon(points: PackedVector2Array, y: float, mat: Material) -> MeshInstance3D:
	var indices := Geometry2D.triangulate_polygon(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in indices:
		var p: Vector2 = points[i]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, y, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 为鸟类找一个栖息点：优先乔木树冠，其次草洲/挺水植物
func _find_perch_point(sid: String, seed_i: int) -> Vector3:
	# 优先在乔木上停歇（树冠高度约 1.5~2.6）
	var tree_rigs: Array = plant_views.get("chishan", {}).get("rigs", [])
	var visible_trees: Array = []
	for r in tree_rigs:
		if r.visible:
			visible_trees.append(r)
	if not visible_trees.is_empty():
		var t: Node3D = visible_trees[(seed_i * 7 + int(sid.length())) % visible_trees.size()]
		return t.position + Vector3(0, 2.5, 0)
	# 退而求其次：草洲/挺水植物上方
	for kind_want in ["marsh", "emergent"]:
		for pid in plant_views:
			if plant_views[pid]["kind"] != kind_want:
				continue
			var rigs: Array = plant_views[pid]["rigs"]
			var vis: Array = []
			for r in rigs:
				if r.visible:
					vis.append(r)
			if not vis.is_empty():
				var p: Node3D = vis[(seed_i * 5 + 3) % vis.size()]
				return p.position + Vector3(0, 1.2, 0)
	# 最后兜底：原地
	return Vector3(-6 + seed_i * 1.2, 1.0, -3 + (seed_i % 3) * 2.0)


## 远景布景：环绕沙盘的起伏草原（纯装饰，不参与任何游戏交互）
func _build_backdrop_grass(parent: Node3D) -> void:
	var backdrop := Node3D.new()
	backdrop.name = "Backdrop"
	parent.add_child(backdrop)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925  # 固定种子，每次启动地貌一致

	# 1) 起伏地面：大尺寸 PlaneMesh + 顶点位移（用 SurfaceTool 造波状起伏）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 90.0     # 覆盖 180×180，远超沙盘，视野边缘不会露空
	var cells := 60
	var step := half * 2.0 / cells
	for ix in cells:
		for iz in cells:
			var x0 := -half + ix * step
			var z0 := -half + iz * step
			var x1 := x0 + step
			var z1 := z0 + step
			var v00 := Vector3(x0, _backdrop_height(x0, z0), z0)
			var v10 := Vector3(x1, _backdrop_height(x1, z0), z0)
			var v01 := Vector3(x0, _backdrop_height(x0, z1), z1)
			var v11 := Vector3(x1, _backdrop_height(x1, z1), z1)
			# 双面渲染 + 显式向上法线，彻底避免朝向/背光问题
			var up := Vector3.UP
			st.set_normal(up); st.add_vertex(v00)
			st.set_normal(up); st.add_vertex(v11)
			st.set_normal(up); st.add_vertex(v01)
			st.set_normal(up); st.add_vertex(v00)
			st.set_normal(up); st.add_vertex(v10)
			st.set_normal(up); st.add_vertex(v11)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _mat(Color(0.66, 0.74, 0.54))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(0, -0.28, 0)  # 略低于沙盘地面，避免z-fighting
	backdrop.add_child(ground)

	# 2) 散落的远景树（沙盘外围才放，避免遮挡主场景）
	var tree_spots: Array = []
	for k in 150:
		var ang := rng.randf_range(0, TAU)
		var dist := rng.randf_range(24.0, 82.0)  # 只在沙盘(±18)之外
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		tree_spots.append(Vector3(x, _backdrop_height(x, z), z))
	for p in tree_spots:
		var t := _make_backdrop_tree(rng)
		t.position = p
		backdrop.add_child(t)

	# 3) 灌木丛点缀
	for k in 90:
		var ang := rng.randf_range(0, TAU)
		var dist := rng.randf_range(22.0, 85.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var bush := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = rng.randf_range(0.7, 1.4)
		bm.height = bm.radius * 1.1
		bush.mesh = bm
		bush.material_override = _mat(Color(0.52, 0.64, 0.44).lightened(rng.randf_range(0.0, 0.14)))
		bush.position = Vector3(x, _backdrop_height(x, z) + bm.radius * 0.4, z)
		bush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		backdrop.add_child(bush)


## 远景地形高度：几层正弦叠加，形成平缓起伏（距离沙盘越远越不必精确）
func _backdrop_height(x: float, z: float) -> float:
	var h := sin(x * 0.11) * cos(z * 0.13) * 1.6
	h += sin(x * 0.31 + 1.7) * cos(z * 0.27 - 0.6) * 0.55
	h += sin(x * 0.63 - 0.4) * cos(z * 0.58 + 2.1) * 0.22
	# 靠近沙盘（半径 22 内）压平并下沉，与沙盘地面平滑衔接
	var d := Vector2(x, z).length()
	if d < 26.0:
		var t := clampf((d - 20.0) / 6.0, 0.0, 1.0)
		h = lerpf(-0.28, h, t)
	return h


## 远景树：低多边形锥形树（随机高矮胖瘦）
func _make_backdrop_tree(rng: RandomNumberGenerator) -> Node3D:
	var tree := Node3D.new()
	var h := rng.randf_range(2.2, 4.6)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.10
	tm.bottom_radius = 0.20
	tm.height = h * 0.45
	trunk.mesh = tm
	trunk.material_override = _mat(Color(0.55, 0.45, 0.36))
	trunk.position = Vector3(0, h * 0.225, 0)
	tree.add_child(trunk)
	var layers := 2 + rng.randi() % 2
	for layer in layers:
		var canopy := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		var r := h * 0.30 * (1.0 - layer * 0.22)
		cm.bottom_radius = r
		cm.height = h * 0.42
		canopy.mesh = cm
		var green := rng.randf_range(0.55, 0.72)
		canopy.material_override = _mat(Color(green * 0.80, green, green * 0.82))
		canopy.position = Vector3(0, h * 0.42 + layer * h * 0.20, 0)
		canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tree.add_child(canopy)
	return tree


## 人工浮岛：水面上的绿色浮床（打出「人工浮岛」牌后显示，拆除牌后隐藏）
func _build_floating_islands(parent: Node3D) -> void:
	var island_positions := [
		Vector3(-4, 0, -2.5), Vector3(0, 0, -0.5), Vector3(3.5, 0, 2), Vector3(-2, 0, 3.5),
	]
	for p in island_positions:
		var island := _make_floating_island()
		island.position = p
		island.visible = false
		parent.add_child(island)
		island_nodes.append(island)


## 单个浮岛模型：棕色浮床底座 + 绿色植被 + 几株挺水植物
func _make_floating_island() -> Node3D:
	var island := Node3D.new()
	# 浮床底座
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.16, 1.4)
	base.mesh = bm
	base.material_override = _mat(Color(0.55, 0.42, 0.30))
	base.position = Vector3(0, 0.17, 0)
	island.add_child(base)
	# 植被层
	var veg := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(1.4, 0.28, 1.0)
	veg.mesh = vm
	veg.material_override = _mat(Color(0.40, 0.66, 0.36))
	veg.position = Vector3(0, 0.38, 0)
	island.add_child(veg)
	# 几株挺水植物点缀
	for k in 3:
		var sprout := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.02
		sm.bottom_radius = 0.05
		sm.height = 0.5 + (k % 2) * 0.15
		sprout.mesh = sm
		sprout.material_override = _mat(Color(0.45, 0.70, 0.38))
		sprout.position = Vector3((k - 1) * 0.5, 0.38 + (0.5 + (k % 2) * 0.15) / 2.0, (k % 2 - 0.5) * 0.3)
		island.add_child(sprout)
	return island


## 湖边社区：房子数量随用地（settlement）增减，原地拆除处长出湿地芦苇；颜色随社区信任度明暗变化
func _build_village(parent: Node3D) -> void:
	var house_positions := [
		Vector3(-11, 0, -7), Vector3(-12.5, 0, -5.2), Vector3(-13, 0, -3.4),
		Vector3(-12.2, 0, -1.6), Vector3(-10.6, 0, 0.2),   # 原有 5 栋（离湖较远）
		Vector3(-9.0, 0, -4.2), Vector3(-8.0, 0, -1.0),    # 新增 2 栋（侵占，靠湖）
	]
	for p in house_positions:
		var house := _make_house()
		house.position = p
		parent.add_child(house)
		var reeds := _make_reed_clump()
		reeds.position = p
		reeds.visible = false
		parent.add_child(reeds)
		house_slots.append({
			"house": house, "reeds": reeds, "mats": _collect_mats(house),
		})


func _make_house() -> Node3D:
	var house := Node3D.new()
	# 墙体
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.4, 1.0, 1.1)
	wall.mesh = wm
	wall.position = Vector3(0, 0.5, 0)
	wall.material_override = _mat(Color(0.93, 0.87, 0.76))
	house.add_child(wall)
	# 屋顶（三棱柱）
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(1.7, 0.6, 1.4)
	roof.mesh = rm
	roof.position = Vector3(0, 1.3, 0)
	roof.material_override = _mat(Color(0.82, 0.60, 0.52))
	house.add_child(roof)
	# 门
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.3, 0.5, 0.05)
	door.mesh = dm
	door.position = Vector3(0, 0.25, 0.58)
	door.material_override = _mat(Color(0.60, 0.48, 0.38))
	house.add_child(door)
	return house


## 退还湿地的芦苇丛（房子拆除后的替代植被）：低矮底垫 + 几根细高秆芦苇
func _make_reed_clump() -> Node3D:
	var clump := Node3D.new()
	# 底垫：低矮泥/草地，表示田地已退为湿地
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.5, 0.12, 1.3)
	pad.mesh = pm
	pad.material_override = _mat(Color(0.58, 0.70, 0.48))
	pad.position = Vector3(0, 0.06, 0)
	clump.add_child(pad)
	# 芦苇：细高秆 + 顶部穗
	var reed_col := Color(0.62, 0.72, 0.50)
	for k in 5:
		var ang := k * 1.26
		var h := 1.5 + (k % 3) * 0.22
		var stalk := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.03
		sm.bottom_radius = 0.05
		sm.height = h
		stalk.mesh = sm
		stalk.material_override = _mat(reed_col)
		stalk.position = Vector3(cos(ang) * 0.34, 0.06 + h / 2.0, sin(ang) * 0.30)
		clump.add_child(stalk)
		var tassel := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.02
		tm.bottom_radius = 0.07
		tm.height = 0.28
		tassel.mesh = tm
		tassel.material_override = _mat(reed_col.lightened(0.28))
		tassel.position = Vector3(cos(ang) * 0.34, 0.06 + h, sin(ang) * 0.30)
		clump.add_child(tassel)
	return clump


func _collect_mats(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.material_override:
			out.append(mi.material_override)
	for c in n.get_children():
		out.append_array(_collect_mats(c))
	return out


## 水面 shader：轻微微波 + 波光
func _make_water_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 water_color : source_color = vec4(0.62, 0.80, 0.86, 0.88);
uniform float wave_speed = 0.55;
uniform float wave_strength = 0.06;

void fragment() {
	// 两层正弦叠加，形成缓慢流动的波纹
	float w1 = sin(VERTEX.x * 2.2 + TIME * wave_speed) * 0.5 + 0.5;
	float w2 = sin(VERTEX.z * 1.7 - TIME * wave_speed * 0.8) * 0.5 + 0.5;
	float ripple = (w1 * w2);
	// 波光提亮水面，产生细微的明暗流动
	vec3 col = water_color.rgb + vec3(0.10, 0.13, 0.16) * ripple * wave_strength * 16.0;
	ALBEDO = col;
	ALPHA = water_color.a;
}
"""
	return sh


## 全屏像素化后处理：把屏幕 UV 量化到 pixel_size 大小的块，形成块状像素
func _make_pixelate_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float pixel_size : hint_range(1.0, 16.0) = 3.5;
uniform sampler2D screen_texture : hint_screen_texture;

void fragment() {
	// 最近邻像素化：按块取左上角像素，整块同色
	vec2 block = SCREEN_PIXEL_SIZE * pixel_size;
	vec2 uv = floor(SCREEN_UV / block) * block;
	COLOR = texture(screen_texture, uv);
}
"""
	return sh


## 像素化图层：位于 UICanvas(layer=1) 之下，只像素化 3D，HUD/文字保持清晰
func _build_pixelate_layer() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PixelateLayer"
	layer.layer = 0  # 只像素化 3D，UI/文字保持清晰锐利
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = _make_pixelate_shader()
	rect.material = sm
	layer.add_child(rect)


## 生成棋盘网格线（生息演算式棋盘感）
func _build_grid(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var half := 18.0      # 网格半宽（覆盖 36×36）
	var step := 2.0       # 格子大小 2 米
	var y := 0.12         # 略高于地面与湖面
	var n := int(half / step)  # 每方向 9 条线（-18..18）
	for i in range(-n, n + 1):
		var c := i * step
		# 横向线（沿 X）
		st.add_vertex(Vector3(-half, y, c))
		st.add_vertex(Vector3(half, y, c))
		# 纵向线（沿 Z）
		st.add_vertex(Vector3(c, y, -half))
		st.add_vertex(Vector3(c, y, half))
	var grid_mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "GridLines"
	mi.mesh = grid_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 湿地泥滩（浅水与草洲之间的过渡带，暖褐色）
func _build_mudflats(parent: Node3D) -> void:
	var positions := [
		Vector3(-12, 0.03, 0), Vector3(12, 0.03, -2), Vector3(-3, 0.03, -12),
		Vector3(3, 0.03, 12), Vector3(-9, 0.03, 7), Vector3(9, 0.03, -8),
	]
	for p in positions:
		var mi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(4.0, 0.15, 4.0)
		mi.mesh = cm
		mi.position = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.80, 0.72, 0.60)
		mi.material_override = mat
		parent.add_child(mi)


func _process(delta: float) -> void:
	_process_birds(delta)
	_process_plants_sway()
	_update_card_hover(delta)
	# 容器尺寸变化时重排扇形（居中）
	if card_box != null and card_box.size.x > 10.0:
		if _fan_layout_size.distance_to(card_box.size) > 1.0:
			_layout_fan()


## 植物随风轻微摆动（只有挺水/乔木/草洲这类露出水面的才明显摆动）
func _process_plants_sway() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for pid in plant_views:
		var kind: String = plant_views[pid]["kind"]
		if kind == "submerged":
			continue  # 沉水植物随水波，不随风
		var amp := 0.045 if kind == "emergent" else 0.03
		var rigs: Array = plant_views[pid]["rigs"]
		for i in rigs.size():
			var rig: Node3D = rigs[i]
			if not rig.visible:
				continue
			# 各自相位错开，避免整齐划一
			var ph := i * 0.8 + rig.position.x * 0.3
			rig.rotation.z = sin(t * 1.1 + ph) * amp
			rig.rotation.x = cos(t * 0.9 + ph * 1.3) * amp * 0.6


## 鸟类状态机：站立 / 啄水 / 行走，朝向符合移动方向
func _process_birds(delta: float) -> void:
	for sid in species_views:
		var view: Dictionary = species_views[sid]
		var rigs: Array = view["rigs"]
		var bases: Array = view["bases"]
		var states: Array = view["states"]
		var timers: Array = view["timers"]
		var targets: Array = view["targets"]
		for i in rigs.size():
			var rig: Node3D = rigs[i]
			if not rig.visible:
				continue
			var base: Vector3 = bases[i]
			timers[i] -= delta
			if timers[i] <= 0.0:
				# 切换状态
				var r := randf()
				# 植被好时，更高概率找栖息地停歇（体现生态联动）
				var veg: int = GameState.metrics.get("vegetation", 50)
				var perch_chance := 0.12 + float(veg) / 100.0 * 0.25
				if r < perch_chance:
					states[i] = 3  # 停歇（飞到栖息点）
					timers[i] = 6.0 + randf() * 4.0
					targets[i] = _find_perch_point(sid, i)
				elif r < 0.45:
					states[i] = 0  # 站立
					timers[i] = 1.0 + randf() * 2.5
				elif r < 0.78:
					states[i] = 1  # 啄水
					timers[i] = 1.2 + randf() * 1.4
				else:
					states[i] = 2  # 行走
					timers[i] = 2.0 + randf() * 2.5
					var ang := randf() * TAU
					var dist := 1.6 + randf() * 3.5
					targets[i] = base + Vector3(cos(ang) * dist, 0, sin(ang) * dist)

			var st: int = states[i]
			match st:
				0:  # 站立：回正，静止
					rig.rotation.x = lerpf(rig.rotation.x, 0.0, delta * 6.0)
					rig.position.y = base.y
				1:  # 啄水：俯身低头
					rig.rotation.x = lerpf(rig.rotation.x, 0.55, delta * 8.0)
					rig.position.y = base.y
				2:  # 行走：朝目标移动，朝向移动方向
					var target: Vector3 = targets[i]
					var to_t := target - rig.position
					var flat := Vector3(to_t.x, 0, to_t.z)
					if flat.length() < 0.2:
						states[i] = 0
						timers[i] = 1.0 + randf() * 2.0
						rig.rotation.x = lerpf(rig.rotation.x, 0.0, delta * 6.0)
					else:
						var dir := flat.normalized()
						var speed := 0.9
						rig.position += dir * speed * delta
						# 朝向移动方向（喙在 +Z）
						rig.rotation.y = atan2(dir.x, dir.z)
						rig.rotation.x = lerpf(rig.rotation.x, 0.0, delta * 6.0)
						# 走路轻微颠簸
						rig.position.y = base.y + abs(sin(Time.get_ticks_msec() * 0.012 + i * 1.7)) * 0.05
				3:  # 停歇：飞向栖息点并在其上停留
					var perch: Vector3 = targets[i]
					var to_p := perch - rig.position
					if to_p.length() < 0.25:
						# 已到栖息点：停在上面（可轻微起伏，像站在枝头）
						rig.position = perch
						rig.rotation.x = lerpf(rig.rotation.x, 0.0, delta * 5.0)
						rig.position.y = perch.y + sin(Time.get_ticks_msec() * 0.004 + i) * 0.03
					else:
						# 飞行：抬升 + 朝目标（速度较快，确保能飞到栖息点）
						var fdir := to_p.normalized()
						rig.position += fdir * 4.5 * delta
						rig.rotation.y = atan2(fdir.x, fdir.z)
						# 飞行时前倾
						rig.rotation.x = lerpf(rig.rotation.x, -0.25, delta * 5.0)


## 为每个物种生成一组会动的个体（最多 10 个/物种），用多几何体拼出可辨识剪影
func _build_species_views(parent: Node3D) -> void:
	for sid in GameState.SPECIES:
		var rigs: Array = []
		var bases: Array = []
		var states: Array = []
		var timers: Array = []
		var targets: Array = []
		for i in 10:
			var rig := Node3D.new()  # 一个物种个体 = 一组几何体
			rig.name = sid
			_build_bird_body(rig, sid)
			rig.visible = false
			parent.add_child(rig)
			rigs.append(rig)
			var base := Vector3(
				(-7 + i * 1.5) + (sid.length() % 3) * 2.0,
				0.0,
				-5 + (i % 4) * 3.0
			)
			bases.append(base)
			states.append(0)
			timers.append(1.0 + (i % 5) * 0.6)
			targets.append(base)
		species_views[sid] = {
			"rigs": rigs, "bases": bases,
			"states": states, "timers": timers, "targets": targets,
		}


## 用几何体拼出鸟类剪影（可辨识）
func _build_bird_body(rig: Node3D, sid: String) -> void:
	var white := Color(0.96, 0.96, 0.94)
	var dark := Color(0.35, 0.35, 0.40)
	var grey := Color(0.78, 0.78, 0.74)
	var red := Color(0.85, 0.45, 0.42)
	var yellow := Color(0.95, 0.85, 0.55)
	var brown := Color(0.72, 0.62, 0.50)

	# 躯干（椭球）
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.28
	bm.height = 0.6
	body.mesh = bm
	body.scale = Vector3(0.8, 0.9, 1.3)
	body.position = Vector3(0, 0.85, 0)
	rig.add_child(body)

	# 头
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	hm.height = 0.34
	head.mesh = hm
	head.position = Vector3(0, 1.35, 0.15)
	rig.add_child(head)

	# 长颈（圆柱，连接头与躯干）
	var neck := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.06
	nm.bottom_radius = 0.08
	nm.height = 0.55
	neck.mesh = nm
	neck.position = Vector3(0, 1.08, 0.05)
	rig.add_child(neck)

	# 长腿（两根细圆柱）
	for side in [-1, 1]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.02
		lm.bottom_radius = 0.02
		lm.height = 0.55
		leg.mesh = lm
		leg.position = Vector3(side * 0.12, 0.35, 0.0)
		rig.add_child(leg)

	# 喙
	var beak := MeshInstance3D.new()
	var bkm := CylinderMesh.new()
	bkm.top_radius = 0.015
	bkm.bottom_radius = 0.03
	bkm.height = 0.2
	beak.mesh = bkm
	beak.rotation_degrees = Vector3(90, 0, 0)
	beak.position = Vector3(0, 1.38, 0.32)
	rig.add_child(beak)

	# 按物种上色与特殊特征
	match sid:
		"baihe":
			body.material_override = _mat(white)
			head.material_override = _mat(white)
			neck.material_override = _mat(white)
			beak.material_override = _mat(yellow)
			# 红色裸区（头顶）
			var crown := MeshInstance3D.new()
			var crm := SphereMesh.new()
			crm.radius = 0.07
			crm.height = 0.15
			crown.mesh = crm
			crown.material_override = _mat(red)
			crown.position = Vector3(0, 1.42, 0.15)
			rig.add_child(crown)
			# 黑色翅尖
			var wing := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.5, 0.08, 0.3)
			wing.mesh = wm
			wing.material_override = _mat(dark)
			wing.position = Vector3(0, 0.9, -0.35)
			rig.add_child(wing)
		"dongfangbaihuan":
			body.material_override = _mat(white)
			head.material_override = _mat(white)
			neck.material_override = _mat(white)
			beak.material_override = _mat(dark)
			# 黑色大翅
			var dwing := MeshInstance3D.new()
			var dwm := BoxMesh.new()
			dwm.size = Vector3(0.6, 0.1, 0.5)
			dwing.mesh = dwm
			dwing.material_override = _mat(dark)
			dwing.position = Vector3(0, 0.9, -0.45)
			rig.add_child(dwing)
		"xiaotiane":
			body.material_override = _mat(white)
			head.material_override = _mat(white)
			neck.material_override = _mat(white)
			beak.material_override = _mat(yellow)
		"baizhenhe":
			body.material_override = _mat(grey)
			head.material_override = _mat(grey)
			neck.material_override = _mat(grey)
			beak.material_override = _mat(yellow)
			# 红色脸
			var face := MeshInstance3D.new()
			var fsm := SphereMesh.new()
			fsm.radius = 0.08
			fsm.height = 0.16
			face.mesh = fsm
			face.material_override = _mat(red)
			face.position = Vector3(0, 1.36, 0.22)
			rig.add_child(face)
		"yanlei":
			body.material_override = _mat(brown)
			head.material_override = _mat(brown)
			neck.material_override = _mat(brown)
			beak.material_override = _mat(yellow)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _update_species_views() -> void:
	for sid in GameState.SPECIES:
		var pop: int = GameState.species_pop.get(sid, 0)
		var count: int = int(pop / 10.0)  # 0-100 → 0-10 个
		var view: Dictionary = species_views[sid]
		var rigs: Array = view["rigs"]
		for i in rigs.size():
			var rig: Node3D = rigs[i]
			var should_show := i < count
			if should_show and not rig.visible:
				# 新出现的个体：弹性放大登场（TRANS_BACK，有"冒出来"的弹性感）
				rig.visible = true
				rig.scale = Vector3(0.01, 0.01, 0.01)
				var tw := rig.create_tween()
				tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(rig, "scale", Vector3.ONE, 0.4)
			elif should_show and rig.scale.x < 1.0:
				# 正在退场又需要显示：立即恢复
				rig.scale = Vector3.ONE
			elif not should_show and rig.visible:
				# 消失的个体：缩小淡出后隐藏（不打断正在进行的退场动画）
				if rig.scale.x < 0.9:
					continue
				var tw2 := rig.create_tween()
				tw2.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				tw2.tween_property(rig, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
				tw2.tween_callback(func() -> void: rig.visible = false)


## 为每种植物生成一组个体（组合模型：根 Node3D + 多个几何体）
func _build_plant_views(parent: Node3D) -> void:
	for pid in GameState.PLANTS:
		var rigs: Array = []
		var kind: String = GameState.PLANTS[pid]["kind"]
		for i in 14:
			var rig := Node3D.new()
			rig.visible = false
			_build_plant_model(rig, pid, kind)
			parent.add_child(rig)
			rigs.append(rig)
		plant_views[pid] = {"rigs": rigs, "kind": kind}


## 构建植物组合模型（比单几何体更有辨识度）
func _build_plant_model(rig: Node3D, pid: String, kind: String) -> void:
	var c: Color = GameState.PLANTS[pid]["color"]
	match kind:
		"submerged":
			# 苦草：水下丛生的带状叶片
			for k in 5:
				var leaf := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(0.08, 0.7, 0.18)
				leaf.mesh = lm
				leaf.material_override = _mat(c)
				leaf.position = Vector3((k - 2) * 0.11, 0.35, (k % 2) * 0.08)
				leaf.rotation.z = (k - 2) * 0.12
				rig.add_child(leaf)
		"floating":
			# 莲：圆形浮叶 + 花
			for k in 3:
				var pad := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.32
				pm.bottom_radius = 0.32
				pm.height = 0.04
				pad.mesh = pm
				pad.material_override = _mat(c)
				pad.position = Vector3((k - 1) * 0.42, 0.06, (k % 2) * 0.3)
				rig.add_child(pad)
			var flower := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.09
			fm.height = 0.18
			flower.mesh = fm
			flower.material_override = _mat(Color(0.94, 0.80, 0.86))
			flower.position = Vector3(0, 0.22, 0)
			rig.add_child(flower)
		"emergent":
			# 芦苇：多根细高秆 + 顶部穗
			for k in 4:
				var stalk := MeshInstance3D.new()
				var sm := CylinderMesh.new()
				sm.top_radius = 0.03
				sm.bottom_radius = 0.045
				sm.height = 1.9 + (k % 3) * 0.25
				stalk.mesh = sm
				stalk.material_override = _mat(c)
				stalk.position = Vector3((k - 1.5) * 0.16, (1.9 + (k % 3) * 0.25) / 2.0, (k % 2) * 0.12)
				rig.add_child(stalk)
				var tassel := MeshInstance3D.new()
				var tm := CylinderMesh.new()
				tm.top_radius = 0.02
				tm.bottom_radius = 0.07
				tm.height = 0.32
				tassel.mesh = tm
				tassel.material_override = _mat(c.lightened(0.28))
				tassel.position = Vector3((k - 1.5) * 0.16, 1.9 + (k % 3) * 0.25, (k % 2) * 0.12)
				rig.add_child(tassel)
		"tree":
			# 池杉：树干 + 三层锥形树冠
			var trunk := MeshInstance3D.new()
			var trm := CylinderMesh.new()
			trm.top_radius = 0.09
			trm.bottom_radius = 0.16
			trm.height = 1.6
			trunk.mesh = trm
			trunk.material_override = _mat(Color(0.55, 0.45, 0.36))
			trunk.position = Vector3(0, 0.8, 0)
			rig.add_child(trunk)
			for layer in 3:
				var canopy := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				var r := 0.85 - layer * 0.22
				cm.top_radius = 0.02
				cm.bottom_radius = r
				cm.height = 0.75
				canopy.mesh = cm
				canopy.material_override = _mat(c.lightened(layer * 0.08))
				canopy.position = Vector3(0, 1.5 + layer * 0.55, 0)
				rig.add_child(canopy)
		_:  # marsh 草洲
			# 草丛：一簇小锥
			for k in 6:
				var blade := MeshInstance3D.new()
				var bm := CylinderMesh.new()
				bm.top_radius = 0.01
				bm.bottom_radius = 0.07
				bm.height = 0.45 + (k % 3) * 0.15
				blade.mesh = bm
				blade.material_override = _mat(c.lightened((k % 3) * 0.06))
				var ang := k * 1.05
				blade.position = Vector3(cos(ang) * 0.14, (0.45 + (k % 3) * 0.15) / 2.0, sin(ang) * 0.14)
				blade.rotation.z = cos(ang) * 0.22
				blade.rotation.x = sin(ang) * 0.22
				rig.add_child(blade)


func _update_plant_views() -> void:
	_ensure_plant_positions()
	for pid in GameState.PLANTS:
		var pop: int = GameState.plant_pop.get(pid, 0)
		var count: int = int(pop / 7.0)  # 0-100 → 0-14
		var view: Dictionary = plant_views[pid]
		var rigs: Array = view["rigs"]
		var kind: String = view["kind"]
		for i in rigs.size():
			var rig: Node3D = rigs[i]
			var should_show := i < count
			if should_show and not rig.visible:
				# 生长动画：从地面纵向"长出来"（高度 0→1 + 轻微过冲）
				rig.visible = true
				rig.position = _plant_position(pid, kind, i)
				rig.scale = Vector3(1.0, 0.01, 1.0)
				var tw := rig.create_tween()
				tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(rig, "scale", Vector3.ONE, 0.55).set_delay(i * 0.03)
			elif should_show:
				# 已在显示：确保缩放正确（防止动画被打断后残留小尺寸）
				if rig.scale.y < 0.95:
					rig.scale = Vector3.ONE
					rig.position = _plant_position(pid, kind, i)
			elif not should_show and rig.visible:
				# 消退：纵向缩回地面
				var tw2 := rig.create_tween()
				tw2.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				tw2.tween_property(rig, "scale", Vector3(1.0, 0.01, 1.0), 0.3)
				tw2.tween_callback(func() -> void: rig.visible = false)


func _plant_position(pid: String, _kind: String, i: int) -> Vector3:
	var pts: Array = plant_positions.get(pid, [])
	if i < pts.size():
		return pts[i]
	return Vector3.ZERO


## 每局按种子随机散落植物位置：打破原来的成排成条网格，改为自然散布
func _ensure_plant_positions() -> void:
	if _plant_pos_seed == GameState.run_seed:
		return
	_plant_pos_seed = GameState.run_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.run_seed
	for pid in GameState.PLANTS:
		var kind: String = GameState.PLANTS[pid]["kind"]
		var pts: Array = []
		for i in 14:
			pts.append(_scatter_plant(kind, pts, rng))
		plant_positions[pid] = pts


## 在各自生境区域内随机取点，同类之间保持最小间距，避免叠成一团
func _scatter_plant(kind: String, placed: Array, rng: RandomNumberGenerator) -> Vector3:
	for attempt in 40:
		var p := _plant_zone_point(kind, rng)
		var ok := true
		for q in placed:
			if p.distance_to(q) < 1.4:
				ok = false
				break
		if ok:
			return p
	return _plant_zone_point(kind, rng)


## 各植物的生境区域（沿用原分布范围，仅把固定网格改为随机取点）
func _plant_zone_point(kind: String, rng: RandomNumberGenerator) -> Vector3:
	match kind:
		"submerged":  # 苦草：水下浅水区
			return Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-2.0, 3.0))
		"floating":   # 莲/荷叶：开阔水面
			return Vector3(rng.randf_range(2.0, 12.0), 0.06, rng.randf_range(-4.0, 1.0))
		"emergent":   # 芦苇：岸边浅滩
			return Vector3(rng.randf_range(-9.0, 6.6), 0.5, rng.randf_range(3.0, 5.5))
		"tree":       # 乔木：岸线 / 草洲外围
			return Vector3(rng.randf_range(-13.0, 11.0), 0.0, rng.randf_range(-12.0, -6.8))
		_:            # 草洲
			return Vector3(rng.randf_range(-8.0, 6.4), 0.05, rng.randf_range(5.0, 7.4))


func _update_3d() -> void:
	var m: Dictionary = GameState.metrics
	var wscale := lerpf(0.55, 1.35, float(m["water_level"]) / 100.0)
	lake_mesh.scale = Vector3(wscale, 1.0, wscale)
	lake_color = Color(0.58, 0.74 + 0.12 * (float(m["water_level"]) / 100.0), 0.88, 0.88)
	lake_mat.set_shader_parameter("water_color", lake_color)

	for i in grass_nodes.size():
		var v := float(m["vegetation"]) / 100.0
		grass_mats[i].albedo_color = Color(0.72 - 0.20 * v, 0.66 + 0.12 * v, 0.55 - 0.05 * v)
		grass_nodes[i].visible = m["vegetation"] > (10 + i * 8)

	var nfish := int(m["fish"] / 12.0)
	for i in fish_nodes.size():
		fish_nodes[i].visible = i < nfish

	# 人工浮岛：数量随 floating_islands 状态
	for i in island_nodes.size():
		island_nodes[i].visible = i < GameState.floating_islands

	# 物种个体数量随物种种群增减
	_update_species_views()

	# 植物数量随植被指标增减
	_update_plant_views()

	# 环湖房子：settlement 决定数量（退田还湿减少、围湖造田增多），拆除处变芦苇
	var active := clampi(roundi(GameState.settlement / 100.0 * 7.0), 0, 7)
	# 社区信任：暖色亮灯的房子数量随信任度变化
	var lit := roundi(float(m["community"]) / 100.0 * active)
	for i in house_slots.size():
		var slot: Dictionary = house_slots[i]
		var is_house: bool = i < active
		slot["house"].visible = is_house
		slot["reeds"].visible = not is_house
		if is_house:
			var warm := 1.0 if i < lit else 0.45
			for mat in slot["mats"]:
				mat.albedo_color = Color(
					0.72 + 0.21 * warm,
					0.66 + 0.21 * warm,
					0.56 + 0.20 * warm
				)


# ==================== UI ====================
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UICanvas"
	add_child(canvas)

	# --- 左侧：时间 / 金钱 / 事件（收窄为竖条，把沙盘让出来）---
	left_panel = PanelContainer.new()
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 0.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_bottom = 0.0
	left_panel.offset_left = 6
	left_panel.offset_right = 210
	left_panel.offset_top = 6
	left_panel.offset_bottom = 190
	_panel_style(left_panel, Color(0.20, 0.14, 0.09, 0.60))
	canvas.add_child(left_panel)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_panel.add_child(lv)

	var title := _make_label("拯救鄱阳湖", 20, Color(1, 0.9, 0.55))
	lv.add_child(title)

	turn_label = _make_label("第 1 / 16 回合", 17, Color(1, 1, 1))
	lv.add_child(turn_label)
	season_label = _make_label("第 1 年 · 春", 14, Color(0.82, 0.86, 0.9))
	lv.add_child(season_label)

	var sep1 := HSeparator.new()
	lv.add_child(sep1)

	var spent_row := HBoxContainer.new()
	spent_row.add_theme_constant_override("separation", 6)
	spent_row.add_child(_make_icon(_icon_grid_for("coin"), Color(0.72, 0.62, 0.50), 14))
	spent_label = _make_label("已消耗：0 万", 12, Color(0.82, 0.86, 0.9))
	spent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spent_row.add_child(spent_label)
	lv.add_child(spent_row)

	var funds_row := HBoxContainer.new()
	funds_row.add_theme_constant_override("separation", 6)
	funds_row.add_child(_make_icon(_icon_grid_for("coin"), Color(0.95, 0.78, 0.25), 18))
	funds_label = _make_label("80 万", 17, Color(1, 0.95, 0.6))
	funds_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	funds_row.add_child(funds_label)
	lv.add_child(funds_row)

	var research_row := HBoxContainer.new()
	research_row.add_theme_constant_override("separation", 6)
	research_row.add_child(_make_icon(_icon_grid_for("research"), Color(0.82, 0.9, 1), 14))
	research_label = _make_label("科研点：0", 14, Color(0.82, 0.9, 1))
	research_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	research_row.add_child(research_label)
	lv.add_child(research_row)

	# --- 右侧：六项指标（收窄为竖条）---
	right_panel = PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 0.0
	right_panel.offset_left = -190
	right_panel.offset_right = -6
	right_panel.offset_top = 6
	right_panel.offset_bottom = 266
	_panel_style(right_panel, Color(0.20, 0.14, 0.09, 0.60))
	canvas.add_child(right_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_panel.add_child(rv)
	var r_title := _make_label("生态指标", 16, Color(0.85, 0.92, 1))
	rv.add_child(r_title)
	for metric in GameState.METRIC_NAMES:
		rv.add_child(_make_metric_row(metric))

	# --- 顶部事件横幅（单行、居中、不遮挡沙盘）---
	event_label = _make_label("暂无", 13, Color(0.95, 0.95, 0.92))
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.clip_text = true
	event_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	event_label.anchor_left = 0.0
	event_label.anchor_top = 0.0
	event_label.anchor_right = 1.0
	event_label.offset_left = 220
	event_label.offset_right = -220
	event_label.offset_top = 4
	event_label.offset_bottom = 30
	event_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.06, 0.8))
	event_label.add_theme_constant_override("outline_size", 5)
	canvas.add_child(event_label)

	# --- 底部中间：手牌（无背景框，卡牌直接浮在沙盘上）---
	hand_panel = PanelContainer.new()
	hand_panel.anchor_left = 0.5
	hand_panel.anchor_top = 1.0
	hand_panel.anchor_right = 0.5
	hand_panel.anchor_bottom = 1.0
	hand_panel.offset_left = -330
	hand_panel.offset_right = 330
	hand_panel.offset_top = -290
	hand_panel.offset_bottom = -4
	# 透明无边框：手牌区域不遮挡沙盘
	var empty_sb := StyleBoxEmpty.new()
	hand_panel.add_theme_stylebox_override("panel", empty_sb)
	hand_panel.visible = false
	canvas.add_child(hand_panel)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hand_panel.add_child(hv)

	# 牌区（扇形手牌，手动定位，无背景）
	card_box = Control.new()
	card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_box.custom_minimum_size = Vector2(0, 200)
	card_box.mouse_filter = Control.MOUSE_FILTER_PASS
	card_box.resized.connect(_on_card_box_resized)
	hv.add_child(card_box)

	# 右下角：行动次数提醒（缩短）+ 结束回合按钮（沙盘素材之外的空白角落）
	bottom_right = VBoxContainer.new()
	bottom_right.anchor_left = 1.0
	bottom_right.anchor_top = 1.0
	bottom_right.anchor_right = 1.0
	bottom_right.anchor_bottom = 1.0
	bottom_right.offset_left = -180
	bottom_right.offset_right = -14
	bottom_right.offset_top = -104
	bottom_right.offset_bottom = -14
	bottom_right.add_theme_constant_override("separation", 4)
	bottom_right.visible = false
	canvas.add_child(bottom_right)

	selected_label = _make_label("已选：0/3", 14, Color(1, 0.9, 0.5))
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.06, 0.8))
	selected_label.add_theme_constant_override("outline_size", 4)
	bottom_right.add_child(selected_label)

	var action_hint := _make_label("每回合最多 3 个行动", 12, Color(0.92, 0.94, 0.96))
	action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.06, 0.8))
	action_hint.add_theme_constant_override("outline_size", 4)
	bottom_right.add_child(action_hint)

	end_turn_btn = _make_button("结束本回合 ▶", _finish_turn, 20)
	end_turn_btn.custom_minimum_size = Vector2(166, 48)
	bottom_right.add_child(end_turn_btn)

	# --- 弹窗（顶层）---
	popup_root = Control.new()
	popup_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.visible = false
	canvas.add_child(popup_root)

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.10)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_root.add_child(dim)

	popup_center = CenterContainer.new()
	popup_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_center.mouse_filter = Control.MOUSE_FILTER_PASS
	popup_root.add_child(popup_center)

	popup_panel = PanelContainer.new()
	popup_panel.custom_minimum_size = Vector2(600, 0)
	_panel_style(popup_panel, Color(0.24, 0.17, 0.11, 0.55))
	popup_center.add_child(popup_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	popup_panel.add_child(pv)
	popup_title = _make_label("", 22, Color(1, 0.9, 0.55))
	pv.add_child(popup_title)
	popup_body = RichTextLabel.new()
	popup_body.bbcode_enabled = true
	popup_body.fit_content = true
	popup_body.custom_minimum_size = Vector2(540, 0)
	popup_body.add_theme_font_size_override("normal_font_size", _snap_px(16))
	popup_body.add_theme_color_override("default_color", Color(0.95, 0.95, 0.95))
	pv.add_child(popup_body)
	popup_button = _make_button("继续", _on_popup_button, 18)
	popup_button.custom_minimum_size = Vector2(0, 44)
	pv.add_child(popup_button)

	# 主菜单（独立 CanvasLayer，盖在 HUD 与沙盘之上）
	_build_menu()


# ==================== 主菜单 ====================
func _build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MenuLayer"
	layer.layer = 10  # 确保在 HUD 之上
	add_child(layer)

	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(menu_root)

	# 半透明暗色底：既挡住 HUD，又隐约露出背后的沙盘
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.05, 0.80)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)

	# --- 第 1 页：标题 / 开始游戏 ---
	menu_title_panel = PanelContainer.new()
	menu_title_panel.custom_minimum_size = Vector2(420, 0)
	_panel_style(menu_title_panel, Color(0.20, 0.14, 0.09, 0.97))
	center.add_child(menu_title_panel)

	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 16)
	menu_title_panel.add_child(tvb)

	var title := _make_label("拯救鄱阳湖", 36, Color(1, 0.9, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tvb.add_child(title)

	var sub := _make_label("生态修复 · 回合制沙盘", 14, Color(0.82, 0.86, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tvb.add_child(sub)

	var title_start := _make_button("开始游戏", _on_title_start, 20)
	title_start.custom_minimum_size = Vector2(0, 52)
	tvb.add_child(title_start)

	var talent_btn := _make_button("天赋树", _show_talent_panel, 16)
	talent_btn.custom_minimum_size = Vector2(0, 40)
	tvb.add_child(talent_btn)

	# --- 第 2 页：选择难度 ---
	menu_difficulty_panel = PanelContainer.new()
	menu_difficulty_panel.custom_minimum_size = Vector2(420, 0)
	_panel_style(menu_difficulty_panel, Color(0.20, 0.14, 0.09, 0.97))
	menu_difficulty_panel.visible = false
	center.add_child(menu_difficulty_panel)

	var dvb := VBoxContainer.new()
	dvb.add_theme_constant_override("separation", 14)
	menu_difficulty_panel.add_child(dvb)

	var d_title := _make_label("选择难度", 24, Color(1, 0.9, 0.55))
	d_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dvb.add_child(d_title)

	var normal_btn := _make_button("简单模式", _on_difficulty_normal, 18)
	normal_btn.custom_minimum_size = Vector2(0, 48)
	dvb.add_child(normal_btn)

	var hard_btn := _make_button("困难模式", _on_difficulty_hard, 18)
	hard_btn.custom_minimum_size = Vector2(0, 48)
	dvb.add_child(hard_btn)

	var d_back := _make_button("返回", _on_difficulty_back, 16)
	d_back.custom_minimum_size = Vector2(0, 40)
	dvb.add_child(d_back)

	# --- 第 3 页：自定义种子 ---
	menu_seed_panel = PanelContainer.new()
	menu_seed_panel.custom_minimum_size = Vector2(420, 0)
	_panel_style(menu_seed_panel, Color(0.20, 0.14, 0.09, 0.97))
	menu_seed_panel.visible = false
	center.add_child(menu_seed_panel)

	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 14)
	menu_seed_panel.add_child(svb)

	var seed_title := _make_label("自定义种子", 24, Color(1, 0.9, 0.55))
	seed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svb.add_child(seed_title)

	menu_mode_label = _make_label("模式：简单", 12, Color(0.82, 0.86, 0.9))
	menu_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svb.add_child(menu_mode_label)

	var seed_l := _make_label("留空或 0 则随机", 14, Color(0.9, 0.92, 0.94))
	seed_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svb.add_child(seed_l)

	seed_input = LineEdit.new()
	seed_input.placeholder_text = "输入数字种子，例如 20260925"
	seed_input.add_theme_font_size_override("font_size", _snap_px(18))
	seed_input.custom_minimum_size = Vector2(0, 42)
	svb.add_child(seed_input)

	menu_hint = _make_label("", 12, Color(1, 0.6, 0.5))
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svb.add_child(menu_hint)

	var seed_start := _make_button("开始游戏", _on_start_pressed, 20)
	seed_start.custom_minimum_size = Vector2(0, 48)
	svb.add_child(seed_start)

	var back_btn := _make_button("返回", _on_seed_back, 16)
	back_btn.custom_minimum_size = Vector2(0, 40)
	svb.add_child(back_btn)

	# --- 第 4 页：天赋树 ---
	menu_talent_panel = PanelContainer.new()
	menu_talent_panel.custom_minimum_size = Vector2(480, 0)
	_panel_style(menu_talent_panel, Color(0.20, 0.14, 0.09, 0.97))
	menu_talent_panel.visible = false
	center.add_child(menu_talent_panel)

	var kvb := VBoxContainer.new()
	kvb.add_theme_constant_override("separation", 10)
	menu_talent_panel.add_child(kvb)

	var t_title := _make_label("天赋树", 24, Color(1, 0.9, 0.55))
	t_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kvb.add_child(t_title)

	talent_points_label = _make_label("天赋点：0", 14, Color(1, 0.95, 0.6))
	talent_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kvb.add_child(talent_points_label)

	var t_sep := HSeparator.new()
	kvb.add_child(t_sep)

	talent_list = VBoxContainer.new()
	talent_list.add_theme_constant_override("separation", 6)
	kvb.add_child(talent_list)

	talent_unlock_btn = _make_button("点亮下一个天赋", _on_talent_unlock, 16)
	talent_unlock_btn.custom_minimum_size = Vector2(0, 44)
	kvb.add_child(talent_unlock_btn)

	var t_back := _make_button("返回", _on_talent_back, 16)
	t_back.custom_minimum_size = Vector2(0, 40)
	kvb.add_child(t_back)


func _show_menu() -> void:
	menu_root.visible = true
	menu_hint.text = ""
	menu_title_panel.visible = true
	menu_difficulty_panel.visible = false
	menu_seed_panel.visible = false
	menu_talent_panel.visible = false


func _on_title_start() -> void:
	menu_title_panel.visible = false
	menu_difficulty_panel.visible = true
	menu_seed_panel.visible = false
	menu_hint.text = ""


func _on_difficulty_normal() -> void:
	GameState.hard_mode = false
	menu_mode_label.text = "模式：简单"
	menu_difficulty_panel.visible = false
	menu_seed_panel.visible = true
	menu_hint.text = ""
	if seed_input != null:
		seed_input.grab_focus()


func _on_difficulty_hard() -> void:
	GameState.hard_mode = true
	menu_mode_label.text = "模式：困难"
	menu_difficulty_panel.visible = false
	menu_seed_panel.visible = true
	menu_hint.text = ""
	if seed_input != null:
		seed_input.grab_focus()


func _on_difficulty_back() -> void:
	menu_difficulty_panel.visible = false
	menu_title_panel.visible = true
	menu_hint.text = ""


func _on_seed_back() -> void:
	menu_hint.text = ""
	menu_seed_panel.visible = false
	menu_difficulty_panel.visible = true


func _show_talent_panel() -> void:
	menu_title_panel.visible = false
	menu_difficulty_panel.visible = false
	menu_seed_panel.visible = false
	menu_talent_panel.visible = true
	_refresh_talent_panel()


func _on_talent_back() -> void:
	menu_talent_panel.visible = false
	menu_title_panel.visible = true


func _on_talent_unlock() -> void:
	Talents.unlock_next()
	_refresh_talent_panel()


## 重建天赋列表 + 刷新点数与按钮状态
func _refresh_talent_panel() -> void:
	for c in talent_list.get_children():
		talent_list.remove_child(c)
		c.queue_free()
	talent_points_label.text = "天赋点：%d" % Talents.points
	for t in Talents.TALENTS:
		var lit := Talents.has(t["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := _make_label(t["name"], 14, Color(1, 0.95, 0.6) if lit else Color(0.6, 0.6, 0.6))
		name_l.custom_minimum_size = Vector2(80, 0)
		row.add_child(name_l)
		var desc_l := _make_label(t["desc"], 12, Color(0.82, 0.86, 0.9) if lit else Color(0.55, 0.58, 0.6))
		desc_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc_l)
		var status_l := _make_label("已点亮" if lit else "未点亮", 12, Color(0.55, 0.9, 0.55) if lit else Color(0.55, 0.55, 0.55))
		row.add_child(status_l)
		talent_list.add_child(row)
	talent_unlock_btn.disabled = not (Talents.points >= 1 and Talents.next_talent_id() != "")


func _hide_menu() -> void:
	menu_root.visible = false


func _on_start_pressed() -> void:
	var s := seed_input.text.strip_edges()
	if s == "" or s == "0":
		GameState.run_seed = 0
	elif s.is_valid_int() and int(s) >= 0:
		GameState.run_seed = int(s)
	else:
		menu_hint.text = "种子需为非负整数（留空则随机）"
		return
	_hide_menu()
	GameState.reset_game()
	_update_hud()
	_update_3d()


func _make_metric_row(metric: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	vb.add_child(head)
	head.add_child(_make_icon(_icon_grid_for(metric), METRIC_COLORS[metric], 14))
	head.add_child(_make_label(GameState.METRIC_NAMES[metric], 12, Color(0.95, 0.95, 0.95)))
	var val := _make_label("0", 12, METRIC_COLORS[metric])
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(val)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 11)
	bar.modulate = METRIC_COLORS[metric]
	vb.add_child(bar)

	metric_bars[metric] = {"bar": bar, "val": val}
	return vb


func _update_hud() -> void:
	var m: Dictionary = GameState.metrics
	for metric in metric_bars:
		var bar: ProgressBar = metric_bars[metric]["bar"]
		var val: Label = metric_bars[metric]["val"]
		# 指标变化不是玩家直接操作 → 用动画"告知"变化（速查表：非用户触发可较长时长）
		var tw := bar.create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(bar, "value", float(m[metric]), 0.35)
		val.text = str(m[metric])

	var t: int = GameState.turn
	turn_label.text = "第 %d / %d 回合" % [t, GameState.TOTAL_TURNS]
	var year: int = int((t - 1) / 4) + 1
	var season: String = SEASONS[(t - 1) % 4]
	season_label.text = "第 %d 年 · %s" % [year, season]
	spent_label.text = "已消耗：%d 万" % GameState.total_spent
	funds_label.text = "%d 万" % GameState.funds
	research_label.text = "科研点：%d" % GameState.research_points
	event_label.text = _current_event if _current_event != "" else "暂无"
	_update_selected_label()


# ==================== 事件 / 结算 / 知识卡 / 报告 ====================
func _on_event(text: String) -> void:
	_current_event = text
	_update_hud()
	hand_panel.visible = false
	bottom_right.visible = false
	_show_popup("第 %d 回合 · 事件" % GameState.turn, text, "开始分配资金", _enter_allocate)


func _enter_allocate() -> void:
	_slide_side_panels(false)  # 新回合开始，侧边栏弹回
	current_hand = GameState.draw_cards(7 + int(Talents.get_bonus("cards")))
	play_deal_anim = true
	_build_hand_panel()
	hand_panel.visible = true
	bottom_right.visible = true


func _build_hand_panel() -> void:
	for c in card_box.get_children():
		c.queue_free()
	card_infos = []
	for card in current_hand:
		var panel := _make_card(card)
		card_box.add_child(panel)
		card_infos.append({
			"panel": panel, "card_id": card["id"],
			"base_pos": Vector2.ZERO, "theta": 0.0, "radial": Vector2.UP,
			"selected": false, "shaking": false, "hovered": false,
		})
	_layout_fan.call_deferred()
	_update_hud()


## 扇形摆放手牌：圆心在下方，牌绕圆心径向排列（牌底小弧、牌顶大弧）
func _layout_fan() -> void:
	var n := card_infos.size()
	if n == 0:
		return
	var card_w := 122.0
	var card_h := 165.0
	var area_size := card_box.size
	if area_size.x < 10.0:
		area_size.x = 528.0

	var step_dist := 66.0                      # 相邻牌在弧上的间距（越小重叠越多）
	var delta_theta := deg_to_rad(8.5)
	var radius: float = step_dist / delta_theta
	var total_span := delta_theta * float(n - 1)

	# 第一遍：以「圆心在原点」计算每张牌的角度与轴心点
	var pivots: Array = []
	var thetas: Array = []
	for i in n:
		var theta := -total_span / 2.0 + delta_theta * float(i)
		pivots.append(Vector2(sin(theta), -cos(theta)) * radius)
		thetas.append(theta)
		var panel: PanelContainer = card_infos[i]["panel"]
		panel.size = Vector2(card_w, card_h)
		panel.custom_minimum_size = Vector2(card_w, card_h)
		panel.pivot_offset = Vector2(card_w / 2.0, card_h)
		panel.rotation = theta

	# 第二遍：算出旋转后整体的真实包围盒（不依赖手算常数）
	var corners := [
		Vector2(-card_w / 2.0, -card_h), Vector2(card_w / 2.0, -card_h),
		Vector2(card_w / 2.0, 0.0), Vector2(-card_w / 2.0, 0.0),
	]
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for i in n:
		for c in corners:
			var p: Vector2 = pivots[i] + c.rotated(thetas[i])
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)

	# 第三遍：整体平移 —— 水平居中于容器，底部贴边（留下上方空间供悬停弹起）
	var bottom_margin := 4.0
	var dx: float = area_size.x / 2.0 - (min_x + max_x) / 2.0
	var dy: float = (area_size.y - bottom_margin) - max_y
	for i in n:
		var panel: PanelContainer = card_infos[i]["panel"]
		panel.position = pivots[i] + Vector2(dx, dy) - panel.pivot_offset
		card_infos[i]["base_pos"] = panel.position
		card_infos[i]["theta"] = thetas[i]
		card_infos[i]["radial"] = Vector2(sin(thetas[i]), -cos(thetas[i]))
	_fan_layout_size = area_size
	# 发牌入场动画（从下方滑入 + 逐张错开）
	if play_deal_anim:
		play_deal_anim = false
		_play_deal_animation()


## 发牌入场：牌从下方滑入，逐张错开（EASE_OUT，玩家等待中的入场用稍长时长）
func _play_deal_animation() -> void:
	for i in card_infos.size():
		var info: Dictionary = card_infos[i]
		var panel: PanelContainer = info["panel"]
		var target: Vector2 = info["base_pos"]
		panel.position = target + Vector2(0, 90.0)
		panel.modulate.a = 0.0
		var tw := panel.create_tween()
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "position", target, 0.34).set_delay(i * 0.045)
		tw.tween_property(panel, "modulate:a", 1.0, 0.22).set_delay(i * 0.045)


## 容器尺寸变化时重排（确保扇形始终居中）
func _on_card_box_resized() -> void:
	if not card_infos.is_empty():
		_layout_fan()


func _make_card(card: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(122, 165)
	panel.size = Vector2(122, 165)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel_style(panel, Color(0.30, 0.22, 0.14, 0.98))
	panel.tooltip_text = "%s\n\n%s" % [card["desc"], _effect_text(card)]
	panel.gui_input.connect(_on_card_gui_input.bind(panel))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)

	var name_l := _make_label(card["name"], 15, Color(1, 1, 1))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_l)

	var cat: String = card["category"]
	var cat_l := _make_label(CATEGORY_NAMES[cat], 11, CATEGORY_COLORS[cat])
	cat_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cat_l)

	var cost_l := _make_label("%d 万" % card["cost"], 16, Color(1, 0.9, 0.55))
	cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cost_l)

	return panel


## 由卡 id 取中文名
func _card_name(card_id: String) -> String:
	for c in GameState.ACTION_CARDS:
		if c["id"] == card_id:
			return c["name"]
	return card_id


func _effect_text(card: Dictionary) -> String:
	var t: Dictionary = card["tiers"]["effective"]
	var parts: Array = []
	for e in t["effects"]:
		var d: int = e["delay"]
		var suffix := "（%d 回合后）" % d if d > 0 else ""
		parts.append("%s %+d%s" % [GameState.METRIC_NAMES[e["metric"]], e["delta"], suffix])
	return "效果：" + "、".join(parts)


func _find_card_info(panel: PanelContainer) -> Dictionary:
	for info in card_infos:
		if info["panel"] == panel:
			return info
	return {}


## 点击卡牌：切换选中（可取消）
func _on_card_gui_input(event: InputEvent, panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_card(panel)


func _toggle_card(panel: PanelContainer) -> void:
	var info: Dictionary = _find_card_info(panel)
	if info.is_empty():
		return
	if info["selected"]:
		info["selected"] = false
		_remove_gold_frame(panel)
	else:
		# 行动位上限
		if _selected_count() >= GameState.MAX_ACTIONS:
			_reject_card(panel, "行动位已满（每回合最多 3 个）")
			return
		# 资金检查：已选卡的总花费 + 这张，不能超过可用资金
		var cost := GameState.tier_cost(info["card_id"], "effective")
		if _committed_funds() + cost > GameState.funds:
			_reject_card(panel, "资金不足（还需 %d 万，可用 %d 万）" % [cost, GameState.funds - _committed_funds()])
			return
		info["selected"] = true
		_apply_gold_frame(panel)
	_update_selected_label()


## 已选卡牌的总花费（万）
func _committed_funds() -> int:
	var total := 0
	for info in card_infos:
		if info["selected"]:
			total += GameState.tier_cost(info["card_id"], "effective")
	return total


func _selected_count() -> int:
	var n := 0
	for info in card_infos:
		if info["selected"]:
			n += 1
	return n


func _update_selected_label() -> void:
	var used := _committed_funds()
	selected_label.text = "已选：%d/%d　预算：%d/%d 万" % [
		_selected_count(), GameState.MAX_ACTIONS, used, GameState.funds]


## 拒绝选中：红框闪烁 + 左右抖动 + 提示原因
func _reject_card(panel: PanelContainer, reason: String) -> void:
	var info: Dictionary = _find_card_info(panel)
	if info.is_empty() or info.get("shaking", false):
		return
	info["shaking"] = true
	var sb := panel.get_theme_stylebox("panel")
	var old_border := Color.WHITE
	if sb is StyleBoxFlat:
		old_border = sb.border_color
		sb.border_color = Color(0.92, 0.26, 0.22)
	var base: Vector2 = panel.position
	var tw := panel.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	for k in 3:
		tw.tween_property(panel, "position:x", base.x + 9.0, 0.045)
		tw.tween_property(panel, "position:x", base.x - 9.0, 0.045)
	tw.tween_property(panel, "position:x", base.x, 0.05)
	tw.tween_callback(func() -> void:
		if is_instance_valid(sb):
			sb.border_color = old_border
		info["shaking"] = false)
	_flash_hint(reason)


## 顶部提示条短暂显示（红字），随后恢复
func _flash_hint(text: String) -> void:
	selected_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36))
	selected_label.text = text
	var tw := selected_label.create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void:
		selected_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		_update_selected_label())


## 每帧轮询卡牌悬停：精确判断鼠标是否在旋转后的卡牌内（避免相邻牌误判）
func _update_card_hover(delta: float) -> void:
	if hand_panel.visible == false or card_infos.is_empty():
		return
	var mouse_global := get_viewport().get_mouse_position()
	var box_tf := card_box.get_global_transform()
	# 1) 命中判定：用「静止位置」base_pos，牌弹起后会整体上移，
	#    若用实时 position 判定，鼠标停在牌底附近会「弹起→落回→再弹起」地抖。
	var hits: Array = []   # 命中的 card_infos 下标
	for i in card_infos.size():
		var info: Dictionary = card_infos[i]
		var panel: PanelContainer = info["panel"]
		if not is_instance_valid(panel):
			continue
		if info.get("shaking", false):
			info["hovered"] = false
			continue
		if _point_in_card(panel, info["base_pos"], mouse_global, box_tf):
			hits.append(i)
	# 2) 重叠时只留最上层那张：从子列表末尾（最后绘制 = 最上层）往前找第一个命中的
	var hovered_idx: int = -1
	if hits.size() == 1:
		hovered_idx = hits[0]
	elif hits.size() > 1:
		var children: Array = card_box.get_children()
		for c in range(children.size() - 1, -1, -1):
			for i in hits:
				if card_infos[i]["panel"] == children[c]:
					hovered_idx = i
					break
			if hovered_idx != -1:
				break
	# 3) 驱动弹起 / 放大（与帧率无关的平滑，替代固定系数 lerp）
	for i in card_infos.size():
		var info: Dictionary = card_infos[i]
		var panel: PanelContainer = info["panel"]
		if not is_instance_valid(panel) or info.get("shaking", false):
			continue  # 抖动动画期间不要抢它的 position
		var hovering: bool = (i == hovered_idx)
		info["hovered"] = hovering
		# 抬起：鼠标悬停的牌 + 已选定的牌（已选牌保持"抬起来挂在那儿"的状态）
		var raised: bool = hovering or info["selected"]
		# 弹起方向：沿径向向外（远离圆心，即向上弹出）
		var target: Vector2 = info["base_pos"] + info["radial"] * (26.0 if raised else 0.0)
		panel.position = panel.position.lerp(target, 1.0 - exp(-12.0 * delta))
		var s: float = 1.06 if hovering else 1.0
		panel.scale = panel.scale.lerp(Vector2(s, s), 1.0 - exp(-14.0 * delta))
	_update_card_stack()


## 手牌分三层叠放（像斗地主那样，选中的牌整体浮起一排）：
##   底层 = 未选中的牌 → 中层 = 已选中的牌 → 顶层 = 鼠标正悬停的那张
## Godot 里兄弟节点越靠后越晚绘制、也就越在上层，所以把三组按这个顺序排进子列表即可。
## 各层内部保持原本的左右顺序；鼠标一移开，悬停那张就插回它自己那一层（不留痕迹）。
## 只改「绘制与拾取顺序」，不动任何坐标，所以不会和扇形布局打架。
func _update_card_stack() -> void:
	if card_infos.is_empty():
		return
	var front: PanelContainer = null
	for info in card_infos:
		if info.get("hovered", false) and is_instance_valid(info["panel"]):
			front = info["panel"]
			break
	var plain: Array = []   # 未选中
	var picked: Array = []  # 已选中
	for info in card_infos:
		var panel: PanelContainer = info["panel"]
		if not is_instance_valid(panel) or panel == front:
			continue
		if info["selected"]:
			picked.append(panel)
		else:
			plain.append(panel)
	var want: Array = plain.duplicate()
	want.append_array(picked)
	if front != null:
		want.append(front)
	# 与当前顺序一致就不动，避免每帧无谓重排
	var cur: Array = card_box.get_children()
	if cur.size() == want.size():
		var same := true
		for i in want.size():
			if cur[i] != want[i]:
				same = false
				break
		if same:
			return
	for i in want.size():
		card_box.move_child(want[i], i)


## 判断全局坐标点是否在旋转后的卡牌矩形内（按「静止位置」base_pos 判定，见 _update_card_hover）
func _point_in_card(panel: PanelContainer, base_pos: Vector2, mouse_global: Vector2, box_tf: Transform2D) -> bool:
	# 鼠标 → card_box 局部坐标
	var local: Vector2 = box_tf.affine_inverse() * mouse_global
	# 相对牌底中心(pivot)的向量
	var offset: Vector2 = local - (base_pos + panel.pivot_offset)
	# 逆旋转到卡牌自身坐标系
	var ang := -panel.rotation
	var rotated := Vector2(
		offset.x * cos(ang) - offset.y * sin(ang),
		offset.x * sin(ang) + offset.y * cos(ang)
	)
	var hx: float = panel.pivot_offset.x
	var hy: float = panel.pivot_offset.y
	return rotated.x >= -hx and rotated.x <= panel.size.x - hx \
		and rotated.y >= -hy and rotated.y <= panel.size.y - hy


## 金色闪光框（选中标记，呼吸发光）
func _apply_gold_frame(panel: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.22, 0.14, 0.98)
	sb.border_color = Color(1.0, 0.85, 0.30)
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	var tw := panel.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sb, "border_color", Color(1.0, 0.95, 0.55), 0.7)
	tw.tween_property(sb, "border_color", Color(0.95, 0.72, 0.18), 0.7)


## 取消选中：恢复普通边框
func _remove_gold_frame(panel: PanelContainer) -> void:
	_panel_style(panel, Color(0.30, 0.22, 0.14, 0.98))


func _finish_turn() -> void:
	# 执行所有选中的卡（防御：资金/行动位不足的记录为失败，不静默吞掉）
	var failed: Array = []
	for info in card_infos:
		if info["selected"]:
			if not GameState.execute_action(info["card_id"], "effective"):
				failed.append(info["card_id"])

	var before: Dictionary = GameState.metrics.duplicate()
	GameState.end_turn()
	var after: Dictionary = GameState.metrics

	var lines: Array = []
	if GameState.last_crisis_name != "":
		lines.append("⚠ 危机爆发：%s" % GameState.last_crisis_name)
		lines.append("")
	lines.append("本回合结算：")
	for metric in GameState.METRIC_NAMES:
		var d: int = after[metric] - before[metric]
		if d != 0:
			lines.append("  %s：%+d" % [GameState.METRIC_NAMES[metric], d])
	for msg in GameState.log_messages:
		lines.append("  · %s" % msg)
	if not failed.is_empty():
		var names: Array = []
		for cid in failed:
			names.append(_card_name(cid))
		lines.append("  ⚠ 以下行动因资金不足未能执行：%s" % "、".join(names))
	lines.append("")
	lines.append("结转资金：%d 万（未用资金享 %d%% 利息，上限 %d 万）" % [GameState.carry, int(GameState.INTEREST_RATE * 100), GameState.MAX_CARRY])
	# 下回合危机预警
	if not GameState.pending_crisis.is_empty():
		lines.append("")
		lines.append("[color=#ffb060]⏳ 预警：%s[/color]" % GameState.pending_crisis["name"])

	hand_panel.visible = false
	bottom_right.visible = false
	_slide_side_panels(true)  # 结算后侧边栏收回屏幕外，让出沙盘
	_show_popup("结算反馈", "\n".join(lines), "继续", _on_resolve_continue)


func _on_resolve_continue() -> void:
	var kid := GameState.pop_pending_knowledge()
	if kid != "":
		_show_knowledge(kid)
	else:
		_advance_to_next()


func _show_knowledge(card_id: String) -> void:
	var k: Dictionary = GameState.KNOWLEDGE_CARDS[card_id]
	var body := "[color=#7fd0ff]【%s】[/color]\n\n" % k["category"]
	body += "%s\n\n" % k["short"]
	body += "[b]生态角色[/b]：%s\n\n" % k["ecology"]
	body += "[b]当前威胁[/b]：%s\n\n" % k["threat"]
	body += "[b]管理建议[/b]：%s" % k["management"]
	_show_popup("知识卡 · %s" % k["name"], body, "收下（继续）", _on_resolve_continue)


func _advance_to_next() -> void:
	if GameState.game_over:
		_show_report(GameState.generate_report())
	else:
		GameState.start_new_turn()
		# start_new_turn 会触发事件信号（有事件回合）。无事件回合不弹窗，
		# 但知识卡弹窗此时已经关闭，所以直接进入分配阶段即可。
		if not popup_root.visible:
			_enter_allocate()


func _on_game_end(report: Dictionary) -> void:
	pass  # 报告在结算展示后再呈现


func _show_report(r: Dictionary) -> void:
	var earned: int = r.get("talent_points", 0)
	if earned > 0:
		Talents.award(earned)
	var body := ""
	var title := "四年 · 生态报告"
	if r.get("is_failure", false):
		title = "被撤换 · 修复失败"
		body += "[color=#ff7060][b]第 %d 回合，%s[/b][/color]\n\n" % [
			r.get("turns_survived", 0), r.get("failure_reason", "生态崩溃")]
		body += "你的修复工作被迫中止。这不是终点——换一个策略，再试一次。\n\n"
	body += "[b]生态维度[/b]（%s）\n" % r["eco"]["grade"]
	for n in r["eco"]["notes"]:
		body += "  · %s\n" % n
	body += "\n[b]社会维度[/b]（%s）\n" % r["social"]["grade"]
	for n in r["social"]["notes"]:
		body += "  · %s\n" % n
	body += "\n[b]管理维度[/b]（%s）\n" % r["manage"]["grade"]
	for n in r["manage"]["notes"]:
		body += "  · %s\n" % n
	body += "\n[b]知识卡收集[/b]：%d / %d　[b]科研点[/b]：%d\n" % [r["knowledge_count"], r["total_knowledge"], r["research_points"]]
	body += "[color=#8a8a8a]本局种子：%d（同种子可复现，便于对照实验）[/color]\n" % r.get("seed", 0)
	if earned > 0:
		body += "[color=#ffd060]获得天赋点：+%d[/color]\n" % earned
	body += "\n[b]反思[/b]\n%s" % r["reflection"]
	_show_popup(title, body, "返回主菜单", _restart)


func _restart() -> void:
	_current_event = ""
	# 回到主菜单，让玩家可重新输入种子（留空则随机）
	_show_menu()


# ==================== 通用弹窗 ====================
func _show_popup(title: String, body: String, button_text: String, on_continue: Callable) -> void:
	popup_title.text = title
	popup_body.text = body
	popup_button.text = button_text
	_popup_continue = on_continue
	popup_root.visible = true
	# 面板 pivot 需要等布局完成后再设，否则用旧尺寸缩放会偏移
	popup_panel.pivot_offset = popup_panel.size * 0.5
	# 弹窗淡入 + 面板轻微弹入（玩家等待中的反馈，用稍长时长更从容）
	popup_root.modulate.a = 0.0
	popup_panel.scale = Vector2(0.94, 0.94)
	var tw := popup_root.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(popup_root, "modulate:a", 1.0, 0.18)
	var tw2 := popup_panel.create_tween()
	tw2.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(popup_panel, "scale", Vector2.ONE, 0.24)
	# 正文打字机效果：逐字从左到右、从上到下依次打出
	popup_body.visible_ratio = 1.0
	popup_body.visible_characters = 0
	var total := popup_body.get_total_character_count()
	var reveal_time: float = clampf(total * 0.016, 0.3, 2.5)
	var tw3 := popup_body.create_tween()
	tw3.set_trans(Tween.TRANS_LINEAR)
	tw3.tween_property(popup_body, "visible_characters", total, reveal_time).set_delay(0.1)


func _on_popup_button() -> void:
	# 若正文还在逐字打字中，第一次点击先把文字补全（避免误关）
	if popup_body.visible_characters < popup_body.get_total_character_count():
		popup_body.visible_characters = -1
		return
	popup_root.visible = false
	var cb := _popup_continue
	_popup_continue = Callable()
	if cb.is_valid():
		cb.call()


# ==================== 控件工厂 ====================
func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _snap_px(size))
	l.add_theme_color_override("font_color", color)
	return l


func _make_button(text: String, cb: Callable, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", _snap_px(size))
	b.add_theme_color_override("font_color", Color(0.96, 0.90, 0.76))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82))
	b.add_theme_color_override("font_pressed_color", Color(0.90, 0.82, 0.66))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.42))
	b.add_theme_stylebox_override("normal", _wood_button(Color(0.42, 0.30, 0.18), Color(0.24, 0.16, 0.09)))
	b.add_theme_stylebox_override("hover", _wood_button(Color(0.52, 0.38, 0.23), Color(0.30, 0.20, 0.11)))
	b.add_theme_stylebox_override("pressed", _wood_button(Color(0.28, 0.19, 0.11), Color(0.16, 0.10, 0.05)))
	b.add_theme_stylebox_override("disabled", _wood_button(Color(0.26, 0.22, 0.17), Color(0.18, 0.15, 0.11)))
	b.pressed.connect(cb)
	return b


## 星露谷风木按钮（硬边角、木色、细边框）
func _wood_button(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


func _panel_style(p: PanelContainer, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0.45, 0.32, 0.18, 1.0)  # 中木棕边框
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)


## 左侧/右侧信息面板滑出屏幕（结算后）或滑回（下一回合开始）
func _slide_side_panels(out: bool) -> void:
	if left_panel == null or right_panel == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if out:
		var lw := left_panel.offset_right - left_panel.offset_left
		var rw := right_panel.offset_right - right_panel.offset_left
		tw.tween_property(left_panel, "offset_left", -lw - 6, 0.35)
		tw.tween_property(left_panel, "offset_right", -6, 0.35)
		tw.tween_property(right_panel, "offset_left", -6, 0.35)
		tw.tween_property(right_panel, "offset_right", rw - 6, 0.35)
	else:
		tw.tween_property(left_panel, "offset_left", 6, 0.35)
		tw.tween_property(left_panel, "offset_right", 210, 0.35)
		tw.tween_property(right_panel, "offset_left", -190, 0.35)
		tw.tween_property(right_panel, "offset_right", -6, 0.35)


# ==================== 像素图标 ====================
## 从字符网格生成像素图标纹理（'#'=描边, 'X'=主色, 'o'=高光, '.'=透明）
func _pixel_icon(grid: String, main: Color, dark: Color, light: Color) -> ImageTexture:
	var rows: Array = []
	for r in grid.split("\n"):
		var line: String = (r as String).strip_edges()
		if line != "":
			rows.append(line)
	var h := rows.size()
	var w := (rows[0] as String).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var line: String = rows[y]
		for x in w:
			match line[x]:
				"#": img.set_pixel(x, y, dark)
				"X": img.set_pixel(x, y, main)
				"o": img.set_pixel(x, y, light)
				_: img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## 生成指定显示尺寸的像素图标控件（最近邻放大保持锐利）
func _make_icon(grid: String, main: Color, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _pixel_icon(grid, main, main.darkened(0.38), main.lightened(0.32))
	tr.custom_minimum_size = Vector2(px, px)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return tr


## 各数值/指标对应的像素图标网格
func _icon_grid_for(kind: String) -> String:
	match kind:
		"coin":
			return """..####..
.#XXXX#.
#XooXXX#
#XooXXX#
#XXXXXX#
#XXXXXX#
.#XXXX#.
..####.."""
		"water_level":
			return """...##...
..#XX#..
.#XooX#.
.#XXXX#.
.#XXXX#.
..#XX#..
...##...
........"""
		"vegetation":
			return """....#...
....##..
..###X#.
.###XX#.
.###XX#.
..###...
....#...
........"""
		"water_quality":
			return """...##...
...##...
..#XX#..
.#XXXX#.
#XXXXXX#
#XXXXXX#
.#XXXX#.
..####.."""
		"fish":
			return """........
..##....
.####..#
#######.
.####..#
..##....
........
........"""
		"birds":
			return """........
..##....
.#####.#
#######.
.####...
..##....
........
........"""
		"community":
			return """........
.##..##.
#XX##XX#
#XXXXXX#
#XXXXXX#
.#XXXX#.
..####..
...##..."""
		"research":
			return """........
.#######
.#######
.#######
.#.#.#.#
.#######
........
........"""
	return ""


# ==================== 像素字体 ====================
## 加载中文像素字体（缝合像素/融合像素，OFL 授权）并设为全局默认字体
func _setup_pixel_font() -> void:
	# 用 load() 读导入后的 FontFile，导出包（.pck）里也能正确加载
	var zh: FontFile = load("res://fonts/fusion-pixel-12px-monospaced-zh_hans.ttf")
	if zh == null:
		return
	var latin: FontFile = load("res://fonts/fusion-pixel-12px-monospaced-latin.ttf")
	if latin != null:
		zh.fallbacks = [latin]
	# 关抗锯齿 + 整数像素对齐，保证像素字体锐利
	zh.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	zh.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	ThemeDB.fallback_font = zh


## 把字号吸附到像素字体的原生尺寸（12px 的整数倍），避免缩放发虚
func _snap_px(s: int) -> int:
	return maxi(12, int(round(s / 12.0)) * 12)
