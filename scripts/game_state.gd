extends Node
## 《拯救鄱阳湖》—— 回合制生态管理模拟
## GameState 单例：数据 + 核心结算逻辑。UI/3D 表现由 main.gd 驱动。

# ==================== 常量 ====================
const TOTAL_TURNS := 16          # 一局 16 回合 = 4 年 × 4 季
const BASE_FUNDING := 100        # 每回合基础拨款（万）
const OPERATION_COST := 20       # 固定运营支出（万）
const MAX_CARRY := 60            # 结转上限（万）
const INTEREST_RATE := 0.05      # 结转利息（每回合，利滚利，利率从低）

# 难度档位：简单 / 普通 / 困难
enum Difficulty { EASY, NORMAL, HARD }

# 各难度参数（简单 / 普通 / 困难）
const FAILURE_THRESHOLD := { Difficulty.EASY: 20, Difficulty.NORMAL: 30, Difficulty.HARD: 40 }   # 判负阈值
const PENALTY_MULT := { Difficulty.EASY: 1.0, Difficulty.NORMAL: 1.5, Difficulty.HARD: 2.0 }     # 扣分惩罚倍率

# 困难档「常规随机扣分」的下限额外抬这么多点，**在难度负向倍率之后**生效。
# 目的：削弱「随机到最坏值 + 指标恰好贴线 = 暴毙」的挫败感。
#
# ⚠ 为什么不直接改原始下界（-5 → -4）：
#   那样会被困难档的 ×2.0 放大成 +2（-10 → -8），而且会让困难档的最坏水位
#   波动**和普通档一样都是 -8**，把两档的区别一并削掉。
#   在倍率之后再抬 1 才是字面意义上的「上调一分」——
#   困难档最坏 -9 仍然比普通档的 -8 更凶，难度梯度保住。
const HARD_ROUTINE_FLOOR_BONUS := 1
const FUNDING_PENALTY := { Difficulty.EASY: 0, Difficulty.NORMAL: 20, Difficulty.HARD: 35 }       # 每回合拨款削减（万）

# ==================== 指标 → 每回合拨款（2026-09-28 第二条玩测反馈）====================
# 反馈原话：「在困难模式里有几个数值，比如社会信任和候鸟，感觉没啥用」。
#
# 量化诊断（tools/sim_metrics.gd，困难档 400 局）：这两项原本**只进结算报告的分数**，
# 涨也好、掉也好，都不会改变牌桌上的收益，于是玩家没有任何理由为它们出牌 ——
#   候鸟：死因占比 0.3%、危机伤害占比 5.6%，且只在「植被 < 42」时才会自然衰减；
#   社区信任：自然衰减的门槛（< 45）**比困难档自己的致死线（50）还低**，
#             也就是说，只要你还活着，它就永远不会自然掉 —— 需要维护的理由根本不存在。
#
# 修法：把「钱从哪来」接到这两项上 —— 它们从"只读的分数"变成"经济引擎"。
#   · 社区信任高 → 地方配套与群众配合到位，拨款更多
#   · 候鸟种群旺 → 观鸟 / 生态旅游能拉到的社会资金更多
# 表格格式：指标 → [[阈值, 金额(万)], ...]，**从上往下取第一个满足的**（写的时候按强度递减）。
# 阈值正数 = 指标 ≥ 阈值 时生效；负数 = 指标 ≤ |阈值| 时生效。
# ⚠ 玩家可见文案不解释因果（只给结果）—— 结算里只多一行「额外拨款：+N 万」，
#   "为什么多"要玩家自己从数字里总结。
const FUNDING_STEPS := {
	"community": [[70, 15], [60, 8], [-30, -15]],
	"birds":     [[70, 10], [-25, -5]],
}
const CRISIS_CHANCE := { Difficulty.EASY: 0.38, Difficulty.NORMAL: 0.55, Difficulty.HARD: 0.68 }  # 危机概率基数
const CRISIS_SLOPE := { Difficulty.EASY: 0.22, Difficulty.NORMAL: 0.25, Difficulty.HARD: 0.28 }   # 危机概率随回合增幅
const START_FLOOR := { Difficulty.EASY: 48, Difficulty.NORMAL: 48, Difficulty.HARD: 48 }          # 开局指标下限（各难度统一，难度只体现在阈值）
const START_BOOST := { Difficulty.EASY: 6, Difficulty.NORMAL: 6, Difficulty.HARD: 6 }             # 开局指标加成（各难度统一）
const REPORT_SCORE := { Difficulty.EASY: 80.0, Difficulty.NORMAL: 70.0, Difficulty.HARD: 65.0 }   # 天赋点达标平均分
# 每回合行动位（行动位 = 一回合最多能打几张牌）
# 简单档多给一个位：新手还没建立起「先补水再护鸟」这类联动的直觉，
# 三个位常常只够救火、铺不出组合，体验偏挫败。普通/困难维持 3。
const MAX_ACTIONS_BY_DIFFICULTY := { Difficulty.EASY: 4, Difficulty.NORMAL: 3, Difficulty.HARD: 3 }

# 每项指标相对「难度致死线」的偏移（正数 = 线更高更严格，负数 = 更宽容）
# 留空 = 六项都用难度线（与旧版行为完全一致）。想调平衡只改这张表，不用动卡牌数值。
# 实测依据（见 版本更新0.0.3.md 第六节）：六项指标的「体质」差 2~3 倍 ——
#   水质 无监测每回合 -2~-4、开局离致死线只有 9.3；社区信任 平时不衰减、缓冲 19.4。
# 共用一条线时死因会高度集中（简单档 89% 死在水质+植被，社区信任只占 1%）。
# 2026-09-28 起**已启用**（按玩测可再调；调完重跑 版本更新0.0.3.md 第五节的验证）：
#   "water_level":     -3,   # 单回合波动最大（困难档 -10..+3），线略往下挪
#   "water_quality":   -5,   # 无条件衰减 + 缓冲最小，最宽容，避免「忘监测就必死」
#   "vegetation":      +3,   # 候鸟与鱼类的上游，略严
#   "fish":            -5,   # 同样无条件衰减（无巡护 -1~-2/回合）
#   "birds":            0,   # 恢复最慢、条件触发，维持原线
#   "community":      +10,   # 平时不衰减（缓冲 19.4），抬线让「牺牲社区」真的会输
# 生效后的六条致死线（顺序：水位/水质/植被/鱼类/候鸟/社区）：
#   简单 17/15/23/15/20/30
#   普通 27/25/28/25/30/40   ← 植被 33→28，见下面的 FAILURE_THRESHOLD_EXTRA
#   困难 37/35/38/35/40/50   ← 植被 43→38
# 想整体关掉、回到「六项共用一条难度线」→ 把下面改回 {}
const FAILURE_THRESHOLD_OFFSET := {"water_level": -3, "water_quality": -5, "vegetation": 3, "fish": -5, "birds": 0, "community": 10}

# 在 FAILURE_THRESHOLD_OFFSET 之上、**只对特定难度**再叠加的调整。
# 用来做「普通/困难太严、简单档不动」这类微调 —— 直接改 FAILURE_THRESHOLD_OFFSET
# 会连简单档一起动，而简单档是给新手的，不该跟着变。
# 2026-09-28 玩测反馈：沉水植被在普通/困难太难保住，两条线各降 5。
const FAILURE_THRESHOLD_EXTRA := {
	Difficulty.NORMAL: {"vegetation": -5},
	Difficulty.HARD:   {"vegetation": -5},
}

# 六项指标的中文名与量纲说明
const METRIC_NAMES := {
	"water_level": "水位",
	"vegetation": "沉水植被",
	"water_quality": "水质",
	"fish": "鱼类资源",
	"birds": "候鸟种群",
	"community": "社区信任",
}

# 死因 → 下一局优先补强的方向（失败报告用来交代「输在哪、下次怎么打」）
# ⚠ 只给「打什么」，不给「为什么」：指标之间的因果链（水质→植被→候鸟…）是隐性参数，
#   要玩家自己从数字里总结。这里写解释就等于把机制白送。
const METRIC_REMEDY := {
	"water_level": "优先补水、蓄水保水，把闸坝联合调度打出来",
	"water_quality": "尽早安排水质监测与清淤",
	"vegetation": "及时补种沉水植物、修复湿地",
	"fish": "持续维持巡护执法，别断",
	"birds": "保住栖息地，给候鸟留出恢复的时间",
	"community": "补偿与转产别断",
}

# 卡牌档位 → 成本倍率
const TIER_COST_MULT := {"basic": 0.5, "effective": 1.0, "deep": 2.0}
const TIER_NAMES := {"basic": "基础投入", "effective": "有效投入", "deep": "深度投入"}

