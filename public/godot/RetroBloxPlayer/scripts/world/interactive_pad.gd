@tool
class_name InteractivePad
extends StaticBody3D
# Configurable interactive brick / pad for RetroBlox maps.
# Exposes Inspector variables for Damage Brick, Kill Brick, Heal Brick,
# Insta-Heal Brick, Speed Pad, Gravity Pad, and Bounce Trampoline.

const STUD := 1.0
const STUD_SHADER_PATH := "res://assets/studs/part_studs.gdshader"
const STUD_TEX_PATH := "res://assets/studs/stud_tile.png"
const STUD_NORMAL_PATH := "res://assets/Materials/Studs 4x4 Normal Plastic.png"

@export_group("Pad Type & Appearance")
@export_enum("Damage Brick:0", "Kill Brick:1", "Heal Brick:2", "Insta-Heal Brick:3", "Speed Pad:4", "Gravity Pad:5", "Bounce Pad:6", "Checkpoint:7") var pad_type: int = 0:
	set(v):
		pad_type = v
		_sync_groups_and_meta()
		if is_inside_tree():
			_rebuild_visuals()

@export var brick_size := Vector3(4.0, 0.6, 4.0):
	set(v):
		brick_size = Vector3(maxf(v.x, 0.2), maxf(v.y, 0.1), maxf(v.z, 0.2))
		if is_inside_tree():
			_rebuild_visuals()

@export var brick_color := Color("f76707"):
	set(v):
		brick_color = v
		if is_inside_tree():
			_rebuild_visuals()

@export var is_neon := false:
	set(v):
		is_neon = v
		if is_inside_tree():
			_rebuild_visuals()

@export var label_text := "DAMAGE BRICK (-20 HP)":
	set(v):
		label_text = v
		if is_inside_tree():
			_rebuild_visuals()

@export var show_label := true:
	set(v):
		show_label = v
		if is_inside_tree():
			_rebuild_visuals()

@export_group("Damage & Heal Variables")
## HP removed each tick when standing on a Damage Brick.
@export var damage_amount := 20.0:
	set(v):
		damage_amount = maxf(v, 0.0)
		set_meta("damage", damage_amount)

## Seconds between damage ticks while standing on the brick.
@export var damage_cooldown := 0.55:
	set(v):
		damage_cooldown = maxf(v, 0.05)
		set_meta("damage_cooldown", damage_cooldown)

## HP restored each tick when standing on a Heal Brick.
@export var heal_amount := 15.0:
	set(v):
		heal_amount = maxf(v, 0.0)
		set_meta("heal", heal_amount)

## Seconds between heal ticks while standing on the brick.
@export var heal_cooldown := 0.45:
	set(v):
		heal_cooldown = maxf(v, 0.05)
		set_meta("heal_cooldown", heal_cooldown)

## If true, continuously damages the player every cooldown period while standing on it. If false (default), damages once per touch.
@export var continuous_damage := false

## If true, continuously heals the player every cooldown period while standing on it. If false (default), heals once per touch.
@export var continuous_heal := false

## If true (or if pad_type is Kill Brick), touching this brick instantly kills the player.
@export var insta_kill := false:
	set(v):
		insta_kill = v
		_sync_groups_and_meta()

## If true (or if pad_type is Insta-Heal Brick), touching this brick instantly restores 100% HP.
@export var insta_heal := false:
	set(v):
		insta_heal = v
		_sync_groups_and_meta()

@export_group("Speed, Gravity & Bounce Variables")
## Walk speed multiplier applied when stepping on a Speed Pad (default 1.65x).
@export var speed_multiplier := 1.65:
	set(v):
		speed_multiplier = maxf(v, 0.1)
		set_meta("speed_multiplier", speed_multiplier)

## Duration in seconds for the Speed Pad boost.
@export var speed_duration := 10.0:
	set(v):
		speed_duration = maxf(v, 0.1)
		set_meta("speed_duration", speed_duration)

## Gravity multiplier applied when stepping on a Gravity Pad (lower = higher moon jumps).
@export var gravity_multiplier := 0.42:
	set(v):
		gravity_multiplier = clampf(v, 0.05, 2.0)
		set_meta("gravity_multiplier", gravity_multiplier)

## Jump velocity multiplier while Gravity Pad boost is active.
@export var jump_boost_multiplier := 1.25:
	set(v):
		jump_boost_multiplier = maxf(v, 0.5)
		set_meta("jump_boost_multiplier", jump_boost_multiplier)

## Duration in seconds for the Gravity Pad boost.
@export var gravity_duration := 10.0:
	set(v):
		gravity_duration = maxf(v, 0.1)
		set_meta("gravity_duration", gravity_duration)

## Upward launch speed when stepping on a Bounce Pad / Trampoline.
@export var bounce_power := 72.0:
	set(v):
		bounce_power = maxf(v, 1.0)
		set_meta("bounce_power", bounce_power)

@export_group("Speed & Gravity Pad Customization")
## If true, speed or gravity boosts last indefinitely until manually cleared or touching a block.
@export var infinite_duration := false:
	set(v):
		infinite_duration = v
		set_meta("infinite_duration", v)

