extends Node3D
## AvatarRig — the classic six-part block avatar with custom procedural & editable animations.
##
## Two visual modes:
##   1) R6IK mode (default) — extracts the catalog mesh parts from retroblox_anims.tscn / .glb / .fbx
##      and mounts them onto clean, anatomically correct joint pivots (shoulders at y=3.5, hips at y=2.0).
##   2) Box mode (fallback) — builds classic R6 box parts if models are absent.
##
## Animation Modes:
##   - Procedural (default): Smooth, natural curves for Walk, Jump, Climb, Sit, and Idle with
##     tweakable variables in the Inspector (walk speed, arm swing, leg swing, etc.).
##   - AnimationPlayer / Custom: Supports drag-and-drop custom Animation resources (custom_walk_anim)
##     or editing keyframes directly in Godot's AnimationPlayer dock (targeting Pivot_0..5:rotation).

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

# Custom keyframe curves extracted from classic Roblox R6 motion
const CURVE_WALK_ARM_L: Array[float] = [0.7854, 0.7175, 0.5301, 0.2482, -0.0847, -0.4042, -0.6479, -0.7746, -0.7581, -0.6089, -0.3682, -0.0763, 0.228, 0.505, 0.7071, 0.7854]
const CURVE_WALK_ARM_R: Array[float] = [-0.7854, -0.7175, -0.5301, -0.2482, 0.0847, 0.4042, 0.6479, 0.7746, 0.7581, 0.6089, 0.3682, 0.0763, -0.228, -0.505, -0.7071, -0.7854]
const CURVE_WALK_LEG_L: Array[float] = [-0.7686, -0.7572, -0.5796, -0.2289, 0.0813, 0.2319, 0.4869, 0.7327, 0.7327, 0.4869, 0.2319, 0.0813, -0.2289, -0.5796, -0.7572, -0.7686]
const CURVE_WALK_LEG_R: Array[float] = [0.8022, 0.6183, 0.3536, 0.1353, -0.0595, -0.4291, -0.69, -0.7796, -0.7796, -0.69, -0.4291, -0.0595, 0.1353, 0.3536, 0.6183, 0.8022]

const CURVE_JUMP_ARM_L: Array[float] = [0.0, 0.0356, 0.1579, 0.4023, 0.8073, 1.337, 1.8515, 2.2625, 2.5686, 2.7295, 2.6638, 2.3225, 1.6098, 0.7477, 0.1837, 0.0]
const CURVE_JUMP_ARM_R: Array[float] = [0.0, 0.0517, 0.1992, 0.4393, 0.7903, 1.2621, 1.781, 2.242, 2.5769, 2.7212, 2.6145, 2.2962, 1.7233, 0.9259, 0.2537, 0.0]
const CURVE_JUMP_LEG_L: Array[float] = [0.0168, -0.0001, -0.0407, -0.0734, -0.114, -0.139, -0.161, -0.1632, -0.1602, -0.164, -0.1458, -0.123, -0.0841, -0.0516, -0.0094, 0.0168]
const CURVE_JUMP_LEG_R: Array[float] = [0.0168, -0.0125, -0.0754, -0.1414, -0.2003, -0.2434, -0.2614, -0.2526, -0.2526, -0.2642, -0.2434, -0.2128, -0.1572, -0.092, -0.0272, 0.0168]
const CURVE_JUMP_HEAD: Array[float] = [0.004, 0.004, 0.0072, 0.0106, 0.0147, 0.0192, 0.0237, 0.0279, 0.0313, 0.0279, 0.0237, 0.0192, 0.0147, 0.0106, 0.0072, 0.004]
const CURVE_JUMP_TORSO: Array[float] = [0.0, 0.0, -0.0034, -0.0034, -0.0071, -0.011, -0.011, -0.0141, -0.0141, -0.011, -0.0071, -0.0071, -0.0034, -0.0034, -0.0002, 0.0]

