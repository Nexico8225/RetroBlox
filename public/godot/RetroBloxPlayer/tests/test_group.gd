extends SceneTree

func _init() -> void:
	print("Testing _on_create_or_group_folder...")
	var scene_root: Node3D = Node3D.new()
	scene_root.name = "Root"
	root.add_child(scene_root)
	
	var part1: Node3D = Node3D.new()
	part1.name = "Part1"
	scene_root.add_child(part1)
	part1.owner = scene_root
	
	var part2: Node3D = Node3D.new()
	part2.name = "Part2"
	scene_root.add_child(part2)
	part2.owner = scene_root
	
	# Simulate plugin grouping
	var folder: Node3D = Node3D.new()
	folder.name = "Folder"
	folder.set_meta("retroblox_folder", true)
	scene_root.add_child(folder, true)
	folder.owner = scene_root
	
	part1.reparent(folder, true)
	part1.owner = scene_root
	part2.reparent(folder, true)
	part2.owner = scene_root
	
	print("Folder child count: ", folder.get_child_count())
	assert(folder.get_child_count() == 2, "Folder must contain 2 parts")
	assert(folder.get_node_or_null("Part1") != null, "Part1 inside folder")
	assert(folder.get_node_or_null("Part2") != null, "Part2 inside folder")
	print("Group into folder logic verified!")
	quit(0)
