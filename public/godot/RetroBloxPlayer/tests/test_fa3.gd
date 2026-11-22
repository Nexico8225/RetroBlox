@tool
extends SceneTree

func _init() -> void:
	var proj_p = "res://project.godot"
	print("res://project.godot exists: ", FileAccess.file_exists(proj_p))
	var glob_p = ProjectSettings.globalize_path(proj_p)
	print("glob_p: ", glob_p)
	print("FileAccess.file_exists(glob_p): ", FileAccess.file_exists(glob_p))
	var f = FileAccess.open(glob_p, FileAccess.READ)
	print("FileAccess.open(glob_p): ", f != null)
	var f_raw = FileAccess.open(glob_p.replace("\\", "/"), FileAccess.READ)
	print("FileAccess.open forward slashes: ", f_raw != null)
	quit(0)
