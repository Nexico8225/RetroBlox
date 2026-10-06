class_name LocalPlayer
extends CharacterBody3D
## The local player — brand-new classic controller for the new player system.
##
## STUDS: 1 Godot unit = 1 Roblox stud. The avatar is 5 studs tall, the
## capsule matches, and every constant is the classic number players remember:
## WalkSpeed 16, JumpPower 50, workspace gravity 196.2.
##
## Features: crisp ground accel + air control, 2.5-stud step-up (stairs),
## TrussPart-style ladders, trampolines, fall damage with the classic 1%/s
## regen, death breakup with the original oof, chat bubbles, nameplate.

signal health_changed(health: float, max_health: float)
signal health_depleted
signal touched_group(group: String, node: Node3D)

const WALK_SPEED := 16.0           # studs / second (classic WalkSpeed)
const JUMP_SPEED := 50.0           # studs / second (classic JumpPower)
const GRAVITY := 196.2             # studs / s^2 (classic workspace gravity)
const ACCEL_GROUND := 145.0        # reach full speed in ~0.11s: crisp, not slippery
const ACCEL_AIR := 62.0            # real air control — you can steer mid-jump
const BRAKE_GROUND := 170.0        # stop on release, classic style
const COYOTE_TIME := 0.08          # grace window after walking off a ledge
const JUMP_BUFFER := 0.12          # pressing jump just before landing still jumps

const MAX_STEP := 2.5              # walk over anything up to this height (stairs!)
const MIN_STEP := 0.05
const STEP_FORWARD := 0.6
const STEP_VISUAL_SPEED := 46.0

const CLIMB_SPEED := 9.0           # ladders: forward = up, back = down, jump = let go
const LADDER_JUMP := 34.0

const MAX_HEALTH := 100.0
const REGEN_DELAY := 5.0
const REGEN_RATE := 1.0            # per second (1% of max, the classic default)
const FALL_SAFE_HEIGHT := 45.0
const FALL_DMG_PER_STUD := 4.0
const BOUNCE_POWER := 72.0         # trampolines
const BOUNCE_COOLDOWN := 0.35

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")

var display_name := "Guest"
var avatar: Node3D
var alive := true
var health := MAX_HEALTH
var heading := 0.0
var grounded := false
var climbing := false
var spawn_point := Transform3D()
var wants_chat_input := false   # set by the game while the chat box is open

var _regen_wait := 0.0
var _falling := false
var _fall_peak_y := 0.0
var _ladder_count := 0
var _coyote := 0.0
var _jump_buffer_left := 0.0
var _step_visual := 0.0
var _bubble: Label3D
var _bubble_left := 0.0
var _bounce_cd := 0.0
var _time := 0.0
var _was_grounded := true
var _steps_loop: AudioStreamPlayer3D
var _climb_loop: AudioStreamPlayer3D


func _init() -> void:
        name = "LocalPlayer"
        collision_layer = 4
        collision_mask = 1
        floor_snap_length = 0.5
        floor_max_angle = deg_to_rad(50.0)

        var col := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 1.2
        capsule.height = 5.2
        col.shape = capsule
        col.position = Vector3(0.0, 2.6, 0.0)
        add_child(col)

        avatar = AvatarRigScript.new()
        avatar.name = "Avatar"
        add_child(avatar)

        _bubble = Label3D.new()
        _bubble.name = "ChatBubble"
        _bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        _bubble.pixel_size = 0.010
        _bubble.font_size = 40
        _bubble.outline_size = 8
        _bubble.width = 420.0
        _bubble.modulate = Color.WHITE
        _bubble.outline_modulate = Color(0, 0, 0, 0.9)
        _bubble.visible = false
        add_child(_bubble)
        _bubble.position = Vector3(0.0, 6.8, 0.0)

        _setup_ladder_sensor()
        _setup_touch_sensor()


func _ready() -> void:
        # autoloads are reachable from _ready — never from _init
        _setup_character_sfx()


