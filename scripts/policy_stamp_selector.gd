extends Control
## Supplied parchment artwork, with one animated seal on the chosen policy.
signal tier_requested(tier: String)
signal stamp_landed
const TIERS := ["basic", "effective", "deep"]
const PAGES := [preload("res://assets/ui/policy-stamp/basic-page.png"), preload("res://assets/ui/policy-stamp/effective-page.png"), preload("res://assets/ui/policy-stamp/deep-page.png")]
const SEALS := [preload("res://assets/ui/policy-stamp/basic-seal.png"), preload("res://assets/ui/policy-stamp/effective-seal.png"), preload("res://assets/ui/policy-stamp/deep-seal.png")]
const CENTERS := [204.0, 343.0, 482.0]
const HOVER_ALPHA := 0.28
var selected := 1
var page: TextureRect
var seal: TextureRect
var hover_seal: TextureRect
var buttons: Array[Button] = []
var _locked := false
var _hovered := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	page = TextureRect.new()
	page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.stretch_mode = TextureRect.STRETCH_SCALE
	page.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	hover_seal = TextureRect.new()
	hover_seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hover_seal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hover_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_seal.modulate.a = HOVER_ALPHA
	hover_seal.hide()
	add_child(hover_seal)
	seal = TextureRect.new()
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seal)
	for i in 3:
		var button := Button.new()
		button.flat = true
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.tooltip_text = ["基础政策投入 · 半价", "有效政策投入 · 全价", "深度政策投入 · 双倍价"][i]
		button.pressed.connect(func(): tier_requested.emit(TIERS[i]))
		button.mouse_entered.connect(_on_slot_entered.bind(i))
		button.mouse_exited.connect(_on_slot_exited.bind(i))
		add_child(button)
		buttons.append(button)
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)
	snap_to_tier(selected, false)

func _on_slot_entered(index: int) -> void:
	_hovered = index
	set_process(true)
	_refresh_hover_seal()

func _on_slot_exited(index: int) -> void:
	if _hovered != index: return
	_hovered = -1
	set_process(false)
	hover_seal.hide()

func _on_visibility_changed() -> void:
	if is_visible_in_tree(): return
	_hovered = -1
	set_process(false)
	if hover_seal != null: hover_seal.hide()

func _process(_delta: float) -> void:
	# Cooldown can disable/re-enable a button without moving the mouse.
	_refresh_hover_seal()

func _refresh_hover_seal() -> void:
	var available := not _locked and _hovered >= 0 and _hovered != selected and is_visible_in_tree()
	if available:
		available = not buttons[_hovered].disabled and get_viewport().gui_get_hovered_control() == buttons[_hovered]
	hover_seal.visible = available
	if available:
		hover_seal.texture = SEALS[_hovered]
		hover_seal.position = Vector2(CENTERS[_hovered] - 75.0, 175) * size / Vector2(667, 500)

func _layout() -> void:
	if seal == null: return
	var factor := size / Vector2(667, 500)
	seal.size = Vector2(150, 135) * factor
	seal.position = Vector2(CENTERS[selected] - 75.0, 175) * factor
	seal.pivot_offset = seal.size * 0.5
	hover_seal.size = seal.size
	for i in buttons.size():
		buttons[i].position = Vector2(CENTERS[i] - 65.0, 185) * factor
		buttons[i].size = Vector2(130, 170) * factor
	_refresh_hover_seal()

func snap_to_tier(index: int, animate: bool) -> void:
	selected = clampi(index, 0, 2)
	if page == null: return
	page.texture = PAGES[selected]
	seal.texture = SEALS[selected]
	_layout()
	preload("res://scripts/motion.gd").cancel(seal, "stamp")
	seal.scale = Vector2.ONE
	seal.modulate.a = 1.0
	if animate:
		seal.scale = Vector2(1.22, 1.22)
		seal.modulate.a = 0.25
		var tw := preload("res://scripts/motion.gd").tween(seal, "response", "stamp")
		tw.tween_property(seal, "scale", Vector2(0.96, 0.96), 0.10)
		tw.parallel().tween_property(seal, "modulate:a", 1.0, 0.10)
		tw.tween_callback(stamp_landed.emit)
		tw.tween_property(seal, "scale", Vector2.ONE, 0.08)

func set_locked(locked: bool) -> void:
	if _locked == locked: return
	_locked = locked
	modulate.a = 0.55 if locked else 1.0
	for button in buttons: button.disabled = locked
	_refresh_hover_seal()
