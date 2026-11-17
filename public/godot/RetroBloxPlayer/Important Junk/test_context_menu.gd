extends SceneTree

func _init() -> void:
	print("Checking EditorContextMenuPlugin in ClassDB...")
	if ClassDB.class_exists("EditorContextMenuPlugin"):
		print("EditorContextMenuPlugin exists!")
		for m in ClassDB.class_get_method_list("EditorContextMenuPlugin"):
			print("  ", m["name"])
		for s in ClassDB.class_get_signal_list("EditorContextMenuPlugin"):
			print("  signal: ", s["name"])
	else:
		print("EditorContextMenuPlugin does NOT exist in ClassDB")
		# Check any class with ContextMenu
		for c in ClassDB.get_class_list():
			if c.find("ContextMenu") >= 0 or c.find("FileSystem") >= 0:
				print("Related class: ", c)
	quit(0)
