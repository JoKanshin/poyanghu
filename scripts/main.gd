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
const CATEGORY_ORDER := ["ecology", "social", "manage"]
# 苦力怕彩蛋（左上角草地，lake_view 局部坐标）
const CREEPER_X := -45.0
const CREEPER_Z := 4.0
const CREEPER_SIZE := 12.0   # 贴图宽度（高度按图片宽高比自动算）
const CREEPER_CHANCE := 0.1  # 进入主菜单时出现的概率
var creeper_mesh: MeshInstance3D = null

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
# 指标悬停小窗（跟随鼠标：本回合会掉多少 / 红线在哪）
var metric_tip: PanelContainer = null
var metric_tip_title: Label = null
var metric_tip_body: RichTextLabel = null
var _tip_metric: String = ""       # 当前小窗显示的是哪一项（"" = 没显示）
var _tip_last_text: String = ""    # 上次写入的正文，内容没变就不重复塞（省得每帧重排版）
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
var menu_col: VBoxContainer            # 左下角选项列
var menu_start_btn: Button
var menu_easy_btn: Button
var menu_normal_btn: Button
var menu_hard_btn: Button
var menu_back_btn: Button
var menu_seed_start_btn: Button
var menu_talent_btn: Button
var menu_settings_btn: Button
var menu_credits_btn: Button
var menu_changelog_btn: Button
var menu_quit_btn: Button
var menu_seed_label: Label
var menu_mode_label: Label
var seed_input: LineEdit
var menu_hint: Label
var menu_talent_panel: PanelContainer
var menu_settings_panel: PanelContainer
var menu_credits_panel: PanelContainer
var menu_changelog_panel: PanelContainer

# 音频 / BGM
var bgm_player: AudioStreamPlayer
var bgm_index: int = 1
var bgm_volume: float = 0.8
var audio_volume_slider: HSlider
var audio_volume_label: Label
var bgm_switch_btn: Button
var pause_settings_panel: PanelContainer
var pause_volume_slider: HSlider
var pause_volume_label: Label
var pause_bgm_btn: Button
const BGM_PATHS := ["res://assets/audio/poyanghu.mp3", "res://assets/audio/poyanghunaiyu.mp3"]
const BGM_NAMES := ["鄱阳湖", "评委审核版"]
const AUDIO_SETTINGS_PATH := "user://settings.json"
var menu_camera_far: bool = false      # 开始页期间镜头拉远看全景
var talent_points_label: Label
var talent_list: VBoxContainer
var talent_unlock_btn: Button
var menu_continue_btn: Button

# 暂停 / 存档
var pause_root: Control
var pause_panel: PanelContainer
var pause_hint: Label
var _paused: bool = false
var _playing: bool = false
var _current_phase: String = "allocate"
var _defer_game_over: bool = false   # 回合结算流程中：报告由结算反馈之后再弹，别抢
const SAVE_PATH = "user://savegame.json"

# 危机警示（大红叹号 + 红屏闪烁 + 雷霆大字）
var crisis_root: Control
var crisis_dim: ColorRect
var crisis_icon: TextureRect
var crisis_title: Label
var crisis_tag: Label
var crisis_body: RichTextLabel
var crisis_button: Button
var _crisis_queue: Array = []   # 危机弹窗队列 {crisis, is_warning}

# 危机预警回顾（顶部条 + 全屏列表）
var warn_bar: Button = null
var warn_panel_root: Control = null
var warn_list_box: VBoxContainer = null
var warn_count_label: Label = null

# 牌库 UI（牌堆）
var deck_root: Control            # 牌堆容器（右面板下方）
var deck_border: Control          # 黄色外框（悬停时显示，自绘贴牌形状）
var deck_backs: Array = []        # 叠放的牌背（TextureRect）
var _deck_hovered: bool = false
var card_back_tex: Texture2D
var deck_viewer: Control          # 牌库查看器（全屏弹层）
var deck_viewer_grid: HFlowContainer
var _deck_open: bool = false
var card_detail: Control          # 卡牌详情弹层（点击查看：左大牌 + 右介绍）
var card_detail_card: CenterContainer  # 左侧大牌容器
var card_detail_title: Label
var card_detail_body: RichTextLabel
var _detail_big_card: Control = null   # 当前详情大牌（用于重开时清理）
var _ui_slide_tweens: Array = []       # 牌库开合时收放主界面的 tween
var _ui_slide_origin: Dictionary = {}  # Control -> [l, t, r, b] 初始 offset
var deck_sort_btn: Button             # 排序切换按钮（互旋箭头）
var _deck_sort_by_category: bool = true  # true=按类别，false=按费用；默认按类别
var _sort_animating: bool = false
var _sort_cooldown_ms: int = -6000   # 上次排序的时间戳，锁死两次切换最低间隔
const SORT_COOLDOWN_MS := 5000
var _deck_viewports: Array = []       # 牌库卡牌的 SubViewport（重建时清理）
var _deck_gyro_view: Control = null   # 当前鼠标悬停的牌库卡牌（只对它做陀螺仪）

# 3D 表现节点
var lake_mesh: MeshInstance3D
var lake_mat: ShaderMaterial
var lake_color: Color = Color(0.62, 0.80, 0.86, 0.88)
var grass_nodes: Array = []
var grass_mats: Array = []
var bird_nodes: Array = []
var fish_nodes: Array = []
var boats: Array = []   # 长江行船 [{rig, x, speed, dir}]
var island_nodes: Array = []      # 人工浮岛节点
var house_slots: Array = []       # 每项 {"house": Node3D, "sprite": Sprite3D, "reeds": Node3D}
var species_views: Dictionary = {}  # sid -> {rigs[], bases[], states[], timers[], targets[]}
var plant_views: Dictionary = {}    # pid -> {meshes[], kind}
var plant_positions: Dictionary = {} # pid -> Array[Vector3]  每局随机散落的位置
var _plant_pos_seed: int = -1        # 已生成位置对应的种子，换局时重新散落

# 开场像素 PPT（Undertale 风：首次游玩讲背景）
var intro_layer: CanvasLayer = null
var intro_root: Control = null
var intro_col: VBoxContainer = null
var intro_image: TextureRect = null
var intro_title: Label = null
var intro_body: Label = null
var intro_hint: Label = null
var intro_slides: Array = []
var intro_index: int = 0
var _intro_playing: bool = false
var _intro_elapsed: float = 0.0
var _intro_advancing: bool = false
const INTRO_SLIDE_SEC := 5.0


func _ready() -> void:
	_load_audio_settings()
	_setup_bgm()
	_setup_pixel_font()
	_setup_camera()
	_build_3d()
	_build_pixelate_layer()
	_build_ui()
	GameState.metrics_changed.connect(_update_hud)
	GameState.metrics_changed.connect(_update_3d)
	GameState.funds_changed.connect(_update_hud)
	GameState.event_triggered.connect(_on_event)
	GameState.crisis_warned.connect(_on_crisis_warn)
	GameState.crisis_hit.connect(_on_crisis_hit)
	GameState.game_ended.connect(_on_game_end)
	# 窗口尺寸/全屏变化时自适应相机，避免全屏后沙盘被裁或留黑边
	get_viewport().size_changed.connect(_fit_camera_to_window)
	_fit_camera_to_window()
	# 首次游玩先放开场 PPT；老玩家直接进主菜单
	if _is_first_play():
		_show_intro()
	else:
		_show_menu()


## 开始页期间镜头拉远的倍率（正交 size 越大 = 视野越广）
const MENU_CAM_ZOOM := 1.7


## 根据窗口宽高比调整正交相机尺寸：让沙盘占满屏幕主体，不因宽屏被推远
func _fit_camera_to_window() -> void:
	var cam := get_node("../Camera3D") as Camera3D
	if cam == null:
		return
	cam.size = _cam_base_size() * (MENU_CAM_ZOOM if menu_camera_far else 1.0)


## 沙盘基准视野：竖直 31 单位，窄屏时按水平需求放宽
func _cam_base_size() -> float:
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return 31.0
	var aspect := vp.x / vp.y
	# 沙盘在 45° 俯视下的垂直投影约 29 世界单位，留边距 → 垂直视野 31
	const VIEW_H := 31.0
	# 窄屏时保证水平也能容纳沙盘宽度
	const NEED_W := 50.0
	return maxf(VIEW_H, NEED_W / aspect)


## 开始页：镜头先压回基准再缓缓推远（开场是「拉远」的动作，不是直接远景）；
## 进入游戏时收回来。
func _set_menu_camera(far: bool) -> void:
	menu_camera_far = far
	var cam := get_node_or_null("../Camera3D") as Camera3D
	if cam == null:
		return
	var base := _cam_base_size()
	if far:
		cam.size = base
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cam, "size", base * (MENU_CAM_ZOOM if far else 1.0), 1.2 if far else 0.8)


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
	# 沙盘等比放大（改这个系数即可整体缩放，不影响布局）
	lake_view.scale = Vector3(1.3, 1.3, 1.3)

	# 湖面（鄱阳湖形不规则多边形 + 注入河流）
	lake_mat = ShaderMaterial.new()
	lake_mat.shader = _make_water_shader()
	lake_mat.set_shader_parameter("water_color", lake_color)
	_build_lake_shape(lake_view)

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

	# 长江行船（装饰性，沿长江缓缓往返）
	_build_boats(lake_view)

	# 远景布景草地（环绕沙盘的低多边形起伏草原，不参与游戏交互）
	_build_backdrop_grass(lake_view)

	# 彩蛋：左上角草地刻一个 Minecraft 苦力怕的脸
	_build_creeper_easter_egg(lake_view)

	# 延迟挂到场景，避免父节点初始化期 add_child 冲突
	var root := get_parent() as Node3D
	root.add_child.call_deferred(lake_view)


## 构建鄱阳湖形水面：南宽北狭的「宝葫芦」形，北部狭长入江水道连长江
func _build_lake_shape(parent: Node3D) -> void:
	# 鄱阳湖轮廓（XZ 平面多边形，北为 -z，南为 +z；北窄为入江水道，南宽为主湖区）
	var outline: PackedVector2Array = [
		Vector2(-2.0, -15.5), Vector2(2.0, -15.5),
		Vector2(2.4, -11.5), Vector2(2.8, -8.0), Vector2(3.4, -5.5),
		Vector2(6.5, -5.0), Vector2(8.5, -3.0), Vector2(9.4, 0.0),
		Vector2(9.0, 3.0), Vector2(7.6, 5.5),
		Vector2(5.8, 7.6), Vector2(3.4, 8.4), Vector2(0.0, 8.9),
		Vector2(-3.4, 8.4), Vector2(-5.8, 7.6),
		Vector2(-7.6, 5.5), Vector2(-9.0, 3.0), Vector2(-9.4, 0.0),
		Vector2(-8.5, -3.0), Vector2(-6.5, -5.0),
		Vector2(-3.4, -5.5), Vector2(-2.8, -8.0), Vector2(-2.4, -11.5),
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


## 长江中心线的 z 坐标（随 x 蜿蜒），生成河面与压平地形的公共基准
func _yangtze_z(x: float) -> float:
	return -14.5 + sin(x * 0.16) * 1.0 + sin(x * 0.043 + 1.3) * 0.7


## 河流：长江（北，蜿蜒自西向东）+ 赣江（南，自南向北，与之垂直）+ 修水/饶河
func _build_rivers(parent: Node3D) -> void:
	# 长江：北侧蜿蜒大河，湖体北口（入江水道 z=-14）汇入其中；两端延伸出镜头
	var yangtze_center := PackedVector2Array()
	for i in range(-75, 61, 5):
		var x := float(i)
		yangtze_center.append(Vector2(x, _yangtze_z(x)))
	var yangtze := _make_flat_polygon(_river_outline(yangtze_center, 2.6), 0.08, lake_mat)
	yangtze.name = "Yangtze"
	parent.add_child(yangtze)

	# 赣江：南侧，自南向北注入湖体南部（第一大支流，与长江近垂直）；南端延伸出镜头
	var gan_center := PackedVector2Array()
	for i in range(6, 61, 4):
		gan_center.append(Vector2(0.0, float(i)))
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


# ==================== 长江行船 ====================
## 生成几艘在长江上缓缓往返的船（装饰，不参与游戏交互）
func _build_boats(parent: Node3D) -> void:
	var configs := [
		{"x": -60.0, "speed": 3.2, "dir": 1.0},
		{"x": 18.0, "speed": 2.4, "dir": -1.0},
		{"x": 44.0, "speed": 3.8, "dir": 1.0},
	]
	for c in configs:
		var rig := _make_boat()
		var x: float = c["x"]
		var z: float = _yangtze_z(x)
		rig.position = Vector3(x, 0.12, z)
		parent.add_child(rig)
		boats.append({"rig": rig, "x": x, "speed": c["speed"], "dir": c["dir"]})


## 单艘船的模型：棕色船体 + 船舱 + 桅杆（船头朝 +Z）
func _make_boat() -> Node3D:
	var boat := Node3D.new()
	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.75, 0.32, 1.9)  # 宽(x) × 高(y) × 长(z，船头朝 +z)
	hull.mesh = hm
	hull.material_override = _mat(Color(0.48, 0.34, 0.24))
	hull.position = Vector3(0, 0.16, 0)
	boat.add_child(hull)
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.6, 0.5, 0.7)
	cabin.mesh = cm
	cabin.material_override = _mat(Color(0.62, 0.46, 0.32))
	cabin.position = Vector3(0, 0.5, -0.35)  # 靠后（-z）
	boat.add_child(cabin)
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.03
	mm.bottom_radius = 0.05
	mm.height = 0.9
	mast.mesh = mm
	mast.material_override = _mat(Color(0.35, 0.28, 0.22))
	mast.position = Vector3(0, 0.75, 0.2)
	boat.add_child(mast)
	return boat


