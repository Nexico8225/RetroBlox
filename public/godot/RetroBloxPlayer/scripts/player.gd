extends CharacterBody3D

## The classic player: capsule movement, account avatar, chat bubble.
## Built from scenes/player.tscn — instantiate that scene, add it to the
## tree, then call initialize(id, name). Remote players use render_remote().
##
## STUDS — 1 Godot unit = 1 Roblox stud. The avatar is 5 studs tall, the
## capsule matches, and every constant below is in studs/studs-per-second,
## using the classic numbers: WalkSpeed 16, JumpPower 50, gravity 196.2.
## Levels built from RetroPart scenes are automatically stud-accurate.

# classic movement — the exact defaults players remember
const WALK_SPEED: float = 16.0          # studs / second (classic WalkSpeed)
const JUMP_SPEED: float = 50.0          # studs / second (classic JumpPower)
const GRAVITY: float = 196.2            # studs / s² (classic workspace gravity)
const ACCEL_GROUND: float = 145.0       # reach full speed in ~0.11s: crisp, not slippery
const ACCEL_AIR: float = 62.0           # real air control — you can steer mid-jump
const BRAKE_GROUND: float = 170.0       # stop on release, classic style

# steps — walk over anything between a paper-thin lip and 3 studs (stairs!)
const MAX_STEP: float = 3.0
const MIN_STEP: float = 0.05
const STEP_FORWARD: float = 0.6         # how far we reach over the lip
const STEP_VISUAL_SPEED: float = 46.0   # how fast the body's visual catches up after a step

# ladders (TrussPart-style) — climb up while pushing forward, climb down
# while pressing back, jump to let go; plays the rig's Climb animation
const CLIMB_SPEED: float = 9.0
const LADDER_JUMP: float = 34.0

# classic health — big falls hurt, 1%/s regen after five quiet seconds
# (the Roblox default), zero health routes into the normal respawn flow
signal health_changed(health: float, max_health: float)
signal health_depleted

const MAX_HEALTH: float = 100.0
const REGEN_DELAY: float = 5.0
const REGEN_RATE: float = 1.0        # per second (1% of max, the classic default)
const FALL_SAFE_HEIGHT: float = 45.0 # studs of clean drop before it starts to hurt
const FALL_DMG_PER_STUD: float = 4.0

# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript := preload("res://scripts/retroblox_api.gd")
const AvatarPlatformScript := preload("res://scripts/avatar_platform.gd")

var peer_id: int = 0
var display_name: String = "Player"
var platform_user_id: String = ""   # RetroBlox account id — ALWAYS set (login only)
var is_remote: bool = false          # driven by the website heartbeat, not local input
var avatar: Node3D
var alive: bool = true
var life_epoch: int = 0
var heading: float = 0.0
var grounded: bool = false
var respawn_left: float = 0.0
var input_direction: Vector2 = Vector2.ZERO
var input_yaw: float = 0.0
var input_jump: int = 0
var input_shiftlock: bool = false
var shiftlock: bool = false
var consumed_jump: int = 0
var last_sequence: int = -1
var input_age: float = 0.0
var chat_last: float = -100.0
var target_position: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO
var target_heading: float = 0.0
var target_grounded: bool = false
var target_climbing: bool = false
var has_snapshot: bool = false
var bubble: Label3D
var bubble_remaining: float = 0.0
var correction: Vector3 = Vector3.ZERO
var health: float = MAX_HEALTH
var regen_wait: float = 0.0
var falling: bool = false
var fall_peak_y: float = 0.0
var climbing: bool = false           # on a ladder right now (drives the Climb anim)
var _ladder_count: int = 0
var _step_visual: float = 0.0        # avatar's downward offset that eases out after a step

func initialize(id: int, player_name: String) -> void:
        peer_id = id
        display_name = player_name
        name = "Player_%d" % id
        collision_layer = 4
        collision_mask = 1
        floor_snap_length = 0.5
        floor_max_angle = deg_to_rad(50.0)
        # the scene provides the capsule, the avatar and the chat bubble
        avatar = get_node("Avatar")
        avatar.configure(id, player_name)
        bubble = get_node("ChatBubble")
        bubble.visible = false
        _setup_ladder_sensor()

## Dress this player from a platform avatar payload
## (GET /api/platform/me for yourself, GET /api/users/{id}/avatar for others).
func dress_from_payload(api: RetrobloxApiScript, payload: Dictionary) -> void:
        if api == null or payload.is_empty():
                return
        await AvatarPlatformScript.apply(api, avatar, payload)

