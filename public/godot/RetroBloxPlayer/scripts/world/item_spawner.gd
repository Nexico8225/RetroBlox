class_name ItemSpawner
extends StaticBody3D
# Editable RetroBlox Gear Spawner & Gear Wall Mount.
# By default, spawns random gears from res://gears/ and changes to another gear every time you pick it up!
# You can also select any specific gear in the Inspector or edit the .tres files inside res://gears/.

const STUD_SHADER_PATH: String = "res://assets/studs/part_studs.gdshader"
const STUD_TEX_PATH: String = "res://assets/studs/stud_tile.png"
const STUD_NORM_PATH: String = "res://assets/Materials/Studs 4x4 Normal Plastic.png"

enum ItemType {
	RANDOM_FROM_GEARS_FOLDER = 0,
	SPEED_COIL = 1,
	GRAVITY_COIL = 2,
	FUSION_COIL = 3,
	HEAL_COIL = 4,
	LINKED_SWORD = 5,
	FLAME_SWORD = 6,
	SLOW_SWORD = 7,
	SUPER_SWORD = 8,
	SWELLING_BALL = 9,
	HEALING_POTION = 10,
	BIG_HEAD_POTION = 11,
	FLYING_CARPET = 12,
	HYPERLASER_GUN = 13,
	ROCKET_LAUNCHER = 14,
	SUBSPACE_TRIPMINE = 15,
	GRAPPLER = 16,
	SPICY_SAUCE = 17,
	GHOST_BURGER = 18,
	HAMBURGER = 19,
	SANDWICH = 20,
	BLOXY_COLA = 21,
	GRAPPLER_V2 = 22,
	MEDKIT = 23,
	VENOMSHANK = 24,
	ICEDAGGER = 25,
	WINDFORCE = 26,
	DARKHEART = 27,
	ILLUMINA = 28,
	SLATESKIN_POTION = 29,
	ROCKET_BOOTS = 30
}

@export_group("Gear Spawner Setup")
## Select "Random From Gears Folder" (default) to cycle random gears on every pickup, or choose a specific gear!
@export var item_type: ItemType = ItemType.RANDOM_FROM_GEARS_FOLDER:
	set(v):
		item_type = v
		if is_inside_tree():
			_roll_next_gear()
			_rebuild_visuals()

## Optional: Drag any GearData (.tres) file from res://gears/ here to spawn that exact custom gear resource.
@export var custom_gear_resource: Resource = null:
	set(v):
		custom_gear_resource = v
		if is_inside_tree():
			_roll_next_gear()
			_rebuild_visuals()

## Folder path containing GearData (.tres) files used when spawning random gears.
@export var gears_folder_path: String = "res://gears"

## Optional custom display name override (leave empty to use the gear's name).
@export var custom_item_name: String = ""

## Seconds before the spawner re-enables after pickup (when random, switches to a new gear immediately!).
@export var respawn_cooldown: float = 1.5

## Whether this item is removed from the player's inventory when they die (default: On / true).
@export var lose_item_when_dead: bool = true

## Pad dimensions in studs (or wall mount plaque size when wall_mount is enabled).
@export var pad_size: Vector3 = Vector3(4.0, 0.5, 4.0):
	set(v):
		pad_size = v
		if is_inside_tree():
			_rebuild_visuals()

## Enable for vertical Gear Wall display mounts.
@export var wall_mount: bool = false:
	set(v):
		wall_mount = v
		if is_inside_tree():
			_rebuild_visuals()

@export_group("Editable Weapon & Coil Variables (Overrides)")
## Set to true to override the .tres gear stats with the Inspector values below on this spawner.
@export var use_inspector_stat_overrides: bool = false
@export var weapon_cooldown: float = 0.40
@export var speed_multiplier: float = 2.0
@export var gravity_multiplier: float = 0.35
@export var jump_boost_multiplier: float = 1.40
@export var heal_per_second: float = 16.0
@export var slash_damage: float = 100.0
@export var lunge_damage: float = 150.0
@export var lunge_cooldown: float = 0.85
@export var sword_range: float = 6.8
@export var lunge_forward_boost: float = 44.0
@export var lunge_up_boost: float = 11.0
@export var lunge_duration: float = 0.32
@export var burn_damage_per_sec: float = 20.0
@export var burn_duration: float = 5.0
@export var slow_multiplier: float = 0.25
@export var slow_duration: float = 5.5
@export var min_swell_damage: float = 35.0
@export var max_swell_damage: float = 250.0
@export var max_swell_scale: float = 5.5
@export var max_charge_time: float = 2.4
@export var swell_launch_speed: float = 42.0
@export var heal_amount: float = 65.0
@export var head_scale_multiplier: float = 2.6
@export var big_head_duration: float = 18.0
@export var unlimited_potion_uses: bool = true
@export var fly_speed: float = 38.0
@export var ascend_speed: float = 24.0
@export var projectile_speed: float = 20.0
@export var projectile_damage: float = 9999.0
@export var insta_kill_on_touch: bool = true
@export var explosion_radius: float = 13.0
@export var explosion_damage: float = 150.0
@export var explosion_knockback: float = 48.0
@export var tripmine_arm_delay: float = 1.2

var _cooldown_left: float = 0.0
var _floating_root: Node3D = null
var _label_3d: Label3D = null
var _time: float = 0.0
var _active_resolved_type: int = 5
var _active_gear_dict: Dictionary = {}
var _loaded_folder_gears: Array[Dictionary] = []


func _ready() -> void:
	if not is_in_group("item_spawner"):
		add_to_group("item_spawner")
	_load_gears_folder()
	_roll_next_gear()
	_rebuild_visuals()


func _process(delta: float) -> void:
	_time += delta
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
		if _floating_root != null and is_instance_valid(_floating_root):
			_floating_root.visible = (_cooldown_left <= 0.0)
	if _floating_root != null and is_instance_valid(_floating_root):
		if wall_mount:
			_floating_root.position.z = 0.65 + sin(_time * 2.8) * 0.08
			_floating_root.rotation.y = sin(_time * 1.6) * 0.35
		else:
			_floating_root.position.y = (pad_size.y * 0.5) + 1.55 + sin(_time * 2.8) * 0.22
			_floating_root.rotation.y = _time * 1.45


func _load_gears_folder() -> void:
	_loaded_folder_gears.clear()
	var dir: DirAccess = DirAccess.open(gears_folder_path)
	if dir != null:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and (fn.ends_with(".tres") or fn.ends_with(".res")):
				var full_p: String = gears_folder_path.path_join(fn)
				if ResourceLoader.exists(full_p):
					var res: Resource = load(full_p)
					if res != null and res.has_method("to_dictionary"):
						var d: Dictionary = res.call("to_dictionary")
						if not d.is_empty():
							_loaded_folder_gears.append(d)
			fn = dir.get_next()
		dir.list_dir_end()


