extends Node
## 《拯救鄱阳湖》—— 回合制生态管理模拟
## GameState 单例：数据 + 核心结算逻辑。UI/3D 表现由 main.gd 驱动。

# ==================== 常量 ====================
const TOTAL_TURNS := 16          # 一局 16 回合 = 4 年 × 4 季
const BASE_FUNDING := 100        # 每回合基础拨款（万）
const OPERATION_COST := 25       # 固定运营支出（万）
const MAX_CARRY := 60            # 结转上限（万）
const MAX_ACTIONS := 3           # 每回合最多执行行动数（行动位）

# 六项指标的中文名与量纲说明
const METRIC_NAMES := {
	"water_level": "水位",
	"vegetation": "沉水植被",
	"water_quality": "水质",
	"fish": "鱼类资源",
	"birds": "候鸟种群",
	"community": "社区信任",
}

# 卡牌档位 → 成本倍率
const TIER_COST_MULT := {"basic": 0.5, "effective": 1.0, "deep": 2.0}
const TIER_NAMES := {"basic": "基础投入", "effective": "有效投入", "deep": "深度投入"}

# ==================== 物种数据 ====================
# 每个物种有生态角色；数量受相关指标与行动联动。地图上按数量显示会动的个体。
const SPECIES := {
	"baihe": {
		"name": "白鹤", "color": Color(0.95, 0.95, 0.95),
		"role": "旗舰物种：取食苦草块茎，是人鸟冲突的核心。",
		"drivers": ["birds", "vegetation"],
	},
	"dongfangbaihuan": {
		"name": "东方白鹳", "color": Color(0.15, 0.15, 0.22),
		"role": "鱼类取食者：湿地健康的指示物种。",
		"drivers": ["birds", "fish"],
	},
	"xiaotiane": {
		"name": "小天鹅", "color": Color(0.90, 0.90, 0.85),
		"role": "浅水滤食者：对碟形湖水位变化最敏感。",
		"drivers": ["birds", "water_level"],
	},
	"baizhenhe": {
		"name": "白枕鹤", "color": Color(0.78, 0.78, 0.72),
		"role": "杂食性：喜在农田与草洲交界处觅食稻谷。",
		"drivers": ["birds", "community"],
	},
	"yanlei": {
		"name": "雁类", "color": Color(0.62, 0.57, 0.47),
		"role": "草洲取食者：数量庞大，是食物链的基础。",
		"drivers": ["birds", "vegetation"],
	},
}

# 行动卡 → 直接提升的物种（体现「某种选项导致物种增多」）
const ACTION_SPECIES_BONUS := {
	"veg_restore": {"baihe": 8, "yanlei": 8},
	"water_control": {"xiaotiane": 8},
	"bird_canteen": {"baihe": 6, "baizhenhe": 6},
	"patrol": {"dongfangbaihuan": 6},
}

