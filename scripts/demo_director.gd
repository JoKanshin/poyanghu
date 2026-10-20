extends Control
## A 60-second real-game walkthrough. Picture, camera and prompter share one clock.
## The native prompter is a separate window and is never drawn in the recorded viewport.
const SIZE := Vector2(1280, 720)
const Physics = preload("res://scripts/motion_web.gd")
var game: Node
var stage: SubViewport
var picture: TextureRect
var prompt: Window
var heading: Label
var words: Label
var upcoming: Label
var progress: ProgressBar
var preview_checks: Dictionary = {}
var focused_card: Dictionary = {}
var manifest: Dictionary
var elapsed := 0.0
var shot_index := -1
var cue_index := 0
var running := false
var completed := false
var camera_focus := SIZE * 0.5
var camera_zoom := 1.0
var desired_zoom := 1.0
var focus_velocity := Vector2.ZERO
var zoom_velocity := 0.0
var caption: PanelContainer
var caption_label: Label
var caption_position := Vector2.ZERO
var framing_mode := "menu"
var drag: Dictionary = {}
var framing_checks := 0
var framing_trace: Array = []
var trace_at := 0.0
var events: Array = []
var failures: Array[String] = []
var water_before := 0
var patrol_before := 0
var _qa := "--demo-qa" in OS.get_cmdline_user_args()
var _capture_dir := OS.get_environment("POYANG_DEMO_SHOTS")
var _captures: Dictionary = {}
var presentation: Control
var introduction: Control
var summary: Control
var summary_images: Dictionary = {}
var summary_captured: Dictionary = {}
var caption_checks := 0
var _presentation_font: SystemFont

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _qa or OS.has_feature("movie"):
		# Keep test/recording windows out of the user's way and at a fixed canvas size.
		get_window().mode = Window.MODE_WINDOWED
		get_window().unresizable = true
		get_window().size = Vector2i(SIZE)
		get_window().position = Vector2i(-2000, -2000)
	get_tree().root.set_meta("demo_autostart_consumed", true)
	if not OS.get_user_data_dir().contains("PoyangDemo"):
		push_error("Demo requires its own PoyangDemo player profile")
		get_tree().quit(2)
		return
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/demo/timeline.json"))
	stage = SubViewport.new()
	stage.name = "RealGameViewport"
	stage.size = Vector2i(SIZE)
	stage.gui_disable_input = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.audio_listener_enable_2d = true
	stage.audio_listener_enable_3d = true
	add_child(stage)
	var background := ColorRect.new()
	background.color = Color("0a171d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	picture = TextureRect.new()
	picture.name = "FullBleedGamePicture"
	picture.texture = stage.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.size = SIZE
	add_child(picture)
	_build_presentation_pages()
	_build_subtitles()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	stage.add_child(scene)
	game = scene.get_node("Game")
	_check(game.menu_root.find_child("DemoEntryButton", true, false) == null, "The demo entry is absent from the embedded game")
	game._score_anim_id += 1
	if game._intro_playing: game._finish_intro()
	game._show_menu()
	game.event_label.hide() # Demo narration replaces the long in-game event ticker.
	game.bgm_volume = 0.48
	game.bgm_index = 0
	game._apply_bgm()
	game.score_speed = 1.3
	# Warming card faces before the clock starts avoids narration drifting during I/O.
	await game._prepare_hand_art(_cards())
	if "--demo-prompter" in OS.get_cmdline_user_args() and not _qa and not OS.has_feature("movie"):
		_build_prompter()
	running = true
	print("DEMO_CLOCK_START_FRAME ", Engine.get_process_frames())
	_advance_shot()

func _cards() -> Array:
	var out: Array = []
	for id in ["water_replenish", "dredge", "fish_restock", "floating_island", "community_comp", "habitat_protect", "patrol"]:
		var card: Dictionary = GameState.card_by_id(id)
		if not card.is_empty(): out.append(card)
	return out

func _build_prompter() -> void:
	get_window().gui_embed_subwindows = false
	prompt = Window.new()
	prompt.title = "旁白提词 · 只录游戏窗口即可（F2 显隐）"
	prompt.size = Vector2i(600, 340)
	prompt.min_size = Vector2i(500, 300)
	prompt.transient = false
	prompt.close_requested.connect(prompt.hide)
	prompt.window_input.connect(_input)
	add_child(prompt)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 22)
	prompt.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color("d6c789"))
	box.add_child(heading)
	words = Label.new()
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_vertical = Control.SIZE_EXPAND_FILL
	words.add_theme_font_size_override("font_size", 26)
	box.add_child(words)
	progress = ProgressBar.new()
	progress.max_value = float(manifest.duration)
	progress.show_percentage = false
	progress.custom_minimum_size.y = 5
	box.add_child(progress)
	upcoming = Label.new()
	upcoming.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upcoming.add_theme_font_size_override("font_size", 16)
	upcoming.add_theme_color_override("font_color", Color("aab9b0"))
	box.add_child(upcoming)
	var help := Label.new()
	help.text = "空格 暂停/继续（镜头、游戏、音乐同步暂停）  ·  F3 字幕  ·  F5 重播  ·  Esc 返回"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 13)
	box.add_child(help)
	prompt.show()
	var usable := DisplayServer.screen_get_usable_rect()
	prompt.position = Vector2i(clampi(get_window().position.x + get_window().size.x + 12, usable.position.x, usable.end.x - 600), clampi(get_window().position.y, usable.position.y, usable.end.y - 340))