# ==================== 物种数据 ====================
# 每个物种有生态角色；数量受相关指标与行动联动。地图上按数量显示会动的个体。
const SPECIES := {
	"baihe": {
		"name": "白鹤", "color": Color(0.97, 0.97, 0.95),
		"role": "旗舰物种：取食苦草块茎，是人鸟冲突的核心。",
		"drivers": ["birds", "vegetation"],
	},
	"dongfangbaihuan": {
		"name": "东方白鹳", "color": Color(0.40, 0.40, 0.47),
		"role": "鱼类取食者：湿地健康的指示物种。",
		"drivers": ["birds", "fish"],
	},
	"xiaotiane": {
		"name": "小天鹅", "color": Color(0.93, 0.93, 0.89),
		"role": "浅水滤食者：对碟形湖水位变化最敏感。",
		"drivers": ["birds", "water_level"],
	},
	"baizhenhe": {
		"name": "白枕鹤", "color": Color(0.86, 0.86, 0.80),
		"role": "杂食性：喜在农田与草洲交界处觅食稻谷。",
		"drivers": ["birds", "community"],
	},
	"yanlei": {
		"name": "雁类", "color": Color(0.72, 0.68, 0.60),
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
	"water_replenish": {"xiaotiane": 8},
	"water_storage": {"xiaotiane": 7},
	"water_schedule": {"xiaotiane": 6},
	"habitat_protect": {"baihe": 8, "xiaotiane": 6},
}

# ==================== 植物数据 ====================
# 不同湿地植物，各有生态角色；数量随指标联动，地图上显示会生长的个体。
# kind: submerged 沉水 / emergent 挺水 / floating 浮叶 / marsh 草洲
const PLANTS := {
	"kucao": {
		"name": "苦草", "color": Color(0.42, 0.66, 0.46), "kind": "submerged",
		"role": "沉水植物，白鹤越冬主食。",
		"drivers": ["vegetation", "water_quality"],
	},
	"luwei": {
		"name": "芦苇", "color": Color(0.70, 0.74, 0.52), "kind": "emergent",
		"role": "挺水植物，净化水质、为鸟类提供筑巢地。",
		"drivers": ["vegetation", "water_level"],
	},
	"lian": {
		"name": "莲", "color": Color(0.52, 0.72, 0.56), "kind": "floating",
		"role": "浮叶植物，白鹤取食莲藕，人鸟冲突焦点。",
		"drivers": ["vegetation", "water_level"],
	},
	"lihao": {
		"name": "藜蒿", "color": Color(0.72, 0.76, 0.54), "kind": "marsh",
		"role": "草洲先锋植物，固土防冲刷。",
		"drivers": ["vegetation", "community"],
	},
	"taicao": {
		"name": "苔草", "color": Color(0.58, 0.70, 0.50), "kind": "marsh",
		"role": "草洲优势种，雁类的主要食物。",
		"drivers": ["vegetation", "water_quality"],
	},
	"chishan": {
		"name": "池杉", "color": Color(0.50, 0.66, 0.46), "kind": "tree",
		"role": "岸边乔木，为候鸟提供筑巢与停歇的栖息地。",
		"drivers": ["vegetation"],
	},
}

# 行动卡 → 直接提升的植物
const ACTION_PLANT_BONUS := {
	"veg_restore": {"kucao": 18, "taicao": 14},
	"water_control": {"luwei": 10, "lian": 10},
	"water_monitor": {"kucao": 8},
	"water_replenish": {"luwei": 8, "lian": 8},
	"water_storage": {"luwei": 8, "lian": 8},
	"water_schedule": {"luwei": 7, "lian": 7},
	"wetland_restore": {"kucao": 12, "taicao": 12, "lihao": 10},
	"floating_island": {"lian": 6},
	"grazing_ban": {"taicao": 10},
}

# 行动卡 → 环湖人类围垦强度（settlement）变化：正值扩张、负值收缩
const ACTION_SETTLEMENT_DELTA := {
	"wetland_restore": -35,  # 退田还湿：农田退还湿地
	"industry_switch": -20,  # 转产投资：退捕退耕
	"grazing_ban": -15,      # 封洲禁牧：放牧点撤除
}

# ==================== 行动卡数据 ====================
# effects: [{metric, delta, delay}]  delay=0 即时；>0 进延迟队列
const ACTION_CARDS := [
	{
		"id": "water_control", "name": "碟形湖控水", "category": "ecology",
		"tags": ["补水调度"],
		"desc": "调节湖区水位，改善沉水植物块茎发育。",
		"cost": 39,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_level", "delta": 6, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 8, "delay": 0}, {"metric": "vegetation", "delta": 4, "delay": 2}]},
			"deep":      {"effects": [{"metric": "water_level", "delta": 18, "delay": 0}, {"metric": "vegetation", "delta": 11, "delay": 2}, {"metric": "community", "delta": -4, "delay": 0}]},
		},
		"side_note": {"deep": "深度控水可能淹没下游农田，社区信任 -4"},
	},
	{
		"id": "veg_restore", "name": "植被补种", "category": "ecology",
		"tags": ["生态修复", "物种防控"],
		"desc": "补种苦草等沉水植物，扩大草洲覆盖。",
		"cost": 30,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 6, "delay": 2}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 8, "delay": 2}, {"metric": "birds", "delta": 5, "delay": 3}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 17, "delay": 3}, {"metric": "birds", "delta": 13, "delay": 3}]},
		},
		"side_note": {"effective": "效果延迟 2~3 回合后显现"},
	},
	{
		# 与「植被补种」的分工：补种是**播种**（delayed 2~3 回合，便宜、附带候鸟收益），
		# 这张是**移栽成株**（当回合落地，贵、只加植被）—— 补的是
		# 「植被眼看要跌破红线、这回合必须拉回来」那类救火场景。
		# 全场原本只有「禁牧禁渔」给即时植被，而它要拿社区信任换（+9 配 -4）。
		"id": "submerged_planting", "name": "沉水植物移栽", "category": "ecology",
		"tags": ["生态修复"],
		"desc": "移栽成株苦草、黑藻，快速重建水下草场 —— 当回合见效，但成株与固定成本高。",
		"cost": 40,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 6, "delay": 1}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 11, "delay": 0}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 25, "delay": 0}, {"metric": "community", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "大规模移栽要占用湖区作业面，社区信任 -3"},
	},
	{
		# 与「沉水植物移栽」配成一对：移栽是**买成株**（贵、当回合落地、有社区代价），
		# 这张是**养冬芽/种子库**（便宜、要等 2~3 回合、总量更大且不伤社区）。
		# 一救火一长投，玩家按「这波撑不撑得住」自己选，而不是只有一条路。
		"id": "seed_bank", "name": "草种库保育", "category": "ecology",
		"tags": ["生态修复"],
		"desc": "保育苦草、黑藻的冬芽与种子库，为后续萌发留足种源 —— 便宜，但要等 2~3 回合才见效。",
		"cost": 33,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 8, "delay": 3}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 13, "delay": 2}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 36, "delay": 3}, {"metric": "community", "delta": -2, "delay": 1}]},
		},
		"side_note": {"effective": "效果延迟 2~3 回合后显现"},
	},
	{
		"id": "water_monitor", "name": "水质监测与病害防治", "category": "ecology",
		"tags": ["水体治理", "病害防控"],
		"desc": "监测总磷总氮，提前发现并防治病害风险。",
		"cost": 22,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_quality", "delta": 3, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 6, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_quality", "delta": 12, "delay": 0}]},
		},
		"side_note": {"effective": "提前发现病害，避免植被延迟受损"},
	},
	{
		"id": "invasive_clear", "name": "外来物种清除", "category": "ecology",
		"tags": ["物种防控"],
		"desc": "清除福寿螺、凤眼莲等外来入侵物种。",
		"cost": 31,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 2, "delay": 0}, {"metric": "fish", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 5, "delay": 1}, {"metric": "fish", "delta": 5, "delay": 1}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 11, "delay": 1}, {"metric": "fish", "delta": 12, "delay": 1}, {"metric": "water_quality", "delta": -3, "delay": 1}]},
		},
		"side_note": {"deep": "快速化学清除有副作用，水质 -3"},
	},
	{
		"id": "bird_canteen", "name": "候鸟食堂营建", "category": "ecology",
		"tags": ["栖息地营造"],
		"desc": "在堤外农田预留食物地块，减少人鸟冲突。",
		"cost": 19,
		"tiers": {
			"basic":     {"effects": [{"metric": "birds", "delta": 3, "delay": 1}]},
			"effective": {"effects": [{"metric": "birds", "delta": 6, "delay": 1}]},
			"deep":      {"effects": [{"metric": "birds", "delta": 15, "delay": 1}, {"metric": "community", "delta": -3, "delay": 1}]},
		},
		"side_note": {"deep": "未与农户充分协商，社区信任 -3"},
	},
	{
		"id": "rescue", "name": "应急救护", "category": "ecology",
		"tags": ["应急救护"],
		"desc": "救护搁浅或受伤个体，建立响应机制。",
		"cost": 11,
		"tiers": {
			"basic":     {"effects": [{"metric": "birds", "delta": 2, "delay": 2}]},
			"effective": {"effects": [{"metric": "birds", "delta": 3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "birds", "delta": 6, "delay": 0}]},
		},
		"side_note": {},
	},
	{
		"id": "community_comp", "name": "社区补偿", "category": "social",
		"tags": ["社区补偿"],
		"desc": "补偿农户候鸟致害损失，缓解人鸟冲突。",
		"cost": 29,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 4, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 8, "delay": 0}]},
			"deep":      {"effects": [{"metric": "community", "delta": 16, "delay": 0}]},
		},
		"side_note": {"deep": "全额补偿 + 转产扶持"},
	},
	{
		"id": "industry_switch", "name": "转产投资", "category": "social",
		"tags": ["产业转产"],
		"desc": "扶持退捕渔民转产，形成替代生计。",
		"cost": 28,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 7, "delay": 3}]},
			"effective": {"effects": [{"metric": "community", "delta": 8, "delay": 2}, {"metric": "fish", "delta": 3, "delay": 2}]},
			"deep":      {"effects": [{"metric": "community", "delta": 16, "delay": 2}, {"metric": "fish", "delta": 6, "delay": 2}]},
		},
		"side_note": {"effective": "见效慢，2~3 回合后显现"},
	},
	{
		"id": "guard_team", "name": "社区共管与护鸟队", "category": "social",
		"tags": ["公众参与"],
		"desc": "建立护鸟员队伍，形成社区巡护网络。",
		"cost": 25,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 4, "delay": 1}]},
			"effective": {"effects": [{"metric": "community", "delta": 5, "delay": 1}, {"metric": "fish", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "community", "delta": 10, "delay": 1}, {"metric": "fish", "delta": 6, "delay": 1}]},
		},
		"side_note": {"effective": "与执法巡逻有协同加成"},
	},
	{
		"id": "education", "name": "科普宣传与公众参与", "category": "social",
		"tags": ["公众参与"],
		"desc": "提升村民与学生认知，形成公众监测网络。",
		"cost": 18,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 3, "delay": 1}]},
			"effective": {"effects": [{"metric": "community", "delta": 5, "delay": 0}]},
			"deep":      {"effects": [{"metric": "community", "delta": 10, "delay": 0}]},
		},
		"side_note": {},
	},
	{
		"id": "patrol", "name": "执法巡逻", "category": "manage",
		"tags": ["执法巡护"],
		"desc": "严查非法捕捞，直接决定鱼类恢复速度。",
		"cost": 19,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 3, "delay": 1}]},
			"effective": {"effects": [{"metric": "fish", "delta": 6, "delay": 1}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 14, "delay": 1}, {"metric": "community", "delta": -2, "delay": 1}]},
		},
		"side_note": {"deep": "严格执法可能引发不满，社区信任 -2"},
	},
	{
		"id": "research", "name": "生态监测与科研", "category": "manage",
		"tags": ["科研监测"],
		"desc": "提高预报准确率，建立长期数据库。",
		"cost": 30,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_quality", "delta": 2, "delay": 2}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_quality", "delta": 6, "delay": 0}]},
		},
		"side_note": {"deep": "科研点数 +3，预报更准"},
	},
	{
		"id": "water_replenish", "name": "生态补水（引江济湖）", "category": "ecology",
		"tags": ["补水调度"],
		"desc": "跨流域引水补充湖区水量，缓解枯水、恢复浅滩生境。",
		"cost": 49,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_level", "delta": 7, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 11, "delay": 0}, {"metric": "vegetation", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "water_level", "delta": 24, "delay": 0}, {"metric": "vegetation", "delta": 7, "delay": 1}, {"metric": "community", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "引水挤占下游农业用水，社区信任 -3"},
	},
	{
		"id": "water_storage", "name": "蓄水保水工程", "category": "ecology",
		"tags": ["补水调度"],
		"desc": "在碟形湖与入江水道修建蓄水闸，汛期拦蓄、旱季保水，稳定湖区水位。",
		"cost": 33,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_level", "delta": 5, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 9, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_level", "delta": 21, "delay": 0}, {"metric": "community", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "拦蓄过多影响下游用水，社区信任 -3"},
	},
	{
		"id": "water_schedule", "name": "闸坝联合调度", "category": "manage",
		"tags": ["补水调度"],
		"desc": "协调上游水库联合调度，保障湖区生态流量，缓解枯水并改善水体流动性。",
		"cost": 33,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_level", "delta": 5, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 7, "delay": 0}, {"metric": "water_quality", "delta": 2, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_level", "delta": 15, "delay": 0}, {"metric": "water_quality", "delta": 5, "delay": 0}, {"metric": "community", "delta": -2, "delay": 0}]},
		},
		"side_note": {"deep": "调水涉及上下游利益，社区信任 -2"},
	},
	{
		"id": "wetland_restore", "name": "退田还湿（湿地生态修复）", "category": "ecology",
		"tags": ["生态修复"],
		"desc": "将环湖低产农田退还为湿地，重建自然水文节律。",
		"cost": 31,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 5, "delay": 1}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 10, "delay": 2}, {"metric": "water_quality", "delta": 5, "delay": 2}, {"metric": "community", "delta": -2, "delay": 0}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 16, "delay": 2}, {"metric": "water_quality", "delta": 9, "delay": 2}, {"metric": "birds", "delta": 6, "delay": 3}, {"metric": "community", "delta": -4, "delay": 0}]},
		},
		"side_note": {"effective": "退田农户短期受损，社区信任 -2"},
	},
	{
		"id": "floating_island", "name": "人工浮岛（生态浮床）", "category": "ecology",
		"tags": ["水体治理"],
		"desc": "布置人工浮岛与生态浮床，吸附氮磷、净化水体。",
		"cost": 35,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_quality", "delta": 5, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 7, "delay": 0}, {"metric": "vegetation", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "water_quality", "delta": 14, "delay": 0}, {"metric": "vegetation", "delta": 6, "delay": 1}]},
		},
		"side_note": {},
	},
	{
		"id": "dredge", "name": "底泥清淤疏浚", "category": "ecology",
		"tags": ["水体治理"],
		"desc": "疏浚淤积底泥，削减内源污染、恢复湖床通透性。",
		"cost": 27,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_quality", "delta": 5, "delay": 2}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 7, "delay": 1}, {"metric": "fish", "delta": 2, "delay": 2}]},
			"deep":      {"effects": [{"metric": "water_quality", "delta": 16, "delay": 1}, {"metric": "fish", "delta": 6, "delay": 2}, {"metric": "vegetation", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "机械清淤扰动湖床，短期植被 -3"},
	},
	{
		"id": "habitat_protect", "name": "越冬栖息地保护", "category": "ecology",
		"tags": ["栖息地营造"],
		"desc": "划定并管护候鸟越冬栖息地，控制人为干扰与栖息地破碎化。",
		"cost": 27,
		"tiers": {
			"basic":     {"effects": [{"metric": "birds", "delta": 4, "delay": 1}]},
			"effective": {"effects": [{"metric": "birds", "delta": 7, "delay": 1}, {"metric": "vegetation", "delta": 2, "delay": 2}]},
			"deep":      {"effects": [{"metric": "birds", "delta": 14, "delay": 1}, {"metric": "vegetation", "delta": 4, "delay": 2}]},
		},
		"side_note": {},
	},
	{
		"id": "ecotourism", "name": "生态旅游与观鸟经济", "category": "social",
		"tags": ["产业转产"],
		"desc": "发展观鸟旅游与生态体验，让保护产生社区收益。",
		"cost": 31,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 5, "delay": 1}]},
			"effective": {"effects": [{"metric": "community", "delta": 6, "delay": 0}, {"metric": "birds", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "community", "delta": 14, "delay": 1}, {"metric": "birds", "delta": 8, "delay": 1}, {"metric": "water_quality", "delta": -2, "delay": 1}]},
		},
		"side_note": {"deep": "游客激增带来环境压力，水质 -2"},
	},
	{
		"id": "damage_insurance", "name": "野生动物致害保险", "category": "social",
		"tags": ["社区补偿"],
		"desc": "建立候鸟致害补偿保险，农户损失及时赔付。",
		"cost": 32,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 5, "delay": 1}]},
			"effective": {"effects": [{"metric": "community", "delta": 7, "delay": 0}, {"metric": "birds", "delta": 2, "delay": 1}]},
			"deep":      {"effects": [{"metric": "community", "delta": 14, "delay": 1}, {"metric": "birds", "delta": 6, "delay": 1}]},
		},
		"side_note": {"deep": "保险兜底后农户不再驱赶候鸟"},
	},
	{
		"id": "eco_brand", "name": "生态产品认证与助销", "category": "social",
		"tags": ["产业转产"],
		"desc": "认证湖区生态农产品并拓展销路，让绿色生产有利可图。",
		"cost": 26,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 5, "delay": 2}]},
			"effective": {"effects": [{"metric": "community", "delta": 6, "delay": 1}, {"metric": "water_quality", "delta": 3, "delay": 2}]},
			"deep":      {"effects": [{"metric": "community", "delta": 10, "delay": 2}, {"metric": "water_quality", "delta": 7, "delay": 2}, {"metric": "vegetation", "delta": 3, "delay": 1}]},
		},
		"side_note": {"effective": "减少化肥农药投入，水质间接改善"},
	},
	{
		"id": "fish_restock", "name": "增殖放流", "category": "manage",
		"tags": ["增殖放流"],
		"desc": "投放鱼苗，恢复鱼类资源量与江湖洄游通道。",
		"cost": 26,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 5, "delay": 2}]},
			"effective": {"effects": [{"metric": "fish", "delta": 8, "delay": 2}, {"metric": "community", "delta": 2, "delay": 2}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 16, "delay": 2}, {"metric": "community", "delta": 4, "delay": 2}]},
		},
		"side_note": {"deep": "渔民共享放流收益，社区信任 +4"},
	},
	{
		# 与「增殖放流」配成一对：放流是**直接投鱼苗**（manage 类，全部延迟 1~2 回合，
		# 还附带社区收益），这张是**修产卵场与洄游通道**（当回合见效、只加鱼）。
		# 补的是「鱼类眼看跌破红线、这回合必须拉回来」的救火位 ——
		# 全场原本给即时鱼的只有执法巡逻与外来物种清除的 +2，杯水车薪。
		"id": "spawning_ground", "name": "鱼类产卵场修复", "category": "manage",
		"tags": ["生态修复"],
		"desc": "修复四大家鱼产卵场与洄游通道：当回合就见鱼群回补，后续繁殖还会再涨一波。",
		"cost": 43,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "fish", "delta": 9, "delay": 0}, {"metric": "fish", "delta": 4, "delay": 2}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 19, "delay": 0}, {"metric": "fish", "delta": 11, "delay": 2}, {"metric": "community", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "产卵场禁渔期影响短期捕捞，社区信任 -3"},
	},
	{
		"id": "smart_patrol", "name": "智慧巡护（无人机遥感）", "category": "manage",
		"tags": ["执法巡护"],
		"desc": "无人机与遥感全天候巡护，监测非法捕捞、火情与水质。",
		"cost": 25,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 4, "delay": 1}]},
			"effective": {"effects": [{"metric": "fish", "delta": 6, "delay": 1}, {"metric": "water_quality", "delta": 2, "delay": 1}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 12, "delay": 1}, {"metric": "water_quality", "delta": 4, "delay": 1}]},
		},
		"side_note": {},
	},
	{
		"id": "wetland_law", "name": "湿地保护立法", "category": "manage",
		"tags": ["执法巡护"],
		"desc": "推动地方湿地保护条例，划定禁渔区与生态红线。",
		"cost": 33,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 8, "delay": 3}]},
			"effective": {"effects": [{"metric": "fish", "delta": 6, "delay": 2}, {"metric": "birds", "delta": 4, "delay": 2}, {"metric": "community", "delta": 3, "delay": 2}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 12, "delay": 2}, {"metric": "birds", "delta": 8, "delay": 2}, {"metric": "community", "delta": 6, "delay": 2}]},
		},
		"side_note": {"effective": "立法见效慢，2 回合后逐步显现"},
	},
	{
		"id": "grazing_ban", "name": "封洲禁牧", "category": "manage",
		"tags": ["生态修复"],
		"desc": "禁止湖洲过度放牧，保护洲滩草甸植被。",
		"cost": 11,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 2, "delay": 2}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 5, "delay": 0}, {"metric": "community", "delta": -2, "delay": 0}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 10, "delay": 0}, {"metric": "community", "delta": -4, "delay": 0}]},
		},
		"side_note": {"effective": "牧民失去放牧地，社区信任 -2"},
	},

	# ==================== 补牌：社会 / 管理（2026-09-28）====================
	# 加这批的原因：三色能力严重不对等 —— 生态 14 张覆盖全部六项，
	# 社会 7 张里**连一张水位卡都没有**，管理 8 张的候鸟只靠 wetland_law 一张弱覆盖。
	# 「？！同花！？」成就也因此偏易（生态三张比社会/管理三张好凑太多）。
	#
	# 设计准则两条：
	#   ① 每个颜色都要能应对**全部六项指标**，不再有"这项只能靠生态"的死角；
	#   ② 每个颜色都要有**当回合见效**的救火牌 —— 否则指标逼近致死线时，
	#      带这个颜色出战就等于没有还手之力（配合 RESCUE_WEIGHT 的加权才有意义）。
	# 数值口径与生态那边对齐：即时救火牌统一 +4/+9~11/+14~18，
	# 带代价的更高一档，延迟牌总量更大但便宜。

	# ---------- 社会（7 张）----------
	{
		"id": "water_comanage", "name": "社区水权共管", "category": "social",
		"tags": ["社区参与", "补水调度"],
		"desc": "把灌溉与生态用水的分配权交给村民议事会，从抢水变成共管。",
		"cost": 44,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_level", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 9, "delay": 0}, {"metric": "community", "delta": 3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_level", "delta": 18, "delay": 0}, {"metric": "community", "delta": 6, "delay": 0}]},
		},
		"side_note": {"effective": "议事会需要时间磨合，但一旦跑通，调度阻力大减"},
	},
	{
		"id": "sewage_comanage", "name": "社区污水共治", "category": "social",
		"tags": ["水体治理", "社区参与"],
		"desc": "村民自建自管小型污水设施，从源头削减入湖污染。",
		"cost": 47,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_quality", "delta": 8, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 10, "delay": 0}, {"metric": "community", "delta": 3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_quality", "delta": 20, "delay": 0}, {"metric": "community", "delta": 6, "delay": 0}]},
		},
		"side_note": {"basic": "见效快，但覆盖范围取决于参与的户数"},
	},
	{
		"id": "fish_market", "name": "社区渔市共营", "category": "social",
		"tags": ["社区参与", "增殖放流"],
		"desc": "村集体统一经营渔获与品牌，收益按户分红，让护鱼的人有饭吃。",
		"cost": 44,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "fish", "delta": 9, "delay": 0}, {"metric": "community", "delta": 3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 18, "delay": 0}, {"metric": "community", "delta": 6, "delay": 0}]},
		},
		"side_note": {"effective": "渔获归集体后，个体偷捕的动机下降"},
	},
	{
		"id": "bird_friendly", "name": "候鸟友好社区", "category": "social",
		"tags": ["社区参与", "栖息地营造"],
		"desc": "与社区共建候鸟友好型生产生活方式，减少人鸟冲突。",
		"cost": 44,
		"tiers": {
			"basic":     {"effects": [{"metric": "birds", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "birds", "delta": 9, "delay": 0}, {"metric": "community", "delta": 3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "birds", "delta": 18, "delay": 0}, {"metric": "community", "delta": 6, "delay": 0}]},
		},
		"side_note": {"deep": "农田为候鸟留食，短期有减产压力"},
	},
	{
		"id": "fisher_retrain", "name": "渔民转产培训", "category": "social",
		"tags": ["产业转型", "社区参与"],
		"desc": "组织退捕渔民参加技能培训与就业对接，转产不离乡。",
		"cost": 42,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 9, "delay": 0}, {"metric": "fish", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "community", "delta": 18, "delay": 1}, {"metric": "fish", "delta": 8, "delay": 0}]},
		},
		"side_note": {"effective": "转产后下湖的人少了，鱼类压力随之下降"},
	},
	{
		"id": "eco_jobs", "name": "生态管护公益岗", "category": "social",
		"tags": ["社区参与", "生态修复"],
		"desc": "设护湿员、护鸟员等公益岗位，把生态保护变成村民的稳定收入。",
		"cost": 41,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 4, "delay": 1}, {"metric": "vegetation", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 7, "delay": 0}, {"metric": "vegetation", "delta": 5, "delay": 1}]},
			"deep":      {"effects": [{"metric": "community", "delta": 14, "delay": 0}, {"metric": "vegetation", "delta": 10, "delay": 1}]},
		},
		"side_note": {"effective": "护湿员日常巡护，草洲破坏随之减少"},
	},
	{
		"id": "eco_resettle", "name": "生态搬迁安置", "category": "social",
		"tags": ["生态修复", "产业转型"],
		"desc": "把圩区内的居民迁出并妥善安置，退出的土地交给湿地自然恢复。",
		"cost": 42,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 10, "delay": 2}, {"metric": "community", "delta": -2, "delay": 2}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 12, "delay": 1}, {"metric": "water_quality", "delta": 5, "delay": 1}, {"metric": "community", "delta": -3, "delay": 0}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 22, "delay": 1}, {"metric": "water_quality", "delta": 11, "delay": 1}, {"metric": "community", "delta": -5, "delay": 0}]},
		},
		"side_note": {"deep": "搬迁触动既有生计，社区信任 -5"},
	},

	# ---------- 管理（6 张）----------
	{
		"id": "sluice_fry", "name": "灌江纳苗", "category": "manage",
		"tags": ["增殖放流", "水工调控"],
		"desc": "汛期开闸引江，让长江鱼苗随水进入湖区 —— 老办法，但管用。",
		"cost": 42,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "fish", "delta": 9, "delay": 0}, {"metric": "water_level", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 18, "delay": 0}, {"metric": "water_level", "delta": 6, "delay": 1}]},
		},
		"side_note": {"effective": "引江也会抬高水位，枯水期效果更明显"},
	},
	{
		"id": "migration_corridor", "name": "迁徙廊道管理", "category": "manage",
		"tags": ["栖息地营造", "执法巡护"],
		"desc": "维护候鸟停歇地的水位与人为干扰管控，保证迁徙通道畅通。",
		"cost": 42,
		"tiers": {
			"basic":     {"effects": [{"metric": "birds", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "birds", "delta": 9, "delay": 0}, {"metric": "vegetation", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "birds", "delta": 18, "delay": 0}, {"metric": "vegetation", "delta": 6, "delay": 1}]},
		},
		"side_note": {"effective": "管控干扰的同时，停歇地草洲也得以休养"},
	},
	{
		"id": "algae_response", "name": "水质应急除藻", "category": "manage",
		"tags": ["水体治理"],
		"desc": "蓝藻暴发时应急打捞与除藻，先把水质压住再谈长效治理。",
		"cost": 40,
		"tiers": {
			"basic":     {"effects": [{"metric": "water_quality", "delta": 6, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 11, "delay": 0}]},
			"deep":      {"effects": [{"metric": "water_quality", "delta": 24, "delay": 0}, {"metric": "community", "delta": -2, "delay": 0}]},
		},
		"side_note": {"deep": "大规模打捞影响湖面作业，社区信任 -2"},
	},
	{
		"id": "obstruction_clear", "name": "湖区清障执法", "category": "manage",
		"tags": ["执法巡护", "生态修复"],
		"desc": "清理湖区内违规围网、矮围与违建，让水草重新长回来。",
		"cost": 42,
		"tiers": {
			"basic":     {"effects": [{"metric": "vegetation", "delta": 6, "delay": 0}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 9, "delay": 0}, {"metric": "fish", "delta": 3, "delay": 1}]},
			"deep":      {"effects": [{"metric": "vegetation", "delta": 18, "delay": 1}, {"metric": "fish", "delta": 8, "delay": 0}]},
		},
		"side_note": {"deep": "拆除围网触及既得利益，执法阻力不小"},
	},
	{
		"id": "lake_chief", "name": "湖长制考核", "category": "manage",
		"tags": ["执法巡护", "社区参与"],
		"desc": "把生态指标纳入湖区干部考核，压着各级真正去治。",
		"cost": 41,
		"tiers": {
			"basic":     {"effects": [{"metric": "community", "delta": 6, "delay": 1}]},
			"effective": {"effects": [{"metric": "community", "delta": 8, "delay": 0}, {"metric": "water_quality", "delta": 4, "delay": 1}]},
			"deep":      {"effects": [{"metric": "community", "delta": 14, "delay": 1}, {"metric": "water_quality", "delta": 8, "delay": 1}, {"metric": "vegetation", "delta": 5, "delay": 1}]},
		},
		"side_note": {"effective": "考核压力层层传导，治理动作随之变快"},
	},
	{
		"id": "fishway", "name": "水工程鱼道建设", "category": "manage",
		"tags": ["栖息地营造", "增殖放流"],
		"desc": "在闸坝上补建过鱼设施，恢复江湖洄游通道 —— 工程量大，见效要等。",
		"cost": 44,
		"tiers": {
			"basic":     {"effects": [{"metric": "fish", "delta": 9, "delay": 2}]},
			"effective": {"effects": [{"metric": "fish", "delta": 11, "delay": 1}, {"metric": "birds", "delta": 4, "delay": 2}]},
			"deep":      {"effects": [{"metric": "fish", "delta": 20, "delay": 1}, {"metric": "birds", "delta": 10, "delay": 2}]},
		},
		"side_note": {"effective": "洄游通道打通后，以鱼为食的候鸟也跟着回来"},
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

# ==================== 危机事件池（肉鸽随机性核心）====================
# 每回合有概率抽中危机；危机提前 1 回合预警，下回合生效。
# weight：同一轮候选之间的相对权重；cond：只有当前状态吻合的危机才会进入候选。
# 防连出与冷却：刚爆发的那个不会紧接着再来；爆发过的在各自的冷却回合内不再抽中。
# 全局喘息：任意两场危机之间至少空出 CRISIS_BREATH_TURNS 个回合（与是不是同一个危机无关）。
# 冷却时长默认走全局 CRISIS_COOLDOWN_TURNS；某个危机若在自己的条目里写了 "cooldown"，
# 就用它自己的 —— 便于给「汛期洪水」「非法捕捞」这类刷得凶的单独拉长间隔。
# 条目里不写 "cooldown" = 用全局值 = 与加这个机制之前完全一样（零行为变化）。
const CRISIS_COOLDOWN_TURNS := 3
const CRISIS_BREATH_TURNS := 1

# 深预警：科研点**累计**到这个数，危机预警从「提前 1 回合」延长到「提前 2 回合」。
# ⚠ 是累计达标而不是消耗 —— 科研点同时是结算报告的评分依据
#   （见 generate_report 里 research_points >= 20 的档位），花掉会连带拉低评价，
#   那就变成「拿成绩换情报」，与「科研投入换监测能力」的设定也不符。
const DEEP_WARN_RESEARCH := 8
const CRISES := [
	{
		"id": "drought", "name": "极端干旱", "weight": 1.0, "cond": "water_level < 45",
		"cooldown": 5,   # 重事件：掉 14 水位，两次之间至少隔 5 回合
		"needs": ["补水调度"],
		"warn": "【自然预警】气象部门预报：未来一季降水显著偏少，湖区面临枯水风险。",
		"hit": "【危机爆发】极端干旱来袭——湖区水位骤降，沉水植物块茎大面积发育受阻，湖床裸露。",
		"effects": [{"metric": "water_level", "delta": -14}, {"metric": "vegetation", "delta": -7}],
	},
	{
		"id": "disease", "name": "苦草病害暴发", "weight": 0.9, "cond": "water_quality < 50",
		"cooldown": 4,   # 慢性病害：会反复，但别连着来
		"needs": ["病害防控", "生态修复"],
		"warn": "【监测提示】巡护员发现局部水草出现腐烂迹象，疑与水体富营养化有关，建议加强监测。",
		"hit": "【危机爆发】苦草病害大面积暴发——沉水植被成片腐烂死亡，候鸟食物锐减。",
		"effects": [{"metric": "vegetation", "delta": -12}, {"metric": "water_quality", "delta": -6}],
	},
	{
		"id": "illegal_fishing", "name": "非法捕捞猖獗", "weight": 1.0, "cond": "fish < 50",
		"cooldown": 5,   # 实测最易刷屏的之一（简单档随机打牌 0.54/局），拉长间隔
		"needs": ["执法巡护"],
		"warn": "【巡护通报】近期湖区外围发现可疑船只活动轨迹，疑似非法捕捞，建议加强执法。",
		"hit": "【危机爆发】非法捕捞猖獗——电捕鱼与密眼网具造成鱼类资源骤减。",
		"effects": [{"metric": "fish", "delta": -13}],
	},
	{
		"id": "bird_conflict", "name": "候鸟大规模进田", "weight": 1.0, "cond": "community < 55",
		"cooldown": 3,   # 社会摩擦：本来就不密（0.04/局），维持全局值
		"needs": ["社区补偿", "栖息地营造"],
		"warn": "【社区报告】农户反映白鹤开始向稻田聚集，若持续可能造成较大损失，请提前协商。",
		"hit": "【危机爆发】数千只候鸟涌入农田取食莲藕、踩踏稻苗，农户损失严重，矛盾激化。",
		"effects": [{"metric": "community", "delta": -14}, {"metric": "birds", "delta": 6}],
	},
	{
		"id": "flood", "name": "汛期洪水", "weight": 0.8, "cond": "water_level > 60",
		"cooldown": 6,   # 大戏一场就够：季节性洪水，一局最多两三次
		"needs": ["生态修复", "栖息地营造"],
		"warn": "【自然预警】上游持续降雨，水文站预计湖区水位将快速上涨。",
		"hit": "【危机爆发】汛期洪水漫过草洲——新生沉水植被被冲毁，底质遭到破坏。",
		"effects": [{"metric": "water_level", "delta": 18}, {"metric": "vegetation", "delta": -10}],
	},
	{
		"id": "pollution", "name": "上游污染输入", "weight": 0.9, "cond": "water_quality < 55",
		"cooldown": 5,   # 实测密度最高（简单档随机打牌 0.91/局），必须压
		"needs": ["水体治理"],
		"warn": "【水质预警】上游监测断面总磷浓度上升，污染团可能随水流进入湖区。",
		"hit": "【危机爆发】上游污染团入境——总磷总氮严重超标，鱼类与沉水植物同时受损。",
		"effects": [{"metric": "water_quality", "delta": -14}, {"metric": "fish", "delta": -6}],
	},
	{
		"id": "invasive", "name": "外来物种暴发", "weight": 0.9, "cond": "vegetation < 55",
		"cooldown": 5,   # 入侵要时间累积（0.62/局 → 拉开）
		"needs": ["物种防控", "生态修复"],
		"warn": "【巡查发现】湖区外围发现福寿螺与凤眼莲扩散迹象，繁殖速度较快。",
		"hit": "【危机爆发】外来物种暴发——福寿螺啃食水生植物，凤眼莲覆盖水面挤占生存空间。",
		"effects": [{"metric": "vegetation", "delta": -10}, {"metric": "fish", "delta": -5}],
	},
	{
		"id": "algal_bloom", "name": "蓝藻水华", "weight": 0.85, "cond": "water_quality < 45",
		"cooldown": 4,   # 与「上游污染」同属水体治理线，错开但不至于消失
		"needs": ["水体治理"],
		"warn": "【监测提示】气温升高、水体流动性变差，蓝藻水华风险上升。",
		"hit": "【危机爆发】蓝藻水华暴发——水面被绿色藻膜覆盖，水体缺氧，候鸟中毒与食物短缺同时发生。",
		"effects": [{"metric": "water_quality", "delta": -12}, {"metric": "birds", "delta": -8}],
	},
	{
		"id": "wetland_encroach", "name": "围湖造田", "weight": 1.0, "cond": "community < 55",
		"cooldown": 6,   # 重事件（还扣 30 安置额度）：一局出现一次就很有分量
		"needs": ["执法巡护", "生态修复"],
		"warn": "【社区动向】部分村民在湿地边缘围垦造田、搭建临时房，有向湖区推进的迹象。",
		"hit": "【危机爆发】围湖造田蔓延——环湖湿地被侵占，临时房屋与圩田向湖推进。",
		"effects": [
			{"metric": "vegetation", "delta": -8},
			{"metric": "water_quality", "delta": -4},
			{"metric": "birds", "delta": -5},
		],
		"settlement": 30,
	},
]

# ==================== 危机对策卡（标签匹配 + 概率加权）====================
# 卡牌上的 tags 与危机上的 needs 做标签匹配：命中任一 needs 的卡就是该危机的对策卡。
# 映射不再写死成卡 id 列表 —— 以后加新卡，只要挂上对的标签就自动进对策池。
#
# 供给策略：预警期抽牌时，对策卡的权重 ×CRISIS_COUNTER_WEIGHT（普通卡 1.0）。
# **大概率但不是必出** —— 肉鸽要有"这波没抽到、只能硬扛"的局面，所以不做硬保底。
# 精确算出的「手上至少 1 张对策卡」概率（26 张里抽 7 张，对策池 3~6 张）：
#   权重 2.5 → 89%~98%　权重 3.0 → 93%~99%　权重 4.0 → 96%~99.8%
# 2026-09-28 之前是"硬保底 2 张"（100% 必出，池 6 张的危机手上平均 2.8 张对策卡）；
# 玩测反馈"不该必出"，故改为概率加权。想调轻重只改这一个数字。
const CRISIS_COUNTER_WEIGHT := 3.0

# 救火加权：某项指标**逼近致死线**时，能拉高那一项的牌抽中概率提高。
# 与对策卡加权**相乘**叠加（一张既是对策又是救火的牌确实该最优先）。
#
# 为什么需要：危机有专门的预警期供给倾斜（上面那条），而**指标本身逼近致死线**
# 原本没有任何供给倾斜 —— 尤其是自然演化的慢性下滑，玩家常常
# 「明知这一项快撑不住了，手上却抽不到能救的牌」。这条补的就是那个缺口。
# 判定用 failure_threshold_for（含每项偏移与难度额外调整），不是裸的难度线。
const RESCUE_MARGIN := 10      # 低于「该指标致死线 + 该值」就算逼近
const RESCUE_WEIGHT := 2.5

# ==================== 卡牌协同（组合出招）====================
# 同回合内同时执行 requires 中全部卡牌，触发额外效果
const SYNERGIES := [
	{
		"id": "sci_plant", "name": "科学补种", "requires": ["water_monitor", "veg_restore"],
		"desc": "先测水质再补种，成活率大幅提升",
		"bonus": [{"metric": "vegetation", "delta": 9}],
	},
	{
		"id": "hydro_restore", "name": "水文修复", "requires": ["water_control", "veg_restore"],
		"desc": "控水与补种协同，为沉水植物创造适宜水位",
		"bonus": [{"metric": "vegetation", "delta": 7}, {"metric": "birds", "delta": 4}],
	},
	{
		"id": "joint_defense", "name": "群防群治", "requires": ["patrol", "guard_team"],
		"desc": "执法与社区共管协同，巡护覆盖翻倍",
		"bonus": [{"metric": "fish", "delta": 8}, {"metric": "community", "delta": 4}],
	},
	{
		"id": "livelihood", "name": "生计转型", "requires": ["community_comp", "industry_switch"],
		"desc": "补偿与转产配套，农户与渔民获得长期出路",
		"bonus": [{"metric": "community", "delta": 9}],
	},
	{
		"id": "coexist", "name": "人鸟共处", "requires": ["bird_canteen", "community_comp"],
		"desc": "候鸟食堂配合社区补偿，把冲突转化为共管",
		"bonus": [{"metric": "birds", "delta": 6}, {"metric": "community", "delta": 5}],
	},
	{
		"id": "clear_water", "name": "清源活水", "requires": ["dredge", "floating_island"],
		"desc": "清淤与浮岛协同，内源外源污染一起削减",
		"bonus": [{"metric": "water_quality", "delta": 8}, {"metric": "vegetation", "delta": 4}],
	},
	{
		"id": "sky_net", "name": "天网巡护", "requires": ["smart_patrol", "patrol"],
		"desc": "无人机侦察配合地面执法，非法捕捞无所遁形",
		"bonus": [{"metric": "fish", "delta": 9}, {"metric": "water_quality", "delta": 3}],
	},
	{
		"id": "river_link", "name": "江湖连通", "requires": ["fish_restock", "water_replenish"],
		"desc": "引水恢复洄游通道，放流鱼苗直达新家园",
		"bonus": [{"metric": "fish", "delta": 8}, {"metric": "water_level", "delta": 3}],
	},
	{
		"id": "green_livelihood", "name": "绿色生计", "requires": ["eco_brand", "industry_switch"],
		"desc": "认证品牌叠加转产投资，绿色产业形成闭环",
		"bonus": [{"metric": "community", "delta": 7}, {"metric": "water_quality", "delta": 5}],
	},
	{
		"id": "bird_tourism", "name": "观鸟经济", "requires": ["ecotourism", "habitat_protect"],
		"desc": "栖息地保护好，观鸟旅游才有持续客流",
		"bonus": [{"metric": "birds", "delta": 7}, {"metric": "community", "delta": 5}],
	},
]

# ==================== 失败原因（任一指标归零即提前结束）====================
const FAILURE_TEXT := {
	"water_level": "鄱阳湖干涸见底，湖床裸露龟裂，候鸟失去越冬栖息地。",
	"vegetation": "沉水植被彻底消失，白鹤失去主要食物来源，草洲退化为荒滩。",
	"water_quality": "水质彻底恶化，蓝藻暴发、水体缺氧，水生生物大面积死亡。",
	"fish": "鱼类资源枯竭，江豚与食鱼水鸟无以为继，禁渔成果付诸东流。",
	"birds": "候鸟种群崩溃，鄱阳湖失去国际重要湿地的生态价值。",
	"community": "社区信任彻底破裂，农户与渔民转入对抗，保护工作再也无法开展。",
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
var last_metric_funding: int = 0   # 上一回合由六项指标换来的额外拨款（结算里显示用，仅结果不给解释）
var research_points: int = 0
var metrics: Dictionary = {}
var species_pop: Dictionary = {}     # 每物种数量 0-100
var plant_pop: Dictionary = {}       # 每植物数量 0-100
var effects_queue: Array = []       # 延迟效果 {metric, delta, remaining, source}
var used_action_ids: Array = []     # 本回合已执行的卡
var knowledge_unlocked: Array = []
var pending_knowledge: Array = []   # 待弹出的知识卡 id
var log_messages: Array = []        # 因果提示
# ==================== 算分流水账 ====================
# 每笔指标增减的归因记录，供主场景播「小丑牌风算分动画」。纯只读副产品，不参与任何判定。
# 每项：{phase, label, ref_id, metric, raw, applied, before, after}
#   raw     = 吃过难度负向倍率后、被 clampi 截断前的「效果值」（弹窗显示的是 applied，见下）
#   applied = 实际落地的变化量（metrics 前后差）——指标贴 0/100 时会被截断而与 raw 不等
# ⚠ 故意不写进 serialize()：动画只在实时的 _finish_turn 路径播，读档永远走不到，
#   加进去只会给存档增加无谓的不兼容面。
var score_ledger: Array = []
var game_over: bool = false
var total_spent: int = 0            # 累计卡牌支出（用于资金效率评价）
# ===== 肉鸽机制状态 =====
var run_seed: int = 0               # 本局种子（同种子可复现，用于反事实对照）
var settlement: int = 70            # 环湖人类围垦强度 0-100，仅用于 3D 房子表现
var difficulty: int = Difficulty.EASY   # 当前难度档位（主菜单选择）
var floating_islands: int = 0       # 人工浮岛数量（视觉表现，0=无）
var pending_crisis: Dictionary = {} # 待爆发的危机（本回合预警，下回合生效）
var forecast_crisis: Dictionary = {} # 深预警：2 回合后那一场，下回合升格为 pending_crisis
                                     # （不是另抽一次随机 —— 是把本来下一回合才抽的那个
                                     #   提前一回合抽出来存着，所以预告一定兑现）
var last_crisis_name: String = ""   # 上回合爆发的危机名（用于结算展示）
var crisis_history: Array = []      # 已爆发的危机 [{id, turn}]，防连出与冷却的依据
var warn_history: Array = []        # 本局预警历史 [{turn, id, value, hit_turn}]，顶部「预警回顾」用
                                    # hit_turn = -1 表示这条预警还没等到爆发（本局就结束了）
var triggered_synergies: Array = [] # 本回合触发的协同
var _fired_synergies: Array = []    # 本局已触发过的协同（防重复）
var is_failure: bool = false        # 是否因生态崩溃提前结束
var failure_reason: String = ""     # 失败原因文案
var failure_metric: String = ""     # 崩溃的指标
var failure_value: int = 0          # 判负时该指标的数值（失败报告用）

signal metrics_changed
signal funds_changed
signal event_triggered(text: String)
signal crisis_warned(crisis: Dictionary)
signal crisis_hit(crisis: Dictionary)
signal knowledge_triggered(card_id: String)
signal turn_changed
signal game_ended(report: Dictionary)


func _ready() -> void:
	pass  # 由主场景在连接信号后调用 reset_game()，避免首个事件信号丢失


# ==================== 存档 ====================
## 序列化全部运行时状态，供暂停退出后读档续玩
func serialize() -> Dictionary:
	return {
		"turn": turn, "funds": funds, "carry": carry,
		"last_metric_funding": last_metric_funding,
		"research_points": research_points,
		"metrics": metrics.duplicate(),
		"species_pop": species_pop.duplicate(),
		"plant_pop": plant_pop.duplicate(),
		"effects_queue": effects_queue.duplicate(true),
		"used_action_ids": used_action_ids.duplicate(),
		"knowledge_unlocked": knowledge_unlocked.duplicate(),
		"pending_knowledge": pending_knowledge.duplicate(),
		"log_messages": log_messages.duplicate(),
		"game_over": game_over, "total_spent": total_spent,
		"run_seed": run_seed, "settlement": settlement,
		# 本局天赋词条：继续游戏要原样带回来，否则中途读档会丢加成
		"talents": Talents.granted.duplicate(),
		"difficulty": difficulty, "floating_islands": floating_islands,
		"pending_crisis": pending_crisis.duplicate(true),
		"forecast_crisis": forecast_crisis.duplicate(true),
		"last_crisis_name": last_crisis_name,
		"crisis_history": crisis_history.duplicate(true),
		"warn_history": warn_history.duplicate(true),
		"triggered_synergies": triggered_synergies.duplicate(),
		"fired_synergies": _fired_synergies.duplicate(),
		"is_failure": is_failure, "failure_reason": failure_reason,
		"failure_metric": failure_metric, "failure_value": failure_value,
	}


## 从存档恢复全部运行时状态（不触发信号，由主场景随后刷新 HUD 与 3D）
func load_state(d: Dictionary) -> void:
	turn = int(d.get("turn", 0))
	funds = int(d.get("funds", 0))
	carry = int(d.get("carry", 0))
	last_metric_funding = int(d.get("last_metric_funding", 0))
	research_points = int(d.get("research_points", 0))
	metrics = _int_dict(d.get("metrics", {}))
	species_pop = _int_dict(d.get("species_pop", {}))
	plant_pop = _int_dict(d.get("plant_pop", {}))
	effects_queue = d.get("effects_queue", [])
	used_action_ids = d.get("used_action_ids", [])
	knowledge_unlocked = d.get("knowledge_unlocked", [])
	pending_knowledge = d.get("pending_knowledge", [])
	log_messages = d.get("log_messages", [])
	game_over = bool(d.get("game_over", false))
	total_spent = int(d.get("total_spent", 0))
	run_seed = int(d.get("run_seed", 0))
	Talents.set_granted(d.get("talents", []))
	settlement = int(d.get("settlement", 70))
	difficulty = int(d.get("difficulty", 1 if d.get("hard_mode", false) else 0))
	floating_islands = int(d.get("floating_islands", 0))
	pending_crisis = d.get("pending_crisis", {})
	forecast_crisis = d.get("forecast_crisis", {})
	last_crisis_name = str(d.get("last_crisis_name", ""))
	crisis_history = d.get("crisis_history", [])
	warn_history = d.get("warn_history", [])
	triggered_synergies = d.get("triggered_synergies", [])
	_fired_synergies = d.get("fired_synergies", [])
	is_failure = bool(d.get("is_failure", false))
	failure_reason = str(d.get("failure_reason", ""))
	failure_metric = str(d.get("failure_metric", ""))
	failure_value = int(d.get("failure_value", 0))
	# 流水账是实时算分动画的副产品，读档后没有「刚刚结算过」的语义，直接清空
	score_ledger = []


## 把字典的值统一转成 int（JSON 兜底）
func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out


func reset_game() -> void:
	turn = 0
	carry = 0
	funds = 0
	research_points = 0
	total_spent = 0
	settlement = 70
	floating_islands = 0
	effects_queue = []
	used_action_ids = []
	knowledge_unlocked = []
	pending_knowledge = []
	log_messages = []
	score_ledger = []
	game_over = false
	pending_crisis = {}
	forecast_crisis = {}
	last_crisis_name = ""
	crisis_history = []
	warn_history = []
	triggered_synergies = []
	_fired_synergies = []
	is_failure = false
	failure_reason = ""
	failure_metric = ""
	failure_value = 0
	# 每局随机种子：同种子可复现（企划书 8.3 反事实对照）
	if run_seed == 0:
		randomize()
		run_seed = randi()
	seed(run_seed)
	# 本局天赋：随种子随机附赠 0~3 条词条。必须在 _roll_starting_metrics() 之前 ——
	# 开局指标要吃「开局 +N」这类词条。见 版本更新0.0.8.md。
	Talents.roll_for_run(run_seed, difficulty)
	metrics = _roll_starting_metrics()
	_guard_starting_metrics()
	_sync_species()
	_sync_plants()
	start_new_turn()


## 随机开局：在基线附近小幅偏移，每局困境不同
func _roll_starting_metrics() -> Dictionary:
	var base := {
		"water_level": 35,   # 偏枯水
		"vegetation": 45,    # 退化
		"water_quality": 40, # 富营养化风险
		"fish": 35,          # 禁渔初期
		"birds": 50,
		"community": 55,
	}
	# 开局数值各难度统一（难度差异体现在判负阈值上），统一抬高下限避免开局过低
	var floor: int = START_FLOOR[difficulty]
	var boost: int = START_BOOST[difficulty]
	var out := {}
	for k in base:
		# 每项在 ±9 内偏移，并保证不低于统一下限
		out[k] = clampi(base[k] + boost + _randi_range(-9, 9), floor, 88)
	# 至少保证有一项明显偏弱，制造"这局的软肋"
	var weak_keys: Array = out.keys()
	var weak: String = weak_keys[_randi_range(0, weak_keys.size() - 1)]
	out[weak] = clampi(out[weak] - 12, floor, 88)
	# 本局天赋加成：定点指标加成 + 全指标加成。
	# ⚠ 放在**最后**加（下限夹取和软肋 -12 都做完之后）：开局值贴着 48 下限的那几项
	#   会把「开局 +N」吞掉 —— 0.0.8 实测：生态专家 +2 在 6 项里有 4 项被下限吞成 0，
	#   还有 1 项被软肋压到下限、只显示出 +1（玩家拿到词条却量不出效果）。
	#   加完再夹一次 [0,88]。
	out["water_level"] = clampi(int(out["water_level"]) + int(Talents.get_bonus("start_water")), 0, 88)
	out["vegetation"] = clampi(int(out["vegetation"]) + int(Talents.get_bonus("start_veg")), 0, 88)
	out["fish"] = clampi(int(out["fish"]) + int(Talents.get_bonus("start_fish")), 0, 88)
	out["birds"] = clampi(int(out["birds"]) + int(Talents.get_bonus("start_birds")), 0, 88)
	out["water_quality"] = clampi(int(out["water_quality"]) + int(Talents.get_bonus("start_quality")), 0, 88)
	out["community"] = clampi(int(out["community"]) + int(Talents.get_bonus("start_community")), 0, 88)
	var all_bonus := int(Talents.get_bonus("start_all"))
	if all_bonus != 0:
		for k in out:
			out[k] = clampi(int(out[k]) + all_bonus, 0, 88)
	return out


## 开局不该"站在悬崖上"：任何低于「该项致死线 + 2」的开局值都抬上来。
## 背景：困难档社区信任致死线是 50、而开局下限只有 48 → 实测 9.3% 的局
## 玩家还没出手就在第一回合被判负（必现的 bug 级体验，且与"难度"无关）。
func _guard_starting_metrics() -> void:
	for m in metrics.keys():
		var safe: int = failure_threshold_for(str(m)) + 2
		if int(metrics[m]) < safe:
			metrics[m] = safe


## 将物种数量同步到目标值（由驱动指标决定）
func _sync_species() -> void:
	for sid in SPECIES:
		species_pop[sid] = _species_target(sid)


## 将植物数量同步到目标值（由驱动指标决定）
func _sync_plants() -> void:
	for pid in PLANTS:
		plant_pop[pid] = _plant_target(pid)


## 物种目标数量 = 驱动指标均值（0-100）
func _species_target(sid: String) -> int:
	var drivers: Array = SPECIES[sid]["drivers"]
	var sum := 0
	for d in drivers:
		sum += metrics[d]
	return int(sum / drivers.size())


## 植物目标数量 = 驱动指标均值（0-100）
func _plant_target(pid: String) -> int:
	var drivers: Array = PLANTS[pid]["drivers"]
	var sum := 0
	for d in drivers:
		sum += metrics[d]
	return int(sum / drivers.size())


## 本回合由六项指标换来的额外拨款（万）。FUNDING_STEPS 的求值器。
## 每一项取**第一个**满足的阶梯（表按强度递减写），不累加同一项的多档。
func _metric_funding() -> int:
	var extra := 0
	for metric in FUNDING_STEPS:
		var cur: int = int(metrics.get(metric, 0))
		for step in FUNDING_STEPS[metric]:
			var thr: int = int(step[0])
			var hit: bool = (cur >= thr) if thr > 0 else (cur <= -thr)
			if hit:
				extra += int(step[1])
				break
	return extra


## 回合开始：结算拨款 + 扣运营支出
func start_new_turn() -> void:
	turn += 1
	used_action_ids = []
	log_messages = []

	# 基础拨款随指标浮动：社区信任、候鸟种群决定能拉到多少社会/旅游资金。
	# 具体阶梯见 FUNDING_STEPS；这一段是「指标 → 钱」的唯一入口。
	last_metric_funding = _metric_funding()
	var funding := BASE_FUNDING + last_metric_funding
	# 按难度削减每回合拨款（普通/困难）
	funding -= FUNDING_PENALTY[difficulty]
	# 天赋加成：基础拨款 + 运营成本减免
	funding += int(Talents.get_bonus("funding"))

	funds = carry + funding - (OPERATION_COST + int(Talents.get_bonus("operation")))
	carry = 0

	metrics_changed.emit()
	funds_changed.emit()
	turn_changed.emit()

	# 触发本回合事件
	if EVENTS.has(turn):
		event_triggered.emit(EVENTS[turn])

	# 危机系统已整体挪到 end_turn()（回合末）：预警与结算都在那里做。
	# 原因见 end_turn 里的注释 —— 伤害与判负要发生在玩家正看着数字的结算里。


## 结算上回合预警的危机：爆发并造成较重惩罚
func _resolve_pending_crisis() -> void:
	if pending_crisis.is_empty():
		return
	var c: Dictionary = pending_crisis
	pending_crisis = {}
	last_crisis_name = c["name"]
	crisis_history.append({"id": c["id"], "turn": turn})   # 防连出 / 冷却的依据
	_mark_warning_hit(str(c["id"]), turn)
	_add_log("⚠ %s" % c["hit"])
	for e in c["effects"]:
		_apply_delta(e["metric"], e["delta"], false, "crisis", str(c["name"]))   # 危机伤害不叠负向倍率，见 _apply_delta 注释
		_add_log("   %s %+d" % [METRIC_NAMES[e["metric"]], e["delta"]])
	if c.has("settlement"):
		_apply_settlement(c["settlement"])
	_sync_species()
	_sync_plants()
	metrics_changed.emit()
	crisis_hit.emit(c)
	check_failure_now()   # 危机爆发把指标打到致死线以下 → 当场判负，不再放你一回合


## 抽取本回合的危机预警（提前 1 回合告知，给玩家应对机会）
## 预警：抽出「下回合爆发」的那一场。只设置 pending_crisis，**不在这里 emit** ——
## 深预警紧接着还要抽出「2 回合后」的那一场，两个一起交给 UI，
## 弹窗同时展示「下回合」和「再下一回合」，避免同一回合弹两次。
## 真正的 emit 在 start_new_turn() 末尾统一发。
func _maybe_warn_crisis() -> void:
	if game_over:
		return  # 已经判负，不再抽新危机（否则预警会盖在失败报告上）
	if turn >= TOTAL_TURNS - 1:
		return  # 最后两回合不再新增危机，避免无法应对
	if not pending_crisis.is_empty():
		return  # 已有待爆发的危机，不叠加
	# 从第 3 回合起才开始抽危机，给玩家缓冲
	if turn < 3:
		return
	var c := _roll_crisis(turn)
	if c.is_empty():
		return
	pending_crisis = c
	_note_warning(c, 1)


## 深预警：再抽出「2 回合后」的那一场，存进 forecast_crisis。
## 它不是另抽一次随机 —— 是把本来要到下一回合才抽的那一场**提前一回合**抽出来存着，
## 下一回合升格为正式预警（见 _promote_forecast_if_needed），所以预告一定兑现。
func _maybe_forecast_crisis() -> void:
	if game_over or not deep_warning_on():
		return
	if not forecast_crisis.is_empty():
		return
	if pending_crisis.is_empty():
		return  # 连下回合的都还没定，谈不上预告再下一回合
	if turn + 2 > TOTAL_TURNS:
		return  # 会落在局末之后，就别给一个永远不会来的「预报」
	# at_turn 传 turn+1：这一场本来会在下一回合才抽，
	# 冷却 / 喘息 / 概率都该按那个时点判，否则会预告出一个到那时早已过期、
	# 或反而还在冷却中的危机。
	# 排除 pending_crisis：那一场会在本预告之前一回合爆发，必须避免「连着同一个」
	var c := _roll_crisis(turn + 1, str(pending_crisis.get("id", "")))
	if c.is_empty():
		return
	forecast_crisis = c
	_note_warning(c, 2)


## 深预警兑现：上一回合预告的那一场，本回合升格为「下回合爆发」的正式预警。
## ⚠ 必须在 _maybe_warn_crisis() **之前**调用 —— 否则它会先抽一个新的把预告顶掉，
##   预告就成假的了。
func _promote_forecast_if_needed() -> void:
	if forecast_crisis.is_empty() or not pending_crisis.is_empty():
		return  # 预告与正式预警一一对应，正常不会同时存在（后者是防御）
	pending_crisis = forecast_crisis
	forecast_crisis = {}
	# 不重复记 warn_history：预告那一回合已经记过了（lead=2）


## 抽一场危机。at_turn = 判定「冷却 / 全局喘息 / 概率」用的时点：
##   正式预警传当前回合；深预警传**它本来会被抽出的那个回合**（turn + 1）。
## exclude_id = 额外排除的危机 id。
##   ⚠ 预告必须把 pending_crisis 传进来：那一场会在预告之前一回合爆发，
##     而此刻它还没进 crisis_history，所以「防连出」和「冷却」两道过滤都拦不住它 ——
##     不排除的话会预告出一个「紧接着上一场、同一个危机」的结果（实测出现过连爆两次）。
## 过滤规则与原来完全一致，只是时点可参数化、多一道排除。抽不到返回空字典。
func _roll_crisis(at_turn: int, exclude_id: String = "") -> Dictionary:
	# 全局喘息：任意两场危机爆发之间至少空出 CRISIS_BREATH_TURNS 个回合。
	var last_hit := _last_crisis_hit_turn()
	if last_hit >= 0 and at_turn - last_hit < CRISIS_BREATH_TURNS:
		return {}  # 上一场危机刚落地，先把这一段喘息时间给玩家
	# 基础概率随难度递增，随回合推进略升（后期压力更大）
	var chance: float = CRISIS_CHANCE[difficulty] + float(at_turn) / float(TOTAL_TURNS) * CRISIS_SLOPE[difficulty]
	# 天赋加成：降低危机触发概率
	chance += Talents.get_bonus("crisis_chance")
	if randf() > chance:
		return {}
	# 加权抽选：只抽「当前状态真的吻合」的危机
	# 预警文案会引用当前值与警戒线（如「水质 90，警戒线 55」），若状态不吻合
	# 就会在安全区报警、自相矛盾 —— 所以这里必须硬性过滤，而不只是加权。
	# 再叠一层「防连出 + 冷却」：
	#   防连出 = 本回合刚爆发过的绝不连着再出（与冷却常量无关，永远生效）
	#   冷却   = 爆发过的在 CRISIS_COOLDOWN_TURNS 回合内不再进候选
	# 两条都过滤完之后候选为空 → 不预警，把喘息空间真的留给玩家。
	var pool: Array = []
	var total_w := 0.0
	for c in CRISES:
		if exclude_id != "" and str(c["id"]) == exclude_id:
			continue
		if not _eval_condition_simple(c["cond"]):
			continue
		if _crisis_hit_at(str(c["id"]), at_turn):
			continue
		if _crisis_cooldown_left(str(c["id"]), at_turn) > 0:
			continue
		pool.append(c)
		total_w += c["weight"]
	if pool.is_empty():
		return {}
	var roll := randf() * total_w
	for c in pool:
		roll -= c["weight"]
		if roll <= 0.0:
			return c
	return {}


## 记一条预警历史（顶部「预警回顾」读它）。
## lead = 提前几回合告知：1 = 常规预警，2 = 深预警
func _note_warning(c: Dictionary, lead: int) -> void:
	var pc := _parse_cond_simple(str(c["cond"]))
	warn_history.append({
		"turn": turn, "id": c["id"], "hit_turn": -1, "lead": lead,
		"value": int(metrics.get(str(pc.get("metric", "")), 0)),
	})


## 深预警是否已开启（科研点累计达标，**不消耗**）
func deep_warning_on() -> bool:
	return research_points >= DEEP_WARN_RESEARCH


## 该危机自己的冷却回合数：条目里写了 "cooldown" 就用它，没写就回落全局 CRISIS_COOLDOWN_TURNS
func crisis_cooldown_of(id: String) -> int:
	for c in CRISES:
		if c["id"] == id:
			return maxi(0, int(c.get("cooldown", CRISIS_COOLDOWN_TURNS)))
	return CRISIS_COOLDOWN_TURNS


## 该危机在 at_turn 时点还剩几回合冷却（>0 = 冷却中，不许再抽中）。
## at_turn 传 -1 表示「当前回合」；深预警要传它本来会被抽出的那个回合。
func _crisis_cooldown_left(id: String, at_turn: int = -1) -> int:
	var t: int = turn if at_turn < 0 else at_turn
	var cooldown := crisis_cooldown_of(id)
	var left := 0
	for h in crisis_history:
		if str(h["id"]) == id:
			left = maxi(left, cooldown - (t - int(h["turn"])))
	return left


## 该危机是不是「在 at_turn 这个回合刚刚爆发过」（防连出的硬底线）
func _crisis_hit_at(id: String, at_turn: int) -> bool:
	for h in crisis_history:
		if str(h["id"]) == id and int(h["turn"]) == at_turn:
			return true
	return false


## 最近一场危机爆发的回合（没有则 -1）
func _last_crisis_hit_turn() -> int:
	var t := -1
	for h in crisis_history:
		t = maxi(t, int(h["turn"]))
	return t


## 按 id 取危机条目（预警回顾面板要用名字、原文、影响、对策标签）
func crisis_by_id(id: String) -> Dictionary:
	for c in CRISES:
		if c["id"] == id:
			return c
	return {}


## 把预警历史里最近一条同名、还没爆发的记录标成「已爆发」
func _mark_warning_hit(id: String, hit_turn: int) -> void:
	for i in range(warn_history.size() - 1, -1, -1):
		var e: Dictionary = warn_history[i]
		if str(e["id"]) == id and int(e.get("hit_turn", -1)) < 0:
			e["hit_turn"] = hit_turn
			return


## 从 cond 字符串里取出 {metric, op, threshold}（预警历史要记下当时的数值）
func _parse_cond_simple(cond: String) -> Dictionary:
	var m := RegEx.new()
	m.compile("(\\w+)\\s*(<=|>=|<|>|==)\\s*(-?\\d+)")
	var res := m.search(cond)
	if res == null:
		return {}
	return {"metric": res.get_string(1), "op": res.get_string(2), "threshold": int(res.get_string(3))}


## 简易条件求值（复用知识卡的表达式风格）
func _eval_condition_simple(cond: String) -> bool:
	var m := RegEx.new()
	m.compile("(\\w+)\\s*(<=|>=|<|>|==)\\s*(-?\\d+)")
	var res := m.search(cond)
	if res == null:
		return false
	var metric := res.get_string(1)
	var op := res.get_string(2)
	var val := int(res.get_string(3))
	if not metrics.has(metric):
		return false
	var cur: int = metrics[metric]
	match op:
		"<": return cur < val
		">": return cur > val
		"<=": return cur <= val
		">=": return cur >= val
		"==": return cur == val
	return false


## 某张卡某档位的成本（万，取整）
func tier_cost(card_id: String, tier: String) -> int:
	var card := _find_card(card_id)
	var discount := 1.0 + Talents.get_bonus("card_cost")
	return maxi(1, int(round(card["cost"] * TIER_COST_MULT[tier] * discount)))


## 从卡池抽 n 张（不重复）。
## 抽 n 张行动卡：预警期对策卡权重 ×CRISIS_COUNTER_WEIGHT（**概率提高，但不是必出**）；
## 没有预警时全体等权，与旧行为完全一致。整手最后打乱，免得对策卡永远躺在最左边。
func draw_cards(n: int) -> Array:
	var total: int = mini(n, ACTION_CARDS.size())
	var pool := ACTION_CARDS.duplicate()
	var wanted := _crisis_counter_set()
	var rescue := _rescue_metric_set()
	var picked: Array = []

	while picked.size() < total and not pool.is_empty():
		var idx := _pick_weighted_index(pool, wanted, rescue)
		picked.append(pool[idx])
		pool.remove_at(idx)

	picked.shuffle()
	return picked


## 加权随机抽一张的下标。权重 = 1.0 ×（对策卡 ? ×3）×（救火卡 ? ×2.5）
func _pick_weighted_index(pool: Array, wanted: Dictionary, rescue: Dictionary) -> int:
	var total_w := 0.0
	for c in pool:
		total_w += _card_weight(c, wanted, rescue)
	var roll := randf() * total_w
	for i in pool.size():
		roll -= _card_weight(pool[i], wanted, rescue)
		if roll <= 0.0:
			return i
	return pool.size() - 1


func _card_weight(card: Dictionary, wanted: Dictionary, rescue: Dictionary) -> float:
	var w: float = CRISIS_COUNTER_WEIGHT if wanted.has(card["id"]) else 1.0
	if not rescue.is_empty() and _card_helps_any(card, rescue):
		w *= RESCUE_WEIGHT
	return w


## 当前哪些指标「逼近致死线」：低于「该指标致死线 + RESCUE_MARGIN」即算
func _rescue_metric_set() -> Dictionary:
	var out: Dictionary = {}
	for m in metrics:
		if int(metrics[m]) < failure_threshold_for(m) + RESCUE_MARGIN:
			out[m] = true
	return out


## 这张牌能不能拉高 needed 里的任意一项（只看正向效果，即时/延迟都算）
func _card_helps_any(card: Dictionary, needed: Dictionary) -> bool:
	for tier in card.get("tiers", {}).values():
		for e in tier.get("effects", []):
			if int(e["delta"]) > 0 and needed.has(str(e["metric"])):
				return true
	return false


## 某个危机的对策卡 id 列表（卡牌 tags 命中危机 needs 任一项即算对策卡）
func counter_ids_for(crisis: Dictionary) -> Array:
	var needs: Array = crisis.get("needs", [])
	var out: Array = []
	if needs.is_empty():
		return out
	for c in ACTION_CARDS:
		for tag in c.get("tags", []):
			if tag in needs:
				out.append(c["id"])
				break
	return out


## 当前预警危机的对策卡 id 列表（无预警时为空）
func counter_card_ids() -> Array:
	if pending_crisis.is_empty():
		return []
	return counter_ids_for(pending_crisis)


## 当前预警危机的对策卡集合（字典，抽牌时快速命中判定用）
func _crisis_counter_set() -> Dictionary:
	var out := {}
	for cid in counter_card_ids():
		out[cid] = true
	return out


## 能否执行：资金够 + 行动位够
func can_execute(card_id: String, tier: String) -> bool:
	var max_actions := action_slots()
	if used_action_ids.size() >= max_actions:
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
			_apply_delta(e["metric"], e["delta"], true, "card", str(card["name"]), str(card["id"]))
		else:
			effects_queue.append({
				"metric": e["metric"], "delta": e["delta"],
				"remaining": delay, "source": card["name"],
				# 记下排入的回合：delay=1 的效果当回合结算就会到期，
				# 若不记这个，它会和「前几轮留下的」混在一起，第 1 回合就会出现
				# 「前几轮遗留」这种不存在的说法。见 advance_effects()。
				"queued_turn": turn,
			})
			# 延迟效果在流水账里也记一条**预告**：applied 恒为 0（此刻确实还没落地），
			# 只为让算分动画能在这张牌上标出「N 回合后才生效」。
			# 没有它就麻烦了：26 张牌里有 12 张的 effective 档是纯延迟效果
			# （植被补种 / 增殖放流 / 湿地保护立法 等全部"长效牌"），
			# 打出去一个字都不爆，看起来像什么都没干。
			# phase 用 "card_delayed" —— 它**不在** SCORE_PHASE_ORDER 里，
			# 所以小票的四类来源求和完全不受影响。
			if metrics.has(e["metric"]):
				var preview: int = int(e["delta"])
				if preview < 0:
					preview = _scaled_delta(preview)   # 与到期时 _apply_delta 的口径保持一致
				score_ledger.append({
					"phase": "card_delayed", "label": str(card["name"]),
					"ref_id": str(card["id"]), "metric": str(e["metric"]),
					"raw": preview, "applied": 0,
					"before": metrics[e["metric"]], "after": metrics[e["metric"]],
					"remaining": delay,
				})

	# 科研投入奖励
	if card_id == "research":
		research_points += {"basic": 1, "effective": 2, "deep": 3}[tier]

	# 行动对特定物种的直接加成（某选项让某物种增多）
	if ACTION_SPECIES_BONUS.has(card_id):
		for sid in ACTION_SPECIES_BONUS[card_id]:
			species_pop[sid] = clampi(species_pop[sid] + ACTION_SPECIES_BONUS[card_id][sid], 0, 100)

	# 行动对特定植物的直接加成
	if ACTION_PLANT_BONUS.has(card_id):
		for pid in ACTION_PLANT_BONUS[card_id]:
			plant_pop[pid] = clampi(plant_pop[pid] + ACTION_PLANT_BONUS[card_id][pid], 0, 100)

	# 行动对环湖用地（房子数量）的影响
	if ACTION_SETTLEMENT_DELTA.has(card_id):
		_apply_settlement(ACTION_SETTLEMENT_DELTA[card_id])

	# 人工浮岛：打出「人工浮岛」→ 沙盘出现浮岛；「底泥清淤疏浚」→ 清除
	if card_id == "floating_island":
		floating_islands = 4
	elif card_id == "dredge":
		floating_islands = 0

	funds_changed.emit()
	metrics_changed.emit()
	check_failure_now()   # 出牌把指标打到致死线以下 → 当场判负
	return true


## 结算自然演化（每回合结束调用）
## 设计：不做决策生态会缓慢恶化（压力），但不会瞬间崩盘（给玩家反应时间）
## ⚠ 增减清单由 natural_evolution_plan() 给出：HUD 的「悬停提示」读的是同一份 plan，
##   所以提示里写的数字和实际结算的数字同源，不会各写一套。
func natural_evolution() -> void:
	for e in natural_evolution_plan():
		# ⚠ 自己算好最终值、传 apply_penalty=false，**不要**再让 _apply_delta 乘一次倍率：
		#   困难档的随机下限是在倍率**之后**抬的（见 natural_evolution_plan），
		#   交给 _apply_delta 缩放会把那个 +1 抹掉（而且会双重放大）。
		#   min/max 夹取对其它条目是恒等操作 —— 它们的 delta 本来就落在自己的区间里 ——
		#   所以简单/普通档与改动前逐字一致。
		var d: int = clampi(_scaled_delta(int(e["delta"])), int(e["min"]), int(e["max"]))
		_apply_delta(str(e["metric"]), d, false, "routine", str(e["why"]))
	_sync_species()
	_sync_plants()
	metrics_changed.emit()


## 本回合自然演化会发生哪些增减（只读推演，不改任何状态）
## 返回 [{metric, delta, min, max, kind, why}]
##   delta   = 引擎实际使用的原始值（水位那一条是本次随机到的值）
##   min/max = 叠加难度负向倍率后，玩家真正会看到的区间
##   kind    = random / loss / gain / none
## roll_random=false 时不去动水位那次随机（HUD 每帧查它，绝不能扰动全局随机序列）
func natural_evolution_plan(roll_random: bool = true) -> Array:
	var sim: Dictionary = metrics.duplicate()   # 推演副本：后一步的条件要看前几步之后的值（与原执行顺序一致）
	var out: Array = []

	# 1) 水位随机波动（枯水更常见，符合鄱阳湖现实）
	# min 是「吃完难度负向倍率后，玩家真正会看到的最坏值」；
	# 困难档再把它抬 HARD_ROUTINE_FLOOR_BONUS 点，减少暴毙（见常量注释）。
	var wl_raw_lo: int = -5
	var wl_lo: int = _scaled_delta(wl_raw_lo)
	var wl_hi: int = _scaled_delta(3)
	if difficulty == Difficulty.HARD:
		wl_lo += HARD_ROUTINE_FLOOR_BONUS
	var wl: int = _randi_range(wl_raw_lo, 3) if roll_random else 0
	out.append({"metric": "water_level", "delta": wl,
		"min": wl_lo, "max": wl_hi, "kind": "random",
		"why": "水位随机波动（枯水更常见，最多涨 3）"})
	# 推演用的也按同一个下限夹一次，否则「小窗显示的范围」与「后几步的条件判断」
	# 会以没抬过下限的值来推，跟实际结算对不上。
	var wl_applied: int = clampi(_scaled_delta(wl), wl_lo, wl_hi)
	sim["water_level"] = clampi(int(sim.get("water_level", 0)) + wl_applied, 0, 100)

	# 2) 水质：无治理则缓慢恶化
	if used_action_ids.has("water_monitor") or used_action_ids.has("research") or used_action_ids.has("smart_patrol"):
		out.append({"metric": "water_quality", "delta": 0, "min": 0, "max": 0, "kind": "none",
			"why": "本回合已投入监测/科研/智慧巡护 → 水质不恶化"})
	else:
		out.append({"metric": "water_quality", "delta": -2,
			"min": _scaled_delta(-2), "max": _scaled_delta(-2), "kind": "loss",
			"why": "没打监测/科研/智慧巡护 → 缓慢恶化"})
		sim["water_quality"] = clampi(int(sim.get("water_quality", 0)) + _scaled_delta(-2), 0, 100)

	# 3) 植被受水质拖累：水质差则植被退化（看推演后的水质）
	var q: int = int(sim.get("water_quality", 0))   # 一律 .get：残留/老存档可能缺项，HUD 每帧都要调它，不能抛错
	if q < 45:
		out.append({"metric": "vegetation", "delta": -3,
			"min": _scaled_delta(-3), "max": _scaled_delta(-3), "kind": "loss",
			"why": "水质 %d 已低于 45 → 植被被拖累" % q})
		sim["vegetation"] = clampi(int(sim.get("vegetation", 0)) + _scaled_delta(-3), 0, 100)
	elif q > 70:
		out.append({"metric": "vegetation", "delta": 1, "min": 1, "max": 1, "kind": "gain",
			"why": "水质 %d 良好（>70）→ 植被恢复" % q})
		sim["vegetation"] = clampi(int(sim.get("vegetation", 0)) + 1, 0, 100)
	else:
		out.append({"metric": "vegetation", "delta": 0, "min": 0, "max": 0, "kind": "none",
			"why": "水质 %d（45~70）→ 植被本回合不变" % q})

	# 4) 植被是候鸟食物基础（看推演后的植被）
	var veg: int = int(sim.get("vegetation", 0))
	if veg < 42:
		out.append({"metric": "birds", "delta": -3,
			"min": _scaled_delta(-3), "max": _scaled_delta(-3), "kind": "loss",
			"why": "植被 %d 已低于 42 → 候鸟食物不足" % veg})
	elif veg > 70:
		out.append({"metric": "birds", "delta": 1, "min": 1, "max": 1, "kind": "gain",
			"why": "植被 %d 良好（>70）→ 候鸟种群回升" % veg})
	else:
		out.append({"metric": "birds", "delta": 0, "min": 0, "max": 0, "kind": "none",
			"why": "植被 %d（42~70）→ 候鸟本回合不变" % veg})

	# 5) 鱼类：禁渔带来缓慢恢复，但执法不足则恢复停滞
	if used_action_ids.has("patrol") or used_action_ids.has("guard_team"):
		out.append({"metric": "fish", "delta": 2, "min": 2, "max": 2, "kind": "gain",
			"why": "本回合已投入巡护/护渔 → 鱼类缓慢恢复"})
	else:
		out.append({"metric": "fish", "delta": -1,
			"min": _scaled_delta(-1), "max": _scaled_delta(-1), "kind": "loss",
			"why": "没打巡护/护渔 → 被非法捕捞蚕食"})

	# 6) 社区信任：长期缺补偿则持续下降
	if int(sim.get("community", 0)) < 45 and not used_action_ids.has("community_comp"):
		out.append({"metric": "community", "delta": -3,
			"min": _scaled_delta(-3), "max": _scaled_delta(-3), "kind": "loss",
			"why": "信任度 %d 低于 45 且本回合没打补偿 → 持续下降" % int(sim.get("community", 0))})
	else:
		out.append({"metric": "community", "delta": 0, "min": 0, "max": 0, "kind": "none",
			"why": "本回合不变（信任度 ≥ 45，或已投入补偿）"})

	return out


## 只读：负向变动在本地难度下实际会掉多少（与 _apply_delta 走同一处代码，保证口径一致）
func _scaled_delta(delta: int) -> int:
	if delta < 0:
		return roundi(delta * PENALTY_MULT[difficulty])
	return delta


## ── HUD 悬停提示用：某一项指标「本回合会掉多少 / 红线在哪」──
## 只读，不改状态。数据来源：natural_evolution_plan()（回合末自然演化）+ pending_crisis（下回合结算时爆发的危机）
## ⚠ why 字段只留给代码与文档：指标之间的因果链是**隐性参数**，不上屏，
##   玩家应该自己从数字里总结。界面层只取数字，别把它渲染出来。
func metric_hover_preview(metric: String) -> Dictionary:
	var cur: int = int(metrics.get(metric, 0))
	var line: int = failure_threshold_for(metric)

	var info: Dictionary = {}
	for e in natural_evolution_plan(false):
		if str(e["metric"]) == metric:
			info = e
			break
	var nat_min: int = int(info.get("min", 0))
	var nat_max: int = int(info.get("max", 0))
	var end_min: int = clampi(cur + nat_min, 0, 100)
	var end_max: int = clampi(cur + nat_max, 0, 100)

	# 已预警、下回合结算时才爆发的危机：只看它有没有打到这一项（危机伤害不吃难度负向倍率）
	var crisis_name := ""
	var crisis_delta := 0
	if not pending_crisis.is_empty():
		for e in pending_crisis.get("effects", []):
			if str(e["metric"]) == metric:
				crisis_name = str(pending_crisis.get("name", "危机"))
				crisis_delta = int(e["delta"])
				break

	var worst: int = clampi(end_min + crisis_delta, 0, 100)
	return {
		"metric": metric, "cur": cur, "line": line,
		"kind": str(info.get("kind", "none")), "why": str(info.get("why", "")),
		"nat_min": nat_min, "nat_max": nat_max,
		"end_min": end_min, "end_max": end_max,
		"crisis_name": crisis_name, "crisis_delta": crisis_delta, "worst": worst,
		"margin_nat": end_min - line,      # 只算自然演化时的余量（取最坏的一头）
		"break_nat": end_min < line,       # 光自然演化就会跌破生态红线
		"break_total": worst < line,       # 把下回合那场危机一起算上
		"penalty_mult": PENALTY_MULT[difficulty],
	}


## 结算卡牌协同：本回合打出指定组合则触发额外效果
func resolve_synergies() -> void:
	triggered_synergies = []
	for s in SYNERGIES:
		var ok := true
		for req in s["requires"]:
			if not used_action_ids.has(req):
				ok = false
				break
		if not ok:
			continue
		# 避免重复触发（同一协同一局内只生效一次）
		if s["id"] in _fired_synergies:
			continue
		_fired_synergies.append(s["id"])
		triggered_synergies.append(s["name"])
		_add_log("★ 协同「%s」：%s" % [s["name"], s["desc"]])
		for e in s["bonus"]:
			_apply_delta(e["metric"], e["delta"], true, "synergy", str(s["name"]), str(s["id"]))
			_add_log("   %s %+d" % [METRIC_NAMES[e["metric"]], e["delta"]])
	_sync_species()
	_sync_plants()


## 推进延迟效果队列（回合结束调用）
func advance_effects() -> void:
	var remaining: Array = []
	for e in effects_queue:
		e["remaining"] -= 1
		if e["remaining"] <= 0:
			# 分成两个来源：
			#   pending  = 本回合刚打出的牌、当回合就到期（delay=1 就是这种）
			#   leftover = 前几轮排队、现在才到期
			# 两者执行时机相同，但玩家看到「前几轮遗留」出现在第 1 回合会莫名其妙。
			# 旧存档的队列条目没有 queued_turn，按 -1 处理 → 归入 leftover，安全。
			var ph: String = "pending" if int(e.get("queued_turn", -1)) == turn else "leftover"
			_apply_delta(e["metric"], e["delta"], true, ph, str(e["source"]))
			_add_log("「%s」的延迟效果显现：%s %+d" % [e["source"], METRIC_NAMES[e["metric"]], e["delta"]])
		else:
			remaining.append(e)
	effects_queue = remaining
	metrics_changed.emit()


## 回合结束：推进延迟、自然演化、结算协同、检查失败与知识卡
func end_turn() -> void:
	advance_effects()
	resolve_synergies()      # 卡牌协同（在自然演化前结算，让玩家看到组合收益）
	natural_evolution()

	# 结转规则：未用资金计息（利滚利），最多 max_carry 万，溢出转科研点（天赋可提升）
	var max_carry := MAX_CARRY + int(Talents.get_bonus("carry"))
	var rate := INTEREST_RATE + Talents.get_bonus("interest")
	carry = int(round(funds * (1.0 + rate)))
	if carry > max_carry:
		var overflow := carry - max_carry
		research_points += overflow / 10
		carry = max_carry
	funds = 0

	# ==================== 危机系统（回合末，2026-09-28 从 start_new_turn 挪来）====================
	# 结算预警中的危机 → 深预警升格 → 抽新预警 → 预告 2 回合后，全部在回合末做。
	#
	# 为什么挪：原来危机的伤害与判负发生在**下回合开局**，而玩家在结算弹窗里看到的
	# 指标是「本回合结算后」的值（还都在红线上）。结果是看着条都还是绿的、点一下
	# 「继续」，下一刻就判负，完全莫名其妙。挪到回合末后，危机伤害直接进本回合的
	# 结算数字，判负也在结算里发生，玩家看得见自己是怎么死的。
	#
	# ⚠ 预警必须**一起**挪，不能只挪结算：只挪结算会让危机晚一整回合才落地，
	#   玩家白得多一整个回合准备（难度变松）。现在预警在本回合末发出 → 玩家下一
	#   回合整回合可以应对 → 下回合末爆发，准备窗口仍是 1 个回合，与原来一致。
	# ⚠ 顺序不能换：升格必须在抽新的之前，否则新抽的会把预告顶掉（预告就成假的了）。
	# ⚠ 放在 _check_failure() 之前：_resolve_pending_crisis 内部会 check_failure_now()，
	#   判负后 _check_failure() 直接返回 true 让 end_turn 提前 return，
	#   后面「打满回合」的 game_ended 就不会重复发一次报告。
	_resolve_pending_crisis()
	_promote_forecast_if_needed()
	_maybe_warn_crisis()
	_maybe_forecast_crisis()
	# 统一 emit 一次：UI 弹窗要同时展示「下回合」与「再下一回合」两条，
	# 所以必须等两场都定下来再通知（emit 在 _maybe_* 里发会导致弹窗只有前一条）。
	if not pending_crisis.is_empty():
		crisis_warned.emit(pending_crisis)

	# 失败判定：任一指标跌破致死线 → 被撤换，提前结束
	if _check_failure():
		return

	_check_knowledge_triggers()

	if turn >= TOTAL_TURNS:
		game_over = true
		game_ended.emit(generate_report())
	# 下一回合由主场景在展示完结算反馈后调用 start_new_turn()


## 当前难度的每回合行动位（= 一回合最多能打几张牌）
func action_slots() -> int:
	# ⚠ 首回合要算上「运筹帷幄」类词条的 +N。所有地方（能否出牌判定、HUD 提示、
	#   「已选 x/y」）都必须走这个入口 —— 0.0.8 真窗口实测：以前只有 can_execute
	#   自己加这一项，结果首回合 HUD 写「每回合最多 3 个行动」、实际能打 4 张。
	var n := int(MAX_ACTIONS_BY_DIFFICULTY.get(difficulty, 3))
	if turn == 1:
		n += int(Talents.get_bonus("first_turn_actions"))
	return n


## 当前难度的判负阈值：指标低于此值即判负
func failure_threshold() -> int:
	return FAILURE_THRESHOLD[difficulty]


## 某一项指标的判负阈值 = 难度线 + 该项偏移 + 该难度下的额外调整
## （两张表里都没写就是难度线本身）
func failure_threshold_for(metric: String) -> int:
	var offset: int = int(FAILURE_THRESHOLD_OFFSET.get(metric, 0))
	offset += int(FAILURE_THRESHOLD_EXTRA.get(difficulty, {}).get(metric, 0))
	return clampi(failure_threshold() + offset, 5, 95)


## 检查是否有指标跌破失败线（上级对政绩不满，将你撤换）
func _check_failure() -> bool:
	if game_over:
		return is_failure   # 已经判负，不重复判、不重复发信号
	for metric in metrics:
		var threshold: int = failure_threshold_for(metric)
		if metrics[metric] < threshold:
			is_failure = true
			game_over = true
			failure_metric = metric
			failure_value = metrics[metric]
			failure_reason = "上级对你的政绩不满意，将你撤换。"
			_add_log("✖ %s（%s 只剩 %d，已跌破生态红线 %d）" % [failure_reason, METRIC_NAMES.get(metric, metric), failure_value, threshold])
			game_ended.emit(generate_report())
			return true
	return false


## 指标一变就查：出牌、危机爆发、自然演化都可以直接调用 → 判负即时生效
func check_failure_now() -> bool:
	return _check_failure()


## 当前所有跌破致死线的指标（失败报告用来把死因说全）
func metrics_below_threshold() -> Array:
	var out: Array = []
	for metric in metrics:
		var threshold: int = failure_threshold_for(metric)
		if metrics[metric] < threshold:
			out.append({"metric": metric, "value": metrics[metric]})
	out.sort_custom(func(a, b): return int(a["value"]) < int(b["value"]))
	return out


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


## 指标增减。apply_penalty = false 时不吃「负向倍率」（危机伤害走这条路）。
## phase/label/ref_id 只用于算分动画的归因；phase 传空字符串 = 不入账（保持旧行为）。
func _apply_delta(metric: String, delta: int, apply_penalty: bool = true,
		phase: String = "", label: String = "", ref_id: String = "") -> void:
	if not metrics.has(metric):
		return
	# 扣分（负向变动）惩罚加成，倍率随难度递增。
	# ⚠ 危机伤害**不吃**这个倍率：危机数值（-14 之类）本身就是设计好的惩罚，
	#   再乘 1.5 / 2.0 会让困难档"任何一次危机都是一击必杀"——对策卡给的是正向数值
	#   （正向不乘倍率），+8 永远追不上 -28，"预警 → 对策卡 → 应对"的核心循环就废了。
	if delta < 0 and apply_penalty:
		delta = _scaled_delta(delta)
	var before: int = metrics[metric]
	var after: int = clampi(before + delta, 0, 100)
	metrics[metric] = after
	if phase != "":
		score_ledger.append({
			"phase": phase, "label": label, "ref_id": ref_id, "metric": metric,
			"raw": delta, "applied": after - before, "before": before, "after": after,
		})


## 清空流水账（每回合出牌结算前调用）
func clear_score_ledger() -> void:
	score_ledger.clear()


## 环湖人类围垦强度变化（仅驱动 3D 房子数量，不参与指标/失败判定）
func _apply_settlement(delta: int) -> void:
	var before := settlement
	settlement = clampi(settlement + delta, 0, 100)
	if settlement != before:
		_add_log("环湖人类围垦%s（%d）" % ["扩张" if delta > 0 else "收缩", delta])


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
	# 本局天赋点：需玩到 12 轮以上且平均评分达标（普通 >80 / 困难 >70），达标得 2 点
	var avg_score: float = (eco["score"] + social["score"] + manage["score"]) / 3.0
	var threshold: float = REPORT_SCORE[difficulty]
	var earned: int = 2 if (turn >= 12 and avg_score > threshold) else 0
	return {
		"eco": eco, "social": social, "manage": manage,
		"reflection": reflection,
		"is_failure": is_failure,
		"failure_reason": failure_reason,
		"failure_metric": failure_metric,
		"failure_metric_name": METRIC_NAMES.get(failure_metric, failure_metric),
		"failure_value": failure_value,
		"failure_threshold": failure_threshold_for(failure_metric) if failure_metric != "" else failure_threshold(),
		"metrics_below": metrics_below_threshold(),
		"seed": run_seed,
		"turns_survived": turn,
		"research_points": research_points,
		"knowledge_count": knowledge_unlocked.size(),
		"total_knowledge": KNOWLEDGE_CARDS.size(),
		"talent_points": earned,
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
	# 科研点现在有实际作用了（深预警），评语要与机制对齐，不能还是纯叙述
	if deep_warning_on():
		notes.append("监测预警已升级：危机可提前 2 回合预判。")
	else:
		notes.append("科研点累计到 %d 可升级监测预警，把危机预判从 1 回合延长到 2 回合。" % DEEP_WARN_RESEARCH)
	if research_points >= 20:
		notes.append("长期数据库建立，预报准确率高。")
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
