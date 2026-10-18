extends Node
const Physics = preload("res://scripts/motion_web.gd")
var depth := 0.0
var rest := Vector2.ZERO
var displacement := Vector2.ZERO
var target := Vector2.ZERO

static func attach(control: Control, gain: float) -> void:
	var driver: Node = load("res://scripts/motion_parallax.gd").new()
	driver.name = "MotionWebDepth"
	driver.depth = gain
	control.add_child(driver)

func _ready() -> void:
	rest = get_parent().position
	set_process(preload("res://scripts/mobile_support.gd").enabled())
	get_parent().visibility_changed.connect(_visibility)

func _visibility() -> void:
	target = Vector2.ZERO
	if preload("res://scripts/mobile_support.gd").enabled() and get_parent().is_visible_in_tree():
		set_process(true)
	if not get_parent().is_visible_in_tree():
		get_parent().position = rest
		displacement = Vector2.ZERO
		set_process(false)

func _input(event: InputEvent) -> void:
	if preload("res://scripts/mobile_support.gd").enabled(): return
	if not event is InputEventMouseMotion or not get_parent().is_visible_in_tree(): return
	if Physics.paused(self): return
	if Physics.reduced(self):
		target = Vector2.ZERO
		displacement = Vector2.ZERO
		get_parent().position = rest
		set_process(false)
		return
	var viewport_size := get_viewport().get_visible_rect().size
	target = Vector2.ZERO if Physics.reduced(self) else (event.position / viewport_size - Vector2.ONE * 0.5) * depth
	set_process(true)

func _process(dt: float) -> void:
	var mobile_mode := preload("res://scripts/mobile_support.gd").enabled()
	if mobile_mode:
		var host := get_tree().get_first_node_in_group("motion_host")
		if host and host.mobile: target = host.mobile.tilt * depth * 2.0
	if Physics.paused(self): return
	if Physics.reduced(self):
		target = Vector2.ZERO
		displacement = Vector2.ZERO
		get_parent().position = rest
		set_process(mobile_mode)
		return
	displacement = displacement.lerp(target, 1.0 - exp(-10.0 * dt))
	if displacement.distance_to(target) < 0.02:
		displacement = target
		set_process(mobile_mode)
	get_parent().position = rest + displacement
