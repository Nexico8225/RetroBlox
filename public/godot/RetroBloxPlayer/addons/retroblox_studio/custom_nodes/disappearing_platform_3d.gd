@tool
class_name DisappearingPlatform3D
extends StaticBody3D

# RetroBlox Custom Node: DisappearingPlatform3D
# Classic Roblox obby disappearing/falling tile: steps on it -> shakes/flashes -> disappears -> regenerates!

@export var delay_before_fall: float = 1.0
@export var respawn_time: float = 3.0

var _is_triggered: bool = false
var _trigger_area: Area3D
var _collision_shape: CollisionShape3D
var _mesh_instance: MeshInstance3D

func _ready() -> void:
	for ch in get_children():
		if ch is CollisionShape3D:
			_collision_shape = ch
		elif ch is MeshInstance3D:
			_mesh_instance = ch

	_trigger_area = Area3D.new()
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = 4 # Players
	add_child(_trigger_area)

	var shape_copy = CollisionShape3D.new()
	if _collision_shape != null and _collision_shape.shape != null:
		shape_copy.shape = _collision_shape.shape
	else:
		var bs = BoxShape3D.new()
		bs.size = Vector3(4.0, 1.0, 4.0)
		shape_copy.shape = bs
	shape_copy.position.y += 0.1
	_trigger_area.add_child(shape_copy)
	_trigger_area.body_entered.connect(_on_stepped_on)

func _on_stepped_on(_body: Node3D) -> void:
	if _is_triggered:
		return
	_is_triggered = true
	_sequence_fall()

func _sequence_fall() -> void:
	var tween = create_tween()
	if _mesh_instance != null:
		tween.tween_property(_mesh_instance, "transparency", 0.7, delay_before_fall)
	await get_tree().create_timer(delay_before_fall).timeout

	if _collision_shape != null:
		_collision_shape.disabled = true
	if _mesh_instance != null:
		_mesh_instance.visible = false

	await get_tree().create_timer(respawn_time).timeout

	if _collision_shape != null:
		_collision_shape.disabled = false
	if _mesh_instance != null:
		_mesh_instance.visible = true
		_mesh_instance.transparency = 0.0
	_is_triggered = false
