extends Node
## Phone input adapter; retain the original board, menus, cards and artwork.
const VisualTheme = preload("res://scripts/visual_theme.gd")
const HOLD_SECONDS := 0.32
const PREFS := "user://mobile_settings.json"
var game: Node
var pointer_down := false
var pointer_origin := Vector2.ZERO
var pointer_position := Vector2.ZERO
var pointer_age := 0.0
var touch_moved := false
var long_pressed := false
var pinned_metric := ""
var tilt := Vector2.ZERO
var neutral := Vector3.ZERO
var calibrated := false
var gyro_enabled := true
var backgrounded := false
var autosave_time := 0.0
var previous_phase := ""
var hint: PanelContainer
var hint_title: Label
var hint_body: RichTextLabel
var skip_button: Button
var pause_button: Button
var sensor_buttons: Array[Button] = []
var touch_scroll: Control
var scroll_start := Vector2.ZERO
var scroll_origin := Vector2.ZERO
var scroll_dragging := false

func configure(host: Node) -> void:
	game = host
	name = "MobilePort"
	get_tree().auto_accept_quit = false
	Engine.max_fps = 60
	if FileAccess.file_exists(PREFS):
		var prefs = JSON.parse_string(FileAccess.get_file_as_string(PREFS))
		if prefs is Dictionary: gyro_enabled = bool(prefs.get("gyro_enabled", true))
	# Only the missing pause entry is added to the existing station heading.
	var column: VBoxContainer = game.left_panel.get_child(0)
	var heading: Control = column.get_child(0)
	var row := HBoxContainer.new()
	column.add_child(row)
	column.move_child(row, 0)
	heading.reparent(row, false)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_button = small_button("暂停", game._toggle_pause)
	pause_button.custom_minimum_size = Vector2(48, 36)
	pause_button.add_theme_font_size_override("font_size", 12)
	row.add_child(pause_button)
	var canvas := CanvasLayer.new()
	canvas.name = "MobileInputHints"
	canvas.layer = 41
	add_child(canvas)
	skip_button = small_button("跳过", go_back)
	skip_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip_button.offset_left = -108
	skip_button.offset_right = -20
	skip_button.offset_top = 16
	skip_button.offset_bottom = 60
	skip_button.hide()
	canvas.add_child(skip_button)
	hint = PanelContainer.new()
	hint.custom_minimum_size = Vector2(340, 0)
	hint.add_theme_stylebox_override("panel", preload("res://scripts/ui_skin.gd").panel(false, 12.0))
	hint.hide()
	canvas.add_child(hint)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	hint.add_child(content)
	hint_title = Label.new()
	hint_title.add_theme_font_size_override("font_size", 20)
	hint_title.add_theme_color_override("font_color", VisualTheme.GOLD)
	content.add_child(hint_title)
	hint_body = RichTextLabel.new()
	hint_body.fit_content = true
	hint_body.scroll_active = false
	hint_body.custom_minimum_size = Vector2(316, 0)
	hint_body.add_theme_font_size_override("normal_font_size", 18)
	hint_body.add_theme_color_override("default_color", VisualTheme.PAPER)
	content.add_child(hint_body)
	game._ignore_mouse(hint)
	for body in [game.card_detail_body, game.knowledge_detail_body]:
		body.fit_content = false
		body.scroll_active = true
	game.seed_input.virtual_keyboard_enabled = true
	game.seed_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_add_sensor_setting(game.menu_settings_panel)
	_add_sensor_setting(game.pause_settings_panel)
	get_viewport().size_changed.connect(_on_resize)

func small_button(text: String, action: Callable) -> Button:
	var button: Button = game._make_button(text, action, 16)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 42
	return button

func _add_sensor_setting(panel: PanelContainer) -> void:
	var column: VBoxContainer = panel.get_child(0)
	var button := small_button("", toggle_sensor)
	column.add_child(button)
	column.move_child(button, maxi(0, column.get_child_count() - 2))
	sensor_buttons.append(button)
	_sync_sensor_buttons()

