extends Node
## Seeded random talents + a much smaller permanent, branching study tree.
## Permanent allocations are captured at run start; menu changes affect new runs.

const SAVE_PATH := "user://talents.json"
const TreeData := preload("res://scripts/talent_tree_data.gd")
const TREE := TreeData.NODES
const GROUPS := TreeData.GROUPS
const CLEAR_REWARDS := [1, 2, 3, 0]

## 词条等级 → 难度（下标 = GameState.Difficulty 枚举值：0 简单 / 1 普通 / 2 困难 / 3 噩梦）
## 噩梦档取困难档同一池（等级 3）：它是"照搬早期困难档"的挑战模式，
## 词条上没有理由再给它开小灶 —— 那反而会把"几乎必死"的设定冲淡。
const TIER_FOR_DIFFICULTY := [1, 2, 3, 3]

## 词条表：30 条，每条带一个 tier（词条等级）。
## 等级划分依据 = 原天赋树的段位：基础 8 条 / 扩展 7 条 / 强化（多为 I 的 II 版）15 条。
const TALENTS := [
	# === tier 1：基础词条（简单模式）===
	{"id": "fund_boost",       "tier": 1, "name": "启动资金",    "desc": "每回合拨款 +5 万",      "bonus": {"key": "funding",            "value": 5}},
	{"id": "cost_cut",         "tier": 1, "name": "精简开支",    "desc": "运营成本 −2 万",        "bonus": {"key": "operation",          "value": -2}},
	{"id": "water_start",      "tier": 1, "name": "蓄水有方",    "desc": "开局水位 +3",           "bonus": {"key": "start_water",        "value": 3}},
	{"id": "veg_start",        "tier": 1, "name": "植被苗圃",    "desc": "开局植被 +3",           "bonus": {"key": "start_veg",          "value": 3}},
	{"id": "extra_card",       "tier": 1, "name": "广开思路",    "desc": "每回合多抽 1 张卡",     "bonus": {"key": "cards",              "value": 1}},
	{"id": "crisis_calm",      "tier": 1, "name": "未雨绸缪",    "desc": "危机概率 −3%",          "bonus": {"key": "crisis_chance",      "value": -0.03}},
	{"id": "first_action",     "tier": 1, "name": "运筹帷幄",    "desc": "首回合行动位 +1",       "bonus": {"key": "first_turn_actions", "value": 1}},
	{"id": "all_boost",        "tier": 1, "name": "生态专家",    "desc": "开局全指标 +2",         "bonus": {"key": "start_all",          "value": 2}},
	# === tier 2：扩展词条（普通模式）===
	{"id": "fish_start",       "tier": 2, "name": "鱼苗繁育",    "desc": "开局鱼类 +3",           "bonus": {"key": "start_fish",         "value": 3}},
	{"id": "bird_start",       "tier": 2, "name": "候鸟驿站",    "desc": "开局候鸟 +3",           "bonus": {"key": "start_birds",        "value": 3}},
	{"id": "quality_start",    "tier": 2, "name": "净水工程",    "desc": "开局水质 +3",           "bonus": {"key": "start_quality",      "value": 3}},
	{"id": "community_start",  "tier": 2, "name": "民心工程",    "desc": "开局社区 +3",           "bonus": {"key": "start_community",    "value": 3}},
	{"id": "carry_boost",      "tier": 2, "name": "扩大蓄水",    "desc": "结转上限 +10 万",       "bonus": {"key": "carry",              "value": 10}},
	{"id": "interest_boost",   "tier": 2, "name": "资金周转",    "desc": "结转利息 +3%",          "bonus": {"key": "interest",           "value": 0.03}},
	{"id": "cost_discount",    "tier": 2, "name": "精打细算",    "desc": "卡牌成本 −10%",         "bonus": {"key": "card_cost",          "value": -0.10}},
	# === tier 3：强化词条（困难模式）===
	{"id": "fund_boost2",      "tier": 3, "name": "启动资金 II", "desc": "每回合拨款 +5 万",      "bonus": {"key": "funding",            "value": 5}},
	{"id": "cost_cut2",        "tier": 3, "name": "精简开支 II", "desc": "运营成本 −2 万",        "bonus": {"key": "operation",          "value": -2}},
	{"id": "water_start2",     "tier": 3, "name": "蓄水有方 II", "desc": "开局水位 +3",           "bonus": {"key": "start_water",        "value": 3}},
	{"id": "veg_start2",       "tier": 3, "name": "植被苗圃 II", "desc": "开局植被 +3",           "bonus": {"key": "start_veg",          "value": 3}},
	{"id": "crisis_calm2",     "tier": 3, "name": "未雨绸缪 II", "desc": "危机概率 −3%",          "bonus": {"key": "crisis_chance",      "value": -0.03}},
	{"id": "all_boost2",       "tier": 3, "name": "生态专家 II", "desc": "开局全指标 +2",         "bonus": {"key": "start_all",          "value": 2}},
	{"id": "fish_start2",      "tier": 3, "name": "鱼苗繁育 II", "desc": "开局鱼类 +3",           "bonus": {"key": "start_fish",         "value": 3}},
	{"id": "bird_start2",      "tier": 3, "name": "候鸟驿站 II", "desc": "开局候鸟 +3",           "bonus": {"key": "start_birds",        "value": 3}},
	{"id": "quality_start2",   "tier": 3, "name": "净水工程 II", "desc": "开局水质 +3",           "bonus": {"key": "start_quality",      "value": 3}},
	{"id": "community_start2", "tier": 3, "name": "民心工程 II", "desc": "开局社区 +3",           "bonus": {"key": "start_community",    "value": 3}},
	{"id": "carry_boost2",     "tier": 3, "name": "扩大蓄水 II", "desc": "结转上限 +10 万",       "bonus": {"key": "carry",              "value": 10}},
	{"id": "interest_boost2",  "tier": 3, "name": "资金周转 II", "desc": "结转利息 +3%",          "bonus": {"key": "interest",           "value": 0.03}},
	{"id": "cost_discount2",   "tier": 3, "name": "精打细算 II", "desc": "卡牌成本 −10%",         "bonus": {"key": "card_cost",          "value": -0.10}},
	{"id": "extra_card2",      "tier": 3, "name": "广开思路 II", "desc": "每回合多抽 1 张卡",     "bonus": {"key": "cards",              "value": 1}},
	{"id": "first_action2",    "tier": 3, "name": "运筹帷幄 II", "desc": "首回合行动位 +1",       "bonus": {"key": "first_turn_actions", "value": 1}},
]

