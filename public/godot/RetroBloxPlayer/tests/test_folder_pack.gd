extends SceneTree

func _init() -> void:
	var folder: Node = Node.new()
	folder.name = "MyFolder"
	
	var sub1: Node3D = Node3D.new()
	sub1.name = "Prop1"
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	sub1.add_child(mi)
	folder.add_child(sub1)
	
	var sub2: Node = Node.new()
	sub2.name = "SubFolder"
	var mi2: MeshInstance3D = MeshInstance3D.new()
	mi2.name = "Mesh2"
	sub2.add_child(mi2)
	folder.add_child(sub2)
	
	# Duplicate
	var clone: Node = folder.duplicate(15)
	_assign_owner_recursive(clone, clone)
	
	var ps: PackedScene = PackedScene.new()
	var err: int = ps.pack(clone)
	print("Pack result: ", err)
	
	var inst: Node = ps.instantiate()
	print("Instantiated child count: ", inst.get_child_count())
	print("SubFolder child count: ", inst.get_node("SubFolder").get_child_count())
	print("SUCCESS")
	quit(0)

func _assign_owner_recursive(node: Node, new_owner: Node) -> void:
	if node != new_owner:
		node.owner = new_owner
	for ch in node.get_children():
		_assign_owner_recursive(ch, new_owner)
