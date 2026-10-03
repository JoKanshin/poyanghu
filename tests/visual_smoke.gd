extends Node
## Run in an isolated test project/user directory; see docs/UI_REDESIGN.md.
var game: Node
var failures: Array[String] = []
var checks: int = 0          # 断言总数（最后打印出来，证据里就有确切条数）
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

func check(ok: bool, message: String) -> void:
	checks += 1
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
	# 主菜单 → 更新日志：确认 v0.1.2 条目渲染出来、且「当前版本」跟着 Changelog.CURRENT 走
	game._show_changelog_panel()
	await settle(0.7)
	check(game.menu_changelog_panel.visible, "更新日志面板应能打开")
	await capture("01a-changelog-v012")
	game._on_changelog_back()
	await settle(0.4)
	# ---------------- 知识卡图鉴（主页入口）----------------
	check(Knowledge.collected_count() == 0, "新账号不该有已收集的知识卡")
	game._open_knowledge_viewer()
	await settle(1.3)
	check(game.knowledge_viewer.visible, "知识卡图鉴应能打开")
	check(game.knowledge_grid.get_child_count() == 8, "图鉴应铺出 8 张知识卡，实际 %d" % game.knowledge_grid.get_child_count())
	check(game.knowledge_count_label.text == "已收集 0 / 8", "计数应为 0 / 8，实际「%s」" % game.knowledge_count_label.text)
	# 真实鼠标可能恰好停在某张卡上（会把底色换成悬停样式），查颜色前先复位
	for v in game.knowledge_grid.get_children():
		game._on_viewer_card_unhover(v)
	await settle(0.3)
	var first_view: Control = game.knowledge_grid.get_child(0)
	var locked_sb: StyleBoxFlat = (first_view.get_meta("panel") as PanelContainer).get_theme_stylebox("panel")
	check(locked_sb.bg_color.is_equal_approx(Color("d9d6cc")), "未收集卡应是灰卡底，实际 %s" % locked_sb.bg_color)
	await capture("01b-knowledge-locked")
	# 点开一张未收集的 —— 只该看到「未收集」与「？」
	var click_ev := InputEventMouseButton.new()
	click_ev.pressed = true
	click_ev.button_index = MOUSE_BUTTON_LEFT
	game._on_knowledge_card_click(click_ev, first_view, "plant_kucao")
	await settle(2.6)   # 详情正文是打字机（最长 2.5s），等它写完再拍
	check(game.knowledge_detail.visible, "点未收集的卡也该打开详情（显示未收集 + ？）")
	check(game.knowledge_detail_title.text == "？？？", "未收集详情标题应是 ？？？，实际「%s」" % game.knowledge_detail_title.text)
	check(game.knowledge_detail_body.text.find("未收集") != -1, "未收集详情该写明「未收集」")
	check(game.knowledge_detail_body.text.find("？") != -1, "未收集详情该出现「？」")
	await capture("01c-knowledge-locked-detail")
	game._close_knowledge_detail()
	game._close_knowledge_viewer()
	await settle(0.5)
	# 收集两张后重开：这两张点亮，其余仍是灰卡
	Knowledge.unlock("plant_kucao")
	Knowledge.unlock("bird_baihe")
	game._open_knowledge_viewer()
	await settle(1.3)
	check(game.knowledge_count_label.text == "已收集 2 / 8", "计数应为 2 / 8，实际「%s」" % game.knowledge_count_label.text)
	for v in game.knowledge_grid.get_children():
		game._on_viewer_card_unhover(v)
	await settle(0.3)
	var lit_view: Control = game.knowledge_grid.get_child(0)
	var lit_sb: StyleBoxFlat = (lit_view.get_meta("panel") as PanelContainer).get_theme_stylebox("panel")
	check(lit_sb.bg_color.is_equal_approx(Color("f1e8cc")), "已收集卡应回到纸卡底，实际 %s" % lit_sb.bg_color)
	var locked2: Control = game.knowledge_grid.get_child(2)
	var locked2_sb: StyleBoxFlat = (locked2.get_meta("panel") as PanelContainer).get_theme_stylebox("panel")
	check(locked2_sb.bg_color.is_equal_approx(Color("d9d6cc")), "没收集的卡仍旧是灰的")
	await capture("01d-knowledge-mixed")
	game._on_knowledge_card_click(click_ev, lit_view, "plant_kucao")
	await settle(2.6)
	check(game.knowledge_detail_title.text == "苦草", "已收集详情标题应是卡名，实际「%s」" % game.knowledge_detail_title.text)
	check(game.knowledge_detail_body.text.find("未收集") == -1, "已收集详情不该出现「未收集」")
	check(game.knowledge_detail_body.text.find("生态角色") != -1, "已收集详情该有「生态角色」")
	check(game.knowledge_detail_body.text.find("关联行动") != -1, "已收集详情该显示「关联行动」标签")
	await capture("01e-knowledge-unlocked-detail")
	game._close_knowledge_detail()
	game._close_knowledge_viewer()
	await settle(0.6)
	game._on_title_start()
	await capture("02-difficulty")
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20260930"
	game._on_start_pressed()
	await close_popups()
	await settle(1.0)
	check(game.card_infos.size() > 0, "Starting a run must deal cards")
	check(game.wetland.house_sites.size() >= 12, "Village should spread around the lake")
	for site in game.wetland.house_sites:
		check(game.wetland._is_land(site) and game.wetland._near_water(site), "Cottage must be on near-shore land")
		check(site.distance_to(game.wetland.CREEPER_ANCHOR) > 0.11, "Cottage covers Creeper clearing")
	var original_settlement: float = GameState.settlement
	GameState.settlement = 100.0
	GameState.metrics_changed.emit()
	await settle(0.25)
	check(game.wetland.house_target_count == game.wetland.house_sites.size(), "Expansion must target every cottage")
	check(game.wetland.house_progress[-1] > 0.0, "Expansion must animate construction")
	GameState.settlement = 0.0
	GameState.metrics_changed.emit()
	await settle(0.25)
	check(game.wetland.house_progress[0] < 1.0, "Wetland recovery must animate cottage removal")
	GameState.settlement = original_settlement
	GameState.metrics_changed.emit()
	var flying_bird: Dictionary = game.wetland.bird_agents[0]
	flying_bird["state"] = 3
	flying_bird["pos"] = Vector2(0.42, 0.50)
	flying_bird["target"] = Vector2(0.35, 0.50)
	game.wetland._process_birds(0.05)
	check(absf(absf(float(flying_bird["angle"])) - PI) < 0.01, "Flying bird must face its destination")
	for info in game.card_infos:
		check(info.panel.size.is_equal_approx(Vector2(122, 165)), "Card footprint changed: " + str(info.panel.size))
	check(game.end_turn_btn.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "End turn button exceeds viewport")
	await capture("03-gameplay")
	# ---------------- 手牌陀螺仪（与牌库 / 知识卡图鉴同一套）----------------
	# 测试机有人在用鼠标：牌堆被点一下就会弹出牌库全屏层，把后面所有画面盖住。
	# 拍手牌之前先把这些层收干净（本测试自己不开它们）。
	game._close_deck_viewer()
	game._close_knowledge_viewer()
	await settle(0.4)
	var probe_info: Dictionary = game.card_infos[game.card_infos.size() - 1]
	var probe_panel: PanelContainer = probe_info["panel"]
	check(probe_panel.material is ShaderMaterial, "手牌应挂上陀螺仪材质")
	var pc: Vector2 = probe_panel.get_global_rect().get_center()
	# 注入一个偏离卡片中心的悬停点（右上 40, -30），倾斜才有非零分量
	for i in 24:
		game._update_card_hover(0.05, pc + Vector2(40, -30))
	# 抬起动画会把这 24 帧里的牌挪走，中心要在走完之后重新取
	pc = probe_panel.get_global_rect().get_center()
	var pmat: ShaderMaterial = probe_panel.material
	var tx: float = pmat.get_shader_parameter("tilt_x")
	var ty: float = pmat.get_shader_parameter("tilt_y")
	check(absf(tx) > 0.02 or absf(ty) > 0.02, "悬停的手牌应产生非零倾斜，实际 tx=%.4f ty=%.4f" % [tx, ty])
	check(pc.distance_to(Vector2(pmat.get_shader_parameter("card_center"))) < 8.0,
		"倾斜中心应是这张牌的中心")
	# 冻住 process：否则下一帧就用「真实鼠标不在牌上」把倾斜抹掉了，拍不出来
	game.set_process(false)
	await settle(0.3)
	await capture("03b-hand-gyro")
	game.set_process(true)
	# 鼠标移开 → 倾斜收回
	for i in 24:
		game._update_card_hover(0.05, Vector2(-500, -500))
	check(absf(float(pmat.get_shader_parameter("tilt_x"))) < 0.02 and absf(float(pmat.get_shader_parameter("tilt_y"))) < 0.02,
		"鼠标移开后手牌倾斜应收回到零")
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
	# ---------------- 点开的那张放大牌也要会晃 ----------------
	var any_view: Control = game.deck_viewer_grid.get_child(0)
	game._show_card_detail(any_view, any_view.get_meta("card"))
	await settle(0.9)
	var big: Control = game._detail_big_card
	check(big != null and big.material is ShaderMaterial, "详情大牌应挂上陀螺仪材质")
	var bc: Vector2 = big.get_global_transform() * big.pivot_offset
	for i in 24:
		game._process_detail_gyro(0.05, bc + Vector2(50, -40))
	var bmat: ShaderMaterial = big.material
	check(absf(float(bmat.get_shader_parameter("tilt_x"))) > 0.02 or absf(float(bmat.get_shader_parameter("tilt_y"))) > 0.02,
		"鼠标压在大牌上时应产生倾斜")
	check(bc.distance_to(Vector2(bmat.get_shader_parameter("card_center"))) < 6.0,
		"大牌的倾斜中心应是它自己的中心")
	game.set_process(false)
	await settle(0.3)
	await capture("05b-detail-gyro")
	game.set_process(true)
	game._close_card_detail()
	await settle(0.3)
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
	# ---------------- 游戏内收集 → 图鉴解锁 的链路 ----------------
	# 走真正的 _show_knowledge（玩家弹知识卡时实际走的那条路径），
	# 验「弹出来了 = 收进收藏了」，再回主页图鉴确认它点亮。
	Knowledge.reset_all()
	check(Knowledge.collected_count() == 0, "重置后不该有已收集的知识卡")
	var probe_kid := "cons_compensate"
	check(not Knowledge.is_collected(probe_kid), "探针卡此刻应为未收集")
	game._show_knowledge(probe_kid)
	await settle(0.5)
	check(Knowledge.is_collected(probe_kid), "游戏内弹出的知识卡应被记入收藏：" + probe_kid)
	check(Knowledge.collected_count() == 1, "收集数应为 1，实际 %d" % Knowledge.collected_count())
	await close_popups()
	game._show_menu()          # 从主页看图鉴 —— 玩家实际的路径（顺带把对局 HUD 收起来）
	await settle(0.7)
	game._open_knowledge_viewer()
	await settle(1.3)
	check(game.knowledge_count_label.text == "已收集 1 / 8", "图鉴计数应变成 1 / 8，实际「%s」" % game.knowledge_count_label.text)
	await capture("13-knowledge-in-game-unlock")
	game._close_knowledge_viewer()
	await settle(0.4)
	print("VISUAL_SMOKE: ", "PASS" if failures.is_empty() else "FAIL",
		" (", failures.size(), " failures / ", checks, " checks)")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
