# res://scripts/apple_worm/apple_item.gd
@tool
class_name AppleItem
extends Node3D

enum AppleType { RED, BLACK, GOLD }

@export var apple_type: AppleType = AppleType.RED:
	set(v):
		apple_type = v
		_update_visuals()

var _body_mesh: MeshInstance3D
var _stem_mesh: MeshInstance3D
var _leaf_mesh: MeshInstance3D
var _aura_light: OmniLight3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		position.x = round(position.x)
		position.y = round(position.y)
		position.z = 0.0
	_update_visuals()

func _process(delta: float) -> void:
	# Subtle floating / spinning animation
	rotation.y += delta * 1.5

func _update_visuals() -> void:
	if not _body_mesh:
		_body_mesh = get_node_or_null("Body") as MeshInstance3D
	if not _body_mesh:
		_body_mesh = MeshInstance3D.new()
		_body_mesh.name = "Body"
		add_child(_body_mesh)
		var sphere = SphereMesh.new()
		sphere.radius = 0.38
		sphere.height = 0.72
		_body_mesh.mesh = sphere
		_body_mesh.position = Vector3(0, 0, 0)

	if not _stem_mesh:
		_stem_mesh = get_node_or_null("Stem") as MeshInstance3D
	if not _stem_mesh:
		_stem_mesh = MeshInstance3D.new()
		_stem_mesh.name = "Stem"
		add_child(_stem_mesh)
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 0.22
		_stem_mesh.mesh = cyl
		_stem_mesh.position = Vector3(0, 0.42, 0)
		var stem_mat = StandardMaterial3D.new()
		stem_mat.albedo_color = Color(0.28, 0.16, 0.08)
		_stem_mesh.material_override = stem_mat

	if not _leaf_mesh:
		_leaf_mesh = get_node_or_null("Leaf") as MeshInstance3D
	if not _leaf_mesh:
		_leaf_mesh = MeshInstance3D.new()
		_leaf_mesh.name = "Leaf"
		add_child(_leaf_mesh)
		var prism = PrismMesh.new()
		prism.size = Vector3(0.18, 0.12, 0.04)
		_leaf_mesh.mesh = prism
		_leaf_mesh.position = Vector3(0.1, 0.44, 0.02)
		_leaf_mesh.rotation = Vector3(0, 0, -0.6)
		var leaf_mat = StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(0.15, 0.75, 0.15)
		_leaf_mesh.material_override = leaf_mat

	var mat = StandardMaterial3D.new()
	match apple_type:
		AppleType.RED:
			mat.albedo_color = Color(0.92, 0.12, 0.12)
			mat.roughness = 0.3
			mat.rim_enabled = true
			mat.rim = 0.4
			mat.emission_enabled = false
		AppleType.BLACK:
			mat.albedo_color = Color(0.08, 0.08, 0.1)
			mat.roughness = 0.2
			mat.metallic = 0.5
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.05, 0.5)
			mat.emission_energy_multiplier = 0.6
		AppleType.GOLD:
			mat.albedo_color = Color(1.0, 0.82, 0.15)
			mat.metallic = 0.9
			mat.roughness = 0.18
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.7, 0.1)
			mat.emission_energy_multiplier = 0.4

	_body_mesh.material_override = mat
