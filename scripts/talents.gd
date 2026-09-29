extends Node
## 天赋系统单例：本地存档 + 每局随机词条
##
## 2026-09-28 大改（见 版本更新0.0.8.md）：**天赋树暂时关闭**。
## 不再靠攒点数线性点亮，改成「每局开局随种子随机附赠 0~3 条词条」。
## 词条按等级分三类，按难度取用：
##   等级 1（基础 8 条）→ 简单模式
##   等级 2（扩展 7 条）→ 普通模式
##   等级 3（强化 15 条）→ 困难模式
## 同一局内：不重复抽同一条，也不会同时出现「同一个加成键」的两条
##（例如 资金周转 与 资金周转 II 都是 interest，同局最多出现一条）。
## 树状解锁的旧数据（points / unlocked）与相关函数全部保留 —— 恢复时把 main.gd 的
## TALENT_TREE_ENABLED 改回 true 即可继续用，老进度不丢。

const SAVE_PATH := "user://talents.json"

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

var points: int = 0            # 天赋树（暂关）用的点数，保留不丢
var unlocked: Array = []       # 天赋树（暂关）已点亮的词条，保留不丢
## 本局随机到的词条 id。每局 reset_game 时重掷；**get_bonus 只看这个列表**。
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
		points = int(data.get("points", 0))
		unlocked = []
		for id in data.get("unlocked", []):
			if _find_talent(id) != -1:
				unlocked.append(id)


## 清空天赋：点数与已解锁全部归零，并立即落盘。
## 供设置里的「清空当前存档」调用 —— 直接写空状态而不是删文件，
## 效果等价，且不会留下「文件不存在」这个需要额外处理的分支。
func reset_all() -> void:
	points = 0
	unlocked = []
	granted = []
	save()


func save() -> void:
	# 确保存档目录存在（Godot 通常会自建，这里兜底防数据丢失）
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"points": points, "unlocked": unlocked}))
	f.close()  # 显式落盘，避免关闭游戏时未写入


# ==================== 本局随机词条（0.0.8 的新天赋系统）====================

## 开局掷词条：**随种子可复现**（同种子 + 同难度 = 同样的词条，便于对照实验）。
## 抽 0~3 条，只从本难度对应的 tier 里抽。
##
## ⚠ 用独立的 RandomNumberGenerator，绝不碰全局随机序列 ——
##   否则掷词条会平移后面所有随机（危机、抽卡、开局指标），
##   同一个种子跑出来的对局会和历史记录对不上，反事实对照全废。
func roll_for_run(for_seed: int, difficulty: int) -> Array:
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


## 本局词条中指定 key 的加成之和
## ⚠ 只认本局随机到的 granted，**不再认 unlocked**：
##   天赋树暂关期间若还让旧解锁生效，老存档会带着满树加成开局，
##   把随机词条的设计整个盖掉。
func get_bonus(key: String) -> float:
	var sum := 0.0
	for id in granted:
		var idx := _find_talent(id)
		if idx != -1 and TALENTS[idx]["bonus"]["key"] == key:
			sum += TALENTS[idx]["bonus"]["value"]
	return sum


# ==================== 天赋树（暂时关闭，代码保留待恢复）====================

func has(id: String) -> bool:
	return id in unlocked


## 下一个待点亮的词条 id；全点亮返回 ""
func next_talent_id() -> String:
	if unlocked.size() >= TALENTS.size():
		return ""
	return TALENTS[unlocked.size()]["id"]


## 点亮下一个词条所需的点数：前 15 条 1 点，第 16 条起 2 点
func next_cost() -> int:
	return 2 if unlocked.size() >= 15 else 1


## 点亮下一个词条（线性）—— 天赋树恢复后才有入口
func unlock_next() -> bool:
	var nid := next_talent_id()
	var cost := next_cost()
	if nid == "" or points < cost:
		return false
	unlocked.append(nid)
	points -= cost
	save()
	return true


func award(n: int) -> void:
	if n <= 0:
		return
	points += n
	save()


func _find_talent(id: String) -> int:
	for i in TALENTS.size():
		if TALENTS[i]["id"] == id:
			return i
	return -1
