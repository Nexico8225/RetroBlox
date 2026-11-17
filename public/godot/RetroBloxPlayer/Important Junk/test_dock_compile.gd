
@tool
extends SceneTree

func _init() -> void:
	var dock_script = load('res://addons/retroblox_studio/toolbox_dock.gd')
	if dock_script != null:
		var dock = dock_script.new()
		print('toolbox_dock compiled and instantiated successfully!')
	quit()
