extends SceneTree

func _init() -> void:
	print("Testing recursive FileSystem folder packager...")
	
	# Create directory structure
	var dir_base = "res://test_village"
	DirAccess.make_dir_recursive_absolute("res://test_village/props")
	
	# 1. House scene
	var house_node = Node3D.new()
	house_node.name = "House"
	var wall = MeshInstance3D.new()
	wall.name = "Wall"
	wall.mesh = BoxMesh.new()
	house_node.add_child(wall)
	wall.owner = house_node
	var hps = PackedScene.new()
	hps.pack(house_node)
	ResourceSaver.save(hps, "res://test_village/house.tscn")
	
	# 2. Prop script
	var scr_file = FileAccess.open("res://test_village/props/torch.gd", FileAccess.WRITE)
	scr_file.store_string("extends Node3D\n# Torch script\n")
	scr_file.close()
	
	# Test recursive scan & build
	var container = Node3D.new()
	container.name = "TestVillage"
	container.set_meta("retroblox_folder", true)
	
	var count = _package_fs_dir_recursive(dir_base, container)
	print("Total files packed from FileSystem folder: ", count)
	
	print("Container child count: ", container.get_child_count())
	print("House in container: ", container.get_node_or_null("House") != null)
	print("Props subfolder in container: ", container.get_node_or_null("props") != null)
	if container.get_node_or_null("props") != null:
		print("Torch in props: ", container.get_node("props").get_node_or_null("torch") != null)
	
	_embed_all(container, container)
	var final_ps = PackedScene.new()
	var err = final_ps.pack(container)
	print("Final pack error: ", err)
	ResourceSaver.save(final_ps, "res://test_village_packed.tscn")
	
	# Clean up test directories
	DirAccess.remove_absolute("res://test_village/house.tscn")
	DirAccess.remove_absolute("res://test_village/props/torch.gd")
	DirAccess.remove_absolute("res://test_village/props")
	DirAccess.remove_absolute("res://test_village")
	DirAccess.remove_absolute("res://test_village_packed.tscn")
	
	print("RECURSIVE FILESYSTEM FOLDER TEST PASSED!")
	quit(0)

func _package_fs_dir_recursive(dir_path: String, parent_node: Node) -> int:
	var total = 0
	var da = DirAccess.open(dir_path)
	if da == null:
		return 0
	da.list_dir_begin()
	var fname = da.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full_p = dir_path.path_join(fname)
			if da.current_is_dir():
				var sub_folder = Node3D.new()
				sub_folder.name = fname.validate_node_name()
				sub_folder.set_meta("retroblox_folder", true)
				parent_node.add_child(sub_folder)
				total += _package_fs_dir_recursive(full_p, sub_folder)
			else:
				var ext = fname.get_extension().to_lower()
				if ext in ["tscn", "scn"]:
					var ps = load(full_p)
					if ps is PackedScene:
						var inst = (ps as PackedScene).instantiate()
						if inst != null:
							parent_node.add_child(inst)
							total += 1
				elif ext in ["glb", "gltf", "obj"]:
					var m = load(full_p)
					if m is Mesh:
						var mi = MeshInstance3D.new()
						mi.name = fname.get_basename().validate_node_name()
						mi.mesh = m as Mesh
						parent_node.add_child(mi)
						total += 1
				elif ext == "gd":
					var s = load(full_p)
					if s is Script:
						var sn = Node3D.new()
						sn.name = fname.get_basename().validate_node_name()
						sn.set_script(s)
						parent_node.add_child(sn)
						total += 1
		fname = da.get_next()
	da.list_dir_end()
	return total

func _embed_all(node: Node, root_owner: Node) -> void:
	if node != root_owner:
		node.owner = root_owner
		node.scene_file_path = ""
	for ch in node.get_children():
		_embed_all(ch, root_owner)
