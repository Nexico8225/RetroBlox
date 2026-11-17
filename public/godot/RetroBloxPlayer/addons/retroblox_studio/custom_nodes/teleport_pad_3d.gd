@tool
class_name TeleportPad3D
extends Area3D

# RetroBlox Custom Node: TeleportPad3D
# Instantly teleports any player who touches it to a target destination or Node3D.

@export var target_node_path: NodePath
@export var target_position: Vector3 = Vector3.ZERO
@export var preserve_velocity: bool = false
@export var cooldown: float = 1.0

var _last_tp_time: float = -999.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Players layer
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_tp_time < cooldown:
		return
	_last_tp_time = now

	var dest: Vector3 = target_position
	if target_node_path != NodePath(""):
		var target_node = get_node_or_null(target_node_path)
		if target_node is Node3D:
			dest = (target_node as Node3D).global_position

	body.global_position = dest
	if not preserve_velocity and "velocity" in body:
		body.set("velocity", Vector3.ZERO)
