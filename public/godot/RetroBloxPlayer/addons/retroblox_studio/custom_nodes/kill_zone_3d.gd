@tool
class_name KillZone3D
extends Area3D

# RetroBlox Custom Node: KillZone3D
# Deals damage or instantly eliminates players touching this area (e.g. Lava, Acid, Void).

@export var damage: float = 100.0
@export var damage_interval: float = 0.5
@export var kill_sound: String = "res://assets/sounds/ouch.ogg"
@export var active: bool = true

var _timer: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Players layer
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if not active or damage_interval <= 0.0:
		return
	_timer += delta
	if _timer >= damage_interval:
		_timer = 0.0
		for body in get_overlapping_bodies():
			_apply_damage(body)

func _on_body_entered(body: Node3D) -> void:
	if not active:
		return
	_apply_damage(body)

func _apply_damage(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("take_damage"):
		body.call("take_damage", damage)
	elif body.has_method("kill"):
		body.call("kill")
	elif body.has_node("Humanoid"):
		var hum = body.get_node("Humanoid")
		if hum.has_method("take_damage"):
			hum.call("take_damage", damage)
