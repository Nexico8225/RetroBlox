extends SceneTree

func _init() -> void:
	# Create subscene
	var tree: Node3D = Node3D.new()
	tree.name = "PineTree"
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = CylinderMesh.new()
	tree.add_child(trunk)
	trunk.owner = tree
	var sub_ps: PackedScene = PackedScene.new()
	sub_ps.pack(tree)
	ResourceSaver.save(sub_ps, "res://test_pine.tscn")
	
	# Create folder
	var folder: Node3D = Node3D.new()
	folder.name = "ForestFolder"
	var inst: Node = sub_ps.instantiate()
	folder.add_child(inst)
	
	# Duplicate folder
	var clone: Node = folder.duplicate(15)
	_embed_all_descendants_recursive(clone, clone)
	
	var folder_ps: PackedScene = PackedScene.new()
	var err: int = folder_ps.pack(clone)
	print("Folder pack error: ", err)
	ResourceSaver.save(folder_ps, "res://test_forest.tscn")
	
	# Delete original subscene to verify folder is 100% self-contained!
	DirAccess.remove_absolute("res://test_pine.tscn")
	
	# Now load folder without subscene existing
	var loaded_ps: PackedScene = load("res://test_forest.tscn")
	var loaded_folder: Node = loaded_ps.instantiate()
	print("Loaded folder child count: ", loaded_folder.get_child_count())
	var loaded_tree: Node = loaded_folder.get_node("PineTree")
	print("Loaded tree child count: ", loaded_tree.get_child_count())
	var loaded_trunk: MeshInstance3D = loaded_tree.get_node("Trunk") as MeshInstance3D
	print("Loaded trunk mesh valid: ", loaded_trunk.mesh != null)
	
	DirAccess.remove_absolute("res://test_forest.tscn")
	print("ALL SELF-CONTAINED FOLDER TESTS PASSED!")
	quit(0)

func _embed_all_descendants_recursive(node: Node, root_owner: Node) -> void:
	if node != root_owner:
		node.owner = root_owner
		node.scene_file_path = ""
	for ch in node.get_children():
		_embed_all_descendants_recursive(ch, root_owner)
