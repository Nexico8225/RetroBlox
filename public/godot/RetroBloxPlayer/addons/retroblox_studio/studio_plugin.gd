@tool
extends EditorPlugin

# RetroBlox Studio Editor Plugin
# Integrates Roblox-style part placement, studio ribbon, and player settings directly into Godot.

const PlayerSettingsDialogScript := preload("res://addons/retroblox_studio/player_settings_dialog.gd")
const StudShader := preload("res://assets/studs/part_studs.gdshader")
const StudTex := preload("res://assets/studs/stud_tile.png")
const StudNormalTex := preload("res://assets/Materials/Studs 4x4 Normal Plastic.png")

var _toolbar: HBoxContainer
var _settings_dialog: AcceptDialog


func _enter_tree() -> void:
	_register_custom_project_settings()
	_create_toolbar()
	_settings_dialog = PlayerSettingsDialogScript.new()
	get_editor_interface().get_base_control().add_child(_settings_dialog)


func _exit_tree() -> void:
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
	if _settings_dialog != null:
		_settings_dialog.queue_free()


func _register_custom_project_settings() -> void:
	# Define default settings if not already present
	_set_setting_default("player/movement/walk_speed", 16.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "1,200,1")
	_set_setting_default("player/movement/jump_power", 50.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,300,1")
	_set_setting_default("player/movement/gravity", 196.2, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1000,1")
	_set_setting_default("player/movement/bunny_hop", true, TYPE_BOOL)
	_set_setting_default("player/health/max_health", 100.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "1,10000,1")
	_set_setting_default("player/health/health_regen_rate", 1.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,50,0.5")
	_set_setting_default("player/health/fall_damage_enabled", true, TYPE_BOOL)
	_set_setting_default("player/features/voice_chat", true, TYPE_BOOL)
	_set_setting_default("player/features/shift_lock", true, TYPE_BOOL)
	_set_setting_default("player/appearance/default_shirt", "", TYPE_STRING)
	_set_setting_default("player/appearance/default_pants", "", TYPE_STRING)
	_set_setting_default("world/baseplate/size", 512.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "64,4096,64")


func _set_setting_default(name: String, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	ProjectSettings.set_initial_value(name, default_value)
	var info: Dictionary = {
		"name": name,
		"type": type,
		"hint": hint,
		"hint_string": hint_string
	}
	ProjectSettings.add_property_info(info)


func _create_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "RetroBloxToolbar"

	var sep1 := VSeparator.new()
	_toolbar.add_child(sep1)

	# Studio Badge
	var title_lbl := Label.new()
	title_lbl.text = "RetroBlox"
	title_lbl.tooltip_text = "RetroBlox Studio Tools"
	_toolbar.add_child(title_lbl)

	# Part Dropdown
	var part_menu := MenuButton.new()
	part_menu.text = "+ Part"
	part_menu.tooltip_text = "Insert a classic Roblox Part into the scene"
	var popup := part_menu.get_popup()
	popup.add_item("Block (4 x 1.2 x 2)", 0)
	popup.add_item("Brick (4 x 2 x 2)", 1)
	popup.add_item("Plate (4 x 0.4 x 4)", 2)
	popup.add_item("Cylinder (4 x 2 x 4)", 3)
	popup.add_item("Sphere (4 x 4 x 4)", 4)
	popup.add_item("Wedge (4 x 2 x 4)", 5)
	popup.add_item("Truss / Ladder (3 x 20 x 0.8)", 6)
	popup.id_pressed.connect(_on_part_selected)
	_toolbar.add_child(part_menu)

	# Player Settings Button
	var settings_btn := Button.new()
	settings_btn.text = "Player Settings"
	settings_btn.tooltip_text = "Edit player walk speed, jump power, gravity, and health"
	settings_btn.pressed.connect(_on_open_player_settings)
	_toolbar.add_child(settings_btn)

	var sep2 := VSeparator.new()
	_toolbar.add_child(sep2)

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)


func _on_open_player_settings() -> void:
	if _settings_dialog != null:
		_settings_dialog.popup_centered()


func _on_part_selected(id: int) -> void:
	var root := get_tree().edited_scene_root
	if root == null:
		printerr("RetroBlox Studio: Open a 3D scene before inserting parts.")
		return

	var target_parent: Node = root.get_node_or_null("World")
	if target_parent == null:
		target_parent = root

	var part := StaticBody3D.new()
	var mesh_inst := MeshInstance3D.new()
	var col_shape := CollisionShape3D.new()

	var part_size := Vector3(4.0, 1.2, 2.0)
	var shape_box := BoxShape3D.new()
	var box_mesh := BoxMesh.new()

	match id:
		0: # Block 4 x 1.2 x 2
			part.name = "Part"
			part_size = Vector3(4.0, 1.2, 2.0)
			box_mesh.size = part_size
			shape_box.size = part_size
			mesh_inst.mesh = box_mesh
			col_shape.shape = shape_box
		1: # Brick 4 x 2 x 2
			part.name = "Brick"
			part_size = Vector3(4.0, 2.0, 2.0)
			box_mesh.size = part_size
			shape_box.size = part_size
			mesh_inst.mesh = box_mesh
			col_shape.shape = shape_box
		2: # Plate 4 x 0.4 x 4
			part.name = "Plate"
			part_size = Vector3(4.0, 0.4, 4.0)
			box_mesh.size = part_size
			shape_box.size = part_size
			mesh_inst.mesh = box_mesh
			col_shape.shape = shape_box
		3: # Cylinder
			part.name = "Cylinder"
			var cyl_mesh := CylinderMesh.new()
			cyl_mesh.top_radius = 2.0
			cyl_mesh.bottom_radius = 2.0
			cyl_mesh.height = 2.0
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = 2.0
			cyl_shape.height = 2.0
			mesh_inst.mesh = cyl_mesh
			col_shape.shape = cyl_shape
		4: # Sphere
			part.name = "Sphere"
			var sph_mesh := SphereMesh.new()
			sph_mesh.radius = 2.0
			sph_mesh.height = 4.0
			var sph_shape := SphereShape3D.new()
			sph_shape.radius = 2.0
			mesh_inst.mesh = sph_mesh
			col_shape.shape = sph_shape
		5: # Wedge
			part.name = "Wedge"
			var pwedge := PrismMesh.new()
			pwedge.size = Vector3(4.0, 2.0, 4.0)
			pwedge.left_to_right = 0.0
			box_mesh.size = Vector3(4.0, 2.0, 4.0)
			shape_box.size = Vector3(4.0, 2.0, 4.0)
			mesh_inst.mesh = pwedge
			col_shape.shape = shape_box
		6: # Truss / Ladder
			part.name = "ClimbLadder"
			part_size = Vector3(3.0, 20.0, 0.8)
			box_mesh.size = part_size
			shape_box.size = part_size
			mesh_inst.mesh = box_mesh
			col_shape.shape = shape_box
			part.add_to_group("ladder")
			part.add_to_group("climb")
			part.collision_layer = 17

	# Apply Studs Material
	var mat := ShaderMaterial.new()
	mat.shader = StudShader
	mat.set_shader_parameter("albedo", Color("7f8c8d"))
	mat.set_shader_parameter("stud_tex", StudTex)
	mat.set_shader_parameter("stud_normal_tex", StudNormalTex)
	mat.set_shader_parameter("stud_density", 1.0)
	mat.set_shader_parameter("normal_depth", 1.2)
	mat.set_shader_parameter("roughness_val", 0.4)
	mat.set_shader_parameter("specular_val", 0.5)
	mesh_inst.material_override = mat

	# Default spawn position: at origin + slight elevation
	part.position = Vector3(0.0, part_size.y * 0.5 + 2.0, 0.0)

	part.add_child(mesh_inst)
	part.add_child(col_shape)
	target_parent.add_child(part)

	# Set owners for Godot scene serialization
	part.owner = root
	mesh_inst.owner = root
	col_shape.owner = root

	# Select the newly created part in the editor
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(part)
