@tool
extends SceneTree
func _initialize() -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("export/android/java_sdk_path", "C:/android/jdk17/jdk-17.0.20.1+1")
	settings.set_setting("export/android/android_sdk_path", "C:/android/sdk")
	print("ANDROID_SDK_READY")
	quit()