func _sync_sensor_buttons() -> void:
	for button in sensor_buttons: button.text = "手机倾斜：" + ("开启" if gyro_enabled else "关闭")

func toggle_sensor() -> void:
	gyro_enabled = not gyro_enabled
	calibrated = false
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"gyro_enabled": gyro_enabled}))
	_sync_sensor_buttons()

func show_card_hint(panel: Control) -> void:
	var info: Dictionary = game._find_card_info(panel)
	if info.is_empty(): return
	var card: Dictionary = GameState.card_by_id(str(info.card_id))
	show_hint(str(card.get("name", "行动牌")), panel.tooltip_text, pointer_position)
	long_pressed = true

func show_hint(title: String, text: String, point: Vector2) -> void:
	hint_title.text = title
	hint_body.text = text
	hint.show()
	hint.reset_size()
	_place_hint(point)
	_place_hint.call_deferred(point)

func _place_hint(point: Vector2) -> void:
	if not hint.visible: return
	var vp := get_viewport().get_visible_rect().size
	var pos := point - Vector2(hint.size.x * 0.5, hint.size.y + 100)
	pos.x = clampf(pos.x, 12, maxf(12, vp.x - hint.size.x - 12))
	pos.y = clampf(pos.y, 12, maxf(12, vp.y - hint.size.y - 12))
	hint.position = pos

func hide_hints() -> void:
	hint.hide()
	pinned_metric = ""
	game.metric_tip.hide()

func update_metric_tip() -> void:
	if pinned_metric.is_empty() or not game._tip_allowed():
		game.metric_tip.hide()
		return
	game._fill_metric_tip(pinned_metric)
	game.metric_tip.show()
	game._place_metric_tip(pointer_position)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()
		return
	if game._ending_playing:
		return
	if event is InputEventScreenTouch:
		if event.index == 0:
			_pointer(event.pressed, event.position)
			if event.pressed:
				touch_scroll = _pick_touch_scroll(event.position)
				scroll_dragging = false
				scroll_origin = event.position
				if touch_scroll:
					scroll_start = Vector2(touch_scroll.get_h_scroll_bar().value if touch_scroll is ScrollContainer else 0.0, touch_scroll.get_v_scroll_bar().value)
				else:
					_begin_touch_card(event.position)
			else:
				if game._card_press_panel != null:
					game._finish_card_pointer(game._card_press_origin if event.canceled else event.position)
				touch_scroll = null
				scroll_dragging = false
	elif event is InputEventScreenDrag:
		if event.index == 0:
			_motion(event.position)
			if game._card_press_panel != null:
				if not game._card_dragging and game._card_press_elapsed >= HOLD_SECONDS: game._start_card_drag()
				if game._card_dragging: game._update_card_drag_pose(event.position, event.relative)
			if is_instance_valid(touch_scroll):
				var movement: Vector2 = event.position - scroll_origin
				if movement.length() >= 16: scroll_dragging = true
				if scroll_dragging:
					touch_scroll.get_v_scroll_bar().value = scroll_start.y - movement.y
					if touch_scroll is ScrollContainer:
						touch_scroll.get_h_scroll_bar().value = scroll_start.x - movement.x
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(event.pressed, event.position)
		if not event.pressed and not touch_moved and not long_pressed and game._tip_allowed():
			for metric in game.metric_bars:
				var row: Control = game.metric_bars[metric].row
				if row.get_global_rect().has_point(event.position):
					pinned_metric = str(metric)
					update_metric_tip()
					break
	elif event is InputEventMouseMotion and pointer_down:
		_motion(event.position)
		if scroll_dragging: get_viewport().set_input_as_handled()