## If true, stepping off the pad and touching any normal block or ground immediately removes the boost.
@export var remove_on_touch_block := false:
	set(v):
		remove_on_touch_block = v
		set_meta("remove_on_touch_block", v)

@export_group("Checkpoint Settings")
## Checkpoint sequence ID.
@export var checkpoint_id: int = 1
## Color when this checkpoint is reached and activated.
@export var active_color := Color("00ff88")
## Whether to fully heal the player upon reaching this checkpoint.
@export var heal_on_checkpoint := true

var is_checkpoint_activated := false


func _ready() -> void:
	_sync_groups_and_meta()
	_rebuild_visuals()


func _sync_groups_and_meta() -> void:
	for g in ["damage", "kill", "heal", "insta_heal", "speed_pad", "gravity_pad", "bounce", "checkpoint"]:
		if is_in_group(g):
			remove_from_group(g)
	if insta_kill or pad_type == 1:
		add_to_group("kill")
	elif insta_heal or pad_type == 3:
		add_to_group("insta_heal")
	elif pad_type == 0:
		add_to_group("damage")
	elif pad_type == 2:
		add_to_group("heal")
	elif pad_type == 4:
		add_to_group("speed_pad")
	elif pad_type == 5:
		add_to_group("gravity_pad")
	elif pad_type == 6:
		add_to_group("bounce")
	elif pad_type == 7:
		add_to_group("checkpoint")
		var spawn_pos := (global_position if is_inside_tree() else position) + Vector3(0.0, brick_size.y * 0.5 + 1.2 * STUD, 0.0)
		set_meta("spawn", spawn_pos)
		if label_text == "DAMAGE BRICK (-20 HP)":
			label_text = "CHECKPOINT"

	set_meta("damage", damage_amount)
	set_meta("damage_cooldown", damage_cooldown)
	set_meta("heal", heal_amount)
	set_meta("heal_cooldown", heal_cooldown)
	set_meta("speed_multiplier", speed_multiplier)
	set_meta("speed_duration", speed_duration)
	set_meta("gravity_multiplier", gravity_multiplier)
	set_meta("jump_boost_multiplier", jump_boost_multiplier)
	set_meta("gravity_duration", gravity_duration)
	set_meta("bounce_power", bounce_power)
	set_meta("infinite_duration", infinite_duration)
	set_meta("remove_on_touch_block", remove_on_touch_block)
	set_meta("color", brick_color.to_html(false))
	set_meta("mat", "neon" if is_neon else "plastic")


func activate_checkpoint() -> void:
	if not is_in_group("checkpoint"):
		return
	is_checkpoint_activated = true
	brick_color = active_color
	is_neon = true
	label_text = "CHECKPOINT ACTIVATED"
	_rebuild_visuals()


func _rebuild_visuals() -> void:
	var col_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node == null:
		col_node = CollisionShape3D.new()
		col_node.name = "CollisionShape3D"
		add_child(col_node)
	var box_shape := BoxShape3D.new()
	box_shape.size = brick_size * STUD
	col_node.shape = box_shape

	var mesh_node := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_node == null:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "MeshInstance3D"
		add_child(mesh_node)
	var box_mesh := BoxMesh.new()
	box_mesh.size = brick_size * STUD
	mesh_node.mesh = box_mesh

	if is_neon:
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = brick_color
		nmat.roughness = 0.28
		nmat.emission_enabled = true
		nmat.emission = brick_color
		nmat.emission_energy_multiplier = 1.25
		mesh_node.material_override = nmat
	else:
		var sh := load(STUD_SHADER_PATH) as Shader
		var st := load(STUD_TEX_PATH) as Texture2D
		var sn := load(STUD_NORMAL_PATH) as Texture2D
		if sh != null:
			var smat := ShaderMaterial.new()
			smat.shader = sh
			smat.set_shader_parameter("albedo", brick_color)
			if st != null:
				smat.set_shader_parameter("stud_tex", st)
			if sn != null:
				smat.set_shader_parameter("stud_normal_tex", sn)
			smat.set_shader_parameter("stud_density", 1.0)
			smat.set_shader_parameter("normal_depth", 1.35)
			smat.set_shader_parameter("roughness_val", 0.38)
			smat.set_shader_parameter("specular_val", 0.52)
			mesh_node.material_override = smat
		else:
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = brick_color
			pmat.roughness = 0.45
			mesh_node.material_override = pmat

	var lbl := get_node_or_null("Label3D") as Label3D
	if show_label and label_text.strip_edges() != "":
		if lbl == null:
			lbl = Label3D.new()
			lbl.name = "Label3D"
			add_child(lbl)
		lbl.visible = true
		lbl.text = label_text
		lbl.font_size = 64
		lbl.pixel_size = 0.0045
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = brick_color.lightened(0.42)
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0, 0, 0, 0.9)
		lbl.position = Vector3(0.0, brick_size.y * 0.5 + 1.2, 0.0)
	elif lbl != null:
		lbl.visible = false
