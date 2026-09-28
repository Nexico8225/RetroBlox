extends CharacterBody3D

## The classic player: capsule movement, account avatar, chat bubble.
## Built from scenes/player.tscn — instantiate that scene, add it to the
## tree, then call initialize(id, name). Remote players use render_remote().
##
## STUDS — 1 Godot unit = 1 Roblox stud. The avatar is EXACTLY 5 studs tall,
## the capsule matches, and every setting below is in studs/studs-per-second.
## Levels built from RetroPart scenes are automatically stud-accurate.
## 1 stud = 0.28 meters (the classic Roblox stud) — the 5-stud character
## is exactly 1.4 m tall.

const STUD_METERS: float = 0.28         # 1 stud = 0.28 m — every size here is stud-native

## ------------------------------------------------------------------
## TUNABLE CHARACTER SETTINGS — select the player in the editor's Scene
## dock and edit them in the Inspector. These are the knobs devs change
## to make THEIR game feel right; the defaults are the classic numbers.
## (Everything is also editable from code: player.walk_speed = 24, etc.)
## ------------------------------------------------------------------

# Movement — classic WalkSpeed 16 with crisp, grippy response
const DEFAULT_WALK_SPEED: float = 16.0
const DEFAULT_WALK_ACCEL: float = 145.0     # reach full speed in ~0.11s: crisp, not slippery
const DEFAULT_AIR_ACCEL: float = 110.0      # classic air control — full steering mid-jump
const DEFAULT_GROUND_BRAKING: float = 170.0 # stop on release, classic style
@export_group("Movement")
@export var walk_speed: float = DEFAULT_WALK_SPEED          ## studs / second
@export var walk_acceleration: float = DEFAULT_WALK_ACCEL   ## studs / s²
@export var air_acceleration: float = DEFAULT_AIR_ACCEL     ## studs / s², mid-air steering
@export var ground_braking: float = DEFAULT_GROUND_BRAKING  ## studs / s², stopping power

# Jump — height in STUDS (easier to reason about than raw velocity),
# gravity in studs/s². The rise is gently eased (jump_up_gravity_scale < 1
# gives the jump a soft, readable arc instead of the old snap); the fall
# stays full-gravity so landings still feel classic and tight.
const DEFAULT_JUMP_HEIGHT: float = 6.0
const DEFAULT_GRAVITY: float = 196.2
const DEFAULT_JUMP_UP_GRAVITY_SCALE: float = 0.6
@export_group("Jump")
@export var jump_height: float = DEFAULT_JUMP_HEIGHT            ## how high the jump peaks, in studs
@export var gravity: float = DEFAULT_GRAVITY                    ## studs / s² (classic 196.2)
@export_range(0.3, 1.0, 0.05) var jump_up_gravity_scale: float = DEFAULT_JUMP_UP_GRAVITY_SCALE
                                                                ## < 1 = floatier, gentler rise

# Climbing — turn can_climb OFF to make a pure obby with no ladders/ledges
const DEFAULT_CLIMB_SPEED: float = 9.0
const DEFAULT_LADDER_JUMP: float = 46.0     # the leap off the ladder, slightly tamer than a ground jump
const DEFAULT_LADDER_PUSH: float = 13.0     # horizontal shove away from the face on jump-off
@export_group("Climbing")
@export var can_climb: bool = true                          ## allow ladders / ledges / rungs at all
@export var climb_speed: float = DEFAULT_CLIMB_SPEED        ## studs / second up and down
@export var ladder_jump: float = DEFAULT_LADDER_JUMP        ## jump-off impulse upward
@export var ladder_push: float = DEFAULT_LADDER_PUSH        ## jump-off shove away from the face

# Sounds — toggle the player's built-in effects (jump / land / footsteps)
@export_group("Sounds")
@export var play_footsteps: bool = true
@export var play_jump_sound: bool = true
@export var play_land_sound: bool = true

# obby forgiveness — the jump itself is untouched, just the timing edges
const COYOTE_TIME: float = 0.12         # you may still jump this long after walking off a ledge
const JUMP_BUFFER: float = 0.14         # a jump pressed just before landing still fires on touch-down