## 长江行船漂移：沿长江中心线缓行，驶出边界后从另一端折返
func _process_boats(delta: float) -> void:
	for b in boats:
		var rig: Node3D = b["rig"]
		var x: float = b["x"] + b["speed"] * b["dir"] * delta
		if x > 61.0:
			x = -76.0
		elif x < -76.0:
			x = 61.0
		b["x"] = x
		# 河流切向 / 垂向：相向而行的船分走河道两侧「车道」，避免会船时穿模
		var dz: float = _yangtze_z(x + 0.6) - _yangtze_z(x - 0.6)
		var tangent := Vector2(1.0, dz).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var lane: float = 0.5 * float(b["dir"])
		var zc: float = _yangtze_z(x)
		rig.position = Vector3(x + normal.x * lane, 0.12, zc + normal.y * lane)
		# 朝向河水流向（船头 +Z 对准切线方向）
		rig.rotation.y = atan2(b["dir"], dz * b["dir"])


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
		if _in_river_zone(x, z) or _in_creeper_zone(x, z):
			continue
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
		if _in_river_zone(x, z) or _in_creeper_zone(x, z):
			continue
		var bush := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = rng.randf_range(0.7, 1.4)
		bm.height = bm.radius * 1.1
		bush.mesh = bm
		bush.material_override = _mat(Color(0.52, 0.64, 0.44).lightened(rng.randf_range(0.0, 0.14)))
		bush.position = Vector3(x, _backdrop_height(x, z) + bm.radius * 0.4, z)
		bush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		backdrop.add_child(bush)


## 是否处于河流走廊内（长江/赣江水面 + 河岸），用于让远景树/灌木避开河道
func _in_river_zone(x: float, z: float) -> bool:
	if x > -77.0 and x < 62.0 and absf(z - _yangtze_z(x)) < 4.0:
		return true
	if z > 5.0 and z < 61.0 and absf(x) < 4.0:
		return true
	return false


## 是否处于苦力怕彩蛋区域，用于让远景树/灌木避开
func _in_creeper_zone(x: float, z: float) -> bool:
	return Vector2(x - CREEPER_X, z - CREEPER_Z).length() < 7.0


## 远景地形高度：几层正弦叠加，形成平缓起伏（距离沙盘越远越不必精确）
func _backdrop_height(x: float, z: float) -> float:
	var h := sin(x * 0.11) * cos(z * 0.13) * 1.6
	h += sin(x * 0.31 + 1.7) * cos(z * 0.27 - 0.6) * 0.55
	h += sin(x * 0.63 - 0.4) * cos(z * 0.58 + 2.1) * 0.22
	# 河流走廊压平到河床高度，避免延伸出的河面被起伏地形掩埋
	var yangtze_d := absf(z - _yangtze_z(x))
	if x > -77.0 and x < 62.0 and yangtze_d < 4.0:
		h = lerpf(-0.28, h, clampf((yangtze_d - 2.2) / 1.8, 0.0, 1.0))
	elif z > 5.0 and z < 61.0 and absf(x) < 4.0:
		h = lerpf(-0.28, h, clampf((absf(x) - 1.8) / 2.2, 0.0, 1.0))
	# 苦力怕彩蛋草地压平，保证脸平整贴地
	var creeper_d := Vector2(x - CREEPER_X, z - CREEPER_Z).length()
	if creeper_d < 8.0:
		h = lerpf(-0.28, h, clampf((creeper_d - 5.0) / 3.0, 0.0, 1.0))
	# 靠近沙盘（半径 22 内）压平并下沉，与沙盘地面平滑衔接
	var d := Vector2(x, z).length()
	if d < 26.0:
		var t := clampf((d - 20.0) / 6.0, 0.0, 1.0)
		h = lerpf(-0.28, h, t)
	return h


## 彩蛋：左上角草地贴一张苦力怕脸（用素材图片，已抠掉亮绿背景）
func _build_creeper_easter_egg(parent: Node3D) -> void:
	# 优先走导入资源（导出打包也能用），失败则直接读文件
	var tex: Texture2D = load("res://assets/creeper.png")
	if tex == null:
		var img := Image.load_from_file("res://assets/creeper.png")
		if img == null:
			return
		tex = ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL  # 与草地同受光照，头部才能和草地同色
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var aspect := float(tex.get_width()) / float(tex.get_height())
	pm.size = Vector2(CREEPER_SIZE, CREEPER_SIZE / aspect)
	mi.mesh = pm
	mi.material_override = mat
	# 草地压平后高度为 -0.28（顶点）+ 节点 -0.28，脸贴在其上略微抬高避免 z-fighting
	mi.position = Vector3(CREEPER_X, -0.28 + _backdrop_height(CREEPER_X, CREEPER_Z) + 0.02, CREEPER_Z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	creeper_mesh = mi


## 苦力怕彩蛋按概率显示（每次进入主菜单重掷）
func _roll_creeper_visibility() -> void:
	if creeper_mesh != null:
		creeper_mesh.visible = randf() < CREEPER_CHANCE


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
		Vector3(-13, 0, -6.5), Vector3(-12.5, 0, -5.2), Vector3(-13, 0, -3.4),
		Vector3(-12.2, 0, -1.6), Vector3(-10.6, 0, 0.2),   # 原有 5 栋（离湖较远）
		Vector3(-9.5, 0, -4.2), Vector3(-10.2, 0, -0.6),   # 新增 2 栋（侵占，靠湖，落在岸上）
	]
	# 美术素材：四款房屋循环使用，营造村庄错落感
	var house_tex_paths := [
		"res://assets/houses/house1.png",
		"res://assets/houses/house2.png",
		"res://assets/houses/house3.png",
		"res://assets/houses/house4.png",
	]
	for i in house_positions.size():
		var p: Vector3 = house_positions[i]
		var house := _make_house(house_tex_paths[i % house_tex_paths.size()])
		house.position = p
		parent.add_child(house)
		var reeds := _make_reed_clump()
		reeds.position = p
		reeds.visible = false
		parent.add_child(reeds)
		var sprite := house.get_child(0) as Sprite3D
		house_slots.append({"house": house, "sprite": sprite, "reeds": reeds})


## 用美术同学画的房屋素材（2D 贴图广告牌）替代原来的 3D 盒子房。
## 返回一个 Node3D 容器（落点 y=0 贴地），内部 Sprite3D 上移半高让贴图底部贴住地面。
func _make_house(path: String) -> Node3D:
	# 优先用导入的贴图（含 mipmap、导出后仍可用）；未导入时直接读 PNG 字节兜底
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		# 素材缺失/读不到时兜底：纯色方块，保证不崩
		var fallback := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(0.88, 0.78, 0.62))
		tex = ImageTexture.create_from_image(fallback)

	var node := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = 0.02
	sprite.position = Vector3(0, 1.0, 0)   # 贴图中心上移，底部贴地
	node.add_child(sprite)
	return node


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
	# 指标悬停小窗：暂停/弹层时它自己会收起来，所以放在 _paused 提前返回之前
	_update_metric_tip()
	if _paused:
		return
	# 开场 PPT 计时：不按键则 8 秒自动过一张
	if _intro_playing:
		_intro_elapsed += delta
		if _intro_elapsed >= INTRO_SLIDE_SEC:
			_advance_intro()
	_process_birds(delta)
	_process_plants_sway()
	_process_boats(delta)
	_update_card_hover(delta)
	_process_deck_gyro(delta)
	_update_sort_cooldown()
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
			# 社区信任：亮灯的暖色 / 熄灭的暗色（贴图用 modulate 调明暗）
			slot["sprite"].modulate = Color(1.0, 1.0, 1.0) if i < lit else Color(0.55, 0.53, 0.48)


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
	_build_pause_menu()
	_build_crisis_alert()
	_build_warn_history(canvas)
	_build_deck_ui(canvas)
	_build_deck_viewer()
	_build_metric_tip(canvas)   # 最后加：小窗要画在 HUD 所有面板之上


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

	# 很淡的压暗：镜头拉远后沙盘全景仍然看得见，开始页不遮景
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.05, 0.34)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)

	# --- 右上角：标题 ---
	var title := _make_label("保卫鄱阳湖", 48, Color(1, 0.9, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 1.0
	title.anchor_right = 1.0
	title.offset_left = -640.0
	title.offset_right = -56.0
	title.offset_top = 32.0
	title.offset_bottom = 116.0
	menu_root.add_child(title)

	# --- 居中容器：留给技能树（天赋树）面板 ---
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)

	# --- 左下角：选项列（逐级展开：主选项 → 难度 → 种子）---
	menu_col = VBoxContainer.new()
	menu_col.anchor_left = 0.0
	menu_col.anchor_right = 0.0
	menu_col.anchor_top = 1.0
	menu_col.anchor_bottom = 1.0
	menu_col.offset_left = 72.0
	menu_col.offset_right = 404.0
	menu_col.offset_top = -430.0
	menu_col.offset_bottom = -60.0
	menu_col.alignment = BoxContainer.ALIGNMENT_END
	menu_col.add_theme_constant_override("separation", 8)
	menu_root.add_child(menu_col)

	# 一级：新游戏 / 继续游戏
	menu_start_btn = _make_button("新游戏", _on_title_start, 26)
	menu_start_btn.custom_minimum_size = Vector2(0, 54)
	menu_col.add_child(menu_start_btn)

	menu_continue_btn = _make_button("继续游戏", _on_continue_pressed, 22)
	menu_continue_btn.custom_minimum_size = Vector2(0, 50)
	menu_continue_btn.visible = false
	menu_col.add_child(menu_continue_btn)

	# 二级：难度（点「开始」后出现在它正下方）
	menu_easy_btn = _make_button("简单模式", _on_difficulty_easy, 20)
	menu_easy_btn.custom_minimum_size = Vector2(0, 46)
	menu_easy_btn.visible = false
	menu_col.add_child(menu_easy_btn)

	menu_normal_btn = _make_button("普通模式", _on_difficulty_normal, 20)
	menu_normal_btn.custom_minimum_size = Vector2(0, 46)
	menu_normal_btn.visible = false
	menu_col.add_child(menu_normal_btn)

	menu_hard_btn = _make_button("困难模式", _on_difficulty_hard, 20)
	menu_hard_btn.custom_minimum_size = Vector2(0, 46)
	menu_hard_btn.visible = false
	menu_col.add_child(menu_hard_btn)

	# 三级：填写种子
	menu_mode_label = _make_label("模式：简单", 14, Color(0.82, 0.86, 0.9))
	menu_mode_label.visible = false
	menu_col.add_child(menu_mode_label)

	menu_seed_label = _make_label("留空或 0 则随机", 14, Color(0.9, 0.92, 0.94))
	menu_seed_label.visible = false
	menu_col.add_child(menu_seed_label)

	seed_input = LineEdit.new()
	seed_input.add_theme_font_size_override("font_size", _snap_px(18))
	seed_input.custom_minimum_size = Vector2(0, 42)
	seed_input.placeholder_text = "种子"
	seed_input.add_theme_color_override("font_placeholder_color", Color(0.85, 0.88, 0.90, 0.35))
	seed_input.visible = false
	menu_col.add_child(seed_input)

	menu_hint = _make_label("", 12, Color(1, 0.6, 0.5))
	menu_col.add_child(menu_hint)

	menu_seed_start_btn = _make_button("开始游戏", _on_start_pressed, 22)
	menu_seed_start_btn.custom_minimum_size = Vector2(0, 50)
	menu_seed_start_btn.visible = false
	menu_col.add_child(menu_seed_start_btn)

	# 返回上一层（难度 / 种子环节可见）
	menu_back_btn = _make_button("返回", _on_menu_back, 16)
	menu_back_btn.custom_minimum_size = Vector2(0, 38)
	menu_back_btn.visible = false
	menu_col.add_child(menu_back_btn)

	# 一级：其余选项（设置与制作人员暂未实现效果）
	menu_talent_btn = _make_button("技能树", _show_talent_panel, 18)
	menu_talent_btn.custom_minimum_size = Vector2(0, 44)
	menu_col.add_child(menu_talent_btn)

	menu_settings_btn = _make_button("设置", _show_settings_panel, 18)
	menu_settings_btn.custom_minimum_size = Vector2(0, 44)
	menu_col.add_child(menu_settings_btn)

	menu_changelog_btn = _make_button("更新日志", _show_changelog_panel, 18)
	menu_changelog_btn.custom_minimum_size = Vector2(0, 44)
	menu_col.add_child(menu_changelog_btn)

	menu_credits_btn = _make_button("制作人员", _show_credits_panel, 18)
	menu_credits_btn.custom_minimum_size = Vector2(0, 44)
	menu_col.add_child(menu_credits_btn)

	menu_quit_btn = _make_button("退出", _on_menu_quit, 18)
	menu_quit_btn.custom_minimum_size = Vector2(0, 44)
	menu_col.add_child(menu_quit_btn)

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

	var t_scroll := ScrollContainer.new()
	t_scroll.custom_minimum_size = Vector2(0, 380)
	t_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	kvb.add_child(t_scroll)

	talent_list = VBoxContainer.new()
	talent_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talent_list.add_theme_constant_override("separation", 6)
	t_scroll.add_child(talent_list)

	talent_unlock_btn = _make_button("点亮下一个天赋", _on_talent_unlock, 16)
	talent_unlock_btn.custom_minimum_size = Vector2(0, 44)
	kvb.add_child(talent_unlock_btn)

	var t_back := _make_button("返回", _on_talent_back, 16)
	t_back.custom_minimum_size = Vector2(0, 40)
	kvb.add_child(t_back)

	# --- 设置面板 ---
	menu_settings_panel = PanelContainer.new()
	menu_settings_panel.custom_minimum_size = Vector2(400, 0)
	_panel_style(menu_settings_panel, Color(0.20, 0.14, 0.09, 0.97))
	menu_settings_panel.visible = false
	center.add_child(menu_settings_panel)

	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 12)
	menu_settings_panel.add_child(svb)

	var s_title := _make_label("设置", 24, Color(1, 0.9, 0.55))
	s_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svb.add_child(s_title)

	var s_sep := HSeparator.new()
	svb.add_child(s_sep)

	# 音量调节
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	svb.add_child(vol_row)
	var vol_lbl := _make_label("音量", 16, Color(0.82, 0.86, 0.9))
	vol_row.add_child(vol_lbl)
	audio_volume_slider = HSlider.new()
	audio_volume_slider.min_value = 0
	audio_volume_slider.max_value = 100
	audio_volume_slider.step = 1
	audio_volume_slider.value = bgm_volume * 100
	audio_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_volume_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(audio_volume_slider)
	audio_volume_label = _make_label("音量：%d%%" % int(bgm_volume * 100), 14, Color(1, 0.95, 0.6))
	vol_row.add_child(audio_volume_label)

	# 切换 BGM
	bgm_switch_btn = _make_button("", _on_switch_bgm, 16)
	bgm_switch_btn.custom_minimum_size = Vector2(0, 44)
	svb.add_child(bgm_switch_btn)
	_update_bgm_btn()

	var replay_btn := _make_button("重新观看开场动画", _on_replay_intro, 20)
	replay_btn.custom_minimum_size = Vector2(0, 52)
	svb.add_child(replay_btn)

	var s_back := _make_button("返回", _on_settings_back, 16)
	s_back.custom_minimum_size = Vector2(0, 40)
	svb.add_child(s_back)

	# --- 制作人员面板 ---
	menu_credits_panel = PanelContainer.new()
	menu_credits_panel.custom_minimum_size = Vector2(420, 0)
	_panel_style(menu_credits_panel, Color(0.20, 0.14, 0.09, 0.97))
	menu_credits_panel.visible = false
	center.add_child(menu_credits_panel)

	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 10)
	menu_credits_panel.add_child(cvb)

	var c_title := _make_label("制作人员", 24, Color(1, 0.9, 0.55))
	c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvb.add_child(c_title)

	var c_sep := HSeparator.new()
	cvb.add_child(c_sep)

	var credits := [
		["策划", "QQQi_ZZZhe"],
		["主程 / 配乐", "Kanshin"],
		["美术", "C3L1K1N4"],
		["林学专家", "Oliveira"],
	]
	for e in credits:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		cvb.add_child(row)
		var role_l := _make_label(str(e[0]) + "：", 16, Color(0.72, 0.76, 0.80))
		row.add_child(role_l)
		var name_l := _make_label(str(e[1]), 16, Color(0.96, 0.94, 0.88))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_l)

	var c_back := _make_button("返回", _on_credits_back, 16)
	c_back.custom_minimum_size = Vector2(0, 40)
	cvb.add_child(c_back)

	# --- 更新日志面板 ---
	menu_changelog_panel = PanelContainer.new()
	menu_changelog_panel.custom_minimum_size = Vector2(580, 0)
	_panel_style(menu_changelog_panel, Color(0.20, 0.14, 0.09, 0.97))
	menu_changelog_panel.visible = false
	center.add_child(menu_changelog_panel)

	var gvb := VBoxContainer.new()
	gvb.add_theme_constant_override("separation", 10)
	menu_changelog_panel.add_child(gvb)

	var g_title := _make_label("更新日志", 24, Color(1, 0.9, 0.55))
	g_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gvb.add_child(g_title)

	var g_sub := _make_label("当前版本 %s" % Changelog.CURRENT, 14, Color(0.72, 0.76, 0.80))
	g_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gvb.add_child(g_sub)

	var g_sep := HSeparator.new()
	gvb.add_child(g_sep)

	# 必须用 ScrollContainer：日志只会越写越长，老弹窗系统不滚动会顶穿窗口
	var g_scroll := ScrollContainer.new()
	g_scroll.custom_minimum_size = Vector2(540, 360)
	g_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gvb.add_child(g_scroll)

	var g_col := VBoxContainer.new()
	g_col.add_theme_constant_override("separation", 12)
	g_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_scroll.add_child(g_col)

	_build_changelog_rows(g_col)

	var g_back := _make_button("返回", _on_changelog_back, 16)
	g_back.custom_minimum_size = Vector2(0, 40)
	gvb.add_child(g_back)


