extends ToolBase
## Rocket Launcher — fires a visible rocket, explodes on contact:
## positional boom + area damage routed through main.gd.

const SPEED := 26.0
const DAMAGE_RADIUS := 6.5
const MAX_DAMAGE := 80.0

var _rocket: Node3D = null
var _rocket_vel: Vector3 = Vector3.ZERO
var _alive: bool = false

func _init() -> void:
	cooldown = 1.6
	var tube := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 1.7
	tube.mesh = cyl
	tube.rotation = Vector3(Mathf.PI / 2.0, 0.0, 0.0)
	tube.position = Vector3(0.3, 0.15, -0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.58, 0.6)
	tube.material_override = mat
	add_child(tube)

func _process(delta: float) -> void:
	super._process(delta)
	if _alive and _rocket != null:
		_rocket.global_position += _rocket_vel * delta
		var hit := _rocket_ray()
		if hit.has("collider") or _rocket.global_position.y < -30.0:
			_explode()

func _rocket_ray() -> Dictionary:
	if _rocket == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		_rocket.global_position, _rocket.global_position + _rocket_vel.normalized() * 1.2)
	if player is PhysicsBody3D:
		query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(query)

func use_primary() -> bool:
	if not ready_to_use() or _alive:
		return false
	start_cooldown(cooldown)
	used.emit("shot")
	var cam := get_viewport().get_camera_3d()
	var dir := (-cam.global_transform.basis.z).normalized() if cam != null else Vector3.FORWARD
	_rocket = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.12
	m.bottom_radius = 0.12
	m.height = 0.6
	_rocket.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.15)
	_rocket.material_override = mat
	get_tree().current_scene.add_child(_rocket)
	_rocket.global_position = player.global_position + Vector3(0, 1.4, 0) + dir * 1.5
	_rocket.look_at(_rocket.global_position + dir, Vector3.UP)
	_rocket.rotate_object_local(Vector3.RIGHT, Mathf.PI / 2.0)
	_rocket_vel = dir * SPEED
	_alive = true
	Sfx.ui("swing", -6.0)
	return true

func _explode() -> void:
	if _rocket == null:
		return
	var at := _rocket.global_position
	_rocket.queue_free()
	_rocket = null
	_alive = false
	Sfx.at("explosion", at, get_tree().current_scene, 2.0)
	if main != null and main.has_method("report_explosion"):
		main.report_explosion(at, DAMAGE_RADIUS, MAX_DAMAGE)

func unequip() -> void:
	super.unequip()
	if _rocket != null:
		_rocket.queue_free()
		_rocket = null
		_alive = false