func _roll_next_gear() -> void:
	if custom_gear_resource != null and custom_gear_resource.has_method("to_dictionary"):
		_active_gear_dict = (custom_gear_resource.call("to_dictionary") as Dictionary).duplicate(true)
		_active_resolved_type = int(_active_gear_dict.get("item_type", 5))
		return

	if item_type == ItemType.RANDOM_FROM_GEARS_FOLDER:
		if _loaded_folder_gears.is_empty():
			_load_gears_folder()
		if not _loaded_folder_gears.is_empty():
			var candidates: Array[Dictionary] = []
			for g in _loaded_folder_gears:
				if int(g.get("item_type", 5)) != _active_resolved_type or _loaded_folder_gears.size() <= 1:
					candidates.append(g)
			var pick: Dictionary = candidates[randi() % candidates.size()]
			_active_gear_dict = pick.duplicate(true)
			_active_resolved_type = int(_active_gear_dict.get("item_type", 5))
			return
		# Fallback random 1..30 if folder was moved
		var next_t: int = (randi() % 30) + 1
		if next_t == _active_resolved_type:
			next_t = (next_t % 30) + 1
		_active_resolved_type = next_t
		_active_gear_dict = get_default_gear_dict(_active_resolved_type)
	else:
		_active_resolved_type = int(item_type)
		# Try matching from loaded folder gears first so editing res://gears/*.tres affects all spawners!
		if _loaded_folder_gears.is_empty():
			_load_gears_folder()
		for g in _loaded_folder_gears:
			if int(g.get("item_type", -1)) == _active_resolved_type:
				_active_gear_dict = g.duplicate(true)
				return
		_active_gear_dict = get_default_gear_dict(_active_resolved_type)


func can_pickup() -> bool:
	return _cooldown_left <= 0.0


func consume_pickup() -> Dictionary:
	_cooldown_left = maxf(0.15, respawn_cooldown)
	var data: Dictionary = get_item_data()
	if item_type == ItemType.RANDOM_FROM_GEARS_FOLDER:
		# Immediately roll the next random gear so when it pops back up (or on the pad), it's a new gear!
		_roll_next_gear()
		_rebuild_visuals()
	if _floating_root != null and is_instance_valid(_floating_root):
		_floating_root.visible = false
	return data


static func get_default_gear_dict(t: int) -> Dictionary:
	var id_str: String = get_type_id(t)
	var name_str: String = get_default_item_name(t)
	var short_str: String = get_short_label(t)
	var col: Color = get_item_color(t)
	var d: Dictionary = {
		"id": id_str,
		"name": name_str,
		"short": short_str,
		"item_type": t,
		"color": col,
		"cooldown": 0.35,
		"lose_item_when_dead": true,
		"speed_multiplier": 2.0 if t in [1, 3] else (1.25 if t == 26 else (1.32 if t == 28 else (1.35 if t == 30 else 1.0))),
		"gravity_multiplier": 0.35 if t in [2, 3] else (0.62 if t == 26 else (0.55 if t == 28 else (0.50 if t == 30 else 1.0))),
		"jump_boost_multiplier": 1.40 if t in [2, 3] else (1.28 if t == 26 else (1.35 if t == 28 else (1.45 if t == 30 else 1.0))),
		"heal_per_second": 16.0 if t == 4 else 0.0,
		"slash_damage": 150.0 if t == 8 else (45.0 if t == 6 else (50.0 if t == 7 else (38.0 if t == 24 else (45.0 if t == 25 else (36.0 if t == 26 else (42.0 if t == 27 else (48.0 if t == 28 else 35.0))))))),
		"lunge_damage": 300.0 if t == 8 else (75.0 if t == 6 else (85.0 if t == 7 else (62.0 if t == 24 else (999.0 if t == 25 else (58.0 if t == 26 else (68.0 if t == 27 else (80.0 if t == 28 else 55.0))))))),
		"lunge_cooldown": 1.0 if t == 8 else (1.9 if t == 28 else 2.2),
		"sword_range": 10.5 if t == 8 else (6.2 if t == 28 else 5.4),
		"lunge_forward_boost": 96.0 if t == 8 else 0.0,
		"lunge_up_boost": 18.0 if t == 8 else (38.0 if t == 28 else (34.0 if t == 26 else 28.0)),
		"lunge_duration": 0.52 if t == 8 else (0.85 if t == 28 else 0.65),
		"grapple_range": 150.0 if t == 22 else 95.0,
		"grapple_speed": 235.0 if t == 22 else 165.0,
		"grapple_duration": 0.95 if t == 22 else 0.85,
		"speed_surge_multiplier": 3.0 if t == 17 else (1.22 if t == 21 else 1.0),
		"speed_surge_duration": 10.0 if t == 17 else (8.0 if t == 21 else 0.0),
		"health_cost_per_sec": 4.0 if t == 17 else 0.0,
		"invisible_duration": 8.0 if t == 18 else 0.0,
		"burn_damage_per_sec": 20.0 if t == 6 else (16.0 if t == 24 else 0.0),
		"burn_duration": 5.0 if t == 6 else (5.5 if t == 24 else 0.0),
		"slow_multiplier": 0.25 if t == 7 else (0.15 if t == 25 else 1.0),
		"slow_duration": 5.5 if t == 7 else (4.5 if t == 25 else 0.0),
		"min_swell_damage": 35.0,
		"max_swell_damage": 250.0,
		"max_swell_scale": 5.5,
		"max_charge_time": 2.4,
		"swell_launch_speed": 42.0,
		"heal_amount": 85.0 if t == 23 else (65.0 if t in [10, 11] else (25.0 if t in [27, 29] else (10.0 if t == 18 else (30.0 if t == 19 else (45.0 if t == 20 else (12.0 if t == 21 else 0.0)))))),
		"head_scale_multiplier": 2.6,
		"big_head_duration": 18.0 if t == 11 else 12.0,
		"unlimited_potion_uses": true,
		"fly_speed": 38.0,
		"ascend_speed": 34.0 if t == 30 else 24.0,
		"projectile_speed": 20.0 if t == 13 else 58.0,
		"projectile_damage": 9999.0,
		"insta_kill_on_touch": true,
		"explosion_radius": 16.0 if t == 15 else 13.0,
		"explosion_damage": 150.0,
		"explosion_knockback": 62.0 if t == 15 else 48.0,
		"tripmine_arm_delay": 1.2,
	}
	if t == 13:
		d["cooldown"] = 0.85
	elif t == 14:
		d["cooldown"] = 1.2
	elif t == 15:
		d["cooldown"] = 1.0
	elif t == 9:
		d["cooldown"] = 0.75
	elif t in [10, 11]:
		d["cooldown"] = 1.1
	elif t == 16:
		d["cooldown"] = 1.1
	elif t == 22:
		d["cooldown"] = 0.65
	elif t == 23:
		d["cooldown"] = 2.0
	elif t == 29:
		d["cooldown"] = 3.0
	elif t == 17:
		d["cooldown"] = 1.2
	elif t == 18:
		d["cooldown"] = 1.0
	elif t in [19, 20, 21]:
		d["cooldown"] = 1.2
	return d