## 把 Changelog.RELEASES 渲染进面板 —— 以后加版本只改 scripts/changelog.gd，这里不用动
func _build_changelog_rows(col: VBoxContainer) -> void:
	for rel in Changelog.RELEASES:
		var v_head := _make_label("v%s · %s" % [str(rel["version"]), str(rel["title"])], 19, Color(1, 0.88, 0.55))
		v_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 标题写长了要能折行，不然会被裁
		v_head.custom_minimum_size = Vector2(520, 0)
		col.add_child(v_head)
		col.add_child(_make_label(str(rel["date"]), 13, Color(0.72, 0.76, 0.80)))
		for sec in rel["sections"]:
			col.add_child(_make_label("◆ " + str(sec["head"]), 16, Color(0.62, 0.82, 1.0)))
			for item in sec["items"]:
				var body := RichTextLabel.new()
				body.bbcode_enabled = false
				body.fit_content = true
				body.scroll_active = false
				body.custom_minimum_size = Vector2(520, 0)
				body.add_theme_font_size_override("normal_font_size", _snap_px(14))
				body.add_theme_color_override("default_color", Color(0.92, 0.90, 0.86))
				body.text = "· " + str(item)
				col.add_child(body)


# ==================== 开场像素 PPT（Undertale 风） ====================
func _is_first_play() -> bool:
	return not FileAccess.file_exists("user://intro_seen")


func _mark_intro_seen() -> void:
	var f := FileAccess.open("user://intro_seen", FileAccess.WRITE)
	if f != null:
		f.close()


## 多色像素画：palette 为 字符->颜色，其余视为透明
func _pixel_art(grid: String, palette: Dictionary) -> ImageTexture:
	var rows: Array = []
	for r in grid.split("\n"):
		var line: String = (r as String).strip_edges()
		if line != "":
			rows.append(line)
	var h := rows.size()
	var w := (rows[0] as String).length()   # 以首行为准，长行截断、短行补透明
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var line: String = rows[y]
		for x in w:
			var ch: String = line[x] if x < line.length() else " "
			img.set_pixel(x, y, palette.get(ch, Color(0, 0, 0, 0)))
	return ImageTexture.create_from_image(img)


func _build_intro() -> void:
	intro_layer = CanvasLayer.new()
	intro_layer.layer = 30
	add_child(intro_layer)
	intro_root = Control.new()
	intro_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_layer.add_child(intro_root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.07, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_root.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 80
	col.offset_right = -80
	col.offset_top = 30
	col.offset_bottom = -30
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_root.add_child(col)
	intro_col = col
	intro_image = TextureRect.new()
	intro_image.custom_minimum_size = Vector2(320, 192)
	intro_image.stretch_mode = TextureRect.STRETCH_SCALE
	intro_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	intro_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	intro_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	intro_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(intro_image)
	intro_title = _make_label("", 30, Color(1, 0.9, 0.55))
	intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(intro_title)
	intro_body = _make_label("", 20, Color(0.92, 0.94, 0.95))
	intro_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	intro_body.add_theme_constant_override("outline_size", 3)
	col.add_child(intro_body)
	intro_hint = _make_label("回车 继续　·　ESC 跳过", 13, Color(0.55, 0.6, 0.65))
	intro_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(intro_hint)


func _show_intro() -> void:
	if intro_root == null:
		_build_intro()
	intro_slides = _make_intro_slides()
	intro_index = 0
	_intro_playing = true
	_intro_elapsed = 0.0
	_intro_advancing = false
	intro_layer.visible = true
	_render_intro_slide()


func _render_intro_slide() -> void:
	_intro_elapsed = 0.0
	var slide: Dictionary = intro_slides[intro_index]
	intro_image.texture = _pixel_art(slide["grid"], slide["palette"])
	intro_title.text = slide["title"]
	intro_body.text = slide["body"]
	# 淡入
	intro_col.modulate.a = 0.0
	var tw := intro_col.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(intro_col, "modulate:a", 1.0, 0.45)


func _advance_intro() -> void:
	if _intro_advancing:
		return
	_intro_advancing = true
	# 淡出，完成后再切下一张 / 结束
	var tw := intro_col.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(intro_col, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		_intro_advancing = false
		if not _intro_playing:
			return  # 淡出期间已被 ESC 跳过
		intro_index += 1
		if intro_index >= intro_slides.size():
			_finish_intro()
		else:
			_render_intro_slide())


func _finish_intro() -> void:
	_intro_playing = false
	_intro_advancing = false
	intro_layer.visible = false
	_mark_intro_seen()
	_show_menu()


func _make_intro_slides() -> Array:
	return [
		{
			"title": "鄱阳湖",
			"body": "中国第一大淡水湖，\n也是亚洲最重要的候鸟越冬地之一。",
			"palette": {
				"S": Color(0.55, 0.78, 0.92), "Y": Color(0.98, 0.85, 0.36),
				"B": Color(0.96, 0.96, 0.95), "W": Color(0.30, 0.62, 0.80),
				"w": Color(0.50, 0.76, 0.90), "D": Color(0.16, 0.42, 0.62),
				"G": Color(0.44, 0.72, 0.44), "g": Color(0.28, 0.54, 0.32),
				"r": Color(0.40, 0.55, 0.34),
			},
			"grid": """SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSYYYYYYSSS
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSYYYYYYYYSS
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSYYYYYYYYSS
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSYYYYYYSSS
SSSSSSSSBSSSSSSSSSSSSBSSSSSSSSSSSSSSSSSS
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWwwwwwwWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWwwWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG
rGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrG
rGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrGrG
gggggggggggggggggggggggggggggggggggggggg
gggggggggggggggggggggggggggggggggggggggg
gggggggggggggggggggggggggggggggggggggggg""",
		},
		{
			"title": "危机逼近",
			"body": "围垦、污染、干旱……\n湖水缩减，候鸟与鱼类正失去家园。",
			"palette": {
				"K": Color(0.10, 0.12, 0.15), "R": Color(0.85, 0.25, 0.22),
				"E": Color(0.52, 0.40, 0.28), "e": Color(0.38, 0.28, 0.20),
				"W": Color(0.28, 0.48, 0.60),
			},
			"grid": """KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKRRRRRRRRRKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKRRRRRRRRRRRKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKRRRRRRRRRKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEEEEEEEeEEEEEEEEEEEEEEEEEEEEEEeEEEEEEEE
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEeEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEeEEEE
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEWWWWWWEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEWWWWWWEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEEWWWWEEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEEEEEeEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
eEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
eEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
eEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE""",
		},
		{
			"title": "你",
			"body": "你被任命为鄱阳湖\n新一任湖区管理员。",
			"palette": {
				"S": Color(0.55, 0.78, 0.92), "P": Color(0.92, 0.76, 0.62),
				"H": Color(0.25, 0.55, 0.30), "C": Color(0.30, 0.50, 0.70),
				"c": Color(0.22, 0.38, 0.55), "Y": Color(0.95, 0.80, 0.30),
				"G": Color(0.44, 0.72, 0.44),
			},
			"grid": """SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSHHHHHHHSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSHHHHHHHHHHSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSPPPPPPSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSPPPPPPPPSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSPPPPPPPPSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSPPPPPPSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSCCCCCCSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSCCCCCCCCCCSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSCCCCYYCCCCSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSCCCCCCCCCCSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSCCCCCCCCCCSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSCCCCCCCCCCSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSccccccccccSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSccccccccccSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSCCCCCCSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSCCCCCCSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSCCCCCCSSSSSSSSSSSSSSSS
SSSSSSSSSSSSSSSSSSccccccSSSSSSSSSSSSSSSS
GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG
GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG""",
		},
		{
			"title": "你的使命",
			"body": "16 个回合内，平衡资金与生态，\n守护水位、植被、水质、鱼类、鸟类与社区。",
			"palette": {
				"K": Color(0.15, 0.18, 0.25), "O": Color(0.95, 0.60, 0.25),
				"R": Color(0.90, 0.40, 0.25), "Y": Color(0.98, 0.85, 0.40),
				"W": Color(0.30, 0.62, 0.80), "D": Color(0.16, 0.42, 0.62),
			},
			"grid": """KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKYYKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKOOOOOOKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKOOOOOOOOKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKOOOOOOOOKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKROOOOOOOKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKRROOOOOKKKKKKKKKKKKKKKKK
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWOOOWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWRRRRWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD""",
		},
	]


func _show_menu() -> void:
	menu_root.visible = true
	menu_col.visible = true
	menu_talent_panel.visible = false
	menu_settings_panel.visible = false
	menu_credits_panel.visible = false
	menu_changelog_panel.visible = false
	_set_hud_visible(false)   # 开始页是干净的全景：HUD 让位给标题与选项
	_menu_state(0)
	_set_menu_camera(true)
	_roll_creeper_visibility()   # 苦力怕彩蛋按概率出现


## 开始页期间隐藏 HUD（左上信息栏 / 右上生态指标 / 事件横幅 / 右下按钮）
func _set_hud_visible(v: bool) -> void:
	var canvas := get_node_or_null("UICanvas")
	if canvas:
		canvas.visible = v
	if not v:
		_close_warn_history()   # 回主菜单/开始页时，别把回顾面板留在屏幕上


## 开始页层级：0 = 主选项 / 1 = 难度 / 2 = 种子
func _menu_state(state: int) -> void:
	var main_level := state == 0
	menu_start_btn.visible = main_level          # 新游戏
	menu_continue_btn.visible = main_level and has_save()  # 继续游戏（有存档才显示）
	menu_talent_btn.visible = main_level
	menu_settings_btn.visible = main_level
	menu_credits_btn.visible = main_level
	menu_changelog_btn.visible = main_level
	menu_quit_btn.visible = main_level

	menu_easy_btn.visible = state == 1
	menu_normal_btn.visible = state == 1
	menu_hard_btn.visible = state == 1

	var seed_level := state == 2
	menu_mode_label.visible = seed_level
	menu_seed_label.visible = seed_level
	seed_input.visible = seed_level
	menu_seed_start_btn.visible = seed_level

	menu_back_btn.visible = state != 0
	menu_hint.text = ""
	if seed_level:
		seed_input.grab_focus()


func _on_title_start() -> void:
	_menu_state(1)


func _on_difficulty_easy() -> void:
	GameState.difficulty = GameState.Difficulty.EASY
	menu_mode_label.text = "模式：简单"
	_update_threshold_lines()
	_menu_state(2)


func _on_difficulty_normal() -> void:
	GameState.difficulty = GameState.Difficulty.NORMAL
	menu_mode_label.text = "模式：普通"
	_update_threshold_lines()
	_menu_state(2)


func _on_difficulty_hard() -> void:
	GameState.difficulty = GameState.Difficulty.HARD
	menu_mode_label.text = "模式：困难"
	_update_threshold_lines()
	_menu_state(2)


## 返回上一层：种子 → 难度，难度 → 主选项
func _on_menu_back() -> void:
	if menu_seed_start_btn.visible:
		_menu_state(1)
	else:
		_menu_state(0)


## 设置 / 制作人员：入口先摆上，具体效果待做
func _on_menu_placeholder() -> void:
	_flash_menu_hint(menu_hint, "（暂未开放）")


## 菜单提示：显示后 3 秒自动消失
func _flash_menu_hint(label: Label, text: String) -> void:
	label.text = text
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func() -> void:
		if label.text == text:
			label.text = "")