# ==================== 行动卡数据 ====================
# effects: [{metric, delta, delay}]  delay=0 即时；>0 进延迟队列
const ACTION_CARDS := [
	{
		"id": "water_control", "name": "碟形湖控水", "category": "ecology",
		"desc": "调节湖区水位，改善沉水植物块茎发育。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "water_level", "delta": 3, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 8, "delay": 0}, {"metric": "vegetation", "delta": 4, "delay": 2}]},
			"deep":     {"effects": [{"metric": "water_level", "delta": 15, "delay": 0}, {"metric": "vegetation", "delta": 8, "delay": 2}, {"metric": "community", "delta": -4, "delay": 0}]},
		},
		"side_note": {"deep": "深度控水可能淹没下游农田，社区信任 -4"},
	},
	{
		"id": "veg_restore", "name": "植被补种", "category": "ecology",
		"desc": "补种苦草等沉水植物，扩大草洲覆盖。",
		"cost": 20,
		"tiers": {
			"basic":    {"effects": [{"metric": "vegetation", "delta": 3, "delay": 2}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 8, "delay": 2}, {"metric": "birds", "delta": 5, "delay": 3}]},
			"deep":     {"effects": [{"metric": "vegetation", "delta": 14, "delay": 3}, {"metric": "birds", "delta": 10, "delay": 3}]},
		},
		"side_note": {"effective": "效果延迟 2~3 回合后显现"},
	},
	{
		"id": "water_monitor", "name": "水质监测与病害防治", "category": "ecology",
		"desc": "监测总磷总氮，提前发现并防治病害风险。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "water_quality", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 6, "delay": 0}]},
			"deep":     {"effects": [{"metric": "water_quality", "delta": 12, "delay": 0}]},
		},
		"side_note": {"effective": "提前发现病害，避免植被延迟受损"},
	},
	{
		"id": "invasive_clear", "name": "外来物种清除", "category": "ecology",
		"desc": "清除福寿螺、凤眼莲等外来入侵物种。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "vegetation", "delta": 2, "delay": 0}, {"metric": "fish", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 5, "delay": 1}, {"metric": "fish", "delta": 5, "delay": 1}]},
			"deep":     {"effects": [{"metric": "vegetation", "delta": 10, "delay": 1}, {"metric": "fish", "delta": 10, "delay": 1}, {"metric": "water_quality", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "快速化学清除有副作用，水质 -3"},
	},
	{
		"id": "bird_canteen", "name": "候鸟食堂营建", "category": "ecology",
		"desc": "在堤外农田预留食物地块，减少人鸟冲突。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "birds", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "birds", "delta": 6, "delay": 1}]},
			"deep":     {"effects": [{"metric": "birds", "delta": 12, "delay": 1}, {"metric": "community", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "未与农户充分协商，社区信任 -3"},
	},
	{
		"id": "rescue", "name": "应急救护", "category": "ecology",
		"desc": "救护搁浅或受伤个体，建立响应机制。",
		"cost": 20,
		"tiers": {
			"basic":    {"effects": [{"metric": "birds", "delta": 1, "delay": 0}]},
			"effective": {"effects": [{"metric": "birds", "delta": 3, "delay": 0}]},
			"deep":     {"effects": [{"metric": "birds", "delta": 5, "delay": 0}]},
		},
		"side_note": {},
	},
	{
		"id": "community_comp", "name": "社区补偿", "category": "social",
		"desc": "补偿农户候鸟致害损失，缓解人鸟冲突。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 3, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 8, "delay": 0}]},
			"deep":     {"effects": [{"metric": "community", "delta": 15, "delay": 0}]},
		},
		"side_note": {"deep": "全额补偿 + 转产扶持"},
	},
	{
		"id": "industry_switch", "name": "转产投资", "category": "social",
		"desc": "扶持退捕渔民转产，形成替代生计。",
		"cost": 60,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 3, "delay": 2}]},
			"effective": {"effects": [{"metric": "community", "delta": 8, "delay": 2}, {"metric": "fish", "delta": 3, "delay": 2}]},
			"deep":     {"effects": [{"metric": "community", "delta": 15, "delay": 2}, {"metric": "fish", "delta": 6, "delay": 2}]},
		},
		"side_note": {"effective": "见效慢，2~3 回合后显现"},
	},
	{
		"id": "guard_team", "name": "社区共管与护鸟队", "category": "social",
		"desc": "建立护鸟员队伍，形成社区巡护网络。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 5, "delay": 1}, {"metric": "fish", "delta": 3, "delay": 1}]},
			"deep":     {"effects": [{"metric": "community", "delta": 10, "delay": 1}, {"metric": "fish", "delta": 6, "delay": 1}]},
		},
		"side_note": {"effective": "与执法巡逻有协同加成"},
	},
	{
		"id": "education", "name": "科普宣传与公众参与", "category": "social",
		"desc": "提升村民与学生认知，形成公众监测网络。",
		"cost": 20,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 5, "delay": 0}]},
			"deep":     {"effects": [{"metric": "community", "delta": 9, "delay": 0}]},
		},
		"side_note": {},
	},
	{
		"id": "patrol", "name": "执法巡逻", "category": "manage",
		"desc": "严查非法捕捞，直接决定鱼类恢复速度。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "fish", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "fish", "delta": 6, "delay": 1}]},
			"deep":     {"effects": [{"metric": "fish", "delta": 12, "delay": 1}, {"metric": "community", "delta": -2, "delay": 0}]},
		},
		"side_note": {"deep": "严格执法可能引发不满，社区信任 -2"},
	},
	{
		"id": "research", "name": "生态监测与科研", "category": "manage",
		"desc": "提高预报准确率，建立长期数据库。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "water_quality", "delta": 1, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 3, "delay": 0}]},
			"deep":     {"effects": [{"metric": "water_quality", "delta": 5, "delay": 0}]},
		},
		"side_note": {"deep": "科研点数 +3，预报更准"},
	},
]

