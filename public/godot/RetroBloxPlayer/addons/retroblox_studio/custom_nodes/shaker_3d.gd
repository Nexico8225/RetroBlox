@tool
class_name Shaker3D
extends Node

# RetroBlox Custom Node: Shaker3D (Hidden Gem Showcase)
# Screen / Camera / Object Shake generator based on trauma-decay algorithm.
# Can shake any Camera3D or Node3D with smooth Perlin/Simplex-style trauma.

@export var target_node_path: NodePath
@export var max_offset: Vector3 = Vector3(0.5, 0.5, 0.2)
@export var max_rotation_deg: Vector3 = Vector3(5.0, 5.0, 3.0)
@export var trauma_decay: float = 1.2
@export var frequency: float = 24.0

var _trauma: float = 0.0
var _time: float = 0.0
var _target: Node3D = null
var _original_pos: Vector3 = Vector3.ZERO
var _original_rot: Vector3 = Vector3.ZERO

func _ready() -> void:
	if target_node_path != NodePath(""):
		_target = get_node_or_null(target_node_path) as Node3D
	elif get_parent() is Node3D:
		_target = get_parent() as Node3D

	if _target != null:
		_original_pos = _target.position
		_original_rot = _target.rotation_degrees

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func set_trauma(amount: float) -> void:
	_trauma = clampf(amount, 0.0, 1.0)

func _process(delta: float) -> void:
	if _target == null or _trauma <= 0.0:
		return

	_time += delta * frequency
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)

	var shake = _trauma * _trauma
	var offset_x = (sin(_time * 1.1) + sin(_time * 2.3)) * 0.5 * max_offset.x * shake
	var offset_y = (cos(_time * 1.3) + sin(_time * 2.7)) * 0.5 * max_offset.y * shake
	var offset_z = (sin(_time * 0.9) + cos(_time * 1.9)) * 0.5 * max_offset.z * shake

	var rot_x = (sin(_time * 1.2) + cos(_time * 2.1)) * 0.5 * max_rotation_deg.x * shake
	var rot_y = (cos(_time * 1.4) + sin(_time * 2.5)) * 0.5 * max_rotation_deg.y * shake
	var rot_z = (sin(_time * 0.8) + cos(_time * 1.7)) * 0.5 * max_rotation_deg.z * shake

	_target.position = _original_pos + Vector3(offset_x, offset_y, offset_z)
	_target.rotation_degrees = _original_rot + Vector3(rot_x, rot_y, rot_z)

	if _trauma <= 0.0:
		_target.position = _original_pos
		_target.rotation_degrees = _original_rot