## 退出：直接关闭游戏窗口
func _on_menu_quit() -> void:
	get_tree().quit()


func _show_talent_panel() -> void:
	menu_col.visible = false
	menu_settings_panel.visible = false
	menu_credits_panel.visible = false
	menu_changelog_panel.visible = false
	menu_talent_panel.visible = true
	_refresh_talent_panel()


func _on_talent_back() -> void:
	menu_talent_panel.visible = false
	menu_col.visible = true
	_menu_state(0)


func _show_settings_panel() -> void:
	menu_col.visible = false
	menu_talent_panel.visible = false
	menu_credits_panel.visible = false
	menu_settings_panel.visible = true


func _on_settings_back() -> void:
	menu_settings_panel.visible = false
	menu_col.visible = true
	_menu_state(0)


func _show_credits_panel() -> void:
	menu_col.visible = false
	menu_talent_panel.visible = false
	menu_settings_panel.visible = false
	menu_changelog_panel.visible = false
	menu_credits_panel.visible = true


func _on_credits_back() -> void:
	menu_credits_panel.visible = false
	menu_col.visible = true
	_menu_state(0)


func _show_changelog_panel() -> void:
	menu_col.visible = false
	menu_talent_panel.visible = false
	menu_settings_panel.visible = false
	menu_credits_panel.visible = false
	menu_changelog_panel.visible = true


func _on_changelog_back() -> void:
	menu_changelog_panel.visible = false
	menu_col.visible = true
	_menu_state(0)


## 设置里重播开场动画：隐藏菜单后重新播放（播完自动回主菜单）
func _on_replay_intro() -> void:
	menu_settings_panel.visible = false
	menu_root.visible = false
	_show_intro()


