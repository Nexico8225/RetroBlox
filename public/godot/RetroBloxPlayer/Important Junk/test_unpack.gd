extends SceneTree

func _init() -> void:
	var sub: Node = Node.new()
	sub.name = "MyFolder"
	var p1: Node3D = Node3D.new()
	p1.name = "Part1"
	sub.add_child(p1)
	p1.owner = sub
	
	var ps: PackedScene = PackedScene.new()
	ps.pack(sub)
	ResourceSaver.save(ps, "res://test_inst.tscn")
	
	# Instantiate
	var root: Node = Node.new()
	root.name = "Root"
	var loaded: PackedScene = load("res://test_inst.tscn")
	var inst: Node = loaded.instantiate()
	root.add_child(inst)
	inst.owner = root
	
	print("Before clearing scene_file_path: ", inst.scene_file_path)
	inst.scene_file_path = ""
	_assign_owner_recursive(inst, root)
	print("After clearing scene_file_path: ", inst.scene_file_path)
	print("Child owner: ", inst.get_node("Part1").owner.name)
	
	DirAccess.remove_absolute("res://test_inst.tscn")
	print("DONE")
	quit(0)

func _assign_owner_recursive(node: Node, new_owner: Node) -> void:
	if node != new_owner:
		node.owner = new_owner
	for ch in node.get_children():
		_assign_owner_recursive(ch, new_owner)