func _pick_touch_scroll(point: Vector2) -> Control:
	var scope: Node = game.get_node("UICanvas")
	for panel in [game.menu_root, game.deck_viewer, game.dispatch_panel, game.warn_panel_root, game.knowledge_viewer, game.card_detail, game.knowledge_detail, game.pause_root, game.popup_root]:
		if panel != null and panel.visible: scope = panel
	return _scroll_at(scope, point)

func _begin_touch_card(point: Vector2) -> void:
	if not game._tip_allowed() or game._sort_animating or game._card_press_panel != null: return
	if game.sandpan_view.collapsed or game.sandpan_view.board_cards_attached: return
	if game.dispatch_panel != null and game.dispatch_panel.visible: return
	var picked: Control
	for info in game.card_infos:
		var panel: Control = info.panel
		if not panel.is_visible_in_tree(): continue
		if preload("res://scripts/card_geometry.gd").contains(panel, point):
			if picked == null or panel.z_index > picked.z_index or panel.z_index == picked.z_index and panel.get_index() > picked.get_index(): picked = panel
	if picked:
		game._card_press_panel = picked
		game._card_press_origin = point
		game._card_press_elapsed = 0.0

func _scroll_at(node: Node, point: Vector2) -> Control:
	if node is Control and not node.is_visible_in_tree(): return null
	var result: Control
	if (node is ScrollContainer or node is RichTextLabel and node.scroll_active) and node.get_global_rect().has_point(point):
		var bar: VScrollBar = node.get_v_scroll_bar()
		if bar.max_value > bar.page: result = node
		elif node is ScrollContainer and node.get_h_scroll_bar().max_value > node.get_h_scroll_bar().page: result = node
	for child in node.get_children():
		var found := _scroll_at(child, point)
		if found: result = found
	return result

func _pointer(down: bool, point: Vector2) -> void:
	if down and not pointer_down:
		hide_hints()
		pointer_origin = point
		touch_moved = false
		pointer_age = 0
		long_pressed = false
	pointer_position = point
	pointer_down = down

func _motion(point: Vector2) -> void:
	pointer_position = point
	if point.distance_to(pointer_origin) > 18: touch_moved = true
	if hint.visible and point.distance_to(pointer_origin) > 48: hint.hide()

func allow_tap() -> bool:
	return not touch_moved and not long_pressed

func _process(delta: float) -> void:
	if not game or backgrounded: return
	_update_tilt(delta)
	skip_button.visible = game._intro_playing and not game._ending_playing
	if game._paused or game._score_animating or game.popup_root.visible or game.crisis_root.visible:
		hide_hints()
	if pointer_down and not touch_moved and not long_pressed:
		pointer_age += delta
		if pointer_age >= HOLD_SECONDS and game._card_press_panel == null:
			long_pressed = true
			_show_control_hint()
	if game._playing and not game._score_animating and game._current_phase != previous_phase:
		game.save_game()
	previous_phase = game._current_phase
	autosave_time += delta
	if autosave_time > 8 and game._playing and not game._score_animating:
		game.save_game()
		autosave_time = 0

func _show_control_hint() -> void:
	if game._tip_allowed():
		for metric in game.metric_bars:
			if game.metric_bars[metric].row.get_global_rect().has_point(pointer_origin):
				pinned_metric = str(metric)
				update_metric_tip()
				return
	var control := get_viewport().gui_get_hovered_control()
	while control:
		if control is BaseButton and not control.disabled: return
		if not control.tooltip_text.is_empty():
			show_hint("说明", control.tooltip_text, pointer_origin)
			return
		control = control.get_parent_control()

