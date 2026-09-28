extends SceneTree
## 「指标 → 拨款」链路单元测试（0.0.5）
## 用法：<godot> --headless --path . --script res://tools/verify_funding.gd
## 覆盖三件事：① FUNDING_STEPS 的取档规则；② start_new_turn 真的把钱按表加上；
##              ③ 存档 serialize/load_state 不丢这个新字段。

var fails := 0
var checks := 0

func _initialize() -> void:
	var GS: Node = root.get_node_or_null("GameState")
	var Tal: Node = root.get_node_or_null("Talents")
	if GS == null or Tal == null:
		print("FAIL: autoload 缺失")
		quit(1); return
	Tal.reset_all()
	GS.difficulty = 2                      # 困难：拨款惩罚 35
	GS.run_seed = 424242                   # 固定种子，开局指标可复现
	GS.reset_game()

	# ① 取档规则
	var cases := [
		[{"community": 75, "birds": 75}, 25, "两档上限（15+10）"],
		[{"community": 70, "birds": 70}, 25, "恰好等于阈值（含等号）"],
		[{"community": 62, "birds": 60}, 8, "社区中档 +8、候鸟未达标 0"],
		[{"community": 59, "birds": 69}, 0, "差一点点都不给"],
		[{"community": 20, "birds": 20}, -20, "两项崩塌（−15−5）"],
		[{"community": 30, "birds": 25}, -20, "下限阈值含等号"],
		[{"community": 55, "birds": 55}, 0, "开局常见值：本项不给钱"],
	]
	for c in cases:
		var snap: Dictionary = GS.metrics.duplicate()
		for k in c[0]:
			GS.metrics[k] = c[0][k]
		var got: int = int(GS._metric_funding())
		_expect(got, int(c[1]), "取档 %s → %+d 万（%s）" % [str(c[0]), int(c[1]), str(c[2])])
		GS.metrics = snap

	# ② start_new_turn 真的把钱加上（且只加一次）
	for extra_case in [{"community": 75, "birds": 75}, {"community": 62, "birds": 60}, {"community": 20, "birds": 20}]:
		GS.metrics = GS.metrics.duplicate()
		for k in extra_case:
			GS.metrics[k] = extra_case[k]
		GS.carry = 0
		var op: int = GS.OPERATION_COST + int(Tal.get_bonus("operation"))
		var expect: int = GS.BASE_FUNDING + int(GS._metric_funding()) - int(GS.FUNDING_PENALTY[2]) \
			+ int(Tal.get_bonus("funding")) - op
		GS.start_new_turn()
		_expect(int(GS.funds), expect, "start_new_turn 资金（%s）" % str(extra_case))
		_expect(int(GS.last_metric_funding), int(GS._metric_funding()),
			"last_metric_funding 与表一致")
		GS.metrics = GS.metrics.duplicate()
		for k in extra_case:
			GS.metrics[k] = extra_case[k]

	# ③ 存档往返
	GS.last_metric_funding = 12345
	var blob: Dictionary = GS.serialize()
	_expect(int(blob.get("last_metric_funding", -1)), 12345, "serialize 写入新字段")
	GS.last_metric_funding = 0
	GS.load_state(blob)
	_expect(int(GS.last_metric_funding), 12345, "load_state 读回新字段")

	print("")
	if fails == 0:
		print("✅ 全部通过：%d 项检查" % checks)
	else:
		print("❌ %d / %d 项失败" % [fails, checks])
	quit(0 if fails == 0 else 1)


func _expect(got: int, want: int, label: String) -> void:
	checks += 1
	if got == want:
		print("   ✓ %s = %d" % [label, got])
	else:
		fails += 1
		print("   ✗ %s：期望 %d，实际 %d" % [label, want, got])