# ==================== 音频 / BGM ====================
## 读取音量与 BGM 选择（无存档则用默认）
func _load_audio_settings() -> void:
	if not FileAccess.file_exists(AUDIO_SETTINGS_PATH):
		return
	var f := FileAccess.open(AUDIO_SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data is Dictionary:
		bgm_index = clampi(int(data.get("bgm_index", 0)), 0, BGM_PATHS.size() - 1)
		bgm_volume = clampf(float(data.get("bgm_volume", 0.8)), 0.0, 1.0)


func _save_audio_settings() -> void:
	var data := {"bgm_index": bgm_index, "bgm_volume": bgm_volume}
	var f := FileAccess.open(AUDIO_SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


## 建立 BGM 播放器并开始循环播放
func _setup_bgm() -> void:
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	_apply_bgm()
	bgm_player.finished.connect(func() -> void: bgm_player.play())  # 循环


## 载入当前 BGM 与音量并播放
func _apply_bgm() -> void:
	var stream: AudioStream = load(BGM_PATHS[bgm_index])
	if stream is AudioStreamMP3:
		stream.loop = true
	bgm_player.stream = stream
	bgm_player.volume_db = linear_to_db(maxf(bgm_volume, 0.001))
	bgm_player.play()


## 音量滑动条回调
func _on_volume_changed(value: float) -> void:
	bgm_volume = value / 100.0
	bgm_volume = clampf(bgm_volume, 0.0, 1.0)
	bgm_player.volume_db = linear_to_db(maxf(bgm_volume, 0.001))
	_save_audio_settings()
	_sync_audio_ui()


## 切换 BGM（在两个曲目间循环）
func _on_switch_bgm() -> void:
	bgm_index = (bgm_index + 1) % BGM_PATHS.size()
	_apply_bgm()
	_save_audio_settings()
	_sync_audio_ui()


## 同步两处音频 UI（主菜单设置 + 暂停设置）
func _sync_audio_ui() -> void:
	var pct := int(bgm_volume * 100)
	if audio_volume_slider != null:
		audio_volume_slider.set_value_no_signal(bgm_volume * 100)
	if audio_volume_label != null:
		audio_volume_label.text = "音量：%d%%" % pct
	if pause_volume_slider != null:
		pause_volume_slider.set_value_no_signal(bgm_volume * 100)
	if pause_volume_label != null:
		pause_volume_label.text = "音量：%d%%" % pct
	_update_bgm_btn()


## 刷新切换 BGM 按钮文字（两处）
func _update_bgm_btn() -> void:
	var txt := "切换 BGM（当前：%s）" % BGM_NAMES[bgm_index]
	if bgm_switch_btn != null:
		bgm_switch_btn.text = txt
	if pause_bgm_btn != null:
		pause_bgm_btn.text = txt


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
	talent_unlock_btn.text = "点亮下一个天赋（%d 点）" % Talents.next_cost()
	talent_unlock_btn.disabled = not (Talents.points >= Talents.next_cost() and Talents.next_talent_id() != "")


func _hide_menu() -> void:
	menu_root.visible = false
	_set_hud_visible(true)
	_set_menu_camera(false)


# ==================== 暂停 / 存档 ====================
## 游戏进行中按下 ESC：弹出暂停菜单（继续游戏 / 设置 / 退出至主菜单）
func _unhandled_input(event: InputEvent) -> void:
	if _intro_playing:
		# 开场 PPT：回车/点击下一张，ESC 直接跳过
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_finish_intro()
			elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_advance_intro()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_advance_intro()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_pause()


func _can_pause() -> bool:
	return _playing and not GameState.game_over and not crisis_root.visible


func _toggle_pause() -> void:
	if not _can_pause():
		return
	if _paused:
		_resume_game()
	else:
		_pause_game()


func _pause_game() -> void:
	_paused = true
	pause_hint.text = ""
	pause_settings_panel.visible = false
	pause_panel.visible = true
	pause_root.visible = true


func _resume_game() -> void:
	_paused = false
	pause_root.visible = false


func _on_pause_settings() -> void:
	pause_panel.visible = false
	pause_settings_panel.visible = true
	_sync_audio_ui()   # 打开时同步主菜单设置


func _on_pause_settings_back() -> void:
	pause_settings_panel.visible = false
	pause_panel.visible = true


## 退出至主菜单：先存档，保留本局进度
func _on_pause_exit() -> void:
	save_game()
	_paused = false
	pause_root.visible = false
	popup_root.visible = false
	hand_panel.visible = false
	bottom_right.visible = false
	_playing = false
	_show_menu()


## 主菜单「继续游戏」：读档续玩
func _on_continue_pressed() -> void:
	if not load_game():
		menu_hint.text = "没有可继续的进度"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func _clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func save_game() -> void:
	var hand_ids: Array = []
	var selected_ids: Array = []
	for info in card_infos:
		hand_ids.append(info["card_id"])
		if info["selected"]:
			selected_ids.append(info["card_id"])
	var data := {
		"state": GameState.serialize(),
		"hand_ids": hand_ids,
		"selected_ids": selected_ids,
		"phase": _current_phase,
		"event_text": _current_event,
	}
	if _current_phase != "allocate":
		data["popup"] = {
			"title": popup_title.text,
			"body": popup_body.text,
			"button": popup_button.text,
		}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		return false
	GameState.load_state(data.get("state", {}))
	_update_threshold_lines()
	_hide_menu()
	_playing = true
	_paused = false
	_current_event = str(data.get("event_text", ""))
	_update_hud()
	_update_3d()
	var phase: String = str(data.get("phase", "allocate"))
	_current_phase = phase
	var popup: Dictionary = data.get("popup", {})
	match phase:
		"popup_event":
			_show_popup("第 %d 回合 · 事件" % GameState.turn, str(popup.get("body", "")), "开始分配资金", _enter_allocate)
		"popup_knowledge":
			_show_popup(str(popup.get("title", "")), str(popup.get("body", "")), "收下（继续）", _on_resolve_continue)
		"popup_settlement":
			_show_popup("结算反馈", str(popup.get("body", "")), "继续", _on_resolve_continue)
		_:
			_restore_hand(data)
	return true


## 恢复分配阶段：重建手牌并还原选中状态
func _restore_hand(data: Dictionary) -> void:
	var hand_ids: Array = data.get("hand_ids", [])
	var selected_ids: Array = data.get("selected_ids", [])
	current_hand = []
	for cid in hand_ids:
		var card: Dictionary = GameState._find_card(cid)
		if not card.is_empty():
			current_hand.append(card)
	play_deal_anim = false
	_build_hand_panel()
	for info in card_infos:
		if info["card_id"] in selected_ids:
			info["selected"] = true
			_apply_gold_frame(info["panel"])
	hand_panel.visible = true
	bottom_right.visible = true
	_slide_side_panels(false)
	_update_selected_label()


## 暂停菜单：盖在 HUD 与沙盘之上的独立层
func _build_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = 20
	add_child(layer)

	pause_root = Control.new()
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.visible = false
	layer.add_child(pause_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(center)

	pause_panel = PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(360, 0)
	_panel_style(pause_panel, Color(0.24, 0.17, 0.11, 0.96))
	center.add_child(pause_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	pause_panel.add_child(pv)

	var t := _make_label("暂停", 30, Color(1, 0.9, 0.55))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(t)

	pause_hint = _make_label("", 13, Color(1, 0.6, 0.5))
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pause_hint)

	var b_resume := _make_button("继续游戏", _resume_game, 22)
	b_resume.custom_minimum_size = Vector2(0, 52)
	pv.add_child(b_resume)

	var b_settings := _make_button("设置", _on_pause_settings, 18)
	b_settings.custom_minimum_size = Vector2(0, 46)
	pv.add_child(b_settings)

	var b_exit := _make_button("退出至主菜单", _on_pause_exit, 18)
	b_exit.custom_minimum_size = Vector2(0, 46)
	pv.add_child(b_exit)

	# --- 暂停设置面板（与主菜单设置同步） ---
	pause_settings_panel = PanelContainer.new()
	pause_settings_panel.custom_minimum_size = Vector2(400, 0)
	_panel_style(pause_settings_panel, Color(0.24, 0.17, 0.11, 0.96))
	pause_settings_panel.visible = false
	center.add_child(pause_settings_panel)

	var psv := VBoxContainer.new()
	psv.add_theme_constant_override("separation", 12)
	pause_settings_panel.add_child(psv)

	var ps_title := _make_label("设置", 24, Color(1, 0.9, 0.55))
	ps_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	psv.add_child(ps_title)

	var ps_sep := HSeparator.new()
	psv.add_child(ps_sep)

	var pvol_row := HBoxContainer.new()
	pvol_row.add_theme_constant_override("separation", 8)
	psv.add_child(pvol_row)
	var pvol_lbl := _make_label("音量", 16, Color(0.82, 0.86, 0.9))
	pvol_row.add_child(pvol_lbl)
	pause_volume_slider = HSlider.new()
	pause_volume_slider.min_value = 0
	pause_volume_slider.max_value = 100
	pause_volume_slider.step = 1
	pause_volume_slider.value = bgm_volume * 100
	pause_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_volume_slider.value_changed.connect(_on_volume_changed)
	pvol_row.add_child(pause_volume_slider)
	pause_volume_label = _make_label("音量：%d%%" % int(bgm_volume * 100), 14, Color(1, 0.95, 0.6))
	pvol_row.add_child(pause_volume_label)

	pause_bgm_btn = _make_button("", _on_switch_bgm, 16)
	pause_bgm_btn.custom_minimum_size = Vector2(0, 44)
	psv.add_child(pause_bgm_btn)

	var ps_back := _make_button("返回", _on_pause_settings_back, 16)
	ps_back.custom_minimum_size = Vector2(0, 40)
	psv.add_child(ps_back)

	_update_bgm_btn()   # 同步两个切换按钮文字


# ==================== 危机警示 ====================
## 危机预警信号：入队，逐个弹出大红警示
func _on_crisis_warn(crisis: Dictionary) -> void:
	_crisis_queue.append({"crisis": crisis, "is_warning": true})
	_process_crisis_queue()


## 危机爆发信号：入队，逐个弹出大红警示
func _on_crisis_hit(crisis: Dictionary) -> void:
	_crisis_queue.append({"crisis": crisis, "is_warning": false})
	_process_crisis_queue()


func _process_crisis_queue() -> void:
	if GameState.game_over:
		return  # 已判负：失败报告优先，危机弹层不再抢屏
	if _crisis_queue.is_empty() or crisis_root.visible:
		return
	var item: Dictionary = _crisis_queue.pop_front()
	_show_crisis_alert(item["crisis"], item["is_warning"])


## 玩家点掉危机弹窗：还有下一个危机就继续弹，否则（无事件弹窗时）进入分配
func _on_crisis_dismiss() -> void:
	crisis_root.visible = false
	if not _crisis_queue.is_empty():
		_process_crisis_queue()
	elif not popup_root.visible:
		_enter_allocate()


## 弹出危机警示：大红叹号 + 屏幕红闪 + 雷霆大字 + 详细说明
func _show_crisis_alert(crisis: Dictionary, is_warning: bool) -> void:
	var name: String = crisis["name"]
	crisis_title.text = name
	crisis_tag.text = "⚠ 危机预警" if is_warning else "⚠ 危机爆发"
	crisis_button.text = "知道了" if is_warning else "继续"
	crisis_body.text = _crisis_body_text(crisis, is_warning)
	# 危机同步到顶部横幅，关掉弹窗后仍可见
	_current_event = "⚠ %s：%s" % [("危机预警" if is_warning else "危机爆发"), name]
	_update_hud()

	crisis_root.visible = true
	# 淡红脉冲：起手轻轻亮一下，随后持续柔和脉冲（不再刺眼）
	crisis_dim.color.a = 0.28
	var pulse := crisis_dim.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(crisis_dim, "color:a", 0.10, 0.6)
	pulse.tween_property(crisis_dim, "color:a", 0.28, 0.6)
	# 像素感叹号：大小脉冲（像在跳动），动画保持不变
	crisis_icon.pivot_offset = crisis_icon.size * 0.5
	var tw := crisis_icon.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(crisis_icon, "scale", Vector2(1.22, 1.22), 0.45)
	tw.tween_property(crisis_icon, "scale", Vector2.ONE, 0.45)


## 危机警示正文：描述 + 「当前 xx 值较低，可能影响 xx」 + 应对建议
func _crisis_body_text(crisis: Dictionary, is_warning: bool) -> String:
	var c := _parse_cond(str(crisis.get("cond", "")))
	var metric := str(c.get("metric", ""))
	var mname := str(GameState.METRIC_NAMES.get(metric, metric))
	var cur := int(GameState.metrics.get(metric, 0))
	var op := str(c.get("op", "<"))
	var low_high := "偏低" if op in ["<", "<="] else "偏高"
	var threshold := int(c.get("threshold", 0))

	var effect_lines: Array = []
	for e in crisis.get("effects", []):
		effect_lines.append("· %s %+d" % [GameState.METRIC_NAMES.get(e["metric"], e["metric"]), int(e["delta"])])

	var body := ""
	if is_warning:
		body += "%s\n\n" % crisis["warn"]
		# 只在当前值真的落在危险侧时才引用警戒线，避免出现
		# 「当前水质 90（偏低，警戒线 55）」这种自相矛盾的提示
		if metric != "" and _cond_holds(cur, op, threshold):
			body += "[color=#ffb060]⚠ 当前%s %d（%s，警戒线 %d）[/color]\n\n" % [mname, cur, low_high, threshold]
		body += "[color=#ff9090]若未及时应对，下一回合可能造成：[/color]\n"
		body += "\n".join(effect_lines)
		var counters: Array = GameState.counter_ids_for(crisis)
		if not counters.is_empty():
			var names: Array = []
			for cid in counters:
				names.append(_card_name(cid))
			# 标签匹配后对策卡可能有 4~6 张，只列前 4 张，免得这段撑爆弹窗
			var shown: Array = names.slice(0, 4)
			var tail: String = "" if names.size() <= 4 else " 等 %d 张" % names.size()
			# 对策卡是「大概率入手」而不是必出（肉鸽要有没抽到的局面），文案不承诺保底
			body += "\n\n[color=#8fd0ff]应对建议（下批手牌里对策卡概率已提高，不保证到手）：优先打出「%s」%s[/color]" % [
				"」「".join(shown), tail]
	else:
		body += "%s\n\n" % crisis["hit"]
		body += "[color=#ff9090]本次已造成：[/color]\n"
		body += "\n".join(effect_lines)
	return body


## 解析危机 cond（如 "water_level < 45"）→ {metric, op, threshold}
func _parse_cond(cond: String) -> Dictionary:
	var parts := cond.strip_edges().split(" ")
	if parts.size() >= 3:
		return {"metric": parts[0], "op": parts[1], "threshold": int(parts[2])}
	return {}


## 当前值是否真的落在危机条件那一侧（安全区不报警）
func _cond_holds(cur: int, op: String, threshold: int) -> bool:
	match op:
		"<": return cur < threshold
		"<=": return cur <= threshold
		">": return cur > threshold
		">=": return cur >= threshold
		"==": return cur == threshold
	return false


## 危机警示弹层（盖在普通弹窗之上）
func _build_crisis_alert() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CrisisLayer"
	layer.layer = 5
	add_child(layer)

	crisis_root = Control.new()
	crisis_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	crisis_root.mouse_filter = Control.MOUSE_FILTER_STOP
	crisis_root.visible = false
	layer.add_child(crisis_root)

	crisis_dim = ColorRect.new()
	crisis_dim.color = Color(1.0, 0.55, 0.55, 0.22)   # 淡红，不再刺眼
	crisis_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	crisis_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	crisis_root.add_child(crisis_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	crisis_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	_panel_style(panel, Color(0.30, 0.12, 0.10, 0.97))
	center.add_child(panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)

	# 像素感叹号（贴图，最近邻放大保持锐利）
	var exclaim_grid := "..##..\n.#XX#.\n.#XX#.\n.#XX#.\n.#XX#.\n.#XX#.\n.#XX#.\n..##..\n......\n.#XX#.\n..##.."
	var exclaim_c := Color(1.0, 0.32, 0.28)
	crisis_icon = TextureRect.new()
	crisis_icon.texture = _pixel_icon(exclaim_grid, exclaim_c, exclaim_c.darkened(0.42), exclaim_c.lightened(0.25))
	crisis_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crisis_icon.stretch_mode = TextureRect.STRETCH_SCALE
	crisis_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crisis_icon.custom_minimum_size = Vector2(52, 96)
	crisis_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pv.add_child(crisis_icon)

	crisis_title = _make_label("", 44, Color(1.0, 0.30, 0.25))
	crisis_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crisis_title.add_theme_color_override("font_outline_color", Color(0.55, 0.0, 0.0, 0.85))
	crisis_title.add_theme_constant_override("outline_size", 8)
	pv.add_child(crisis_title)

	crisis_tag = _make_label("", 18, Color(1.0, 0.55, 0.45))
	crisis_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(crisis_tag)

	crisis_body = RichTextLabel.new()
	crisis_body.bbcode_enabled = true
	crisis_body.fit_content = true
	crisis_body.custom_minimum_size = Vector2(500, 0)
	crisis_body.add_theme_font_size_override("normal_font_size", _snap_px(16))
	crisis_body.add_theme_color_override("default_color", Color(0.98, 0.95, 0.92))
	pv.add_child(crisis_body)

	crisis_button = _make_button("知道了", _on_crisis_dismiss, 20)
	crisis_button.custom_minimum_size = Vector2(0, 50)
	pv.add_child(crisis_button)


# ==================== 危机预警回顾（P1）====================
## 顶部「预警回顾」条：预警弹窗关掉后信息收在这里，点一下能重看本局全部预警
func _build_warn_history(canvas: CanvasLayer) -> void:
	warn_bar = _make_button("", _open_warn_history, 13)
	warn_bar.anchor_left = 0.5
	warn_bar.anchor_right = 0.5
	warn_bar.offset_left = -240
	warn_bar.offset_right = 240
	warn_bar.offset_top = 34
	warn_bar.offset_bottom = 64
	warn_bar.clip_text = true
	warn_bar.tooltip_text = "点击重看本局全部危机预警"
	warn_bar.visible = false
	canvas.add_child(warn_bar)

	var layer := CanvasLayer.new()
	layer.name = "WarnLayer"
	layer.layer = 6   # 危机弹窗(5) 之上、主菜单(10) 之下
	add_child(layer)

	warn_panel_root = Control.new()
	warn_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	warn_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	warn_panel_root.visible = false
	layer.add_child(warn_panel_root)

	var warn_dim := ColorRect.new()   # 不叫 dim：类里已有一个 dim，重名会多一条 SHADOWED_VARIABLE 警告
	warn_dim.color = Color(0.04, 0.06, 0.08, 0.74)
	warn_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	warn_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	warn_panel_root.add_child(warn_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	warn_panel_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	_panel_style(panel, Color(0.16, 0.13, 0.10, 0.97))
	center.add_child(panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)

	var title := _make_label("本局危机预警回顾", 24, Color(1, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(title)

	warn_count_label = _make_label("", 14, Color(0.85, 0.88, 0.92))
	warn_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(warn_count_label)

	# 列表必须能滚：本局最多可能攒下 8~10 条，弹窗本体不滚动会顶穿窗口
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)

	warn_list_box = VBoxContainer.new()
	warn_list_box.add_theme_constant_override("separation", 8)
	warn_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(warn_list_box)

	var close_btn := _make_button("关闭", _close_warn_history, 18)
	close_btn.custom_minimum_size = Vector2(0, 46)
	pv.add_child(close_btn)


func _open_warn_history() -> void:
	if warn_panel_root == null:
		return
	_build_warn_rows()
	warn_panel_root.visible = true


func _close_warn_history() -> void:
	if warn_panel_root:
		warn_panel_root.visible = false


## 顶部那一条：显示最近一条预警，点开看全部
func _refresh_warn_bar() -> void:
	if warn_bar == null:
		return
	var rows: Array = GameState.warn_history
	if rows.is_empty():
		warn_bar.visible = false
		return
	var last: Dictionary = rows[rows.size() - 1]
	warn_bar.text = "⚠ 危机预警日志：%s（第 %d 回合）· 共 %d 条" % [
		_crisis_short_label(str(last["id"])), int(last["turn"]), rows.size()]
	warn_bar.visible = true


## 顶部预警条用的短名（比 METRIC_NAMES 更短，避免「沉水植被告急」这种读起来绕的串）
const WARN_SHORT_METRIC := {"vegetation": "植被", "fish": "鱼类", "birds": "候鸟", "community": "社区信任"}


## 危机的短标签，如「水位告急」「水质偏高」（由 cond 里的指标 + 方向推出来）
func _crisis_short_label(id: String) -> String:
	var c: Dictionary = GameState.crisis_by_id(id)
	if c.is_empty():
		return "危机"
	var pc := _parse_cond(str(c.get("cond", "")))
	var metric := str(pc.get("metric", ""))
	var nm := str(WARN_SHORT_METRIC.get(metric, GameState.METRIC_NAMES.get(metric, metric)))
	return nm + ("告急" if str(pc.get("op", "<")) in ["<", "<="] else "偏高")


func _build_warn_rows() -> void:
	for ch in warn_list_box.get_children():
		ch.queue_free()
	var rows: Array = GameState.warn_history
	warn_count_label.text = "共 %d 条（最新的在最上面）" % rows.size()
	if rows.is_empty():
		warn_list_box.add_child(_make_label("本局还没有出现过预警。", 16, Color(0.85, 0.88, 0.92)))
		return
	for i in range(rows.size() - 1, -1, -1):
		warn_list_box.add_child(_make_warn_row(rows[i]))


## 一条预警：第几回合 / 预警原文 / 当时的数值 / 后来有没有爆发 / 当时该打什么标签
func _make_warn_row(e: Dictionary) -> Control:
	var id := str(e["id"])
	var turn := int(e["turn"])
	var hit := int(e.get("hit_turn", -1))
	var c: Dictionary = GameState.crisis_by_id(id)
	var cname: String = str(c.get("name", id))
	var pc := _parse_cond(str(c.get("cond", "")))
	var metric := str(pc.get("metric", ""))
	var mname := str(GameState.METRIC_NAMES.get(metric, metric))
	var line := int(pc.get("threshold", 0))

	var panel := PanelContainer.new()
	_panel_style(panel, Color(0.13, 0.11, 0.09, 0.94))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(520, 0)
	body.add_theme_font_size_override("normal_font_size", _snap_px(14))
	body.add_theme_color_override("default_color", Color(0.94, 0.92, 0.88))

	var t := "[color=#ffb060]第 %d 回合 · ⚠ 危机预警：%s[/color]\n" % [turn, cname]
	t += "%s\n" % str(c.get("warn", ""))
	t += "当时：%s %d（警戒线 %d）\n" % [mname, int(e.get("value", 0)), line]
	if hit > 0:
		var eff: Array = []
		for ef in c.get("effects", []):
			eff.append("%s %+d" % [GameState.METRIC_NAMES.get(ef["metric"], ef["metric"]), int(ef["delta"])])
		t += "[color=#ff9090]→ 第 %d 回合已爆发：%s[/color]\n" % [hit, "、".join(eff)]
	else:
		t += "[color=#9aa0a6]→ 未爆发（本局在那之前就结束了）[/color]\n"
	# 沿用预警弹窗里的说法（「应对建议：优先打出「卡名」」），不暴露内部的标签名 ——
	# 「补水调度」「病害防控」这类标签玩家在别处根本看不到，写在日志里会显得割裂。
	var counters: Array = GameState.counter_ids_for(c)
	if not counters.is_empty():
		var names: Array = []
		for cid in counters:
			names.append(_card_name(cid))
		var shown: Array = names.slice(0, 3)
		var tail: String = "" if names.size() <= 3 else " 等 %d 张" % names.size()
		t += "[color=#8fd0ff]应对建议：优先打出「%s」%s[/color]" % ["」「".join(shown), tail]
	body.text = t
	panel.add_child(body)
	return panel


# ==================== 牌库（牌堆）UI ====================
## 生成主题像素牌背（湖水蓝 + 波浪横纹）
func _make_card_back_texture() -> Texture2D:
	var grid := """################
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
#XXooooooooooXX#
#XXXXXXXXXXXXXX#
################"""
	var main_c := Color(0.30, 0.52, 0.72)
	return _pixel_icon(grid, main_c, main_c.darkened(0.45), main_c.lightened(0.35))


## 牌堆：生态指标框下方，叠放三张牌背；悬停黄框+孔雀开屏，点击查看牌库
func _build_deck_ui(canvas: CanvasLayer) -> void:
	card_back_tex = _make_card_back_texture()

	deck_root = Control.new()
	deck_root.anchor_left = 1.0
	deck_root.anchor_top = 0.0
	deck_root.anchor_right = 1.0
	deck_root.anchor_bottom = 0.0
	deck_root.offset_left = -190
	deck_root.offset_right = -6
	deck_root.offset_top = 276
	deck_root.offset_bottom = 392
	deck_root.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(deck_root)

	# 黄色外框（悬停时显示，自绘贴牌形状）
	deck_border = Control.new()
	deck_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_border.visible = false
	deck_border.draw.connect(_on_deck_border_draw)
	deck_root.add_child(deck_border)

	# 叠放的三张牌背
	var stack_positions := [Vector2(58, 18), Vector2(60, 15), Vector2(62, 12)]
	for i in 3:
		var back := TextureRect.new()
		back.texture = card_back_tex
		back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.custom_minimum_size = Vector2(64, 86)
		back.size = Vector2(64, 86)
		back.position = stack_positions[i]
		back.pivot_offset = Vector2(32, 43)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_root.add_child(back)
		deck_backs.append(back)

	# 悬停 / 点击
	deck_root.mouse_entered.connect(_on_deck_mouse_entered)
	deck_root.mouse_exited.connect(_on_deck_mouse_exited)
	deck_root.gui_input.connect(_on_deck_gui_input)


func _on_deck_mouse_entered() -> void:
	_deck_hovered = true
	_fan_deck(true)
	# 展开动画结束后才显示黄框（途中不显示）
	var tw := create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(func() -> void:
		if _deck_hovered:
			deck_border.visible = true
			deck_border.queue_redraw())


func _on_deck_mouse_exited() -> void:
	_deck_hovered = false
	deck_border.visible = false
	_fan_deck(false)


## 孔雀开屏：悬停时三张牌背扇形展开，移开后收回
func _fan_deck(out: bool) -> void:
	var fan_positions := [Vector2(34, 26), Vector2(60, 8), Vector2(86, 26)]
	var fan_rotations := [-0.26, 0.0, 0.26]
	var stack_positions := [Vector2(58, 18), Vector2(60, 15), Vector2(62, 12)]
	for i in deck_backs.size():
		var back: TextureRect = deck_backs[i]
		var pos: Vector2 = fan_positions[i] if out else stack_positions[i]
		var rot: float = fan_rotations[i] if out else 0.0
		var tw := back.create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(back, "position", pos, 0.22)
		tw.parallel().tween_property(back, "rotation", rot, 0.22)


## 自绘黄框：给每张牌背各画一条贴牌黄边（严格贴着每张牌的形状）
func _on_deck_border_draw() -> void:
	for back in deck_backs:
		var corners := _card_corners(back)
		var pts := corners.duplicate()
		pts.append(corners[0])
		deck_border.draw_polyline(pts, Color(1.0, 0.85, 0.3), 3.0, true)


## 计算一张牌背（带旋转）的四个角点（deck_root 局部坐标）
func _card_corners(back: TextureRect) -> PackedVector2Array:
	var c := cos(back.rotation)
	var s := sin(back.rotation)
	var corners := PackedVector2Array()
	var locals: Array[Vector2] = [Vector2.ZERO, Vector2(back.size.x, 0), Vector2(back.size.x, back.size.y), Vector2(0, back.size.y)]
	for local in locals:
		var rel: Vector2 = local - back.pivot_offset
		var rotated := Vector2(rel.x * c - rel.y * s, rel.x * s + rel.y * c)
		corners.append(back.position + back.pivot_offset + rotated)
	return corners


func _on_deck_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_deck_viewer()


## 牌库查看器：全屏弹层，逐张发牌展示所有卡牌
func _build_deck_viewer() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DeckViewerLayer"
	layer.layer = 8
	add_child(layer)

	deck_viewer = Control.new()
	deck_viewer.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	deck_viewer.visible = false
	layer.add_child(deck_viewer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_viewer.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 70
	box.offset_right = -70
	box.offset_top = 40
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 12)
	deck_viewer.add_child(box)

	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 10)
	box.add_child(title_bar)

	var title := _make_label("全部卡牌", 28, Color(1, 0.9, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_bar.add_child(title)

	deck_sort_btn = _make_sort_button()
	title_bar.add_child(deck_sort_btn)
	_update_sort_btn()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	# 四周留内边距：顶部留足放大+漂浮的余量，避免顶行/左列卡被裁剪
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(margin)

	deck_viewer_grid = HFlowContainer.new()
	deck_viewer_grid.add_theme_constant_override("h_separation", 14)
	deck_viewer_grid.add_theme_constant_override("v_separation", 14)
	deck_viewer_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(deck_viewer_grid)

	var close := _make_button("关闭", _close_deck_viewer, 20)
	close.custom_minimum_size = Vector2(0, 48)
	box.add_child(close)

	_build_card_detail()


## 牌库打开时把 HUD 其余面板收出屏幕，关闭时弹回原位（保持尺寸，仅平移 offset）
func _slide_main_ui(out: bool) -> void:
	for tw in _ui_slide_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_ui_slide_tweens.clear()
	var vp := get_viewport().get_visible_rect().size
	var ctrls: Array = [left_panel, right_panel, event_label, hand_panel, bottom_right, deck_root]
	for c in ctrls:
		if c == null:
			continue
		if not _ui_slide_origin.has(c):
			_ui_slide_origin[c] = [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom]
		var origin: Array = _ui_slide_origin[c]
		var dir := _slide_out_dir(c)
		var dx := dir.x * (vp.x + 200.0)
		var dy := dir.y * (vp.y + 200.0)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if out:
			tw.tween_property(c, "offset_left", c.offset_left + dx, 0.34)
			tw.parallel().tween_property(c, "offset_right", c.offset_right + dx, 0.34)
			tw.parallel().tween_property(c, "offset_top", c.offset_top + dy, 0.34)
			tw.parallel().tween_property(c, "offset_bottom", c.offset_bottom + dy, 0.34)
		else:
			tw.tween_property(c, "offset_left", origin[0], 0.34)
			tw.parallel().tween_property(c, "offset_right", origin[2], 0.34)
			tw.parallel().tween_property(c, "offset_top", origin[1], 0.34)
			tw.parallel().tween_property(c, "offset_bottom", origin[3], 0.34)
		_ui_slide_tweens.append(tw)


## 每个面板收起的方向（向最近的屏幕外平移）
func _slide_out_dir(c: Control) -> Vector2:
	if c == left_panel:
		return Vector2(-1, 0)   # 左面板向左出
	if c == right_panel or c == deck_root:
		return Vector2(1, 0)    # 右面板 / 牌堆向右出
	if c == event_label:
		return Vector2(0, -1)   # 顶部横幅向上出
	if c == bottom_right:
		return Vector2(1, 0)    # 结束回合按钮向右出
	return Vector2(0, 1)       # 手牌向下出


func _open_deck_viewer() -> void:
	if _deck_open:
		return
	_deck_open = true
	deck_viewer.visible = true
	# 收起牌堆的悬停状态（避免残留黄框/孔雀开屏），并把其余 HUD 收出屏幕
	_deck_hovered = false
	deck_border.visible = false
	_fan_deck(false)
	_slide_main_ui(true)
	_update_sort_btn()   # 重开时同步按钮文字与当前排序方式，严格绑定
	# 重建全部卡牌
	for c in deck_viewer_grid.get_children():
		deck_viewer_grid.remove_child(c)
		c.queue_free()
	for vp in _deck_viewports:
		if is_instance_valid(vp):
			vp.queue_free()
	_deck_viewports.clear()
	_deck_gyro_view = null
	var cards: Array = []
	for card in _sorted_action_cards(_deck_sort_by_category):
		# 卡牌内容放进 SubViewport 渲染成纹理，再挂到 TextureRect 上，
		# 这样整张牌（面板 + 文字）是一个可被透视着色器整体倾斜的图元。
		var panel := _make_card(card)
		var vp := SubViewport.new()
		vp.size = Vector2(122, 165)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.add_child(panel)
		deck_viewer.add_child(vp)
		_deck_viewports.append(vp)

		var view := TextureRect.new()
		view.texture = vp.get_texture()
		view.custom_minimum_size = Vector2(122, 165)
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		view.set_meta("card", card)
		view.set_meta("panel", panel)
		view.material = _make_gyro_material()
		view.tooltip_text = "%s\n\n%s" % [card["desc"], _effect_text(card)]
		view.scale = Vector2(0.3, 0.3)
		view.modulate.a = 0.0
		view.mouse_entered.connect(_on_viewer_card_hover.bind(view, card))
		view.mouse_exited.connect(_on_viewer_card_unhover.bind(view))
		view.gui_input.connect(_on_viewer_card_click.bind(view, card))
		deck_viewer_grid.add_child(view)
		cards.append(view)
	# 等一帧布局完成后逐张发牌
	await get_tree().process_frame
	for i in cards.size():
		var p: Control = cards[i]
		var tw := p.create_tween()
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2.ONE, 0.28).set_delay(i * 0.03)
		tw.parallel().tween_property(p, "modulate:a", 1.0, 0.18).set_delay(i * 0.03)


## 牌库卡牌的透视倾斜材质（绕 X/Y 轴 3D 旋转 + 透视投影）
func _make_gyro_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float tilt_x = 0.0;
uniform float tilt_y = 0.0;
uniform vec2 card_size = vec2(122.0, 165.0);

void vertex() {
	vec2 c = VERTEX - card_size * 0.5;
	float cy = cos(tilt_y);
	float sy = sin(tilt_y);
	float cx = cos(tilt_x);
	float sx = sin(tilt_x);
	// 绕 Y 轴（偏航）
	vec3 q = vec3(c.x * cy, c.y, -c.x * sy);
	// 绕 X 轴（俯仰）
	vec3 r = vec3(q.x, q.y * cx - q.z * sx, q.y * sx + q.z * cx);
	// 透视投影：越深越小
	float f = 520.0;
	float persp = f / (f + r.z);
	VERTEX = vec2(r.x, r.y) * persp + card_size * 0.5;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("card_size", Vector2(122, 165))
	return mat


func _close_deck_viewer() -> void:
	_deck_open = false
	_deck_gyro_view = null
	deck_viewer.visible = false
	_slide_main_ui(false)


# ==================== 牌库排序（按类别 / 按费用 切换） ====================
## 互旋箭头图标（两个方向相反的箭头，表示切换）
func _make_swap_icon_texture(px: int) -> ImageTexture:
	var grid := """............X...
............XX..
XXXXXXXXXXXXXXX.
XXXXXXXXXXXXXXXX
XXXXXXXXXXXXXXX.
............XX..
............X...
................
................
...X............
..XX............
.XXXXXXXXXXXXXXX
XXXXXXXXXXXXXXXX
.XXXXXXXXXXXXXXX
..XX............
...X............"""
	var img := _grid_image(grid, Color(1.0, 0.92, 0.66), Color(0.85, 0.72, 0.42), Color(1.0, 1.0, 1.0))
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


## 排序切换按钮：互旋箭头 + 文字，点击切换排序方式
func _make_sort_button() -> Button:
	var b := _make_button("", _toggle_deck_sort, 16)
	b.icon = _make_swap_icon_texture(32)
	b.custom_minimum_size = Vector2(150, 42)
	return b


## 刷新排序按钮文字与提示
func _update_sort_btn() -> void:
	if deck_sort_btn == null:
		return
	var mode := "按类别排序" if _deck_sort_by_category else "按费用排序"
	deck_sort_btn.text = mode
	deck_sort_btn.tooltip_text = "切换排序方式（当前：%s）" % mode


## 排序冷却：锁死期间按钮禁用并显示倒计时，禁止交互/无按下反馈
func _update_sort_cooldown() -> void:
	if deck_sort_btn == null:
		return
	var remaining := SORT_COOLDOWN_MS - (Time.get_ticks_msec() - _sort_cooldown_ms)
	if remaining > 0:
		if not deck_sort_btn.disabled:
			deck_sort_btn.disabled = true
		deck_sort_btn.text = "冷却中 %d 秒" % int(ceil(remaining / 1000.0))
	elif deck_sort_btn.disabled:
		deck_sort_btn.disabled = false
		_update_sort_btn()


func _toggle_deck_sort() -> void:
	# 锁死两次切换之间的最低时间间隔（5 秒），杜绝连点造成排列错乱
	var now := Time.get_ticks_msec()
	if now - _sort_cooldown_ms < SORT_COOLDOWN_MS:
		return
	if _sort_animating:
		return
	_sort_cooldown_ms = now
	_sort_animating = true
	_deck_sort_by_category = not _deck_sort_by_category
	_update_sort_btn()
	await _sort_deck_cards(_deck_sort_by_category)
	_sort_animating = false


## 按当前排序规则返回 ACTION_CARDS 的有序副本
func _sorted_action_cards(by_category: bool) -> Array:
	var cards: Array = GameState.ACTION_CARDS.duplicate()
	cards.sort_custom(func(a, b): return _card_dict_less(a, b, by_category))
	return cards


## 两张卡牌的比较器：类别排序按类别序（生态→社会→管理），费用排序按费用升序
func _card_dict_less(a: Dictionary, b: Dictionary, by_category: bool) -> bool:
	if by_category:
		var oa := CATEGORY_ORDER.find(a["category"])
		var ob := CATEGORY_ORDER.find(b["category"])
		if oa != ob:
			return oa < ob
	else:
		if a["cost"] != b["cost"]:
			return a["cost"] < b["cost"]
		var oa := CATEGORY_ORDER.find(a["category"])
		var ob := CATEGORY_ORDER.find(b["category"])
		if oa != ob:
			return oa < ob
	# 同级再按费用、id 稳定排序
	if a["cost"] != b["cost"]:
		return a["cost"] < b["cost"]
	return a["id"] < b["id"]


## 重排牌库卡牌并让它们直接飞到新位置
func _sort_deck_cards(by_category: bool) -> void:
	var panels: Array = deck_viewer_grid.get_children()
	if panels.size() < 2:
		return
	# 先停掉所有悬停动画并复位，避免和飞行动画打架
	for p in panels:
		_kill_card_tweens(p)
		p.z_index = 0
		p.rotation = 0.0
		p.scale = Vector2.ONE
		p.modulate.a = 1.0
		_remove_yellow_frame(p)
	# 记录旧位置
	var old_pos := {}
	for p in panels:
		old_pos[p] = p.position
	# 按新规则排序并重排子节点
	panels.sort_custom(func(a, b): return _card_dict_less(a.get_meta("card"), b.get_meta("card"), by_category))
	for i in panels.size():
		deck_viewer_grid.move_child(panels[i], i)
	# 等两帧确保 HFlowContainer 完成重新布局（一帧可能不够，读到旧位置会导致排序没变）
	deck_viewer_grid.queue_sort()
	await get_tree().process_frame
	await get_tree().process_frame
	# 把每张牌拉回旧位置，再 tween 直接飞到新位置
	for p in panels:
		var new_pos: Vector2 = p.position
		p.position = old_pos[p]
		p.set_meta("base_pos", new_pos)   # 更新悬停基准位，避免下次悬停飞到旧位
		var tw: Tween = p.create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(p, "position", new_pos, 0.3)
	# 等飞行动画完成，期间 _sort_animating 保持 true，避免连点造成位置 tween 重叠
	await get_tree().create_timer(0.32).timeout


# ==================== 牌库卡牌悬停 / 点击查看 ====================
## 悬停：浮起放大 + 轻微漂浮 + 黄框；并记录为陀螺仪目标
func _on_viewer_card_hover(view: Control, _card: Dictionary) -> void:
	_deck_gyro_view = view
	_kill_card_tweens(view)
	if not view.has_meta("base_pos"):
		view.set_meta("base_pos", view.position)  # 首次悬停才记录原位（此时布局已完成）
	var base: Vector2 = view.get_meta("base_pos")
	view.z_index = 10
	view.pivot_offset = view.size * 0.5
	var tweens: Array = []
	# 浮起放大
	var tw := view.create_tween()
	tweens.append(tw)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(view, "position:y", base.y - 16, 0.16)
	tw.parallel().tween_property(view, "scale", Vector2(1.12, 1.12), 0.16)
	# 四周轻微漂浮（幅度/速度都调小，避免和陀螺仪叠加显得像果冻）
	var fx := view.create_tween().set_loops()
	tweens.append(fx)
	fx.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fx.tween_property(view, "position:x", base.x + 2.5, 2.2).set_delay(0.16)
	fx.tween_property(view, "position:x", base.x - 2.5, 2.2)
	var fy := view.create_tween().set_loops()
	tweens.append(fy)
	fy.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fy.tween_property(view, "position:y", base.y - 16 + 2, 2.0).set_delay(0.16)
	fy.tween_property(view, "position:y", base.y - 16 - 2, 2.0)
	view.set_meta("hover_tweens", tweens)
	_apply_yellow_frame(view)


func _on_viewer_card_unhover(view: Control) -> void:
	if _deck_gyro_view == view:
		_deck_gyro_view = null
	_kill_card_tweens(view)
	view.z_index = 0
	var base: Vector2 = view.get_meta("base_pos", view.position)
	var tw := view.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(view, "position", base, 0.16)
	tw.parallel().tween_property(view, "scale", Vector2.ONE, 0.16)
	tw.parallel().tween_property(view, "rotation", 0.0, 0.16)
	view.set_meta("return_tween", tw)
	_remove_yellow_frame(view)


## 取消该卡牌所有悬停/归位动画，避免快速反复划过时 tween 打架
func _kill_card_tweens(view: Control) -> void:
	var tweens: Array = view.get_meta("hover_tweens", [])
	for t in tweens:
		if t != null:
			t.kill()
	view.set_meta("hover_tweens", null)
	if view.has_meta("return_tween"):
		var ret: Tween = view.get_meta("return_tween")
		if ret != null:
			ret.kill()
	view.set_meta("return_tween", null)


## 牌库陀螺仪：只对鼠标悬停的那张牌做 3D 透视倾斜（绕 X/Y 轴），其余回正
func _process_deck_gyro(delta: float) -> void:
	if not _deck_open or deck_viewer_grid == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var k := 1.0 - exp(-12.0 * delta)
	for view in deck_viewer_grid.get_children():
		if not is_instance_valid(view):
			continue
		var mat: ShaderMaterial = view.material
		if mat == null:
			continue
		var target_x := 0.0
		var target_y := 0.0
		if view == _deck_gyro_view:
			var center: Vector2 = view.get_global_rect().get_center()
			var d: Vector2 = mouse - center
			# 鼠标在卡牌内的相对位置 → 俯仰/偏航角（±约 18°）
			target_x = clampf(d.y * 0.0032, -0.32, 0.32)
			target_y = clampf(d.x * 0.0042, -0.32, 0.32)
		var cur_x: float = view.get_meta("gyro_x", 0.0)
		var cur_y: float = view.get_meta("gyro_y", 0.0)
		var nx := lerpf(cur_x, target_x, k)
		var ny := lerpf(cur_y, target_y, k)
		view.set_meta("gyro_x", nx)
		view.set_meta("gyro_y", ny)
		mat.set_shader_parameter("tilt_x", nx)
		mat.set_shader_parameter("tilt_y", ny)


func _on_viewer_card_click(event: InputEvent, view: Control, card: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_card_detail(view, card)


func _apply_yellow_frame(view: Control) -> void:
	var panel: PanelContainer = view.get_meta("panel")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.22, 0.14, 0.98)
	sb.border_color = Color(1.0, 0.85, 0.3)
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


func _remove_yellow_frame(view: Control) -> void:
	var panel: PanelContainer = view.get_meta("panel")
	_panel_style(panel, Color(0.30, 0.22, 0.14, 0.98))


## 卡牌详情：左大牌 + 右介绍框（打字机）；大牌从被点击处平移放大投射到左侧展示位
func _show_card_detail(view: Control, card: Dictionary) -> void:
	card_detail.visible = true
	if _detail_big_card != null and is_instance_valid(_detail_big_card):
		_detail_big_card.queue_free()
		_detail_big_card = null
	var big := _make_card(card)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.pivot_offset = Vector2(61, 82.5)
	_detail_big_card = big
	# 起始：被点击卡牌的屏幕中心；终点：左侧展示区中心
	var src_center := view.get_global_rect().get_center()
	var dst_center := card_detail_card.get_global_rect().get_center()
	var inv := card_detail.get_global_transform().affine_inverse()
	var src_local: Vector2 = inv * src_center - big.pivot_offset
	var dst_local: Vector2 = inv * dst_center - big.pivot_offset
	big.position = src_local
	big.scale = Vector2.ONE
	card_detail.add_child(big)
	# 投射动画：平移 + 放大
	var fly := big.create_tween()
	fly.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fly.tween_property(big, "position", dst_local, 0.4)
	fly.parallel().tween_property(big, "scale", Vector2(1.8, 1.8), 0.4)
	card_detail_title.text = card["name"]
	card_detail_body.text = _card_detail_text(card)
	card_detail_body.visible_characters = 0
	var total := card_detail_body.get_total_character_count()
	var tw := card_detail_body.create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(card_detail_body, "visible_characters", total, clampf(total * 0.03, 0.4, 2.5))


func _card_detail_text(card: Dictionary) -> String:
	var body := "[color=#8a8a8a]类别：%s　成本：%d 万[/color]\n\n" % [CATEGORY_NAMES[card["category"]], card["cost"]]
	body += "%s\n\n" % card["desc"]
	body += "[b]档位效果[/b]\n"
	for tier in ["basic", "effective", "deep"]:
		var t: Dictionary = card["tiers"][tier]
		var parts: Array = []
		for e in t["effects"]:
			var d: int = e["delay"]
			var suffix := "（%d 回合后）" % d if d > 0 else ""
			parts.append("%s %+d%s" % [GameState.METRIC_NAMES[e["metric"]], int(e["delta"]), suffix])
		body += "· %s：%s\n" % [GameState.TIER_NAMES[tier], "、".join(parts)]
	if card.has("side_note") and not card["side_note"].is_empty():
		for k in card["side_note"]:
			body += "\n[color=#ffb060]※ %s[/color]" % card["side_note"][k]
	return body


func _close_card_detail() -> void:
	card_detail.visible = false


func _on_card_detail_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_card_detail()


## 卡牌详情弹层（覆盖在牌库查看器之上）
func _build_card_detail() -> void:
	card_detail = Control.new()
	card_detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	card_detail.visible = false
	deck_viewer.add_child(card_detail)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_card_detail_dim_input)
	card_detail.add_child(dim)

	card_detail_card = CenterContainer.new()
	card_detail_card.anchor_left = 0.0
	card_detail_card.anchor_right = 0.5
	card_detail_card.anchor_top = 0.0
	card_detail_card.anchor_bottom = 1.0
	card_detail_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_detail.add_child(card_detail_card)

	var info := PanelContainer.new()
	info.anchor_left = 0.52
	info.anchor_right = 0.98
	info.anchor_top = 0.08
	info.anchor_bottom = 0.92
	_panel_style(info, Color(0.24, 0.17, 0.11, 0.96))
	card_detail.add_child(info)

	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 10)
	info.add_child(iv)

	card_detail_title = _make_label("", 30, Color(1, 0.9, 0.55))
	card_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(card_detail_title)

	var sep := HSeparator.new()
	iv.add_child(sep)

	card_detail_body = RichTextLabel.new()
	card_detail_body.bbcode_enabled = true
	card_detail_body.fit_content = true
	card_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_detail_body.add_theme_font_size_override("normal_font_size", _snap_px(16))
	card_detail_body.add_theme_color_override("default_color", Color(0.96, 0.94, 0.9))
	iv.add_child(card_detail_body)

	var close := _make_button("返回", _close_card_detail, 18)
	close.custom_minimum_size = Vector2(0, 44)
	iv.add_child(close)


func _on_start_pressed() -> void:
	var s := seed_input.text.strip_edges()
	if s == "" or s == "0":
		GameState.run_seed = 0
	elif s.is_valid_int() and int(s) >= 0:
		GameState.run_seed = int(s)
	else:
		menu_hint.text = "种子需为非负整数（留空则随机）"
		return
	_clear_save()           # 放弃（判负）上一局暂停的进度
	_playing = true
	_hide_menu()
	GameState.reset_game()
	_update_hud()
	_update_3d()
	_play_hud_enter()      # 开局登场：两块面板从屏幕外滑入


## 开局登场：左侧「回合 / 资金」面板从屏幕左外滑入，右侧「生态指标」面板从右外滑入。
## 方向与 _slide_side_panels 保持一致，落点就是两块面板的常驻位置。
## 手感：QUART + EASE_OUT（起步快、收尾稳），右侧晚 0.08s 出发，两侧同时淡入。
func _play_hud_enter() -> void:
	if left_panel == null or right_panel == null:
		return
	const L_HOME_L := 6.0        # 左面板常驻位置
	const L_HOME_R := 210.0
	const R_HOME_L := -190.0     # 右面板常驻位置（锚在屏幕右缘，负值向左）
	const R_HOME_R := -6.0
	const GAP := 12.0            # 屏幕外的额外间隙
	const DUR := 0.55            # 滑入时长（秒）
	const LAG := 0.08            # 右侧延后出发

	# 先瞬移到屏幕外（同帧完成，渲染时看不到中间状态）
	left_panel.offset_left = -(L_HOME_R - L_HOME_L) - GAP
	left_panel.offset_right = -GAP
	right_panel.offset_left = GAP
	right_panel.offset_right = (R_HOME_R - R_HOME_L) + GAP
	left_panel.modulate.a = 0.0
	right_panel.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(left_panel, "offset_left", L_HOME_L, DUR)
	tw.tween_property(left_panel, "offset_right", L_HOME_R, DUR)
	tw.tween_property(left_panel, "modulate:a", 1.0, DUR * 0.7)
	tw.tween_property(right_panel, "offset_left", R_HOME_L, DUR).set_delay(LAG)
	tw.tween_property(right_panel, "offset_right", R_HOME_R, DUR).set_delay(LAG)
	tw.tween_property(right_panel, "modulate:a", 1.0, DUR * 0.7).set_delay(LAG)


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

	# 进度条 + 阈值红线：红线作为进度条的兄弟节点，避免被指标颜色 modulate 染色
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 11)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.modulate = METRIC_COLORS[metric]
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bar)

	# 阈值红线（像素竖线）：指标低于此线即判负；锚定在阈值比例处，随难度更新
	var line := ColorRect.new()
	line.color = Color(1.0, 0.2, 0.2, 0.95)
	line.anchor_left = 0.2
	line.anchor_right = 0.2
	line.offset_left = -1
	line.offset_right = 1
	line.anchor_top = 0.0
	line.anchor_bottom = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)

	vb.add_child(wrap)

	metric_bars[metric] = {"bar": bar, "val": val, "line": line, "row": vb}
	return vb


## 按「难度线 + 每指标偏移」更新指标条上的阈值红线位置
## 六项的红线不再一样长：哪项更脆，线就更靠右，玩家一眼看得出来。
func _update_threshold_lines() -> void:
	for metric in metric_bars:
		var line: ColorRect = metric_bars[metric].get("line")
		if line != null:
			var ratio: float = GameState.failure_threshold_for(metric) / 100.0
			line.anchor_left = ratio
			line.anchor_right = ratio


# ==================== 指标悬停小窗 ====================
## 鼠标移到某一项指标上时，跟随指针弹出的小窗：
## 本回合自然演化会掉多少 / 回合末大概落到哪 / 致死线（红线）在哪 / 余量还剩多少；
## 若已有「已预警、下回合开局才爆发」的危机且正好打到这一项，也提前告诉你。
## 数字全部来自 GameState.metric_hover_preview()（只读推演），这里只负责显示，不参与任何判定。
const METRIC_TIP_W := 294.0


func _build_metric_tip(parent: Node) -> void:
	metric_tip = PanelContainer.new()
	metric_tip.custom_minimum_size = Vector2(METRIC_TIP_W, 0)
	metric_tip.anchor_left = 0.0
	metric_tip.anchor_top = 0.0
	metric_tip.anchor_right = 0.0
	metric_tip.anchor_bottom = 0.0
	metric_tip.visible = false
	_panel_style(metric_tip, Color(0.16, 0.12, 0.08, 0.96))
	parent.add_child(metric_tip)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	metric_tip.add_child(vb)

	metric_tip_title = _make_label("", 14, Color(0.95, 0.95, 0.95))
	vb.add_child(metric_tip_title)

	metric_tip_body = RichTextLabel.new()
	metric_tip_body.bbcode_enabled = true
	metric_tip_body.fit_content = true
	metric_tip_body.scroll_active = false
	metric_tip_body.custom_minimum_size = Vector2(METRIC_TIP_W - 26, 0)
	metric_tip_body.add_theme_font_size_override("normal_font_size", 13)
	metric_tip_body.add_theme_color_override("default_color", Color(0.90, 0.90, 0.88))
	vb.add_child(metric_tip_body)

	# 小窗只负责「看」：整棵子树都不接收鼠标。否则指针一进小窗，指标行的悬停就断了，会闪。
	_ignore_mouse(metric_tip)


## 递归关掉一棵子树的鼠标响应
func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


## 每帧判断鼠标是否落在某个指标行上：是 → 刷新内容并跟随指针；否 → 收起
## mouse_override 仅供自动化测试顶替真实鼠标，正常游戏不传（默认取真实鼠标位置）
func _update_metric_tip(mouse_override: Vector2 = Vector2.INF) -> void:
	if metric_tip == null:
		return
	if not _tip_allowed():
		metric_tip.visible = false
		_tip_metric = ""
		return
	var mp: Vector2 = mouse_override if mouse_override != Vector2.INF else get_viewport().get_mouse_position()
	var hovered := ""
	for metric in metric_bars:
		var row: Control = metric_bars[metric].get("row")
		if row != null and row.is_visible_in_tree() and row.get_global_rect().has_point(mp):
			hovered = str(metric)
			break
	if hovered == "":
		metric_tip.visible = false
		_tip_metric = ""
		return
	if hovered != _tip_metric:
		_tip_metric = hovered
		_tip_last_text = ""
	_fill_metric_tip(hovered)
	metric_tip.visible = true
	_place_metric_tip(mp)


## 什么时候允许显示：正常分配回合，且没有任何弹层盖在 HUD 上
func _tip_allowed() -> bool:
	if _current_phase != "allocate" or _paused or GameState.game_over:
		return false
	if right_panel == null or not right_panel.is_visible_in_tree():
		return false
	if popup_root != null and popup_root.visible:
		return false
	if crisis_root != null and crisis_root.visible:
		return false
	if warn_panel_root != null and warn_panel_root.visible:
		return false
	if deck_viewer != null and deck_viewer.visible:
		return false
	if menu_root != null and menu_root.visible:
		return false
	if pause_root != null and pause_root.visible:
		return false
	return true


## 小窗正文。每次都按当前数值重算 → 出牌/结算后数字不会停在上一回合
func _fill_metric_tip(metric: String) -> void:
	var p: Dictionary = GameState.metric_hover_preview(metric)
	metric_tip_title.text = "%s   %d" % [str(GameState.METRIC_NAMES.get(metric, metric)), int(p["cur"])]
	metric_tip_title.add_theme_color_override("font_color", METRIC_COLORS.get(metric, Color(0.92, 0.92, 0.92)))

	var cur: int = int(p["cur"])
	var kind: String = str(p["kind"])
	var nat_min: int = int(p["nat_min"])
	var nat_max: int = int(p["nat_max"])
	var end_min: int = int(p["end_min"])
	var end_max: int = int(p["end_max"])

	# ① 本回合自然演化会掉多少（水位是随机，给区间）
	var dtxt := ""
	var dcol := "#8e9aa4"
	if kind == "random":
		dtxt = "%+d ~ %+d" % [nat_min, nat_max]
		dcol = "#ffcc66"
	elif nat_min == 0 and nat_max == 0:
		dtxt = "不变"
	elif nat_min > 0:
		dtxt = "%+d" % nat_min
		dcol = "#7ee08a"
	else:
		dtxt = "%+d" % nat_min
		dcol = "#ff8f7a"
	var rows: Array = []
	rows.append("[color=#cfd6dc]本回合自然演化[/color]   [color=%s][b]%s[/b][/color]" % [dcol, dtxt])
	rows.append("[color=#8e9aa4]· %s[/color]" % str(p["why"]))

	# ② 回合末大概落到哪
	if kind == "random":
		rows.append("[color=#cfd6dc]回合末约[/color]   [b]%d ~ %d[/b]" % [end_min, end_max])
	else:
		rows.append("[color=#cfd6dc]回合末约[/color]   [b]%d[/b] %s" % [end_min, _tip_delta_suffix(cur, end_min)])

	# ③ 红线（致死线）与余量
	var line: int = int(p["line"])
	var margin: int = int(p["margin_nat"])
	var mcol := "#7ee08a"
	if margin < 0:
		mcol = "#ff5a5a"
	elif margin <= 3:
		mcol = "#ffcc66"
	rows.append("[color=#cfd6dc]致死线[/color]   [color=#ff8080][b]%d[/b][/color]    [color=#cfd6dc]余量[/color] [color=%s][b]%d[/b][/color]" % [line, mcol, margin])
	var mult: float = float(p["penalty_mult"])
	if mult > 1.0 and nat_min < 0:
		rows.append("[color=#8e9aa4]（当前难度：负向变动 ×%.1f 已计入）[/color]" % mult)
	if bool(p["break_nat"]):
		rows.append("[color=#ff5a5a][b]⚠ 照这样到回合末就会跌破致死线[/b][/color]")
	elif margin <= 3:
		rows.append("[color=#ffcc66]⚠ 已经很贴红线了[/color]")

	# ④ 预警中、下回合开局才爆发的危机正好打到这一项
	if int(p["crisis_delta"]) != 0:
		rows.append("[color=#ffb060]⚠ 预警中：%s[/color]" % str(p["crisis_name"]))
		var tail := "会跌破致死线" if bool(p["break_total"]) else "仍在红线之上"
		rows.append("[color=#8e9aa4]· 下回合开局 %+d → 约 %d，%s[/color]" % [int(p["crisis_delta"]), int(p["worst"]), tail])

	var txt := ""
	for r in rows:
		txt += str(r) + "\n"
	txt = txt.strip_edges()
	if txt != _tip_last_text:
		_tip_last_text = txt
		metric_tip_body.text = txt


func _tip_delta_suffix(from_v: int, to_v: int) -> String:
	var d: int = to_v - from_v
	if d == 0:
		return "（不变）"
	return "（%+d）" % d


## 跟随指针：默认贴在指针左侧；指针右侧是右侧指标面板，所以再限一道「不许压住面板」
func _place_metric_tip(mp: Vector2) -> void:
	metric_tip.reset_size()
	var s: Vector2 = metric_tip.size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var limit_x: float = vp.x - 8.0
	if right_panel != null and right_panel.is_visible_in_tree():
		limit_x = minf(limit_x, right_panel.get_global_rect().position.x - 8.0)
	var pos := Vector2(mp.x - s.x - 16.0, mp.y - s.y * 0.5)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, limit_x - s.x))
	# 窗口顶部 4~62px 是「当前事件横幅 + 危机预警日志条」，压住它们会看不清；
	# 能整个让到下面就让（悬停上面几项时会触发），否则再退回居中。
	if pos.y < 66.0 and 66.0 + s.y <= vp.y - 8.0:
		pos.y = 66.0
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - s.y - 8.0))
	metric_tip.position = pos


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
	_refresh_warn_bar()