const CURVE_CLIMB_ARM_L: Array[float] = [2.2689, 2.1967, 1.8475, 1.3255, 0.7921, 0.6575, 0.8156, 1.2217, 1.6595, 2.115, 2.2814, 2.1401, 1.7208, 1.2837, 0.8612, 0.6981]
const CURVE_CLIMB_ARM_R: Array[float] = [0.6981, 0.7554, 0.9769, 1.372, 1.8581, 2.2294, 2.355, 2.1931, 1.7419, 1.114, 0.6981, 0.7169, 1.0799, 1.624, 2.0872, 2.2689]
const CURVE_CLIMB_LEG_L: Array[float] = [0.104, 0.0182, -0.1435, -0.2514, -0.2388, -0.245, -0.3482, -0.4469, -0.4018, -0.3462, -0.0024, 0.1774, 0.1248, -0.1004, -0.2504, -0.245]
const CURVE_CLIMB_LEG_R: Array[float] = [-0.245, -0.3036, -0.4317, -0.398, -0.3447, 0.0102, 0.0749, -0.1146, -0.2697, -0.2951, -0.245, -0.3043, -0.2256, -0.1122, 0.0084, 0.104]

const CURVE_SIT_ARM_L: Array[float] = [0.0, 0.0143, 0.0551, 0.2053, 0.3093, 0.4281, 0.6922, 0.8268, 0.9553, 1.1787, 1.2715, 1.3515, 1.4735, 1.516, 1.5464, 1.5708]
const CURVE_SIT_ARM_R: Array[float] = [0.0, 0.0162, 0.0619, 0.225, 0.3336, 0.454, 0.7101, 0.8362, 0.9553, 1.1637, 1.253, 1.3324, 1.46, 1.507, 1.5418, 1.5708]
const CURVE_SIT_LEG: Array[float] = [0.0168, -0.0082, -0.0123, 0.0759, 0.1673, 0.2881, 0.6656, 0.7754, 0.8807, 1.0803, 1.176, 1.268, 1.4327, 1.4997, 1.5519, 1.5876]

const CURVE_IDLE_LEG: Array[float] = [0.0168, 0.0202, 0.015, 0.006, 0.0013, -0.0034, -0.0117, -0.015, -0.0186, -0.0117, -0.0077, -0.0034, 0.006, 0.0106, 0.015, 0.0168]

@export_group("Custom Walk Animation")
## Drag-and-drop a custom Animation resource created in Godot here to replace the default walk!
@export var custom_walk_anim: Animation = null:
	set(v):
		custom_walk_anim = v
		if _anim_player != null and v != null:
			var lib := _anim_player.get_animation_library("")
			if lib != null:
				if lib.has_animation(&"CustomWalk"):
					lib.remove_animation(&"CustomWalk")
				lib.add_animation(&"CustomWalk", v)
## Force the rig to drive all motions using the AnimationPlayer instead of code curves.
@export var use_animation_player := false
## Or set a custom animation clip name (e.g. "CustomWalk", "Walk", etc.)
@export var walk_clip_name: StringName = &"Walk"

@export_group("Editable Animations")
@export var walk_arm_swing := 0.82
@export var walk_leg_swing := 0.78
@export var walk_cycle_speed := 8.5
@export var walk_torso_lean := -0.04
@export var jump_arm_angle := 2.73
@export var jump_leg_spread := 0.26
@export var climb_arm_reach := 2.35
@export var climb_swing := 0.65
@export var climb_cycle_speed := 9.0
@export var idle_breathe_speed := 1.6
@export var idle_arm_sway := 0.03

var parts: Array[MeshInstance3D] = []
var HEAD_PIVOT_Y := 4.525

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
var _walk_phase := 0.0
var _jump_phase := 0.0
var _sit_phase := 0.0
var _applied_colors: Dictionary = {}
var _applied_textures: Dictionary = {}
var _applied_face_tex: Texture2D = null
var _applied_face_scale := 1.0
var _applied_tshirt_tex: Texture2D = null
var _anim_player: AnimationPlayer
var _current_anim := &""
var _active_emote := ""
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
	for surface in range(mi.mesh.get_surface_count()):
		mi.set_surface_override_material(surface, null)
	mi.material_override = _make_material(color)


func set_part_textured(index: int, mesh: Mesh, tex: Texture2D) -> void:
	_ensure_built()
	if index < 0 or index >= parts.size():
		return
	_applied_textures[index] = [mesh, tex]
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
		overlay.position = Vector3.ZERO
		overlay.rotation = Vector3.ZERO
		overlay.scale = Vector3.ONE * 1.018
		_overlays[index] = overlay
	else:
		mi.mesh = mesh
		mi.material_override = material


