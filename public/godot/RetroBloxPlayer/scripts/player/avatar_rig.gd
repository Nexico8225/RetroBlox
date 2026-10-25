extends Node3D
## AvatarRig — the classic six-part block avatar playing the user's FBX animations.
##
## Two visual modes:
##   1) R6IK mode (default) — loads res://assets/models/retroblox_anims.fbx with its
##      AnimationPlayer (Idle, Walk, Jump, Climb, Sit).
##   2) Box mode (fallback) — a code-built classic box body if FBX is absent.
##
## The rig is EXACTLY 5 studs tall (classic R6 height).

const HEAD := 0
const TORSO := 1
const ARM_L := 2
const ARM_R := 3
const LEG_L := 4
const LEG_R := 5
const HEAD_INDEX := 0

const RIG_TSCN_PATH := "res://assets/models/retroblox_anims.tscn"
const RIG_GLB_PATH := "res://assets/models/retroblox_anims.glb"
const RIG_SCENE_PATH := "res://assets/models/retroblox_anims.fbx"
const STUD := 1.0
const RIG_HEIGHT := 5.0 * STUD
const SITE_RIG_HEIGHT := 5.0

const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const ANIM_JUMP := &"Jump"
const ANIM_CLIMB := &"Climb"
const ANIM_SIT := &"Sit"

const NOOB_HEAD := Color("f5cd30")
const NOOB_TORSO := Color("0d69ac")
const NOOB_ARMS := Color("f5cd30")
const NOOB_LEGS := Color("7ab53e")

const PART_ALIASES: Array = [
	[HEAD, ["head"]],
	[TORSO, ["torso"]],
	[ARM_L, ["left arm", "leftarm", "arm l", "l arm"]],
	[ARM_R, ["right arm", "rightarm", "arm r", "r arm"]],
	[LEG_L, ["left leg", "leftleg", "leg l", "l leg"]],
	[LEG_R, ["right leg", "rightleg", "leg r", "r leg"]],
]
const RIG_NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_"

const BOX_LEG_H := 2.0 * STUD
const BOX_TORSO := Vector3(2.0, 2.0, 1.0) * STUD
const BOX_ARM := Vector3(1.0, 2.0, 1.0) * STUD
const BOX_LEG := Vector3(1.0, 2.0, 1.0) * STUD
const BOX_HEAD := Vector3(1.15, 1.15, 1.15) * STUD

var parts: Array[MeshInstance3D] = []
var HEAD_PIVOT_Y := 0.0

var _pivots: Array[Node3D] = []
var _part_sizes: Array[Vector3] = []
var _part_aabb: Array[AABB] = []
var _mounts: Array[Node3D] = []
var _overlays: Dictionary = {}
var _nameplate: Label3D
var _face_decal: MeshInstance3D
var _tshirt_decal: MeshInstance3D
var _display_name := "Player"
var _built := false
var _using_r6ik := false
var _time := 0.0
var _applied_colors: Dictionary = {}
var _anim_player: AnimationPlayer
var _current_anim := &""
var _oof_audio: AudioStream


func _ready() -> void:
	_ensure_built(true)


func is_r6ik() -> bool:
	return _using_r6ik


func setup(p_name: String) -> void:
	_display_name = p_name
	_ensure_built(true)
	paint_noob()
	set_display_name(p_name)


func set_display_name(value: String) -> void:
	_display_name = value
	if _nameplate != null and is_instance_valid(_nameplate):
		_nameplate.text = value
		_nameplate.visible = value != ""


func paint_noob() -> void:
	set_part_color(HEAD, NOOB_HEAD)
	set_part_color(TORSO, NOOB_TORSO)
	set_part_color(ARM_L, NOOB_ARMS)
	set_part_color(ARM_R, NOOB_ARMS)
	set_part_color(LEG_L, NOOB_LEGS)
	set_part_color(LEG_R, NOOB_LEGS)


func set_part_color(index: int, color: Color) -> void:
	_ensure_built()
	if index < 0 or index >= parts.size():
		return
	_applied_colors[index] = color
	var mi := parts[index]
	if mi == null or not is_instance_valid(mi) or mi.mesh == null:
		return
	for surface in mi.mesh.get_surface_count():
		mi.set_surface_override_material(surface, null)
	mi.material_override = _make_material(color)