# ==================== 事件 / 结算 / 知识卡 / 报告 ====================
func _on_event(text: String) -> void:
	_current_event = text
	_current_phase = "popup_event"
	_update_hud()
	hand_panel.visible = false
	bottom_right.visible = false
	_show_popup("第 %d 回合 · 事件" % GameState.turn, text, "开始分配资金", _enter_allocate)


func _enter_allocate() -> void:
	_current_phase = "allocate"
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
			if GameState.game_over:
				break   # 已经判负，剩下的牌不再执行

	# 判负即时化：出牌当场把指标打到致死线以下 → 不再结算、不再进分配，直接给失败报告
	if GameState.game_over:
		if _current_phase != "popup_report":
			_show_report(GameState.generate_report())
		return

	var before: Dictionary = GameState.metrics.duplicate()
	_defer_game_over = true   # 结算流程自己按「结算反馈 → 报告」的顺序收尾
	GameState.end_turn()
	_defer_game_over = false
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
		var counter_names: Array = []
		for cid in GameState.counter_card_ids():
			counter_names.append(_card_name(cid))
		var shown_c: Array = counter_names.slice(0, 3)
		var tail_c: String = "" if counter_names.size() <= 3 else " 等 %d 张" % counter_names.size()
		lines.append("[color=#8a8a8a]   （专项响应已列入下批：%s%s，出现概率已提高，不保证到手）[/color]" % [
			"、".join(shown_c), tail_c])

	hand_panel.visible = false
	bottom_right.visible = false
	_slide_side_panels(true)  # 结算后侧边栏收回屏幕外，让出沙盘
	_current_phase = "popup_settlement"
	_show_popup("结算反馈", "\n".join(lines), "继续", _on_resolve_continue)


