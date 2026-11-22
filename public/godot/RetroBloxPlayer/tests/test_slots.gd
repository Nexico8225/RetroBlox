extends SceneTree

func _init() -> void:
	for e in ClassDB.class_get_enum_constants("EditorContextMenuPlugin", "ContextMenuSlot", true):
		print("Slot: ", e, " = ", ClassDB.class_get_integer_constant("EditorContextMenuPlugin", e))
	quit(0)
