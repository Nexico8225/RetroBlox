class_name GearData
extends Resource
# Editable Gear Resource saved in res://gears/ — click any .tres file in res://gears/ to edit its variables in Godot Inspector!

@export var gear_id: String = "sword"
@export var gear_name: String = "Linked Sword"
@export var short_name: String = "SWORD"
@export var category: String = "swords"
@export var item_type: int = 5
@export var color: Color = Color("fcc419")
@export var cooldown: float = 1.0
@export var lose_item_when_dead: bool = true
@export var rent_tix: int = 250
@export var buy_tix: int = 250
@export var max_uses: int = -1

@export_group("Melee & Sword Settings")
@export var slash_damage: float = 35.0
@export var lunge_damage: float = 55.0
@export var lunge_cooldown: float = 2.4
@export var sword_range: float = 4.8
@export var lunge_up_boost: float = 22.0
@export var lunge_forward_boost: float = 78.0
@export var lunge_float_duration: float = 0.85
@export var knockback_power: float = 22.0
@export var lifesteal_amount: float = 0.0
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
@export var explosion_radius: float = 12.0
@export var explosion_damage: float = 130.0
@export var explosion_knockback: float = 55.0
@export var tripmine_arm_delay: float = 1.5
@export var bomb_fuse_time: float = 2.5

@export_group("Consumable, Skin & Carpet Settings")
@export var heal_amount: float = 75.0
@export var heal_over_time_duration: float = 1.5
@export var buff_duration: float = 10.0
@export var cola_lunge_boost: float = 42.0
@export var head_scale_multiplier: float = 2.6
@export var big_head_duration: float = 25.0
@export var skin_mode: String = ""
@export var unlimited_potion_uses: bool = true
@export var fly_speed: float = 38.0
@export var ascend_speed: float = 24.0


func to_dictionary() -> Dictionary:
	return {
		"id": gear_id,
		"name": gear_name,
		"short": short_name,
		"category": category,
		"item_type": item_type,
		"color": color,
		"cooldown": cooldown,
		"lose_item_when_dead": lose_item_when_dead,
		"rent_tix": rent_tix,
		"buy_tix": buy_tix,
		"max_uses": max_uses,
		"uses_left": max_uses,
		"slash_damage": slash_damage,
		"lunge_damage": lunge_damage,
		"lunge_cooldown": lunge_cooldown,
		"sword_range": sword_range,
		"lunge_up_boost": lunge_up_boost,
		"lunge_forward_boost": lunge_forward_boost,
		"lunge_float_duration": lunge_float_duration,
		"knockback_power": knockback_power,
		"lifesteal_amount": lifesteal_amount,
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
		"bomb_fuse_time": bomb_fuse_time,
		"heal_amount": heal_amount,
		"heal_over_time_duration": heal_over_time_duration,
		"buff_duration": buff_duration,
		"cola_lunge_boost": cola_lunge_boost,
		"head_scale_multiplier": head_scale_multiplier,
		"big_head_duration": big_head_duration,
		"skin_mode": skin_mode,
		"unlimited_potion_uses": unlimited_potion_uses,
		"fly_speed": fly_speed,
		"ascend_speed": ascend_speed,
	}
