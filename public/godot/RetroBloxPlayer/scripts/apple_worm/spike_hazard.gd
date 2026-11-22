# res://scripts/apple_worm/spike_hazard.gd
@tool
class_name SpikeHazard
extends Node3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		position.x = round(position.x)
		position.y = round(position.y)
		position.z = 0.0
	_build_spikes()

func _build_spikes() -> void:
	if get_child_count() > 0:
		return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.3

	for offset in [Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0)]:
		var m = MeshInstance3D.new()
		var prism = PrismMesh.new()
		prism.size = Vector3(0.45, 0.7, 0.45)
		m.mesh = prism
		m.material_override = mat
		m.position = offset + Vector3(0, -0.15, 0)
		add_child(m)
