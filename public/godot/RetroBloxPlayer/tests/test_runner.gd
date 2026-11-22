extends SceneTree

func _init() -> void:
	print("Testing load of test_cmp_load.gd...")
	var s: Script = load("res://test_cmp_load.gd")
	if s == null:
		print("FAILED to load script with EditorContextMenuPlugin")
	else:
		print("SUCCESS: Loaded script with EditorContextMenuPlugin: ", s)
	DirAccess.remove_absolute("res://test_cmp_load.gd")
	quit(0)
