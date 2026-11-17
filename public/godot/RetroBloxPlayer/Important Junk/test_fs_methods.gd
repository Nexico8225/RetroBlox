extends SceneTree

func _init() -> void:
	print("Checking EditorPlugin and FileSystemDock methods in Godot 4...")
	for m in ClassDB.class_get_method_list("EditorPlugin"):
		if m["name"].find("file") >= 0 or m["name"].find("context") >= 0 or m["name"].find("dock") >= 0:
			print("EditorPlugin: ", m["name"])
			
	if ClassDB.class_exists("FileSystemDock"):
		for m in ClassDB.class_get_method_list("FileSystemDock"):
			if m["name"].find("menu") >= 0 or m["name"].find("context") >= 0 or m["name"].find("file") >= 0:
				print("FileSystemDock: ", m["name"])
	quit(0)
