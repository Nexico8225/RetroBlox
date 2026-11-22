extends SceneTree

func _init() -> void:
	for m in ClassDB.class_get_method_list("EditorContextMenuPlugin", true):
		if m["name"] == "_popup_menu":
			print("_popup_menu args: ", m["args"])
	quit(0)
