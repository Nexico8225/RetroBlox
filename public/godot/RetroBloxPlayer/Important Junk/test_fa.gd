@tool
extends SceneTree

func _init() -> void:
	var path = "C:/Windows/notepad.exe"
	print("File exists: ", FileAccess.file_exists(path))
	var bytes = FileAccess.get_file_as_bytes(path)
	print("Bytes length: ", bytes.size())
	quit(0)
