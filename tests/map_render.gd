extends Node
var failures: Array[String] = []
var checks := 0
var game: Node
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")
var baseline := OS.get_environment("POYANG_MAP_BASELINE") == "1"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(name: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(name + ".png"))

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle()
	if game._intro_playing: game._finish_intro()
	GameState.run_seed = 20261004
	GameState.difficulty = 0
	GameState.reset_game()
	game._hide_menu()
	game.popup_root.hide()
	game._set_hud_visible(false)
	game.wetland.camera_tween.kill()
	game.wetland.reduced_motion = true
	for metric in GameState.metrics: GameState.metrics[metric] = 65
	GameState.metrics.water_level = 50
	GameState.settlement = 60
	for pid in GameState.plant_pop: GameState.plant_pop[pid] = 60
	game.wetland.sync_state({}, false)
	await settle()
	for i in game.wetland.house_progress.size(): game.wetland.house_progress[i] = 1.0 if i < game.wetland.house_target_count else 0.0
	game.wetland._set_camera_zoom(0.9)
	await settle()
	await capture("01-normal-map")
	var saved: Dictionary = GameState.serialize()
	if not baseline:
		check(game.wetland.get_node_or_null("GroundShadows") != null, "Contact shadows must be on an independent ground layer")
		var units: Array = game.wetland._scenery_draw_order()
		var last_y := -INF
		for unit in units:
			var y: float = game.wetland._shadow_point(unit["uv"]).y
			check(y >= last_y - 0.001, "Scenery draw order does not follow camera depth")
			last_y = y
		seed(773)
		var expected := randi()
		seed(773)
		game.wetland._scenery_draw_order()
		game.wetland._contact_shadow_specs()
		check(randi() == expected, "Render planning consumed gameplay RNG")
	for window_size in [Vector2i(960,540), Vector2i(1280,720), Vector2i(1600,900)]:
		get_window().size = window_size
		await settle()
		for zoom in [0.9, 1.0, 1.3]:
			game.wetland._set_camera_zoom(zoom)
			await settle(0.1)
			var layer: Control = game.wetland.get_node("Wildlife")
			for uv in [Vector2(0.3,0.4), Vector2(0.55,0.6), Vector2(0.7,0.8)]:
				check((layer.get_transform() * game.wetland._wildlife_point(uv)).distance_to(game.wetland._point(uv)) <= 1.5, "Billboard drifted from 3D ground anchor")
			if not baseline:
				var radius := 30.0
				var polygon: PackedVector2Array = game.wetland._shadow_polygon(Vector2(0.5,0.5), game.wetland._px_to_uv(radius))
				check(absf((polygon[0] - polygon[20]).length() - radius * 2.0) < 0.02, "Shadow width changed due to rounded projection")
				check(game.wetland.get_node("GroundShadows").get_transform().is_equal_approx(layer.get_transform()), "Shadow and scenery zoom transforms differ")
	await capture("02-wide-map")
	get_window().size = Vector2i(1280,720)
	game.wetland._set_camera_zoom(0.9)
	for water_level in [20, 85]:
		GameState.metrics.water_level = water_level
		game.wetland.sync_state({}, false)
		await settle()
		await capture("03-dry-map" if water_level == 20 else "04-high-water-map")
	if not baseline:
		# Pixel sampling around both rivers checks CPU habitat classification against GPU.
		GameState.metrics.water_level = 50
		game.wetland.sync_state({}, false)
		await settle()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var terrain: Image = game.wetland.terrain_viewport.get_texture().get_image()
			for uv in [Vector2(0.4184458,0.1112966), Vector2(0.326131,0.4793997), Vector2(0.3412264,0.4328778)]:
				var point: Vector2 = game.wetland._point(uv)
				var color := terrain.get_pixelv(Vector2i(point))
				check(game.wetland._is_water(uv) and color.b > color.g and color.g > color.r, "CPU water mask disagrees with rendered river junction")
			# Suppress scenery to test shadow clipping directly against the same terrain texture.
			game.wetland.get_node("Wildlife").hide()
			await settle()
			await RenderingServer.frame_post_draw
			var with_shadows: Image = get_viewport().get_texture().get_image()
			game.wetland.get_node("GroundShadows").hide()
			await settle()
			await RenderingServer.frame_post_draw
			var without_shadows: Image = get_viewport().get_texture().get_image()
			var water_samples := 0
			var polluted := 0
			for y in range(0,terrain.get_height(),3):
				for x in range(0,terrain.get_width(),3):
					var color := terrain.get_pixel(x,y)
					if color.b > color.g + 0.02 and color.g > color.r + 0.02:
						water_samples += 1
						if with_shadows.get_pixel(x,y) != without_shadows.get_pixel(x,y): polluted += 1
			check(water_samples > 100 and polluted == 0, "Contact shadows darkened river/lake pixels")
			print("WATER_SHADOW_CLIP: ", water_samples, " water samples, ", polluted, " altered")
			game.wetland.get_node("GroundShadows").show()
			game.wetland.get_node("Wildlife").show()
	check(GameState.metrics.water_level in [50,85], "Rendering mutated gameplay state")
	GameState.load_state(saved)
	print("MAP_RENDER: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
