@tool
class_name SpawnLocation
extends RetroPart

## A classic spawn pad. Players appear on the spawn pads in your map,
## round-robin. Defaults to the classic 6 x 1 x 6 grey plate — resize or
## recolor it like any RetroPart.

func _init() -> void:
        size = Vector3(6.0, 1.0, 6.0)
        color = Color("a3a2a5")


func _enter_tree() -> void:
        if not is_in_group("spawn"):
                add_to_group("spawn")