var points: int = 0            # Legacy linear progress retained as a backup.
var unlocked: Array = []
var inspiration := 0
var tree_ranks: Dictionary = {}
var nightmare_mastery := false
var claimed_runs: Dictionary = {}
var run_tree_ranks: Dictionary = {}
var run_tree_mastery := false
## Current run's seeded random entries; the original pool and RNG are unchanged.
var granted: Array = []


func _ready() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		load_profile(data)

func load_profile(data: Dictionary) -> void:
	points = maxi(0, int(data.get("points", 0)))
	unlocked = data.get("unlocked", []).duplicate()
	inspiration = maxi(0, int(data.get("inspiration", 0)))
	nightmare_mastery = bool(data.get("nightmare_mastery", false))
	tree_ranks = sanitize_tree(data.get("tree_ranks", {}), nightmare_mastery)
	claimed_runs = data.get("claimed_runs", {}).duplicate()


## 清空天赋：点数与已解锁全部归零，并立即落盘。
## 供设置里的「清空当前存档」调用 —— 直接写空状态而不是删文件，
## 效果等价，且不会留下「文件不存在」这个需要额外处理的分支。
func reset_all() -> void:
	points = 0
	unlocked = []
	granted = []
	inspiration = 0
	tree_ranks = {}
	nightmare_mastery = false
	claimed_runs = {}
	run_tree_ranks = {}
	run_tree_mastery = false
	save()


func save() -> bool:
	# 确保存档目录存在（Godot 通常会自建，这里兜底防数据丢失）
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": 2, "points": points, "unlocked": unlocked,
		"inspiration": inspiration, "tree_ranks": tree_ranks, "nightmare_mastery": nightmare_mastery,
		"claimed_runs": claimed_runs}))
	f.flush()
	var ok := f.get_error() == OK
	f.close()  # 显式落盘，避免关闭游戏时未写入
	return ok


# ==================== 本局随机词条（0.0.8 的新天赋系统）====================