## One classic physics step. `direction` is the movement input (y<0 = forward),
## `camera_yaw` the camera orbit, `jump_serial` bumps on every fresh jump press.
func drive(delta: float, direction: Vector2, camera_yaw: float, jump_serial: int, use_shiftlock: bool = false) -> void:
        if not alive:
                return
        var wish := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, camera_yaw)
        if wish.length() > 1.0:
                wish = wish.normalized()

        # ---- ladders: touching a TrussPart-style ladder while pushing toward it
        # climbs it — forward = up, back = down, jump = let go. No gravity here.
        climbing = false
        if _ladder_count > 0:
                if jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        velocity.y = LADDER_JUMP
                        velocity.x = -wish.x * 6.0
                        velocity.z = -wish.z * 6.0
                elif direction.y < -0.2:
                        velocity.y = CLIMB_SPEED
                        climbing = true
                elif direction.y > 0.2:
                        velocity.y = -CLIMB_SPEED
                        climbing = true
                else:
                        velocity.y = 0.0
                        climbing = true
                # gentle slide toward the ladder so you hug it instead of hovering
                velocity.x = move_toward(velocity.x, 0.0, ACCEL_GROUND * delta)
                velocity.z = move_toward(velocity.z, 0.0, ACCEL_GROUND * delta)
        else:
                # ---- ground / air movement, classic response ----
                var accel: float = ACCEL_GROUND if is_on_floor() else ACCEL_AIR
                var target := wish * WALK_SPEED
                if wish.length_squared() < 0.005 and is_on_floor():
                        # no input on the ground: brake toward a clean stop
                        velocity.x = move_toward(velocity.x, 0.0, BRAKE_GROUND * delta)
                        velocity.z = move_toward(velocity.z, 0.0, BRAKE_GROUND * delta)
                else:
                        velocity.x = move_toward(velocity.x, target.x, accel * delta)
                        velocity.z = move_toward(velocity.z, target.z, accel * delta)
                if not is_on_floor():
                        velocity.y -= GRAVITY * delta
                elif velocity.y < 0.0:
                        velocity.y = 0.0
                if jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        if is_on_floor():
                                velocity.y = JUMP_SPEED

        move_and_slide()
        grounded = is_on_floor()
        if grounded and is_on_wall():
                _attempt_step_up()
        # facing — shift lock squares up to the camera, otherwise face the run
        if use_shiftlock:
                heading = lerp_angle(heading, camera_yaw, 1.0 - exp(-14.0 * delta))
        elif wish.length_squared() > 0.005:
                heading = lerp_angle(heading, atan2(-wish.x, -wish.z), 1.0 - exp(-18.0 * delta))
        # the avatar eases up to the body after a step — stairs look smooth,
        # the collision stays exact
        if _step_visual != 0.0:
                _step_visual = move_toward(_step_visual, 0.0, STEP_VISUAL_SPEED * delta)
                avatar.position.y = _step_visual
        _update_fall_damage()
        # passive regen — the classic 1%/s after five quiet seconds
        if regen_wait > 0.0:
                regen_wait -= delta
        elif health < MAX_HEALTH:
                health = minf(health + REGEN_RATE, MAX_HEALTH)
                health_changed.emit(health, MAX_HEALTH)
        avatar.rotation.y = heading

## STAIRS — walk over any ledge between MIN_STEP and MAX_STEP studs.
## Runs after move_and_slide when we ended up against a wall: measure the
## ledge with a downward ray from a raised position, and if the lip is in
## range and there is headroom, rise + reach over + settle onto the step.
func _attempt_step_up() -> void:
        var hvel := Vector3(velocity.x, 0.0, velocity.z)
        if hvel.length_squared() < 1.0:
                return
        var dir := hvel.normalized()
        var space := get_world_3d().direct_space_state
        if space == null:
                return
        var feet := global_position.y
        # 1) something low actually blocking straight ahead?
        var probe := PhysicsRayQueryParameters3D.create(
                global_position + Vector3(0.0, MIN_STEP + 0.15, 0.0),
                global_position + Vector3(0.0, MIN_STEP + 0.15, 0.0) + dir * 1.4,
                collision_mask
        )
        if space.intersect_ray(probe).is_empty():
                return
        # 2) headroom to rise the full step? (blocked above = ceiling, abort)
        if test_move(global_transform, Vector3.UP * MAX_STEP):
                return
        # 3) reach over the lip and measure the landing height with a ray
        var over := global_position + Vector3.UP * MAX_STEP + dir * STEP_FORWARD
        var down_ray := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (MAX_STEP + 0.4), collision_mask)
        var hit := space.intersect_ray(down_ray)
        if hit.is_empty():
                return  # nothing to land on at that height — it is a tall wall
        var lip: float = float(hit["position"].y) - feet
        if lip < MIN_STEP or lip > MAX_STEP + 0.01:
                return  # too tall (or we are already level) — jump like classic
        # 4) execute: rise, reach, settle. The body snaps; the avatar eases.
        move_and_collide(Vector3.UP * (lip + 0.06))
        move_and_collide(dir * STEP_FORWARD)
        var settle := move_and_collide(Vector3.DOWN * (lip + 0.2))
        if settle != null and velocity.y < 0.0:
                velocity.y = 0.0
        grounded = true
        _step_visual = minf(_step_visual - lip, -lip)
        if _step_visual < -MAX_STEP:
                _step_visual = -MAX_STEP

## Ladder sensor — one Area3D hugging the body; TrussPart-style ladders are
## Area3D nodes on layer 16 in the "ladder" group.
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
        shape_node.disabled = false
        area.add_child(shape_node)
        add_child(area)
        area.area_entered.connect(func(other: Area3D) -> void:
                if other.is_in_group("ladder"):
                        _ladder_count += 1)
        area.area_exited.connect(func(other: Area3D) -> void:
                if other.is_in_group("ladder"):
                        _ladder_count = maxi(_ladder_count - 1, 0))

