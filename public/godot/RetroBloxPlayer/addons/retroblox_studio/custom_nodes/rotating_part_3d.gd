@tool
class_name RotatingPart3D
extends AnimatableBody3D

# RetroBlox Custom Node: RotatingPart3D
# Constantly rotates around an axis (e.g. spinning obstacle, turbine, coin spinner).

@export var rotation_axis: Vector3 = Vector3.UP
@export var degrees_per_second: float = 90.0

func _physics_process(delta: float) -> void:
	var rad = deg_to_rad(degrees_per_second * delta)
	rotate(rotation_axis.normalized(), rad)
