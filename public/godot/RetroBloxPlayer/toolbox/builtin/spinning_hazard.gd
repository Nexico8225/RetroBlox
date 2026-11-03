extends Node3D
## Rotating hazard bar that spins continuously and damages players on contact.

@export var spin_speed_deg: float = 90.0
@export var damage_per_touch: float = 35.0
@export var spin_axis: Vector3 = Vector3.UP

var _cooldowns: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is Area3D:
			var area := child as Area3D
			if not area.body_entered.is_connected(_on_body_entered):
				area.body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var axis := spin_axis.normalized()
	if axis.length_squared() > 0.001:
		rotate(axis, deg_to_rad(spin_speed_deg) * delta)
	var now := Time.get_ticks_msec() * 0.001
	for k in _cooldowns.keys():
		if now - float(_cooldowns[k]) > 0.65:
			_cooldowns.erase(k)

func _on_body_entered(body: Node) -> void:
	if body == null or Engine.is_editor_hint():
		return
	var id := body.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	if _cooldowns.has(id):
		return
	_cooldowns[id] = now
	if body.has_method("take_damage"):
		body.call("take_damage", damage_per_touch)
