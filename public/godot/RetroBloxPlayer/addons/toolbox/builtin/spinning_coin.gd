extends Node3D
## Spinning collectible coin with bobbing motion and auto-respawn.

@export var spin_speed: float = 140.0
@export var bob_height: float = 0.35
@export var respawn_time: float = 5.0

var _base_y: float = 0.0
var _time: float = 0.0
var _collected: bool = false
var _respawn_timer: float = 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	_base_y = position.y
	_mesh = get_node_or_null("CoinMesh") as MeshInstance3D
	var area := get_node_or_null("PickupArea") as Area3D
	if area != null and not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _collected:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_collected = false
			if _mesh != null:
				_mesh.visible = true
		return
	_time += delta
	rotate_y(deg_to_rad(spin_speed) * delta)
	position.y = _base_y + sin(_time * 3.2) * bob_height

func _on_body_entered(body: Node) -> void:
	if _collected or Engine.is_editor_hint():
		return
	if body is CharacterBody3D:
		_collected = true
		_respawn_timer = respawn_time
		if _mesh != null:
			_mesh.visible = false
		var sfx_node: Node = get_node_or_null("/root/Sfx")
		if sfx_node != null and sfx_node.has_method("play_click"):
			sfx_node.call("play_click")
