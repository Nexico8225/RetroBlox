extends Node3D
## CameraRig — the classic orbit camera. The cursor stays FREE and usable in
## third person (hold the RIGHT mouse button to orbit), the scroll wheel zooms
## from true first person all the way out to the horizon, and Shift Lock
## (SHIFT) captures the cursor dead-center and squares the character to the
## camera. Zooming all the way in is first person: the camera becomes your
## eyes, the avatar hides, and the cursor locks in the middle just like
## shift lock.

signal first_person_changed(active: bool)

const PIVOT_HEIGHT := 4.6        # third-person look height (just above the head)
const EYE_HEIGHT := 4.5          # first-person eye height
const FIRST_PERSON_AT := 2.0     # zoom in past this = first person
const MIN_ZOOM := 0.0            # fully zoomed in = your eyes
const MAX_ZOOM := 120.0          # zoom out VERY far — see the whole place
const DEFAULT_ZOOM := 14.0
const SHOULDER_OFFSET := 2.1     # shift-lock right-shoulder park
## v4.0 game feel: the scroll wheel drives a TARGET distance and the arm
## glides to it — zooming reads butter-smooth instead of teleporting.
const ZOOM_GLIDE := 11.0
## v4.0 game feel: a hard landing dips the pivot a beat — the drop "lands".
const LAND_DIP_MAX := 0.55

var player: Node3D
var yaw := 0.0
var pitch := -0.18
var distance := DEFAULT_ZOOM
var shift_locked := false
var first_person := false

var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _ui_blocked := false         # menu / chat open — cursor free, no orbit
var _orbiting := false           # RMB held in third person
var _zoom_target := DEFAULT_ZOOM # the wheel's ask; distance glides to it
var _land_dip := 0.0             # current dip offset (studs, spring decay)


func _init() -> void:
        _pivot = Node3D.new()
        _pivot.name = "Pivot"
        add_child(_pivot)

        _arm = SpringArm3D.new()
        _arm.spring_length = DEFAULT_ZOOM
        _arm.collision_mask = 1
        _arm.margin = 0.4
        _pivot.add_child(_arm)

        _camera = Camera3D.new()
        _camera.fov = 70.0
        _camera.near = 0.1
        _camera.far = 1200.0
        _camera.current = true
        _arm.add_child(_camera)


func setup(p_player: Node3D) -> void:
        player = p_player
        var settings: Node = get_node_or_null("/root/Settings")
        if settings != null:
                _camera.fov = float(settings.get("fov"))
                settings.changed.connect(_on_setting_changed)
        _apply_mouse_mode()
        # v4.0: the landing dip — the rig may be a plain Node3D in tests
        if player != null and is_instance_valid(player) and player.has_signal("land_impact"):
                player.connect("land_impact", _on_land_impact)


## A hard landing asks for a dip sized to the impact; the spring in
## _process gives it back with a soft overshoot-free decay.
func _on_land_impact(speed: float) -> void:
        _land_dip = minf(speed / 50.0, 1.0) * LAND_DIP_MAX


func _on_setting_changed(key: String, value: Variant) -> void:
        if key == "fov":
                _camera.fov = float(value)


## Shift Lock toggle — squares the character to the camera and captures the
## cursor in the middle of the screen.
func set_shift_locked(on: bool) -> void:
        shift_locked = on
        _apply_mouse_mode()


## Menus and chat free the cursor and pause the orbit; gameplay restores it.
func set_ui_blocked(blocked: bool) -> void:
        _ui_blocked = blocked
        _apply_mouse_mode()


func is_mouse_captured() -> bool:
        return (first_person or shift_locked) and not _ui_blocked


func camera() -> Camera3D:
        return _camera


## The yaw the player controller should use for movement + facing.
func drive_yaw() -> float:
        return yaw


func is_first_person() -> bool:
        return first_person


## Cursor rules, classic style:
##   * menu / chat open              -> cursor visible and usable
##   * third person                  -> cursor visible and usable
##   * shift lock OR first person    -> cursor locked in the middle, hidden
func _apply_mouse_mode() -> void:
        if _ui_blocked:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        elif first_person or shift_locked:
                Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
        else:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
                # rotate when the cursor is captured (shift lock / first person)
                # OR while right-dragging in third person — never while using UI
                if _ui_blocked or not (_orbiting or is_mouse_captured()):
                        return
                var mm := event as InputEventMouseMotion
                var sens := 1.0
                var settings: Node = get_node_or_null("/root/Settings")
                if settings != null:
                        sens = maxf(float(settings.get("mouse_sensitivity")), 0.05)
                yaw -= mm.relative.x * 0.0032 * sens
                pitch -= mm.relative.y * 0.0032 * sens
                pitch = clampf(pitch, deg_to_rad(-72.0), deg_to_rad(80.0))
        elif event is InputEventMouseButton and event.is_pressed():
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
                        _zoom(-_zoom_step())
                elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        _zoom(_zoom_step())
                elif mb.button_index == MOUSE_BUTTON_RIGHT and not _ui_blocked:
                        _orbiting = true
        elif event is InputEventMouseButton and not event.is_pressed():
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_RIGHT:
                        _orbiting = false


## Zoom steps grow with distance: fine control up close, huge leaps far out.
func _zoom_step() -> float:
        return clampf(distance * 0.16, 1.2, 16.0)


func _zoom(step: float) -> void:
        var was := first_person
        _zoom_target = clampf(_zoom_target + step, MIN_ZOOM, MAX_ZOOM)
        if _zoom_target < FIRST_PERSON_AT:
                distance = _zoom_target   # first-person handoff stays instant
        first_person = _zoom_target < FIRST_PERSON_AT
        if first_person != was:
                first_person_changed.emit(first_person)
        _apply_mouse_mode()


func _process(delta: float) -> void:
        if player == null or not is_instance_valid(player):
                return
        # v4.0: the zoom glides — the wheel sets the target, the arm eases
        # there, and first-person still snaps the moment you cross the line
        if first_person:
                distance = _zoom_target
        else:
                distance = lerpf(distance, _zoom_target, 1.0 - exp(-ZOOM_GLIDE * delta))
        # the landing dip springs back — soft, quick, never floaty
        if _land_dip > 0.001:
                _land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * delta))
        else:
                _land_dip = 0.0
        var dip := _land_dip if not first_person else 0.0
        if first_person:
                # the camera IS the head — no boom, no shoulder park
                global_position = player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
                _pivot.rotation = Vector3(pitch, yaw, 0.0)
                _arm.position = Vector3.ZERO
                _arm.spring_length = 0.0
        else:
                global_position = player.global_position + Vector3(0.0, PIVOT_HEIGHT - dip, 0.0)
                _pivot.rotation = Vector3(pitch, yaw, 0.0)
                _arm.spring_length = distance
                # shift lock: hug the right shoulder and keep the near plane tight
                _arm.position.x = SHOULDER_OFFSET if shift_locked else 0.0
