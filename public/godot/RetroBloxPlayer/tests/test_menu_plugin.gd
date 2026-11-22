extends SceneTree

class TestMenuPlugin extends EditorContextMenuPlugin:
	func _popup_menu(paths: PackedStringArray) -> void:
		print("Popup menu called with paths: ", paths)
		add_context_menu_item("Publish Folder to Toolbox...", _on_clicked.bind(paths))
	
	func _on_clicked(paths: PackedStringArray) -> void:
		print("Clicked with paths: ", paths)

func _init() -> void:
	var p = TestMenuPlugin.new()
	print("Instantiated TestMenuPlugin successfully!")
	quit(0)