# ==================== 知识卡数据 ====================
const KNOWLEDGE_CARDS := {
	"plant_kucao": {
		"name": "苦草", "category": "植物", "trigger": "observation",
		"short": "鄱阳湖湖区分布面积最大的沉水植物。",
		"ecology": "白鹤越冬食物的主要来源之一，通过块茎无性繁殖。",
		"threat": "水体富营养化可能导致种群大面积腐烂死亡。",
		"management": "补种前应先检测水质，控制总磷、总氮浓度。",
		"condition": "turn == 1",
	},
	"bird_baihe": {
		"name": "白鹤", "category": "鸟类", "trigger": "observation",
		"short": "国家一级保护动物，鄱阳湖是重要的越冬地。",
		"ecology": "全身白羽、脸部裸区红色，取食苦草块茎。",
		"threat": "沉水植被退化导致食物不足，转向农田觅食。",
		"management": "保护碟形湖与草洲，营建候鸟食堂。",
		"condition": "turn == 2",
	},
	"bird_xiaotiane": {
		"name": "小天鹅", "category": "鸟类", "trigger": "observation",
		"short": "体型较小的天鹅，嘴基黄黑，是国家二级保护动物。",
		"ecology": "浅水滤食者，靠碟形湖浅水区觅食沉水植物与底栖动物。",
		"threat": "水位异常波动会让浅水觅食地消失，种群随之下滑。",
		"management": "碟形湖控水应维持适宜浅水深度，保障小天鹅觅食地。",
		"condition": "turn == 3",
	},
	"bird_dongfang": {
		"name": "东方白鹳", "category": "鸟类", "trigger": "observation",
		"short": "白身黑翅、嘴黑而长的大型涉禽。",
		"ecology": "迁徙季大量取食鱼类，是湿地健康指示物种。",
		"threat": "鱼类资源下降与栖息地破碎化。",
		"management": "禁渔与执法巡逻是恢复鱼类资源的关键。",
		"condition": "turn == 4",
	},
	"mech_water_quality": {
		"name": "水质与苦草", "category": "机制", "trigger": "decision",
		"short": "富营养化是沉水植被退化的主因之一。",
		"ecology": "总磷、总氮超标会诱发藻类暴发，遮蔽苦草。",
		"threat": "忽视水质监测，病害可能滞后爆发。",
		"management": "补种与水质治理应同步推进。",
		"condition": "vegetation < 45",
	},
	"mech_fushouluo": {
		"name": "福寿螺综合防控", "category": "外来物种", "trigger": "decision",
		"short": "外来入侵物种会挤占本土物种空间。",
		"ecology": "福寿螺繁殖快，啃食水生植物。",
		"threat": "化学灭杀可能误伤本土螺类。",
		"management": "应优先农业防治与生态调控，科学用药为最后手段。",
		"condition": "vegetation < 40",
	},
	"cons_disease": {
		"name": "苦草病害的因果", "category": "案例", "trigger": "consequence",
		"short": "水质超标会滞后引发植被病害。",
		"ecology": "早期水质超标 → 后续苦草病害暴发。",
		"threat": "后果延迟 2~3 回合，容易被忽略。",
		"management": "长期监测水质是预防的关键。",
		"condition": "water_quality < 35",
	},
	"cons_compensate": {
		"name": "野生动物致害补偿", "category": "管理策略", "trigger": "consequence",
		"short": "人鸟冲突需要共管而非对立。",
		"ecology": "白鹤取食莲藕、踩踏稻田造成农户损失。",
		"threat": "补偿缺位可能触发驱鸟等对抗行为。",
		"management": "走合规补偿渠道，配合转产扶持。",
		"condition": "community < 40",
	},
}

