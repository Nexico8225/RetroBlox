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

# steps — Minecraft-style: when you walk into a ledge you are TELEPORTED
# straight up onto it (collide + press W = on top). Anything between a
# paper-thin lip and 3 studs (stairs!) just works.
const MAX_STEP: float = 3.0
const MIN_STEP: float = 0.05
const STEP_PUSH: float = 0.9           # nudge forward after the step teleport

# ladders (TrussPart-style) — you only latch on when you are FACING the
# ladder and holding W. Push forward to climb up, back to climb down, and
# the Climb animation plays only while you actually move. SPACE jumps you
# off; looking back-left/back-right (shift lock) lets go too.
const CLIMB_SPEED: float = 9.0
const LADDER_JUMP: float = 34.0
const LADDER_JUMP_AWAY: float = 8.0    # horizontal push off the ladder
const CLIMB_FACING_DOT: float = 0.45   # must look at the ladder to grab it
const CLIMB_LOOKAWAY_DOT: float = -0.25  # looking back-ish lets go
const CLIMB_LOOKAWAY_TIME: float = 0.18  # ...held this long (no flicker)
const CLIMB_COOLDOWN: float = 0.4      # after a jump-off, before re-latch

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
var display_name: String = "Guest"
var platform_user_id: String = ""   # RetroBlox account id, "" for guests
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
var has_snapshot: bool = false
var bubble: Label3D
var bubble_remaining: float = 0.0
var correction: Vector3 = Vector3.ZERO
var health: float = MAX_HEALTH
var regen_wait: float = 0.0
var falling: bool = false
var fall_peak_y: float = 0.0
var climbing: bool = false           # on a ladder right now (drives the Climb anim)
var first_person: bool = false       # set by main.gd when the camera zooms all the way in
var _ladder_count: int = 0
var _wish: Vector3 = Vector3.ZERO    # input direction this frame (camera-relative)
var _ladder_dir: Vector3 = Vector3.ZERO  # horizontal direction toward the ladder we latched
var _climb_cooldown: float = 0.0
var _look_away: float = 0.0
var _climb_anim: bool = false         # true only while actually moving on a ladder
var _step_visual: float = 0.0        # avatar's downward offset that eases out after a step

