extends Node3D
# Third-person and first-person orbit camera with shift-lock and collision spring arm.
signal first_person_changed(active: bool)

const PIVOT_HEIGHT := 4.6
const EYE_HEIGHT := 4.5
const FIRST_PERSON_AT := 2.0
const MIN_ZOOM := 0.0
const MAX_ZOOM := 120.0
const DEFAULT_ZOOM := 14.0
const SHOULDER_OFFSET := 2.1
const ZOOM_GLIDE := 11.0
const LAND_DIP_MAX := 0.55

const TD_MIN_ZOOM := 16.0
const TD_MAX_ZOOM := 64.0
const TD_DEFAULT_ZOOM := 34.0
const TD_PITCH := -1.15

var mode_topdown := false

var player: Node3D
var yaw := 0.0
var pitch := -0.18
var distance := DEFAULT_ZOOM
var shift_locked := false
var first_person := false

var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _ui_blocked := false
var _orbiting := false
var _zoom_target := DEFAULT_ZOOM
var _land_dip := 0.0
var _touch_points: Dictionary = {}


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _pivot != null and is_instance_valid(_pivot):
		return
	_pivot = get_node_or_null("Pivot") as Node3D
	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = "Pivot"
		add_child(_pivot)

	_arm = _pivot.get_node_or_null("SpringArm3D") as SpringArm3D
	if _arm == null:
		_arm = SpringArm3D.new()
		_arm.name = "SpringArm3D"
		_arm.spring_length = DEFAULT_ZOOM
		_arm.collision_mask = 1
		_arm.margin = 0.4
		_pivot.add_child(_arm)

	_camera = _arm.get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.fov = 70.0
		_camera.near = 0.1
		_camera.far = 1200.0
		_camera.current = true
		_arm.add_child(_camera)


func setup(p_player: Node3D) -> void:
	_ensure_nodes()
	player = p_player
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		_camera.fov = float(settings.get("fov"))
		_apply_quality_far(int(settings.get("graphics_quality")))
		if not settings.changed.is_connected(_on_setting_changed):
			settings.changed.connect(_on_setting_changed)
	_apply_mouse_mode()
	if player != null and is_instance_valid(player) and player.has_signal("land_impact"):
		if not player.is_connected("land_impact", _on_land_impact):
			player.connect("land_impact", _on_land_impact)


func _on_land_impact(speed: float) -> void:
	_land_dip = minf(speed / 50.0, 1.0) * LAND_DIP_MAX


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "fov" and _camera != null:
		_camera.fov = float(value)
	elif key == "graphics_quality" and _camera != null:
		var settings: Node = get_node_or_null("/root/Settings")
		if settings != null:
			_apply_quality_far(int(settings.get("graphics_quality")))
	elif key == "mobile_controls":
		_apply_mouse_mode()


func _apply_quality_far(q: int) -> void:
	if _camera == null:
		return
	match q:
		0: _camera.far = 350.0
		1: _camera.far = 700.0
		2: _camera.far = 1200.0
		3: _camera.far = 2000.0


func set_shift_locked(on: bool) -> void:
	if mode_topdown:
		shift_locked = false
		return
	shift_locked = on
	_apply_mouse_mode()


func set_mode(mode: String) -> void:
	if mode != "topdown":
		return
	mode_topdown = true
	yaw = 0.0
	pitch = TD_PITCH
	distance = TD_DEFAULT_ZOOM
	_zoom_target = TD_DEFAULT_ZOOM
	first_person = false
	shift_locked = false
	_apply_mouse_mode()


func set_ui_blocked(blocked: bool) -> void:
	_ui_blocked = blocked
	if blocked:
		_touch_points.clear()
	_apply_mouse_mode()


func is_mouse_captured() -> bool:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and bool(settings.call("is_mobile_ui_active")):
		return false
	return (first_person or shift_locked) and not _ui_blocked


func camera() -> Camera3D:
	_ensure_nodes()
	return _camera


func drive_yaw() -> float:
	return yaw


func is_first_person() -> bool:
	return first_person


