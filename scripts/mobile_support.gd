extends RefCounted
## Shared feature check; the preview flag exercises the same UI on a desktop.
static func enabled() -> bool:
	return OS.has_feature("android") or "--mobile-preview" in OS.get_cmdline_user_args()

static func tap(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and (not event.pressed if enabled() else event.pressed)
