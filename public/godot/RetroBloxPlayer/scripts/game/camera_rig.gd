extends Node3D
## CameraRig — the new orbit camera. Mouse-captured third person with a
## collision-aware spring arm, scroll zoom, and classic Shift Lock (the
## character squares up to the camera and it parks on the right shoulder).

const PIVOT_HEIGHT := 4.6      # look from just above the head
const MIN_ZOOM := 6.0
const MAX_ZOOM := 26.0
const DEFAULT_ZOOM := 14.0
const SHOULDER_OFFSET := 2.1   # shift-lock right-shoulder park

var player: Node3D
var yaw := 0.0
var pitch := -0.18
var distance := DEFAULT_ZOOM
var shift_locked := false

var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _mouse_captured := false


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
        _camera.near = 0.2
        _camera.far = 900.0
        _camera.current = true
        _arm.add_child(_camera)


func setup(p_player: Node3D) -> void:
        player = p_player
        set_physics_process(true)
        # settings: fov + sensitivity apply now and live-update while playing
        var settings: Node = get_node_or_null("/root/Settings")
        if settings != null:
                _camera.fov = float(settings.get("fov"))
                settings.changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, value: Variant) -> void:
        if key == "fov":
                _camera.fov = float(value)


func set_mouse_captured(captured: bool) -> void:
        _mouse_captured = captured
        var mode := Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
        Input.set_mouse_mode(mode)


func is_mouse_captured() -> bool:
        return _mouse_captured


func camera() -> Camera3D:
        return _camera


## The yaw the player controller should use for movement + facing.
func drive_yaw() -> float:
        return yaw


func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseMotion and _mouse_captured:
                var mm := event as InputEventMouseMotion
                var sens := 1.0
                var settings: Node = get_node_or_null("/root/Settings")
                if settings != null:
                        sens = maxf(float(settings.get("mouse_sensitivity")), 0.05)
                yaw -= mm.relative.x * 0.0032 * sens
                pitch -= mm.relative.y * 0.0032 * sens
                pitch = clampf(pitch, deg_to_rad(-72.0), deg_to_rad(78.0))
        elif event is InputEventMouseButton and event.is_pressed():
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
                        distance = clampf(distance - 2.0, MIN_ZOOM, MAX_ZOOM)
                elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        distance = clampf(distance + 2.0, MIN_ZOOM, MAX_ZOOM)


func _process(_delta: float) -> void:
        if player == null or not is_instance_valid(player):
                return
        var focus := player.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
        global_position = focus
        _pivot.rotation = Vector3(pitch, yaw, 0.0)
        _arm.spring_length = distance
        # shift lock: hug the right shoulder and keep the near plane tight
        _arm.position.x = SHOULDER_OFFSET if shift_locked else 0.0
