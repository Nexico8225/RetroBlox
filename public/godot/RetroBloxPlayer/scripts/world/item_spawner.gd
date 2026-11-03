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
	MEDKIT = 16,
	HAMBURGER = 17,
	SPICY_SAUCE = 18,
	BLOXY_COLA = 19,
	TIMEBOMB = 20,
	ILLUMINA = 21,
	VENOMSHANK = 22,
	DARKHEART = 23,
	WINDFORCE = 24,
	GOLD_SKIN_POTION = 25,
	GHOST_SKIN_POTION = 26,
	RAINBOW_SKIN_POTION = 27,
	TITAN_SKIN_POTION = 28,
	SLINGSHOT = 29,
	PAINTBALL_GUN = 30,
	SUPERBALL = 31,
	GHOSTWALKER = 32,
	SLATESKIN_POTION = 33
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
@export var respawn_cooldown: float = 8.0

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
static var _static_folder_gears_cache: Array[Dictionary] = []


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
		if _label_3d != null and is_instance_valid(_label_3d):
			if _cooldown_left > 0.0:
				_label_3d.text = "Respawning in %.0fs" % _cooldown_left
			else:
				var resolved_t: int = _active_resolved_type if _active_resolved_type >= 1 else 5
				var disp_name: String = custom_item_name.strip_edges() if custom_item_name.strip_edges() != "" else String(_active_gear_dict.get("name", get_default_item_name(resolved_t)))
				_label_3d.text = (" Random: %s" % disp_name) if (item_type == ItemType.RANDOM_FROM_GEARS_FOLDER and custom_gear_resource == null) else disp_name
	if _floating_root != null and is_instance_valid(_floating_root):
		if wall_mount:
			_floating_root.position.z = 0.65 + sin(_time * 2.8) * 0.08
			_floating_root.rotation.y = sin(_time * 1.6) * 0.35
		else:
			_floating_root.position.y = (pad_size.y * 0.5) + 1.55 + sin(_time * 2.8) * 0.22
			_floating_root.rotation.y = _time * 1.45


func _load_gears_folder() -> void:
	if gears_folder_path == "res://gears" and not _static_folder_gears_cache.is_empty():
		_loaded_folder_gears = _static_folder_gears_cache.duplicate(true)
		return
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
	if gears_folder_path == "res://gears" and not _loaded_folder_gears.is_empty():
		_static_folder_gears_cache = _loaded_folder_gears.duplicate(true)


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
		# Fallback random 1..15 if folder was moved
		var next_t: int = (randi() % 28) + 1
		if next_t == _active_resolved_type:
			next_t = (next_t % 28) + 1
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


static func get_default_respawn_cooldown(t: int) -> float:
	match t:
		5: return 10.0
		6, 7: return 45.0
		22, 32: return 55.0
		23, 24: return 65.0
		8: return 80.0
		21: return 90.0
	return 18.0


