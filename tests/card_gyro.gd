extends Node
## Run only with an isolated user directory.
var game: Node
var checks := 0
var failures: Array[String] = []
var shader_code := ""
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")
const RigidShader = preload("res://scripts/card_rigid.gdshader")
const AffineShader = preload("res://tests/fixtures/teammate_card_gyro.gdshader")

func projection_errors(shader: Shader) -> Vector2i:
	var pattern := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = [Color8(220, 40, 60), Color8(30, 190, 80), Color8(40, 80, 220)]
	for y in 256:
		for x in 256:
			pattern.set_pixel(x, y, colors[(int(x / 16.0) + int(y / 16.0)) % 3])
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(pattern)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var center := get_viewport().get_visible_rect().size * 0.5
	sprite.position = center
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tilt_x", 0.32)
	material.set_shader_parameter("tilt_y", -0.32)
	material.set_shader_parameter("card_center", center)
	sprite.material = material
	layer.add_child(sprite)
	await settle(0.2)
	RenderingServer.force_draw()
	var rendered := get_viewport().get_texture().get_image()
	var samples := 0
	var errors := 0
	var cx := cos(0.32)
	var sx := sin(0.32)
	var cy := cos(-0.32)
	var sy := sin(-0.32)
	for y in range(int(center.y) - 110, int(center.y) + 110, 4):
		for x in range(int(center.x) - 110, int(center.x) + 110, 4):
			# Invert the analytic planar camera projection at this pixel center.
			var screen := Vector2(x + 0.5, y + 0.5) - center
			var a := cy + screen.x * cx * sy / 520.0
			var b := -screen.x * sx / 520.0
			var c := sx * sy + screen.y * cx * sy / 520.0
			var d := cx - screen.y * sx / 520.0
			var det := a * d - b * c
			var source := Vector2((screen.x * d - b * screen.y) / det,
				(a * screen.y - screen.x * c) / det) + Vector2(128, 128)
			if not Rect2(4, 4, 248, 248).has_point(source):
				continue
			# Ignore grid boundaries, where nearest-pixel sampling can alias.
			if fmod(source.x, 16.0) < 2.0 or fmod(source.x, 16.0) > 14.0 or fmod(source.y, 16.0) < 2.0 or fmod(source.y, 16.0) > 14.0:
				continue
			var expected := pattern.get_pixel(int(source.x), int(source.y))
			var actual := rendered.get_pixel(x, y)
			samples += 1
			if absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) > 0.02:
				errors += 1
	layer.queue_free()
	await get_tree().process_frame
	return Vector2i(samples, errors)

func verify_rigid_projection() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var old_errors := await projection_errors(AffineShader)
	var rigid_errors := await projection_errors(RigidShader)
	check(rigid_errors.x > 500, "Rigid projection sampled enough interior pixels")
	check(rigid_errors.y < rigid_errors.x * 0.01, "Rigid-plane texture agrees with analytical projection")
	check(old_errors.y > rigid_errors.y + rigid_errors.x * 0.02, "Projection test detects the previous affine texture deformation")
	print("RIGID_PROJECTION: samples=%d old_errors=%d rigid_errors=%d" % [rigid_errors.x, old_errors.y, rigid_errors.y])

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle(seconds: float = 0.3) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(label: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + ".png"))

func card_pixels(card: Control) -> int:
	if DisplayServer.get_name() == "headless":
		return -1
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	var colors := {}
	var bounds := card.get_global_rect().intersection(get_viewport().get_visible_rect())
	var pixels := 0
	var scale: Vector2 = Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	for y in range(int(bounds.position.y * scale.y), int(bounds.end.y * scale.y), 4):
		for x in range(int(bounds.position.x * scale.x), int(bounds.end.x * scale.x), 4):
			var color := img.get_pixel(x, y)
			colors[color.to_rgba32()] = true
			if color.a > 0.5:
				pixels += 1
	check(colors.size() > 8, "Rendered card contains artwork and text colors")
	return pixels

func check_material_tree(node: Node) -> void:
	for child in node.get_children():
		check(not child is SubViewport, "No flattened card viewport remains")
		if child is CanvasItem:
			check(child.use_parent_material, "Each card primitive uses the reference parent material")
		check_material_tree(child)

func check_tilt(card: Control, label: String) -> void:
	var material := card.material as ShaderMaterial
	check(material != null, label + " uses a gyro material")
	if material == null:
		return
	if shader_code.is_empty():
		shader_code = material.shader.code
	check(material.shader.code == shader_code, label + " uses the shared projection")
	check(material.shader == RigidShader, label + " uses the shared rigid-plane shader")
	check_material_tree(card)
	check(absf(float(material.get_shader_parameter("tilt_x"))) > 0.02, label + " tilts vertically")
	check(absf(float(material.get_shader_parameter("tilt_y"))) > 0.02, label + " tilts horizontally")
	check(Vector2(material.get_shader_parameter("card_center")).distance_to(game._card_gyro_center(card)) < 0.1, label + " follows the transformed center")
	for i in 24:
		game._step_card_gyro(card, Vector2.ZERO, 0.05)
	check(absf(float(material.get_shader_parameter("tilt_x"))) < 0.001 and absf(float(material.get_shader_parameter("tilt_y"))) < 0.001, label + " returns flat")

