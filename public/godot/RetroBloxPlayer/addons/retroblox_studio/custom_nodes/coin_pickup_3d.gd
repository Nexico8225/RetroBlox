@tool
class_name CoinPickup3D
extends Area3D

# RetroBlox Custom Node: CoinPickup3D
# Collectible item that spins, adds points/Tix to the player, and respawns.

@export var value: int = 10
@export var currency_type: String = "Tix"
@export var rotation_speed: float = 120.0
@export var respawn_time: float = 10.0
@export var pickup_sound: String = "res://assets/sounds/coin.ogg"

var _collected: bool = false
var _mesh_node: Node3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Players
	body_entered.connect(_on_pickup)
	for ch in get_children():
		if ch is MeshInstance3D or ch is Node3D:
			_mesh_node = ch
			break

func _process(delta: float) -> void:
	if _mesh_node != null and not _collected:
		_mesh_node.rotate_y(deg_to_rad(rotation_speed * delta))

func _on_pickup(body: Node3D) -> void:
	if _collected:
		return
	_collected = true
	visible = false

	if body.has_method("add_points"):
		body.call("add_points", value)
	elif body.has_method("add_tix"):
		body.call("add_tix", value)

	if respawn_time > 0.0:
		await get_tree().create_timer(respawn_time).timeout
		_collected = false
		visible = true
	else:
		queue_free()
