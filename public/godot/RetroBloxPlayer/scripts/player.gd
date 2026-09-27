extends CharacterBody3D

## The classic player: capsule movement, account avatar, chat bubble.
## Built from scenes/player.tscn — instantiate that scene, add it to the
## tree, then call initialize(id, name). Remote players use render_remote().

const WALK_SPEED: float = 8.0
const JUMP_SPEED: float = 11.0
const GRAVITY: float = 30.0

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

func initialize(id: int, player_name: String) -> void:
        peer_id = id
        display_name = player_name
        name = "Player_%d" % id
        collision_layer = 4
        collision_mask = 1
        floor_snap_length = 0.35
        floor_max_angle = deg_to_rad(46.0)
        # the scene provides the capsule, the avatar and the chat bubble
        avatar = get_node("Avatar")
        avatar.configure(id, player_name)
        bubble = get_node("ChatBubble")
        bubble.visible = false

## Dress this player from a platform avatar payload
## (GET /api/platform/me for yourself, GET /api/users/{id}/avatar for others).
func dress_from_payload(api: RetrobloxApi, payload: Dictionary) -> void:
        if api == null or payload.is_empty():
                return
        await AvatarPlatform.apply(api, avatar, payload)

func drive(delta: float, direction: Vector2, camera_yaw: float, jump_serial: int, use_shiftlock: bool = false) -> void:
        if not alive:
                return
        var wish := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, camera_yaw)
        if wish.length() > 1.0:
                wish = wish.normalized()
        # Fast classic movement, with a little air control and stop smoothing.
        var acceleration: float = 65.0 if is_on_floor() else 24.0
        velocity.x = move_toward(velocity.x, wish.x * WALK_SPEED, acceleration * delta)
        velocity.z = move_toward(velocity.z, wish.z * WALK_SPEED, acceleration * delta)
        if not is_on_floor():
                velocity.y -= GRAVITY * delta
        elif velocity.y < 0.0:
                velocity.y = 0.0
        if jump_serial > consumed_jump:
                consumed_jump = jump_serial
                if is_on_floor():
                        velocity.y = JUMP_SPEED
        if use_shiftlock:
                # Shift Lock: the character always squares up with the camera.
                heading = lerp_angle(heading, camera_yaw, 1.0 - exp(-14.0 * delta))
        elif wish.length_squared() > 0.005:
                heading = lerp_angle(heading, atan2(-wish.x, -wish.z), 1.0 - exp(-18.0 * delta))
        move_and_slide()
        grounded = is_on_floor()
        avatar.rotation.y = heading

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
                avatar.animate(delta, Vector2(velocity.x, velocity.z).length(), grounded)
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

func die(world: Node3D, epoch: int, seed_value: int) -> void:
        if epoch < life_epoch:
                return
        life_epoch = epoch
        alive = false
        velocity = Vector3.ZERO
        correction = Vector3.ZERO
        input_direction = Vector2.ZERO
        bubble.visible = false
        avatar.burst(world, seed_value)

func respawn_at(pos: Vector3, epoch: int) -> void:
        life_epoch = epoch
        alive = true
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