# ==================== 事件数据 ====================
# 按回合触发，给出线索不给答案
const EVENTS := {
	1: "【危机显现】鄱阳湖连续枯水，沉水植被退化，候鸟食物告急。你是新任生态修复员，请诊断问题，做出第一个管理决策。",
	3: "【自然预警】水位预报显示 70% 概率进入枯水期，沉水植物块茎发育将受抑制。",
	5: "【社区报告】农户报告白鹤进入稻田取食，人鸟冲突初现端倪。",
	7: "【突发状况】极端干旱持续，湖区水位进一步下降。",
	9: "【矛盾激化】白鹤大量聚集农田，农户损失严重。请选择：优先保护候鸟，还是优先保障社区生计？",
	11: "【政策通知】上级将在第 3 年末进行生态成效考核，鱼类指数达标可获专项拨款。",
	13: "【转折点】累积决策开始显现效果，进入关键分支。",
	15: "【收官】第 4 年冬，准备生成最终生态报告。",
}

# ==================== 运行时状态 ====================
var turn: int = 0
var funds: int = 0          # 本回合可用资金
var carry: int = 0          # 结转下回合
var research_points: int = 0
var metrics: Dictionary = {}
var species_pop: Dictionary = {}     # 每物种数量 0-100
var effects_queue: Array = []       # 延迟效果 {metric, delta, remaining, source}
var used_action_ids: Array = []     # 本回合已执行的卡
var knowledge_unlocked: Array = []
var pending_knowledge: Array = []   # 待弹出的知识卡 id
var log_messages: Array = []        # 因果提示
var game_over: bool = false
var total_spent: int = 0            # 累计卡牌支出（用于资金效率评价）

signal metrics_changed
signal funds_changed
signal event_triggered(text: String)
signal knowledge_triggered(card_id: String)
signal turn_changed
signal game_ended(report: Dictionary)


func _ready() -> void:
	pass  # 由主场景在连接信号后调用 reset_game()，避免首个事件信号丢失


func reset_game() -> void:
	turn = 0
	carry = 0
	funds = 0
	research_points = 0
	total_spent = 0
	effects_queue = []
	used_action_ids = []
	knowledge_unlocked = []
	pending_knowledge = []
	log_messages = []
	game_over = false
	metrics = {
		"water_level": 35,   # 偏枯水
		"vegetation": 45,    # 退化
		"water_quality": 40, # 富营养化风险
		"fish": 35,          # 禁渔初期
		"birds": 50,
		"community": 55,
	}
	_sync_species()
	start_new_turn()


## 将物种数量同步到目标值（由驱动指标决定）
func _sync_species() -> void:
	for sid in SPECIES:
		species_pop[sid] = _species_target(sid)


## 物种目标数量 = 驱动指标均值（0-100）
func _species_target(sid: String) -> int:
	var drivers: Array = SPECIES[sid]["drivers"]
	var sum := 0
	for d in drivers:
		sum += metrics[d]
	return int(sum / drivers.size())


## 回合开始：结算拨款 + 扣运营支出
func start_new_turn() -> void:
	turn += 1
	used_action_ids = []
	log_messages = []

	# 基础拨款随信任度浮动
	var funding := BASE_FUNDING
	if metrics["community"] >= 70:
		funding += 15
	elif metrics["community"] <= 30:
		funding -= 15

	funds = carry + funding - OPERATION_COST
	carry = 0

	metrics_changed.emit()
	funds_changed.emit()
	turn_changed.emit()

	# 触发本回合事件
	if EVENTS.has(turn):
		event_triggered.emit(EVENTS[turn])


## 某张卡某档位的成本（万，取整）
func tier_cost(card_id: String, tier: String) -> int:
	var card := _find_card(card_id)
	return int(round(card["cost"] * TIER_COST_MULT[tier]))


## 能否执行：资金够 + 行动位够
func can_execute(card_id: String, tier: String) -> bool:
	if used_action_ids.size() >= MAX_ACTIONS:
		return false
	return funds >= tier_cost(card_id, tier)