# steps — walk over anything between a paper-thin lip and 3 studs (stairs!)
const MAX_STEP: float = 3.0
const MIN_STEP: float = 0.05
const STEP_FORWARD: float = 0.6         # how far we reach over the lip
const STEP_VISUAL_SPEED: float = 46.0   # how fast the body's visual catches up after a step

# climbables (TrussPart-style ladders and auto-detected rungs) — you climb
# ONLY while facing the climbable face and pushing into it (W): facing
# backwards/left/right never sticks you on. W = up, S = down, nothing =
# hang on the spot; riding past a segment's top glides you up-and-forward
# onto the ledge (or seamlessly onto the next rung above), sliding past
# the bottom lets go, and SPACE leaps you OFF — a short cooldown then
# keeps you off the face while you fall back down, so jumping off works.
# Speed, leap impulse and the on/off switch are the exported settings above.
const LADDER_HUG: float = 2.6           # creep into the face while riding so you stay glued
const CLIMB_COOLDOWN: float = 0.35      # after a jump-off: falling, NOT re-sticking
const CLIMB_FACE_DOT: float = 0.5       # facing gate — you must press INTO the face
const CLIMB_GRAB_DISTANCE: float = 1.7  # how close to the face climb starts

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
var climbing: bool = false           # on a climbable right now (drives the Climb anim)
var _climbing: bool = false          # the persistent climb state machine
var _climb_cooldown: float = 0.0     # > 0 after a jump-off: falling, NOT re-sticking
var _ladder_zones: Dictionary = {}   # every climb zone currently overlapping the sensor
var _ladder_outward: Vector3 = Vector3.ZERO  # horizontal direction the riding face points in
var _coyote: float = 0.0             # seconds of jump grace left after leaving the ground
var _jump_buffer: float = 0.0        # seconds remaining on a buffered jump press
var _step_visual: float = 0.0        # avatar's downward offset that eases out after a step
var _air_fall_speed: float = 0.0     # fastest downward speed this airtime (drives the land thump)
var _step_timer: float = 0.0         # countdown between footstep sounds while walking

## Jump velocity that peaks exactly at `jump_height` under the eased rise
## gravity — height in studs is far easier to tune than raw launch speed.
func _jump_speed() -> float:
        var up_g: float = maxf(gravity * jump_up_gravity_scale, 0.1)
        return sqrt(2.0 * up_g * maxf(jump_height, 0.5))