func initialize(id: int, player_name: String) -> void:
        peer_id = id
        display_name = player_name
        name = "Player_%d" % id
        collision_layer = 4
        collision_mask = 1
        floor_snap_length = 0.5
        floor_max_angle = deg_to_rad(50.0)
        # Roblox-style wall behavior: EVERY wall contact slides, so walking
        # into a wall at any angle glides along it instead of sticking
        wall_min_slide_angle = 0.0
        max_slides = 6
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
        _wish = Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, camera_yaw)
        if _wish.length() > 1.0:
                _wish = _wish.normalized()
        if _climb_cooldown > 0.0:
                _climb_cooldown = maxf(_climb_cooldown - delta, 0.0)

        var jumped := false
        # ---- ladders: latch on ONLY when facing the ladder and holding W;
        # while climbing, W = up / S = down / nothing = hang still; SPACE or
        # looking away (shift lock) lets go. No gravity while on the ladder.
        var climbing_move := false
        if climbing:
                if _ladder_count <= 0:
                        climbing = false            # climbed past the top / stepped off
                elif jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        climbing = false
                        _climb_cooldown = CLIMB_COOLDOWN
                        velocity.y = LADDER_JUMP
                        velocity.x = -_ladder_dir.x * LADDER_JUMP_AWAY
                        velocity.z = -_ladder_dir.z * LADDER_JUMP_AWAY
                else:
                        # looking back-left / back-right / back (shift lock) lets go
                        var view := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
                        if view.dot(_ladder_dir) < CLIMB_LOOKAWAY_DOT:
                                _look_away += delta
                                if _look_away >= CLIMB_LOOKAWAY_TIME:
                                        climbing = false
                        else:
                                _look_away = 0.0
                if climbing:
                        if direction.y < -0.2:
                                velocity.y = CLIMB_SPEED
                                climbing_move = true
                        elif direction.y > 0.2:
                                velocity.y = -CLIMB_SPEED
                                climbing_move = true
                        else:
                                velocity.y = 0.0    # hang still — the anim stops too
                        # hug the ladder; face it like the classic truss
                        velocity.x = move_toward(velocity.x, 0.0, ACCEL_GROUND * delta)
                        velocity.z = move_toward(velocity.z, 0.0, ACCEL_GROUND * delta)
                        heading = lerp_angle(heading, atan2(-_ladder_dir.x, -_ladder_dir.z), 1.0 - exp(-16.0 * delta))
        elif _ladder_count > 0 and _climb_cooldown <= 0.0 and direction.y < -0.2 and _wish.length_squared() > 0.05:
                # entering: only when you are FACING the ladder and holding W
                var to_ladder := _nearest_ladder_dir()
                if to_ladder != Vector3.ZERO and _wish.dot(to_ladder) > CLIMB_FACING_DOT:
                        climbing = true
                        _ladder_dir = to_ladder
                        _look_away = 0.0
                        velocity.y = maxf(velocity.y, 0.0)

        if not climbing:
                # ---- ground / air movement, classic response ----
                var accel: float = ACCEL_GROUND if is_on_floor() else ACCEL_AIR
                var target := _wish * WALK_SPEED
                if _wish.length_squared() < 0.005 and is_on_floor():
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
                                jumped = true

        move_and_slide()
        grounded = is_on_floor()
        if grounded and not jumped:
                _attempt_step_up()
        # facing — shift lock squares up to the camera, otherwise face the run
        if climbing:
                pass  # heading already tracks the ladder
        elif use_shiftlock:
                heading = lerp_angle(heading, camera_yaw, 1.0 - exp(-14.0 * delta))
        elif _wish.length_squared() > 0.005:
                heading = lerp_angle(heading, atan2(-_wish.x, -_wish.z), 1.0 - exp(-18.0 * delta))
        # the avatar eases up to the body after a step — stairs look smooth,
        # the collision stays exact
        if _step_visual != 0.0:
                _step_visual = move_toward(_step_visual, 0.0, 46.0 * delta)
                avatar.position.y = _step_visual
        _update_fall_damage()
        # passive regen — the classic 1%/s after five quiet seconds
        if regen_wait > 0.0:
                regen_wait -= delta
        elif health < MAX_HEALTH:
                health = minf(health + REGEN_RATE, MAX_HEALTH)
                health_changed.emit(health, MAX_HEALTH)
        avatar.rotation.y = heading
        _climb_anim = climbing_move

## STAIRS — collide with a ledge + press W = teleported on top of it.
## Uses the INPUT direction (not the post-collision velocity, which is
## zeroed against the wall you are pushing into — the old bug that made
## stairs work only at diagonal angles). Measured with rays; teleported
## straight up when the lip is MIN_STEP..MAX_STEP high and there is
## headroom. Walls taller than MAX_STEP stay solid — you glide along them.
func _attempt_step_up() -> void:
        var dir := Vector3(_wish.x, 0.0, _wish.z)
        if dir.length_squared() < 0.2:
                return
        dir = dir.normalized()
        var space := get_world_3d().direct_space_state
        if space == null:
                return
        var feet := global_position.y
        var exclude: Array[RID] = [get_rid()]
        # 1) something actually blocking straight ahead at knee height?
        var probe := PhysicsRayQueryParameters3D.create(
                global_position + Vector3(0.0, 0.45, 0.0),
                global_position + Vector3(0.0, 0.45, 0.0) + dir * 1.6,
                collision_mask, exclude
        )
        probe.hit_from_inside = true
        var block := space.intersect_ray(probe)
        if block.is_empty():
                return
        # 2) headroom to stand on top of the step? (blocked above = ceiling)
        if test_move(global_transform, Vector3.UP * (MAX_STEP + 0.1)):
                return
        # 3) measure the landing height with a downward ray past the blocker
        var top_start: Vector3 = (block["position"] as Vector3) + dir * 0.3 + Vector3.UP * (MAX_STEP + 0.6)
        var down_ray := PhysicsRayQueryParameters3D.create(
                top_start, top_start + Vector3.DOWN * (MAX_STEP + 0.9), collision_mask, exclude
        )
        var hit := space.intersect_ray(down_ray)
        if hit.is_empty():
                return  # nothing to land on at that height — it is a tall wall
        var lip: float = float(hit["position"].y) - feet
        if lip < MIN_STEP or lip > MAX_STEP:
                return  # too tall (or already level) — jump like classic
        var rise: float = lip + 0.05
        if test_move(global_transform, Vector3.UP * rise):
                return
        # 4) THE TELEPORT: straight up onto the step, then a small push
        # forward so you stand ON it. The body snaps; the avatar eases.
        move_and_collide(Vector3.UP * rise)
        if not test_move(global_transform, dir * STEP_PUSH):
                move_and_collide(dir * STEP_PUSH)
        if velocity.y < 0.0:
                velocity.y = 0.0
        grounded = true
        _step_visual = -lip