func probe_grid(grid: HFlowContainer, label: String) -> Control:
	var card: Control = grid.get_child(0)
	game._on_viewer_card_hover(card, {})
	await settle(0.4)
	game._kill_card_tweens(card)
	var mouse: Vector2 = game._card_gyro_center(card) + Vector2(40, -30)
	for i in 24:
		game._process_deck_gyro(0.05, mouse)
	await capture(label)
	check_tilt(card, label)
	check(card.get_meta("panel") is PanelContainer, label + " uses original card primitives")
	check(await card_pixels(card) > 100 or DisplayServer.get_name() == "headless", label + " has a rendered card face")
	var position_before: Vector2 = card.position
	await settle(0.7)
	check(card.position.is_equal_approx(position_before), label + " has no idle floating loop")
	game._on_viewer_card_unhover(card)
	return card

func probe_detail(card: Control, label: String) -> void:
	check(card is PanelContainer, label + " uses teammate's original panel implementation")
	var mouse: Vector2 = game._card_gyro_center(card) + Vector2(40, -30)
	for i in 24:
		game._process_detail_gyro(0.05, mouse)
	await capture(label)
	check_tilt(card, label)
	check(get_viewport().get_visible_rect().encloses(card.get_global_rect()), label + " fits the window")

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.4)
	await verify_rigid_projection()
	if game._intro_playing:
		game._finish_intro()
	await settle(1.0)
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20261004"
	game._on_start_pressed()
	for i in 12:
		if not game.popup_root.visible:
			break
		game._on_popup_button()
		await settle(0.1)
	await settle(1.5)
	GameState.funds = 1000
	game.set_process(false)
	for action in GameState.ACTION_CARDS:
		var made: Dictionary = game._make_card(action)
		game._bind_card_gyro(made.panel)
		add_child(made.panel)
		await get_tree().process_frame
		await get_tree().process_frame
		var face: PanelContainer = made.panel
		check(face.size.x <= 122.1 and face.size.y <= 165.1, "%s keeps its fixed card dimensions" % action.id)
		check(face.is_ancestor_of(made.cost_label) and not made.cost_label.visible, "%s price state belongs to its panel without drawing text" % action.id)
		var bitmap: TextureRect = face.get_meta("pixel_face")
		check(bitmap.texture == game.PixelCardArt.texture(action.name, str(GameState.tier_cost(action.id, game.play_tier))), "%s price is written into the pixel face" % action.id)
		made.panel.queue_free()
	for info in game.card_infos:
		var panel: PanelContainer = info.panel
		check(panel.get_meta("pixel_face") is TextureRect, "Hand card uses the shared pixel face")
		check(panel.get_theme_stylebox("panel") is StyleBoxFlat, "Hand card preserves the selection frame")
		check(panel.size.is_equal_approx(Vector2(122, 165)), "Hand card keeps its fixed footprint")
		check_material_tree(panel)
	var info: Dictionary = game.card_infos.back()
	var hand: PanelContainer = info.panel
	var center: Vector2 = game._card_gyro_center(hand)
	for i in 24:
		game._update_card_hover(0.05, center + Vector2(35, -25))
	await capture("gyro-hand")
	check_tilt(hand, "Hand")
	check(await card_pixels(hand) > 100 or DisplayServer.get_name() == "headless", "Hand rendering is nonblank")
	game._set_play_tier("basic", false)
	var basic_cost: String = info.cost_label.text
	game._toggle_card(hand)
	check(info.selected and info.tier == "basic", "Original hand card remains selectable")
	check(hand.get_theme_stylebox("panel").border_color.is_equal_approx(game.VisualTheme.GOLD), "Selected card frame remains visible")
	await settle(2.1)
	game._set_play_tier("deep", false)
	check(game.play_tier == "deep", "Lever switches after its real cooldown")
	check(info.tier == "basic", "Selected card preserves its locked price tier")
	game._toggle_card(hand)
	check(info.cost_label.text != basic_cost, "Live card prices still refresh")
	check(not info.selected, "Original hand card remains deselectable")
	game._open_deck_viewer()
	await settle(1.8)
	var action_view := await probe_grid(game.deck_viewer_grid, "gyro-deck")
	game._show_card_detail(action_view, action_view.get_meta("card"))
	await settle(0.6)
	await probe_detail(game._detail_big_card, "gyro-action-detail")
	game._close_card_detail()
	game._close_deck_viewer()
	await settle(0.5)
	game._open_dispatch_panel()
	await settle(1.8)
	await probe_grid(game.dispatch_grid, "gyro-dispatch")
	game._close_dispatch_panel()
	Knowledge.reset_all()
	Knowledge.unlock("geo_poyang")
	game._open_knowledge_viewer()
	await settle(1.8)
	await probe_grid(game.knowledge_grid, "gyro-knowledge-locked")
	var knowledge_view: Control = game.knowledge_grid.get_child(8)
	game._show_knowledge_detail(knowledge_view, "geo_poyang")
	await settle(0.6)
	await probe_detail(game._knowledge_big_card, "gyro-knowledge-detail")
	get_window().size = Vector2i(960, 540)
	game._close_knowledge_detail()
	await settle(0.5)
	game._show_knowledge_detail(knowledge_view, "geo_poyang")
	await settle(0.6)
	await probe_detail(game._knowledge_big_card, "gyro-knowledge-small")
	print("CARD_GYRO: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