func _update_tilt(delta: float) -> void:
	if not gyro_enabled or game._paused or game.wetland.reduced_motion:
		tilt = tilt.lerp(Vector2.ZERO, 1.0 - exp(-12 * delta))
		return
	var gravity := Input.get_gravity()
	var rate := Input.get_gyroscope()
	if gravity.length() > 0.1 and not calibrated:
		neutral = gravity
		calibrated = true
	var target := Vector2.ZERO
	if calibrated:
		var change := (gravity - neutral) / 9.81
		target = Vector2(change.y, change.x) * 0.42
	target += Vector2(rate.x, rate.y) * 0.025
	target = target.clamp(Vector2(-0.20, -0.20), Vector2(0.20, 0.20))
	tilt = tilt.lerp(target, 1.0 - exp(-8 * delta))

func update_hand(delta: float) -> void:
	for info in game.card_infos:
		var panel: Control = info.panel
		if not is_instance_valid(panel) or info.get("flying", false) or info.get("shaking", false): continue
		info["hovered"] = false
		if not game._card_dragging and not info.get("staged_by_drag", false):
			game.MotionSpring.to(panel, "position", info.base_pos, 430.0, 32.0)
			game.MotionSpring.to(panel, "rotation", float(info.theta), 460.0, 34.0)
			game.MotionSpring.to(panel, "scale", Vector2.ONE, 390.0, 30.0)
		game._step_card_gyro(panel, tilt * 0.5, delta)

func fit_popup() -> void:
	if game.popup_photo_frame.visible: return
	game.popup_body.fit_content = false
	game.popup_body.scroll_active = true
	game.popup_body.custom_minimum_size.y = minf(float(game.popup_body.get_content_height()), get_viewport().get_visible_rect().size.y - 220)
	game.popup_panel.reset_size()

func go_back() -> void:
	if DisplayServer.virtual_keyboard_get_height() > 0:
		DisplayServer.virtual_keyboard_hide()
		var focus := get_viewport().gui_get_focus_owner()
		if focus: focus.release_focus()
		return
	if game._card_press_panel != null:
		game._finish_card_pointer(game._card_press_origin)
		hide_hints()
		return
	if hint.visible or not pinned_metric.is_empty(): hide_hints(); return
	if game.title_photos and game.title_photos._zoom and game.title_photos._zoom.visible:
		game.title_photos._close_zoom(); return
	if game._ending_playing: game._finish_ending(); return
	if game._intro_playing: game._finish_intro(); return
	for pair in [[game.knowledge_detail, game._close_knowledge_detail], [game.card_detail, game._close_card_detail], [game.knowledge_viewer, game._close_knowledge_viewer], [game.dispatch_panel, game._close_dispatch_panel], [game.deck_viewer, game._close_deck_viewer], [game.warn_panel_root, game._close_warn_history]]:
		if pair[0] != null and pair[0].visible: pair[1].call(); return
	if game._paused:
		if game.pause_settings_panel.visible: game._on_pause_settings_back()
		else: game._resume_game()
		return
	if game.menu_root.visible:
		for pair in [[game.menu_clear_confirm_panel, game._on_clear_confirm_cancel], [game.menu_credits_panel, game._on_credits_back], [game.menu_achievements_panel, game._on_achievements_back], [game.menu_talent_panel, game._on_talent_back], [game.menu_settings_panel, game._on_settings_back]]:
			if pair[0] != null and pair[0].visible: pair[1].call(); return
		if game.menu_back_btn.visible: game._on_menu_back()
		return
	if game.popup_root.visible or game.crisis_root.visible or game._score_animating: return
	game._toggle_pause()

func _notification(what: int) -> void:
	if game == null: return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		backgrounded = true
		calibrated = false
		pointer_down = false
		touch_scroll = null
		scroll_dragging = false
		if game._card_press_panel != null: game._finish_card_pointer(game._card_press_origin)
		hide_hints()
		if game._playing and not game._score_animating:
			game.save_game()
			if game._can_pause() and not game._paused: game._pause_game()
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		backgrounded = false
		calibrated = false
		game._sync_master_mute()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if game._playing and not game._score_animating: game.save_game()
		get_tree().quit()

func _on_resize() -> void:
	calibrated = false
	hide_hints()
