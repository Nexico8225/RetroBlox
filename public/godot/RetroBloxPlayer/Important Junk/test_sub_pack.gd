extends SceneTree

func _init() -> void:
	# Create a dummy subscene
	var sub_root: Node3D = Node3D.new()
	sub_root.name = "TreeSubScene"
	var leaf: MeshInstance3D = MeshInstance3D.new()
	leaf.name = "Leaves"
	sub_root.add_child(leaf)
	leaf.owner = sub_root
	var sub_ps: PackedScene = PackedScene.new()
	sub_ps.pack(sub_root)
	ResourceSaver.save(sub_ps, "res://test_sub.tscn")
	
	# Main scene with a folder containing an instance of test_sub.tscn
	var folder: Node = Node.new()
	folder.name = "FolderWithSubScene"
	var inst_tree: Node = sub_ps.instantiate()
	folder.add_child(inst_tree)
	
	# Now clone folder and pack
	var clone: Node = folder.duplicate(15)
	_assign_owner_recursive(clone, clone)
	var ps: PackedScene = PackedScene.new()
	var err: int = ps.pack(clone)
	print("Pack subscene result: ", err)
	
	DirAccess.remove_absolute("res://test_sub.tscn")
	quit(0)

func _assign_owner_recursive(node: Node, new_owner: Node) -> void:
	if node != new_owner:
		node.owner = new_owner
	for ch in node.get_children():
		_assign_owner_recursive(ch, new_owner)
