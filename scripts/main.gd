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
var research_label: Label
var event_label: Label
var right_panel: PanelContainer
var metric_bars: Dictionary = {}
var hand_panel: PanelContainer
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

# 3D 表现节点
var lake_mesh: MeshInstance3D
var lake_mat: StandardMaterial3D
var grass_nodes: Array = []
var grass_mats: Array = []
var bird_nodes: Array = []
var fish_nodes: Array = []
var village_nodes: Array = []     # 多栋房子
var village_mats: Array = []
var species_views: Dictionary = {}  # sid -> {rigs[], bases[], states[], timers[], targets[]}
var plant_views: Dictionary = {}    # pid -> {meshes[], kind}


func _ready() -> void:
	_setup_camera()
	_build_3d()
	_build_ui()
	GameState.metrics_changed.connect(_update_hud)
	GameState.metrics_changed.connect(_update_3d)
	GameState.funds_changed.connect(_update_hud)
	GameState.event_triggered.connect(_on_event)
	GameState.game_ended.connect(_on_game_end)
	GameState.reset_game()
	_update_hud()
	_update_3d()


# ==================== 相机 ====================
func _setup_camera() -> void:
	var cam := get_node("../Camera3D") as Camera3D
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 17.5
	# 饥荒式 2.5D：正交 + 45° 方位角 + 约 57° 俯角（顶面与侧面均可见，立体感强）
	cam.position = Vector3(6, 13, 6)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)

	# 暖色方向光（湿地黄昏氛围）
	var light := get_node("../DirectionalLight3D") as DirectionalLight3D
	light.light_color = Color(1.0, 0.85, 0.65)
	light.light_energy = 1.4
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.shadow_enabled = true


# ==================== 3D 表现 ====================
func _build_3d() -> void:
	var lake_view := Node3D.new()
	lake_view.name = "LakeView"

	# 湖面
	lake_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(18, 18)
	lake_mesh.mesh = pm
	lake_mesh.position = Vector3(0, 0.08, 0)
	lake_mat = StandardMaterial3D.new()
	lake_mat.albedo_color = Color(0.20, 0.50, 0.80, 0.88)
	lake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lake_mesh.material_override = lake_mat
	lake_view.add_child(lake_mesh)

	# 棋盘网格线（生息演算式棋盘感）
	_build_grid(lake_view)

	# 草洲（8 块，改湿地地貌分层）
	var grass_positions := [
		Vector3(-7, 0.05, -5), Vector3(-4, 0.05, -7), Vector3(6, 0.05, -4),
		Vector3(8, 0.05, 2), Vector3(-8, 0.05, 4), Vector3(3, 0.05, 7),
		Vector3(-2, 0.05, 8), Vector3(-6, 0.05, -2),
	]
	for p in grass_positions:
		var mi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(3.0, 0.25, 3.0)
		mi.mesh = cm
		mi.position = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.62, 0.30)
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
		mat.albedo_color = Color(0.55, 0.55, 0.62)
		mi.material_override = mat
		lake_view.add_child(mi)
		fish_nodes.append(mi)

	# 渔村（湖边一排房子）
	_build_village(lake_view)

	# 延迟挂到场景，避免父节点初始化期 add_child 冲突
	var root := get_parent() as Node3D
	root.add_child.call_deferred(lake_view)


## 湖边社区：一排房子，数量/颜色随社区信任度变化
func _build_village(parent: Node3D) -> void:
	var house_positions := [
		Vector3(-11, 0, -7), Vector3(-12.5, 0, -5.2), Vector3(-13, 0, -3.4),
		Vector3(-12.2, 0, -1.6), Vector3(-10.6, 0, 0.2),
	]
	for p in house_positions:
		var house := _make_house()
		house.position = p
		parent.add_child(house)
		village_nodes.append(house)
		var mats := _collect_mats(house)
		for m in mats:
			village_mats.append(m)


