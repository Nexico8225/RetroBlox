@tool
class_name JumpPad3D
extends Area3D

# RetroBlox Custom Node: JumpPad3D
# Launches the player upwards or in a specified direction when touched.

@export var jump_force: float = 85.0
@export var launch_direction: Vector3 = Vector3.UP
@export var cooldown: float = 0.25

var _last_launch_time: float = -999.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Players layer
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_launch_time < cooldown:
		return
	_last_launch_time = now

	var dir = launch_direction.normalized()
	if body is CharacterBody3D:
		var cb := body as CharacterBody3D
		cb.velocity = dir * jump_force
	elif body.has_method("launch"):
		body.call("launch", dir * jump_force)
	elif "velocity" in body:
		body.set("velocity", dir * jump_force)
