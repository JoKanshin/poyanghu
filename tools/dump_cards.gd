extends SceneTree
## 卡牌数值导出（给美术/策划对表用）
## 用法：<godot> --headless --path . --script res://tools/dump_cards.gd
## 输出：每条卡一行 TSV —— 名称、种类、费用(基础/有效/深度)、各档效果、标签
##       效果字段格式：指标 值（延迟N）  多个用 ' / ' 连接；某档没有的项不出现
##       标签字段用 '、' 连接（危机对策卡匹配用，对表文档的附录要用）
## 之所以让引擎自己导出：三档数值是曲里拐弯算出来的，人在文档里手抄必错。

const CAT := {"ecology": "生态", "social": "社会", "manage": "管理"}


## ⚠ 注意：--script 模式下**不能**在编译期引用 autoload 的全局名（GameState/Talents），
##   否则会带着 game_state.gd 一起编译，而那时 autoload 标识符还没注册，报
##   "Identifier not found: Talents"。所以这里一律走 root.get_node_or_null + 动态取值。
func _initialize() -> void:
	var GS: Node = root.get_node_or_null("GameState")
	if GS == null:
		print("FAIL: 缺 GameState")
		quit(1)
		return
	var names: Dictionary = GS.METRIC_NAMES
	var cards: Array = GS.ACTION_CARDS
	print("名称	种类	基础价	有效价	深度价	基础效果	有效效果	深度效果	标签")
	for card in cards:
		var tiers: Array = []
		var eff: Array = []
		for t in ["basic", "effective", "deep"]:
			tiers.append(str(GS.tier_cost(str(card["id"]), t)))
			eff.append(_eff_text(card, t, names))
		print("%s	%s	%s	%s	%s	%s	%s	%s	%s" % [str(card["name"]),
			CAT.get(str(card["category"]), str(card["category"])),
			tiers[0], tiers[1], tiers[2], eff[0], eff[1], eff[2],
			"、".join(PackedStringArray(card.get("tags", [])))])
	quit(0)


func _eff_text(card: Dictionary, tier: String, names: Dictionary) -> String:
	var parts: Array = []
	for e in card["tiers"][tier]["effects"]:
		var d: int = int(e.get("delay", 0))
		var suffix := "（延迟%d）" % d if d > 0 else ""
		parts.append("%s %+d%s" % [names.get(str(e["metric"]), str(e["metric"])), int(e["delta"]), suffix])
	return " / ".join(parts) if not parts.is_empty() else "—"