func _on_resolve_continue() -> void:
	var kid := GameState.pop_pending_knowledge()
	if kid != "":
		_show_knowledge(kid)
	else:
		_advance_to_next()


func _show_knowledge(card_id: String) -> void:
	_current_phase = "popup_knowledge"
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
		# 危机警示是独立弹层，也计入「有弹窗」判断，避免危机弹窗未关就发牌。
		if not popup_root.visible and not crisis_root.visible:
			_enter_allocate()


func _on_game_end(report: Dictionary) -> void:
	# 中途判负（出牌 / 危机爆发）→ 立刻把失败报告推到玩家面前，
	# 不让他继续出牌、产生「还能救」的错觉。
	if _defer_game_over:
		return      # 回合结算流程：结算反馈展示完，由 _advance_to_next 再出报告
	if _current_phase == "popup_report":
		return      # 报告已经开着，别叠层
	if report.get("is_failure", false):
		_crisis_queue.clear()
		crisis_root.visible = false   # 危机警示让位给失败报告，不留残影
		_show_report(report)


func _show_report(r: Dictionary) -> void:
	_current_phase = "popup_report"
	_clear_save()  # 一局已结束，清掉存档（不能再继续）
	var earned: int = r.get("talent_points", 0)
	if earned > 0:
		Talents.award(earned)
	var body := ""
	var title := "四年 · 生态报告"
	if r.get("is_failure", false):
		title = "被撤换 · 修复失败"
		body += "[color=#ff7060][b]第 %d 回合，%s[/b][/color]\n\n" % [
			r.get("turns_survived", 0), r.get("failure_reason", "生态崩溃")]
		# 死因：点名是哪个指标先崩的、崩到多少、线在哪 —— 玩家才知道自己输在哪
		var fm: String = str(r.get("failure_metric", ""))
		if fm != "":
			var fname: String = str(r.get("failure_metric_name", fm))
			var fval: int = int(r.get("failure_value", GameState.metrics.get(fm, 0)))
			var fthr: int = int(r.get("failure_threshold", GameState.failure_threshold_for(fm)))
			body += "[b]直接死因：[/b]%s 跌至 [color=#ff9090]%d[/color]（致死线 %d）\n" % [fname, fval, fthr]
			var remedy: String = str(GameState.METRIC_REMEDY.get(fm, ""))
			if remedy != "":
				body += "[color=#8fd0ff]补强建议：%s[/color]\n" % remedy
		var below: Array = r.get("metrics_below", [])
		if below.size() > 1:
			var parts: Array = []
			for e in below:
				parts.append("%s %d" % [GameState.METRIC_NAMES.get(e["metric"], e["metric"]), int(e["value"])])
			body += "[color=#c08080]同一回合跌破致死线的还有：%s[/color]\n" % "、".join(parts)
		if GameState.last_crisis_name != "":
			body += "[color=#c08080]本回合危机：%s[/color]\n" % GameState.last_crisis_name
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
	_playing = false
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
	return ImageTexture.create_from_image(_grid_image(grid, main, dark, light))


## 把网格字符串解析成 Image（# 深色 / X 主色 / o 高亮）
func _grid_image(grid: String, main: Color, dark: Color, light: Color) -> Image:
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
	return img


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
