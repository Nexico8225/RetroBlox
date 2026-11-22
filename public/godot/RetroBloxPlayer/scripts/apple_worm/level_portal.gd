# res://scripts/apple_worm/level_portal.gd
@tool
class_name LevelPortal
extends Node3D

var _ring_mesh: MeshInstance3D
var _vortex_mesh: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		position.x = round(position.x)
		position.y = round(position.y)
		position.z = 0.0
	_build_visuals()

func _process(delta: float) -> void:
	if _vortex_mesh:
		_vortex_mesh.rotation.z += delta * 2.5
	if _ring_mesh:
		_ring_mesh.rotation.z -= delta * 0.8

func _build_visuals() -> void:
	if not _ring_mesh:
		_ring_mesh = get_node_or_null("Ring") as MeshInstance3D
	if not _ring_mesh:
		_ring_mesh = MeshInstance3D.new()
		_ring_mesh.name = "Ring"
		add_child(_ring_mesh)
		var torus = TorusMesh.new()
		torus.inner_radius = 0.38
		torus.outer_radius = 0.48
		_ring_mesh.mesh = torus
		_ring_mesh.rotation_degrees = Vector3(90, 0, 0)
		var ring_mat = StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.2, 0.05, 0.3)
		ring_mat.metallic = 0.8
		ring_mat.roughness = 0.3
		_ring_mesh.material_override = ring_mat

	if not _vortex_mesh:
		_vortex_mesh = get_node_or_null("Vortex") as MeshInstance3D
	if not _vortex_mesh:
		_vortex_mesh = MeshInstance3D.new()
		_vortex_mesh.name = "Vortex"
		add_child(_vortex_mesh)
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.38
		cyl.bottom_radius = 0.38
		cyl.height = 0.08
		_vortex_mesh.mesh = cyl
		_vortex_mesh.rotation_degrees = Vector3(90, 0, 0)
		var vortex_mat = StandardMaterial3D.new()
		vortex_mat.albedo_color = Color(0.68, 0.1, 0.95)
		vortex_mat.emission_enabled = true
		vortex_mat.emission = Color(0.75, 0.12, 1.0)
		vortex_mat.emission_energy_multiplier = 1.8
		_vortex_mesh.material_override = vortex_mat

	if not _light:
		_light = get_node_or_null("Light") as OmniLight3D
	if not _light:
		_light = OmniLight3D.new()
		_light.name = "Light"
		_light.light_color = Color(0.8, 0.2, 1.0)
		_light.light_energy = 1.2
		_light.omni_range = 3.5
		add_child(_light)
