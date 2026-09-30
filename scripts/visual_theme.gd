extends RefCounted
## Shared presentation tokens. No gameplay state is changed here.
const INK := Color("102f35")
const PANEL := Color("123b40")
const EDGE := Color("508078")
const PAPER := Color("f1e8cc")
const GOLD := Color("f1c66e")
const MINT := Color("9dd5bd")
const ART := preload("res://assets/art/conservation-cards.png")

static func box(bg: Color, edge: Color, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(2)
	s.set_corner_radius_all(5)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0.015, 0.06, 0.07, 0.45)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 4)
	return s

static func card_style(selected: bool = false) -> StyleBoxFlat:
	var s := box(PAPER, GOLD if selected else Color("b5c6a9"), 7)
	s.shadow_size = 9 if selected else 5
	s.shadow_color = Color(0.02, 0.10, 0.11, 0.55)
	return s

static func illustration(card: Dictionary) -> AtlasTexture:
	var category := str(card.get("category", "ecology"))
	var column: int = {"ecology": 0, "social": 1, "manage": 2}.get(category, 0)
	# Stable artwork selection without consuming the game's random generator.
	var row := posmod(str(card.get("id", "")).hash(), 2)
	var tile := Vector2(ART.get_width() / 3.0, ART.get_height() / 2.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = ART
	atlas.region = Rect2(Vector2(column, row) * tile, tile)
	atlas.filter_clip = true
	return atlas

static func style_button(b: Button, danger: bool = false, primary: bool = false) -> void:
	var base := Color("783f3e") if danger else PANEL
	var accent := Color("f3ab91") if danger else MINT
	if primary:
		base = GOLD
		accent = Color("fff0b7")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var bg := base
		if state == "hover": bg = base.lightened(0.15)
		if state == "pressed": bg = base.darkened(0.18)
		if state == "disabled": bg = Color("263e41")
		var s := box(bg, accent if state == "hover" else base.lightened(0.22), 7)
		s.shadow_size = 1 if state == "pressed" else 4
		s.shadow_offset.y = 1 if state == "pressed" else 3
		b.add_theme_stylebox_override(state, s)
	var focus := box(Color(0, 0, 0, 0), GOLD, 7)
	focus.shadow_size = 0
	b.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK if primary else PAPER)
	b.add_theme_color_override("font_disabled_color", Color("8b9b94"))

static func button_feedback(b: Button, active: bool) -> void:
	var previous: Tween = b.get_meta("feedback_tween") if b.has_meta("feedback_tween") else null
	if previous and previous.is_valid(): previous.kill()
	var tw := b.create_tween()
	b.set_meta("feedback_tween", tw)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "modulate", Color(1.09, 1.09, 1.04) if active else Color.WHITE, 0.14)