## The classic character sounds — plastic footsteps while walking, the jump
## whoosh on takeoff, and the climb loop on ladders. All 3D, on the SFX bus.
func _setup_character_sfx() -> void:
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx == null:
                return
        _steps_loop = sfx.call("make_loop_3d", "Footsteps", self)
        _climb_loop = sfx.call("make_loop_3d", "ClimbLoop", self)
        if _climb_loop != null:
                _climb_loop.pitch_scale = 1.25


func setup(p_name: String) -> void:
        display_name = p_name
        avatar.call("setup", p_name)


## Dress from a platform avatar payload (null payload = classic noob guest).
func dress(api, payload: Dictionary) -> void:
        if payload.is_empty():
                return
        await AvatarDresserScript.apply(api, avatar, payload)


func _physics_process(delta: float) -> void:
        _time += delta
        if _bounce_cd > 0.0:
                _bounce_cd -= delta
        if _bubble_left > 0.0:
                _bubble_left -= delta
                _bubble.visible = alive and _bubble_left > 0.0
        _update_loops()


## One classic physics step. `direction.y < 0` = forward (W), cam_yaw orients
## the input, `just_pressed` is the raw jump press this frame.
func drive(delta: float, direction: Vector2, cam_yaw: float, just_pressed: bool, use_shiftlock: bool) -> void:
        if not alive:
                return
        var wish := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, cam_yaw)
        if wish.length() > 1.0:
                wish = wish.normalized()

        # jump buffering + coyote time — responsive without feeling floaty
        if just_pressed:
                _jump_buffer_left = JUMP_BUFFER
        elif _jump_buffer_left > 0.0:
                _jump_buffer_left -= delta
        if grounded:
                _coyote = COYOTE_TIME
        elif _coyote > 0.0:
                _coyote -= delta

        climbing = false
        if _ladder_count > 0:
                _drive_ladder(wish, delta)
        else:
                _drive_ground_air(wish, delta)

        move_and_slide()
        grounded = is_on_floor()
        if grounded and is_on_wall():
                _attempt_step_up()

        # facing — shift lock squares up to the camera, otherwise face the run
        if use_shiftlock:
                heading = lerp_angle(heading, cam_yaw, 1.0 - exp(-14.0 * delta))
        elif wish.length_squared() > 0.005:
                heading = lerp_angle(heading, atan2(-wish.x, -wish.z), 1.0 - exp(-18.0 * delta))

        # the avatar eases onto ledges after a step — stairs look smooth
        if _step_visual != 0.0:
                _step_visual = move_toward(_step_visual, 0.0, STEP_VISUAL_SPEED * delta)
                avatar.position.y = _step_visual

        _update_fall_damage()
        if _regen_wait > 0.0:
                _regen_wait -= delta
        elif health < MAX_HEALTH:
                health = minf(health + REGEN_RATE, MAX_HEALTH)
                health_changed.emit(health, MAX_HEALTH)
        avatar.rotation.y = heading
        # rig clips: Idle / Walk / Jump / Climb — driven by THIS player's state
        var hspeed := Vector2(velocity.x, velocity.z).length()
        avatar.call("animate", delta, hspeed, grounded, climbing)


func _drive_ladder(wish: Vector3, delta: float) -> void:
        # classic truss: hug the ladder, forward climbs up, back slides down
        var forward_amount := -wish.z  # -Z is forward after rotation
        if _jump_buffer_left > 0.0:
                _jump_buffer_left = 0.0
                velocity.y = LADDER_JUMP
                velocity.x = -wish.x * 6.0
                velocity.z = -wish.z * 6.0
        elif forward_amount > 0.2:
                velocity.y = CLIMB_SPEED
                climbing = true
        elif forward_amount < -0.2:
                velocity.y = -CLIMB_SPEED
                climbing = true
        else:
                velocity.y = 0.0
                climbing = true
        velocity.x = move_toward(velocity.x, 0.0, ACCEL_GROUND * delta)
        velocity.z = move_toward(velocity.z, 0.0, ACCEL_GROUND * delta)


