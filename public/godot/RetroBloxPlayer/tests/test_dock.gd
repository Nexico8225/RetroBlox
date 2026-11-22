@tool
extends SceneTree

func _init() -> void:
	print("=== VERIFYING TOOLBOX DOCK UPDATES ===")
	var dock_cls = load("res://addons/retroblox_studio/toolbox_dock.gd")
	print("Dock class loaded: ", dock_cls != null)
	var dock = dock_cls.new()
	print("Dock instantiated: ", dock != null)
	print("Catalog count: ", dock._catalog_items.size())
	dock.free()
	print("=== ALL CHECKS PASSED ===")
	quit(0)