func get_item_data() -> Dictionary:
	if _active_gear_dict.is_empty():
		_roll_next_gear()
	var d: Dictionary = _active_gear_dict.duplicate(true)
	if custom_item_name.strip_edges() != "":
		d["name"] = custom_item_name.strip_edges()
	d["lose_item_when_dead"] = lose_item_when_dead
	if use_inspector_stat_overrides:
		d["cooldown"] = weapon_cooldown
		d["speed_multiplier"] = speed_multiplier
		d["gravity_multiplier"] = gravity_multiplier
		d["jump_boost_multiplier"] = jump_boost_multiplier
		d["heal_per_second"] = heal_per_second
		d["slash_damage"] = slash_damage
		d["lunge_damage"] = lunge_damage
		d["lunge_cooldown"] = lunge_cooldown
		d["sword_range"] = sword_range
		d["lunge_forward_boost"] = lunge_forward_boost
		d["lunge_up_boost"] = lunge_up_boost
		d["lunge_duration"] = lunge_duration
		d["burn_damage_per_sec"] = burn_damage_per_sec
		d["burn_duration"] = burn_duration
		d["slow_multiplier"] = slow_multiplier
		d["slow_duration"] = slow_duration
		d["min_swell_damage"] = min_swell_damage
		d["max_swell_damage"] = max_swell_damage
		d["max_swell_scale"] = max_swell_scale
		d["max_charge_time"] = max_charge_time
		d["swell_launch_speed"] = swell_launch_speed
		d["heal_amount"] = heal_amount
		d["head_scale_multiplier"] = head_scale_multiplier
		d["big_head_duration"] = big_head_duration
		d["unlimited_potion_uses"] = unlimited_potion_uses
		d["fly_speed"] = fly_speed
		d["ascend_speed"] = ascend_speed
		d["projectile_speed"] = projectile_speed
		d["projectile_damage"] = projectile_damage
		d["insta_kill_on_touch"] = insta_kill_on_touch
		d["explosion_radius"] = explosion_radius
		d["explosion_damage"] = explosion_damage
		d["explosion_knockback"] = explosion_knockback
		d["tripmine_arm_delay"] = tripmine_arm_delay
	return d


static func get_type_from_id(id_str: String) -> int:
	match id_str:
		"speed_coil": return 1
		"gravity_coil": return 2
		"fusion_coil": return 3
		"heal_coil": return 4
		"sword": return 5
		"flame_sword": return 6
		"slow_sword": return 7
		"super_sword": return 8
		"swelling_ball": return 9
		"healing_potion": return 10
		"big_head_potion": return 11
		"flying_carpet": return 12
		"laser_gun": return 13
		"rocket_launcher": return 14
		"subspace_tripmine": return 15
		"grappler": return 16
		"spicy_sauce": return 17
		"ghost_burger": return 18
		"hamburger": return 19
		"sandwich": return 20
		"bloxy_cola": return 21
		"grappler_v2": return 22
		"medkit": return 23
		"venomshank": return 24
		"icedagger": return 25
		"windforce": return 26
		"darkheart": return 27
		"illumina": return 28
		"slateskin_potion": return 29
		"rocket_boots": return 30
	return 5


static func get_type_id(t: int) -> String:
	match t:
		1: return "speed_coil"
		2: return "gravity_coil"
		3: return "fusion_coil"
		4: return "heal_coil"
		5: return "sword"
		6: return "flame_sword"
		7: return "slow_sword"
		8: return "super_sword"
		9: return "swelling_ball"
		10: return "healing_potion"
		11: return "big_head_potion"
		12: return "flying_carpet"
		13: return "laser_gun"
		14: return "rocket_launcher"
		15: return "subspace_tripmine"
		16: return "grappler"
		17: return "spicy_sauce"
		18: return "ghost_burger"
		19: return "hamburger"
		20: return "sandwich"
		21: return "bloxy_cola"
		22: return "grappler_v2"
		23: return "medkit"
		24: return "venomshank"
		25: return "icedagger"
		26: return "windforce"
		27: return "darkheart"
		28: return "illumina"
		29: return "slateskin_potion"
		30: return "rocket_boots"
	return "sword"


static func get_default_item_name(t: int) -> String:
	match t:
		1: return "Speed Coil"
		2: return "Gravity Coil"
		3: return "Fusion Coil"
		4: return "Heal Coil"
		5: return "Linked Sword"
		6: return "Flame Sword (Firebrand)"
		7: return "Slow Sword"
		8: return "Super Sword"
		9: return "Swelling Ball"
		10: return "Healing Potion"
		11: return "Big Head Potion"
		12: return "Flying Carpet"
		13: return "Hyperlaser Gun"
		14: return "Rocket Launcher"
		15: return "Subspace Tripmine"
		16: return "Grappler V1"
		17: return "Spicy Sauce"
		18: return "Ghost Burger"
		19: return "Hamburger"
		20: return "Sandwich"
		21: return "Bloxy Cola"
		22: return "Grappler V2 (Hyper)"
		23: return "Medkit"
		24: return "Venomshank"
		25: return "Icedagger"
		26: return "Windforce"
		27: return "Darkheart"
		28: return "Illumina"
		29: return "Slateskin Potion"
		30: return "Rocket Boots"
	return "Linked Sword"


static func get_short_label(t: int) -> String:
	match t:
		1: return "SPEED"
		2: return "GRAV"
		3: return "FUSION"
		4: return "HEALCOIL"
		5: return "SWORD"
		6: return "FLAME"
		7: return "SLOW"
		8: return "SUPER"
		9: return "SWELL"
		10: return "HEAL"
		11: return "BIGHEAD"
		12: return "CARPET"
		13: return "LASER"
		14: return "ROCKET"
		15: return "TRIPMINE"
		16: return "GRAP V1"
		17: return "SPICY"
		18: return "GHOST"
		19: return "BURGER"
		20: return "SANDWICH"
		21: return "COLA"
		22: return "GRAP V2"
		23: return "MEDKIT"
		24: return "VENOM"
		25: return "ICEDAG"
		26: return "WIND"
		27: return "DARK"
		28: return "ILLUMINA"
		29: return "SLATE"
		30: return "BOOTS"
	return "ITEM"


