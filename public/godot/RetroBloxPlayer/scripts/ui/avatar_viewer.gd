class_name AvatarViewer
extends SubViewportContainer
## v12.4 — the ESC menu's LIVE AVATAR. Not a photo: the player's actual rig
## standing on its own little 3D stage inside the card. DRAG to spin them
## around and see every side, drag up/down tilts, the wheel zooms in close.
## A slow turntable plays until the first grab so every card feels alive —
## after that it holds perfectly still so you can inspect them carefully.
##
## The stage renders ONLY while the menu is open (the visibility flip swaps
## the SubViewport between UPDATE_ALWAYS and UPDATE_DISABLED), so five
## players cost nothing while you're playing.

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")

const RIG_CENTER := Vector3(0.0, 2.5, 0.0)   # the rig is 5 studs tall, feet at origin
const START_DIST := 8.6
const MIN_DIST := 5.2
const MAX_DIST := 13.0
const IDLE_SPIN := 0.55                      # rad/s — the gentle turntable
const DRAG_SPEED := 0.011                    # rad per pixel

var _vp: SubViewport
var _cam: Camera3D
var _rig: Node3D
var _yaw := 0.0
var _pitch := 0.12
var _dist := START_DIST
var _dragging := false
var _grabbed := false          # once grabbed, the idle spin never returns
var _drag_pos := Vector2.ZERO


func _init() -> void:
        stretch = true
        custom_minimum_size = Vector2(0, 150)
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        size_flags_vertical = Control.SIZE_EXPAND_FILL
        mouse_filter = Control.MOUSE_FILTER_STOP
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        tooltip_text = "Drag to spin · wheel to zoom"


func _ready() -> void:
        _vp = SubViewport.new()
        _vp.name = "Stage"
        _vp.transparent_bg = true
        _vp.own_world_3d = true
        _vp.msaa_3d = Viewport.MSAA_2X
        _vp.disable_3d = false
        _vp.mesh_lod_threshold = 0.0
        _vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
        add_child(_vp)

        var env := WorldEnvironment.new()
        var e := Environment.new()
        e.background_mode = Environment.BG_COLOR
        e.background_color = Color(0, 0, 0, 0)
        e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        e.ambient_light_color = Color(0.9, 0.93, 1.0)
        e.ambient_light_energy = 0.85
        env.environment = e
        _vp.add_child(env)

        _cam = Camera3D.new()
        _cam.fov = 32.0
        _cam.current = true
        _vp.add_child(_cam)
        # the lights ride the CAMERA — whoever you orbit to, the face you're
        # looking at is always the lit one (the classic avatar-editor read)
        var key := DirectionalLight3D.new()
        key.rotation_degrees = Vector3(-24, 28, 0)   # front-left key
        key.light_energy = 1.15
        _cam.add_child(key)
        var fill := DirectionalLight3D.new()
        fill.rotation_degrees = Vector3(-10, 150, 0) # soft back rim
        fill.light_energy = 0.45
        _cam.add_child(fill)

        _update_camera()


## Dress the stage with the player's real look — the same payload the rig
## in the world wears. Safe to call once; the game resolves payloads.
func dress(api, payload: Dictionary) -> void:
        # the job can outrun the tree: the card enters the grid a frame
        # after it is built — hold until this stage is actually ready
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
        # await_all: hold until every shirt/face/hat stream landed so the
        # card never flashes a half-dressed body mid-turntable
        await AvatarDresserScript.apply(api, _rig, payload, true)
        if not is_instance_valid(self) or _rig == null or not is_instance_valid(_rig):
                return
        _rig.call("set_display_name", "")


func _notification(what: int) -> void:
        if what == NOTIFICATION_VISIBILITY_CHANGED and _vp != null and is_instance_valid(_vp):
                # render only while the menu actually shows the card
                if is_visible_in_tree():
                        _vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
                else:
                        _vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
        if _vp == null or not is_visible_in_tree():
                return
        if not _grabbed:
                _yaw += delta * IDLE_SPIN
                _update_camera()


func _update_camera() -> void:
        if _cam == null or not is_instance_valid(_cam):
                return
        var cp := cos(_pitch)
        var offset := Vector3(sin(_yaw) * cp, sin(_pitch), -cos(_yaw) * cp) * _dist
        _cam.position = RIG_CENTER + offset
        _cam.look_at(RIG_CENTER, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT:
                        _dragging = mb.pressed
                        if mb.pressed:
                                _grabbed = true
                                _drag_pos = mb.position
                        accept_event()
                elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
                        _dist = clampf(_dist - 0.7, MIN_DIST, MAX_DIST)
                        _update_camera()
                        accept_event()
                elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        _dist = clampf(_dist + 0.7, MIN_DIST, MAX_DIST)
                        _update_camera()
                        accept_event()
        elif event is InputEventMouseMotion and _dragging:
                var mm := event as InputEventMouseMotion
                var d := mm.position - _drag_pos
                _drag_pos = mm.position
                _yaw += d.x * DRAG_SPEED
                _pitch = clampf(_pitch + d.y * 0.007, -0.4, 0.9)
                _update_camera()
                accept_event()
