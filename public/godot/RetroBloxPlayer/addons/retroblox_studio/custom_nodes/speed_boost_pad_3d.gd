@tool
class_name SpeedBoostPad3D
extends Area3D

# RetroBlox Custom Node: SpeedBoostPad3D
# Temporarily boosts player walk speed on contact.

@export var speed_multiplier: float = 2.5
@export var boost_duration: float = 4.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Players layer
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("apply_speed_boost"):
		body.call("apply_speed_boost", speed_multiplier, boost_duration)
	elif "walk_speed" in body:
		var orig = float(body.get("walk_speed"))
		body.set("walk_speed", orig * speed_multiplier)
		get_tree().create_timer(boost_duration).timeout.connect(func():
			if is_instance_valid(body) and "walk_speed" in body:
				body.set("walk_speed", orig)
		)
