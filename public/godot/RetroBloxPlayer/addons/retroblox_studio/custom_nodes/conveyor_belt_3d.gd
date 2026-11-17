@tool
class_name ConveyorBelt3D
extends AnimatableBody3D

# RetroBlox Custom Node: ConveyorBelt3D
# Constantly conveys/pushes players and rigid bodies across its surface in a direction.

@export var conveyor_speed: float = 12.0
@export var local_direction: Vector3 = Vector3.FORWARD

func _physics_process(_delta: float) -> void:
	constant_linear_velocity = global_transform.basis * (local_direction.normalized() * conveyor_speed)
