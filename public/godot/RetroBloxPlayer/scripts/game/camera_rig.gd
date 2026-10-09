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
        distance = clampf(distance + step, MIN_ZOOM, MAX_ZOOM)
        first_person = distance < FIRST_PERSON_AT
        if first_person != was:
                first_person_changed.emit(first_person)
        _apply_mouse_mode()


func _process(_delta: float) -> void:
        if player == null or not is_instance_valid(player):
                return
        if first_person:
                # the camera IS the head — no boom, no shoulder park
                global_position = player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
                _pivot.rotation = Vector3(pitch, yaw, 0.0)
                _arm.position = Vector3.ZERO
                _arm.spring_length = 0.0
        else:
                global_position = player.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
                _pivot.rotation = Vector3(pitch, yaw, 0.0)
                _arm.spring_length = distance
                # shift lock: hug the right shoulder and keep the near plane tight
                _arm.position.x = SHOULDER_OFFSET if shift_locked else 0.0
