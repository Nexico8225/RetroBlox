extends SceneTree
## Dev tool: prints the structure of the rig FBX (bones, skinned meshes,
## animation tracks). Run:  godot --headless --script res://tools/inspect_rig.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://assets/models/retroblox_anims.fbx")
	if packed == null:
		print("RIG LOAD FAILED")
		quit(1)
		return
	var inst: Node = packed.instantiate()
	_dump(inst, 0)
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		print("== SKELETON ", s.name, " bones=", s.get_bone_count())
		for i in s.get_bone_count():
			print("   bone ", i, " ", s.get_bone_name(i), " parent=", s.get_bone_parent(i), " rest=", s.get_bone_rest(i).origin)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		print("== MESH ", mi.name, " skin=", mi.skin != null, " skeleton=", mi.skeleton, " aabb=", mi.get_aabb())
	for node in inst.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		for a in ap.get_animation_list():
			var anim := ap.get_animation(a)
			print("== ANIM ", a, " len=", anim.length, " loop=", anim.loop_mode, " tracks=", anim.get_track_count())
			for t in anim.get_track_count():
				print("     ", anim.track_get_type(t), " ", anim.track_get_path(t), " keys=", anim.track_get_key_count(t))
	quit(0)


func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is Node3D:
		extra = " pos=%s rot=%s scale=%s" % [(n as Node3D).position, (n as Node3D).rotation_degrees, (n as Node3D).scale]
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_dump(c, depth + 1)