## 开局掷词条：**随种子可复现**（同种子 + 同难度 = 同样的词条，便于对照实验）。
## 抽 0~3 条，只从本难度对应的 tier 里抽。
##
## ⚠ 用独立的 RandomNumberGenerator，绝不碰全局随机序列 ——
##   否则掷词条会平移后面所有随机（危机、抽卡、开局指标），
##   同一个种子跑出来的对局会和历史记录对不上，反事实对照全废。
func roll_for_run(for_seed: int, difficulty: int) -> Array:
	run_tree_ranks = sanitize_tree(tree_ranks, nightmare_mastery)
	run_tree_mastery = nightmare_mastery
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("talent:v1:%d:%d" % [for_seed, difficulty])
	var tier: int = TIER_FOR_DIFFICULTY[clampi(difficulty, 0, TIER_FOR_DIFFICULTY.size() - 1)]
	var pool: Array = []
	for t in TALENTS:
		if int(t.get("tier", 0)) == tier:
			pool.append(t)
	# 洗牌：自己实现，保证只依赖本函数自己的 rng
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var count := rng.randi_range(0, 3)
	var used_keys := {}
	var picked: Array = []
	for t in pool:
		if picked.size() >= count:
			break
		var key: String = str(t["bonus"]["key"])
		if used_keys.has(key):
			continue          # 同一加成键只取一条：防「资金增加 I / II」同局出现
		used_keys[key] = true
		picked.append(str(t["id"]))
	picked.sort()             # 展示顺序稳定，方便截图核对
	granted = picked
	return granted


## 读档恢复本局词条（继续游戏用 —— 不重掷，掷出来什么就是什么）
func set_granted(ids: Array) -> void:
	granted = []
	for id in ids:
		if _find_talent(str(id)) != -1:
			granted.append(str(id))


## 取词条条目（找不到返回空字典）
func entry(id: String) -> Dictionary:
	var i := _find_talent(id)
	if i == -1:
		return {}
	return TALENTS[i]


## Random entries and the permanent allocation captured at this run's start.
func get_bonus(key: String) -> float:
	var sum := 0.0
	for id in granted:
		var idx := _find_talent(id)
		if idx != -1 and TALENTS[idx]["bonus"]["key"] == key:
			sum += TALENTS[idx]["bonus"]["value"]
	return sum + tree_bonus(key, run_tree_ranks)


# ==================== Branching permanent study ====================

func tree_entry(id: String) -> Dictionary:
	for node in TREE:
		if node.id == id: return node
	return {}

func rank_of(id: String, ranks: Dictionary) -> int:
	return 1 if id == "origin" else int(ranks.get(id, 0))

func tree_rank(id: String) -> int:
	return int(tree_entry(id).get("max_rank", 0)) if nightmare_mastery else rank_of(id, tree_ranks)

func group_used(group: String, ranks: Dictionary) -> int:
	var count := 0
	for node in TREE:
		if node.group == group: count += rank_of(node.id, ranks)
	return count

func parents_met(node: Dictionary, ranks: Dictionary) -> bool:
	if node.parents.is_empty(): return true
	var count := 0
	for id in node.parents:
		if rank_of(id, ranks) > 0: count += 1
	return count > 0 if node.get("mode", "all") == "any" else count == node.parents.size()

func sanitize_tree(raw: Dictionary, full: bool = false) -> Dictionary:
	var result := {}
	for node in TREE:
		if node.id == "origin": continue
		var rank := int(node.max_rank) if full else clampi(int(raw.get(node.id, 0)), 0, int(node.max_rank))
		if not full:
			if not parents_met(node, result): continue
			if GROUPS.has(node.group): rank = mini(rank, maxi(0, int(GROUPS[node.group].cap) - group_used(node.group, result)))
		if rank > 0: result[node.id] = rank
	return result

func upgrade_status(id: String) -> Dictionary:
	var node := tree_entry(id)
	if node.is_empty(): return {"ok": false, "reason": "未知节点"}
	if nightmare_mastery: return {"ok": false, "reason": "噩梦通关奖励：全树已满级"}
	if tree_rank(id) >= int(node.max_rank): return {"ok": false, "reason": "已满级"}
	if not parents_met(node, tree_ranks):
		var names: Array[String] = []
		for parent in node.parents: names.append(str(tree_entry(parent).name))
		return {"ok": false, "reason": ("任选一个前置：" if node.get("mode", "all") == "any" else "需要全部前置：") + "、".join(names)}
	if GROUPS.has(node.group):
		var group: Dictionary = GROUPS[node.group]
		if group_used(node.group, tree_ranks) >= int(group.cap):
			return {"ok": false, "reason": "%s已达 %d 级上限，可重置分配" % [group.name, group.cap]}
	if inspiration < int(node.cost): return {"ok": false, "reason": "需要 %d 灵感，通关后可获得" % node.cost}
	return {"ok": true, "reason": "可研修"}

