@tool
extends SceneTree

func _init() -> void:
	var fd = FileDialog.new()
	fd.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg, *.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
		"* ; All Files"
	])
	print("Filters set successfully: ", fd.filters)
	quit(0)
