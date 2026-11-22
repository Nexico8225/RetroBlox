@tool
extends SceneTree

func _init() -> void:
	var path = "C:/Windows/notepad.exe"
	var f = FileAccess.open(path, FileAccess.READ)
	print("FileAccess.open with raw path: ", f != null)
	if f != null:
		var buf = f.get_buffer(16)
		print("Read bytes from open: ", buf.size())
		f.close()
	print("FileAccess.file_exists with globalize: ", FileAccess.file_exists(ProjectSettings.globalize_path(path)))
	var fa_bytes = FileAccess.get_file_as_bytes(path)
	print("get_file_as_bytes raw: ", fa_bytes.size())
	quit(0)