func consume_pickup() -> Dictionary:
	var resolved_t: int = _active_resolved_type if _active_resolved_type >= 1 else int(item_type)
	_cooldown_left = maxf(respawn_cooldown, get_default_respawn_cooldown(resolved_t))
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
		"speed_multiplier": 2.0 if t in [1, 3] else 1.0,
		"gravity_multiplier": 0.35 if t in [2, 3] else 1.0,
		"jump_boost_multiplier": 1.40 if t in [2, 3] else 1.0,
		"heal_per_second": 16.0 if t == 4 else 0.0,
		"slash_damage": 150.0 if t == 8 else (45.0 if t == 6 else (50.0 if t == 7 else 100.0)),
		"lunge_damage": 300.0 if t == 8 else (75.0 if t == 6 else (85.0 if t == 7 else 150.0)),
		"lunge_cooldown": 1.0 if t == 8 else 0.85,
		"sword_range": 10.5 if t == 8 else 7.0,
		"lunge_forward_boost": 78.0 if t == 8 else 44.0,
		"lunge_up_boost": 18.0 if t == 8 else 11.0,
		"lunge_duration": 0.46 if t == 8 else 0.32,
		"burn_damage_per_sec": 20.0 if t == 6 else 0.0,
		"burn_duration": 5.0 if t == 6 else 0.0,
		"slow_multiplier": 0.25 if t == 7 else 1.0,
		"slow_duration": 5.5 if t == 7 else 0.0,
		"min_swell_damage": 35.0,
		"max_swell_damage": 250.0,
		"max_swell_scale": 5.5,
		"max_charge_time": 2.4,
		"swell_launch_speed": 42.0,
		"heal_amount": 65.0,
		"head_scale_multiplier": 2.6,
		"big_head_duration": 18.0,
		"unlimited_potion_uses": true,
		"fly_speed": 38.0,
		"ascend_speed": 24.0,
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
	elif t in [10, 11, 25, 26, 27, 28, 33]:
		d["cooldown"] = 1.1
	elif t == 29:
		d["cooldown"] = 0.45
		d["projectile_speed"] = 78.0
		d["projectile_damage"] = 28.0
		d["knockback_power"] = 22.0
	elif t == 30:
		d["cooldown"] = 0.38
		d["projectile_speed"] = 72.0
		d["projectile_damage"] = 25.0
		d["knockback_power"] = 18.0
	elif t == 31:
		d["cooldown"] = 0.85
		d["projectile_speed"] = 54.0
		d["projectile_damage"] = 40.0
		d["knockback_power"] = 48.0
	elif t == 32:
		d["cooldown"] = 0.80
		d["slash_damage"] = 48.0
		d["lunge_damage"] = 78.0
		d["speed_multiplier"] = 1.32
		d["gravity_multiplier"] = 0.45
		d["jump_boost_multiplier"] = 1.35
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
		"medkit": return 16
		"hamburger": return 17
		"spicy_sauce": return 18
		"bloxy_cola": return 19
		"timebomb": return 20
		"illumina": return 21
		"venomshank": return 22
		"darkheart": return 23
		"windforce": return 24
		"gold_skin_potion": return 25
		"ghost_skin_potion": return 26
		"rainbow_skin_potion": return 27
		"titan_skin_potion": return 28
		"slingshot": return 29
		"paintball_gun": return 30
		"superball": return 31
		"ghostwalker": return 32
		"slateskin_potion": return 33
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
		16: return "medkit"
		17: return "hamburger"
		18: return "spicy_sauce"
		19: return "bloxy_cola"
		20: return "timebomb"
		21: return "illumina"
		22: return "venomshank"
		23: return "darkheart"
		24: return "windforce"
		25: return "gold_skin_potion"
		26: return "ghost_skin_potion"
		27: return "rainbow_skin_potion"
		28: return "titan_skin_potion"
		29: return "slingshot"
		30: return "paintball_gun"
		31: return "superball"
		32: return "ghostwalker"
		33: return "slateskin_potion"
	return "sword" 


static func get_default_item_name(t: int) -> String:
	match t:
		1: return "Speed Coil"
		2: return "Gravity Coil"
		3: return "Fusion Coil"
		4: return "Heal Coil"
		5: return "Linked Sword"
		6: return "Firebrand"
		7: return "Ice Dagger"
		8: return "Super Sword"
		9: return "Swelling Ball"
		10: return "Healing Potion"
		11: return "Big Head Potion"
		12: return "Flying Carpet"
		13: return "Hyperlaser Gun"
		14: return "Rocket Launcher"
		15: return "Subspace Tripmine"
		16: return "Medkit"
		17: return "Hamburger"
		18: return "Spicy Sauce"
		19: return "Bloxy Cola"
		20: return "Classic Timebomb"
		21: return "Illumina"
		22: return "Venomshank"
		23: return "Darkheart"
		24: return "Windforce"
		25: return "24K Gold Skin Potion"
		26: return "Ghostwalker Skin Potion"
		27: return "Neon Rainbow Skin"
		28: return "Giant Titan Skin"
		29: return "Slingshot"
		30: return "Paintball Gun"
		31: return "Superball"
		32: return "Ghostwalker"
		33: return "Slateskin Potion"
	return "Linked Sword" 