## 执行一张行动卡（返回是否成功）
func execute_action(card_id: String, tier: String) -> bool:
	var card := _find_card(card_id)
	if card.is_empty():
		return false
	if not can_execute(card_id, tier):
		return false
	var cost := tier_cost(card_id, tier)
	funds -= cost
	total_spent += cost
	used_action_ids.append(card_id)

	var tier_data: Dictionary = card["tiers"][tier]
	for e in tier_data["effects"]:
		var delay: int = e["delay"]
		if delay <= 0:
			_apply_delta(e["metric"], e["delta"])
		else:
			effects_queue.append({
				"metric": e["metric"], "delta": e["delta"],
				"remaining": delay, "source": card["name"],
			})

	# 科研投入奖励
	if card_id == "research":
		research_points += {"basic": 1, "effective": 2, "deep": 3}[tier]

	# 行动对特定物种的直接加成（某选项让某物种增多）
	if ACTION_SPECIES_BONUS.has(card_id):
		for sid in ACTION_SPECIES_BONUS[card_id]:
			species_pop[sid] = clampi(species_pop[sid] + ACTION_SPECIES_BONUS[card_id][sid], 0, 100)

	funds_changed.emit()
	metrics_changed.emit()
	return true


## 结算自然演化（每回合结束调用）
func natural_evolution() -> void:
	# 水位随机小幅波动
	_apply_delta("water_level", _randi_range(-4, 4))

	# 植被受水质拖累：水质差则植被缓慢退化
	if metrics["water_quality"] < 40:
		_apply_delta("vegetation", -2)
	elif metrics["water_quality"] > 65:
		_apply_delta("vegetation", 1)

	# 植被是候鸟食物基础
	if metrics["vegetation"] < 40:
		_apply_delta("birds", -2)
	elif metrics["vegetation"] > 65:
		_apply_delta("birds", 1)

	# 鱼类缓慢自然恢复（禁渔背景），执法不足时恢复慢
	_apply_delta("fish", 1)

	# 社区信任：长期缺补偿则下降
	if metrics["community"] < 40 and not used_action_ids.has("community_comp"):
		_apply_delta("community", -3)

	_sync_species()
	metrics_changed.emit()


## 推进延迟效果队列（回合结束调用）
func advance_effects() -> void:
	var remaining: Array = []
	for e in effects_queue:
		e["remaining"] -= 1
		if e["remaining"] <= 0:
			_apply_delta(e["metric"], e["delta"])
			_add_log("「%s」的延迟效果显现：%s %+d" % [e["source"], METRIC_NAMES[e["metric"]], e["delta"]])
		else:
			remaining.append(e)
	effects_queue = remaining
	metrics_changed.emit()


## 回合结束：推进延迟、自然演化、结转、知识卡检查
func end_turn() -> void:
	advance_effects()
	natural_evolution()

	# 结转规则：最多 MAX_CARRY 万，溢出转科研点
	if funds > MAX_CARRY:
		var overflow := funds - MAX_CARRY
		research_points += overflow / 10
		funds = MAX_CARRY
	carry = funds
	funds = 0

	_check_knowledge_triggers()

	if turn >= TOTAL_TURNS:
		game_over = true
		game_ended.emit(generate_report())
	# 下一回合由主场景在展示完结算反馈后调用 start_new_turn()


## 检查知识卡触发条件，压入待弹出队列
func _check_knowledge_triggers() -> void:
	for card_id in KNOWLEDGE_CARDS:
		if card_id in knowledge_unlocked:
			continue
		if _eval_condition(KNOWLEDGE_CARDS[card_id]["condition"]):
			knowledge_unlocked.append(card_id)
			pending_knowledge.append(card_id)


func pop_pending_knowledge() -> String:
	if pending_knowledge.is_empty():
		return ""
	return pending_knowledge.pop_front()


## 简单条件求值：支持 "turn == 1" 或 "metric < value"
func _eval_condition(cond: String) -> bool:
	var expr := cond.strip_edges()
	if expr.begins_with("turn"):
		var parts := expr.split("==")
		return turn == int(parts[1].strip_edges())
	# metric 比较
	var m := RegEx.new()
	m.compile("(\\w+)\\s*(<=|>=|<|>|==)\\s*(-?\\d+)")
	var res := m.search(expr)
	if res:
		var metric := res.get_string(1)
		var op := res.get_string(2)
		var val := int(res.get_string(3))
		if not metrics.has(metric):
			return false
		match op:
			"<": return metrics[metric] < val
			">": return metrics[metric] > val
			"<=": return metrics[metric] <= val
			">=": return metrics[metric] >= val
			"==": return metrics[metric] == val
	return false


