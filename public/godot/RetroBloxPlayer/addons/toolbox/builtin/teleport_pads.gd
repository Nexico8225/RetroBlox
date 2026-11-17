extends Node3D
## Linked Green & Red Easy Teleport Pads from the RetroBlox Toolbox.

var _cooldowns: Dictionary = {}

func _ready() -> void:
	var area_a := get_node_or_null("PadGreen/AreaA") as Area3D
	var area_b := get_node_or_null("PadRed/AreaB") as Area3D
	var pad_a := get_node_or_null("PadGreen") as Node3D
	var pad_b := get_node_or_null("PadRed") as Node3D
	if area_a != null and pad_b != null:
		area_a.body_entered.connect(func(b: Node) -> void: _teleport_to(b, pad_b))
	if area_b != null and pad_a != null:
		area_b.body_entered.connect(func(b: Node) -> void: _teleport_to(b, pad_a))

func _teleport_to(body: Node, dest: Node3D) -> void:
	if Engine.is_editor_hint() or not (body is CharacterBody3D):
		return
	var id := body.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	if _cooldowns.has(id) and now - float(_cooldowns[id]) < 1.2:
		return
	_cooldowns[id] = now
	(body as CharacterBody3D).global_position = dest.global_position + Vector3(0, 3.0, 0)
