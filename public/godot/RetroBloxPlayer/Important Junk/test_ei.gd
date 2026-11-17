extends SceneTree

func _init() -> void:
	print("Checking EditorInterface methods...")
	# In headless without editor interface, test class info
	for m in ClassDB.class_get_method_list("EditorInterface"):
		if m["name"].find("selected") >= 0 or m["name"].find("path") >= 0:
			print(m["name"])
	quit(0)