static func get_item_color(t: int) -> Color:
	match t:
		1: return Color("ff3b30")
		2: return Color("339af0")
		3: return Color("be4bdb")
		4: return Color("40c057")
		5: return Color("fcc419")
		6: return Color("ff5c00")
		7: return Color("22b8cf")
		8: return Color("ffd43b")
		9: return Color("f06595")
		10: return Color("40c057")
		11: return Color("be4bdb")
		12: return Color("f59f00")
		13: return Color("00e5ff")
		14: return Color("ff5252")
		15: return Color("ff00aa")
		16: return Color("c0eb75")
		17: return Color("ff6b35")
		18: return Color("9be7ff")
		19: return Color("f59f00")
		20: return Color("ffe066")
		21: return Color("e03131")
		22: return Color("00e5ff")
		23: return Color("f03e3e")
		24: return Color("51cf66")
		25: return Color("339af0")
		26: return Color("74c0fc")
		27: return Color("ae3ec9")
		28: return Color("faa2c1")
		29: return Color("868e96")
		30: return Color("fd7e14")
	return Color.WHITE


func _rebuild_visuals() -> void:
	for ch in get_children():
		if bool(ch.get_meta("_spawner_generated", false)):
			ch.queue_free()

	var resolved_t: int = _active_resolved_type if _active_resolved_type >= 1 else 5
	var col_color: Color = get_item_color(resolved_t)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.set_meta("_spawner_generated", true)
	var bshape: BoxShape3D = BoxShape3D.new()
	bshape.size = Vector3(2.8, 2.8, 1.2) if wall_mount else pad_size
	col.shape = bshape
	add_child(col)

	var pad_mi: MeshInstance3D = MeshInstance3D.new()
	pad_mi.set_meta("_spawner_generated", true)
	var bmesh: BoxMesh = BoxMesh.new()
	bmesh.size = Vector3(2.6, 2.6, 0.22) if wall_mount else pad_size
	pad_mi.mesh = bmesh

	if ResourceLoader.exists(STUD_SHADER_PATH):
		var smat: ShaderMaterial = ShaderMaterial.new()
		smat.shader = load(STUD_SHADER_PATH) as Shader
		smat.set_shader_parameter("albedo", col_color.darkened(0.15))
		if ResourceLoader.exists(STUD_TEX_PATH):
			var st: Texture2D = load(STUD_TEX_PATH) as Texture2D
			smat.set_shader_parameter("stud_tex", st)
		if ResourceLoader.exists(STUD_NORM_PATH):
			var sn: Texture2D = load(STUD_NORM_PATH) as Texture2D
			smat.set_shader_parameter("stud_normal_tex", sn)
		smat.set_shader_parameter("stud_density", 1.0)
		smat.set_shader_parameter("normal_depth", 1.35)
		smat.set_shader_parameter("roughness_val", 0.35)
		smat.set_shader_parameter("specular_val", 0.55)
		smat.set_shader_parameter("stud_full", false)
		smat.set_shader_parameter("stud_top", true)
		smat.set_shader_parameter("stud_bottom", false)
		smat.set_shader_parameter("stud_left", false)
		smat.set_shader_parameter("stud_right", false)
		smat.set_shader_parameter("stud_front", wall_mount)
		smat.set_shader_parameter("stud_back", false)
		pad_mi.material_override = smat
	else:
		var std: StandardMaterial3D = StandardMaterial3D.new()
		std.albedo_color = col_color.darkened(0.15)
		pad_mi.material_override = std
	add_child(pad_mi)

	if not wall_mount:
		var ring_mi: MeshInstance3D = MeshInstance3D.new()
		ring_mi.set_meta("_spawner_generated", true)
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = minf(pad_size.x, pad_size.z) * 0.40
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.06
		ring_mi.mesh = cyl
		ring_mi.position = Vector3(0.0, pad_size.y * 0.5 + 0.04, 0.0)
		var rmat: StandardMaterial3D = StandardMaterial3D.new()
		rmat.albedo_color = col_color
		rmat.emission_enabled = true
		rmat.emission = col_color
		rmat.emission_energy_multiplier = 0.65
		ring_mi.material_override = rmat
		add_child(ring_mi)

	_floating_root = build_item_mesh_3d(resolved_t)
	_floating_root.set_meta("_spawner_generated", true)
	if wall_mount:
		_floating_root.position = Vector3(0.0, 0.0, 0.65)
	else:
		_floating_root.position = Vector3(0.0, pad_size.y * 0.5 + 1.55, 0.0)
	add_child(_floating_root)

	_label_3d = Label3D.new()
	_label_3d.set_meta("_spawner_generated", true)
	var disp_name: String = custom_item_name.strip_edges() if custom_item_name.strip_edges() != "" else String(_active_gear_dict.get("name", get_default_item_name(resolved_t)))
	if item_type == ItemType.RANDOM_FROM_GEARS_FOLDER and custom_gear_resource == null:
		_label_3d.text = "🎲 [ID %d] %s" % [resolved_t, disp_name]
	else:
		_label_3d.text = "[ID %d] %s" % [resolved_t, disp_name]
	_label_3d.font_size = 28 if wall_mount else 34
	_label_3d.outline_size = 10
	_label_3d.modulate = col_color.lightened(0.35)
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if wall_mount:
		_label_3d.position = Vector3(0.0, 1.55, 0.45)
	else:
		_label_3d.position = Vector3(0.0, pad_size.y * 0.5 + 3.05, 0.0)
	add_child(_label_3d)


