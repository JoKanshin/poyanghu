extends Node
## Run in an isolated test project/user directory; see docs/UI_REDESIGN.md.
var game: Node
var failures: Array[String] = []
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle(seconds: float = 0.4) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(label: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + ".png"))

func close_popups() -> void:
	for i in 12:
		if not game.popup_root.visible: break
		game._on_popup_button()
		await settle(0.1)

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.3)
	if game._intro_playing: game._finish_intro()
	await settle()
	await capture("01-menu")
	game._on_title_start()
	await capture("02-difficulty")
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20260930"
	game._on_start_pressed()
	await close_popups()
	await settle(1.0)
	check(game.card_infos.size() > 0, "Starting a run must deal cards")
	for info in game.card_infos:
		check(info.panel.size.is_equal_approx(Vector2(122, 165)), "Card footprint changed: " + str(info.panel.size))
	check(game.end_turn_btn.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "End turn button exceeds viewport")
	await capture("03-gameplay")
	var before: Dictionary = GameState.metrics.duplicate()
	var before_funds: int = GameState.funds
	var info: Dictionary = game.card_infos[0]
	game._set_play_tier("basic", false)
	game._toggle_card(info.panel)
	var locked_tier: String = info.tier
	game._set_play_tier("deep", false)
	check(info.tier == locked_tier, "Changing lever must preserve selected card tier")
	check(GameState.funds == before_funds and GameState.metrics == before, "Selecting cards must not spend/apply effects")
	await settle()
	await capture("04-selected")
	game._toggle_card(info.panel)
	game._set_play_tier("effective", false)
	game._open_deck_viewer()
	await settle(1.8)
	await capture("05-deck")
	game._close_deck_viewer()
	await settle(0.7)
	game._open_dispatch_panel()
	await settle(1.0)
	await capture("06-dispatch")
	game._close_dispatch_panel()
	await settle(0.6)
	game._pause_game()
	await settle(0.3)
	await capture("07-pause")
	game._on_pause_settings()
	await settle(0.3)
	await capture("08-settings")
	game._on_pause_settings_back()
	game._resume_game()
	# Resolve an actual turn, including the existing score choreography.
	game._set_play_tier("basic", false)
	game._toggle_card(game.card_infos[0].panel)
	var turn_before: int = GameState.turn
	game.score_speed = 1.5
	game._finish_turn()
	await settle(1.0)
	await capture("09-scoring")
	for i in 100:
		if not game._score_animating: break
		await settle(0.2)
	check(not game._score_animating, "Score animation did not finish")
	await close_popups()
	await settle(0.7)
	check(GameState.turn > turn_before or not game._playing, "End turn failed to advance")
	check(game.wetland.metrics == GameState.metrics, "Map must reflect settled ecology")
	await capture("10-next-season")
	# Save/resume exercise uses the isolated test user directory.
	game.save_game()
	var saved_turn: int = GameState.turn
	check(game.load_game(), "Could not load saved run")
	check(GameState.turn == saved_turn, "Resume changed the turn")
	await settle()
	# Every card, including long names, must fit existing animation viewports.
	for card in GameState.ACTION_CARDS:
		var made: Dictionary = game._make_card(card)
		add_child(made.panel)
		await get_tree().process_frame
		check(made.panel.get_combined_minimum_size().y <= 165, "Card too tall: " + str(card.name))
		made.panel.queue_free()
	get_window().size = Vector2i(960, 540)
	await settle(0.8)
	await capture("11-small-window")
	check(game.end_turn_btn.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "Small-window controls clipped")
	get_window().size = Vector2i(1600, 900)
	await settle(0.8)
	await capture("12-large-window")
	print("VISUAL_SMOKE: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