func set_tshirt(tex: Texture2D) -> void:
	_ensure_built()
	if tex == null:
		return
	_applied_tshirt_tex = tex
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


func set_face(tex: Texture2D, face_scale: float) -> void:
	_ensure_built()
	if tex == null:
		return
	_applied_face_tex = tex
	_applied_face_scale = face_scale
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


func set_custom_walk(anim: Animation) -> void:
	custom_walk_anim = anim
	if _anim_player != null and anim != null:
		var lib := _anim_player.get_animation_library("")
		if lib != null:
			if lib.has_animation(&"CustomWalk"):
				lib.remove_animation(&"CustomWalk")
			lib.add_animation(&"CustomWalk", anim)


func add_custom_animation(anim_name: StringName, anim: Animation) -> void:
	if _anim_player != null and anim != null:
		var lib := _anim_player.get_animation_library("")
		if lib != null:
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
			lib.add_animation(anim_name, anim)


func _sample_curve(curve: Array[float], phase_01: float) -> float:
	if curve.is_empty():
		return 0.0
	var p := clampf(phase_01, 0.0, 1.0) * float(curve.size() - 1)
	var i0 := int(floor(p))
	var i1 := mini(i0 + 1, curve.size() - 1)
	var t := p - float(i0)
	return lerpf(curve[i0], curve[i1], t)


func animate(delta: float, speed: float, grounded: bool, climbing: bool = false) -> void:
	_ensure_built(true)
	_time += delta
	if speed > 0.8 * STUD or not grounded or climbing:
		_active_emote = ""

	var has_custom_walk: bool = custom_walk_anim != null or (_anim_player != null and _anim_player.has_animation(&"CustomWalk"))
	if use_animation_player or has_custom_walk:
		_drive_animation_player(speed, grounded, climbing)
		return

	_animate_pivots(delta, speed, grounded, climbing)


func _drive_animation_player(speed: float, grounded: bool, climbing: bool) -> void:
	var target := ANIM_IDLE
	var rate := 1.0
	if _active_emote.to_lower() == "sit":
		target = ANIM_SIT
	elif climbing:
		target = ANIM_CLIMB
		if speed < 0.25 * STUD:
			rate = 0.0
		else:
			rate = clampf(speed / (9.0 * STUD), 0.7, 1.5)
	elif not grounded:
		target = ANIM_JUMP
		rate = 1.25
	elif speed > 0.5 * STUD:
		if custom_walk_anim != null or (_anim_player != null and _anim_player.has_animation(&"CustomWalk")):
			target = &"CustomWalk"
		else:
			target = walk_clip_name
		rate = clampf(speed / (12.0 * STUD), 0.6, 1.8)

	if _current_anim != target and _anim_player != null and _anim_player.has_animation(target):
		_current_anim = target
		_anim_player.play(target, 0.12, rate)
	elif _anim_player != null and _anim_player.is_playing():
		_anim_player.speed_scale = rate


func play_emote(clip: String) -> void:
	_ensure_built(true)
	_active_emote = clip
	_sit_phase = 0.0
	if clip == "":
		_current_anim = &""
		return
	var anim_name := StringName(clip)
	_current_anim = &"emote_" + anim_name
	if _anim_player != null and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)


func on_jump() -> void:
	_jump_phase = 0.0
	if (use_animation_player or custom_walk_anim != null) and _anim_player != null and _anim_player.has_animation(ANIM_JUMP):
		_current_anim = ANIM_JUMP
		_anim_player.play(ANIM_JUMP, 0.05, 1.25)


