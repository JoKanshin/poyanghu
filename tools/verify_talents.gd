extends SceneTree
## 「开局随机词条」体检（0.0.8）
## 用法：<godot> --headless --path . --script res://tools/verify_talents.gd
## 覆盖七件事：
##   ① 每局抽 0~3 条；② 只出本难度等级的词条；③ 同局不重复 id、不重复加成键；
##   ④ 同种子同难度可复现；⑤ 分布大致均匀；⑥ 旧天赋树的 unlocked 不再泄漏加成；
##   ⑦ 加成链路真的生效（开局指标吃到「开局 +N」）+ 存档往返不丢词条。

var fails := 0
var checks := 0

const ALL_KEYS := ["funding", "operation", "card_cost", "interest", "carry", "cards",
	"crisis_chance", "first_turn_actions", "start_all", "start_water", "start_veg",
	"start_fish", "start_birds", "start_quality", "start_community"]


func _initialize() -> void:
	var GS: Node = root.get_node_or_null("GameState")
	var Tal: Node = root.get_node_or_null("Talents")
	if GS == null or Tal == null:
		print("FAIL: autoload 缺失")
		quit(1)
		return

	# ---------- ①②③④⑤ 扫 3 难度 × 300 种子 ----------
	var dist := {0: 0, 1: 0, 2: 0, 3: 0}
	var bad_count := 0
	var bad_tier := 0
	var bad_dup_id := 0
	var bad_dup_key := 0
	var bad_repeat := 0
	var total := 0
	for diff in [0, 1, 2]:
		for s in range(1, 301):
			var got: Array = Tal.roll_for_run(s, diff)
			total += 1
			checks += 1
			if got.size() > 3:
				bad_count += 1
			dist[got.size()] += 1
			var seen := {}
			var keys := {}
			for id in got:
				var t: Dictionary = Tal.entry(str(id))
				if t.is_empty() or int(t.get("tier", 0)) != int(Tal.TIER_FOR_DIFFICULTY[diff]):
					bad_tier += 1
				if seen.has(id):
					bad_dup_id += 1
				seen[id] = true
				var k: String = str(t["bonus"]["key"])
				if keys.has(k):
					bad_dup_key += 1
				keys[k] = true
			if str(Tal.roll_for_run(s, diff)) != str(got):
				bad_repeat += 1
	print("① 扫描 %d 局：超 3 条 %d、等级错 %d、重复 id %d、重复加成键 %d、不可复现 %d"
		% [total, bad_count, bad_tier, bad_dup_id, bad_dup_key, bad_repeat])
	fails += bad_count + bad_tier + bad_dup_id + bad_dup_key + bad_repeat
	print("⑤ 分布（0/1/2/3 条）：%d / %d / %d / %d（各约 %.0f%%）"
		% [dist[0], dist[1], dist[2], dist[3], 100.0 / 4])

	# 附：给每个难度印几个「抽满 3 条」的种子 —— 复现与截图取证用
	# （同种子 + 同难度必出同样词条，所以这些种子可以反复复现同一屏）
	for diff in [0, 1, 2]:
		var found: Array = []
		for s in range(1, 2000):
			if Tal.roll_for_run(s, diff).size() == 3:
				found.append(s)
				if found.size() >= 5:
					break
		if found.is_empty():
			print("   ✗ 难度 %d 前 2000 个种子里没有抽满 3 条的" % diff)
			fails += 1
			continue
		print("   难度 %d 抽满 3 条的种子：%s；种子 %d → %s"
			% [diff, str(found), int(found[0]), str(Tal.roll_for_run(int(found[0]), diff))])

	# 三个等级的词条数（3 条都抽得满）
	for diff in [0, 1, 2]:
		var tier: int = int(Tal.TIER_FOR_DIFFICULTY[diff])
		var n := 0
		for t in Tal.TALENTS:
			if int(t.get("tier", 0)) == tier:
				n += 1
		print("   %s 模式用等级 %d：%d 条" % [["简单", "普通", "困难"][diff], tier, n])
		checks += 1
		if n < 3:
			fails += 1
			print("   ✗ 等级 %d 词条不足 3 条，抽不满" % tier)

	# ---------- ⑥ 满树 unlocked 不许泄漏加成 ----------
	Tal.unlocked = []
	for t in Tal.TALENTS:
		Tal.unlocked.append(t["id"])
	Tal.roll_for_run(20260928, 2)
	var leak := 0
	for k in ALL_KEYS:
		var want := 0.0
		for id in Tal.granted:
			var t: Dictionary = Tal.entry(str(id))
			if str(t["bonus"]["key"]) == k:
				want += float(t["bonus"]["value"])
		checks += 1
		if absf(Tal.get_bonus(k) - want) > 0.0001:
			leak += 1
			print("   ✗ %s：满树时 get_bonus=%f，应只算本局词条 %f" % [k, Tal.get_bonus(k), want])
	Tal.unlocked = []
	fails += leak
	print("⑥ 满树存档（30 条全解锁）下跑一局：加成泄漏 %d 处（应为 0）" % leak)

	# ---------- ⑦ 加成链路：开局指标吃到「开局 +N」 ----------
	seed(12345)
	Tal.granted = ["all_boost"]                    # 开局全指标 +2
	var with_t: Dictionary = GS._roll_starting_metrics()
	seed(12345)                                    # 同一种子 → 随机抖动相同，差值即词条贡献
	Tal.granted = []
	var without_t: Dictionary = GS._roll_starting_metrics()
	var diff_bad := 0
	for k in with_t:
		checks += 1
		if int(with_t[k]) - int(without_t[k]) != 2:
			diff_bad += 1
			print("   ✗ %s：带词条 %d vs 不带 %d（差 %d，应 2）"
				% [k, int(with_t[k]), int(without_t[k]), int(with_t[k]) - int(without_t[k])])
	fails += diff_bad
	print("⑦ 生态专家（开局全指标 +2）作用到 6 项指标：错 %d 处（应为 0）" % diff_bad)

	Tal.granted = ["cost_discount"]                # 卡牌成本 −10%
	var c1: int = int(GS.tier_cost("veg_restore", "effective"))
	Tal.granted = []
	var c2: int = int(GS.tier_cost("veg_restore", "effective"))
	checks += 1
	print("   精打细算：同一张卡 %d 万 → %d 万" % [c2, c1])
	if c1 >= c2:
		fails += 1
		print("   ✗ 卡牌成本没有随词条下降")

	# ---------- roll 确实接进了 reset_game ----------
	Tal.granted = []
	GS.difficulty = 2
	GS.run_seed = 424242
	GS.reset_game()
	var direct: Array = Tal.roll_for_run(424242, 2)
	checks += 1
	print("   reset_game 后的本局词条：%s" % str(Tal.granted))
	if str(Tal.granted) != str(direct):
		fails += 1
		print("   ✗ reset_game 掷出的词条与 roll_for_run(种子) 不一致：%s vs %s"
			% [str(Tal.granted), str(direct)])

	# ---------- 存档往返 ----------
	# ---------- ⑨ 首回合行动位口径一致（HUD 与能否出牌必须同一个数）----------
	GS.difficulty = 2
	GS.turn = 1
	Tal.granted = ["first_action"]
	var slots_with: int = int(GS.action_slots())
	Tal.granted = []
	var slots_without: int = int(GS.action_slots())
	checks += 1
	print("⑨ 首回合行动位：带「运筹帷幄」%d / 不带 %d（应差 1）" % [slots_with, slots_without])
	if slots_with - slots_without != 1:
		fails += 1
		print("   ✗ 首回合行动位没把词条算进去 —— HUD 与「能否出牌」会不一致")
	Tal.granted = []

	# ---------- ⑩ 存档往返 ----------
	var want: Array = ["cost_cut2", "bird_start2"]
	Tal.granted = want.duplicate()
	var blob: Dictionary = GS.serialize()
	checks += 1
	if str(blob.get("talents", [])) != str(Tal.granted):
		fails += 1
		print("   ✗ serialize 没带上本局词条")
	Tal.granted = []
	GS.load_state(blob)
	checks += 1
	var rt_ok: bool = str(Tal.granted) == str(want)
	if not rt_ok:
		fails += 1
		print("   ✗ load_state 没恢复本局词条：%s" % str(Tal.granted))
	print("⑩ 存档往返：%s（%s）" % ["带上并恢复 ✓" if rt_ok else "失败", str(Tal.granted)])

	print("")
	if fails == 0:
		print("✅ 全部通过：%d 项检查" % checks)
	else:
		print("❌ %d / %d 项失败" % [fails, checks])
	quit(0 if fails == 0 else 1)