## Horizontal direction toward the nearest ladder area we are touching.
func _nearest_ladder_dir() -> Vector3:
        var sensor := get_node_or_null("LadderSensor") as Area3D
        if sensor == null:
                return Vector3.ZERO
        var best: Vector3 = Vector3.ZERO
        var best_dist: float = INF
        for area in sensor.get_overlapping_areas():
                if not area.is_in_group("ladder"):
                        continue
                var offset := area.global_position - global_position
                offset.y = 0.0
                var dist := offset.length_squared()
                if dist < best_dist:
                        best_dist = dist
                        best = offset.normalized() if dist > 0.0001 else Vector3.ZERO
        return best

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

func reconcile(delta: float) -> void:
        if not has_snapshot or not alive:
                return
        # Small local prediction correction, not production rewind/lag compensation.
        var amount := correction * (1.0 - exp(-8.0 * delta))
        global_position += amount
        correction -= amount

func accept_snapshot(pos: Vector3, vel: Vector3, yaw: float, floor_state: bool, local: bool) -> void:
        target_position = pos
        target_velocity = vel
        target_heading = yaw
        target_grounded = floor_state
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
                var speed := Vector2(velocity.x, velocity.z).length()
                # the Climb clip only while actually moving on the ladder —
                # hang still and the animation stops with you
                avatar.animate(delta, speed, grounded, _climb_anim)
        if bubble_remaining > 0.0:
                bubble_remaining -= delta
                bubble.visible = alive and bubble_remaining > 0.0 and not first_person

func show_message(message: String) -> void:
        # Plain text only: markup cannot be injected.
        var words := message.split(" ")
        var lines: Array[String] = []
        var current := ""
        for word in words:
                if current.length() + word.length() > 30 and not current.is_empty():
                        lines.append(current)
                        current = ""
                current += (" " if not current.is_empty() else "") + word.left(30)
                if lines.size() >= 4:
                        break
        if lines.size() < 4 and not current.is_empty():
                lines.append(current)
        bubble.text = "\n".join(lines)
        bubble_remaining = 6.0
        bubble.visible = alive and not first_person

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
        climbing = false
        _climb_anim = false
        bubble.visible = false
        avatar.burst(world, seed_value)

## Where the death camera should look while this player is rebuilding —
## the falling torso piece, so the camera rides down with the body.
func death_focus() -> Vector3:
        if avatar != null and avatar.debris_torso != null and is_instance_valid(avatar.debris_torso):
                return avatar.debris_torso.global_position + Vector3.UP * 1.2
        return global_position + Vector3(0, 4.3, 0)

func respawn_at(pos: Vector3, epoch: int) -> void:
        life_epoch = epoch
        alive = true
        health = MAX_HEALTH
        regen_wait = 0.0
        falling = false
        climbing = false
        _climb_anim = false
        _climb_cooldown = 0.0
        _look_away = 0.0
        _ladder_dir = Vector3.ZERO
        first_person = false
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