func _input(event: InputEvent) -> void:
	if _qa or OS.has_feature("movie"): return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if completed: return
				get_tree().paused = not get_tree().paused
				if game: game.bgm_player.stream_paused = get_tree().paused
			KEY_F3:
				caption.visible = not caption.visible
			KEY_F2:
				if prompt: prompt.visible = not prompt.visible
				else: _build_prompter()
			KEY_F5:
				get_tree().paused = false
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().paused = false
				get_tree().change_scene_to_file("res://scenes/main.tscn")

func _process(dt: float) -> void:
	if not running: return
	if (_qa or OS.has_feature("movie")) and get_window().size != Vector2i(SIZE):
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(SIZE)
	if not get_tree().paused and not completed:
		elapsed = minf(float(manifest.duration), elapsed + dt)
		while shot_index + 1 < manifest.shots.size() and elapsed >= float(manifest.shots[shot_index + 1].at):
			_advance_shot()
		while cue_index < manifest.cues.size() and elapsed >= float(manifest.cues[cue_index].at):
			var cue: Dictionary = manifest.cues[cue_index]
			cue_index += 1
			_act(str(cue.action))
			if cue.has("focus"): _focus(cue.focus, float(cue.zoom))
		# Finish transient popups only in the specific transition gaps, never over a narrated panel.
		if elapsed >= _at("start") and elapsed < _at("start") + 2 or elapsed >= _at("continue") and elapsed < _at("crisis") - 0.5 or elapsed >= _at("repair") + 2.4 and elapsed < _at("knowledge") + 1.5 or elapsed >= _at("closing"):
			_dismiss_transients()
		_tick_drag()
		if elapsed >= float(manifest.duration): _complete()
	_check_preview_state()
	_render_camera(dt if not get_tree().paused else 0.0)
	_update_presentation()
	_capture_summary_images()
	_update_prompter()
	if not _capture_dir.is_empty():
		for t in [3, 8, 13, 17, 19, 20, 21, 22, 23, 26, 32, 36, 39, 43, 46, 53, 55]:
			if elapsed >= t and not _captures.has(t):
				_captures[t] = true
				_save_frame.call_deferred(t)

func _advance_shot() -> void:
	shot_index += 1
	var shot: Dictionary = manifest.shots[shot_index]
	_act(str(shot.action))
	_focus(shot.focus, float(shot.zoom))

func _focus(point: Array, zoom: float) -> void:
	desired_zoom = zoom

func _bounds(control: Control) -> Rect2:
	var tf := control.get_global_transform()
	var rect := Rect2(tf * Vector2.ZERO, Vector2.ZERO)
	for p in [Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]: rect = rect.expand(tf * p)
	return rect

func _card_info(id: String) -> Dictionary:
	for info in game.card_infos:
		if str(info.card_id) == id: return info
	return {}

func _panel_bounds(control: Control) -> Rect2:
	var parent: Node = control
	while parent and not parent is PanelContainer: parent = parent.get_parent()
	return _bounds(parent) if parent is Control else _bounds(control)

