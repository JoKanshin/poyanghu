extends Node
var game: Node
var mobile: Node
var checks := 0
var failures := 0
var screenshots := OS.get_environment("POYANG_SCREENSHOT_DIR")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func wait_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func shot(name: String) -> void:
	if screenshots.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshots.path_join(name + ".png"))
func point_event(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
func begin_hold(info: Dictionary) -> Vector2:
	var panel: Control = info.panel
	var point := panel.get_global_transform() * (panel.size * 0.5)
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)
	return point
func _ready() -> void:
	if not OS.get_user_data_dir().contains("PoyangMobileQA"):
		push_error("Mobile tests require isolated player data")
		get_tree().quit(1)
		return
	var scene := preload("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	mobile = game.mobile
	if mobile == null:
		push_error("Mobile input adapter did not initialize")
		get_tree().quit(1)
		return
	await wait_for(1)
	if game._intro_playing: game._finish_intro()
	await wait_for(0.3)
	await shot("01-original-menu")
	check(game.menu_col.get_parent() == game.menu_root, "Original main menu has no replacement or scrolling wrapper")
	check(game.menu_start_btn.custom_minimum_size.y == 54, "Original button dimensions are retained")
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	check(not game.seed_input.has_focus(), "Optional numeric seed does not open the keyboard automatically")
	game.seed_input.text = "20261017"
	game._on_start_pressed()
	for i in 30:
		if game.popup_root.visible: game._on_popup_button()
		if game.crisis_root.visible: game._on_crisis_dismiss()
		await wait_for(0.1)
	await wait_for(1)
	check(game._current_phase == "allocate", "Original allocation flow works")
	check(game.left_panel.visible and game.right_panel.visible and game.bottom_right.visible and game.tier_lever.visible, "All original HUD panels remain visible")
	check(game.hand_panel.offset_top == -290 and game.hand_panel.offset_bottom == -4, "Original hand placement is unchanged")
	check(game.staged_board.anchor_left == 1.0 and game.staged_board.offset_left == -562, "Original pending board placement is unchanged")
	check(game.left_panel.offset_left == 18 and game.left_panel.size.x == 204, "Pause entry retains the original station width")
	await shot("02-original-game")
	GameState.funds = 1000
	var info: Dictionary = game.card_infos.back()
	var point := begin_hold(info)
	await wait_for(0.10)
	check(not game._card_dragging, "A brief touch does not start dragging")
	await wait_for(0.35)
	check(game._card_dragging, "Hold starts the existing drag operation")
	check(mobile.hint.visible and mobile.hint_body.text.contains("万"), "The same hold displays the original tier and price explanation")
	check(not info.selected, "Holding a card never spends budget")
	await shot("03-hold-detail")
	game._finish_card_pointer(point)
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.position = point
	touch_up.pressed = false
	Input.parse_input_event(touch_up)
	await wait_for(0.5)
	check(not info.selected and game._committed_funds() == 0, "Releasing in place returns to hand without a charge")
	mobile.hide_hints()
	point = begin_hold(info)
	await wait_for(0.4)
	var destination: Vector2 = game.staged_board.get_global_rect().get_center()
	mobile._motion(destination)
	game._update_card_drag_pose(destination, destination - point)
	game._finish_card_pointer(destination)
	touch_up.position = destination
	Input.parse_input_event(touch_up)
	await wait_for(0.6)
	check(info.selected and info.stage_zone == "board", "Hold then drag onto the original board queues a card")
	check(not mobile.hint.visible, "Moving the card clears the reading hint from the playfield")
	check(game._committed_funds() > 0, "Drag selection reserves the correct budget")
	game._return_staged_to_hand(info)
	await wait_for(0.5)
	check(not info.selected and game._committed_funds() == 0, "Original take-back rule refunds the reservation")
	var metric_row: Control = game.metric_bars.water_level.row
	var metric_point := metric_row.get_global_rect().get_center()
	point_event(metric_point, true)
	await wait_for(0.05)
	point_event(metric_point, false)
	await wait_for(0.1)
	check(mobile.pinned_metric == "water_level" and game.metric_tip.visible, "Tap shows the existing metric tooltip without hovering")
	await shot("04-tap-metric")
	mobile.go_back()
	check(not game.metric_tip.visible, "Back dismisses a pinned tooltip")
	mobile.pause_button.pressed.emit()
	check(game._paused and game.pause_root.visible, "Visible pause entry opens the original pause menu")
	await shot("05-original-pause")
	game._on_pause_settings()
	mobile.go_back()
	check(game.pause_panel.visible and not game.pause_settings_panel.visible, "Back returns one setting level")
	mobile.go_back()
	check(not game._paused, "Second back resumes the original game")
	mobile._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(game._paused and game.has_save(), "Backgrounding saves and pauses")
	mobile._notification(NOTIFICATION_APPLICATION_RESUMED)
	check(game._paused, "Resume stays paused until the child continues")
	mobile.go_back()
	Input.set_gravity(Vector3(0, 0, 9.81))
	mobile.calibrated = false
	mobile._update_tilt(0.1)
	Input.set_gravity(Vector3(2, 1, 9))
	mobile._update_tilt(0.2)
	check(mobile.tilt.length() > 0.01 and mobile.tilt.length() < 0.3, "Physical sensors produce bounded tilt")
	Input.set_gravity(Vector3.ZERO)
	mobile.gyro_enabled = false
	mobile._update_tilt(1)
	check(mobile.tilt.length() < 0.001, "Tilt is optional")
	mobile.gyro_enabled = true
	game._open_deck_viewer()
	await wait_for(1.5)
	var scroll: ScrollContainer = game.deck_viewer_scroll
	var swipe_from := scroll.get_global_rect().get_center() + Vector2(0, 100)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = swipe_from
	touch.pressed = true
	Input.parse_input_event(touch)
	await wait_for(0.08)
	for step in 10:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = swipe_from - Vector2(0, (step + 1) * 24)
		drag.relative = Vector2(0, -24)
		Input.parse_input_event(drag)
		await wait_for(0.02)
	touch.position = swipe_from - Vector2(0, 240)
	touch.pressed = false
	Input.parse_input_event(touch)
	await wait_for(0.25)
	check(scroll.scroll_vertical > 0 and not game.card_detail.visible, "Real screen touch and drag scroll the original library without opening a card")
	game.MotionScroll.reset_to_top(scroll)
	await wait_for(0.15)
	var view: Control = game.deck_viewer_grid.get_child(0)
	var card: Dictionary = GameState.card_by_id("patrol")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	mobile.touch_moved = true
	game._on_viewer_card_click(release, view, card)
	check(not game.card_detail.visible, "Scrolling the original library never opens a card on release")
	mobile.touch_moved = false
	mobile.long_pressed = false
	game._on_viewer_card_click(release, view, card)
	check(game.card_detail.visible, "A deliberate tap opens the original card detail")
	check(not game.card_detail_body.fit_content and game.card_detail_body.scroll_active, "Long descriptions scroll in their existing panel")
	mobile.go_back()
	check(not game.card_detail.visible and game._deck_open, "Back closes detail before the library")
	mobile.go_back()
	check(not game._deck_open, "A second back closes the library")
	await wait_for(0.6)
	for size in [Vector2i(1280,720), Vector2i(1600,720), Vector2i(1024,768), Vector2i(960,540)]:
		get_window().size = size
		await wait_for(0.3)
		var viewport := get_viewport().get_visible_rect()
		check(viewport.encloses(game.bottom_right.get_global_rect()), "Original action controls fit " + str(size))
		await shot("06-original-" + str(size.x) + "x" + str(size.y))
	# Complete a real round, including its existing settlement screens.
	game._finish_turn()
	await wait_for(6)
	check(not game._score_animating and game.popup_root.visible, "A real round reaches the original settlement screen")
	await shot("07-original-settlement")
	for i in 35:
		if game.crisis_root.visible: game._on_crisis_dismiss()
		if game.popup_root.visible: game._on_popup_button()
		await wait_for(0.1)
		if game._current_phase == "allocate" and not game._score_animating and not game.popup_root.visible: break
	check(GameState.turn == 2 and game._current_phase == "allocate", "The next round remains playable")
	print("MOBILE_INPUT_ORIGINAL_UI: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
