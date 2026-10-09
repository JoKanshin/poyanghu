extends "res://scripts/main.gd"
var replayed_cards: Array[String] = []
var popped_cards: Array[String] = []
func _play_score_animation(ledger: Array, before_all: Dictionary, played: Array, after: Dictionary) -> void:
	for index in played:
		replayed_cards.append(str(card_infos[index]["card_id"]))
	await super._play_score_animation(ledger, before_all, played, after)
func _play_card_shake(panel: PanelContainer, amp: float) -> void:
	popped_cards.append(str(panel.get_meta("probe_card_id", "")))
	super._play_card_shake(panel, amp)