## Fall damage — track the apex while airborne, hurt on landing.
func _update_fall_damage() -> void:
        if not alive:
                return
        if grounded:
                if falling:
                        falling = false
                        var drop: float = fall_peak_y - global_position.y
                        if drop > FALL_SAFE_HEIGHT:
                                hurt((drop - FALL_SAFE_HEIGHT) * FALL_DMG_PER_STUD)
        else:
                fall_peak_y = maxf(fall_peak_y, global_position.y) if falling else global_position.y
                falling = true

func render_remote(delta: float) -> void:
        if not alive or not has_snapshot:
                return
        global_position = global_position.lerp(target_position, 1.0 - exp(-18.0 * delta))
        heading = lerp_angle(heading, target_heading, 1.0 - exp(-18.0 * delta))
        avatar.rotation.y = heading
        velocity = target_velocity
        grounded = target_grounded
        climbing = target_climbing

## A remote player that just appeared: land it exactly where the website
## says instead of sliding in from the spawn pad.
func snap_remote(pos: Vector3) -> void:
        global_position = pos
        target_position = pos
        target_heading = 0.0
        has_snapshot = true
        heading = 0.0
        avatar.rotation.y = 0.0

func reconcile(delta: float) -> void:
        if not has_snapshot or not alive:
                return
        # Small local prediction correction, not production rewind/lag compensation.
        var amount := correction * (1.0 - exp(-8.0 * delta))
        global_position += amount
        correction -= amount

func accept_snapshot(pos: Vector3, vel: Vector3, yaw: float, floor_state: bool, local: bool, climbing_state: bool = false) -> void:
        target_position = pos
        target_velocity = vel
        target_heading = yaw
        target_grounded = floor_state
        target_climbing = climbing_state
        has_snapshot = true
        if local:
                var error := pos - global_position
                if error.length() > 3.0:
                        global_position = pos
                        velocity = vel
                        correction = Vector3.ZERO
                else:
                        # Ignore a small deadband to avoid needless micro-jitter.
                        correction = error if error.length() > 0.18 else Vector3.ZERO
                        if absf(error.y) > 1.3:
                                velocity.y = vel.y

func update_visuals(delta: float) -> void:
        if alive:
                avatar.animate(delta, Vector2(velocity.x, velocity.z).length(), grounded, climbing)
        if bubble_remaining > 0.0:
                bubble_remaining -= delta
                bubble.visible = alive and bubble_remaining > 0.0

func show_message(message: String) -> void:
        # Plain text only: markup cannot be injected.
        var words := message.split(" ")
        var lines: Array[String] = []
        var current := ""
        for word in words:
                if current.length() + word.length() > 28 and not current.is_empty():
                        lines.append(current)
                        current = ""
                current += (" " if not current.is_empty() else "") + word.left(28)
                if lines.size() >= 3:
                        break
        if lines.size() < 3 and not current.is_empty():
                lines.append(current)
        bubble.text = "\n".join(lines)
        bubble_remaining = 5.5
        bubble.visible = alive

## Damage API — amount <= 0 is a no-op; hitting 0 emits health_depleted
## (main.gd routes that into the normal reset/respawn flow).
func hurt(amount: float) -> void:
        if not alive or amount <= 0.0:
                return
        health = maxf(health - amount, 0.0)
        regen_wait = REGEN_DELAY
        health_changed.emit(health, MAX_HEALTH)
        if health <= 0.0:
                health_depleted.emit()

func heal(amount: float) -> void:
        if not alive or amount <= 0.0:
                return
        health = minf(health + amount, MAX_HEALTH)
        health_changed.emit(health, MAX_HEALTH)

func die(world: Node3D, epoch: int, seed_value: int) -> void:
        if epoch < life_epoch:
                return
        life_epoch = epoch
        alive = false
        health = 0.0
        health_changed.emit(health, MAX_HEALTH)
        velocity = Vector3.ZERO
        correction = Vector3.ZERO
        input_direction = Vector2.ZERO
        bubble.visible = false
        avatar.burst(world, seed_value)

func respawn_at(pos: Vector3, epoch: int) -> void:
        life_epoch = epoch
        alive = true
        health = MAX_HEALTH
        regen_wait = 0.0
        falling = false
        climbing = false
        _step_visual = 0.0
        if avatar != null:
                avatar.position.y = 0.0
        health_changed.emit(health, MAX_HEALTH)
        global_position = pos
        target_position = pos
        velocity = Vector3.ZERO
        target_velocity = Vector3.ZERO
        correction = Vector3.ZERO
        input_direction = Vector2.ZERO
        input_jump = 0
        consumed_jump = 0
        last_sequence = -1
        heading = 0.0
        target_heading = 0.0
        grounded = false
        has_snapshot = false
        avatar.rotation.y = 0.0
        avatar.visible = true
        bubble.visible = false
        bubble_remaining = 0.0
