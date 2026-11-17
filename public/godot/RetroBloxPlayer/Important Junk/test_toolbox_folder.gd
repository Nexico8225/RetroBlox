extends SceneTree

func _init() -> void:
	print("Running full Toolbox Folder Publish & Insert verification...")
	
	# Create a mock scene root
	var scene_root: Node3D = Node3D.new()
	scene_root.name = "TestWorld"
	root.add_child(scene_root)
	
	# Create a Folder node with children
	var folder: Node3D = Node3D.new()
	folder.name = "MyVillageFolder"
	folder.set_meta("retroblox_folder", true)
	scene_root.add_child(folder)
	folder.owner = scene_root
	
	# Add child 1: House
	var house: Node3D = Node3D.new()
	house.name = "House"
	folder.add_child(house)
	house.owner = scene_root
	var wall: MeshInstance3D = MeshInstance3D.new()
	wall.name = "Wall"
	wall.mesh = BoxMesh.new()
	house.add_child(wall)
	wall.owner = scene_root
	
	# Add child 2: Tree
	var tree_node: Node3D = Node3D.new()
	tree_node.name = "PineTree"
	folder.add_child(tree_node)
	tree_node.owner = scene_root
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = CylinderMesh.new()
	tree_node.add_child(trunk)
	trunk.owner = scene_root
	
	print("Folder prepared with %d children" % folder.get_child_count())
	
	# Instantiate Toolbox dock
	var tb_scr = load("res://addons/retroblox_studio/toolbox_dock.gd")
	var tb = tb_scr.new()
	scene_root.add_child(tb)
	tb._ready()
	
	# Test picking folder
	tb._pub_scene_nodes.clear()
	tb._pub_scene_nodes.append(folder)
	tb._pub_node_picker.add_item("MyVillageFolder")
	tb._pub_node_picker.selected = 0
	tb._on_publish_node_picked(0)
	print("Category selected: ", tb._pub_cat_option.get_item_text(tb._pub_cat_option.selected))
	print("Description: ", tb._pub_desc_input.text)
	print("Tags: ", tb._pub_tags_input.text)
	
	assert(tb._pub_cat_option.get_item_text(tb._pub_cat_option.selected) == "Folders", "Category should be Folders")
	
	# Test confirm publish
	tb._confirm_publish_selected()
	print("Catalog items count: ", tb._catalog_items.size())
	var published_item = tb._catalog_items[0]
	print("Published item name: ", published_item["name"])
	print("Published item category: ", published_item["category"])
	print("Published item type: ", published_item["type"])
	print("Published item path: ", published_item["path"])
	print("Published item thumb_kind: ", published_item.get("thumb_kind", ""))
	
	assert(published_item["category"] == "Folders", "Catalog category should be Folders")
	assert(published_item["type"] == "folder", "Catalog type should be folder")
	assert(FileAccess.file_exists(published_item["path"]), "Published file must exist on disk: " + published_item["path"])
	
	# Test inserting published folder back into scene
	var loaded_folder_ps: PackedScene = load(published_item["path"])
	var inst: Node = loaded_folder_ps.instantiate()
	print("Instantiated folder child count: ", inst.get_child_count())
	assert(inst.get_child_count() == 2, "Folder must contain 2 children (House and PineTree)")
	assert(inst.get_node_or_null("House") != null, "House must exist in folder")
	assert(inst.get_node_or_null("PineTree") != null, "PineTree must exist in folder")
	print("House child count: ", inst.get_node("House").get_child_count())
	assert(inst.get_node("House").get_node_or_null("Wall") != null, "Wall must exist inside House")
	print("PineTree child count: ", inst.get_node("PineTree").get_child_count())
	assert(inst.get_node("PineTree").get_node_or_null("Trunk") != null, "Trunk must exist inside PineTree")
	
	# Clean up test published file
	DirAccess.remove_absolute(published_item["path"])
	var up = published_item["user_path"]
	if FileAccess.file_exists(up):
		DirAccess.remove_absolute(up)
	
	print("ALL TOOLBOX FOLDER PUBLISH & INSERT TESTS PASSED!")
	quit(0)
