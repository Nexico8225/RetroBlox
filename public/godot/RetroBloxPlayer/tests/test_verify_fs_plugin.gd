extends SceneTree

func _init() -> void:
	print("Verifying fs_context_menu_plugin.gd...")
	var scr = load("res://addons/retroblox_studio/fs_context_menu_plugin.gd")
	if scr == null:
		printerr("FAILED to load fs_context_menu_plugin.gd")
		quit(1)
		return
	print("fs_context_menu_plugin.gd OK!")
	quit(0)