func _animate_pivots(delta: float, speed: float, grounded: bool, climbing: bool) -> void:
	if _pivots.size() < 6:
		return
	var k := 1.0 - exp(-18.0 * delta)
	var arm_l_x := 0.0
	var arm_r_x := 0.0
	var leg_l_x := 0.0
	var leg_r_x := 0.0
	var head_x := 0.0
	var torso_x := 0.0
	var arm_l_z := 0.0
	var arm_r_z := 0.0

	if grounded and not climbing:
		_jump_phase = 0.0

	if _active_emote.to_lower() == "sit":
		_sit_phase = minf(_sit_phase + delta * 2.5, 1.0)
		arm_l_x = _sample_curve(CURVE_SIT_ARM_L, _sit_phase)
		arm_r_x = _sample_curve(CURVE_SIT_ARM_R, _sit_phase)
		leg_l_x = _sample_curve(CURVE_SIT_LEG, _sit_phase)
		leg_r_x = _sample_curve(CURVE_SIT_LEG, _sit_phase)
	elif climbing:
		var climb_moving := speed > 0.25 * STUD
		if climb_moving:
			_walk_phase = fposmod(_walk_phase + delta * clampf(speed / (9.0 * STUD), 0.75, 1.6) * (climb_cycle_speed / 6.28318), 1.0)
		var c_scale := climb_arm_reach / 2.35
		arm_l_x = _sample_curve(CURVE_CLIMB_ARM_L, _walk_phase) * c_scale
		arm_r_x = _sample_curve(CURVE_CLIMB_ARM_R, _walk_phase) * c_scale
		leg_l_x = _sample_curve(CURVE_CLIMB_LEG_L, _walk_phase)
		leg_r_x = _sample_curve(CURVE_CLIMB_LEG_R, _walk_phase)
	elif not grounded:
		# Custom Jump curve: rises smoothly to peak and holds airborne pose until landing
		_jump_phase = minf(_jump_phase + delta * 2.2, 0.60)
		var j_arm_scale := jump_arm_angle / 2.73
		var j_leg_scale := jump_leg_spread / 0.26
		arm_l_x = _sample_curve(CURVE_JUMP_ARM_L, _jump_phase) * j_arm_scale
		arm_r_x = _sample_curve(CURVE_JUMP_ARM_R, _jump_phase) * j_arm_scale
		leg_l_x = _sample_curve(CURVE_JUMP_LEG_L, _jump_phase) * j_leg_scale
		leg_r_x = _sample_curve(CURVE_JUMP_LEG_R, _jump_phase) * j_leg_scale
		head_x = _sample_curve(CURVE_JUMP_HEAD, _jump_phase)
		torso_x = _sample_curve(CURVE_JUMP_TORSO, _jump_phase)
	elif speed > 0.5 * STUD:
		var movement := clampf(speed / (16.0 * STUD), 0.15, 1.35)
		var walk_rate := (walk_cycle_speed / 6.28318) * clampf(speed / (16.0 * STUD), 0.55, 1.45)
		_walk_phase = fposmod(_walk_phase + delta * walk_rate, 1.0)
		var amp := minf(movement, 1.0)
		var a_scale := (walk_arm_swing / 0.7854) * amp
		var l_scale := (walk_leg_swing / 0.7854) * amp
		arm_l_x = _sample_curve(CURVE_WALK_ARM_L, _walk_phase) * a_scale
		arm_r_x = _sample_curve(CURVE_WALK_ARM_R, _walk_phase) * a_scale
		leg_l_x = _sample_curve(CURVE_WALK_LEG_L, _walk_phase) * l_scale
		leg_r_x = _sample_curve(CURVE_WALK_LEG_R, _walk_phase) * l_scale
		torso_x = walk_torso_lean * movement
	else:
		var idle_p := fposmod(_time * (idle_breathe_speed / 6.28318), 1.0)
		leg_l_x = _sample_curve(CURVE_IDLE_LEG, idle_p)
		leg_r_x = _sample_curve(CURVE_IDLE_LEG, idle_p)
		head_x = sin(_time * idle_breathe_speed) * 0.02
		torso_x = sin(_time * idle_breathe_speed + 0.5) * 0.01
		arm_l_z = -idle_arm_sway - absf(sin(_time * idle_breathe_speed)) * 0.025
		arm_r_z = idle_arm_sway + absf(sin(_time * idle_breathe_speed)) * 0.025

	_pivots[ARM_L].rotation.x = lerp_angle(_pivots[ARM_L].rotation.x, arm_l_x, k)
	_pivots[ARM_R].rotation.x = lerp_angle(_pivots[ARM_R].rotation.x, arm_r_x, k)
	_pivots[LEG_L].rotation.x = lerp_angle(_pivots[LEG_L].rotation.x, leg_l_x, k)
	_pivots[LEG_R].rotation.x = lerp_angle(_pivots[LEG_R].rotation.x, leg_r_x, k)
	_pivots[ARM_L].rotation.z = lerp_angle(_pivots[ARM_L].rotation.z, arm_l_z, k)
	_pivots[ARM_R].rotation.z = lerp_angle(_pivots[ARM_R].rotation.z, arm_r_z, k)
	_pivots[HEAD].rotation.x = lerp_angle(_pivots[HEAD].rotation.x, head_x, k)
	_pivots[TORSO].rotation.x = lerp_angle(_pivots[TORSO].rotation.x, torso_x, k)