func _make_house() -> Node3D:
	var house := Node3D.new()
	# 墙体
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.4, 1.0, 1.1)
	wall.mesh = wm
	wall.position = Vector3(0, 0.5, 0)
	wall.material_override = _mat(Color(0.78, 0.62, 0.44))
	house.add_child(wall)
	# 屋顶（三棱柱）
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(1.7, 0.6, 1.4)
	roof.mesh = rm
	roof.position = Vector3(0, 1.3, 0)
	roof.material_override = _mat(Color(0.48, 0.30, 0.24))
	house.add_child(roof)
	# 门
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.3, 0.5, 0.05)
	door.mesh = dm
	door.position = Vector3(0, 0.25, 0.58)
	door.material_override = _mat(Color(0.35, 0.24, 0.16))
	house.add_child(door)
	return house


func _collect_mats(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.material_override:
			out.append(mi.material_override)
	for c in n.get_children():
		out.append_array(_collect_mats(c))
	return out


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
		Vector3(-11, 0.03, 0), Vector3(11, 0.03, -1), Vector3(0, 0.03, -11),
		Vector3(1, 0.03, 11), Vector3(-5, 0.03, 9), Vector3(5, 0.03, -9),
	]
	for p in positions:
		var mi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(4.0, 0.15, 4.0)
		mi.mesh = cm
		mi.position = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.52, 0.42, 0.28)
		mi.material_override = mat
		parent.add_child(mi)


func _process(delta: float) -> void:
	_process_birds(delta)
	_update_card_hover(delta)
	# 容器尺寸变化时重排扇形（居中）
	if card_box != null and card_box.size.x > 10.0:
		if _fan_layout_size.distance_to(card_box.size) > 1.0:
			_layout_fan()


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
				if r < 0.45:
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
	var white := Color(0.94, 0.94, 0.93)
	var dark := Color(0.13, 0.13, 0.18)
	var grey := Color(0.68, 0.67, 0.63)
	var red := Color(0.80, 0.15, 0.12)
	var yellow := Color(0.92, 0.72, 0.25)
	var brown := Color(0.55, 0.48, 0.38)

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
			flower.material_override = _mat(Color(0.92, 0.65, 0.78))
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
			trunk.material_override = _mat(Color(0.36, 0.25, 0.16))
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


func _plant_position(pid: String, kind: String, i: int) -> Vector3:
	match kind:
		"submerged":
			return Vector3(-6 + (i % 6) * 2.4, 0.0, -2 + int(i / 6) * 2.5)
		"floating":
			return Vector3(2 + (i % 5) * 2.5, 0.06, -4 + int(i / 5) * 2.5)
		"emergent":
			return Vector3(-9 + (i % 7) * 2.6, 0.5, 3 + int(i / 7) * 2.5)
		"tree":
			# 乔木在岸边 / 草洲外围
			return Vector3(-13 + (i % 5) * 6.0, 0.0, -12 + int(i / 5) * 2.6)
		_:
			return Vector3(-8 + (i % 7) * 2.4, 0.05, 5 + int(i / 7) * 2.4)


func _update_3d() -> void:
	var m: Dictionary = GameState.metrics
	var wscale := lerpf(0.55, 1.35, float(m["water_level"]) / 100.0)
	lake_mesh.scale = Vector3(wscale, 1.0, wscale)
	lake_mat.albedo_color = Color(0.18, 0.45 + 0.35 * (float(m["water_level"]) / 100.0), 0.80, 0.88)

	for i in grass_nodes.size():
		var v := float(m["vegetation"]) / 100.0
		grass_mats[i].albedo_color = Color(0.55 - 0.3 * v, 0.35 + 0.35 * v, 0.20 + 0.15 * v)
		grass_nodes[i].visible = m["vegetation"] > (10 + i * 8)

	var nfish := int(m["fish"] / 12.0)
	for i in fish_nodes.size():
		fish_nodes[i].visible = i < nfish

	# 物种个体数量随物种种群增减
	_update_species_views()

	# 植物数量随植被指标增减
	_update_plant_views()

	# 社区房子：信任度高则更多房子亮灯（暖色），低则灰暗
	var cv := float(m["community"]) / 100.0
	var lit_count := int(cv / 20.0)  # 0-100 → 0-5 栋亮
	for i in village_mats.size():
		var house_cv: float = 1.0 if i < lit_count else 0.45
		village_mats[i].albedo_color = Color(
			0.45 + 0.35 * house_cv,
			0.32 + 0.25 * house_cv,
			0.22 + 0.1 * house_cv
		)


