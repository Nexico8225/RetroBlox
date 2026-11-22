# res://scripts/apple_worm/wall_block.gd
@tool
class_name WallBlock
extends Node3D

enum TopStyle { SNOW, GRASS, PLAIN }

@export var top_style: TopStyle = TopStyle.SNOW:
	set(v):
		top_style = v
		_update_mesh()

var _mesh_dirt: MeshInstance3D
var _mesh_top: MeshInstance3D

func _ready() -> void:
	# Ensure snapped to integer grid in XY plane
	if not Engine.is_editor_hint():
		position.x = round(position.x)
		position.y = round(position.y)
		position.z = 0.0
	_update_mesh()

func _update_mesh() -> void:
	if not _mesh_dirt:
		_mesh_dirt = get_node_or_null("Dirt") as MeshInstance3D
	if not _mesh_dirt:
		_mesh_dirt = MeshInstance3D.new()
		_mesh_dirt.name = "Dirt"
		add_child(_mesh_dirt)
		var box = BoxMesh.new()
		box.size = Vector3(1.0, 1.0, 0.9)
		_mesh_dirt.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.26, 0.14) # Rich earthy brown
		mat.roughness = 0.85
		_mesh_dirt.material_override = mat

	if not _mesh_top:
		_mesh_top = get_node_or_null("Top") as MeshInstance3D
	if not _mesh_top:
		_mesh_top = MeshInstance3D.new()
		_mesh_top.name = "Top"
		add_child(_mesh_top)
		var box = BoxMesh.new()
		box.size = Vector3(1.02, 0.22, 0.92)
		_mesh_top.mesh = box
		_mesh_top.position = Vector3(0.0, 0.42, 0.01)

	var top_mat = StandardMaterial3D.new()
	match top_style:
		TopStyle.SNOW:
			top_mat.albedo_color = Color(0.96, 0.97, 1.0) # Snow white
			top_mat.roughness = 0.4
			_mesh_top.visible = true
		TopStyle.GRASS:
			top_mat.albedo_color = Color(0.24, 0.68, 0.22) # Grass green
			top_mat.roughness = 0.7
			_mesh_top.visible = true
		TopStyle.PLAIN:
			_mesh_top.visible = false
	_mesh_top.material_override = top_mat