func _drive_ground_air(wish: Vector3, delta: float) -> void:
        var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
        var target := wish * WALK_SPEED
        if wish.length_squared() < 0.005 and is_on_floor():
                velocity.x = move_toward(velocity.x, 0.0, BRAKE_GROUND * delta)
                velocity.z = move_toward(velocity.z, 0.0, BRAKE_GROUND * delta)
        else:
                velocity.x = move_toward(velocity.x, target.x, accel * delta)
                velocity.z = move_toward(velocity.z, target.z, accel * delta)
        if not is_on_floor():
                velocity.y -= GRAVITY * delta
        elif velocity.y < 0.0:
                velocity.y = 0.0
        if _jump_buffer_left > 0.0 and (is_on_floor() or _coyote > 0.0):
                _jump_buffer_left = 0.0
                _coyote = 0.0
                velocity.y = JUMP_SPEED
                _play_jump_sound()


## STAIRS — walk over any ledge between MIN_STEP and MAX_STEP studs. Measure
## the lip with rays; if it is in range with headroom, rise + reach + settle.
func _attempt_step_up() -> void:
        var hvel := Vector3(velocity.x, 0.0, velocity.z)
        if hvel.length_squared() < 1.0:
                return
        var dir := hvel.normalized()
        var space := get_world_3d().direct_space_state
        if space == null:
                return
        var feet := global_position.y
        var probe := PhysicsRayQueryParameters3D.create(
                global_position + Vector3(0.0, MIN_STEP + 0.15, 0.0),
                global_position + Vector3(0.0, MIN_STEP + 0.15, 0.0) + dir * 1.4,
                collision_mask)
        if space.intersect_ray(probe).is_empty():
                return
        if test_move(global_transform, Vector3.UP * MAX_STEP):
                return
        var over := global_position + Vector3.UP * MAX_STEP + dir * STEP_FORWARD
        var down_ray := PhysicsRayQueryParameters3D.create(
                over, over + Vector3.DOWN * (MAX_STEP + 0.4), collision_mask)
        var hit := space.intersect_ray(down_ray)
        if hit.is_empty():
                return
        var lip: float = float(hit["position"].y) - feet
        if lip < MIN_STEP or lip > MAX_STEP + 0.01:
                return
        move_and_collide(Vector3.UP * (lip + 0.06))
        move_and_collide(dir * STEP_FORWARD)
        var settle := move_and_collide(Vector3.DOWN * (lip + 0.2))
        if settle != null and velocity.y < 0.0:
                velocity.y = 0.0
        grounded = true
        _step_visual = minf(_step_visual - lip, -lip)
        if _step_visual < -MAX_STEP:
                _step_visual = -MAX_STEP


func _update_fall_damage() -> void:
        if not alive:
                return
        if grounded:
                if _falling:
                        _falling = false
                        var drop := _fall_peak_y - global_position.y
                        if drop > FALL_SAFE_HEIGHT:
                                hurt((drop - FALL_SAFE_HEIGHT) * FALL_DMG_PER_STUD)
        else:
                _fall_peak_y = maxf(_fall_peak_y, global_position.y) if _falling else global_position.y
                _falling = true


func show_bubble(message: String) -> void:
        # plain text only — markup cannot be injected
        var words := message.split(" ")
        var lines: Array[String] = []
        var current := ""
        for word in words:
                if current.length() + word.length() > 26 and not current.is_empty():
                        lines.append(current)
                        current = ""
                current += (" " if not current.is_empty() else "") + word.left(26)
                if lines.size() >= 3:
                        break
        if lines.size() < 3 and not current.is_empty():
                lines.append(current)
        _bubble.text = "\n".join(lines)
        _bubble_left = 5.5
        _bubble.visible = alive


func hurt(amount: float) -> void:
        if not alive or amount <= 0.0:
                return
        health = maxf(health - amount, 0.0)
        _regen_wait = REGEN_DELAY
        health_changed.emit(health, MAX_HEALTH)
        if health <= 0.0:
                health_depleted.emit()


