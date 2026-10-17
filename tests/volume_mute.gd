extends Node
## 音量滑条 0% 的回归：0 必须真的没有声音。
## 0.2.9 的 bug 是 linear_to_db(maxf(v, 0.001)) 在 0% 时停在 -60 dB，安静段落里还听得到 BGM。
## 这里断言三条：播放器落到静音底、主总线被 mute、0% 时播音效也是静音底，另外量一次主总线峰值。
## 用法：隔离副本 + 真窗口（peak 需要真实音频线程），headless 量不到输出电平。

var checks := 0
var failures := 0
var game: Node


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Run in an isolated test project")
		get_tree().quit(1)
		return
	# 看门狗：任何一处 await 被打断时窗口不会自己关，这里兜底退出，别把跑测试的终端挂住。
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("WATCHDOG: 测试 30 秒未退出")
		get_tree().quit(2))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await wait(1.2)

	var silent: float = float(game.SILENT_VOLUME_DB)
	check(silent <= -80.0, "静音底是 -80 dB 或更低")

	game._on_volume_changed(0.0)
	await wait(0.8)
	check(is_equal_approx(game.bgm_player.volume_db, silent), "0% 时 BGM 播放器落到静音底")
	check(is_equal_approx(game._deal_sfx_player.volume_db, silent), "0% 时发牌音效播放器落到静音底")
	check(AudioServer.is_bus_mute(0), "0% 时主总线被静音")

	game.play_sfx("ding")
	await wait(0.4)
	var quietest := 0.0
	for p in game._sfx_players:
		quietest = minf(quietest, p.volume_db)
	check(quietest <= silent, "0% 时播出的音效也是静音底")
	var peak_zero := AudioServer.get_bus_peak_volume_left_db(0, 0)
	check(peak_zero <= -150.0, "0%% 时主总线峰值在静音底（实测 %.1f dB）" % peak_zero)

	game._on_volume_changed(50.0)
	await wait(1.0)
	check(not AudioServer.is_bus_mute(0), "拉回 50% 后主总线解除静音")
	check(absf(game.bgm_player.volume_db + 6.02) < 0.2, "50%% 对应 -6 dB（实测 %.2f）" % game.bgm_player.volume_db)
	var peak_half := AudioServer.get_bus_peak_volume_left_db(0, 0)
	check(peak_half > peak_zero + 20.0, "50%% 时主总线重新有输出（%.1f vs %.1f）" % [peak_half, peak_zero])

	# 播片与 BGM 共用同一个音量：0% 时播片也必须是静音底。
	game._on_volume_changed(0.0)
	game._play_ending()
	await wait(0.9)
	check(is_equal_approx(game.ending_player.volume_db, silent), "0% 时结尾播片也是静音底")
	game._finish_ending()
	await wait(0.4)

	# 收尾恢复 80%，让同一个副本下次跑起来还是默认听感。
	game._on_volume_changed(80.0)
	await wait(0.4)
	check(not AudioServer.is_bus_mute(0), "收尾恢复 80% 时总线不静音")

	print("VOLUME_MUTE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
