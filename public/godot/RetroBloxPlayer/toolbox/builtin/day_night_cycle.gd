extends Node
## Standalone Day/Night cycle script. Attach to World or DirectionalLight3D.

@export var day_length_seconds: float = 120.0
@export var start_hour: float = 10.0

var _time_hours: float = 10.0

func _ready() -> void:
	_time_hours = start_hour

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if day_length_seconds <= 1.0:
		return
	_time_hours = fposmod(_time_hours + (24.0 / day_length_seconds) * delta, 24.0)
	var sun := _find_sun()
	if sun != null:
		var angle := ((_time_hours / 24.0) * 360.0) - 90.0
		sun.rotation_degrees.x = -angle
		var daylight := clampf(sin(deg_to_rad(angle)), 0.08, 1.0)
		sun.light_energy = daylight * 1.15

func _find_sun() -> DirectionalLight3D:
	if get_parent() is DirectionalLight3D:
		return get_parent() as DirectionalLight3D
	if get_tree() != null and get_tree().current_scene != null:
		for ch in get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
			return ch as DirectionalLight3D
	return null