func _subject_bounds() -> Rect2:
	if not drag.is_empty():
		return _bounds(drag.info.panel).grow(48)
	match framing_mode:
		"monitor", "dismiss_crisis": return _bounds(game.right_panel).grow(30)
		"choose":
			# Keep the complete hand AND the investment lever in the shot.
			var rect := _bounds(game.tier_lever)
			for info in game.card_infos: rect = rect.merge(_bounds(info.panel))
			return rect.grow(24)
		"stage_patrol", "stage_water":
			if not focused_card.is_empty() and is_instance_valid(focused_card.panel): return _bounds(focused_card.panel).grow(70)
			return _bounds(game.staged_board).grow(24)
		"settle", "repair":
			if game.popup_root.visible: return _bounds(game.popup_panel).grow(24)
			var rect := _bounds(game.right_panel)
			for info in game.card_infos:
				if bool(info.get("selected", false)) and is_instance_valid(info.panel): rect = rect.merge(_bounds(info.panel))
			return rect.grow(24)
		"crisis": return _panel_bounds(game.crisis_body).grow(24)
		"knowledge":
			if is_instance_valid(game._knowledge_big_card): return _bounds(game._knowledge_big_card).grow(110)
		"knowledge_text":
			if is_instance_valid(game._knowledge_big_card):
				return _bounds(game._knowledge_big_card).merge(_panel_bounds(game.knowledge_detail_body)).grow(24)
	return Rect2(Vector2.ZERO, Vector2(stage.size))

func _render_camera(dt: float) -> void:
	var output := get_viewport_rect().size
	if stage.size != Vector2i(output): stage.size = Vector2i(output)
	var source := Vector2(stage.size)
	picture.size = source
	var subject := _subject_bounds().intersection(Rect2(Vector2.ZERO, source))
	# The supplied review film uses steady, slide-like compositions. Keep the live
	# game whole between the opening and closing pages; no camera hunting or crops.
	camera_zoom = 1.0
	picture.scale = Vector2.ONE
	picture.position = Vector2.ZERO
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	var projected := subject
	framing_checks += 1
	_check(Rect2(Vector2(-1, -1), output + Vector2(2, 2)).encloses(projected), "Whole narrated subject stays in frame: " + framing_mode)
	if elapsed >= trace_at:
		trace_at += 0.25
		framing_trace.append({"at": snappedf(elapsed, 0.01), "mode": framing_mode, "screen": [projected.position.x, projected.position.y, projected.size.x, projected.size.y], "zoom": camera_zoom, "bgm": game.bgm_index})
	_update_subtitles(subject, 1.0, Vector2.ZERO, dt)

