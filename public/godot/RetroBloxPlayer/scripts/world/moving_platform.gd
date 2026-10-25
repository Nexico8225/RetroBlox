@tool
class_name MovingPlatform
extends AnimatableBody3D
# Classic RetroBlox Moveable Platform (Point A <-> Point B).
# Supports:
#   - Mode 0 ("Always Move") or Mode 1 ("Move When Player Stands On It")
#   - Editable Easing ("Linear", "SineInOut", "QuadInOut", "CubicInOut",
#     "ExpoInOut", "BounceOut", "ElasticOut", "BackInOut")
#   - Point A / Point B offsets or world coordinates

const STUD := 1.0
const STUDS_SHADER_PATH := "res://assets/studs/part_studs.gdshader"

@export_group("Platform Appearance")
@export var block_size := Vector3(6.0, 1.0, 6.0):
	set(v):
		block_size = Vector3(maxf(v.x, 0.2), maxf(v.y, 0.2), maxf(v.z, 0.2))
		if is_inside_tree():
			_rebuild_visuals_and_collider()

@export var block_color := Color("f5cd30"):
	set(v):
		block_color = v
		if is_inside_tree():
			_rebuild_visuals_and_collider()

@export_group("Movement (Point A to Point B)")
## Choose whether the platform moves continuously or only when a player stands on it.
@export_enum("Always Move:0", "Move When Player Stands On It:1") var move_mode: int = 0:
	set(v):
		move_mode = v
		move_on_stand = (v == 1)

## Toggle: if true, platform moves to Point B when player stands on it and returns to Point A when they step off.
@export var move_on_stand := false:
	set(v):
		if move_on_stand == v:
			return
		move_on_stand = v
		if v and move_mode == 0:
			move_mode = 1
		elif not v and move_mode == 1:
			move_mode = 0

## Toggle alias for backwards compatibility.
@export var move_on_player_stand := false:
	set(v):
		if move_on_player_stand == v:
			return
		move_on_player_stand = v
		move_on_stand = v

## If true, jumping while on the moving platform carries you along with the platform in mid-air so you never get dropped off.
@export var keep_player_on_jump := true

## If false (default), Point A is the platform's starting position + point_a, and Point B is starting position + point_b (or target_offset). If true, point_a and point_b are exact world coordinates.
@export var use_world_coordinates := false

## Point A offset (or world position if use_world_coordinates is true).
@export var point_a := Vector3.ZERO

## Point B offset from start (or world position if use_world_coordinates is true).
@export var point_b := Vector3(0.0, 0.0, 14.0):
	set(v):
		point_b = v
		target_offset = v

## Legacy / convenience alias for point_b offset.
@export var target_offset := Vector3(0.0, 0.0, 14.0):
	set(v):
		target_offset = v
		if point_b != v:
			point_b = v

## Seconds it takes to travel from Point A to Point B.
@export var move_duration := 3.0

## Seconds to pause at Point A / Point B.
@export var wait_time := 0.8

## Easing curve for the movement between Point A and Point B.
@export_enum("Linear", "SineInOut", "QuadInOut", "CubicInOut", "ExpoInOut", "BounceOut", "ElasticOut", "BackInOut") var easing := "SineInOut"

var _origin := Vector3.ZERO
var _world_a := Vector3.ZERO
var _world_b := Vector3.ZERO
var _progress := 0.0        # 0.0 = Point A, 1.0 = Point B
var _forward := true        # true = heading to B, false = heading to A
var _wait_timer := 0.0
var _players_on_top: Array[Node3D] = []
var _stand_area: Area3D


func _ready() -> void:
	sync_to_physics = true
	add_to_group("moving_platform")
	_rebuild_visuals_and_collider()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_origin = global_position
	_recompute_endpoints()
	global_position = _world_a
	_wait_timer = wait_time
	_setup_stand_sensor()
	set_physics_process(true)


func _recompute_endpoints() -> void:
	if use_world_coordinates:
		_world_a = point_a * STUD
		_world_b = point_b * STUD
	else:
		_world_a = _origin + point_a * STUD
		var b_off := point_b if point_b != Vector3.ZERO else target_offset
		_world_b = _origin + b_off * STUD


func _rebuild_visuals_and_collider() -> void:
	var has_custom := false
	for child in get_children():
		if (child is MeshInstance3D or child is CollisionShape3D) and not child.has_meta("_mp_gen"):
			has_custom = true
	if has_custom:
		return
	for child in get_children():
		if child.has_meta("_mp_gen"):
			child.queue_free()

	var world_sz := block_size * STUD
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "PlatformMesh"
	mesh_inst.set_meta("_mp_gen", true)
	var bm := BoxMesh.new()
	bm.size = world_sz
	mesh_inst.mesh = bm

	var wb := load("res://scripts/world/world_builder.gd")
	if wb != null and wb.has_method("make_studded_material"):
		mesh_inst.material_override = wb.call("make_studded_material", block_color)
	if mesh_inst.material_override == null:
		var std := StandardMaterial3D.new()
		std.albedo_color = block_color
		std.roughness = 0.4
		mesh_inst.material_override = std
	add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = "PlatformCollider"
	col.set_meta("_mp_gen", true)
	var shape := BoxShape3D.new()
	shape.size = world_sz
	col.shape = shape
	add_child(col)


