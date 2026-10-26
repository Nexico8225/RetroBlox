@tool
class_name ClimbLadderPart
extends StaticBody3D
# Configurable Climbable Ladder / Truss part for RetroBlox maps.
# Automatically sets collision_layer = 1 | 16 and group "ladder".

const STUD := 1.0
const STUD_SHADER_PATH := "res://assets/studs/part_studs.gdshader"
const STUD_TEX_PATH := "res://assets/studs/stud_tile.png"
const STUD_NORMAL_PATH := "res://assets/Materials/Studs 4x4 Normal Plastic.png"

@export_group("Ladder Settings")
@export var ladder_size := Vector3(2.4, 9.5, 0.8):
	set(v):
		ladder_size = Vector3(maxf(v.x, 0.2), maxf(v.y, 0.5), maxf(v.z, 0.2))
		if is_inside_tree():
			_rebuild_visuals()

@export var ladder_color := Color("f59f00"):
	set(v):
		ladder_color = v
		if is_inside_tree():
			_rebuild_visuals()

@export var climb_speed := 11.0:
	set(v):
		climb_speed = maxf(v, 1.0)
		set_meta("climb_speed", climb_speed)

@export var label_text := "CLIMB LADDER":
	set(v):
		label_text = v
		if is_inside_tree():
			_rebuild_visuals()

@export var show_label := true:
	set(v):
		show_label = v
		if is_inside_tree():
			_rebuild_visuals()


func _ready() -> void:
	collision_layer = 1 | 16
	if not is_in_group("ladder"):
		add_to_group("ladder")
	set_meta("climb_speed", climb_speed)
	set_meta("color", ladder_color.to_html(false))
	set_meta("mat", "plastic")
	_rebuild_visuals()


func _rebuild_visuals() -> void:
	var col_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node == null:
		col_node = CollisionShape3D.new()
		col_node.name = "CollisionShape3D"
		add_child(col_node)
	var box_shape := BoxShape3D.new()
	box_shape.size = ladder_size * STUD
	col_node.shape = box_shape

	var mesh_node := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_node == null:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "MeshInstance3D"
		add_child(mesh_node)
	var box_mesh := BoxMesh.new()
	box_mesh.size = ladder_size * STUD
	mesh_node.mesh = box_mesh

	var sh := load(STUD_SHADER_PATH) as Shader
	var st := load(STUD_TEX_PATH) as Texture2D
	var sn := load(STUD_NORMAL_PATH) as Texture2D
	if sh != null:
		var smat := ShaderMaterial.new()
		smat.shader = sh
		smat.set_shader_parameter("albedo", ladder_color)
		if st != null:
			smat.set_shader_parameter("stud_tex", st)
		if sn != null:
			smat.set_shader_parameter("stud_normal_tex", sn)
		smat.set_shader_parameter("stud_density", 1.0)
		smat.set_shader_parameter("normal_depth", 1.35)
		smat.set_shader_parameter("roughness_val", 0.38)
		smat.set_shader_parameter("specular_val", 0.52)
		mesh_node.material_override = smat

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
		lbl.modulate = ladder_color.lightened(0.38)
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0, 0, 0, 0.9)
		lbl.position = Vector3(0.0, ladder_size.y * 0.5 + 0.85, 0.0)
	elif lbl != null:
		lbl.visible = false
