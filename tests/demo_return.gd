extends Node

func _ready() -> void:
	if not OS.get_user_data_dir().contains("PoyangDemo"):
		get_tree().quit(2)
		return
	# A sibling of current_scene survives the actual scene change at the end.
	var watch := preload("res://tests/fixtures/demo_return_watch.gd").new()
	get_tree().root.add_child.call_deferred(watch)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
