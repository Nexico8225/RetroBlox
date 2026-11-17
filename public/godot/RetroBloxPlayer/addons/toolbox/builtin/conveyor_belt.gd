extends StaticBody3D
## Conveyor belt block with script that pushes players along its local -Z (forward) direction.

@export var belt_speed: float = 14.0

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var dir := -global_transform.basis.z.normalized()
	constant_linear_velocity = dir * belt_speed