static func get_short_label(t: int) -> String:
	match t:
		1: return "SPEED"
		2: return "GRAV"
		3: return "FUSION"
		4: return "HEALCOIL"
		5: return "SWORD"
		6: return "FIREBRAND"
		7: return "ICEDAGGER"
		8: return "SUPER"
		9: return "SWELL"
		10: return "POTION"
		11: return "BIGHEAD"
		12: return "CARPET"
		13: return "LASER"
		14: return "ROCKET"
		15: return "TRIPMINE"
		16: return "MEDKIT"
		17: return "BURGER"
		18: return "SPICY"
		19: return "COLA"
		20: return "BOMB"
		21: return "ILLUMINA"
		22: return "VENOM"
		23: return "DARKHEART"
		24: return "WINDFORCE"
		25: return "GOLDSKIN"
		26: return "GHOST"
		27: return "RAINBOW"
		28: return "TITAN"
		29: return "SLING"
		30: return "PAINT"
		31: return "BALL"
		32: return "GHOSTW"
		33: return "SLATE"
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
		16: return Color("fa5252")
		17: return Color("e8590c")
		18: return Color("e03131")
		19: return Color("ae3ec9")
		20: return Color("343a40")
		21: return Color("ff66cc")
		22: return Color("5cd820")
		23: return Color("a61e4d")
		24: return Color("4dabf7")
		25: return Color("ffd43b")
		26: return Color("66d9e8")
		27: return Color("f06595")
		28: return Color("ff922b")
		29: return Color("b07d4f")
		30: return Color("22b8cf")
		31: return Color("e03131")
		32: return Color("ced4da")
		33: return Color("868e96")
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
	pad_mi.visible = wall_mount
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
		_label_3d.text = " Random Gear: %s" % disp_name
	else:
		_label_3d.text = disp_name
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
		# Authentic Roblox Helical Spring Coils built from tilted metallic TorusMesh rings!
		var mat_a: StandardMaterial3D = glow_mat.duplicate() as StandardMaterial3D
		mat_a.metallic = 0.72
		mat_a.roughness = 0.18
		mat_a.emission_energy_multiplier = 0.85
		var mat_b: StandardMaterial3D = mat_a
		if t == 3:
			mat_a = StandardMaterial3D.new()
			mat_a.albedo_color = Color("ff3b30")
			mat_a.metallic = 0.72
			mat_a.roughness = 0.18
			mat_a.emission_enabled = true
			mat_a.emission = Color("ff3b30")
			mat_a.emission_energy_multiplier = 0.85
			mat_b = StandardMaterial3D.new()
			mat_b.albedo_color = Color("339af0")
			mat_b.metallic = 0.72
			mat_b.roughness = 0.18
			mat_b.emission_enabled = true
			mat_b.emission = Color("339af0")
			mat_b.emission_energy_multiplier = 0.85
		for r_i in range(5):
			var tor: TorusMesh = TorusMesh.new()
			tor.inner_radius = 0.62
			tor.outer_radius = 0.82
			var py: float = -0.60 + float(r_i) * 0.30
			var use_m: StandardMaterial3D = mat_a if (r_i % 2 == 0) else mat_b
			_add_part(root, tor, use_m, Vector3(0.0, py, 0.0), Vector3(11.0, float(r_i) * 35.0, 0.0))

	elif t in [5, 6, 7, 8, 21, 22, 23, 24, 32]:
		# Super Sword (8) uses the exact classic Linked Sword (5) model!
		var is_linked_look: bool = (t in [5, 8])
		var scale_mult: float = 1.22 if t == 21 else 1.05
		var gold_mat: StandardMaterial3D = StandardMaterial3D.new()
		gold_mat.albedo_color = Color("fcc419") if is_linked_look else get_item_color(t)
		gold_mat.metallic = 0.85
		gold_mat.roughness = 0.18
		if not is_linked_look:
			gold_mat.emission_enabled = true
			gold_mat.emission = gold_mat.albedo_color
			gold_mat.emission_energy_multiplier = 0.65

		var grip_mat: StandardMaterial3D = StandardMaterial3D.new()
		grip_mat.albedo_color = Color("1864ab") if is_linked_look else get_item_color(t).darkened(0.48)
		grip_mat.roughness = 0.50

		var blade_mat: StandardMaterial3D = StandardMaterial3D.new()
		if is_linked_look:
			blade_mat.albedo_color = Color("e9ecef")
			blade_mat.metallic = 0.92
			blade_mat.roughness = 0.12
		elif t == 21:
			# Illumina: glowing crystal magenta/silver blade!
			blade_mat.albedo_color = Color(1.0, 0.58, 0.92, 0.88)
			blade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			blade_mat.metallic = 0.85
			blade_mat.roughness = 0.08
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("ff66cc")
			blade_mat.emission_energy_multiplier = 1.85
		elif t == 32:
			# Ghostwalker: translucent phantom silver-blue blade!
			blade_mat.albedo_color = Color(0.82, 0.92, 1.0, 0.52)
			blade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			blade_mat.metallic = 0.65
			blade_mat.roughness = 0.10
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("a5d8ff")
			blade_mat.emission_energy_multiplier = 1.25
		elif t == 23:
			# Darkheart: obsidian black & crimson vampiric blade!
			blade_mat.albedo_color = Color("1f1218")
			blade_mat.metallic = 0.9
			blade_mat.roughness = 0.15
			blade_mat.emission_enabled = true
			blade_mat.emission = Color("c92a2a")
			blade_mat.emission_energy_multiplier = 0.95
		else:
			blade_mat.albedo_color = get_item_color(t).lightened(0.18)
			blade_mat.metallic = 0.8
			blade_mat.roughness = 0.15
			blade_mat.emission_enabled = true
			blade_mat.emission = get_item_color(t)
			blade_mat.emission_energy_multiplier = 1.10

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

		# Central fuller / elemental core ridge along the blade
		var fuller: BoxMesh = BoxMesh.new()
		fuller.size = Vector3(0.09 * scale_mult, 1.65 * scale_mult, 0.095 * scale_mult)
		_add_part(root, fuller, gold_mat, Vector3(0.0, 0.55 * scale_mult, 0.0))

		# Special SFOTH Elemental Sword Auras (Illumina, Super Sword, Ghostwalker, Darkheart, Venomshank, Windforce, Firebrand, Ice Dagger)
		if t in [6, 7, 21, 22, 23, 24, 32]:
			var aura_tor: TorusMesh = TorusMesh.new()
			aura_tor.inner_radius = 0.28 * scale_mult
			aura_tor.outer_radius = 0.36 * scale_mult
			_add_part(root, aura_tor, gold_mat if t in [8, 24] else blade_mat, Vector3(0.0, -0.40 * scale_mult, 0.0), Vector3(90.0, 0.0, 0.0))

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

	elif t in [10, 11, 25, 26, 27, 28, 33]:
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

	elif t == 16:
		# Medkit (white medical case + bright red cross + dark handle)
		var case_mat: StandardMaterial3D = StandardMaterial3D.new()
		case_mat.albedo_color = Color("f8f9fa")
		case_mat.roughness = 0.35
		var red_mat: StandardMaterial3D = StandardMaterial3D.new()
		red_mat.albedo_color = Color("e03131")
		red_mat.emission_enabled = true
		red_mat.emission = Color("e03131")
		red_mat.emission_energy_multiplier = 0.35
		var h_mat: StandardMaterial3D = StandardMaterial3D.new()
		h_mat.albedo_color = Color("343a40")
		var m_box: BoxMesh = BoxMesh.new()
		m_box.size = Vector3(1.15, 0.82, 0.42)
		_add_part(root, m_box, case_mat)
		var cross_v: BoxMesh = BoxMesh.new()
		cross_v.size = Vector3(0.18, 0.50, 0.46)
		_add_part(root, cross_v, red_mat)
		var cross_h: BoxMesh = BoxMesh.new()
		cross_h.size = Vector3(0.50, 0.18, 0.46)
		_add_part(root, cross_h, red_mat)
		var handle_b: BoxMesh = BoxMesh.new()
		handle_b.size = Vector3(0.46, 0.14, 0.14)
		_add_part(root, handle_b, h_mat, Vector3(0.0, 0.48, 0.0))

	elif t == 17:
		# Hamburger (bottom bun, beef patty, melted cheese, green lettuce, top bun)
		var bun_mat: StandardMaterial3D = StandardMaterial3D.new()
		bun_mat.albedo_color = Color("e69138")
		bun_mat.roughness = 0.65
		var meat_mat: StandardMaterial3D = StandardMaterial3D.new()
		meat_mat.albedo_color = Color("5c2d16")
		meat_mat.roughness = 0.8
		var cheese_mat: StandardMaterial3D = StandardMaterial3D.new()
		cheese_mat.albedo_color = Color("fcc419")
		var let_mat: StandardMaterial3D = StandardMaterial3D.new()
		let_mat.albedo_color = Color("40c057")
		var b_cyl: CylinderMesh = CylinderMesh.new()
		b_cyl.top_radius = 0.52
		b_cyl.bottom_radius = 0.48
		b_cyl.height = 0.18
		_add_part(root, b_cyl, bun_mat, Vector3(0.0, -0.24, 0.0))
		var p_cyl: CylinderMesh = CylinderMesh.new()
		p_cyl.top_radius = 0.54
		p_cyl.bottom_radius = 0.54
		p_cyl.height = 0.16
		_add_part(root, p_cyl, meat_mat, Vector3(0.0, -0.08, 0.0))
		var c_box: BoxMesh = BoxMesh.new()
		c_box.size = Vector3(0.82, 0.05, 0.82)
		_add_part(root, c_box, cheese_mat, Vector3(0.0, 0.02, 0.0), Vector3(0.0, 45.0, 0.0))
		var l_cyl: CylinderMesh = CylinderMesh.new()
		l_cyl.top_radius = 0.55
		l_cyl.bottom_radius = 0.55
		l_cyl.height = 0.07
		_add_part(root, l_cyl, let_mat, Vector3(0.0, 0.08, 0.0))
		var t_sph: SphereMesh = SphereMesh.new()
		t_sph.radius = 0.52
		t_sph.height = 0.52
		_add_part(root, t_sph, bun_mat, Vector3(0.0, 0.16, 0.0))

	elif t == 18:
		# Spicy Sauce Bottle (fiery red bottle + flame band + green cap)
		var sauce_mat: StandardMaterial3D = StandardMaterial3D.new()
		sauce_mat.albedo_color = Color("e03131")
		sauce_mat.emission_enabled = true
		sauce_mat.emission = Color("ff4500")
		sauce_mat.emission_energy_multiplier = 0.55
		var lbl_mat: StandardMaterial3D = StandardMaterial3D.new()
		lbl_mat.albedo_color = Color("fcc419")
		var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
		cap_mat.albedo_color = Color("2f9e44")
		var b_body: CylinderMesh = CylinderMesh.new()
		b_body.top_radius = 0.28
		b_body.bottom_radius = 0.30
		b_body.height = 0.85
		_add_part(root, b_body, sauce_mat, Vector3(0.0, -0.15, 0.0))
		var b_lbl: CylinderMesh = CylinderMesh.new()
		b_lbl.top_radius = 0.295
		b_lbl.bottom_radius = 0.295
		b_lbl.height = 0.34
		_add_part(root, b_lbl, lbl_mat, Vector3(0.0, -0.15, 0.0))
		var b_neck: CylinderMesh = CylinderMesh.new()
		b_neck.top_radius = 0.11
		b_neck.bottom_radius = 0.24
		b_neck.height = 0.32
		_add_part(root, b_neck, sauce_mat, Vector3(0.0, 0.42, 0.0))
		var b_cap: CylinderMesh = CylinderMesh.new()
		b_cap.top_radius = 0.12
		b_cap.bottom_radius = 0.12
		b_cap.height = 0.18
		_add_part(root, b_cap, cap_mat, Vector3(0.0, 0.65, 0.0))

	elif t == 19:
		# Bloxy Cola Can (classic brown/gold soda can + silver top rim)
		var cola_mat: StandardMaterial3D = StandardMaterial3D.new()
		cola_mat.albedo_color = Color("6b3e26")
		cola_mat.metallic = 0.45
		cola_mat.roughness = 0.28
		var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
		stripe_mat.albedo_color = Color("fcc419")
		var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
		rim_mat.albedo_color = Color("dee2e6")
		rim_mat.metallic = 0.85
		rim_mat.roughness = 0.18
		var can_cyl: CylinderMesh = CylinderMesh.new()
		can_cyl.top_radius = 0.30
		can_cyl.bottom_radius = 0.30
		can_cyl.height = 0.82
		_add_part(root, can_cyl, cola_mat)
		var band_cyl: CylinderMesh = CylinderMesh.new()
		band_cyl.top_radius = 0.31
		band_cyl.bottom_radius = 0.31
		band_cyl.height = 0.22
		_add_part(root, band_cyl, stripe_mat)
		var top_rim: CylinderMesh = CylinderMesh.new()
		top_rim.top_radius = 0.28
		top_rim.bottom_radius = 0.30
		top_rim.height = 0.08
		_add_part(root, top_rim, rim_mat, Vector3(0.0, 0.44, 0.0))

	elif t == 20:
		# Classic Timebomb (black metal sphere + fuse cap + glowing orange spark)
		var bomb_mat: StandardMaterial3D = StandardMaterial3D.new()
		bomb_mat.albedo_color = Color("212529")
		bomb_mat.metallic = 0.65
		bomb_mat.roughness = 0.28
		var spark_mat: StandardMaterial3D = StandardMaterial3D.new()
		spark_mat.albedo_color = Color("ff922b")
		spark_mat.emission_enabled = true
		spark_mat.emission = Color("ff5c00")
		spark_mat.emission_energy_multiplier = 2.4
		var b_sph: SphereMesh = SphereMesh.new()
		b_sph.radius = 0.56
		b_sph.height = 1.12
		_add_part(root, b_sph, bomb_mat)
		var fuse_cap: CylinderMesh = CylinderMesh.new()
		fuse_cap.top_radius = 0.14
		fuse_cap.bottom_radius = 0.18
		fuse_cap.height = 0.18
		_add_part(root, fuse_cap, bomb_mat, Vector3(0.0, 0.56, 0.0))
		var spark_sph: SphereMesh = SphereMesh.new()
		spark_sph.radius = 0.14
		spark_sph.height = 0.28
		_add_part(root, spark_sph, spark_mat, Vector3(0.0, 0.78, 0.0))

	elif t == 29:
		# Classic Wooden Y-Slingshot
		var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
		wood_mat.albedo_color = Color("8b5a2b")
		wood_mat.roughness = 0.65
		var band_mat: StandardMaterial3D = StandardMaterial3D.new()
		band_mat.albedo_color = Color("d9480f")
		var handle_c: CylinderMesh = CylinderMesh.new()
		handle_c.top_radius = 0.09
		handle_c.bottom_radius = 0.09
		handle_c.height = 0.65
		_add_part(root, handle_c, wood_mat, Vector3(0.0, -0.25, 0.0))
		var fork_l: CylinderMesh = CylinderMesh.new()
		fork_l.top_radius = 0.075
		fork_l.bottom_radius = 0.08
		fork_l.height = 0.55
		_add_part(root, fork_l, wood_mat, Vector3(-0.18, 0.22, 0.0), Vector3(0.0, 0.0, 28.0))
		_add_part(root, fork_l, wood_mat, Vector3(0.18, 0.22, 0.0), Vector3(0.0, 0.0, -28.0))
		var band_b: BoxMesh = BoxMesh.new()
		band_b.size = Vector3(0.56, 0.06, 0.12)
		_add_part(root, band_b, band_mat, Vector3(0.0, 0.42, 0.08))

	elif t == 30:
		# Classic Paintball Gun Marker
		var pgun_mat: StandardMaterial3D = StandardMaterial3D.new()
		pgun_mat.albedo_color = Color("1098ad")
		pgun_mat.metallic = 0.55
		pgun_mat.roughness = 0.28
		var hop_mat: StandardMaterial3D = StandardMaterial3D.new()
		hop_mat.albedo_color = Color("212529")
		var body_b: BoxMesh = BoxMesh.new()
		body_b.size = Vector3(0.22, 0.28, 0.85)
		_add_part(root, body_b, pgun_mat, Vector3(0.0, 0.08, 0.0))
		var brl: CylinderMesh = CylinderMesh.new()
		brl.top_radius = 0.07
		brl.bottom_radius = 0.08
		brl.height = 0.75
		_add_part(root, brl, hop_mat, Vector3(0.0, 0.12, -0.65), Vector3(90.0, 0.0, 0.0))
		var hopper: SphereMesh = SphereMesh.new()
		hopper.radius = 0.22
		hopper.height = 0.44
		_add_part(root, hopper, hop_mat, Vector3(0.0, 0.42, 0.05))
		var grip_p: BoxMesh = BoxMesh.new()
		grip_p.size = Vector3(0.18, 0.44, 0.22)
		_add_part(root, grip_p, hop_mat, Vector3(0.0, -0.22, 0.20), Vector3(16.0, 0.0, 0.0))

	elif t == 31:
		# Classic Red Superball
		var sb_mat: StandardMaterial3D = StandardMaterial3D.new()
		sb_mat.albedo_color = Color("e03131")
		sb_mat.roughness = 0.12
		sb_mat.metallic = 0.25
		sb_mat.emission_enabled = true
		sb_mat.emission = Color("ff6b6b")
		sb_mat.emission_energy_multiplier = 0.45
		var sb_sph: SphereMesh = SphereMesh.new()
		sb_sph.radius = 0.48
		sb_sph.height = 0.96
		_add_part(root, sb_sph, sb_mat)

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
