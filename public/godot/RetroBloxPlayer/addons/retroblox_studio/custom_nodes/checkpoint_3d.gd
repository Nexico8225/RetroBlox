@tool
class_name Checkpoint3D
extends Area3D

# RetroBlox Custom Node: Checkpoint3D
# Updates the player's respawn position to this pad's location when touched.

@export var checkpoint_id: int = 1
@export var active_color: Color = Color(0.2, 0.9, 0.3)
@export var inactive_color: Color = Color(0.8, 0.8, 0.8)

var _activated: bool = false
var _mesh_inst: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Players
	body_entered.connect(_on_touched)
	for ch in get_children():
		if ch is MeshInstance3D:
			_mesh_inst = ch
			break

func _on_touched(body: Node3D) -> void:
	if body.has_method("set_checkpoint"):
		body.call("set_checkpoint", global_position, checkpoint_id)
	elif "checkpoint_pos" in body:
		body.set("checkpoint_pos", global_position)

	if not _activated:
		_activated = true
		if _mesh_inst != null and _mesh_inst.material_override is StandardMaterial3D:
			var mat := _mesh_inst.material_override.duplicate() as StandardMaterial3D
			mat.albedo_color = active_color
			mat.emission_enabled = true
			mat.emission = active_color
			_mesh_inst.material_override = mat