func _slide_label(parent: Control, text: String, point: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.size = dimensions
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", _presentation_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_presentation_pages() -> void:
	_presentation_font = SystemFont.new()
	_presentation_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	presentation = Control.new()
	presentation.name = "ReviewPresentation"
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	introduction = Control.new()
	introduction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation.add_child(introduction)
	var gold := Color("e5d293")
	var paper := Color("f1f2e8")
	var muted := Color("b3c3c0")
	_slide_label(introduction, "鄱阳归翎 · 生态修复手记", Vector2(56, 112), Vector2(1168, 64), 38, gold)
	_slide_label(introduction, "立意与核心玩法", Vector2(56, 182), Vector2(500, 40), 22, gold)
	_slide_label(introduction, "在出牌与取舍中\n理解湿地生态保护", Vector2(56, 260), Vector2(500, 112), 32, paper)
	_slide_label(introduction, "面向青少年与亲子", Vector2(56, 406), Vector2(500, 40), 24, muted)
	_slide_label(introduction, "16 回合跨越 4 年", Vector2(56, 458), Vector2(500, 44), 27, gold)
	_slide_label(introduction, "选择行动卡，分配投入，观察变化", Vector2(56, 518), Vector2(510, 50), 22, paper)
	_slide_label(introduction, "以真实保护行动为原型的卡牌策略游戏", Vector2(584, 600), Vector2(640, 40), 20, muted)
	summary = Control.new()
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation.add_child(summary)
	_slide_label(summary, "技术与交互亮点", Vector2(56, 112), Vector2(1168, 64), 38, gold)
	_slide_label(summary, "鄱阳归翎 · 生态修复手记", Vector2(56, 180), Vector2(1168, 40), 22, muted)
	var columns := [
		["wetland", "湿地生态沙盘", "生态指标驱动场景变化\n让决策结果在湖面上可见"],
		["card", "投入与卡牌交互", "先在已打出区看清牌面\n再自动归入待执行区"],
		["settlement", "可追溯结算反馈", "逐项呈现数值变化及来源\n支持观察、推演与复盘"]
	]
	for i in range(columns.size()):
		var x := 56.0 + i * 408.0
		var preview := TextureRect.new()
		preview.position = Vector2(x, 246)
		preview.size = Vector2(352, 224)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary.add_child(preview)
		summary_images[str(columns[i][0])] = preview
		_slide_label(summary, str(columns[i][1]), Vector2(x, 502), Vector2(368, 46), 27, gold)
		_slide_label(summary, str(columns[i][2]), Vector2(x, 566), Vector2(368, 90), 22, paper)

func _update_presentation() -> void:
	var output := get_viewport_rect().size
	var scale_factor := minf(output.x / SIZE.x, output.y / SIZE.y)
	presentation.scale = Vector2.ONE * scale_factor
	presentation.position = (output - SIZE * scale_factor) * 0.5
	introduction.visible = elapsed < _at("monitor")
	summary.visible = elapsed >= _at("closing")
	picture.visible = not summary.visible
	if introduction.visible:
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size = Vector2(640, 360) * scale_factor
		picture.position = presentation.position + Vector2(584, 228) * scale_factor

func _capture_summary_images() -> void:
	for entry in [{"at": 8.0, "key": "wetland"}, {"at": 20.0, "key": "card"}, {"at": 26.0, "key": "settlement"}]:
		var key := str(entry.key)
		if elapsed < float(entry.at) or summary_captured.has(key): continue
		if key == "settlement":
			if not game.popup_root.visible or game.popup_title.text != "结算反馈": continue
			if game.popup_root.modulate.a < 0.99 or absf(game.popup_panel.scale.x - 1.0) > 0.015: continue
			if game._popup_reveal and game._popup_reveal.is_valid(): game._popup_reveal.kill()
			game.popup_body.visible_characters = -1
		summary_captured[key] = true
		_store_summary_image.call_deferred(key)

func _store_summary_image(key: String) -> void:
	await RenderingServer.frame_post_draw
	var snapshot := stage.get_texture().get_image()
	if key == "card" and not focused_card.is_empty():
		var bounds := _bounds(focused_card.panel).grow(10).intersection(Rect2(Vector2.ZERO, Vector2(stage.size)))
		snapshot = snapshot.get_region(Rect2i(bounds))
	elif key == "settlement" and game.popup_root.visible:
		var bounds := _bounds(game.popup_panel).grow(4).intersection(Rect2(Vector2.ZERO, Vector2(stage.size)))
		snapshot = snapshot.get_region(Rect2i(bounds))
	summary_images[key].texture = ImageTexture.create_from_image(snapshot)

func _build_subtitles() -> void:
	caption = PanelContainer.new()
	caption.name = "NarrationSubtitles"
	caption.z_index = 20
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0a171d")
	style.border_color = Color(0.82, 0.76, 0.52, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	caption.add_theme_stylebox_override("panel", style)
	add_child(caption)
	caption_label = Label.new()
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption_label.clip_text = true
	caption_label.add_theme_font_size_override("font_size", 24)
	caption_label.add_theme_font_override("font", _presentation_font)
	caption_label.add_theme_color_override("font_color", Color("fff9df"))
	caption_label.add_theme_constant_override("outline_size", 2)
	caption_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	caption.add_child(caption_label)

func _update_subtitles(subject: Rect2, zoom: float, offset: Vector2, dt: float) -> void:
	var item: Dictionary = {}
	for line in manifest.captions:
		if elapsed >= float(line.at) and elapsed < float(line.until):
			item = line
			break
	if item.is_empty(): return
	var text := str(item.text)
	var output := get_viewport_rect().size
	# A fixed subtitle rail: neither position nor panel size changes between sentences.
	if caption_label.text != text: caption_label.text = text
	caption.custom_minimum_size = Vector2(minf(640, output.x - 40), 56)
	caption.size = caption.custom_minimum_size
	caption.position = Vector2((output.x - caption.size.x) * 0.5, 20)
	caption.modulate.a = 1.0
	caption_checks += 1
	_check(caption.position.y == 20 and caption.size.y == 56 and caption.modulate.a == 1.0, "Subtitles stay fixed and fully visible inside the picture")

func _update_prompter() -> void:
	if not prompt or shot_index < 0: return
	var shot: Dictionary = manifest.shots[shot_index]
	heading.text = "%02d:%02d / %02d:%02d  ·  %s%s" % [int(elapsed) / 60, int(elapsed) % 60, int(manifest.duration) / 60, int(manifest.duration) % 60, shot.title, "  [已暂停]" if get_tree().paused else ""]
	words.text = str(shot.text)
	progress.value = elapsed
	if completed:
		upcoming.text = "演示完成，自动返回主菜单。"
	else:
		var next := "结束" if shot_index + 1 == manifest.shots.size() else str(manifest.shots[shot_index + 1].title)
		upcoming.text = "本段剩余 %.1f 秒  ·  下一段：%s" % [maxf(0, float(shot.until) - elapsed), next]

func _act(action: String) -> void:
	if action != "continue": framing_mode = action
	events.append({"at": snappedf(elapsed, 0.01), "action": action, "bgm": game.bgm_index})
	print("DEMO_CUE ", snappedf(elapsed, 0.01), " ", action)
	match action:
		"start":
			game._on_difficulty_pick(GameState.Difficulty.EASY)
			game.seed_input.text = "20261020"
			game._on_start_pressed()
			GameState._is_settlement_preview = true # A reproducible demo fixture; suppress unrelated random interrupts.
			GameState.pending_crisis = {}
			GameState.forecast_crisis = {}
			GameState.music_crisis_recovery = {}
			GameState.metrics["vegetation"] = 65
			GameState.metrics["water_quality"] = 66
			GameState.metrics["fish"] = 60
			GameState.metrics["community"] = 65
			game._update_hud()
			game._update_3d()
		"monitor":
			_check(game._current_phase == "allocate", "Game entered the real allocation phase")
			_check(game.bgm_index == 0, "Normal scene uses theme")
		"choose":
			_install_hand()
			game._set_play_tier("deep", true)
			patrol_before = int(GameState.metrics.fish)
		"stage_patrol":
			_stage_card("patrol")
		"settle":
			_check(game._ordered_staged_indices().size() == 1, "Patrol really entered the play queue")
			game._finish_turn()
		"continue":
			_check(int(GameState.metrics.fish) > patrol_before, "Real patrol settlement changed fish")
			_dismiss_transients()
		"crisis":
			_dismiss_transients()
			GameState.pending_crisis = GameState.crisis_by_id("drought").duplicate(true)
			water_before = int(GameState.metrics.water_level)
			GameState._resolve_pending_crisis()
			game._update_bgm_state()
			_check(game.crisis_root.visible, "Drought alert is visible during its narration")
			_check(game.bgm_index == 1, "Crisis scene uses danger music")
			_check(int(GameState.metrics.water_level) < water_before, "Actual drought lowers water")
		"dismiss_crisis":
			if game.crisis_root.visible: game._on_crisis_dismiss()
		"stage_water":
			_install_hand()
			game._set_play_tier("deep", true)
			_stage_card("water_replenish")
		"repair":
			_check(game._ordered_staged_indices().size() == 1, "Water replenishment is queued")
			game._finish_turn()
		"knowledge":
			_dismiss_transients()
			if not GameState.has_unresolved_music_crisis():
				# Settlement holds the previous mood until allocation resumes; this narrated cut has already recovered.
				game._bgm_danger = false
				game.bgm_index = 0
				game._apply_bgm()
			game._update_bgm_state()
			_check(not GameState.has_unresolved_music_crisis(), "Actual water card resolves drought recovery targets")
			_check(game.bgm_index == 0, "Resolved crisis returns to theme")
			_show_crane()
		"closing":
			if game.knowledge_detail.visible: game._close_knowledge_detail()
			if game.knowledge_viewer.visible: game._close_knowledge_viewer()
			_dismiss_transients()

func _install_hand() -> void:
	game.current_hand = _cards()
	game.play_deal_anim = false
	game._build_hand_panel()
	game._sort_animating = false
	GameState.funds = maxi(GameState.funds, 180)
	GameState.turn_budget = maxi(GameState.turn_budget, 180)
	game._update_hud()

func _stage_card(id: String) -> void:
	for info in game.card_infos:
		if str(info.card_id) != id: continue
		var panel: Control = info.panel
		game._card_press_panel = panel
		game._card_press_origin = panel.get_global_transform() * (panel.size * 0.5)
		game._card_press_elapsed = 1.0
		game._start_card_drag()
		var point: Vector2 = game.card_box.get_global_transform() * Vector2(game.card_box.size.x * 0.5, -115.5)
		focused_card = info
		drag = {"info": info, "from": game._card_press_origin, "to": point, "started": elapsed, "duration": 1.2 if id == "patrol" else 0.6, "preview_seconds": 2.4 if id == "patrol" else 1.2}
		return
	_check(false, "Missing demo card " + id)

func _tick_drag() -> void:
	if drag.is_empty(): return
	var u := clampf((elapsed - float(drag.started)) / float(drag.duration), 0, 1)
	var eased := 0.5 - 0.5 * cos(PI * u)
	var point: Vector2 = Vector2(drag.from).lerp(Vector2(drag.to), eased) + Vector2(0, -sin(PI * u) * 44)
	game._update_card_drag_pose(point, Vector2.ZERO)
	if u >= 1:
		var info: Dictionary = drag.info
		game._finish_card_pointer(Vector2(drag.to))
		_check(bool(info.selected), "Tracked card landed in the real play queue")
		_check(str(info.stage_zone) == "preview", "Upward release uses the original full-size preview area")
		info["preview_left"] = float(drag.preview_seconds)
		events.append({"at": snappedf(elapsed, 0.01), "action": "preview_" + str(info.card_id)})
		drag = {}

func _dismiss_transients() -> void:
	if game._score_animating: return
	if game.popup_root.visible:
		game.popup_body.visible_characters = -1
		game._on_popup_button()
	if game.crisis_root.visible and framing_mode in ["start", "continue"]:
		game._on_crisis_dismiss()

func _show_crane() -> void:
	var kid := ""
	for id in GameState.KNOWLEDGE_CARDS:
		if str(GameState.KNOWLEDGE_CARDS[id].get("name", "")).contains("白鹤"):
			kid = str(id)
			break
	_check(not kid.is_empty(), "White crane knowledge card exists")
	if kid.is_empty(): return
	Knowledge.unlock(kid)
	game._open_knowledge_viewer()
	await get_tree().process_frame
	var index: int = Knowledge.all_ids().find(kid)
	var view: Control = game.knowledge_grid.get_child(index)
	game._show_knowledge_detail(view, kid)

func _check(ok: bool, message: String) -> void:
	if not ok:
		if failures.has(message): return
		failures.append(message)
		push_error("DEMO: " + message)

func _save_frame(t: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_capture_dir.path_join("%02d.png" % t))

func _complete() -> void:
	completed = true
	_check(shot_index == 7 and cue_index == manifest.cues.size(), "All narration and action cues completed")
	_check(summary.visible, "The closing review page is visible")
	_check(summary_captured.size() == 3, "All three review images were captured from the real game")
	var file := FileAccess.open("user://demo-run.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"duration": elapsed, "events": events, "failures": failures, "framing_checks": framing_checks, "framing_trace": framing_trace, "preview_checks": preview_checks, "caption_checks": caption_checks, "summary_images": summary_captured.keys(), "style": "steady review slides"}, "  "))
	print("DEMO_DONE: ", elapsed, " seconds, ", failures.size(), " failures")
	if (_qa and not "--demo-check-return" in OS.get_cmdline_user_args()) or OS.has_feature("movie"):
		get_tree().quit(0 if failures.is_empty() else 1)
	else:
		# End the presentation itself, then restore a usable main menu.
		running = false
		get_tree().paused = false
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _at(action: String) -> float:
	for entry in manifest.shots + manifest.cues:
		if str(entry.action) == action: return float(entry.at)
	return INF

func _check_preview_state() -> void:
	for target in [{"at": 20.0, "id": "patrol", "zone": "preview"}, {"at": 23.0, "id": "patrol", "zone": "board"}, {"at": 36.0, "id": "water_replenish", "zone": "preview"}]:
		var key := str(target.id) + "_" + str(target.zone)
		if elapsed < float(target.at) or preview_checks.has(key): continue
		var info := _card_info(str(target.id))
		if info.is_empty():
			_check(false, "Missing tracked preview card " + key)
			continue
		preview_checks[key] = {"at": elapsed, "zone": info.get("stage_zone", ""), "scale": info.panel.scale.x, "board_height": game.staged_board.size.y}
		_check(str(info.get("stage_zone", "")) == str(target.zone), "Original preview-to-board lifecycle: " + key)
		_check(absf(game.staged_board.size.y - 124) < 0.1, "Wooden board retains its original height")
		if str(target.zone) == "preview": _check(info.panel.scale.x > 0.95, "Preview shows a full-size card: " + key)
		else: _check(absf(info.panel.scale.x - game.BOARD_CARD_SCALE) < 0.03, "Docked card returns to its original miniature size")
