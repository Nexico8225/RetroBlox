class_name WorldConfig
extends Node3D
# Map-wide tuning for the spawn hub. Add this node under World to change safe-zone size,
# item respawn timers and hub layout distances without touching any script.
# Every value here is read at runtime by scripts/game/game.gd.

@export_group("Safe Zone")
## Radius in studs where players cannot take damage (spawn plaza).
@export var safe_zone_radius: float = 26.0:
	set(v):
		safe_zone_radius = maxf(v, 1.0)
## Vertical tolerance in studs above / below the safe-zone pad.
@export var safe_zone_height: float = 30.0:
	set(v):
		safe_zone_height = maxf(v, 1.0)
## Health per second restored inside the safe zone (0 = no healing, classic spawn only).
@export var safe_zone_heal_per_sec: float = 4.0
## Removes burn / slow effects on contact.
@export var safe_zone_clears_effects: bool = true

@export_group("Item Spawners")
## Seconds before a picked-up gear reappears on its pad.
@export var item_respawn_cooldown: float = 1.5:
	set(v):
		item_respawn_cooldown = maxf(v, 0.1)
## Applies the value above to every spawner in the map on load.
@export var override_spawner_cooldowns: bool = true

@export_group("Spawn Plaza")
## Distance in studs from the spawn pad to the first ring of gear pads.
@export var gear_ring_radius: float = 16.0
## Height of the sign that labels the plaza.
@export var plaza_sign_height: float = 12.0


func _ready() -> void:
	add_to_group("world_config")
