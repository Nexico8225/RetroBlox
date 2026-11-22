# res://scripts/apple_worm/worm_character.gd
class_name WormCharacter
extends Node3D

var segment_nodes: Array[Node3D] = []
var head_node: Node3D
var eye_left: MeshInstance3D
var eye_right: MeshInstance3D
var mouth_mesh: MeshInstance3D

var worm_mat: StandardMaterial3D
var eye_white_mat: StandardMaterial3D
var eye_pupil_mat: StandardMaterial3D
var mouth_mat: StandardMaterial3D

func _init() -> void:
	worm_mat = StandardMaterial3D.new()
	worm_mat.albedo_color = Color(0.18, 0.78, 0.38) # Vibrant emerald green
	worm_mat.roughness = 0.35

	eye_white_mat = StandardMaterial3D.new()
	eye_white_mat.albedo_color = Color(1.0, 1.0, 1.0)
	eye_white_mat.roughness = 0.2

	eye_pupil_mat = StandardMaterial3D.new()
	eye_pupil_mat.albedo_color = Color(0.05, 0.05, 0.08)
	eye_pupil_mat.roughness = 0.1

	mouth_mat = StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(0.92, 0.28, 0.52) # Pink tongue/mouth
	mouth_mat.roughness = 0.3

func sync_segments(positions: Array[Vector2i], facing: Vector2i, animate: bool = true) -> void:
	var count = positions.size()
	
	# Adjust segment nodes count
	while segment_nodes.size() < count:
		var idx = segment_nodes.size()
		var seg = _create_segment(idx == 0)
		add_child(seg)
		segment_nodes.append(seg)
		
	while segment_nodes.size() > count:
		var last = segment_nodes.pop_back()
		if is_instance_valid(last):
			last.queue_free()

	# Position each segment
	for i in range(count):
		var target_pos = Vector3(positions[i].x, positions[i].y, 0.0)
		var node = segment_nodes[i]
		if not animate:
			node.position = target_pos
		else:
			var tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "position", target_pos, 0.09)

	# Update head orientation
	if segment_nodes.size() > 0:
		_orient_head(facing)

func _create_segment(is_head: bool) -> Node3D:
	var root = Node3D.new()
	var body = MeshInstance3D.new()
	body.name = "Body"
	
	# Rounded block for segment
	var box = BoxMesh.new()
	if is_head:
		box.size = Vector3(0.94, 0.94, 0.94)
	else:
		box.size = Vector3(0.88, 0.88, 0.88)
	body.mesh = box
	body.material_override = worm_mat
	root.add_child(body)

	if is_head:
		head_node = root
		# Eyes
		var e_left_white = MeshInstance3D.new()
		var e_left_sphere = SphereMesh.new()
		e_left_sphere.radius = 0.14
		e_left_sphere.height = 0.28
		e_left_white.mesh = e_left_sphere
		e_left_white.material_override = eye_white_mat
		e_left_white.position = Vector3(0.2, 0.22, 0.42)
		root.add_child(e_left_white)

		var e_left_pupil = MeshInstance3D.new()
		var p_sphere = SphereMesh.new()
		p_sphere.radius = 0.07
		p_sphere.height = 0.14
		e_left_pupil.mesh = p_sphere
		e_left_pupil.material_override = eye_pupil_mat
		e_left_pupil.position = Vector3(0.0, 0.0, 0.1)
		e_left_white.add_child(e_left_pupil)

		var e_right_white = MeshInstance3D.new()
		e_right_white.mesh = e_left_sphere
		e_right_white.material_override = eye_white_mat
		e_right_white.position = Vector3(-0.2, 0.22, 0.42)
		root.add_child(e_right_white)

		var e_right_pupil = MeshInstance3D.new()
		e_right_pupil.mesh = p_sphere
		e_right_pupil.material_override = eye_pupil_mat
		e_right_pupil.position = Vector3(0.0, 0.0, 0.1)
		e_right_white.add_child(e_right_pupil)

		# Cute Mouth / Tongue
		var mouth = MeshInstance3D.new()
		var mouth_box = BoxMesh.new()
		mouth_box.size = Vector3(0.28, 0.16, 0.12)
		mouth.mesh = mouth_box
		mouth.material_override = mouth_mat
		mouth.position = Vector3(0.0, -0.22, 0.44)
		root.add_child(mouth)
		mouth_mesh = mouth

	return root

func _orient_head(facing: Vector2i) -> void:
	if not head_node:
		return
	if facing == Vector2i.RIGHT:
		head_node.rotation_degrees = Vector3(0, 0, -90)
	elif facing == Vector2i.LEFT:
		head_node.rotation_degrees = Vector3(0, 0, 90)
	elif facing == Vector2i.UP:
		head_node.rotation_degrees = Vector3(0, 0, 0)
	elif facing == Vector2i.DOWN:
		head_node.rotation_degrees = Vector3(0, 0, 180)
