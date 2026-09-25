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
var card_box: HBoxContainer
var selected_label: Label
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
var village_mesh: MeshInstance3D
var village_mat: StandardMaterial3D
var species_views: Dictionary = {}  # sid -> {node, meshes[], base_positions[], speeds[]}


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
	cam.size = 15.0
	# 饥荒式 2.5D：正交 + 45° 方位角 + 约 57° 俯角（顶面与侧面均可见，立体感强）
	cam.position = Vector3(6, 13, 6)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)


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

	# 草洲（8 块）
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

	# 鸟群（8 只白鹤占位）—— 替换为多物种动态个体系统
	_build_species_views(lake_view)

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

	# 渔村（占位房屋群）
	village_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.5, 1.6, 3.5)
	village_mesh.mesh = bm
	village_mesh.position = Vector3(-10, 0.8, -9)
	village_mat = StandardMaterial3D.new()
	village_mat.albedo_color = Color(0.65, 0.45, 0.30)
	village_mesh.material_override = village_mat
	lake_view.add_child(village_mesh)

	# 延迟挂到场景，避免父节点初始化期 add_child 冲突
	var root := get_parent() as Node3D
	root.add_child.call_deferred(lake_view)


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


func _process(delta: float) -> void:
	# 物种个体在各自位置附近游走
	var time := Time.get_ticks_msec() / 1000.0
	for sid in species_views:
		var view: Dictionary = species_views[sid]
		var meshes: Array = view["meshes"]
		var bases: Array = view["bases"]
		var speeds: Array = view["speeds"]
		var phases: Array = view["phases"]
		for i in meshes.size():
			var mi: MeshInstance3D = meshes[i]
			var b: Vector3 = bases[i]
			var sp: float = speeds[i]
			var ph: float = phases[i]
			mi.position = b + Vector3(
				sin(time * sp + ph) * 1.2,
				sin(time * sp * 1.7 + ph) * 0.25,
				cos(time * sp + ph) * 1.2
			)


## 为每个物种生成一组会动的个体（最多 12 个/物种）
func _build_species_views(parent: Node3D) -> void:
	for sid in GameState.SPECIES:
		var color: Color = GameState.SPECIES[sid]["color"]
		var meshes: Array = []
		var bases: Array = []
		var speeds: Array = []
		var phases: Array = []
		for i in 12:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.18
			sm.height = 0.45
			mi.mesh = sm
			mi.visible = false
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mi.material_override = mat
			parent.add_child(mi)
			meshes.append(mi)
			# 每个物种在湖区不同区域活动
			var base := Vector3(
				(-7 + i * 1.4) + (sid.length() % 3) * 2.0,
				1.0,
				-5 + (i % 4) * 3.0
			)
			bases.append(base)
			speeds.append(0.6 + (i % 5) * 0.2)
			phases.append(i * 1.3)
		species_views[sid] = {"meshes": meshes, "bases": bases, "speeds": speeds, "phases": phases}


func _update_species_views() -> void:
	for sid in GameState.SPECIES:
		var pop: int = GameState.species_pop.get(sid, 0)
		var count: int = int(pop / 8.0)  # 0-100 → 0-12 个
		var view: Dictionary = species_views[sid]
		var meshes: Array = view["meshes"]
		for i in meshes.size():
			meshes[i].visible = i < count


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

	var cv := float(m["community"]) / 100.0
	village_mat.albedo_color = Color(0.45 + 0.35 * cv, 0.32 + 0.25 * cv, 0.22 + 0.1 * cv)


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
	_panel_style(left_panel, Color(0.08, 0.11, 0.14, 0.92))
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
	_panel_style(right_panel, Color(0.08, 0.11, 0.14, 0.92))
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
	hand_panel.offset_top = -190
	hand_panel.offset_bottom = -8
	_panel_style(hand_panel, Color(0.10, 0.13, 0.16, 0.96))
	hand_panel.visible = false
	canvas.add_child(hand_panel)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hand_panel.add_child(hv)

	var h_top := HBoxContainer.new()
	hv.add_child(h_top)
	var h_hint := _make_label("每回合最多执行 3 个行动（点击档位直接执行）", 13, Color(0.8, 0.85, 0.9))
	h_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_top.add_child(h_hint)
	selected_label = _make_label("已选：0/3", 14, Color(1, 0.9, 0.5))
	h_top.add_child(selected_label)
	var end_btn := _make_button("结束本回合 ▶", _finish_turn, 16)
	end_btn.custom_minimum_size = Vector2(140, 34)
	h_top.add_child(end_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hv.add_child(scroll)
	card_box = HBoxContainer.new()
	card_box.add_theme_constant_override("separation", 8)
	scroll.add_child(card_box)

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
	_panel_style(popup_panel, Color(0.12, 0.16, 0.20, 0.98))
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
		metric_bars[metric]["bar"].value = m[metric]
		metric_bars[metric]["val"].text = str(m[metric])

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
	_build_allocate_panel()
	hand_panel.visible = true


func _build_allocate_panel() -> void:
	for c in card_box.get_children():
		c.queue_free()
	for card in GameState.ACTION_CARDS:
		card_box.add_child(_make_card(card))
	_update_hud()


func _make_card(card: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 150)
	_panel_style(panel, Color(0.16, 0.20, 0.24, 0.98))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)

	var name_l := _make_label(card["name"], 15, Color(1, 1, 1))
	vb.add_child(name_l)

	var cat: String = card["category"]
	vb.add_child(_make_label(CATEGORY_NAMES[cat], 11, CATEGORY_COLORS[cat]))

	var desc := _make_label(card["desc"], 11, Color(0.82, 0.85, 0.88))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 42)
	vb.add_child(desc)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 4)
	vb.add_child(btns)
	for tier in ["basic", "effective", "deep"]:
		var cost := GameState.tier_cost(card["id"], tier)
		var btn := _make_button("%s%d万" % [GameState.TIER_NAMES[tier].substr(0, 2), cost], _on_action_click.bind(card["id"], tier), 11)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = "%s（%d 万）" % [GameState.TIER_NAMES[tier], cost]
		btn.disabled = not GameState.can_execute(card["id"], tier)
		btns.add_child(btn)

	return panel


func _on_action_click(card_id: String, tier: String) -> void:
	if not GameState.can_execute(card_id, tier):
		return
	GameState.execute_action(card_id, tier)
	_build_allocate_panel()


func _finish_turn() -> void:
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


func _on_popup_button() -> void:
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
	b.pressed.connect(cb)
	return b


func _panel_style(p: PanelContainer, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
