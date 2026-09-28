extends SceneTree
## 「钱只能是整数万」体检（0.0.7）
## 用法：<godot> --headless --path . --script res://tools/verify_prices.gd

var fails := 0
var checks := 0

func _initialize() -> void:
	var GS: Node = root.get_node_or_null("GameState")
	var Tal: Node = root.get_node_or_null("Talents")
	if GS == null or Tal == null:
		print("FAIL: autoload 缺失"); quit(1); return
	Tal.reset_all()

	# ① 42 张卡 × 3 档：价格必须等于 round()，且打印出来不能带小数点
	var tiers := ["basic", "effective", "deep"]
	var sums := {"basic": 0, "effective": 0, "deep": 0}
	for card in GS.ACTION_CARDS:
		for t in tiers:
			var c: int = int(GS.tier_cost(str(card["id"]), t))
			var raw: float = float(card["cost"]) * float(GS.TIER_COST_MULT[t]) * (1.0 + float(Tal.get_bonus("card_cost")))
			var want: int = maxi(1, int(round(raw)))
			var shown: String = "%d" % c
			checks += 1
			if c != want or shown.find(".") != -1:
				fails += 1
				print("   ✗ %s·%s 显示=%s 值=%d 期望=%d" % [card["id"], t, shown, c, want])
			sums[t] += c
	print("① 三档价格：%d 张卡 × 3 档 = %d 个，全部整数万" % [GS.ACTION_CARDS.size(), checks])
	print("   全卡池合计：基础 %d 万 / 有效 %d 万 / 深度 %d 万" % [sums["basic"], sums["effective"], sums["deep"]])

	# ② 整局 16 回合：资金 / 结转 / 利息每一步都要是整数
	for diff in [0, 1, 2]:
		GS.difficulty = diff
		GS.run_seed = 20260928
		GS.reset_game()
		var bad := 0
		for turn in range(GS.TOTAL_TURNS):
			var f: int = int(GS.funds)
			var c: int = int(GS.carry)
			checks += 1
			if ("%d" % f).find(".") != -1 or ("%d" % c).find(".") != -1:
				bad += 1
				print("   ✗ 难度%d 第%d回合 资金/结转带小数：%s / %s" % [diff, turn + 1, f, c])
			if turn == 0 or turn == GS.TOTAL_TURNS - 1:
				print("   难度%d 第%2d回合：到手 %d 万、结转 %d 万" % [diff, turn + 1, f, c])
			GS.start_new_turn()
		fails += bad
	print("② 三难度各 16 回合资金流水：%d 项检查" % (3 * GS.TOTAL_TURNS))

	print("")
	if fails == 0:
		print("✅ 全部通过：%d 项检查，钱与价格全程整数万" % checks)
	else:
		print("❌ %d / %d 项失败" % [fails, checks])
	quit(0 if fails == 0 else 1)
