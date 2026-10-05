class_name ToolBase
extends Node3D
## Base for all RetroBlox tools. Lives under the local player's avatar hand
## mount; the owner calls use_primary()/use_secondary() from input.

signal used(kind: String)  # "swing" | "shot" | "place" — main.gd routes effects

var player: Node3D = null          # the local player node
var main: Node = null              # main.gd — for RPCs
var cooldown: float = 0.0
var _cd_left: float = 0.0

func setup(p_player: Node3D, p_main: Node) -> void:
	player = p_player
	main = p_main

func _process(delta: float) -> void:
	_cd_left = maxf(0.0, _cd_left - delta)

func ready_to_use() -> bool:
	return _cd_left <= 0.0

func start_cooldown(seconds: float) -> void:
	_cd_left = seconds

## Override in tools. Return true if the action fired.
func use_primary() -> bool:
	return false

func use_secondary() -> bool:
	return false

func equip() -> void:
	visible = true

func unequip() -> void:
	visible = false

## Aim ray from the camera through the crosshair-ish center.
func aim_ray(max_distance: float) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * max_distance)
	query.exclude = [player.get_rid()] if player is PhysicsBody3D else []
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit
