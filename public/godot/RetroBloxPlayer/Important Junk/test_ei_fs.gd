extends SceneTree

func _init() -> void:
	for m in ClassDB.class_get_method_list("EditorInterface", true):
		if m["name"].find("file_system") >= 0 or m["name"].find("paths") >= 0:
			print(m["name"])
	quit(0)
