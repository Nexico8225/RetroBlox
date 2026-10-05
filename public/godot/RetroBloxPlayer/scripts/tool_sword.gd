extends ToolBase
## Classic Sword — swing, double-press lunge, ray melee damage, hit sound.

const RANGE := 5.2
const DAMAGE := 34.0        # three hits — classic sword feel
const LUNGE_DAMAGE := 68.0

var _last_press: float = -10.0

func _init() -> void:
	cooldown = 0.45
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.14, 2.6)
	mesh.mesh = box
	mesh.position = Vector3(0.25, 0.1, -1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.83, 0.85, 0.9)
	mat.metallic = 0.65
	mat.roughness = 0.35
	mesh.material_override = mat
	add_child(mesh)
	var grip := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.2, 0.32, 0.2)
	grip.mesh = gbox
	grip.position = Vector3(0.25, 0.1, 0.35)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.45, 0.28, 0.12)
	grip.material_override = gmat
	add_child(grip)

func use_primary() -> bool:
	if not ready_to_use():
		return false
	var now := Time.get_ticks_msec() / 1000.0
	var lunge := now - _last_press < 0.35
	_last_press = now
	start_cooldown(cooldown + (0.25 if lunge else 0.0))
	Sfx.ui("swing", -4.0)
	used.emit("swing")
	# lunge shove
	if lunge and player != null:
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		player.velocity += forward.normalized() * 9.0
	var hit := aim_ray(RANGE)
	if hit.has("collider"):
		Sfx.ui("hit", -3.0)
		if main != null and main.has_method("report_hit"):
			main.report_hit(hit["collider"])
	return true
