extends SceneTree

func _init() -> void:
	print("Testing load of toolbox_dock.gd...")
	var tb_scr = load("res://addons/retroblox_studio/toolbox_dock.gd")
	if tb_scr == null:
		print("FAILED to load toolbox_dock.gd")
		quit(1)
		return
	print("toolbox_dock.gd parsed and loaded successfully!")

	print("Testing load of studio_plugin.gd...")
	var sp_scr = load("res://addons/retroblox_studio/studio_plugin.gd")
	if sp_scr == null:
		print("FAILED to load studio_plugin.gd")
		quit(1)
		return
	print("studio_plugin.gd parsed and loaded successfully!")
	quit(0)
