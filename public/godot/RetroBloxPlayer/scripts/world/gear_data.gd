class_name GearData
extends Resource
# Editable Gear Resource saved in res://gears/ — click any .tres file in res://gears/ to edit its variables in Godot Inspector!

@export var gear_id: String = "sword"
@export var gear_name: String = "Linked Sword"
@export var short_name: String = "SWORD"
@export var item_type: int = 5
@export var color: Color = Color("fcc419")
@export var cooldown: float = 1.1
@export var lose_item_when_dead: bool = true

@export_group("Melee & Sword Settings")
@export var slash_damage: float = 35.0
@export var lunge_damage: float = 55.0
@export var lunge_cooldown: float = 2.6
@export var sword_range: float = 4.8
## Forward lunge speed in studs/second. The lunge stays level with the ground you left.
@export var lunge_forward_boost: float = 46.0
## How long the level dash lasts in seconds. When it ends, gravity takes over and you fall.
@export var lunge_duration: float = 0.34
## Upward pop given at the start of the lunge, in studs/second (0 = perfectly flat).
@export var lunge_up_boost: float = 0.0
## Legacy field kept so older scenes keep loading (unused by the flat lunge).
@export var lunge_float_duration: float = 0.0
@export var burn_damage_per_sec: float = 0.0
@export var burn_duration: float = 0.0
@export var slow_multiplier: float = 1.0
@export var slow_duration: float = 0.0

@export_group("Coil & Passive Settings")
@export var speed_multiplier: float = 1.0
@export var gravity_multiplier: float = 1.0
@export var jump_boost_multiplier: float = 1.0
@export var heal_per_second: float = 0.0

@export_group("Swelling Ball Settings")
@export var min_swell_damage: float = 25.0
@export var max_swell_damage: float = 120.0
@export var max_swell_scale: float = 4.5
@export var max_charge_time: float = 2.5
@export var swell_launch_speed: float = 38.0

@export_group("Projectile & Explosive Settings")
@export var projectile_speed: float = 18.0
@export var projectile_damage: float = 9999.0
@export var insta_kill_on_touch: bool = true
@export var explosion_radius: float = 10.0
@export var explosion_damage: float = 120.0
@export var explosion_knockback: float = 42.0
@export var tripmine_arm_delay: float = 1.5

@export_group("Potion & Carpet Settings")
@export var heal_amount: float = 65.0
@export var head_scale_multiplier: float = 2.6
@export var big_head_duration: float = 18.0
@export var unlimited_potion_uses: bool = true
@export var fly_speed: float = 38.0
@export var ascend_speed: float = 24.0

@export_group("Grappler Settings")
## Maximum rope length in studs. Aim at a wall or platform and the hook pulls you there.
@export var grapple_range: float = 60.0
## Pull speed in studs/second once the hook bites.
@export var grapple_speed: float = 95.0
## How long the pull lasts before you drop (seconds).
@export var grapple_duration: float = 1.15

@export_group("Speed Surge & Food Settings")
## Walk speed multiplier while the surge lasts (Spicy Sauce = 3.0).
@export var speed_surge_multiplier: float = 1.0
## Surge duration in seconds.
@export var speed_surge_duration: float = 0.0
## Health drained per second while the surge is active (Spicy Sauce burns HP).
@export var health_cost_per_sec: float = 0.0

@export_group("Invisibility Settings")
## Seconds of invisibility after eating (Ghost Burger).
@export var invisible_duration: float = 0.0


func to_dictionary() -> Dictionary:
	return {
		"id": gear_id,
		"name": gear_name,
		"short": short_name,
		"item_type": item_type,
		"color": color,
		"cooldown": cooldown,
		"lose_item_when_dead": lose_item_when_dead,
		"slash_damage": slash_damage,
		"lunge_damage": lunge_damage,
		"lunge_cooldown": lunge_cooldown,
		"sword_range": sword_range,
		"lunge_forward_boost": lunge_forward_boost,
		"lunge_duration": lunge_duration,
		"lunge_up_boost": lunge_up_boost,
		"lunge_float_duration": lunge_float_duration,
		"burn_damage_per_sec": burn_damage_per_sec,
		"burn_duration": burn_duration,
		"slow_multiplier": slow_multiplier,
		"slow_duration": slow_duration,
		"speed_multiplier": speed_multiplier,
		"gravity_multiplier": gravity_multiplier,
		"jump_boost_multiplier": jump_boost_multiplier,
		"heal_per_second": heal_per_second,
		"min_swell_damage": min_swell_damage,
		"max_swell_damage": max_swell_damage,
		"max_swell_scale": max_swell_scale,
		"max_charge_time": max_charge_time,
		"swell_launch_speed": swell_launch_speed,
		"projectile_speed": projectile_speed,
		"projectile_damage": projectile_damage,
		"insta_kill_on_touch": insta_kill_on_touch,
		"explosion_radius": explosion_radius,
		"explosion_damage": explosion_damage,
		"explosion_knockback": explosion_knockback,
		"tripmine_arm_delay": tripmine_arm_delay,
		"heal_amount": heal_amount,
		"head_scale_multiplier": head_scale_multiplier,
		"big_head_duration": big_head_duration,
		"unlimited_potion_uses": unlimited_potion_uses,
		"fly_speed": fly_speed,
		"ascend_speed": ascend_speed,
		"grapple_range": grapple_range,
		"grapple_speed": grapple_speed,
		"grapple_duration": grapple_duration,
		"speed_surge_multiplier": speed_surge_multiplier,
		"speed_surge_duration": speed_surge_duration,
		"health_cost_per_sec": health_cost_per_sec,
		"invisible_duration": invisible_duration,
	}
