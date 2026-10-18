extends CharacterBody3D
## The player. Classic feel: WalkSpeed 16, JumpPower 50, gravity 196.2 (studs).
## Tune the numbers below in the Inspector or right here, then press F5.

signal won
signal toast(msg: String)

const SPEED := 16.0          # studs / second
const JUMP := 50.0           # jump launch speed
const GRAVITY := 196.2       # studs / second^2
const BOUNCE := 85.0         # bounce pad launch speed
const CLIMB := 12.0          # ladder climb speed
const KILL_Y := -60.0        # falling below this respawns you
const MOUSE_SENS := 0.0035

var topdown := false         # the exporter sets this per template
var yaw := 0.0
var pitch := -0.9            # radians, negative = camera above
var spawn_pos := Vector3.ZERO
var checkpoint := Vector3.ZERO
var won_game := false

@onready var cam: Camera3D = $Camera

func _ready() -> void:
        spawn_pos = global_position
        checkpoint = global_position
        if topdown:
                yaw = 0.0
                pitch = -1.12
        else:
                pitch = -0.62
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not topdown:
                yaw -= event.relative.x * MOUSE_SENS
                pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.4, -0.12)
        elif event.is_action_pressed("ui_cancel"):
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
        if not is_on_floor():
                velocity.y -= GRAVITY * delta
        var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        var s := sin(yaw)
        var c := cos(yaw)
        # forward key = away from the camera (screen-up in top-down mode)
        var dir := Vector3(s * inp.y + c * inp.x, 0.0, c * inp.y - s * inp.x)
        velocity.x = dir.x * SPEED
        velocity.z = dir.z * SPEED
        if Input.is_action_just_pressed("jump") and is_on_floor():
                velocity.y = JUMP
        move_and_slide()
        _touch_scan(inp)
        if not topdown:
                var d := 16.0
                var off := Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * d
                cam.global_position = global_position + off + Vector3(0, 2.5, 0)
                cam.look_at(global_position + Vector3(0, 2.0, 0))
        else:
                var d := 42.0
                cam.global_position = global_position + Vector3(0, d * absf(sin(pitch)) + 2.0, d * absf(cos(pitch)))
                cam.look_at(global_position + Vector3(0, 1.5, 0))
        if global_position.y < KILL_Y and not won_game:
                _respawn()

func _touch_scan(inp: Vector2) -> void:
        for i in get_slide_collision_count():
                var col := get_slide_collision(i)
                var other := col.get_collider()
                if other == null:
                        continue
                if other.is_in_group("kill"):
                        if not won_game:
                                _respawn()
                        return
                elif other.is_in_group("goal"):
                        if not won_game:
                                won_game = true
                                won.emit()
                        return
                elif other.is_in_group("checkpoint"):
                        var top: Vector3 = other.global_position + Vector3(0, 2.5, 0)
                        if top.distance_to(checkpoint) > 1.0:
                                checkpoint = top
                                toast.emit("Checkpoint saved.")
                elif other.is_in_group("bounce") and is_on_floor():
                        velocity.y = BOUNCE
                elif other.is_in_group("ladder") and inp.y < -0.1:
                        velocity.y = CLIMB

func _respawn() -> void:
        global_position = checkpoint + Vector3(0, 1.5, 0)
        velocity = Vector3.ZERO
        toast.emit("You died. Back you go.")