## Fire one of the AudioStreamPlayer3D nodes placed in scenes/player.tscn
## (JumpSound / LandSound / StepSound). Missing node or stream = silent no-op,
## so stripping the sound nodes from the scene never breaks movement.
func _sfx(sfx_name: String, pitch: float = 1.0) -> void:
        var sfx := get_node_or_null(NodePath(sfx_name)) as AudioStreamPlayer3D
        if sfx == null or sfx.stream == null:
                return
        sfx.pitch_scale = pitch
        sfx.play()

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

        # ---- climbables — ladders and rungs. Entry needs ALL of: touching a
        # climb zone, pressing W, FACING the face, and being close to it.
        # Facing backwards/left/right never sticks you on. While riding:
        # W = up, S = down, nothing = hang; riding past a segment's top glides
        # you up-and-forward onto the ledge (or seamlessly onto the next rung
        # above), sliding past the bottom lets go, SPACE leaps you OFF and a
        # short cooldown keeps you off the face while you fall back down.
        _climb_cooldown = maxf(_climb_cooldown - delta, 0.0)
        var on_floor := is_on_floor()
        var touching: bool = not _ladder_zones.is_empty()
        if _climbing and not touching:
                _climbing = false          # the climbable ended above/below us
        if _climbing:
                var up_bounds := _climb_bounds(true)
                if jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        _climbing = false
                        _climb_cooldown = CLIMB_COOLDOWN
                        # THE LEAP OFF — up and away from the face; the cooldown
                        # means you fall back down instead of re-sticking to it
                        velocity.y = ladder_jump
                        var push := _ladder_outward * ladder_push
                        if wish.length_squared() > 0.005:
                                push += wish.normalized() * 7.0
                        velocity.x = push.x
                        velocity.z = push.z
                elif on_floor:
                        _climbing = false          # standing somewhere solid — walk, don't ride
                elif direction.y < -0.2:
                        if global_position.y < up_bounds.y - 0.45:
                                velocity.y = climb_speed
                                _hug_face(delta)
                        elif _climb_zone_above(up_bounds.y) != null:
                                # the next rung of a stacked build starts right
                                # above — ride on and chain onto it seamlessly
                                # (climb off the first stud, climb onto the second)
                                velocity.y = climb_speed
                                _hug_face(delta)
                        else:
                                _vault_ledge(up_bounds.y)   # top of the climb: mount
                elif direction.y > 0.2:
                        var down_bounds := _climb_bounds(false)
                        if global_position.y <= down_bounds.x + 0.15:
                                _climbing = false   # slid off the bottom — fall
                        else:
                                velocity.y = -climb_speed
                                _hug_face(delta)
                else:
                        velocity.y = 0.0           # hang on the spot
                        _hug_face(delta)
        elif touching and _climb_cooldown <= 0.0 and can_climb and direction.y < -0.2:
                # ENTER CLIMB — W into a face you are actually facing, up close,
                # with the face's top still at or above your chest (no grabbing
                # a rung from on top of it). can_climb = the dev's kill switch.
                var zone := _resolve_climb_zone(true, wish)
                if zone != null:
                        var outward := _ladder_outward_of(zone)
                        var face_dot := wish.normalized().dot(-outward) if wish.length_squared() > 0.005 else 0.0
                        var grabable: bool = face_dot >= CLIMB_FACE_DOT \
                                and _face_gap(zone) <= CLIMB_GRAB_DISTANCE \
                                and global_position.y + 2.6 <= _zone_top(zone) + 0.3
                        if grabable:
                                _climbing = true
                                _ladder_outward = outward
                                velocity.y = climb_speed
                                _hug_face(delta)
        if not _climbing:
                # ---- ground / air movement, classic response ----
                var accel: float = walk_acceleration if is_on_floor() else air_acceleration
                var target := wish * walk_speed
                if wish.length_squared() < 0.005 and is_on_floor():
                        # no input on the ground: brake toward a clean stop
                        velocity.x = move_toward(velocity.x, 0.0, ground_braking * delta)
                        velocity.z = move_toward(velocity.z, 0.0, ground_braking * delta)
                else:
                        velocity.x = move_toward(velocity.x, target.x, accel * delta)
                        velocity.z = move_toward(velocity.z, target.z, accel * delta)
                if not is_on_floor():
                        # eased rise, classic fall: gravity relaxes while you
                        # go UP (a soft, readable arc instead of the old snap)
                        # and bites at full strength on the way down
                        var g_scale: float = jump_up_gravity_scale if velocity.y > 0.0 else 1.0
                        velocity.y -= gravity * g_scale * delta
                        _air_fall_speed = minf(_air_fall_speed, velocity.y)
                elif velocity.y < 0.0:
                        velocity.y = 0.0
                # coyote time + jump buffering — the timing edges stay forgiving
                # for obby jumps; the arc itself comes from the settings above
                if is_on_floor():
                        _coyote = COYOTE_TIME
                else:
                        _coyote = maxf(_coyote - delta, 0.0)
                if jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        _jump_buffer = JUMP_BUFFER
                else:
                        _jump_buffer = maxf(_jump_buffer - delta, 0.0)
                if _jump_buffer > 0.0 and _coyote > 0.0:
                        _jump_buffer = 0.0
                        _coyote = 0.0
                        velocity.y = _jump_speed()
                        if play_jump_sound:
                                _sfx("JumpSound", randf_range(0.94, 1.06))

        climbing = _climbing
        move_and_slide()
        var was_grounded := grounded
        grounded = is_on_floor()
        if grounded and is_on_wall():
                _attempt_step_up()
        # ---- built-in sound effects (nodes live in scenes/player.tscn) ----
        if grounded and not was_grounded:
                # landing: only a real drop gets the thump, stair lips stay quiet
                if play_land_sound and _air_fall_speed < -14.0:
                        _sfx("LandSound", randf_range(0.92, 1.08))
                _air_fall_speed = 0.0
                _step_timer = 0.18   # first footstep lands right after touchdown
        elif not grounded:
                _air_fall_speed = minf(_air_fall_speed, velocity.y)
        var ground_speed := Vector2(velocity.x, velocity.z).length()
        if play_footsteps and grounded and ground_speed > 2.0:
                _step_timer -= delta * maxf(ground_speed / walk_speed, 0.4)
                if _step_timer <= 0.0:
                        _step_timer = 0.34
                        _sfx("StepSound", randf_range(0.88, 1.18))
        else:
                _step_timer = minf(_step_timer, 0.12)
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
## Area3D nodes on layer 16 in the "ladder" group. The touched ladder's
## outward direction is remembered so jumping off shoves you away from it.
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
        area.area_entered.connect(_on_ladder_area_entered)
        area.area_exited.connect(_on_ladder_area_exited)


