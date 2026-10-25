class_name AvatarViewer
extends SubViewportContainer
# Renders a static, properly framed 3D viewport preview of an avatar for the ESC menu player cards.

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")

const RIG_CENTER := Vector3(0.0, 2.75, 0.0)
const START_DIST := 11.2
const MIN_DIST := 7.0
const MAX_DIST := 15.0

var _vp: SubViewport
var _cam: Camera3D
var _rig: Node3D
var _yaw := 0.16
var _pitch := 0.10
var _dist := START_DIST


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 175)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.name = "Stage"
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.disable_3d = false
	_vp.mesh_lod_threshold = 0.0
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.92, 0.94, 1.0)
	e.ambient_light_energy = 0.85
	env.environment = e
	_vp.add_child(env)

	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.current = true
	_vp.add_child(_cam)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-24, 28, 0)
	key.light_energy = 1.1
	_cam.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 150, 0)
	fill.light_energy = 0.45
	_cam.add_child(fill)

	_update_camera()


func dress(api, payload: Dictionary) -> void:
	if not is_node_ready():
		await ready
	if _vp == null or not is_instance_valid(_vp):
		return
	if _rig == null:
		_rig = AvatarRigScript.new()
		_vp.add_child(_rig)
		_rig.call("setup", "")
	if payload.is_empty():
		return
	await AvatarDresserScript.apply(api, _rig, payload, true)
	if not is_instance_valid(self) or _rig == null or not is_instance_valid(_rig):
		return
	_rig.call("set_display_name", "")
	_update_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _vp != null and is_instance_valid(_vp):
		if is_visible_in_tree():
			_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			_update_camera()
		else:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _update_camera() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var cp := cos(_pitch)
	var offset := Vector3(sin(_yaw) * cp, sin(_pitch), -cos(_yaw) * cp) * _dist
	_cam.position = RIG_CENTER + offset
	_cam.look_at(RIG_CENTER, Vector3.UP)