func _apply_delta(metric: String, delta: int) -> void:
	if not metrics.has(metric):
		return
	metrics[metric] = clampi(metrics[metric] + delta, 0, 100)


func _find_card(card_id: String) -> Dictionary:
	for c in ACTION_CARDS:
		if c["id"] == card_id:
			return c
	return {}


func _add_log(msg: String) -> void:
	log_messages.append(msg)


func _randi_range(a: int, b: int) -> int:
	return randi() % (b - a + 1) + a


## 生成结局报告
func generate_report() -> Dictionary:
	var eco := _eval_eco()
	var social := _eval_social()
	var manage := _eval_manage()
	var reflection := _build_reflection()
	return {
		"eco": eco, "social": social, "manage": manage,
		"reflection": reflection,
		"research_points": research_points,
		"knowledge_count": knowledge_unlocked.size(),
		"total_knowledge": KNOWLEDGE_CARDS.size(),
	}


func _eval_eco() -> Dictionary:
	var veg: int = metrics["vegetation"]
	var fish: int = metrics["fish"]
	var birds: int = metrics["birds"]
	var score: float = (veg + fish + birds) / 3.0
	var grade := _grade(score)
	var notes: Array = []
	if birds >= 70:
		notes.append("候鸟保护优秀，白鹤与雁类种群稳定。")
	elif birds < 40:
		notes.append("候鸟种群萎缩，白鹤食物不足。")
	if veg >= 70:
		notes.append("沉水植被恢复良好。")
	elif veg < 40:
		notes.append("沉水植被仍处于退化状态。")
	if fish >= 70:
		notes.append("鱼类资源显著恢复，禁渔成效明显。")
	elif fish < 40:
		notes.append("鱼类资源恢复缓慢。")
	if notes.is_empty():
		notes.append("生态整体均衡，但没有指标特别突出。")
	return {"score": score, "grade": grade, "notes": notes}


func _eval_social() -> Dictionary:
	var comm: int = metrics["community"]
	var grade := _grade(comm)
	var notes: Array = []
	if comm >= 70:
		notes.append("社区信任度高，护鸟队与志愿者形成合力。")
	elif comm < 40:
		notes.append("社区信任度低，人鸟矛盾激化。")
	notes.append("转产与补偿覆盖率：%s" % ("高" if used_action_ids.size() >= 0 else "需评估"))
	return {"score": float(comm), "grade": grade, "notes": notes}


func _eval_manage() -> Dictionary:
	var eff := 100.0 if total_spent == 0 else clampf(100.0 - abs(total_spent - (TOTAL_TURNS * 55)) / (TOTAL_TURNS * 55) * 100.0, 0, 100)
	var grade := _grade(eff)
	var notes: Array = []
	notes.append("科研点数累计：%d（代表长期监测积累）" % research_points)
	if research_points >= 20:
		notes.append("长期数据库建立，预报准确率高。")
	else:
		notes.append("科研投入不足，风险预警能力有限。")
	return {"score": eff, "grade": grade, "notes": notes}


func _grade(score: float) -> String:
	if score >= 80:
		return "优秀"
	elif score >= 60:
		return "良好"
	elif score >= 40:
		return "合格"
	else:
		return "警示"


func _build_reflection() -> String:
	var parts: Array = []
	if metrics["community"] >= 60 and metrics["birds"] < 50:
		parts.append("你优先安抚了社区，但候鸟食物供给被牺牲，白鹤种群承压。")
	elif metrics["birds"] >= 60 and metrics["community"] < 50:
		parts.append("你优先保护候鸟，但社区补偿不足，人鸟矛盾可能持续。")
	else:
		parts.append("你在生态与生计之间寻求平衡，没有明显的单边倾斜。")

	if "research" in used_action_ids or research_points > 0:
		parts.append("你对科研监测的投入让预报更准确，降低了不确定性。")
	else:
		parts.append("你长期忽视科研监测，很多风险直到爆发才被发现。")

	parts.append("这是代价认知：每一个决策都在改变鄱阳湖，而资源永远不够覆盖所有需求。")
	return "　".join(parts)