func _on_ladder_area_entered(other: Area3D) -> void:
        if not other.is_in_group("ladder"):
                return
        _ladder_zones[other.get_instance_id()] = other
        if _ladder_outward == Vector3.ZERO:
                _ladder_outward = _ladder_outward_of(other)


func _on_ladder_area_exited(other: Area3D) -> void:
        if not other.is_in_group("ladder"):
                return
        _ladder_zones.erase(other.get_instance_id())
        if _ladder_zones.is_empty():
                _ladder_outward = Vector3.ZERO


## Ladder areas publish the direction their climbable face points in as the
## "outward" meta (in the ladder part's local space); trusses face +Z.
func _ladder_outward_of(ladder_area: Area3D) -> Vector3:
        var local: Vector3 = ladder_area.get_meta("outward", Vector3.BACK)
        var owner_part := ladder_area.get_parent() as Node3D
        if owner_part == null:
                return Vector3.ZERO
        var world := (owner_part.global_transform.basis * local)
        world.y = 0.0
        return world.normalized() if world.length_squared() > 0.0001 else Vector3.ZERO


## Pick the climbable segment we are riding from every zone overlapping the
## sensor. Stacked rungs all overlap the tall sensor at once, so the choice
## is POSITIONAL: the segment whose vertical band contains the chest wins;
## in a gap between two bands the next one in the travel direction wins —
## that is what makes climbing up run off the first stud and onto the second
## stud above it (and the reverse on the way down). A thin platform also
## carries one zone per open face — `face_hint` (the direction you push)
## breaks those ties toward the face you are actually standing in front of.
func _resolve_climb_zone(up: bool, face_hint: Vector3 = Vector3.ZERO) -> Area3D:
        var chest := global_position.y + 2.6
        var best: Area3D = null
        var best_score: float = -1000.0
        for value in _ladder_zones.values():
                var zone := value as Area3D
                if zone == null or not is_instance_valid(zone):
                        continue
                var part := zone.get_parent() as Node3D
                if part == null:
                        continue
                var half: float = _zone_half_height(zone)
                if half < 0.0:
                        continue
                var bottom: float = part.global_position.y - half
                var top: float = part.global_position.y + half
                var score: float
                if chest >= bottom - 0.35 and chest <= top + 0.35:
                        score = 100.0     # chest inside this segment's band
                else:
                        var dist: float = minf(absf(chest - bottom), absf(chest - top))
                        score = 50.0 - dist
                        if (up and top > chest) or (not up and bottom < chest):
                                score += 5.0   # prefer the next band in travel direction
                # multi-face parts: the face you push INTO outranks the others
                if face_hint.length_squared() > 0.005:
                        var outward := _ladder_outward_of(zone)
                        if outward != Vector3.ZERO and face_hint.normalized().dot(-outward) >= CLIMB_FACE_DOT:
                                score += 20.0
                if score > best_score:
                        best_score = score
                        best = zone
        return best