static func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func build_item_mesh_3d(t: int) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "ItemVisual3D"
	var c: Color = get_item_color(t)

	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color = c
	glow_mat.metallic = 0.35
	glow_mat.roughness = 0.22
	glow_mat.emission_enabled = true
	glow_mat.emission = c
	glow_mat.emission_energy_multiplier = 0.45

	if t in [1, 2, 3, 4]:
		# Helical Spring Coils: radius = 0.78 so it wraps clearly OUTSIDE the 1.0x1.0 R6 Right Arm!
		var num_turns: int = 4
		var segs_per_turn: int = 12
		var total_segs: int = num_turns * segs_per_turn
		var radius: float = 0.78
		var height: float = 1.45
		var mat_a: StandardMaterial3D = glow_mat.duplicate() as StandardMaterial3D
		mat_a.emission_energy_multiplier = 0.95
		var mat_b: StandardMaterial3D = mat_a
		if t == 3:
			mat_a = StandardMaterial3D.new()
			mat_a.albedo_color = Color("ff3b30")
			mat_a.emission_enabled = true
			mat_a.emission = Color("ff3b30")
			mat_a.emission_energy_multiplier = 0.95
			mat_b = StandardMaterial3D.new()
			mat_b.albedo_color = Color("339af0")
			mat_b.emission_enabled = true
			mat_b.emission = Color("339af0")
			mat_b.emission_energy_multiplier = 0.95

		for i in range(total_segs):
			var frac: float = float(i) / float(total_segs)
			var ang: float = frac * float(num_turns) * TAU
			var py: float = -height * 0.5 + frac * height
			var px: float = cos(ang) * radius
			var pz: float = sin(ang) * radius
			var seg_mesh: SphereMesh = SphereMesh.new()
			seg_mesh.radius = 0.17
			seg_mesh.height = 0.34
			var use_mat: StandardMaterial3D = mat_a if (i % 2 == 0) else mat_b
			_add_part(root, seg_mesh, use_mat, Vector3(px, py, pz))

	elif t in [5, 6, 7, 8, 24, 25, 26, 27, 28]:
		# Swords: Linked (5), Flame (6), Slow (7), Super (8), Venomshank (24), Icedagger (25), Windforce (26), Darkheart (27), Illumina (28)
		var scale_mult: float = 1.48 if t == 8 else (0.78 if t == 25 else (1.12 if t == 28 else 1.0))
		var gold_mat: StandardMaterial3D = StandardMaterial3D.new()
		gold_mat.albedo_color = Color("ff5c00") if t == 6 else (Color("22b8cf") if t in [7, 25] else (Color("51cf66") if t == 24 else (Color("74c0fc") if t == 26 else (Color("ae3ec9") if t == 27 else (Color("faa2c1") if t == 28 else Color("fcc419"))))))
		gold_mat.metallic = 0.85
		gold_mat.roughness = 0.18
		if t in [6, 7, 8, 24, 25, 26, 27, 28]:
			gold_mat.emission_enabled = true
			gold_mat.emission = gold_mat.albedo_color
			gold_mat.emission_energy_multiplier = 0.55

		var grip_mat: StandardMaterial3D = StandardMaterial3D.new()
		grip_mat.albedo_color = Color("7f1d1d") if t == 6 else (Color("0c4a6e") if t in [7, 25] else (Color("1b4332") if t == 24 else (Color("1864ab") if t == 26 else (Color("212529") if t == 27 else (Color("a61e4d") if t == 28 else (Color("5f3dc4") if t == 8 else Color("1864ab")))))))
		grip_mat.roughness = 0.55

		var blade_mat: StandardMaterial3D = StandardMaterial3D.new()
		if t == 6:
			blade_mat.albedo_color = Color("ff4500")
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("ff6b00")
			blade_mat.emission_energy_multiplier = 1.15
		elif t in [7, 25]:
			blade_mat.albedo_color = Color("339af0") if t == 25 else Color("66d9e8")
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("74c0fc") if t == 25 else Color("22b8cf")
			blade_mat.emission_energy_multiplier = 1.15 if t == 25 else 0.95
		elif t == 24:
			blade_mat.albedo_color = Color("2f9e44")
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("51cf66")
			blade_mat.emission_energy_multiplier = 1.1
		elif t == 26:
			blade_mat.albedo_color = Color("74c0fc")
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("a5d8ff")
			blade_mat.emission_energy_multiplier = 1.0
		elif t == 27:
			blade_mat.albedo_color = Color("1f1924")
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("9c36b5")
			blade_mat.emission_energy_multiplier = 1.2
		elif t == 28:
			blade_mat.albedo_color = Color("fcc2d7")
			blade_mat.metallic = 0.95
			blade_mat.roughness = 0.08
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("ffdeeb")
			blade_mat.emission_energy_multiplier = 1.4
		elif t == 8:
			blade_mat.albedo_color = Color("ffd43b")
			blade_mat.metallic = 0.9
			blade_mat.roughness = 0.12
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("fcc419")
			blade_mat.emission_energy_multiplier = 0.85
		else:
			blade_mat.albedo_color = Color("e9ecef")
			blade_mat.metallic = 0.92
			blade_mat.roughness = 0.12

		var pommel: SphereMesh = SphereMesh.new()
		pommel.radius = 0.16 * scale_mult
		pommel.height = 0.32 * scale_mult
		_add_part(root, pommel, gold_mat, Vector3(0.0, -1.18 * scale_mult, 0.0))

		var grip: CylinderMesh = CylinderMesh.new()
		grip.top_radius = 0.095 * scale_mult
		grip.bottom_radius = 0.095 * scale_mult
		grip.height = 0.66 * scale_mult
		_add_part(root, grip, grip_mat, Vector3(0.0, -0.78 * scale_mult, 0.0))

		var guard: BoxMesh = BoxMesh.new()
		guard.size = Vector3(0.96 * scale_mult, 0.16 * scale_mult, 0.24 * scale_mult)
		_add_part(root, guard, gold_mat, Vector3(0.0, -0.40 * scale_mult, 0.0))

		for dir_s in [-1.0, 1.0]:
			var g_tip: SphereMesh = SphereMesh.new()
			g_tip.radius = 0.12 * scale_mult
			g_tip.height = 0.24 * scale_mult
			_add_part(root, g_tip, gold_mat, Vector3(dir_s * 0.48 * scale_mult, -0.40 * scale_mult, 0.0))

		var blade: BoxMesh = BoxMesh.new()
		blade.size = Vector3(0.24 * scale_mult, 1.85 * scale_mult, 0.07 * scale_mult)
		_add_part(root, blade, blade_mat, Vector3(0.0, 0.60 * scale_mult, 0.0))

		var tip: PrismMesh = PrismMesh.new()
		tip.size = Vector3(0.24 * scale_mult, 0.42 * scale_mult, 0.07 * scale_mult)
		_add_part(root, tip, blade_mat, Vector3(0.0, 1.73 * scale_mult, 0.0))

	elif t == 9:
		# Swelling Ball (glowing pink-magenta energy sphere + dual rings)
		var core_sph: SphereMesh = SphereMesh.new()
		core_sph.radius = 0.52
		core_sph.height = 1.04
		var s_mat: StandardMaterial3D = StandardMaterial3D.new()
		s_mat.albedo_color = Color("f06595")
		s_mat.emission_enabled = true
		s_mat.emission = Color("ff007f")
		s_mat.emission_energy_multiplier = 1.25
		_add_part(root, core_sph, s_mat)

		var ring_tor: TorusMesh = TorusMesh.new()
		ring_tor.inner_radius = 0.60
		ring_tor.outer_radius = 0.68
		_add_part(root, ring_tor, glow_mat, Vector3.ZERO, Vector3(35.0, 0.0, 25.0))
		_add_part(root, ring_tor, glow_mat, Vector3.ZERO, Vector3(-35.0, 45.0, -25.0))

	elif t in [10, 11, 29]:
		var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
		glass_mat.albedo_color = Color(0.88, 0.96, 1.0, 0.38)
		glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass_mat.roughness = 0.08
		glass_mat.metallic = 0.2

		var flask_outer: SphereMesh = SphereMesh.new()
		flask_outer.radius = 0.56
		flask_outer.height = 1.12
		_add_part(root, flask_outer, glass_mat, Vector3(0.0, -0.18, 0.0))

		var liquid_inner: SphereMesh = SphereMesh.new()
		liquid_inner.radius = 0.46
		liquid_inner.height = 0.92
		_add_part(root, liquid_inner, glow_mat, Vector3(0.0, -0.22, 0.0))

		var neck: CylinderMesh = CylinderMesh.new()
		neck.top_radius = 0.20
		neck.bottom_radius = 0.24
		neck.height = 0.46
		_add_part(root, neck, glass_mat, Vector3(0.0, 0.46, 0.0))

		var cork: CylinderMesh = CylinderMesh.new()
		cork.top_radius = 0.22
		cork.bottom_radius = 0.17
		cork.height = 0.24
		var cork_mat: StandardMaterial3D = StandardMaterial3D.new()
		cork_mat.albedo_color = Color("a66321")
		cork_mat.roughness = 0.85
		_add_part(root, cork, cork_mat, Vector3(0.0, 0.72, 0.0))

	elif t == 12:
		var colors: Array[Color] = [
			Color("e03131"), Color("f76707"), Color("fcc419"),
			Color("2f9e44"), Color("1971c2"), Color("9c36b5")
		]
		var stripe_w: float = 2.1 / float(colors.size())
		for i in range(colors.size()):
			var sm: StandardMaterial3D = StandardMaterial3D.new()
			sm.albedo_color = colors[i]
			sm.roughness = 0.55
			var sbox: BoxMesh = BoxMesh.new()
			sbox.size = Vector3(stripe_w, 0.12, 1.55)
			var sx: float = -1.05 + stripe_w * (float(i) + 0.5)
			_add_part(root, sbox, sm, Vector3(sx, 0.0, 0.0))
		var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
		trim_mat.albedo_color = Color("fcc419")
		trim_mat.metallic = 0.7
		trim_mat.roughness = 0.25
		for c_pos in [Vector3(-1.05, 0.0, -0.78), Vector3(1.05, 0.0, -0.78), Vector3(-1.05, 0.0, 0.78), Vector3(1.05, 0.0, 0.78)]:
			var tassel: SphereMesh = SphereMesh.new()
			tassel.radius = 0.14
			tassel.height = 0.28
			_add_part(root, tassel, trim_mat, c_pos)

	elif t == 13:
		var gun_dark: StandardMaterial3D = StandardMaterial3D.new()
		gun_dark.albedo_color = Color("212529")
		gun_dark.metallic = 0.75
		gun_dark.roughness = 0.28

		var body_box: BoxMesh = BoxMesh.new()
		body_box.size = Vector3(0.28, 0.36, 1.15)
		_add_part(root, body_box, gun_dark, Vector3(0.0, 0.10, 0.0))

		var barrel_cyl: CylinderMesh = CylinderMesh.new()
		barrel_cyl.top_radius = 0.09
		barrel_cyl.bottom_radius = 0.11
		barrel_cyl.height = 0.95
		_add_part(root, barrel_cyl, glow_mat, Vector3(0.0, 0.14, -0.75), Vector3(90.0, 0.0, 0.0))

		for r_idx in range(3):
			var coil_ring: TorusMesh = TorusMesh.new()
			coil_ring.inner_radius = 0.11
			coil_ring.outer_radius = 0.17
			_add_part(root, coil_ring, glow_mat, Vector3(0.0, 0.14, -0.45 - float(r_idx) * 0.26), Vector3(90.0, 0.0, 0.0))

		var grip_box: BoxMesh = BoxMesh.new()
		grip_box.size = Vector3(0.22, 0.52, 0.26)
		_add_part(root, grip_box, gun_dark, Vector3(0.0, -0.26, 0.28), Vector3(18.0, 0.0, 0.0))

	elif t == 14:
		var rpg_tube_mat: StandardMaterial3D = StandardMaterial3D.new()
		rpg_tube_mat.albedo_color = Color("3b4252")
		rpg_tube_mat.metallic = 0.68
		rpg_tube_mat.roughness = 0.32

		var red_warhead_mat: StandardMaterial3D = StandardMaterial3D.new()
		red_warhead_mat.albedo_color = Color("e03131")
		red_warhead_mat.emission_enabled = true
		red_warhead_mat.emission = Color("e03131")
		red_warhead_mat.emission_energy_multiplier = 0.35

		var tube: CylinderMesh = CylinderMesh.new()
		tube.top_radius = 0.22
		tube.bottom_radius = 0.22
		tube.height = 2.15
		_add_part(root, tube, rpg_tube_mat, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))

		var bell: CylinderMesh = CylinderMesh.new()
		bell.top_radius = 0.22
		bell.bottom_radius = 0.32
		bell.height = 0.36
		_add_part(root, bell, rpg_tube_mat, Vector3(0.0, 0.0, 1.15), Vector3(90.0, 0.0, 0.0))

		var warhead: CylinderMesh = CylinderMesh.new()
		warhead.top_radius = 0.02
		warhead.bottom_radius = 0.24
		warhead.height = 0.48
		_add_part(root, warhead, red_warhead_mat, Vector3(0.0, 0.0, -1.25), Vector3(-90.0, 0.0, 0.0))

		var f_grip: BoxMesh = BoxMesh.new()
		f_grip.size = Vector3(0.18, 0.48, 0.22)
		_add_part(root, f_grip, rpg_tube_mat, Vector3(0.0, -0.34, -0.35), Vector3(12.0, 0.0, 0.0))

	elif t in [16, 22]:
		# Grappler V1 (16, lime) & Grappler V2 (22, hyper cyan)
		var g_col_v: Color = Color("00e5ff") if t == 22 else Color("c0eb75")
		var g_metal: StandardMaterial3D = StandardMaterial3D.new()
		g_metal.albedo_color = g_col_v
		g_metal.metallic = 0.85
		g_metal.roughness = 0.20
		g_metal.emission_enabled = true
		g_metal.emission = g_col_v
		g_metal.emission_energy_multiplier = 0.95 if t == 22 else 0.45

		var shank: BoxMesh = BoxMesh.new()
		shank.size = Vector3(0.26, 1.25, 0.26) if t == 22 else Vector3(0.24, 1.15, 0.24)
		_add_part(root, shank, g_metal, Vector3(0.0, 0.15, 0.0))

		var bend: TorusMesh = TorusMesh.new()
		bend.inner_radius = 0.34
		bend.outer_radius = 0.50 if t == 22 else 0.48
		_add_part(root, bend, g_metal, Vector3(0.0, 0.86, 0.0), Vector3(90.0, 0.0, 0.0))

		for p_idx in range(4 if t == 22 else 3):
			var prong: BoxMesh = BoxMesh.new()
			prong.size = Vector3(0.12, 0.62 if t == 22 else 0.55, 0.12)
			var ang_off: float = float(p_idx) * (90.0 if t == 22 else 120.0)
			_add_part(root, prong, g_metal, Vector3(cos(deg_to_rad(ang_off)) * 0.34, 1.16, sin(deg_to_rad(ang_off)) * 0.34), Vector3(0.0, ang_off, -20.0))

		var spool: CylinderMesh = CylinderMesh.new()
		spool.top_radius = 0.36
		spool.bottom_radius = 0.36
		spool.height = 0.30
		var spool_mat: StandardMaterial3D = StandardMaterial3D.new()
		spool_mat.albedo_color = Color("1f2937") if t == 22 else Color("495057")
		spool_mat.roughness = 0.6
		_add_part(root, spool, spool_mat, Vector3(0.0, -0.78, 0.0), Vector3(90.0, 0.0, 0.0))

		for r_idx2 in range(3):
			var rope_ring: TorusMesh = TorusMesh.new()
			rope_ring.inner_radius = 0.30
			rope_ring.outer_radius = 0.44
			var rope_mat: StandardMaterial3D = StandardMaterial3D.new()
			rope_mat.albedo_color = Color("99e9f2") if t == 22 else Color("e9fac8")
			rope_mat.roughness = 0.85
			_add_part(root, rope_ring, rope_mat, Vector3(0.0, -1.02 + float(r_idx2) * 0.16, 0.0), Vector3(90.0, 0.0, 0.0))

	elif t == 23:
		# Medkit: classic white first-aid case with glowing red cross + handle
		var case_mat: StandardMaterial3D = StandardMaterial3D.new()
		case_mat.albedo_color = Color("f8f9fa")
		case_mat.roughness = 0.35
		var cross_mat: StandardMaterial3D = StandardMaterial3D.new()
		cross_mat.albedo_color = Color("e03131")
		cross_mat.emission_enabled = true
		cross_mat.emission = Color("ff4d4d")
		cross_mat.emission_energy_multiplier = 0.65

		var box_m: BoxMesh = BoxMesh.new()
		box_m.size = Vector3(1.45, 1.05, 0.55)
		_add_part(root, box_m, case_mat, Vector3.ZERO)

		var ch_v: BoxMesh = BoxMesh.new()
		ch_v.size = Vector3(0.24, 0.68, 0.60)
		_add_part(root, ch_v, cross_mat, Vector3.ZERO)

		var ch_h: BoxMesh = BoxMesh.new()
		ch_h.size = Vector3(0.68, 0.24, 0.60)
		_add_part(root, ch_h, cross_mat, Vector3.ZERO)

		var h_mat: StandardMaterial3D = StandardMaterial3D.new()
		h_mat.albedo_color = Color("343a40")
		var handle_top: BoxMesh = BoxMesh.new()
		handle_top.size = Vector3(0.56, 0.12, 0.16)
		_add_part(root, handle_top, h_mat, Vector3(0.0, 0.64, 0.0))

	elif t == 30:
		# Rocket Boots: twin jet thruster boots with glowing orange exhaust cones
		var boot_mat: StandardMaterial3D = StandardMaterial3D.new()
		boot_mat.albedo_color = Color("fd7e14")
		boot_mat.metallic = 0.65
		boot_mat.roughness = 0.28
		var flame_mat: StandardMaterial3D = StandardMaterial3D.new()
		flame_mat.albedo_color = Color("ffd43b")
		flame_mat.emission_enabled = true
		flame_mat.emission = Color("ff6b00")
		flame_mat.emission_energy_multiplier = 1.4
		for side_x in [-0.42, 0.42]:
			var boot_cyl: CylinderMesh = CylinderMesh.new()
			boot_cyl.top_radius = 0.26
			boot_cyl.bottom_radius = 0.30
			boot_cyl.height = 0.95
			_add_part(root, boot_cyl, boot_mat, Vector3(float(side_x), 0.10, 0.0))
			var toe: BoxMesh = BoxMesh.new()
			toe.size = Vector3(0.50, 0.34, 0.78)
			_add_part(root, toe, boot_mat, Vector3(float(side_x), -0.25, -0.15))
			var jet: CylinderMesh = CylinderMesh.new()
			jet.top_radius = 0.14
			jet.bottom_radius = 0.28
			jet.height = 0.45
			_add_part(root, jet, flame_mat, Vector3(float(side_x), -0.65, 0.05))

	elif t == 17:
		# Spicy Sauce: squat bottle with a molten glow
		var sauce_mat: StandardMaterial3D = StandardMaterial3D.new()
		sauce_mat.albedo_color = Color("ff6b35")
		sauce_mat.emission_enabled = true
		sauce_mat.emission = Color("e8590c")
		sauce_mat.emission_energy_multiplier = 0.75
		sauce_mat.roughness = 0.2

		var bottle: CylinderMesh = CylinderMesh.new()
		bottle.top_radius = 0.42
		bottle.bottom_radius = 0.52
		bottle.height = 1.35
		_add_part(root, bottle, sauce_mat, Vector3(0.0, -0.05, 0.0))

		var neck: CylinderMesh = CylinderMesh.new()
		neck.top_radius = 0.20
		neck.bottom_radius = 0.30
		neck.height = 0.45
		_add_part(root, neck, sauce_mat, Vector3(0.0, 0.80, 0.0))

		var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
		cap_mat.albedo_color = Color("c92a2a")
		cap_mat.metallic = 0.6
		cap_mat.roughness = 0.3
		var cap: CylinderMesh = CylinderMesh.new()
		cap.top_radius = 0.24
		cap.bottom_radius = 0.24
		cap.height = 0.22
		_add_part(root, cap, cap_mat, Vector3(0.0, 1.10, 0.0))

		var label: CylinderMesh = CylinderMesh.new()
		label.top_radius = 0.44
		label.bottom_radius = 0.54
		label.height = 0.42
		var label_mat: StandardMaterial3D = StandardMaterial3D.new()
		label_mat.albedo_color = Color("fff3bf")
		label_mat.roughness = 0.7
		_add_part(root, label, label_mat, Vector3(0.0, -0.10, 0.0))

	elif t == 18:
		# Ghost Burger: see-through ghost-white burger
		var ghost_mat: StandardMaterial3D = StandardMaterial3D.new()
		ghost_mat.albedo_color = Color(0.72, 0.94, 1.0, 0.55)
		ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_mat.emission_enabled = true
		ghost_mat.emission = Color("9be7ff")
		ghost_mat.emission_energy_multiplier = 0.9
		ghost_mat.roughness = 0.15

		var top_bun: SphereMesh = SphereMesh.new()
		top_bun.radius = 0.72
		top_bun.height = 0.78
		_add_part(root, top_bun, ghost_mat, Vector3(0.0, 0.42, 0.0), Vector3.ZERO)

		var bottom_bun: SphereMesh = SphereMesh.new()
		bottom_bun.radius = 0.68
		bottom_bun.height = 0.46
		_add_part(root, bottom_bun, ghost_mat, Vector3(0.0, -0.42, 0.0), Vector3.ZERO)

		var patty: CylinderMesh = CylinderMesh.new()
		patty.top_radius = 0.66
		patty.bottom_radius = 0.66
		patty.height = 0.24
		_add_part(root, patty, ghost_mat, Vector3(0.0, 0.02, 0.0))

		for eye_x in [-0.24, 0.24]:
			var eye: SphereMesh = SphereMesh.new()
			eye.radius = 0.10
			eye.height = 0.20
			var eye_mat: StandardMaterial3D = StandardMaterial3D.new()
			eye_mat.albedo_color = Color("0b1f2a")
			_add_part(root, eye, eye_mat, Vector3(float(eye_x), 0.55, 0.62))

	elif t in [19, 20, 21]:
		# Food court picks: Hamburger (19), Sandwich (20), Bloxy Cola (21)
		if t == 19 or t == 20:
			var bun_mat: StandardMaterial3D = StandardMaterial3D.new()
			bun_mat.albedo_color = Color("f2ac57") if t == 19 else Color("f5d38a")
			bun_mat.roughness = 0.65

			var bun_top: SphereMesh = SphereMesh.new()
			bun_top.radius = 0.74
			bun_top.height = 0.80
			_add_part(root, bun_top, bun_mat, Vector3(0.0, 0.40, 0.0))

			var bun_bottom: SphereMesh = SphereMesh.new()
			bun_bottom.radius = 0.70
			bun_bottom.height = 0.44
			_add_part(root, bun_bottom, bun_mat, Vector3(0.0, -0.44, 0.0))

			if t == 19:
				var patty_mat: StandardMaterial3D = StandardMaterial3D.new()
				patty_mat.albedo_color = Color("6b3f21")
				patty_mat.roughness = 0.8
				var meat: CylinderMesh = CylinderMesh.new()
				meat.top_radius = 0.70
				meat.bottom_radius = 0.70
				meat.height = 0.28
				_add_part(root, meat, patty_mat, Vector3(0.0, 0.0, 0.0))

				var cheese_mat: StandardMaterial3D = StandardMaterial3D.new()
				cheese_mat.albedo_color = Color("ffd43b")
				cheese_mat.roughness = 0.5
				var cheese: BoxMesh = BoxMesh.new()
				cheese.size = Vector3(1.34, 0.08, 1.34)
				_add_part(root, cheese, cheese_mat, Vector3(0.0, 0.18, 0.0), Vector3(0.0, 12.0, 0.0))
			else:
				var filling_mat: StandardMaterial3D = StandardMaterial3D.new()
				filling_mat.albedo_color = Color("e8590c")
				filling_mat.roughness = 0.7
				var filling: BoxMesh = BoxMesh.new()
				filling.size = Vector3(1.26, 0.30, 0.86)
				_add_part(root, filling, filling_mat, Vector3(0.0, 0.02, 0.0), Vector3(0.0, 0.0, 8.0))

				var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
				leaf_mat.albedo_color = Color("51cf66")
				leaf_mat.roughness = 0.6
				var leaf: BoxMesh = BoxMesh.new()
				leaf.size = Vector3(1.30, 0.10, 0.92)
				_add_part(root, leaf, leaf_mat, Vector3(0.0, 0.20, 0.0), Vector3(0.0, -6.0, 0.0))
		else:
			var can_mat: StandardMaterial3D = StandardMaterial3D.new()
			can_mat.albedo_color = Color("ced4da")
			can_mat.metallic = 0.8
			can_mat.roughness = 0.25

			var can_body: CylinderMesh = CylinderMesh.new()
			can_body.top_radius = 0.36
			can_body.bottom_radius = 0.36
			can_body.height = 1.55
			_add_part(root, can_body, can_mat, Vector3.ZERO)

			var band_mat: StandardMaterial3D = StandardMaterial3D.new()
			band_mat.albedo_color = Color("e03131")
			band_mat.emission_enabled = true
			band_mat.emission = Color("c92a2a")
			band_mat.emission_energy_multiplier = 0.35
			var band: CylinderMesh = CylinderMesh.new()
			band.top_radius = 0.375
			band.bottom_radius = 0.375
			band.height = 0.72
			_add_part(root, band, band_mat, Vector3(0.0, 0.05, 0.0))

			var lid: CylinderMesh = CylinderMesh.new()
			lid.top_radius = 0.30
			lid.bottom_radius = 0.36
			lid.height = 0.10
			_add_part(root, lid, can_mat, Vector3(0.0, 0.82, 0.0))

	else:
		var cage_mat: StandardMaterial3D = StandardMaterial3D.new()
		cage_mat.albedo_color = Color("1f1b2c")
		cage_mat.metallic = 0.82
		cage_mat.roughness = 0.22

		var core_mat: StandardMaterial3D = StandardMaterial3D.new()
		core_mat.albedo_color = Color("ff00aa")
		core_mat.emission_enabled = true
		core_mat.emission = Color("ff00aa")
		core_mat.emission_energy_multiplier = 1.65

		var core_sphere: SphereMesh = SphereMesh.new()
		core_sphere.radius = 0.36
		core_sphere.height = 0.72
		_add_part(root, core_sphere, core_mat)

		for rot_v in [Vector3.ZERO, Vector3(90, 0, 0), Vector3(0, 0, 90), Vector3(45, 45, 0), Vector3(-45, 45, 0)]:
			var bar: BoxMesh = BoxMesh.new()
			bar.size = Vector3(0.16, 1.28, 0.16)
			_add_part(root, bar, cage_mat, Vector3.ZERO, rot_v)

	return root


static func get_type_meta(t: int) -> Dictionary:
	if t == 0:
		return {"id": "random", "name": "Random Gear", "short": "RANDOM", "color": Color("ffd43b")}
	return {
		"id": get_type_id(t),
		"name": get_default_item_name(t),
		"short": get_short_label(t),
		"color": get_item_color(t),
	}