# ==================== UI ====================
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UICanvas"
	add_child(canvas)

	# --- 左侧：时间 / 金钱 / 事件 ---
	left_panel = PanelContainer.new()
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 0.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 8
	left_panel.offset_right = 292
	left_panel.offset_top = 8
	left_panel.offset_bottom = -200
	_panel_style(left_panel, Color(0.20, 0.14, 0.09, 0.94))
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

	funds_label = _make_label("资金：75 万", 17, Color(1, 0.95, 0.6))
	lv.add_child(funds_label)
	research_label = _make_label("科研点：0", 14, Color(0.82, 0.9, 1))
	lv.add_child(research_label)

	var sep2 := HSeparator.new()
	lv.add_child(sep2)

	var ev_title := _make_label("特殊事件", 15, Color(1, 0.75, 0.5))
	lv.add_child(ev_title)
	event_label = _make_label("暂无", 13, Color(0.9, 0.92, 0.94))
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(event_label)

	# --- 右侧：六项指标 ---
	right_panel = PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -292
	right_panel.offset_right = -8
	right_panel.offset_top = 8
	right_panel.offset_bottom = -200
	_panel_style(right_panel, Color(0.20, 0.14, 0.09, 0.94))
	canvas.add_child(right_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_panel.add_child(rv)
	var r_title := _make_label("生态指标", 16, Color(0.85, 0.92, 1))
	rv.add_child(r_title)
	for metric in GameState.METRIC_NAMES:
		rv.add_child(_make_metric_row(metric))

	# --- 底部中间：手牌 ---
	hand_panel = PanelContainer.new()
	hand_panel.anchor_left = 0.0
	hand_panel.anchor_top = 1.0
	hand_panel.anchor_right = 1.0
	hand_panel.anchor_bottom = 1.0
	hand_panel.offset_left = 300
	hand_panel.offset_right = -300
	hand_panel.offset_top = -320
	hand_panel.offset_bottom = -8
	_panel_style(hand_panel, Color(0.22, 0.15, 0.10, 0.96))
	hand_panel.visible = false
	canvas.add_child(hand_panel)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hand_panel.add_child(hv)

	var h_top := HBoxContainer.new()
	hv.add_child(h_top)
	var h_hint := _make_label("每回合最多执行 3 个行动（点击卡牌直接执行）", 13, Color(0.8, 0.85, 0.9))
	h_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_top.add_child(h_hint)
	selected_label = _make_label("已选：0/3", 14, Color(1, 0.9, 0.5))
	h_top.add_child(selected_label)
	var end_btn := _make_button("结束本回合 ▶", _finish_turn, 16)
	end_btn.custom_minimum_size = Vector2(140, 34)
	h_top.add_child(end_btn)

	# 牌区（扇形手牌，手动定位）
	card_box = Control.new()
	card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_box.custom_minimum_size = Vector2(0, 238)
	card_box.mouse_filter = Control.MOUSE_FILTER_PASS
	card_box.resized.connect(_on_card_box_resized)
	hv.add_child(card_box)

	# --- 弹窗（顶层）---
	popup_root = Control.new()
	popup_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.visible = false
	canvas.add_child(popup_root)

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_root.add_child(dim)

	popup_center = CenterContainer.new()
	popup_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_center.mouse_filter = Control.MOUSE_FILTER_PASS
	popup_root.add_child(popup_center)

	popup_panel = PanelContainer.new()
	popup_panel.custom_minimum_size = Vector2(600, 0)
	_panel_style(popup_panel, Color(0.24, 0.17, 0.11, 0.98))
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
	popup_body.add_theme_font_size_override("normal_font_size", 16)
	popup_body.add_theme_color_override("default_color", Color(0.95, 0.95, 0.95))
	pv.add_child(popup_body)
	popup_button = _make_button("继续", _on_popup_button, 18)
	popup_button.custom_minimum_size = Vector2(0, 44)
	pv.add_child(popup_button)


func _make_metric_row(metric: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(_make_label(GameState.METRIC_NAMES[metric], 13, Color(0.95, 0.95, 0.95)))
	var val := _make_label("0", 13, METRIC_COLORS[metric])
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(val)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
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
	funds_label.text = "资金：%d 万" % GameState.funds
	research_label.text = "科研点：%d" % GameState.research_points
	event_label.text = _current_event if _current_event != "" else "暂无"
	selected_label.text = "已选：%d/%d" % [GameState.used_action_ids.size(), GameState.MAX_ACTIONS]


# ==================== 事件 / 结算 / 知识卡 / 报告 ====================
func _on_event(text: String) -> void:
	_current_event = text
	_update_hud()
	hand_panel.visible = false
	_show_popup("第 %d 回合 · 事件" % GameState.turn, text, "开始分配资金", _enter_allocate)


func _enter_allocate() -> void:
	current_hand = GameState.draw_cards(6)
	play_deal_anim = true
	_build_hand_panel()
	hand_panel.visible = true


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
			"selected": false,
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
	var bottom_margin := 10.0
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
		if _selected_count() >= GameState.MAX_ACTIONS:
			return
		info["selected"] = true
		_apply_gold_frame(panel)
	_update_selected_label()


func _selected_count() -> int:
	var n := 0
	for info in card_infos:
		if info["selected"]:
			n += 1
	return n


func _update_selected_label() -> void:
	selected_label.text = "已选：%d/%d" % [_selected_count(), GameState.MAX_ACTIONS]


## 每帧轮询卡牌悬停：精确判断鼠标是否在旋转后的卡牌内（避免相邻牌误判）
func _update_card_hover(delta: float) -> void:
	if hand_panel.visible == false or card_infos.is_empty():
		return
	var mouse_global := get_viewport().get_mouse_position()
	var box_tf := card_box.get_global_transform()
	for info in card_infos:
		var panel: PanelContainer = info["panel"]
		if not is_instance_valid(panel):
			continue
		var hovering: bool = _point_in_card(panel, mouse_global, box_tf)
		var raised: bool = hovering or info["selected"]
		# 弹起方向：沿径向向外（远离圆心，即向上弹出）
		var target: Vector2 = info["base_pos"] + info["radial"] * (26.0 if raised else 0.0)
		# 与帧率无关的平滑（每秒 12 倍速收敛），替代固定系数 lerp
		panel.position = panel.position.lerp(target, 1.0 - exp(-12.0 * delta))


## 判断全局坐标点是否在旋转后的卡牌矩形内
func _point_in_card(panel: PanelContainer, mouse_global: Vector2, box_tf: Transform2D) -> bool:
	# 鼠标 → card_box 局部坐标
	var local: Vector2 = box_tf.affine_inverse() * mouse_global
	# 相对牌底中心(pivot)的向量
	var offset: Vector2 = local - (panel.position + panel.pivot_offset)
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
	# 执行所有选中的卡（按选中顺序，资金不足的跳过）
	for info in card_infos:
		if info["selected"]:
			GameState.execute_action(info["card_id"], "effective")

	var before: Dictionary = GameState.metrics.duplicate()
	GameState.end_turn()
	var after: Dictionary = GameState.metrics

	var lines: Array = []
	lines.append("本回合结算：")
	for metric in GameState.METRIC_NAMES:
		var d: int = after[metric] - before[metric]
		if d != 0:
			lines.append("  %s：%+d" % [GameState.METRIC_NAMES[metric], d])
	for msg in GameState.log_messages:
		lines.append("  · %s" % msg)
	lines.append("")
	lines.append("结转资金：%d 万（上限 %d 万）" % [GameState.carry, GameState.MAX_CARRY])

	hand_panel.visible = false
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
	var body := ""
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
	body += "\n[b]反思[/b]\n%s" % r["reflection"]
	_show_popup("四年 · 生态报告", body, "重新开始", _restart)


func _restart() -> void:
	_current_event = ""
	GameState.reset_game()
	_update_hud()
	_update_3d()


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
	# 正文逐字揭示（长文本慢一点，短文本快一点，上限 0.7s）
	popup_body.visible_ratio = 0.0
	var reveal_time: float = clampf(body.length() * 0.006, 0.25, 0.7)
	var tw3 := popup_body.create_tween()
	tw3.set_trans(Tween.TRANS_LINEAR)
	tw3.tween_property(popup_body, "visible_ratio", 1.0, reveal_time).set_delay(0.1)


func _on_popup_button() -> void:
	# 若正文还在逐字揭示中，第一次点击先把文字补全（避免误关）
	if popup_body.visible_ratio < 1.0:
		popup_body.visible_ratio = 1.0
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
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_button(text: String, cb: Callable, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
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