func burst(world: Node3D, impulse_seed: int, is_first_person: bool = false) -> void:
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
		if is_first_person and i == HEAD:
			continue
		var piece := _make_debris_piece(debris, i)
		piece.linear_velocity = Vector3(
			rng.randf_range(-4.8, 4.8), rng.randf_range(4.0, 7.5), rng.randf_range(-4.8, 4.8)) * STUD
		piece.angular_velocity = Vector3(
			rng.randf_range(-5.5, 5.5), rng.randf_range(-5.5, 5.5), rng.randf_range(-5.5, 5.5))
	if debris.is_inside_tree():
		var audio := AudioStreamPlayer3D.new()
		audio.name = "OriginalOof"
		audio.stream = _get_oof_audio()
		audio.max_distance = 40.0 * STUD
		audio.unit_size = 10.0 * STUD
		debris.add_child(audio)
		audio.play()
	var tree := world.get_tree() if (world != null and world.is_inside_tree()) else (get_tree() if is_inside_tree() else null)
	if tree != null:
		var cleanup := tree.create_timer(5.0)
		cleanup.timeout.connect(debris.queue_free)


func _get_oof_audio() -> AudioStream:
	if _oof_audio == null:
		if ResourceLoader.exists("res://assets/rbx_uuhhh.mp3"):
			_oof_audio = load("res://assets/rbx_uuhhh.mp3")
		else:
			_oof_audio = load("res://assets/oof.wav")
	return _oof_audio


func _clear_rig_nodes() -> void:
	for child in get_children():
		if String(child.name).begins_with("UGCYaw_"):
			continue
		child.free()
	parts.clear()
	_pivots.clear()
	_part_sizes.clear()
	_part_aabb.clear()
	_mounts.clear()
	_overlays.clear()
	_nameplate = null
	_face_decal = null
	_tshirt_decal = null
	_anim_player = null


func _reapply_saved_appearance() -> void:
	for index in _applied_colors.keys():
		if int(index) >= 0 and int(index) < parts.size():
			parts[int(index)].material_override = _make_material(_applied_colors[index])
	for index in _applied_textures.keys():
		var pair: Array = _applied_textures[index]
		if pair.size() == 2:
			set_part_textured(int(index), pair[0], pair[1])
	if _applied_face_tex != null:
		set_face(_applied_face_tex, _applied_face_scale)
	if _applied_tshirt_tex != null:
		set_tshirt(_applied_tshirt_tex)


func _ensure_built(_allow_upgrade: bool = false) -> void:
	if _built:
		return
	_built = true
	if _try_r6ik():
		return
	_build_boxes()


