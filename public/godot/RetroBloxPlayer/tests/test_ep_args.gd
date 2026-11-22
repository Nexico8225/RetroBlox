extends SceneTree

func _init() -> void:
	for m in ClassDB.class_get_method_list("EditorPlugin", true):
		if m["name"].find("context_menu") >= 0:
			print(m["name"], " -> ", m["args"])
	quit(0)
