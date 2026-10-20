extends Node
var age := 0.0
var saw_demo := false
var stable_menu := 0.0
var clicked_entry := false
var entry_hid_immediately := false

func _process(dt: float) -> void:
	age += dt
	var scene := get_tree().current_scene
	if age > 64:
		push_error("Demo did not return to a usable menu before the timeout")
		get_tree().quit(1)
		return
	if scene == null: return
	if not clicked_entry and scene.scene_file_path == "res://scenes/main.tscn":
		var game: Node = scene.get_node("Game")
		game._show_menu()
		var button: Button = game.demo_entry_button
		if not is_instance_valid(button):
			push_error("The main menu has no demo entry")
			get_tree().quit(1)
			return
		button.pressed.emit()
		clicked_entry = true
		entry_hid_immediately = not button.visible and button.disabled
		if not entry_hid_immediately:
			push_error("The demo entry did not hide immediately after clicking")
			get_tree().quit(1)
		return
	if scene.scene_file_path == "res://scenes/demo.tscn":
		if stable_menu > 0:
			push_error("--demo-auto repeated instead of remaining at the menu")
			get_tree().quit(1)
		saw_demo = true
	elif saw_demo and scene.scene_file_path == "res://scenes/main.tscn":
		stable_menu += dt
		if stable_menu < 0.6: return
		var game: Node = scene.get_node("Game")
		var ok: bool = game.menu_root.visible and not game._playing and not game._ending_playing and not get_tree().paused and entry_hid_immediately and is_instance_valid(game.demo_entry_button) and game.demo_entry_button.visible
		var file := FileAccess.open("user://demo-return-check.json", FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"returned_to_menu": ok, "elapsed": age, "stable_menu_seconds": stable_menu, "entry_hidden_immediately": entry_hid_immediately, "entry_available_again_on_return": game.demo_entry_button.visible}))
		print("DEMO_RETURN: ", "PASS" if ok else "FAIL", " at ", snappedf(age, 0.01), " seconds")
		get_tree().quit(0 if ok else 1)