func _apply_mouse_mode() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	var mobile_active := false if settings == null else bool(settings.call("is_mobile_ui_active"))
	if _ui_blocked or mobile_active:
		_orbiting = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif first_person or shift_locked or _orbiting:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _apply_orbit_delta(rel: Vector2) -> void:
	if mode_topdown:
		return
	var sens := 1.0
	var inv_y := false
	var inv_x := false
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		sens = maxf(float(settings.get("mouse_sensitivity")), 0.05)
		inv_y = bool(settings.get("invert_y"))
		inv_x = bool(settings.get("invert_x"))
	yaw += rel.x * 0.0032 * sens * (1.0 if inv_x else -1.0)
	pitch += rel.y * 0.0032 * sens * (1.0 if inv_y else -1.0)
	pitch = clampf(pitch, deg_to_rad(-72.0), deg_to_rad(80.0))


func _unhandled_input(event: InputEvent) -> void:
	if _ui_blocked:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			var vp_size := get_viewport().get_visible_rect().size
			var settings: Node = get_node_or_null("/root/Settings")
			var mobile_on := false if settings == null else bool(settings.call("is_mobile_ui_active"))
			# Ignore touches that start on the bottom-left thumbstick or bottom-right buttons
			if mobile_on and st.position.x < 240.0 and st.position.y > vp_size.y - 240.0:
				return
			if mobile_on and st.position.x > vp_size.x - 240.0 and st.position.y > vp_size.y - 200.0:
				return
			_touch_points[st.index] = st.position
		else:
			_touch_points.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touch_points.has(sd.index):
			return
		var prev_pos: Vector2 = _touch_points[sd.index]
		_touch_points[sd.index] = sd.position
		if _touch_points.size() == 1:
			_apply_orbit_delta(sd.relative)
		elif _touch_points.size() >= 2:
			var keys := _touch_points.keys()
			var k0: int = int(keys[0])
			var k1: int = int(keys[1])
			var p0: Vector2 = _touch_points[k0]
			var p1: Vector2 = _touch_points[k1]
			var old_p0 := prev_pos if sd.index == k0 else p0
			var old_p1 := prev_pos if sd.index == k1 else p1
			var old_dist := old_p0.distance_to(old_p1)
			var new_dist := p0.distance_to(p1)
			var delta_span := old_dist - new_dist
			if absf(delta_span) > 0.5:
				_zoom(delta_span * 0.08)
	elif event is InputEventMouseMotion:
		if not (_orbiting or is_mouse_captured()):
			return
		_apply_orbit_delta((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-_zoom_step())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(_zoom_step())
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mode_topdown:
			_orbiting = true
			_apply_mouse_mode()
	elif event is InputEventMouseButton and not event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = false
			_apply_mouse_mode()


func _zoom_step() -> float:
	return clampf(distance * 0.16, 1.2, 16.0)


func _zoom(step: float) -> void:
	var was := first_person
	var lo := TD_MIN_ZOOM if mode_topdown else MIN_ZOOM
	var hi := TD_MAX_ZOOM if mode_topdown else MAX_ZOOM
	_zoom_target = clampf(_zoom_target + step, lo, hi)
	if _zoom_target < FIRST_PERSON_AT:
		distance = _zoom_target
	first_person = _zoom_target < FIRST_PERSON_AT
	if first_person != was:
		first_person_changed.emit(first_person)
	_apply_mouse_mode()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_ensure_nodes()
	if first_person:
		distance = _zoom_target
	else:
		distance = lerpf(distance, _zoom_target, 1.0 - exp(-ZOOM_GLIDE * delta))
	if _land_dip > 0.001:
		_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * delta))
	else:
		_land_dip = 0.0
	var dip := _land_dip if not (first_person or mode_topdown) else 0.0
	if mode_topdown:
		global_position = player.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
		_pivot.rotation = Vector3(TD_PITCH, 0.0, 0.0)
		_arm.position = Vector3.ZERO
		_arm.spring_length = distance
	elif first_person:
		global_position = player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
		_pivot.rotation = Vector3(pitch, yaw, 0.0)
		_arm.position = Vector3.ZERO
		_arm.spring_length = 0.0
	else:
		global_position = player.global_position + Vector3(0.0, PIVOT_HEIGHT - dip, 0.0)
		_pivot.rotation = Vector3(pitch, yaw, 0.0)
		_arm.spring_length = distance
		_arm.position.x = SHOULDER_OFFSET if shift_locked else 0.0