func set_part_textured(index: int, mesh: Mesh, tex: Texture2D) -> void:
	_ensure_built()
	if index < 0 or index >= parts.size():
		return
	var mi := parts[index]
	var material := StandardMaterial3D.new()
	material.albedo_texture = tex
	material.roughness = 0.78
	if _using_r6ik:
		if _overlays.has(index) and is_instance_valid(_overlays[index]):
			_overlays[index].queue_free()
		var overlay := MeshInstance3D.new()
		overlay.name = "ClothingOverlay_%d" % index
		overlay.mesh = mesh
		overlay.material_override = material
		_mounts[index].add_child(overlay)
		overlay.scale = Vector3.ONE * 1.02
		_overlays[index] = overlay
	else:
		mi.mesh = mesh
		mi.material_override = material


func set_face(tex: Texture2D, face_scale: float) -> void:
	_ensure_built()
	if tex == null:
		return
	if _face_decal != null and is_instance_valid(_face_decal):
		_face_decal.queue_free()
		_face_decal = null
	var head_size := _part_sizes[HEAD_INDEX] if _part_sizes.size() > HEAD_INDEX else Vector3.ONE * STUD
	var w: float = head_size.x * 0.62 * clampf(face_scale, 0.5, 2.0)
	var quad := MeshInstance3D.new()
	quad.name = "FaceDecal"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(w, w)
	quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = tex
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = material
	var host: Node3D = _mounts[HEAD_INDEX] if _mounts.size() > HEAD_INDEX else self
	host.add_child(quad)
	quad.position = Vector3(0.0, head_size.y * 0.04, -head_size.z * 0.5 - 0.015)
	quad.rotation = Vector3(0.0, PI, 0.0)
	_face_decal = quad


func set_tshirt(tex: Texture2D) -> void:
	_ensure_built()
	if tex == null:
		return
	if _tshirt_decal != null and is_instance_valid(_tshirt_decal):
		_tshirt_decal.queue_free()
		_tshirt_decal = null
	var torso_size := _part_sizes[TORSO] if _part_sizes.size() > TORSO else BOX_TORSO
	var quad := MeshInstance3D.new()
	quad.name = "TshirtDecal"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(torso_size.x * 0.92, torso_size.y * 0.92)
	quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = tex
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = material
	var host: Node3D = _mounts[TORSO] if _mounts.size() > TORSO else self
	host.add_child(quad)
	quad.position = Vector3(0.0, 0.0, -torso_size.z * 0.5 - 0.015)
	quad.rotation = Vector3(0.0, PI, 0.0)
	_tshirt_decal = quad


func animate(delta: float, speed: float, grounded: bool, climbing: bool = false) -> void:
	_ensure_built()
	_time += delta
	if _using_r6ik and _anim_player != null and is_instance_valid(_anim_player):
		_animate_r6ik(speed, grounded, climbing)
		return
	_animate_boxes(delta, speed, grounded, climbing)


func _animate_r6ik(speed: float, grounded: bool, climbing: bool) -> void:
	var next: StringName = ANIM_IDLE
	var rate := 1.0
	if climbing:
		next = ANIM_CLIMB
		if speed < 0.2:
			rate = 0.0
		else:
			rate = clampf(speed / (8.0 * STUD), 0.6, 1.4)
	elif not grounded:
		next = ANIM_JUMP
		rate = 1.0
	elif speed > 0.8 * STUD:
		next = ANIM_WALK
		rate = clampf(speed / (16.0 * STUD), 0.6, 1.4)
	if _current_anim != next:
		_current_anim = next
		if _anim_player.has_animation(next):
			var blend := 0.0 if (next == ANIM_JUMP or _current_anim == ANIM_JUMP) else 0.14
			_anim_player.play(next, blend, rate)
	if next == ANIM_WALK or next == ANIM_CLIMB:
		_anim_player.speed_scale = rate


func on_jump() -> void:
	if _using_r6ik and _anim_player != null and is_instance_valid(_anim_player):
		_current_anim = ANIM_JUMP
		if _anim_player.has_animation(ANIM_JUMP):
			_anim_player.play(ANIM_JUMP, 0.0, 1.0)


