extends SceneTree

func _init() -> void:
	print("Checking how FileSystemDock context menu is structured...")
	var tb_scr = load("res://addons/retroblox_studio/toolbox_dock.gd")
	var sp_scr = load("res://addons/retroblox_studio/studio_plugin.gd")
	print("Plugins loaded fine.")
	quit(0)
