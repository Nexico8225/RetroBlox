extends SceneTree

func _init() -> void:
	for m in ClassDB.class_get_method_list("EditorContextMenuPlugin", true):
		print("Method: ", m["name"], " args: ", m["args"])
	quit(0)
