class_name AvatarRagdoll
extends Node3D

## R6 Avatar Physics Ragdoll
## Replaces or complements break-apart burst with a continuous, articulated physical ragdoll.
## Supports:
## - Full R6 6-part skeleton connected via 3D physics joints (ConeTwistJoint3D).
## - Proper collision layers and non-colliding joint pairs.
## - Transfer of avatar skin colors, shirts, pants, faces, and UGC accessories.
## - Inherited momentum and impulse forces (push, throw, explosion, fling).
## - Torso tracking for camera follow and get-up recovery.

signal recovered

const STUD := 1.0

const HEAD := 0
const TORSO := 1
const ARM_L := 2
const ARM_R := 3
const LEG_L := 4
const LEG_R := 5

const PART_MASSES: Array[float] = [0.65, 1.9, 0.45, 0.45, 0.65, 0.65]

var torso: RigidBody3D = null
var parts: Array[RigidBody3D] = []
var joints: Array[Joint3D] = []

var is_dead := false
var time_alive := 0.0
var get_up_ready := false
const MIN_RAGDOLL_TIME := 1.1


func _ready() -> void:
	parts.resize(6)


func _physics_process(delta: float) -> void:
	time_alive += delta
	if time_alive >= MIN_RAGDOLL_TIME:
		get_up_ready = true


func get_torso_position() -> Vector3:
	if torso != null and is_instance_valid(torso):
		return torso.global_position
	return global_position


func get_torso_velocity() -> Vector3:
	if torso != null and is_instance_valid(torso):
		return torso.linear_velocity
	return Vector3.ZERO


func apply_torso_impulse(imp: Vector3) -> void:
	if torso != null and is_instance_valid(torso):
		torso.apply_central_impulse(imp)
		torso.apply_torque_impulse(Vector3(randf_range(-imp.z, imp.z), randf_range(-imp.x, imp.x), randf_range(-imp.y, imp.y)) * 0.25)


func is_settled() -> bool:
	if torso == null or not is_instance_valid(torso):
		return true
	return torso.linear_velocity.length() < 1.2 and torso.angular_velocity.length() < 1.5