func heal(amount: float) -> void:
        if not alive or amount <= 0.0:
                return
        health = minf(health + amount, MAX_HEALTH)
        health_changed.emit(health, MAX_HEALTH)


## Death: hide the avatar in a burst of debris + the classic oof.
func die(world: Node3D) -> void:
        if not alive:
                return
        alive = false
        health = 0.0
        health_changed.emit(health, MAX_HEALTH)
        velocity = Vector3.ZERO
        _bubble.visible = false
        avatar.call("burst", world, randi())


func respawn_at(pos: Vector3) -> void:
        alive = true
        health = MAX_HEALTH
        _regen_wait = 0.0
        _falling = false
        climbing = false
        _step_visual = 0.0
        _bubble_left = 0.0
        _bubble.visible = false
        avatar.position.y = 0.0
        health_changed.emit(health, MAX_HEALTH)
        global_position = pos
        velocity = Vector3.ZERO
        heading = 0.0
        avatar.rotation.y = 0.0
        avatar.visible = true


## Trampolines — the classic bounce pad launch.
func _do_bounce() -> void:
        if not alive or _bounce_cd > 0.0:
                return
        _bounce_cd = BOUNCE_COOLDOWN
        velocity.y = BOUNCE_POWER
        _falling = true
        _fall_peak_y = global_position.y
        _play_jump_sound(0.9)


# ---------------------------------------------------------------- sounds

func _play_jump_sound(_pitch := 1.0) -> void:
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx != null:
                sfx.call("play_jump_3d", self)


## Loops update: footsteps only while moving on the floor, climb loop only on
## ladders. The climb pitch rides the climb speed like the classic client.
func _update_loops() -> void:
        if _steps_loop == null or _climb_loop == null:
                return
        if not is_instance_valid(_steps_loop) or not is_instance_valid(_climb_loop):
                return
        var hspeed := Vector2(velocity.x, velocity.z).length()
        var walking := alive and grounded and not climbing and hspeed > 2.0
        _steps_loop.playing = walking
        if walking:
                _steps_loop.pitch_scale = clampf(0.85 + hspeed / WALK_SPEED * 0.35, 0.85, 1.3)
        _climb_loop.playing = alive and climbing


# ---------------------------------------------------------------- sensors

## TrussPart-style ladders are Area3D nodes on layer 16 in the "ladder" group.
func _setup_ladder_sensor() -> void:
        var area := Area3D.new()
        area.name = "LadderSensor"
        area.collision_layer = 0
        area.collision_mask = 16
        area.monitorable = false
        var shape_node := CollisionShape3D.new()
        var shape := CapsuleShape3D.new()
        shape.radius = 1.15
        shape.height = 5.2
        shape_node.shape = shape
        shape_node.position = Vector3(0.0, 2.6, 0.0)
        area.add_child(shape_node)
        add_child(area)
        area.area_entered.connect(func(other: Area3D) -> void:
                if other.is_in_group("ladder"):
                        _ladder_count += 1)
        area.area_exited.connect(func(other: Area3D) -> void:
                if other.is_in_group("ladder"):
                        _ladder_count = maxi(_ladder_count - 1, 0))


## Touch sensor for special parts: kill bricks, goals, checkpoints, bouncy
## pads. They are StaticBody3D nodes in the matching group on layer 1.
func _setup_touch_sensor() -> void:
        var area := Area3D.new()
        area.name = "TouchSensor"
        area.collision_layer = 0
        area.collision_mask = 1
        area.monitorable = false
        var shape_node := CollisionShape3D.new()
        var shape := CapsuleShape3D.new()
        shape.radius = 1.45
        shape.height = 5.4
        shape_node.shape = shape
        shape_node.position = Vector3(0.0, 2.6, 0.0)
        area.add_child(shape_node)
        add_child(area)
        area.body_entered.connect(func(other: Node3D) -> void:
                for g in ["kill", "goal", "checkpoint", "bounce"]:
                        if other.is_in_group(g):
                                if g == "bounce":
                                        _do_bounce()
                                        return
                                touched_group.emit(g, other)
                                return)
