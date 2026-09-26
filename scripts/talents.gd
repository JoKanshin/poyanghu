extends Node
## 天赋系统单例：永久成长 + 本地存档
## 每局结束按评分发放天赋点；天赋线性解锁，点亮后提供跨局永久加成。

const SAVE_PATH := "user://talents.json"

# 线性天赋树：按数组顺序依次点亮
const TALENTS := [
	{"id": "fund_boost",    "name": "启动资金", "desc": "每回合基础拨款 +20 万", "bonus": {"key": "funding",       "value": 20}},
	{"id": "cost_cut",      "name": "精简开支", "desc": "每回合运营成本 -5 万",   "bonus": {"key": "operation",     "value": -5}},
	{"id": "water_start",   "name": "蓄水有方", "desc": "开局水位 +10",           "bonus": {"key": "start_water",   "value": 10}},
	{"id": "veg_start",     "name": "植被苗圃", "desc": "开局植被 +10",           "bonus": {"key": "start_veg",     "value": 10}},
	{"id": "extra_action",  "name": "运筹帷幄", "desc": "每回合行动位 +1",        "bonus": {"key": "actions",       "value": 1}},
	{"id": "crisis_calm",   "name": "未雨绸缪", "desc": "危机触发概率 -10%",      "bonus": {"key": "crisis_chance", "value": -0.10}},
	{"id": "extra_card",    "name": "广开思路", "desc": "每回合多抽 1 张卡",      "bonus": {"key": "cards",         "value": 1}},
	{"id": "all_boost",     "name": "生态专家", "desc": "开局全指标 +5",          "bonus": {"key": "start_all",     "value": 5}},
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"points": points, "unlocked": unlocked}))


func has(id: String) -> bool:
	return id in unlocked


## 下一个待点亮的天赋 id；全点亮返回 ""
func next_talent_id() -> String:
	if unlocked.size() >= TALENTS.size():
		return ""
	return TALENTS[unlocked.size()]["id"]


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
	if nid == "" or points < 1:
		return false
	unlocked.append(nid)
	points -= 1
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
