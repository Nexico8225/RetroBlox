@tool
extends EditorContextMenuPlugin
## RetroBlox Studio — FileSystem Dock Context Menu Hook
## Adds '📁 Publish Folder to RetroBlox Toolbox...' when right-clicking any folder in FileSystem.

var plugin_ref: EditorPlugin


func _popup_menu(paths: PackedStringArray) -> void:
	for p in paths:
		var gp: String = ProjectSettings.globalize_path(p)
		if DirAccess.dir_exists_absolute(gp) and not FileAccess.file_exists(gp):
			add_context_menu_item("📁 Publish Folder to RetroBlox Toolbox...", _on_item_pressed.bind(p))
			break


func _on_item_pressed(folder_path: String) -> void:
	if plugin_ref != null and plugin_ref.has_method("_on_publish_fs_folder_path"):
		plugin_ref.call("_on_publish_fs_folder_path", folder_path)