func _try_r6ik() -> bool:
	var packed: PackedScene = null
	for path in [RIG_TSCN_PATH, RIG_GLB_PATH, RIG_SCENE_PATH]:
		if ResourceLoader.exists(path):
			packed = load(path)
			if packed != null:
				break
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
	if found.size() < 6:
		inst.free()
		return false

	var raw_bounds := AABB()
	var have_bounds := false
	var part_chains: Dictionary = {}
	var part_boxes: Dictionary = {}
	var upright_xform := Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3.ZERO)
	for index in found:
		var mi: MeshInstance3D = found[index]
		var box := _vertex_aabb(mi.mesh, upright_xform)
		part_chains[index] = upright_xform
		part_boxes[index] = box
		raw_bounds = box if not have_bounds else raw_bounds.merge(box)
		have_bounds = true

	var fit := RIG_HEIGHT / maxf(raw_bounds.size.y, 0.0001)
	var raw_center := raw_bounds.get_center()
	var model_xform := Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * fit),
		Vector3(-raw_center.x * fit, -raw_bounds.position.y * fit, -raw_center.z * fit)
	)

	_clear_rig_nodes()
	_using_r6ik = true

	for i in range(6):
		var src_mi: MeshInstance3D = found[i]
		var full_xform: Transform3D = model_xform * part_chains[i]
		var box: AABB = model_xform * part_boxes[i]
		var center: Vector3 = box.get_center()
		var size: Vector3 = box.size

		var pivot_pos := center
		match i:
			HEAD:
				pivot_pos = Vector3(0.0, 4.0 * STUD, 0.0)
			TORSO:
				pivot_pos = Vector3(0.0, 3.0 * STUD, 0.0)
			ARM_L, ARM_R:
				pivot_pos = Vector3(center.x, 3.5 * STUD, 0.0)
			LEG_L, LEG_R:
				pivot_pos = Vector3(center.x, 2.0 * STUD, 0.0)

		var pivot := Node3D.new()
		pivot.name = "Pivot_%d" % i
		pivot.position = pivot_pos
		add_child(pivot)
		_pivots.append(pivot)

		var holder := Node3D.new()
		holder.name = "Holder_%d" % i
		holder.position = -pivot_pos
		pivot.add_child(holder)

		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Part_%d" % i
		mesh_node.mesh = src_mi.mesh
		mesh_node.transform = full_xform
		holder.add_child(mesh_node)
		parts.append(mesh_node)
		_part_sizes.append(size)
		_part_aabb.append(box)

		var mount := Node3D.new()
		mount.name = "Mount_%d" % i
		mount.position = center - pivot_pos
		pivot.add_child(mount)
		_mounts.append(mount)

		if i == HEAD_INDEX:
			HEAD_PIVOT_Y = center.y

	inst.free()

	_setup_anim_library()
	_nameplate = _make_nameplate()
	_nameplate.position = Vector3(0.0, RIG_HEIGHT + 0.9 * STUD, 0.0)
	add_child(_nameplate)
	_nameplate.text = _display_name

	_reapply_saved_appearance()
	return true


func _setup_anim_library() -> void:
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimationPlayer"
	add_child(_anim_player)
	var lib := AnimationLibrary.new()

	var walk_anim := Animation.new()
	walk_anim.length = 0.8
	walk_anim.loop_mode = Animation.LOOP_LINEAR
	_add_curve_track(walk_anim, "Pivot_2:rotation", CURVE_WALK_ARM_L, 0.8)
	_add_curve_track(walk_anim, "Pivot_3:rotation", CURVE_WALK_ARM_R, 0.8)
	_add_curve_track(walk_anim, "Pivot_4:rotation", CURVE_WALK_LEG_L, 0.8)
	_add_curve_track(walk_anim, "Pivot_5:rotation", CURVE_WALK_LEG_R, 0.8)
	lib.add_animation(ANIM_WALK, walk_anim)

	var jump_anim := Animation.new()
	jump_anim.length = 0.8
	jump_anim.loop_mode = Animation.LOOP_NONE
	_add_curve_track(jump_anim, "Pivot_2:rotation", CURVE_JUMP_ARM_L, 0.8)
	_add_curve_track(jump_anim, "Pivot_3:rotation", CURVE_JUMP_ARM_R, 0.8)
	_add_curve_track(jump_anim, "Pivot_4:rotation", CURVE_JUMP_LEG_L, 0.8)
	_add_curve_track(jump_anim, "Pivot_5:rotation", CURVE_JUMP_LEG_R, 0.8)
	lib.add_animation(ANIM_JUMP, jump_anim)

	var climb_anim := Animation.new()
	climb_anim.length = 1.0
	climb_anim.loop_mode = Animation.LOOP_LINEAR
	_add_curve_track(climb_anim, "Pivot_2:rotation", CURVE_CLIMB_ARM_L, 1.0)
	_add_curve_track(climb_anim, "Pivot_3:rotation", CURVE_CLIMB_ARM_R, 1.0)
	_add_curve_track(climb_anim, "Pivot_4:rotation", CURVE_CLIMB_LEG_L, 1.0)
	_add_curve_track(climb_anim, "Pivot_5:rotation", CURVE_CLIMB_LEG_R, 1.0)
	lib.add_animation(ANIM_CLIMB, climb_anim)

	var sit_anim := Animation.new()
	sit_anim.length = 0.5
	sit_anim.loop_mode = Animation.LOOP_NONE
	_add_curve_track(sit_anim, "Pivot_2:rotation", CURVE_SIT_ARM_L, 0.5)
	_add_curve_track(sit_anim, "Pivot_3:rotation", CURVE_SIT_ARM_R, 0.5)
	_add_curve_track(sit_anim, "Pivot_4:rotation", CURVE_SIT_LEG, 0.5)
	_add_curve_track(sit_anim, "Pivot_5:rotation", CURVE_SIT_LEG, 0.5)
	lib.add_animation(ANIM_SIT, sit_anim)

	var idle_anim := Animation.new()
	idle_anim.length = 1.0
	idle_anim.loop_mode = Animation.LOOP_LINEAR
	_add_curve_track(idle_anim, "Pivot_4:rotation", CURVE_IDLE_LEG, 1.0)
	_add_curve_track(idle_anim, "Pivot_5:rotation", CURVE_IDLE_LEG, 1.0)
	lib.add_animation(ANIM_IDLE, idle_anim)

	if custom_walk_anim != null:
		lib.add_animation(&"CustomWalk", custom_walk_anim)

	_anim_player.add_animation_library("", lib)


