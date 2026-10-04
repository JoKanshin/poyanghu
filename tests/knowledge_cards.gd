extends Node
## Run only in the isolated project made by prepare_visual_test.py.
var checks := 0
var failures: Array[String] = []
var game: Node
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

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
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + ".png"))

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Knowledge tests require an isolated user directory")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	Knowledge.reset_all()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.4)
	if game._intro_playing:
		game._finish_intro()
	await settle(1.0)
	game._open_knowledge_viewer()
	await settle(1.8)
	check(game.knowledge_grid.get_child_count() == 40, "All 40 cards must appear")
	check(game.knowledge_count_label.text == "已收集 0 / 40", "New profile starts at 0 / 40")
	game._show_knowledge_detail(game.knowledge_grid.get_child(8), "geo_poyang")
	check(game.knowledge_detail_title.text == "？？？", "Locked card title stays hidden")
	check(not "source_url" in game.knowledge_detail_body.text and not "https://" in game.knowledge_detail_body.text, "Locked card sources stay hidden")
	game._close_knowledge_detail()
	game._close_knowledge_viewer()
	game._show_knowledge("geo_poyang")
	check(Knowledge.is_collected("geo_poyang"), "Gameplay popup collects the new card")
	check("资料来源" in game.popup_body.text, "Gameplay popup includes source")
	game.popup_root.visible = false
	for kid in Knowledge.all_ids():
		Knowledge.unlock(kid)
	Knowledge._load()
	check(Knowledge.collected_count() == 40, "All new cards survive save reload")
	game._open_knowledge_viewer()
	await settle(1.8)
	check(game.knowledge_count_label.text == "已收集 40 / 40", "Full collection count is correct")
	for i in Knowledge.all_ids().size():
		var kid: String = Knowledge.all_ids()[i]
		var view: Control = game.knowledge_grid.get_child(i)
		var panel: PanelContainer = view.get_meta("panel")
		check(panel.size.x <= 122.1 and panel.size.y <= 165.1, "%s must fit its card texture: %s" % [kid, panel.size])
		check(game.KNOWLEDGE_ART_TILE.has(kid), "%s needs a theme illustration" % kid)
		game._show_knowledge_detail(view, kid)
		check(game.knowledge_detail_title.text == GameState.KNOWLEDGE_CARDS[kid]["name"], "%s opens the correct title" % kid)
		if i >= 8:
			check(GameState.KNOWLEDGE_CARDS[kid]["source_url"] in game.knowledge_detail_body.text, "%s opens its source link" % kid)
	game._close_knowledge_detail()
	await capture("knowledge-all-desktop")
	for window_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().size = window_size
		await settle(0.4)
		game._show_knowledge_detail(game.knowledge_grid.get_child(32), "protect_scientific_release")
		await settle(2.6)
		var bounds := get_viewport().get_visible_rect()
		check(bounds.encloses(game._knowledge_big_card.get_global_rect()), "Enlarged card must fit window")
		check(bounds.encloses(game.knowledge_detail_title.get_global_rect()), "Long title must fit window")
		check(bounds.encloses(game.knowledge_detail_body.get_global_rect()), "Body must fit window")
		check(game.knowledge_detail_body.scroll_active, "Long details need scrolling")
		await capture("knowledge-detail-%d" % window_size.x)
		game._close_knowledge_detail()
	game._show_knowledge_detail(game.knowledge_grid.get_child(26), "mech_wetland_carbon")
	check("初中拓展" in game.knowledge_detail_body.text, "Carbon card carries age-level label")
	await settle(2.6)
	await capture("knowledge-carbon-small")
	print("KNOWLEDGE_UI: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
