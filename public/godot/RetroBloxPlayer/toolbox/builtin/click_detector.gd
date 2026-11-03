extends Node3D
## Roblox-style ClickDetector / Proximity Interact script.
## Attach to any 3D Part or Model (or place as a child inside one) to run custom logic when clicked in 3D.

signal clicked(by_node: Node)

@export var max_activation_distance: float = 24.0
@export var bounce_on_click: bool = true


func _ready() -> void:
	# 1. Connect to parent if parent has collision (standard Roblox ClickDetector pattern)
	var parent_node: Node = get_parent()
	if parent_node is CollisionObject3D:
		parent_node.input_event.connect(_on_input_event)
	elif parent_node != null:
		for ch: Node in parent_node.get_children():
			if ch != self and ch is CollisionObject3D:
				ch.input_event.connect(_on_input_event)

	# 2. Connect to any CollisionObject3D children
	for ch: Node in get_children():
		if ch is CollisionObject3D:
			ch.input_event.connect(_on_input_event)


func _on_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.is_pressed() and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(self)
			if bounce_on_click:
				var tw := create_tween()
				var base_s := scale
				tw.tween_property(self, "scale", base_s * 1.15, 0.08)
				tw.tween_property(self, "scale", base_s, 0.12)
