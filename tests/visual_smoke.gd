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

func creeper_screen_rect() -> Rect2:
	var mesh: MeshInstance3D = game.wetland.creeper_mesh
	var camera: Camera3D = game.wetland.map_camera
	var bounds := mesh.get_aabb()
	var rect := Rect2(camera.unproject_position(mesh.to_global(bounds.get_endpoint(0))), Vector2.ZERO)
	for i in range(1, 8):
		rect = rect.expand(camera.unproject_position(mesh.to_global(bounds.get_endpoint(i))))
	return rect

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.3)
	if game._intro_playing: game._finish_intro()
	await settle(1.3)
	var menu_camera_size: float = game.wetland.map_camera.size
	check(is_equal_approx(game.wetland.camera_zoom_factor, game.MENU_CAM_ZOOM), "Menu must pull the active map camera back")
	game.wetland.easter_rng.seed = 20261002
	var saw_creeper := false
	var saw_no_creeper := false
	for i in 100:
		game._roll_creeper_visibility()
		saw_creeper = saw_creeper or game.wetland.creeper_mesh.visible
		saw_no_creeper = saw_no_creeper or not game.wetland.creeper_mesh.visible
	check(saw_creeper and saw_no_creeper, "Creeper probability must allow both outcomes")
	game.wetland.creeper_mesh.visible = true
	check(game.wetland.creeper_mesh.is_visible_in_tree(), "Creeper must be attached to the rendered 3D world")
	check(game.wetland._is_land(game.wetland.CREEPER_ANCHOR), "Creeper decal must remain on land")
	var secret: Vector2 = game.wetland._point(game.wetland.CREEPER_ANCHOR)
	var window_rect := get_viewport().get_visible_rect().grow(-24)
	check(window_rect.has_point(secret) and secret.x > window_rect.size.x * 0.40, "Menu camera must keep the Creeper inside the unshaded view")
	check(window_rect.encloses(creeper_screen_rect()), "Entire Creeper must fit inside the menu view")
	check(game.wetland.scenery_props.size() > 200, "Empty meadows need varied pixel vegetation and stones")
	for prop in game.wetland.scenery_props:
		check(prop.pos.distance_to(game.wetland.CREEPER_ANCHOR) >= 0.15, "Scenery must leave the secret clearing open")
	for route in [game.wetland.yangtze_route, game.wetland.gan_route]:
		check(not get_viewport().get_visible_rect().has_point(game.wetland._point(route[0])), "River extension must continue beyond the screen")
	var ship_a: Dictionary = game.wetland._river_sample(game.wetland.yangtze_route, 0.4)
	var ship_b: Dictionary = game.wetland._river_sample(game.wetland.yangtze_route, 0.41)
	check(ship_a.pos.distance_to(ship_b.pos) > 0.01 and game.wetland._in_river_corridor(ship_a.pos, 0.02), "Yangtze ships must move along the channel")
	await capture("01-menu")
	get_window().size = Vector2i(960, 540)
	await settle(0.4)
	var small_secret: Vector2 = game.wetland._point(game.wetland.CREEPER_ANCHOR)
	check(get_viewport().get_visible_rect().grow(-20).has_point(small_secret), "Small-window menu must keep the secret visible")
	check(get_viewport().get_visible_rect().grow(-20).encloses(creeper_screen_rect()), "Small-window menu must show the entire Creeper")
	await capture("01b-menu-small-window")
	get_window().size = Vector2i(1280, 720)
	await settle(0.4)
	game._on_title_start()
	await capture("02-difficulty")
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20260930"
	game._on_start_pressed()
	await settle(0.3)
	check(game.wetland.map_camera.size < menu_camera_size and game.wetland.camera_zoom_factor > game.wetland.GAME_CAMERA_ZOOM, "Entering a run must animate camera zoom")
	check(game.wetland.creeper_mesh.visible, "Starting a run must preserve the menu's Creeper roll")
	await close_popups()
	await settle(1.0)
	check(game.card_infos.size() > 0, "Starting a run must deal cards")
	check(is_equal_approx(game.wetland.camera_zoom_factor, game.wetland.GAME_CAMERA_ZOOM), "Game camera zoom must settle at its closer scale")
	check(not get_viewport().get_visible_rect().intersects(creeper_screen_rect()), "Entire Creeper must be beyond the gameplay viewport")
	var wildlife: Control = game.wetland.get_node("Wildlife")
	var habitat := Vector2(0.4, 0.6)
	var screen_anchor: Vector2 = wildlife.get_transform() * game.wetland._wildlife_point(habitat)
	check(screen_anchor.distance_to(game.wetland._point(habitat)) < 2.0, "Scenery must track the camera projection")
	for species in 5:
		var bird_sheet: Texture2D = game.wetland.BIRD_ACTIONS[species]
		check(bird_sheet.get_width() >= 128 and bird_sheet.get_height() >= 128, "Bird atlas must contain all sixteen poses")
		for frame in 16:
			var region: Rect2 = game.wetland._bird_frame_region(species, frame)
			check(Rect2(Vector2.ZERO, bird_sheet.get_size()).encloses(region), "Bird animation frame exceeds atlas")
	for state in [0, 1, 2, 3, 4, 5]:
		for age in [0.0, 0.2, 0.5, 1.0]:
			var frame: int = game.wetland._bird_animation_frame({"state": state, "animation_age": age, "slot": 0})
			check(frame >= 0 and frame < 16, "Animation state must select a valid bird pose")
	check(game.wetland._bird_animation_frame({"state": 3, "animation_age": 0.0}) == 14, "Flight must begin with takeoff")
	check(game.wetland._bird_animation_frame({"state": 0, "animation_previous_state": 5, "animation_age": 0.0}) == 15, "Return flight must finish with landing")
	var camera: Camera3D = game.wetland.map_camera
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Map must use a real orthographic 3D camera")
	check(is_equal_approx(camera.position.x, camera.position.z), "Camera azimuth must be 45 degrees")
	check(is_equal_approx(camera.position.y, Vector2(camera.position.x, camera.position.z).length()), "Camera pitch must be 45 degrees")
	var marker := Vector2(0.4, 0.6)
	check(game.wetland._point(marker).is_equal_approx(camera.unproject_position(game.wetland._ground_position(marker)).round()), "Habitat must match projected terrain")
	check(game.wetland.house_sites.size() >= 12, "Village should spread around the lake")
	for site in game.wetland.house_sites:
		check(game.wetland._is_land(site) and game.wetland._near_water(site), "Cottage must be on near-shore land")
		check(site.distance_to(game.wetland.CREEPER_ANCHOR) > 0.11, "Cottage covers Creeper clearing")
	var original_settlement: float = GameState.settlement
	GameState.settlement = 100.0
	GameState.metrics_changed.emit()
	await settle(0.25)
	check(game.wetland.house_target_count == 7, "Settlement must keep the old maximum of seven cottages")
	check(game.wetland.house_progress[6] > 0.0, "Expansion must animate construction")
	game._score_animating = true
	GameState.settlement = 0.0
	GameState.metrics_changed.emit()
	check(game.wetland.house_target_count == 7, "Scenery must stay frozen during score reveal")
	game._score_animating = false
	game._update_3d()
	GameState.settlement = 0.0
	GameState.metrics_changed.emit()
	await settle(0.25)
	check(game.wetland.house_progress[0] < 1.0, "Wetland recovery must animate cottage removal")
	GameState.settlement = original_settlement
	GameState.metrics_changed.emit()
	game._pause_game()
	await settle(0.1)
	var paused_elapsed: float = game.wetland.elapsed
	await settle(0.2)
	check(is_equal_approx(paused_elapsed, game.wetland.elapsed), "Pause must freeze scenery animation")
	game._resume_game()
	var flying_bird: Dictionary = game.wetland.bird_agents[0]
	flying_bird["state"] = 3
	flying_bird["pos"] = Vector2(0.42, 0.50)
	flying_bird["target"] = Vector2(0.35, 0.50)
	game.wetland._process_birds(0.05)
	check(absf(absf(float(flying_bird["angle"])) - PI) < 0.01, "Flying bird must face its destination")
	check(game.wetland._bird_facing(flying_bird) == -1.0, "Bird flying screen-left must mirror horizontally")
	for heading in [0.0, PI / 2.0, PI, -PI / 2.0]:
		var center := Vector2(0.5, 0.5)
		var screen_direction := camera.unproject_position(game.wetland._ground_position(center + Vector2.from_angle(heading) * 0.01)) - camera.unproject_position(game.wetland._ground_position(center))
		var expected_facing := -1.0 if screen_direction.x < 0.0 else 1.0
		check(game.wetland._bird_facing({"angle": heading}) == expected_facing, "Bird facing must follow projected motion")
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
	check(not get_viewport().get_visible_rect().intersects(creeper_screen_rect()), "Small-window gameplay must leave the entire Creeper outside")
	check(game.end_turn_btn.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "Small-window controls clipped")
	get_window().size = Vector2i(1600, 900)
	await settle(0.8)
	await capture("12-large-window")
	check(not get_viewport().get_visible_rect().intersects(creeper_screen_rect()), "Large-window gameplay must leave the entire Creeper outside")
	# Returning to the menu reveals the same physical clearing as the camera retreats.
	game._pause_game()
	game._on_pause_exit()
	game.wetland.creeper_mesh.visible = true
	await settle(1.3)
	await capture("13-return-to-menu")
	for window_size in [Vector2i(960, 900), Vector2i(1920, 720)]:
		get_window().size = window_size
		await settle(0.4)
		check(get_viewport().get_visible_rect().grow(-20).encloses(creeper_screen_rect()), "Menu must reveal the entire Creeper across aspect ratios")
		game._on_continue_pressed()
		await settle(1.0)
		check(not get_viewport().get_visible_rect().intersects(creeper_screen_rect()), "Resuming must move the entire Creeper beyond the viewport")
		game._pause_game()
		game._on_pause_exit()
		game.wetland.creeper_mesh.visible = true
		await settle(1.3)
	print("VISUAL_SMOKE: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