static func _ensure_classic_climb_anim(ap: AnimationPlayer) -> void:
	var anim := Animation.new()
	anim.length = 0.8
	anim.loop_mode = Animation.LOOP_LINEAR

	var t_la := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t_la, "Left Arm")
	var t_ra := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t_ra, "Right Arm")
	var t_ll := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t_ll, "Left Leg")
	var t_rl := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t_rl, "Right Leg")

	var steps := 8
	for i in range(steps + 1):
		var time := float(i) * (anim.length / float(steps))
		var phase := float(i) / float(steps) * TAU
		var alt := sin(phase)

		var pitch_l := deg_to_rad(90.0 - 135.0 + alt * 25.0)
		var pitch_r := deg_to_rad(90.0 - 135.0 - alt * 25.0)
		var q_la := Quaternion(Vector3.RIGHT, pitch_l)
		var q_ra := Quaternion(Vector3.RIGHT, pitch_r)

		var pitch_ll := deg_to_rad(90.0 + alt * 28.0)
		var pitch_rl := deg_to_rad(90.0 - alt * 28.0)
		var q_ll := Quaternion(Vector3.RIGHT, pitch_ll)
		var q_rl := Quaternion(Vector3.RIGHT, pitch_rl)

		anim.rotation_track_insert_key(t_la, time, q_la)
		anim.rotation_track_insert_key(t_ra, time, q_ra)
		anim.rotation_track_insert_key(t_ll, time, q_ll)
		anim.rotation_track_insert_key(t_rl, time, q_rl)

	var lib: AnimationLibrary = ap.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)
	if lib.has_animation(ANIM_CLIMB):
		lib.remove_animation(ANIM_CLIMB)
	lib.add_animation(ANIM_CLIMB, anim)


func play_emote(clip: String) -> void:
	_ensure_built()
	if not _using_r6ik or _anim_player == null or not is_instance_valid(_anim_player):
		return
	if clip == "":
		_current_anim = &""
		return
	var anim_name := StringName(clip)
	if _anim_player.has_animation(anim_name):
		_current_anim = &"emote_" + anim_name
		_anim_player.play(anim_name, 0.2)


func _animate_boxes(_delta: float, speed: float, grounded: bool, climbing: bool) -> void:
	if _pivots.size() < 6:
		return
	var movement := clampf(absf(speed) / (5.0 * STUD), 0.0, 1.0)
	var walk_rate := 4.8 + movement * 2.0
	var swing := sin(_time * walk_rate) * movement
	if climbing:
		var alt := sin(_time * 6.5) * 0.9
		_pivots[ARM_L].rotation.x = -2.4 + alt * 0.4
		_pivots[ARM_R].rotation.x = -2.4 - alt * 0.4
		_pivots[LEG_L].rotation.x = alt * 0.5
		_pivots[LEG_R].rotation.x = -alt * 0.5
		return
	if grounded:
		_pivots[ARM_L].rotation.x = swing * 0.7
		_pivots[ARM_R].rotation.x = -swing * 0.7
		_pivots[LEG_L].rotation.x = -swing * 0.66
		_pivots[LEG_R].rotation.x = swing * 0.66
		_pivots[ARM_L].rotation.z = sin(_time * 2.1) * 0.025 * (1.0 - movement)
		_pivots[ARM_R].rotation.z = -sin(_time * 2.1) * 0.025 * (1.0 - movement)
		_pivots[HEAD].rotation.x = sin(_time * 1.8) * 0.025
		_pivots[TORSO].rotation.x = sin(_time * 1.8 + 0.5) * 0.012
	else:
		_pivots[ARM_L].rotation.x = -2.6
		_pivots[ARM_R].rotation.x = -2.6
		_pivots[ARM_L].rotation.z = 0.0
		_pivots[ARM_R].rotation.z = 0.0
		_pivots[LEG_L].rotation.x = 0.35
		_pivots[LEG_R].rotation.x = -0.35
		_pivots[HEAD].rotation.x = 0.0
		_pivots[TORSO].rotation.x = 0.0


func burst(world: Node3D, impulse_seed: int) -> void:
	_ensure_built()
	if world == null:
		return
	visible = false
	var debris := Node3D.new()
	debris.name = "AvatarBreakup"
	world.add_child(debris)
	debris.global_position = global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(impulse_seed) * 104729 + 13
	for i in range(parts.size()):
		var piece := _make_debris_piece(debris, i)
		piece.linear_velocity = Vector3(
			rng.randf_range(-4.8, 4.8), rng.randf_range(4.0, 7.5), rng.randf_range(-4.8, 4.8)) * STUD
		piece.angular_velocity = Vector3(
			rng.randf_range(-5.5, 5.5), rng.randf_range(-5.5, 5.5), rng.randf_range(-5.5, 5.5))
	var audio := AudioStreamPlayer3D.new()
	audio.name = "OriginalOof"
	audio.stream = _get_oof_audio()
	audio.max_distance = 40.0 * STUD
	audio.unit_size = 10.0 * STUD
	debris.add_child(audio)
	audio.play()
	var cleanup := world.get_tree().create_timer(5.0)
	cleanup.timeout.connect(debris.queue_free)


