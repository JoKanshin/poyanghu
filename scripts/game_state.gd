extends Node
## 《拯救鄱阳湖》—— 回合制生态管理模拟
## GameState 单例：数据 + 核心结算逻辑。UI/3D 表现由 main.gd 驱动。

# ==================== 常量 ====================
const TOTAL_TURNS := 16          # 一局 16 回合 = 4 年 × 4 季
const BASE_FUNDING := 100        # 每回合基础拨款（万）
const OPERATION_COST := 20       # 固定运营支出（万）
const MAX_CARRY := 60            # 结转上限（万）
const INTEREST_RATE := 0.05      # 结转利息（每回合，利滚利，利率从低）
const MAX_ACTIONS := 3           # 每回合最多执行行动数（行动位）

# 困难模式参数
const HARD_FAILURE_THRESHOLD := 35   # 困难模式：任一指标低于此值即判负
const HARD_FUNDING_PENALTY := 25     # 困难模式：每回合基础拨款削减（万）
const HARD_PENALTY_MULT := 1.5       # 困难模式：扣分（负向变动）惩罚倍率

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
	{
		"id": "water_replenish", "name": "生态补水（引江济湖）", "category": "ecology",
		"desc": "跨流域引水补充湖区水量，缓解枯水、恢复浅滩生境。",
		"cost": 40,
		"tiers": {
			"basic":    {"effects": [{"metric": "water_level", "delta": 5, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_level", "delta": 11, "delay": 0}, {"metric": "vegetation", "delta": 3, "delay": 1}]},
			"deep":     {"effects": [{"metric": "water_level", "delta": 19, "delay": 0}, {"metric": "vegetation", "delta": 6, "delay": 1}, {"metric": "community", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "引水挤占下游农业用水，社区信任 -3"},
	},
	{
		"id": "wetland_restore", "name": "退田还湿（湿地生态修复）", "category": "ecology",
		"desc": "将环湖低产农田退还为湿地，重建自然水文节律。",
		"cost": 50,
		"tiers": {
			"basic":    {"effects": [{"metric": "vegetation", "delta": 4, "delay": 1}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 10, "delay": 2}, {"metric": "water_quality", "delta": 5, "delay": 2}, {"metric": "community", "delta": -2, "delay": 0}]},
			"deep":     {"effects": [{"metric": "vegetation", "delta": 18, "delay": 2}, {"metric": "water_quality", "delta": 9, "delay": 2}, {"metric": "birds", "delta": 6, "delay": 3}, {"metric": "community", "delta": -4, "delay": 0}]},
		},
		"side_note": {"effective": "退田农户短期受损，社区信任 -2"},
	},
	{
		"id": "floating_island", "name": "人工浮岛（生态浮床）", "category": "ecology",
		"desc": "布置人工浮岛与生态浮床，吸附氮磷、净化水体。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "water_quality", "delta": 3, "delay": 0}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 7, "delay": 0}, {"metric": "vegetation", "delta": 3, "delay": 1}]},
			"deep":     {"effects": [{"metric": "water_quality", "delta": 13, "delay": 0}, {"metric": "vegetation", "delta": 5, "delay": 1}]},
		},
		"side_note": {},
	},
	{
		"id": "dredge", "name": "底泥清淤疏浚", "category": "ecology",
		"desc": "疏浚淤积底泥，削减内源污染、恢复湖床通透性。",
		"cost": 40,
		"tiers": {
			"basic":    {"effects": [{"metric": "water_quality", "delta": 3, "delay": 1}]},
			"effective": {"effects": [{"metric": "water_quality", "delta": 7, "delay": 1}, {"metric": "fish", "delta": 2, "delay": 2}]},
			"deep":     {"effects": [{"metric": "water_quality", "delta": 13, "delay": 1}, {"metric": "fish", "delta": 5, "delay": 2}, {"metric": "vegetation", "delta": -3, "delay": 0}]},
		},
		"side_note": {"deep": "机械清淤扰动湖床，短期植被 -3"},
	},
	{
		"id": "habitat_protect", "name": "越冬栖息地保护", "category": "ecology",
		"desc": "划定并管护候鸟越冬栖息地，控制人为干扰与栖息地破碎化。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "birds", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "birds", "delta": 7, "delay": 1}, {"metric": "vegetation", "delta": 2, "delay": 2}]},
			"deep":     {"effects": [{"metric": "birds", "delta": 13, "delay": 1}, {"metric": "vegetation", "delta": 4, "delay": 2}]},
		},
		"side_note": {},
	},
	{
		"id": "ecotourism", "name": "生态旅游与观鸟经济", "category": "social",
		"desc": "发展观鸟旅游与生态体验，让保护产生社区收益。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 3, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 6, "delay": 0}, {"metric": "birds", "delta": 3, "delay": 1}]},
			"deep":     {"effects": [{"metric": "community", "delta": 11, "delay": 0}, {"metric": "birds", "delta": 6, "delay": 1}, {"metric": "water_quality", "delta": -2, "delay": 0}]},
		},
		"side_note": {"deep": "游客激增带来环境压力，水质 -2"},
	},
	{
		"id": "damage_insurance", "name": "野生动物致害保险", "category": "social",
		"desc": "建立候鸟致害补偿保险，农户损失及时赔付。",
		"cost": 20,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 3, "delay": 0}]},
			"effective": {"effects": [{"metric": "community", "delta": 7, "delay": 0}, {"metric": "birds", "delta": 2, "delay": 1}]},
			"deep":     {"effects": [{"metric": "community", "delta": 12, "delay": 0}, {"metric": "birds", "delta": 4, "delay": 1}]},
		},
		"side_note": {"deep": "保险兜底后农户不再驱赶候鸟"},
	},
	{
		"id": "eco_brand", "name": "生态产品认证与助销", "category": "social",
		"desc": "认证湖区生态农产品并拓展销路，让绿色生产有利可图。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "community", "delta": 2, "delay": 1}]},
			"effective": {"effects": [{"metric": "community", "delta": 6, "delay": 1}, {"metric": "water_quality", "delta": 3, "delay": 2}]},
			"deep":     {"effects": [{"metric": "community", "delta": 11, "delay": 1}, {"metric": "water_quality", "delta": 6, "delay": 2}, {"metric": "vegetation", "delta": 3, "delay": 2}]},
		},
		"side_note": {"effective": "减少化肥农药投入，水质间接改善"},
	},
	{
		"id": "fish_restock", "name": "增殖放流", "category": "manage",
		"desc": "投放鱼苗，恢复鱼类资源量与江湖洄游通道。",
		"cost": 30,
		"tiers": {
			"basic":    {"effects": [{"metric": "fish", "delta": 3, "delay": 1}]},
			"effective": {"effects": [{"metric": "fish", "delta": 8, "delay": 2}, {"metric": "community", "delta": 2, "delay": 2}]},
			"deep":     {"effects": [{"metric": "fish", "delta": 15, "delay": 2}, {"metric": "community", "delta": 4, "delay": 2}]},
		},
		"side_note": {"deep": "渔民共享放流收益，社区信任 +4"},
	},
	{
		"id": "smart_patrol", "name": "智慧巡护（无人机遥感）", "category": "manage",
		"desc": "无人机与遥感全天候巡护，监测非法捕捞、火情与水质。",
		"cost": 40,
		"tiers": {
			"basic":    {"effects": [{"metric": "fish", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "fish", "delta": 6, "delay": 1}, {"metric": "water_quality", "delta": 2, "delay": 1}]},
			"deep":     {"effects": [{"metric": "fish", "delta": 12, "delay": 1}, {"metric": "water_quality", "delta": 4, "delay": 1}]},
		},
		"side_note": {},
	},
	{
		"id": "wetland_law", "name": "湿地保护立法", "category": "manage",
		"desc": "推动地方湿地保护条例，划定禁渔区与生态红线。",
		"cost": 50,
		"tiers": {
			"basic":    {"effects": [{"metric": "fish", "delta": 2, "delay": 2}]},
			"effective": {"effects": [{"metric": "fish", "delta": 6, "delay": 2}, {"metric": "birds", "delta": 4, "delay": 2}, {"metric": "community", "delta": 3, "delay": 2}]},
			"deep":     {"effects": [{"metric": "fish", "delta": 11, "delay": 2}, {"metric": "birds", "delta": 7, "delay": 2}, {"metric": "community", "delta": 5, "delay": 2}]},
		},
		"side_note": {"effective": "立法见效慢，2 回合后逐步显现"},
	},
	{
		"id": "grazing_ban", "name": "封洲禁牧", "category": "manage",
		"desc": "禁止湖洲过度放牧，保护洲滩草甸植被。",
		"cost": 20,
		"tiers": {
			"basic":    {"effects": [{"metric": "vegetation", "delta": 2, "delay": 0}]},
			"effective": {"effects": [{"metric": "vegetation", "delta": 5, "delay": 0}, {"metric": "community", "delta": -2, "delay": 0}]},
			"deep":     {"effects": [{"metric": "vegetation", "delta": 9, "delay": 0}, {"metric": "community", "delta": -4, "delay": 0}]},
		},
		"side_note": {"effective": "牧民失去放牧地，社区信任 -2"},
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
# weight：基础权重；cond：满足时权重翻倍，让危机与当前生态状态呼应。
const CRISES := [
	{
		"id": "drought", "name": "极端干旱", "weight": 1.0, "cond": "water_level < 45",
		"warn": "【自然预警】气象部门预报：未来一季降水显著偏少，湖区面临枯水风险。",
		"hit": "【危机爆发】极端干旱来袭——湖区水位骤降，沉水植物块茎大面积发育受阻，湖床裸露。",
		"effects": [{"metric": "water_level", "delta": -14}, {"metric": "vegetation", "delta": -7}],
	},
	{
		"id": "disease", "name": "苦草病害暴发", "weight": 0.9, "cond": "water_quality < 50",
		"warn": "【监测提示】巡护员发现局部水草出现腐烂迹象，疑与水体富营养化有关，建议加强监测。",
		"hit": "【危机爆发】苦草病害大面积暴发——沉水植被成片腐烂死亡，候鸟食物锐减。",
		"effects": [{"metric": "vegetation", "delta": -12}, {"metric": "water_quality", "delta": -6}],
	},
	{
		"id": "illegal_fishing", "name": "非法捕捞猖獗", "weight": 1.0, "cond": "fish < 50",
		"warn": "【巡护通报】近期湖区外围发现可疑船只活动轨迹，疑似非法捕捞，建议加强执法。",
		"hit": "【危机爆发】非法捕捞猖獗——电捕鱼与密眼网具造成鱼类资源骤减。",
		"effects": [{"metric": "fish", "delta": -13}],
	},
	{
		"id": "bird_conflict", "name": "候鸟大规模进田", "weight": 1.0, "cond": "community < 55",
		"warn": "【社区报告】农户反映白鹤开始向稻田聚集，若持续可能造成较大损失，请提前协商。",
		"hit": "【危机爆发】数千只候鸟涌入农田取食莲藕、踩踏稻苗，农户损失严重，矛盾激化。",
		"effects": [{"metric": "community", "delta": -14}, {"metric": "birds", "delta": 6}],
	},
	{
		"id": "flood", "name": "汛期洪水", "weight": 0.8, "cond": "water_level > 60",
		"warn": "【自然预警】上游持续降雨，水文站预计湖区水位将快速上涨。",
		"hit": "【危机爆发】汛期洪水漫过草洲——新生沉水植被被冲毁，底质遭到破坏。",
		"effects": [{"metric": "water_level", "delta": 18}, {"metric": "vegetation", "delta": -10}],
	},
	{
		"id": "pollution", "name": "上游污染输入", "weight": 0.9, "cond": "water_quality < 55",
		"warn": "【水质预警】上游监测断面总磷浓度上升，污染团可能随水流进入湖区。",
		"hit": "【危机爆发】上游污染团入境——总磷总氮严重超标，鱼类与沉水植物同时受损。",
		"effects": [{"metric": "water_quality", "delta": -14}, {"metric": "fish", "delta": -6}],
	},
	{
		"id": "invasive", "name": "外来物种暴发", "weight": 0.9, "cond": "vegetation < 55",
		"warn": "【巡查发现】湖区外围发现福寿螺与凤眼莲扩散迹象，繁殖速度较快。",
		"hit": "【危机爆发】外来物种暴发——福寿螺啃食水生植物，凤眼莲覆盖水面挤占生存空间。",
		"effects": [{"metric": "vegetation", "delta": -10}, {"metric": "fish", "delta": -5}],
	},
	{
		"id": "algal_bloom", "name": "蓝藻水华", "weight": 0.85, "cond": "water_quality > 60",
		"warn": "【监测提示】气温升高、水体流动性变差，蓝藻水华风险上升。",
		"hit": "【危机爆发】蓝藻水华暴发——水面被绿色藻膜覆盖，水体缺氧，候鸟中毒与食物短缺同时发生。",
		"effects": [{"metric": "water_quality", "delta": -12}, {"metric": "birds", "delta": -8}],
	},
	{
		"id": "wetland_encroach", "name": "围湖造田", "weight": 1.0, "cond": "community < 55",
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
var research_points: int = 0
var metrics: Dictionary = {}
var species_pop: Dictionary = {}     # 每物种数量 0-100
var plant_pop: Dictionary = {}       # 每植物数量 0-100
var effects_queue: Array = []       # 延迟效果 {metric, delta, remaining, source}
var used_action_ids: Array = []     # 本回合已执行的卡
var knowledge_unlocked: Array = []
var pending_knowledge: Array = []   # 待弹出的知识卡 id
var log_messages: Array = []        # 因果提示
var game_over: bool = false
var total_spent: int = 0            # 累计卡牌支出（用于资金效率评价）
# ===== 肉鸽机制状态 =====
var run_seed: int = 0               # 本局种子（同种子可复现，用于反事实对照）
var settlement: int = 70            # 环湖人类围垦强度 0-100，仅用于 3D 房子表现
var hard_mode: bool = false         # 困难模式（主菜单选择）
var pending_crisis: Dictionary = {} # 待爆发的危机（本回合预警，下回合生效）
var last_crisis_name: String = ""   # 上回合爆发的危机名（用于结算展示）
var triggered_synergies: Array = [] # 本回合触发的协同
var _fired_synergies: Array = []    # 本局已触发过的协同（防重复）
var is_failure: bool = false        # 是否因生态崩溃提前结束
var failure_reason: String = ""     # 失败原因文案
var failure_metric: String = ""     # 崩溃的指标

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
	settlement = 70
	effects_queue = []
	used_action_ids = []
	knowledge_unlocked = []
	pending_knowledge = []
	log_messages = []
	game_over = false
	pending_crisis = {}
	last_crisis_name = ""
	triggered_synergies = []
	_fired_synergies = []
	is_failure = false
	failure_reason = ""
	failure_metric = ""
	# 每局随机种子：同种子可复现（企划书 8.3 反事实对照）
	if run_seed == 0:
		randomize()
		run_seed = randi()
	seed(run_seed)
	metrics = _roll_starting_metrics()
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
	var out := {}
	for k in base:
		# 每项在 ±9 内偏移，并保证不低于失败线（25）
		out[k] = clampi(base[k] + _randi_range(-9, 9), 25, 88)
	# 至少保证有一项明显偏弱，制造"这局的软肋"
	var weak_keys: Array = out.keys()
	var weak: String = weak_keys[_randi_range(0, weak_keys.size() - 1)]
	out[weak] = clampi(out[weak] - 12, 25, 88)
	return out


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
	# 困难模式：初始/每回合资金削减
	if hard_mode:
		funding -= HARD_FUNDING_PENALTY

	funds = carry + funding - OPERATION_COST
	carry = 0

	metrics_changed.emit()
	funds_changed.emit()
	turn_changed.emit()

	# 触发本回合事件
	if EVENTS.has(turn):
		event_triggered.emit(EVENTS[turn])

	# 危机系统：先结算爆发的，再抽取新的预警
	_resolve_pending_crisis()
	_maybe_warn_crisis()


## 结算上回合预警的危机：爆发并造成较重惩罚
func _resolve_pending_crisis() -> void:
	if pending_crisis.is_empty():
		return
	var c: Dictionary = pending_crisis
	pending_crisis = {}
	last_crisis_name = c["name"]
	_add_log("⚠ %s" % c["hit"])
	for e in c["effects"]:
		_apply_delta(e["metric"], e["delta"])
		_add_log("   %s %+d" % [METRIC_NAMES[e["metric"]], e["delta"]])
	if c.has("settlement"):
		_apply_settlement(c["settlement"])
	_sync_species()
	_sync_plants()
	metrics_changed.emit()
	event_triggered.emit(c["hit"])


## 抽取本回合的危机预警（提前 1 回合告知，给玩家应对机会）
func _maybe_warn_crisis() -> void:
	if turn >= TOTAL_TURNS - 1:
		return  # 最后两回合不再新增危机，避免无法应对
	if not pending_crisis.is_empty():
		return  # 已有待爆发的危机，不叠加
	# 从第 3 回合起才开始抽危机，给玩家缓冲
	if turn < 3:
		return
	# 基础概率 38%（困难模式 55%），随回合推进略升（后期压力更大）
	var chance: float
	if hard_mode:
		chance = 0.55 + float(turn) / float(TOTAL_TURNS) * 0.25
	else:
		chance = 0.38 + float(turn) / float(TOTAL_TURNS) * 0.22
	if randf() > chance:
		return
	# 加权抽选：与当前生态状态呼应的危机会更容易出现
	var total_w := 0.0
	var weights: Array = []
	for c in CRISES:
		var w: float = c["weight"]
		if _eval_condition_simple(c["cond"]):
			w *= 1.8  # 状态吻合 → 权重翻倍
		weights.append(w)
		total_w += w
	var roll := randf() * total_w
	for i in CRISES.size():
		roll -= weights[i]
		if roll <= 0.0:
			pending_crisis = CRISES[i]
			event_triggered.emit(pending_crisis["warn"])
			return


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
	return int(round(card["cost"] * TIER_COST_MULT[tier]))


## 从卡池随机抽 n 张（不重复，洗牌后取前 n）
func draw_cards(n: int) -> Array:
	var pool := ACTION_CARDS.duplicate()
	pool.shuffle()
	return pool.slice(0, min(n, pool.size()))


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

	# 行动对特定植物的直接加成
	if ACTION_PLANT_BONUS.has(card_id):
		for pid in ACTION_PLANT_BONUS[card_id]:
			plant_pop[pid] = clampi(plant_pop[pid] + ACTION_PLANT_BONUS[card_id][pid], 0, 100)

	# 行动对环湖用地（房子数量）的影响
	if ACTION_SETTLEMENT_DELTA.has(card_id):
		_apply_settlement(ACTION_SETTLEMENT_DELTA[card_id])

	funds_changed.emit()
	metrics_changed.emit()
	return true


## 结算自然演化（每回合结束调用）
## 设计：不做决策生态会缓慢恶化（压力），但不会瞬间崩盘（给玩家反应时间）
func natural_evolution() -> void:
	# 水位随机波动（枯水更常见，符合鄱阳湖现实）
	_apply_delta("water_level", _randi_range(-5, 3))

	# 水质：无治理则缓慢恶化
	if used_action_ids.has("water_monitor") or used_action_ids.has("research") or used_action_ids.has("smart_patrol"):
		pass  # 本回合有监测/科研/智慧巡护投入 → 水质不恶化
	else:
		_apply_delta("water_quality", -2)

	# 植被受水质拖累：水质差则植被退化（比之前更重）
	if metrics["water_quality"] < 45:
		_apply_delta("vegetation", -3)
	elif metrics["water_quality"] > 70:
		_apply_delta("vegetation", 1)

	# 植被是候鸟食物基础
	if metrics["vegetation"] < 42:
		_apply_delta("birds", -3)
	elif metrics["vegetation"] > 70:
		_apply_delta("birds", 1)

	# 鱼类：禁渔带来缓慢恢复，但执法不足则恢复停滞
	if used_action_ids.has("patrol") or used_action_ids.has("guard_team"):
		_apply_delta("fish", 2)
	else:
		_apply_delta("fish", -1)  # 无巡护 → 非法捕捞蚕食

	# 社区信任：长期缺补偿则持续下降
	if metrics["community"] < 45 and not used_action_ids.has("community_comp"):
		_apply_delta("community", -3)

	_sync_species()
	_sync_plants()
	metrics_changed.emit()


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
			_apply_delta(e["metric"], e["delta"])
			_add_log("   %s %+d" % [METRIC_NAMES[e["metric"]], e["delta"]])
	_sync_species()
	_sync_plants()


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


## 回合结束：推进延迟、自然演化、结算协同、检查失败与知识卡
func end_turn() -> void:
	advance_effects()
	resolve_synergies()      # 卡牌协同（在自然演化前结算，让玩家看到组合收益）
	natural_evolution()

	# 结转规则：未用资金计息（利滚利），最多 MAX_CARRY 万，溢出转科研点
	carry = int(round(funds * (1.0 + INTEREST_RATE)))
	if carry > MAX_CARRY:
		var overflow := carry - MAX_CARRY
		research_points += overflow / 10
		carry = MAX_CARRY
	funds = 0

	# 失败判定：任一指标跌破 20 → 被撤换，提前结束
	if _check_failure():
		return

	_check_knowledge_triggers()

	if turn >= TOTAL_TURNS:
		game_over = true
		game_ended.emit(generate_report())
	# 下一回合由主场景在展示完结算反馈后调用 start_new_turn()


## 检查是否有指标跌破失败线（普通 20 / 困难 35：上级对政绩不满，将你撤换）
func _check_failure() -> bool:
	var threshold: int = HARD_FAILURE_THRESHOLD if hard_mode else 20
	for metric in metrics:
		if metrics[metric] < threshold:
			is_failure = true
			game_over = true
			failure_metric = metric
			failure_reason = "上级对你的政绩不满意，将你撤换。"
			_add_log("✖ %s（%s 跌破 %d）" % [failure_reason, METRIC_NAMES.get(metric, metric), threshold])
			game_ended.emit(generate_report())
			return true
	return false


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
	# 困难模式：扣分（负向变动）惩罚加成
	if hard_mode and delta < 0:
		delta = roundi(delta * HARD_PENALTY_MULT)
	metrics[metric] = clampi(metrics[metric] + delta, 0, 100)


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
	return {
		"eco": eco, "social": social, "manage": manage,
		"reflection": reflection,
		"is_failure": is_failure,
		"failure_reason": failure_reason,
		"failure_metric": failure_metric,
		"seed": run_seed,
		"turns_survived": turn,
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