func _setup_stand_sensor() -> void:
	if _stand_area != null and is_instance_valid(_stand_area):
		_stand_area.queue_free()
	_stand_area = Area3D.new()
	_stand_area.name = "StandSensor"
	_stand_area.collision_layer = 0
	_stand_area.collision_mask = 0xFFFFFFFF
	_stand_area.monitoring = true
	_stand_area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var world_sz := block_size * STUD
	box.size = Vector3(world_sz.x + 1.2 * STUD, 7.5 * STUD, world_sz.z + 1.2 * STUD)
	cs.shape = box
	cs.position = Vector3(0.0, world_sz.y * 0.5 + 3.6 * STUD, 0.0)
	_stand_area.add_child(cs)
	_stand_area.body_entered.connect(_on_stand_entered)
	_stand_area.body_exited.connect(_on_stand_exited)
	add_child(_stand_area)


func _on_stand_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		(body as CharacterBody3D).platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
		if not _players_on_top.has(body):
			_players_on_top.append(body)


func _on_stand_exited(body: Node3D) -> void:
	_players_on_top.erase(body)


func _is_player_on_or_jumping_above(b: CharacterBody3D) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var world_sz := block_size * STUD
	var rel := b.global_position - global_position
	var max_x := world_sz.x * 0.5 + 1.6 * STUD
	var max_z := world_sz.z * 0.5 + 1.6 * STUD
	if absf(rel.x) > max_x or absf(rel.z) > max_z:
		return false
	var top_y := world_sz.y * 0.5
	var max_y := top_y + (9.5 * STUD if keep_player_on_jump else 1.8 * STUD)
	return rel.y >= top_y - 0.6 * STUD and rel.y <= max_y


func _is_player_standing() -> bool:
	if _stand_area != null and is_instance_valid(_stand_area):
		for b in _stand_area.get_overlapping_bodies():
			if b is CharacterBody3D and _is_player_on_or_jumping_above(b as CharacterBody3D):
				(b as CharacterBody3D).platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
				if not _players_on_top.has(b):
					_players_on_top.append(b)
				return true
	for i in range(_players_on_top.size() - 1, -1, -1):
		var p := _players_on_top[i]
		if not is_instance_valid(p) or not (p is CharacterBody3D) or not _is_player_on_or_jumping_above(p as CharacterBody3D):
			_players_on_top.remove_at(i)
	if not _players_on_top.is_empty():
		return true
	return false


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_recompute_endpoints()
	var dur := maxf(move_duration, 0.05)
	var stand_only := (move_mode == 1) or move_on_stand or move_on_player_stand
	var has_rider := _is_player_standing()

	if stand_only:
		if has_rider:
			if _progress < 1.0:
				_progress = minf(1.0, _progress + delta / dur)
		else:
			if _progress > 0.0:
				_progress = maxf(0.0, _progress - delta / dur)
	else:
		if _wait_timer > 0.0:
			_wait_timer -= delta
		else:
			if _forward:
				_progress += delta / dur
				if _progress >= 1.0:
					_progress = 1.0
					_forward = false
					_wait_timer = maxf(wait_time, 0.0)
			else:
				_progress -= delta / dur
				if _progress <= 0.0:
					_progress = 0.0
					_forward = true
					_wait_timer = maxf(wait_time, 0.0)

	var prev_pos := global_position
	var eased_t := _evaluate_easing(_progress, easing)
	var next_pos := _world_a.lerp(_world_b, eased_t)
	var step_delta := next_pos - prev_pos
	global_position = next_pos

	if keep_player_on_jump and step_delta.length_squared() > 0.0:
		var top_surface_y := next_pos.y + block_size.y * 0.5 * STUD
		for p in _players_on_top:
			if is_instance_valid(p) and p is CharacterBody3D:
				var cb := p as CharacterBody3D
				cb.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
				if not cb.is_on_floor():
					cb.global_position += step_delta
					if cb.global_position.y < top_surface_y + 0.02:
						cb.global_position.y = top_surface_y + 0.02


static func _evaluate_easing(t: float, kind: String) -> float:
	var x := clampf(t, 0.0, 1.0)
	match kind:
		"Linear":
			return x
		"SineInOut":
			return -(cos(PI * x) - 1.0) * 0.5
		"QuadInOut":
			return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) * 0.5
		"CubicInOut":
			return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5
		"ExpoInOut":
			if x == 0.0 or x == 1.0:
				return x
			return pow(2.0, 20.0 * x - 10.0) * 0.5 if x < 0.5 else (2.0 - pow(2.0, -20.0 * x + 10.0)) * 0.5
		"BackInOut":
			var c1 := 1.70158
			var c2 := c1 * 1.525
			if x < 0.5:
				return (pow(2.0 * x, 2.0) * ((c2 + 1.0) * 2.0 * x - c2)) * 0.5
			return (pow(2.0 * x - 2.0, 2.0) * ((c2 + 1.0) * (x * 2.0 - 2.0) + c2) + 2.0) * 0.5
		"ElasticOut":
			if x == 0.0 or x == 1.0:
				return x
			var c4 := (2.0 * PI) / 3.0
			return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * c4) + 1.0
		"BounceOut":
			return _bounce_out(x)
		_:
			return -(cos(PI * x) - 1.0) * 0.5


static func _bounce_out(x: float) -> float:
	var n1 := 7.5625
	var d1 := 2.75
	if x < 1.0 / d1:
		return n1 * x * x
	elif x < 2.0 / d1:
		var xm := x - 1.5 / d1
		return n1 * xm * xm + 0.75
	elif x < 2.5 / d1:
		var xm2 := x - 2.25 / d1
		return n1 * xm2 * xm2 + 0.9375
	else:
		var xm3 := x - 2.625 / d1
		return n1 * xm3 * xm3 + 0.984375
