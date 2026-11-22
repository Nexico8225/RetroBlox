extends SceneTree

func _init() -> void:
	print("FileSystemDock signals:")
	for s in ClassDB.class_get_signal_list("FileSystemDock", true):
		print("  signal: ", s["name"], " args: ", s["args"])
	print("FileSystemDock methods:")
	for m in ClassDB.class_get_method_list("FileSystemDock", true):
		print("  method: ", m["name"])
	quit(0)
