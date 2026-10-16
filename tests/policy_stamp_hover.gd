extends Node

const Selector := preload("res://scripts/policy_stamp_selector.gd")
var selector: Control
var checks := 0
var failures := 0
var requests: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func move_to(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame

func hover(index: int) -> void:
	await move_to(selector.buttons[index].get_global_rect().get_center())

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	selector = Selector.new()
	selector.position = Vector2(40, 40)
	selector.size = Vector2(667, 500)
	add_child(selector)
	selector.tier_requested.connect(func(tier: String): requests.append(tier))
	await get_tree().process_frame
	check(not selector.hover_seal.visible, "No preview before mouse hover")
	for index in [0, 2]:
		await hover(index)
		check(selector.hover_seal.visible, "An enabled unstamped box shows a preview")
		check(selector.hover_seal.texture == selector.SEALS[index], "Preview reuses that tier's actual seal texture")
		check(selector.hover_seal.modulate == Color(1, 1, 1, selector.HOVER_ALPHA), "Only opacity changes, not the seal color")
		check(selector.hover_seal.size == selector.seal.size and selector.hover_seal.scale == Vector2.ONE, "Preview uses the real seal's size without an animation")
		check(selector.selected == 1 and selector.seal.texture == selector.SEALS[1] and is_equal_approx(selector.seal.modulate.a, 1.0), "Hover does not change the selected tier or real stamp")
		check(requests.is_empty(), "Hover does not request a policy change")
	await hover(1)
	check(not selector.hover_seal.visible, "Already stamped box has no preview")
	await hover(0)
	selector.buttons[0].disabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(not selector.hover_seal.visible, "Disabling the hovered box hides the preview without mouse movement")
	selector.buttons[0].disabled = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(selector.hover_seal.visible, "Re-enabling the same box restores the preview without mouse movement")
	selector.set_locked(true)
	check(not selector.hover_seal.visible, "Cooldown/settlement lock hides the preview immediately")
	await hover(2)
	check(not selector.hover_seal.visible, "Entering a locked box never shows a preview")
	selector.set_locked(false)
	await get_tree().process_frame
	check(selector.hover_seal.visible, "Unlocking while hovered restores the preview")
	selector.snap_to_tier(2, false)
	check(not selector.hover_seal.visible, "Stamping the previewed tier removes the preview immediately")
	await hover(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = selector.buttons[0].get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	get_viewport().push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click, true)
	check(requests == ["basic"], "The preview does not intercept clicks on its box")
	selector.size *= 0.5
	await get_tree().process_frame
	await hover(0)
	check(selector.hover_seal.size.is_equal_approx(Vector2(75, 67.5)), "Preview follows responsive selector scaling")
	check(selector.hover_seal.position.is_equal_approx(Vector2(64.5, 87.5)), "Preview stays aligned with the stamp position after resizing")
	var overlay := ColorRect.new()
	overlay.position = selector.position
	overlay.size = selector.size
	add_child(overlay)
	await hover(0)
	check(not selector.hover_seal.visible, "An overlay blocking the box suppresses the preview")
	overlay.queue_free()
	await get_tree().process_frame
	await move_to(Vector2(1200, 700))
	check(not selector.hover_seal.visible and not selector.is_processing(), "Leaving the region removes the preview and stops hover polling")
	await hover(0)
	selector.hide()
	check(not selector.hover_seal.visible, "Hiding the selector clears its preview")
	print("POLICY_STAMP_HOVER: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