func _get_oof_audio() -> AudioStream:
	if _oof_audio == null:
		if ResourceLoader.exists("res://assets/rbx_uuhhh.mp3"):
			_oof_audio = load("res://assets/rbx_uuhhh.mp3")
		else:
			_oof_audio = load("res://assets/oof.wav")
	return _oof_audio


func _ensure_built(allow_upgrade: bool = false) -> void:
	if _built:
		if allow_upgrade and not _using_r6ik:
			_try_r6ik()
		return
	_built = true
	if _try_r6ik():
		return
	_build_boxes()


func _try_r6ik() -> bool:
	var path_to_load := ""
	if ResourceLoader.exists(RIG_TSCN_PATH):
		path_to_load = RIG_TSCN_PATH
	elif ResourceLoader.exists(RIG_GLB_PATH):
		path_to_load = RIG_GLB_PATH
	elif ResourceLoader.exists(RIG_SCENE_PATH):
		path_to_load = RIG_SCENE_PATH
	if path_to_load == "":
		return false
	var packed: PackedScene = load(path_to_load)
	if packed == null:
		return false
	var inst: Node3D = packed.instantiate()
	if inst == null:
		return false
	var found: Dictionary = {}
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var index := _match_part_name(mi.name, mi.mesh.resource_name)
		if index >= 0:
			found[index] = mi
		else:
			mi.visible = false
	if found.size() < 6:
		inst.free()
		return false
	_using_r6ik = true

	for node in inst.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		ap.autoplay = ""
		ap.stop()
		for clip in [ANIM_IDLE, ANIM_WALK, ANIM_CLIMB, ANIM_SIT]:
			var looped := ap.get_animation(clip)
			if looped != null:
				looped.loop_mode = Animation.LOOP_LINEAR
		var jump_anim := ap.get_animation(ANIM_JUMP)
		if jump_anim != null:
			jump_anim.loop_mode = Animation.LOOP_NONE
		_ensure_classic_climb_anim(ap)
		_anim_player = ap

	var raw_bounds := AABB()
	var have_bounds := false
	var part_boxes: Dictionary = {}
	for index in found:
		var mi: MeshInstance3D = found[index]
		var chain := _chain_transform(mi, inst)
		var box := _vertex_aabb(mi.mesh, chain)
		part_boxes[index] = box
		raw_bounds = box if not have_bounds else raw_bounds.merge(box)
		have_bounds = true
	var fit := RIG_HEIGHT / maxf(raw_bounds.size.y, 0.0001)
	var raw_center := raw_bounds.get_center()
	var model := Node3D.new()
	model.name = "R6IKModel"
	model.scale = Vector3.ONE * fit
	model.position = Vector3(-raw_center.x * fit, -raw_bounds.position.y * fit, -raw_center.z * fit)
	model.add_child(inst)
	add_child(model)

	parts.clear()
	_pivots.clear()
	_part_sizes.clear()
	_part_aabb.clear()
	_mounts.clear()
	for i in range(6):
		var mi: MeshInstance3D = found[i]
		var box: AABB = model.transform * part_boxes[i]
		parts.append(mi)
		_part_sizes.append(box.size)
		_part_aabb.append(box)
		var mount := Node3D.new()
		mount.name = "Mount_%d" % i
		mi.add_child(mount)
		var world_center := to_global(box.get_center())
		mount.transform = mi.global_transform.affine_inverse() * Transform3D(global_transform.basis, world_center)
		_mounts.append(mount)
		if i == HEAD_INDEX:
			HEAD_PIVOT_Y = box.get_center().y
	for i in range(6):
		_pivots.append(null)

	_nameplate = _make_nameplate()
	_nameplate.position = Vector3(0.0, RIG_HEIGHT + 0.9 * STUD, 0.0)
	add_child(_nameplate)
	_nameplate.text = _display_name

	for index in _applied_colors:
		if index >= 0 and index < parts.size():
			parts[index].material_override = _make_material(_applied_colors[index])
	return true