func _add_curve_track(anim: Animation, path: String, curve: Array[float], duration: float) -> void:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath(path))
	var n := curve.size()
	for i in range(n):
		var time_pos := (float(i) / maxf(float(n - 1), 1.0)) * duration
		anim.track_insert_key(t, time_pos, Vector3(curve[i], 0.0, 0.0))


func _build_boxes() -> void:
	_clear_rig_nodes()
	_using_r6ik = false

	var limb_defs: Array = [
		[HEAD, Vector3(0, 4.0 + 1.15 * 0.5 - 0.05, 0) * STUD, BOX_HEAD, Vector3(0, 4.0, 0) * STUD],
		[TORSO, Vector3(0, 3.0, 0) * STUD, BOX_TORSO, Vector3(0, 3.0, 0) * STUD],
		[ARM_L, Vector3(-1.5, 3.0, 0) * STUD, BOX_ARM, Vector3(-1.5, 3.5, 0) * STUD],
		[ARM_R, Vector3(1.5, 3.0, 0) * STUD, BOX_ARM, Vector3(1.5, 3.5, 0) * STUD],
		[LEG_L, Vector3(-0.5, 1.0, 0) * STUD, BOX_LEG, Vector3(-0.5, 2.0, 0) * STUD],
		[LEG_R, Vector3(0.5, 1.0, 0) * STUD, BOX_LEG, Vector3(0.5, 2.0, 0) * STUD],
	]
	for def in limb_defs:
		var index: int = def[0]
		var center: Vector3 = def[1]
		var size: Vector3 = def[2]
		var pivot_pos: Vector3 = def[3]
		var pivot := Node3D.new()
		pivot.name = "Pivot_%d" % index
		pivot.position = pivot_pos
		add_child(pivot)
		_pivots.append(pivot)

		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Part_%d" % index
		mesh_node.position = center - pivot_pos
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_node.mesh = mesh
		pivot.add_child(mesh_node)
		parts.append(mesh_node)
		_part_sizes.append(size)
		_part_aabb.append(AABB(center - size * 0.5, size))

		var mount := Node3D.new()
		mount.name = "Mount_%d" % index
		mount.position = Vector3.ZERO
		mesh_node.add_child(mount)
		_mounts.append(mount)

	HEAD_PIVOT_Y = (4.0 + 1.15 * 0.5 - 0.05) * STUD
	_setup_anim_library()

	_nameplate = _make_nameplate()
	_nameplate.position = Vector3(0.0, RIG_HEIGHT + 0.9 * STUD, 0.0)
	add_child(_nameplate)
	_nameplate.text = _display_name

	_reapply_saved_appearance()


func _make_nameplate() -> Label3D:
	var label := Label3D.new()
	label.name = "Nameplate"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.007
	label.font_size = 40
	label.outline_size = 7
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.text = _display_name
	return label


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
	piece.global_transform = _mounts[index].global_transform
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
	shape.size = _part_sizes[index]
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
			var index: int = entry[0]
			var aliases: Array = entry[1]
			for alias in aliases:
				if norm == alias or norm.begins_with(alias) or norm.ends_with(alias):
					return index
	return -1


func _norm_part_name(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if ch in RIG_NAME_CHARS:
			out += ch
		elif ch == " " or ch == "-" or ch == ".":
			out += " "
	while "  " in out:
		out = out.replace("  ", " ")
	return out.strip_edges()
