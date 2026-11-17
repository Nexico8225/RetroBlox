@tool
class_name PhantomCamera3D
extends Node3D

# RetroBlox Custom Node: PhantomCamera3D (Hidden Gem Showcase)
# Advanced follow and look-at camera controller with smoothing, lead distance and damping.

@export var follow_target_path: NodePath
@export var look_at_target_path: NodePath
@export var follow_distance: float = 12.0
@export var follow_height: float = 6.0
@export var follow_damping: float = 6.0
@export var rotation_damping: float = 8.0
@export var active: bool = true

var _follow_target: Node3D = null
var _look_at_target: Node3D = null

func _ready() -> void:
	if follow_target_path != NodePath(""):
		_follow_target = get_node_or_null(follow_target_path) as Node3D
	if look_at_target_path != NodePath(""):
		_look_at_target = get_node_or_null(look_at_target_path) as Node3D

func _process(delta: float) -> void:
	if not active or _follow_target == null:
		return

	var target_pos = _follow_target.global_position
	var behind_dir = -_follow_target.global_transform.basis.z.normalized()
	var desired_pos = target_pos + behind_dir * follow_distance + Vector3(0, follow_height, 0)

	global_position = global_position.lerp(desired_pos, follow_damping * delta)

	var look_pos = target_pos
	if _look_at_target != null:
		look_pos = _look_at_target.global_position

	var current_rot = global_transform.basis
	var target_rot = Transform3D().looking_at(look_pos - global_position, Vector3.UP).basis
	global_transform.basis = current_rot.slerp(target_rot, rotation_damping * delta)