func _build_boxes() -> void:
	parts.clear()
	_pivots.clear()
	_part_sizes.clear()
	_part_aabb.clear()
	_mounts.clear()
	if _face_decal != null and is_instance_valid(_face_decal):
		_face_decal = null

	var limb_defs: Array = [
		[HEAD, Vector3(0, 4.0 + 1.15 * 0.5 - 0.05, 0) * STUD, BOX_HEAD, null],
		[TORSO, Vector3(0, 3.0, 0) * STUD, BOX_TORSO, null],
		[ARM_L, Vector3(-1.5, 3.0, 0) * STUD, BOX_ARM, Vector3(-1.5, 4.0, 0) * STUD],
		[ARM_R, Vector3(1.5, 3.0, 0) * STUD, BOX_ARM, Vector3(1.5, 4.0, 0) * STUD],
		[LEG_L, Vector3(-0.5, 1.0, 0) * STUD, BOX_LEG, Vector3(-0.5, 2.0, 0) * STUD],
		[LEG_R, Vector3(0.5, 1.0, 0) * STUD, BOX_LEG, Vector3(0.5, 2.0, 0) * STUD],
	]

	for def in limb_defs:
		var index: int = def[0]
		var center_pos: Vector3 = def[1]
		var size: Vector3 = def[2]
		var pivot_pos = def[3]

		var mi := MeshInstance3D.new()
		mi.name = "Part_%d" % index
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mi.mesh = box_mesh
		parts.append(mi)
		_part_sizes.append(size)
		_part_aabb.append(AABB(center_pos - size * 0.5, size))

		var mount := Node3D.new()
		mount.name = "Mount_%d" % index
		_mounts.append(mount)

		if pivot_pos != null:
			var p := Node3D.new()
			p.name = "Pivot_%d" % index
			p.position = pivot_pos
			add_child(p)
			_pivots.append(p)
			p.add_child(mi)
			mi.position = center_pos - pivot_pos
			mi.add_child(mount)
			mount.position = Vector3.ZERO
		else:
			add_child(mi)
			mi.position = center_pos
			_pivots.append(mi)
			mi.add_child(mount)
			mount.position = Vector3.ZERO

	HEAD_PIVOT_Y = (4.0 + 1.15 * 0.5 - 0.05) * STUD

	_nameplate = _make_nameplate()
	_nameplate.position = Vector3(0.0, RIG_HEIGHT + 0.9 * STUD, 0.0)
	add_child(_nameplate)
	_nameplate.text = _display_name

	for index in _applied_colors:
		if index >= 0 and index < parts.size():
			parts[index].material_override = _make_material(_applied_colors[index])


func _make_nameplate() -> Label3D:
	var l := Label3D.new()
	l.name = "Nameplate"
	l.pixel_size = 0.0055
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 38
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = Color.WHITE
	return l


func _make_debris_piece(debris: Node3D, index: int) -> RigidBody3D:
	var source: MeshInstance3D = parts[index]
	var piece := RigidBody3D.new()
	piece.name = "BrokenPart_%d" % index
	piece.collision_layer = 2
	piece.collision_mask = 3
	piece.mass = 0.7
	piece.linear_damp = 0.35
	piece.angular_damp = 0.45
	debris.add_child(piece)
	piece.global_transform = source.global_transform
	var mesh_copy := MeshInstance3D.new()
	mesh_copy.name = "Mesh"
	mesh_copy.mesh = source.mesh
	mesh_copy.material_override = source.material_override
	for surface: int in range(source.mesh.get_surface_count()):
		var override := source.get_surface_override_material(surface)
		if override != null:
			mesh_copy.set_surface_override_material(surface, override)
	piece.add_child(mesh_copy)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _part_sizes[index] if _part_sizes.size() > index else Vector3.ONE * STUD
	collision.shape = shape
	piece.add_child(collision)
	return piece


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	return material


func _chain_transform(node: Node, top: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != top:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _vertex_aabb(mesh: Mesh, xform: Transform3D) -> AABB:
	var faces := mesh.get_faces()
	var box := AABB()
	var first := true
	for vertex in faces:
		var world := xform * vertex
		if first:
			box = AABB(world, Vector3.ZERO)
			first = false
		else:
			box = box.expand(world)
	return box


func _match_part_name(node_name: String, mesh_name: String) -> int:
	for source in [node_name, mesh_name]:
		var norm := _norm_part_name(source)
		if norm.is_empty():
			continue
		for entry in PART_ALIASES:
			for alias in entry[1]:
				if norm == alias or norm.begins_with(alias):
					return int(entry[0])
	return -1


func _norm_part_name(raw: String) -> String:
	var s := raw.to_lower()
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "$":
			i += 1
			while i < s.length() and RIG_NAME_CHARS.contains(s[i]):
				i += 1
		else:
			out += s[i]
			i += 1
	out = out.replace("_", " ").replace(".", " ").replace("-", " ")
	var keep: Array[String] = []
	for token in out.split(" ", false):
		var clean := ""
		for ch in token:
			if RIG_NAME_CHARS.contains(ch):
				clean += ch
		if not clean.is_empty():
			keep.append(clean)
	return " ".join(keep)
