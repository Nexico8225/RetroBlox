extends Node3D
## Classic Roblox-style Car script — moves forward when a player touches or sits in the seat!

@export var drive_speed: float = 22.0
@export var turn_speed: float = 1.8

var _driver: CharacterBody3D = null

func _ready() -> void:
	var seat_area := get_node_or_null("SeatTrigger") as Area3D
	if seat_area != null:
		seat_area.body_entered.connect(func(b: Node) -> void:
			if b is CharacterBody3D:
				_driver = b as CharacterBody3D
		)
		seat_area.body_exited.connect(func(b: Node) -> void:
			if b == _driver:
				_driver = null
		)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _driver == null or not is_instance_valid(_driver):
		return
	var fwd := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_right", "move_left")
	if absf(fwd) > 0.05:
		rotate_y(steer * turn_speed * delta * signf(fwd))
		var step := -global_transform.basis.z * (fwd * drive_speed * delta)
		global_position += step
		_driver.global_position = global_position + Vector3(0, 2.2, 0)
