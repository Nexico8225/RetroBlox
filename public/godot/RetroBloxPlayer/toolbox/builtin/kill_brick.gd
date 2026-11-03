extends Node3D
## Attach to any 3D Part or StaticBody3D to turn it into an instant Lava / Kill Brick.

@export var damage: float = 100.0

func _ready() -> void:
	var area := Area3D.new()
	area.name = "KillArea"
	add_child(area)
	for ch in get_children():
		if ch is CollisionShape3D:
			var dup := (ch as CollisionShape3D).duplicate() as CollisionShape3D
			dup.scale = Vector3(1.05, 1.08, 1.05)
			area.add_child(dup)
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body != null and body.has_method("take_damage"):
		body.call("take_damage", damage)
