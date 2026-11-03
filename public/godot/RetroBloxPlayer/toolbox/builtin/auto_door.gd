extends Node3D
## Proximity-activated sliding door model with script.

@export var slide_distance: float = 3.2
@export var slide_speed: float = 6.0
@export var trigger_radius: float = 7.0

var _left_panel: Node3D
var _right_panel: Node3D
var _left_closed_x: float = -1.5
var _right_closed_x: float = 1.5

func _ready() -> void:
	_left_panel = get_node_or_null("LeftDoor") as Node3D
	_right_panel = get_node_or_null("RightDoor") as Node3D
	if _left_panel != null:
		_left_closed_x = _left_panel.position.x
	if _right_panel != null:
		_right_closed_x = _right_panel.position.x

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var open_amount := 0.0
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		for ch in tree.current_scene.find_children("*", "CharacterBody3D", true, false):
			var cb := ch as CharacterBody3D
			if cb != null and cb.global_position.distance_to(global_position) <= trigger_radius:
				open_amount = 1.0
				break
	var target_l := _left_closed_x - slide_distance * open_amount
	var target_r := _right_closed_x + slide_distance * open_amount
	if _left_panel != null:
		_left_panel.position.x = move_toward(_left_panel.position.x, target_l, slide_speed * delta)
	if _right_panel != null:
		_right_panel.position.x = move_toward(_right_panel.position.x, target_r, slide_speed * delta)