## Bottom (x) and top (y) of the segment we are riding, in world Y.
func _climb_bounds(up: bool) -> Vector2:
        var fallback := Vector2(global_position.y - 3.0, global_position.y + 3.0)
        var zone := _resolve_climb_zone(up)
        if zone == null or not is_instance_valid(zone):
                return fallback
        var half: float = _zone_half_height(zone)
        if half < 0.0:
                return fallback
        var part := zone.get_parent() as Node3D
        return Vector2(part.global_position.y - half, part.global_position.y + half)


## Half height of a zone's owner part along world Y (-1 when unmeasurable).
func _zone_half_height(zone: Area3D) -> float:
        var part := zone.get_parent() as Node3D
        if part == null:
                return -1.0
        var half: float = absf((part.global_transform.basis * Vector3(0.0, part.size.y * 0.5, 0.0)).y)
        return half if half >= 0.05 else 0.5


func _zone_top(zone: Area3D) -> float:
        var half: float = _zone_half_height(zone)
        var part := zone.get_parent() as Node3D
        if part == null or half < 0.0:
                return global_position.y + 3.0
        return part.global_position.y + half


## Another climb zone whose segment starts at/above `top_y` — the next rung
## in a stacked build. Cresting chains onto it instead of mounting.
func _climb_zone_above(top_y: float) -> Area3D:
        for value in _ladder_zones.values():
                var zone := value as Area3D
                if zone == null or not is_instance_valid(zone):
                        continue
                var half: float = _zone_half_height(zone)
                if half < 0.0:
                        continue
                var part := zone.get_parent() as Node3D
                if part.global_position.y - half >= top_y - 0.3:
                        return zone
        return null


## Crest vault — the top of the climb: rise above the lip, reach over and
## settle onto the standing surface behind the face. Same pattern as the
## stair step-up, so mounting feels like stepping up, not a leap of faith.
func _vault_ledge(top_y: float) -> void:
        _climbing = false
        _climb_cooldown = 0.3
        var lip: float = maxf(top_y - global_position.y + 0.25, 0.2)
        move_and_collide(Vector3.UP * lip)
        move_and_collide(-_ladder_outward * 1.2)
        var settle := move_and_collide(Vector3.DOWN * (lip + 0.6))
        if settle != null:
                velocity = Vector3.ZERO
                grounded = true
        else:
                # nothing to stand on up there — peel off and fall
                velocity = Vector3(-_ladder_outward.x * 2.0, -2.0, -_ladder_outward.z * 2.0)


## Horizontal distance from the body to a zone's climbable face plane
## (positive = in front of the face). Keeps the fat touch-sensor from
## magnet-sticking you onto a face you are not standing next to.
func _face_gap(zone: Area3D) -> float:
        if zone == null or not is_instance_valid(zone):
                return 999.0
        var part := zone.get_parent() as Node3D
        if part == null:
                return 999.0
        var local: Vector3 = zone.get_meta("outward", Vector3.BACK)
        var axis := local.abs()
        var depth: float = part.size.x * axis.x + part.size.y * axis.y + part.size.z * axis.z
        var outward: Vector3 = part.global_transform.basis * local
        outward.y = 0.0
        if outward.length_squared() < 0.0001:
                return 999.0
        outward = outward.normalized()
        var face: Vector3 = part.global_position + part.global_transform.basis * (local * (depth * 0.5))
        return (global_position - face).dot(outward)


## Creep toward the face while riding so the body stays glued to it.
func _hug_face(delta: float) -> void:
        velocity.x = move_toward(velocity.x, -_ladder_outward.x * LADDER_HUG, walk_acceleration * delta)
        velocity.z = move_toward(velocity.z, -_ladder_outward.z * LADDER_HUG, walk_acceleration * delta)

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
                # climbing animates from the VERTICAL speed (the climb cycle
                # tracks your up/down motion); everything else from ground speed
                var anim_speed: float = absf(velocity.y) if climbing else Vector2(velocity.x, velocity.z).length()
                avatar.animate(delta, anim_speed, grounded, climbing)
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
        _climbing = false
        _climb_cooldown = 0.0
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
        _air_fall_speed = 0.0
        _step_timer = 0.0
        avatar.rotation.y = 0.0
        avatar.visible = true
        bubble.visible = false
        bubble_remaining = 0.0