func unlock(id: String) -> bool:
	if not upgrade_status(id).ok: return false
	var before := tree_ranks.duplicate()
	var cost: int = tree_entry(id).cost
	tree_ranks[id] = tree_rank(id) + 1
	inspiration -= cost
	if save(): return true
	tree_ranks = before
	inspiration += cost
	return false

func allocated_cost() -> int:
	var total := 0
	for node in TREE: total += int(node.cost) * int(tree_ranks.get(node.id, 0))
	return total

func respec() -> bool:
	if nightmare_mastery: return false
	var refund := allocated_cost()
	var before := tree_ranks.duplicate()
	tree_ranks = {}
	inspiration += refund
	if save(): return true
	tree_ranks = before
	inspiration -= refund
	return false

func tree_bonus(key: String, ranks: Dictionary) -> float:
	var total := 0.0
	for node in TREE: total += float(node.bonus.get(key, 0)) * int(ranks.get(node.id, 0))
	return total

func set_run_tree(ranks: Dictionary, mastery: bool = false) -> void:
	run_tree_mastery = mastery
	run_tree_ranks = sanitize_tree(ranks, mastery)

func run_tree_count() -> int:
	return run_tree_ranks.size()

func run_tree_summary() -> String:
	var lines: Array[String] = []
	for node in TREE:
		var rank := int(run_tree_ranks.get(node.id, 0))
		if rank > 0: lines.append("%s %d/%d · %s" % [node.name, rank, node.max_rank, node.desc])
	return "\n".join(lines)

func run_tree_effect_summary() -> String:
	var starts: Array[String] = []
	for pair in [["start_water", "水位"], ["start_quality", "水质"], ["start_veg", "植被"], ["start_fish", "鱼类"], ["start_birds", "候鸟"], ["start_community", "社区"]]:
		var value := int(tree_bonus(pair[0], run_tree_ranks))
		if value > 0: starts.append("%s +%d" % [pair[1], value])
	var economy: Array[String] = []
	for pair in [["funding", "拨款"], ["operation", "运营成本"], ["carry", "结转上限"]]:
		var value := int(tree_bonus(pair[0], run_tree_ranks))
		if value != 0: economy.append("%s %s%d万" % [pair[1], "+" if value > 0 else "", value])
	var rates: Array[String] = []
	for pair in [["card_cost", "卡牌成本"], ["crisis_chance", "危机概率"]]:
		var value := int(round(tree_bonus(pair[0], run_tree_ranks) * 100))
		if value != 0: rates.append("%s %d%%" % [pair[1], value])
	var lines: Array[String] = []
	if not starts.is_empty(): lines.append("开局：" + " · ".join(starts))
	if not economy.is_empty(): lines.append("每回合：" + " · ".join(economy))
	if not rates.is_empty(): lines.append(" · ".join(rates))
	return "\n".join(lines)

## Every victorious run earns inspiration, including early wins. Reopening is safe.
func claim_victory_report(report: Dictionary) -> Dictionary:
	var result := {"amount": 0, "mastery": false, "duplicate": false, "save_error": false}
	var run_id := str(report.get("run_id", ""))
	var mode := int(report.get("difficulty", -1))
	if run_id.is_empty() or mode < 0 or mode > 3 or not bool(report.get("victory", false)) or bool(report.get("is_failure", false)): return result
	if claimed_runs.has(run_id):
		result.duplicate = true
		return result
	var previous_ranks := tree_ranks.duplicate()
	var previous_mastery := nightmare_mastery
	var amount: int = CLEAR_REWARDS[mode]
	if mode == 3:
		nightmare_mastery = true
		tree_ranks = sanitize_tree({}, true)
	inspiration += amount
	claimed_runs[run_id] = mode
	if not save():
		inspiration -= amount
		tree_ranks = previous_ranks
		nightmare_mastery = previous_mastery
		claimed_runs.erase(run_id)
		result.save_error = true
		return result
	result.amount = amount
	result.mastery = mode == 3
	return result


func _find_talent(id: String) -> int:
	for i in TALENTS.size():
		if TALENTS[i]["id"] == id:
			return i
	return -1
