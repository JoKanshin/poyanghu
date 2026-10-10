extends Node
var game: Node
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle(seconds: float = 0.3) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("POYANG_SCREENSHOT_DIR").path_join(name + ".png"))

func regular_info() -> Dictionary:
	for info in game.card_infos:
		if info.card_id == "patrol" and not info.get("dispatched", false): return info
	return {}

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.5)
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20261010"
	game._on_start_pressed()
	for i in 24:
		if game.popup_root.visible: game._on_popup_button()
		await settle(0.1)
	check(GameState.turn_budget == GameState.funds, "New turn snapshots its available budget")
	check(GameState.turn_card_spent == 0, "New turn clears card expenses")
	GameState.funds = 85
	GameState.turn_budget = 85
	GameState.turn_card_spent = 0
	for metric in GameState.metrics: GameState.metrics[metric] = 70
	game.current_hand = [GameState.card_by_id("patrol"), GameState.card_by_id("community_comp")]
	game.play_deal_anim = false
	game._build_hand_panel()
	game._update_hud()
	check(game.funds_label.text == "0 / 85 万", "Empty table shows zero over total budget")
	check(not game.selected_label.visible and game.selected_label.text.is_empty(), "Old table and budget text stays removed")
	check(not game.action_hint.visible and game.action_hint.text.is_empty(), "Old action-limit text stays removed")
	var info := regular_info()
	info.selected = true
	info.staged_by_drag = true
	info.stage_order = 0
	info.tier = "effective"
	game._update_selected_label()
	check(game.funds_label.text == "20 / 85 万", "Staged regular card adds its cost")
	info.tier = "deep"
	game._update_selected_label()
	check(game.funds_label.text == "%d / 85 万" % GameState.tier_cost("patrol", "deep"), "Locked tier cost updates the numerator")
	info.tier = "effective"
	check(GameState.dispatch_card("rescue"), "Actual dispatch payment succeeds")
	game._sync_dispatched_stage_cards()
	game._update_selected_label()
	check(GameState.funds == 45 and GameState.turn_card_spent == 40, "Dispatch charge is recorded exactly once")
	check(game.funds_label.text == "60 / 85 万", "Dispatch plus regular cost uses the original total budget")
	info.selected = false
	game._update_selected_label()
	check(game.funds_label.text == "40 / 85 万", "Returning a regular card reduces the numerator")
	info.selected = true
	game._layout_fan()
	game._update_selected_label()
	await settle(0.6)
	await capture("01-budget-staged")
	game.save_game()
	check(game.load_game(), "Staged budget survives actual game save/load")
	check(game.funds_label.text == "60 / 85 万", "Save/load retains total and paid dispatch without duplicates")
	var legacy: Dictionary = GameState.serialize()
	legacy.erase("turn_budget")
	legacy.erase("turn_card_spent")
	GameState.load_state(legacy)
	check(GameState.turn_budget == 85 and GameState.turn_card_spent == 40, "Older saves recover the known dispatch charge")
	check(GameState.spend(5), "Non-card expense succeeds")
	game._update_selected_label()
	check(game.funds_label.text == "60 / 85 万", "Refresh-type expense neither shrinks total budget nor counts as card cost")
	var observed: Array[String] = []
	GameState.funds_changed.connect(func() -> void: observed.append(game.funds_label.text))
	game.score_speed = 3.0
	game._process_staged_cards(2.2)
	await settle(0.8)
	game._finish_turn()
	for i in 200:
		if not game._score_animating: break
		await settle(0.1)
	check(not game._score_animating, "Settlement completes")
	check(GameState.turn_card_spent == 60, "Execution records regular cost but does not recharge dispatch")
	check(game.funds_label.text == "60 / 85 万", "Settlement keeps the same ratio even after funds are carried forward")
	for text in observed: check(text == "60 / 85 万", "Each payment signal avoids double-counting staged cards: " + text)
	await capture("02-budget-settlement")
	game.popup_root.visible = false
	GameState.pending_knowledge.clear()
	GameState.start_new_turn()
	game.popup_root.visible = false
	game._enter_allocate()
	check(GameState.turn_card_spent == 0, "Next turn resets card expenses")
	check(game.funds_label.text == "0 / %d 万" % GameState.turn_budget, "Next turn starts at zero with its new budget")
	get_window().size = Vector2i(960, 540)
	GameState.turn_budget = 155
	GameState.turn_card_spent = 134
	game._update_hud()
	await settle(0.8)
	check(get_viewport().get_visible_rect().encloses(game.funds_label.get_global_rect()), "Three-digit ratio fits a small window")
	check(get_viewport().get_visible_rect().encloses(game.end_turn_btn.get_global_rect()), "Removing labels keeps operation buttons inside the window")
	await capture("03-budget-small-window")
	print("TURN_BUDGET: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
