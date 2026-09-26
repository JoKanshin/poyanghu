extends Node
## 天赋系统单例：永久成长 + 本地存档
## 每局结束按评分发放天赋点；天赋线性解锁，点亮后提供跨局永久加成。

const SAVE_PATH := "user://talents.json"

# 线性天赋树：按数组顺序依次点亮（基础 8 条 + 升级/扩展，共 30 条）
const TALENTS := [
	# === 基础天赋 1-8 ===
	{"id": "fund_boost",     "name": "启动资金",   "desc": "每回合拨款 +5 万",     "bonus": {"key": "funding",           "value": 5}},
	{"id": "cost_cut",       "name": "精简开支",   "desc": "运营成本 −2 万",       "bonus": {"key": "operation",         "value": -2}},
	{"id": "water_start",    "name": "蓄水有方",   "desc": "开局水位 +3",           "bonus": {"key": "start_water",       "value": 3}},
	{"id": "veg_start",      "name": "植被苗圃",   "desc": "开局植被 +3",           "bonus": {"key": "start_veg",         "value": 3}},
	{"id": "extra_card",     "name": "广开思路",   "desc": "每回合多抽 1 张卡",     "bonus": {"key": "cards",             "value": 1}},
	{"id": "crisis_calm",    "name": "未雨绸缪",   "desc": "危机概率 −3%",          "bonus": {"key": "crisis_chance",     "value": -0.03}},
	{"id": "first_action",   "name": "运筹帷幄",   "desc": "首回合行动位 +1",       "bonus": {"key": "first_turn_actions", "value": 1}},
	{"id": "all_boost",      "name": "生态专家",   "desc": "开局全指标 +2",         "bonus": {"key": "start_all",         "value": 2}},
	# === 升级与扩展 9-30 ===
	{"id": "fund_boost2",    "name": "启动资金 II", "desc": "每回合拨款 +5 万",    "bonus": {"key": "funding",           "value": 5}},
	{"id": "cost_cut2",      "name": "精简开支 II", "desc": "运营成本 −2 万",      "bonus": {"key": "operation",         "value": -2}},
	{"id": "water_start2",   "name": "蓄水有方 II", "desc": "开局水位 +3",          "bonus": {"key": "start_water",       "value": 3}},
	{"id": "veg_start2",     "name": "植被苗圃 II", "desc": "开局植被 +3",          "bonus": {"key": "start_veg",         "value": 3}},
	{"id": "fish_start",     "name": "鱼苗繁育",    "desc": "开局鱼类 +3",           "bonus": {"key": "start_fish",        "value": 3}},
	{"id": "bird_start",     "name": "候鸟驿站",    "desc": "开局候鸟 +3",           "bonus": {"key": "start_birds",       "value": 3}},
	{"id": "quality_start",  "name": "净水工程",    "desc": "开局水质 +3",           "bonus": {"key": "start_quality",     "value": 3}},
	{"id": "community_start","name": "民心工程",    "desc": "开局社区 +3",           "bonus": {"key": "start_community",   "value": 3}},
	{"id": "crisis_calm2",   "name": "未雨绸缪 II", "desc": "危机概率 −3%",         "bonus": {"key": "crisis_chance",     "value": -0.03}},
	{"id": "all_boost2",     "name": "生态专家 II", "desc": "开局全指标 +2",        "bonus": {"key": "start_all",         "value": 2}},
	{"id": "fish_start2",    "name": "鱼苗繁育 II", "desc": "开局鱼类 +3",          "bonus": {"key": "start_fish",        "value": 3}},
	{"id": "bird_start2",    "name": "候鸟驿站 II", "desc": "开局候鸟 +3",          "bonus": {"key": "start_birds",       "value": 3}},
	{"id": "quality_start2", "name": "净水工程 II", "desc": "开局水质 +3",          "bonus": {"key": "start_quality",     "value": 3}},
	{"id": "community_start2","name": "民心工程 II","desc": "开局社区 +3",          "bonus": {"key": "start_community",   "value": 3}},
	{"id": "carry_boost",    "name": "扩大蓄水",    "desc": "结转上限 +10 万",      "bonus": {"key": "carry",             "value": 10}},
	{"id": "carry_boost2",   "name": "扩大蓄水 II", "desc": "结转上限 +10 万",      "bonus": {"key": "carry",             "value": 10}},
	{"id": "interest_boost", "name": "资金周转",    "desc": "结转利息 +3%",         "bonus": {"key": "interest",          "value": 0.03}},
	{"id": "interest_boost2","name": "资金周转 II","desc": "结转利息 +3%",          "bonus": {"key": "interest",          "value": 0.03}},
	{"id": "cost_discount",  "name": "精打细算",    "desc": "卡牌成本 −10%",        "bonus": {"key": "card_cost",         "value": -0.10}},
	{"id": "cost_discount2", "name": "精打细算 II","desc": "卡牌成本 −10%",        "bonus": {"key": "card_cost",         "value": -0.10}},
	{"id": "extra_card2",    "name": "广开思路 II", "desc": "每回合多抽 1 张卡",    "bonus": {"key": "cards",             "value": 1}},
	{"id": "first_action2",  "name": "运筹帷幄 II", "desc": "首回合行动位 +1",      "bonus": {"key": "first_turn_actions", "value": 1}},
]

var points: int = 0
var unlocked: Array = []


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


func save() -> void:
	# 确保存档目录存在（Godot 通常会自建，这里兜底防数据丢失）
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"points": points, "unlocked": unlocked}))
	f.close()  # 显式落盘，避免关闭游戏时未写入


func has(id: String) -> bool:
	return id in unlocked


## 下一个待点亮的天赋 id；全点亮返回 ""
func next_talent_id() -> String:
	if unlocked.size() >= TALENTS.size():
		return ""
	return TALENTS[unlocked.size()]["id"]


## 点亮下一个天赋所需的天赋点：前 15 条 1 点，第 16 条起 2 点
func next_cost() -> int:
	return 2 if unlocked.size() >= 15 else 1


## 已点亮天赋中指定 key 的加成之和
func get_bonus(key: String) -> float:
	var sum := 0.0
	for id in unlocked:
		var idx := _find_talent(id)
		if idx != -1 and TALENTS[idx]["bonus"]["key"] == key:
			sum += TALENTS[idx]["bonus"]["value"]
	return sum


## 点亮下一个天赋（线性）
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