static func spawn(avatar_node: Node3D, world: Node3D, init_vel: Vector3 = Vector3.ZERO, impulse: Vector3 = Vector3.ZERO, dead := false) -> AvatarRagdoll:
	if avatar_node == null or world == null:
		return null

	var ragdoll := AvatarRagdoll.new()
	ragdoll.name = "AvatarRagdoll"
	ragdoll.is_dead = dead
	world.add_child(ragdoll)
	ragdoll.global_position = avatar_node.global_position

	var src_parts: Array = avatar_node.get("parts") if "parts" in avatar_node else []
	var part_sizes: Array = avatar_node.get("_part_sizes") if "_part_sizes" in avatar_node else []
	var mounts: Array = avatar_node.get("_mounts") if "_mounts" in avatar_node else []

	var pmat := PhysicsMaterial.new()
	pmat.friction = 0.92
	pmat.bounce = 0.04

	var total_initial_vel := init_vel + impulse

	# 1. Create the 6 rigid bodies
	for i in range(6):
		var body := RigidBody3D.new()
		body.name = ["Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg"][i]
		body.collision_layer = 2
		body.collision_mask = 1
		body.mass = PART_MASSES[i]
		body.linear_damp = 0.55
		body.angular_damp = 1.15
		body.can_sleep = false
		body.continuous_cd = (i == TORSO or i == HEAD)
		body.physics_material_override = pmat

		ragdoll.add_child(body)
		ragdoll.parts[i] = body

		# Match position/orientation
		if i < mounts.size() and is_instance_valid(mounts[i]):
			body.global_transform = (mounts[i] as Node3D).global_transform
		else:
			body.global_position = avatar_node.global_position + Vector3(0.0, 2.5 * STUD, 0.0)

		# Initial velocity & slight tumble
		body.linear_velocity = total_initial_vel
		if i == TORSO:
			ragdoll.torso = body
			body.angular_velocity = Vector3(
				randf_range(-3.5, 3.5),
				randf_range(-2.5, 2.5),
				randf_range(-3.5, 3.5)
			)
		else:
			body.angular_velocity = Vector3(
				randf_range(-2.0, 2.0),
				randf_range(-2.0, 2.0),
				randf_range(-2.0, 2.0)
			)

		# Visual mesh
		if i < src_parts.size() and src_parts[i] is MeshInstance3D:
			var src_mi: MeshInstance3D = src_parts[i]
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = src_mi.mesh
			mi.material_override = src_mi.material_override
			for s in range(src_mi.mesh.get_surface_count()):
				var ov := src_mi.get_surface_override_material(s)
				if ov != null:
					mi.set_surface_override_material(s, ov)
			body.add_child(mi)

		# Collision Shape
		var col := CollisionShape3D.new()
		col.name = "Collision"
		var size_vec := Vector3(1.0, 2.0, 1.0) * STUD
		if i < part_sizes.size() and part_sizes[i] is Vector3:
			size_vec = part_sizes[i]

		if i == HEAD:
			var sph := SphereShape3D.new()
			sph.radius = (size_vec.x * 0.5) * 0.96
			col.shape = sph
		else:
			var bshape := BoxShape3D.new()
			# Slightly inset collision boxes to avoid snagging against adjacent limbs
			bshape.size = size_vec * 0.95
			col.shape = bshape
		body.add_child(col)

		# Copy overlays (e.g. FaceDecal, T-Shirt)
		if i < mounts.size() and is_instance_valid(mounts[i]):
			for child in (mounts[i] as Node).get_children():
				if child is MeshInstance3D:
					var overlay_dup: MeshInstance3D = child.duplicate()
					body.add_child(overlay_dup)

	# Copy UGC accessories (hats, gears, hair)
	for child in avatar_node.get_children():
		if String(child.name).begins_with("UGCYaw_"):
			var ugc_copy: Node = child.duplicate()
			if ragdoll.parts[HEAD] != null:
				ragdoll.parts[HEAD].add_child(ugc_copy)

	# 2. Add collision exceptions so adjacent connected limbs do not fight
	var torso_body := ragdoll.parts[TORSO]
	if torso_body != null:
		for limb_idx in [HEAD, ARM_L, ARM_R, LEG_L, LEG_R]:
			var limb_body := ragdoll.parts[limb_idx]
			if limb_body != null:
				torso_body.add_collision_exception_with(limb_body)
				limb_body.add_collision_exception_with(torso_body)

	if ragdoll.parts[LEG_L] != null and ragdoll.parts[LEG_R] != null:
		ragdoll.parts[LEG_L].add_collision_exception_with(ragdoll.parts[LEG_R])
		ragdoll.parts[LEG_R].add_collision_exception_with(ragdoll.parts[LEG_L])

	# 3. Connect physics joints
	if torso_body != null:
		var neck_pos := _get_pivot_pos(avatar_node, HEAD, torso_body.global_position + Vector3(0.0, 1.0 * STUD, 0.0))
		_build_joint(ragdoll, "NeckJoint", torso_body, ragdoll.parts[HEAD], neck_pos, 35.0, 30.0)

		var arm_l_pos := _get_pivot_pos(avatar_node, ARM_L, torso_body.global_position + Vector3(-1.5 * STUD, 0.5 * STUD, 0.0))
		_build_joint(ragdoll, "ArmLJoint", torso_body, ragdoll.parts[ARM_L], arm_l_pos, 85.0, 45.0)

		var arm_r_pos := _get_pivot_pos(avatar_node, ARM_R, torso_body.global_position + Vector3(1.5 * STUD, 0.5 * STUD, 0.0))
		_build_joint(ragdoll, "ArmRJoint", torso_body, ragdoll.parts[ARM_R], arm_r_pos, 85.0, 45.0)

		var leg_l_pos := _get_pivot_pos(avatar_node, LEG_L, torso_body.global_position + Vector3(-0.5 * STUD, -1.0 * STUD, 0.0))
		_build_joint(ragdoll, "LegLJoint", torso_body, ragdoll.parts[LEG_L], leg_l_pos, 70.0, 35.0)

		var leg_r_pos := _get_pivot_pos(avatar_node, LEG_R, torso_body.global_position + Vector3(0.5 * STUD, -1.0 * STUD, 0.0))
		_build_joint(ragdoll, "LegRJoint", torso_body, ragdoll.parts[LEG_R], leg_r_pos, 70.0, 35.0)

	# 4. If dead, play oof sound and set cleanup timer
	if dead:
		var audio := AudioStreamPlayer3D.new()
		audio.name = "RagdollOof"
		if avatar_node.has_method("_get_oof_audio"):
			audio.stream = avatar_node.call("_get_oof_audio")
		audio.max_distance = 45.0 * STUD
		audio.unit_size = 10.0 * STUD
		ragdoll.add_child(audio)
		audio.play()

		var tree := ragdoll.get_tree()
		if tree != null:
			var cleanup := tree.create_timer(7.5)
			cleanup.timeout.connect(ragdoll._safe_cleanup)

	return ragdoll


func _safe_cleanup() -> void:
	if is_instance_valid(self):
		queue_free()


static func _get_pivot_pos(avatar_node: Node3D, index: int, fallback: Vector3) -> Vector3:
	if avatar_node.has_method("get_part_pivot"):
		var p: Node3D = avatar_node.call("get_part_pivot", index)
		if p != null and is_instance_valid(p):
			return p.global_position
	return fallback


static func _build_joint(parent: Node3D, j_name: String, node_a: RigidBody3D, node_b: RigidBody3D, pivot_pos: Vector3, swing_deg: float, twist_deg: float) -> ConeTwistJoint3D:
	if node_a == null or node_b == null:
		return null
	var joint := ConeTwistJoint3D.new()
	joint.name = j_name
	parent.add_child(joint)
	joint.global_position = pivot_pos
	joint.node_a = node_a.get_path()
	joint.node_b = node_b.get_path()
	joint.swing_span = deg_to_rad(swing_deg)
	joint.twist_span = deg_to_rad(twist_deg)
	joint.softness = 0.5
	joint.bias = 0.3
	parent.joints.append(joint)
	return joint
