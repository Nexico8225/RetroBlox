class_name LocalPlayer
extends CharacterBody3D
## The local player — brand-new classic controller for the new player system.
##
## SCALE — the classic size: 1 stud = 1 Godot unit. The avatar is 5 studs
## tall, and every constant here is authored in studs
## and multiplied by STUD, so the classic numbers still rule the feel:
## WalkSpeed 16, JumpPower 50, workspace gravity 196.2.
##
## Features: crisp ground accel + air control, 2.5-stud step-up (stairs),
## TrussPart-style ladders (even ones built from segments with 1-3 stud gaps
## between them — the climb grace carries you across the gap), stud-edge
## climbing (walk into any studded platform edge while FACING it and W climbs
## it, Roblox style), mantle over the top lip. While climbing the torso locks
## onto the ladder / wall face — it never twists left or right — and the
## Climb clip can't break from body spin. S climbs down, Space jumps off,
## trampolines, fall damage with the
## classic 1%/s regen, death breakup with the original oof.

signal health_changed(health: float, max_health: float)
signal health_depleted
signal touched_group(group: String, node: Node3D)

## One stud in Godot units — shared by the world
## builder, camera and avatar rig. A player is 5 studs tall.
const STUD := 1.0

const WALK_SPEED := 16.0 * STUD   # studs / second (classic WalkSpeed)
const JUMP_SPEED := 50.0 * STUD   # studs / second (classic JumpPower)
const GRAVITY := 196.2 * STUD     # studs / s^2 (classic workspace gravity)
const ACCEL_GROUND := 145.0 * STUD  # reach full speed in ~0.11s: crisp
const ACCEL_AIR := 62.0 * STUD    # real air control — you can steer mid-jump
const BRAKE_GROUND := 170.0 * STUD  # stop on release, classic style
const COYOTE_TIME := 0.08         # grace window after walking off a ledge
const JUMP_BUFFER := 0.12         # pressing jump just before landing still jumps

const MAX_STEP := 2.5 * STUD      # walk over anything up to this height (stairs!)
const MIN_STEP := 0.05 * STUD
const STEP_FORWARD := 0.6 * STUD
const STEP_PROBE_AHEAD := 1.7 * STUD  # down-ray lands BEYOND the capsule radius
const STEP_VISUAL_SPEED := 46.0 * STUD

const CLIMB_SPEED := 9.0 * STUD   # ladders + stud edges: W = up, S = down
const LADDER_JUMP := 34.0 * STUD  # jump-off launch
const LADDER_DISMOUNT := 0.35     # after a climb jump you fly FREE this long

## CLIMB FACING — you must FACE the surface to climb it (Roblox truss rule).
## v3.6: grabbing is DELIBERATE now — you have to be squared up to the face
## AND clearly pressing into it. Brushing a wall at an angle just walks past
## (that grab-on-touch was the big jank: it yanked you off your run).
const CLIMB_FACE_START := 0.65   # dot(heading, to surface) needed to grab
const CLIMB_FACE_STAY := 0.35    # fall below this while climbing = let go + fall
const CLIMB_GRACE := 0.45         # seconds the climb survives rung/gap stretches
const WALL_REACH := 3.0 * STUD    # probe ray length for stud edges
const HUG_PRESSURE := 1.2 * STUD  # gentle push into the surface while climbing
## A climb only STARTS on faces that are TORSO-height or taller (2.7 studs):
## 1-2 stud steps stay stairs (the step-up walks over them) — touching a low
## step with your legs must NEVER put the body into the climb grip.
const WALL_GRAB_MIN_H := 2.7 * STUD
## Heights (studs above the feet) of the vertical probe rays — spread so
## plate towers with gaps always have at least one ray on a plate.
const WALL_PROBE_HS: Array = [0.5, 1.7, 2.7, 2.9, 4.1]

const LAND_SOUND_FALL := 22.0 * STUD  # impact speed that triggers the landing thud
const FALL_WIND_SPEED := 34.0 * STUD  # downward speed where the wind loop kicks in

const MAX_HEALTH := 100.0
const REGEN_DELAY := 5.0
const REGEN_RATE := 1.0            # per second (1% of max, the classic default)
const FALL_SAFE_HEIGHT := 45.0     # studs — below this, no damage
const FALL_DMG_PER_STUD := 4.0
const BOUNCE_POWER := 72.0 * STUD  # trampolines
const BOUNCE_COOLDOWN := 0.35

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")
const ChatBubbleScript := preload("res://scripts/player/chat_bubble.gd")

enum ClimbKind { NONE, LADDER, WALL }

var display_name := "Guest"
var avatar: Node3D
var bubble: ChatBubble
var alive := true
var health := MAX_HEALTH
var heading := 0.0
var grounded := false
var climbing := false
var spawn_point := Transform3D()
var wants_chat_input := false   # set by the game while the chat box is open
var dust_enabled := true        # landing / jump dust puffs (the game can turn these off)

var _regen_wait := 0.0
var _falling := false
var _fall_peak_y := 0.0
var _ladder_areas: Array[Area3D] = []
var _climb_kind: int = ClimbKind.NONE
var _climb_face := Vector3.ZERO  # direction to FACE to stay on the surface
var _climb_grace := 0.0
var _coyote := 0.0
var _jump_buffer_left := 0.0
var _step_visual := 0.0
var _step_dir := Vector3.ZERO     # last walk wish — step-ups probe THIS, not
                                  # the slid velocity (a head-on wall zeroes it)
var _bounce_cd := 0.0
var _time := 0.0
var _steps_loop: AudioStreamPlayer3D
var _climb_loop: AudioStreamPlayer3D
var _fall_loop: AudioStreamPlayer3D
var _ladder_dismount := 0.0
var _input_shiftlock := false     # live input flags (ladder-grip rules)
var _input_first_person := false
var _last_vy := 0.0


func _init() -> void:
        name = "LocalPlayer"
        collision_layer = 4
        collision_mask = 1
        floor_snap_length = 0.5 * STUD
        floor_max_angle = deg_to_rad(50.0)

        var col := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 1.2 * STUD
        capsule.height = 5.2 * STUD
        col.shape = capsule
        col.position = Vector3(0.0, 2.6 * STUD, 0.0)
        add_child(col)

        avatar = AvatarRigScript.new()
        avatar.name = "Avatar"
        add_child(avatar)

        bubble = ChatBubbleScript.new()
        bubble.name = "ChatBubble"
        add_child(bubble)

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
        _fall_loop = sfx.call("make_loop_3d", "FallingLoop", self)
        if _climb_loop != null:
                _climb_loop.pitch_scale = 1.25


func setup(p_name: String) -> void:
        display_name = p_name
        avatar.call("setup", p_name)


## The classic white bubble over YOUR head too — everyone's chat shows.
func show_bubble(message: String) -> void:
        bubble.show_text(message)


## Dress from a platform avatar payload (null payload = classic noob guest).
func dress(api, payload: Dictionary) -> void:
        if payload.is_empty():
                return
        await AvatarDresserScript.apply(api, avatar, payload)


func _physics_process(delta: float) -> void:
        _time += delta
        if _bounce_cd > 0.0:
                _bounce_cd -= delta
        _update_loops()


## One classic physics step. `direction.y < 0` = forward (W), cam_yaw orients
## the input, `just_pressed` is the raw jump press this frame and `jump_held`
## says the key is STILL down — holding Space hops over and over (classic
## hold-to-jump). `first_person` locks the body to the camera yaw like shift
## lock, but ladders still climb.
func drive(delta: float, direction: Vector2, cam_yaw: float, just_pressed: bool, use_shiftlock: bool, first_person := false, jump_held := false) -> void:
        if not alive:
                return
        _input_shiftlock = use_shiftlock
        _input_first_person = first_person
        var wish := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, cam_yaw)
        if wish.length() > 1.0:
                wish = wish.normalized()
        if wish.length_squared() > 0.005:
                _step_dir = wish.normalized()

        # jump buffering + coyote time — responsive without feeling floaty.
        # HOLDING the key re-fills the buffer every grounded frame, so the
        # player keeps hopping the moment they land (classic bunny hop)
        if just_pressed:
                _jump_buffer_left = JUMP_BUFFER
        elif jump_held and (grounded or _coyote > 0.0) and _climb_kind == ClimbKind.NONE:
                _jump_buffer_left = JUMP_BUFFER
        elif _jump_buffer_left > 0.0:
                _jump_buffer_left -= delta
        if grounded:
                _coyote = COYOTE_TIME
        elif _coyote > 0.0:
                _coyote -= delta

        if _ladder_dismount > 0.0:
                _ladder_dismount -= delta

        # facing — while CLIMBING the torso locks onto the ladder / wall face
        # and NEVER twists left or right: A/D and S climb and duck without
        # spinning the body, so the grip — and the Climb clip — cannot break
        # from body spin. Shift lock / first person square up to the camera;
        # otherwise face the run.
        if _climb_kind != ClimbKind.NONE:
                heading = lerp_angle(heading, atan2(-_climb_face.x, -_climb_face.z), 1.0 - exp(-22.0 * delta))
        elif use_shiftlock or first_person:
                heading = lerp_angle(heading, cam_yaw, 1.0 - exp(-14.0 * delta))
        elif wish.length_squared() > 0.005:
                heading = lerp_angle(heading, atan2(-wish.x, -wish.z), 1.0 - exp(-18.0 * delta))

        _update_climb(wish, delta)
        if _climb_kind != ClimbKind.NONE:
                _drive_climb(wish, delta)
                # FACE CHECK — now only a safety net (heading is locked to the
                # surface): something truly shoving the view off the wall
                # still lets go and falls.
                var forward := Vector3(-sin(heading), 0.0, -cos(heading))
                if forward.dot(_climb_face) < CLIMB_FACE_STAY:
                        _stop_climb()
                        velocity.y -= GRAVITY * delta
        else:
                _drive_ground_air(wish, delta)

        move_and_slide()
        var was_grounded := grounded
        grounded = is_on_floor()
        # landing thud after real air time (Roblox plays jump_land on impact)
        if grounded and not was_grounded and _last_vy < -LAND_SOUND_FALL:
                _play_land_sound()
                _dust(clampf(-_last_vy / (40.0 * STUD), 1.0, 1.8))
        if grounded and is_on_wall() and _climb_kind == ClimbKind.NONE:
                _attempt_step_up()

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
        _last_vy = velocity.y
        avatar.rotation.y = heading
        # rig clips: Idle / Walk / Jump / Climb — driven by THIS player's state
        var hspeed := Vector2(velocity.x, velocity.z).length()
        var anim_speed := absf(velocity.y) if climbing else hspeed
        avatar.call("animate", delta, anim_speed, grounded, climbing)


# ---------------------------------------------------------------- climbing

## Decide whether this frame climbs — ladders (TrussPart volumes) or stud
## edges (any vertical wall you walk into while facing it). Holding W into
## the surface grabs on; the grace window carries you across 1-3 stud gaps
## between ladder segments or rung plates without dropping.
func _update_climb(wish: Vector3, delta: float) -> void:
        # standing on the floor without pressing INTO the surface = not a
        # climb: idle at a wall, or S down into the ground = simply let go
        if _climb_kind != ClimbKind.NONE and grounded and wish.dot(_climb_face) <= 0.2:
                _stop_climb()
                return
        if _climb_kind == ClimbKind.LADDER:
                if not _ladder_areas.is_empty():
                        var lad: Area3D = _nearest_ladder()
                        var face := _toward(lad)
                        # a volume the body has crossed through would report
                        # the OPPOSITE face — keep the grabbed face instead
                        # (the hug pressure pulls the body back onto the rungs)
                        if face != Vector3.ZERO and face.dot(_climb_face) > -0.5:
                                _climb_face = face
                        _climb_grace = CLIMB_GRACE
                        return
                        # still inside the rungs — all good
                # left the volume: a gap between segments, or the top of the
                # ladder. Hold the grip for CLIMB_GRACE while still facing in.
                _climb_grace -= delta
                if wish.dot(_climb_face) > 0.2 and _try_mantle():
                        return
                if _climb_grace <= 0.0 or wish.dot(_climb_face) < -0.2:
                        _stop_climb()
                return

        if _climb_kind == ClimbKind.WALL:
                var normal := _wall_hit_along(_climb_face)
                if normal != Vector3.ZERO:
                        _climb_face = -normal
                        _climb_grace = CLIMB_GRACE
                        return
                # past the lip (top of the platform) — mantle onto it, Roblox style
                _climb_grace -= delta
                if wish.dot(_climb_face) > 0.2 and _try_mantle():
                        return
                if _climb_grace <= 0.0 or wish.dot(_climb_face) < -0.2:
                        _stop_climb()
                return

        # --- not climbing: can we grab on? ---
        if _ladder_dismount > 0.0:
                return
        # shift lock walks straight past ladders (the classic feel) — first
        # person and normal third person climb them like always
        var ladder_ok := not _input_shiftlock or _input_first_person
        # ladders first: touching a rung volume + pressing into it + facing it
        if ladder_ok and not _ladder_areas.is_empty():
                var lad: Area3D = _nearest_ladder()
                var face := _toward(lad)
                if face != Vector3.ZERO and wish.dot(face) > 0.4:
                        var forward := Vector3(-sin(heading), 0.0, -cos(heading))
                        if forward.dot(face) >= CLIMB_FACE_START:
                                _climb_kind = ClimbKind.LADDER
                                _climb_face = face
                                _climb_grace = CLIMB_GRACE
                                return
        # stud edges: probing along the walk direction finds a vertical face.
        # Only faces that reach TORSO height (>= ~2.7 studs) count — a 1-2
        # stud step under your legs is STAIRS (step-up), never the climb grip.
        # v3.6: the press must be CLEARLY into the face (> 0.5) — strolling
        # past at an angle never grabs anymore.
        if wish.length_squared() > 0.04:
                var normal := _wall_hit_along(wish, WALL_GRAB_MIN_H / STUD)
                if normal != Vector3.ZERO:
                        var face := -normal
                        var forward := Vector3(-sin(heading), 0.0, -cos(heading))
                        if wish.dot(face) > 0.5 and forward.dot(face) >= CLIMB_FACE_START:
                                _climb_kind = ClimbKind.WALL
                                _climb_face = face
                                _climb_grace = CLIMB_GRACE


## One climb physics step: W = up, S = down, nothing pressed = hug, Space =
## jump OFF (same jump-off as always). Gravity does not apply on the surface.
func _drive_climb(wish: Vector3, _delta: float) -> void:
        var up_amount := wish.dot(_climb_face)
        if _jump_buffer_left > 0.0:
                _jump_buffer_left = 0.0
                _ladder_dismount = LADDER_DISMOUNT   # fly free, no instant re-grab
                velocity.y = LADDER_JUMP
                velocity.x = -_climb_face.x * 8.0 * STUD  # push OFF the surface
                velocity.z = -_climb_face.z * 8.0 * STUD
                _stop_climb()
        elif up_amount > 0.2:
                velocity.y = CLIMB_SPEED
                climbing = true
        elif up_amount < -0.2:
                velocity.y = -CLIMB_SPEED
                climbing = true
        else:
                velocity.y = 0.0
                climbing = true
        # hug the surface — a whisper of pressure keeps the body glued on
        velocity.x = _climb_face.x * HUG_PRESSURE
        velocity.z = _climb_face.z * HUG_PRESSURE


func _stop_climb() -> void:
        _climb_kind = ClimbKind.NONE
        climbing = false
        _climb_grace = 0.0


func _nearest_ladder() -> Area3D:
        var best: Area3D = null
        var best_d := INF
        for lad in _ladder_areas:
                if not is_instance_valid(lad):
                        continue
                var d := lad.global_position.distance_squared_to(global_position)
                if d < best_d:
                        best_d = d
                        best = lad
        return best


## Horizontal unit vector from the body toward a ladder volume (the way you
## must FACE to climb it). ZERO when standing inside it.
func _toward(lad: Area3D) -> Vector3:
        var to := lad.global_position - global_position
        to.y = 0.0
        if to.length_squared() < 0.0016:
                return Vector3.ZERO
        return to.normalized()


## Probe a few rays spread up the body along `dir`; the first vertical face
## they find (a stud platform edge, a plate in a gapped rung tower) wins.
## `min_h` (studs) skips low probes — used when STARTING a climb so shallow
## steps (1 stud) keep using the step-up instead of the climb grip.
func _wall_hit_along(dir: Vector3, min_h := 0.0) -> Vector3:
        var d := Vector3(dir.x, 0.0, dir.z)
        if d.length_squared() < 0.001:
                return Vector3.ZERO
        d = d.normalized()
        var space := get_world_3d().direct_space_state
        if space == null:
                return Vector3.ZERO
        for raw_h: float in WALL_PROBE_HS:
                if raw_h < min_h:
                        continue
                var from := global_position + Vector3.UP * (raw_h * STUD)
                var query := PhysicsRayQueryParameters3D.create(from, from + d * WALL_REACH, collision_mask)
                var hit := space.intersect_ray(query)
                if hit.is_empty():
                        continue
                var normal: Vector3 = hit["normal"]
                if absf(normal.y) < 0.4:
                        return normal
        return Vector3.ZERO


## Climbed past the top lip: pop up onto the platform, Roblox style.
func _try_mantle() -> bool:
        var f := Vector3(_climb_face.x, 0.0, _climb_face.z).normalized()
        var space := get_world_3d().direct_space_state
        if space == null:
                return false
        var over := global_position + f * STEP_FORWARD + Vector3.UP * MAX_STEP
        var down := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * MAX_STEP, collision_mask)
        var hit := space.intersect_ray(down)
        if hit.is_empty():
                return false
        var lip: float = float(hit["position"].y) - global_position.y
        if lip < MIN_STEP or lip > MAX_STEP + 0.01:
                return false
        move_and_collide(Vector3.UP * (lip + 0.06))
        move_and_collide(f * STEP_FORWARD * 2.0)
        velocity = Vector3.ZERO
        _stop_climb()
        grounded = true
        return true


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
                _dust()


## A soft dust puff at the feet — takeoffs, hard landings, bounces.
func _dust(strength := 1.0) -> void:
        if not dust_enabled or not alive:
                return
        var world := get_parent()
        if world == null or not is_inside_tree():
                return
        var puff := CPUParticles3D.new()
        puff.name = "DustPuff"
        puff.one_shot = true
        puff.emitting = true
        puff.amount = int(10 * strength)
        puff.lifetime = 0.45
        puff.explosiveness = 0.92
        puff.direction = Vector3.UP
        puff.spread = 75.0
        puff.initial_velocity_min = 2.0 * strength * STUD
        puff.initial_velocity_max = 5.0 * strength * STUD
        puff.gravity = Vector3(0.0, -7.0 * STUD, 0.0)
        puff.scale_amount_min = 0.16 * STUD
        puff.scale_amount_max = 0.34 * STUD
        var ring := SphereMesh.new()
        ring.radius = 0.5
        ring.height = 1.0
        ring.radial_segments = 6
        ring.rings = 3
        puff.mesh = ring
        puff.color = Color(0.92, 0.9, 0.84, 0.8)
        world.add_child(puff)
        puff.global_position = global_position + Vector3(0.0, 0.25 * STUD, 0.0)
        var timer := get_tree().create_timer(1.0)
        timer.timeout.connect(puff.queue_free)


## STAIRS — walk over any ledge between MIN_STEP and MAX_STEP studs. Measure
## the lip with rays; if it is in range with headroom, rise + reach + settle.
## v3.6 ROOT FIX for "stairs don't work": the probe now tries the WALK WISH
## first (your intent) and the slid velocity second. The old order read the
## slid velocity FIRST — move_and_slide bends it to run ALONG a wall, so any
## diagonal approach probed parallel to the step and never found the lip.
func _attempt_step_up() -> void:
        var hvel := Vector3(velocity.x, 0.0, velocity.z)
        var wish := _step_dir if _step_dir.length_squared() >= 0.5 else Vector3.ZERO
        var slid := hvel.normalized() if hvel.length_squared() >= 1.0 else Vector3.ZERO
        if wish == Vector3.ZERO and slid == Vector3.ZERO:
                return
        if wish != Vector3.ZERO and _step_along(wish):
                return
        if slid != Vector3.ZERO and slid.distance_to(wish) > 0.05 and _step_along(slid):
                return


## One direction probe + rise. TRUE when the step was walked over.
func _step_along(dir: Vector3) -> bool:
        var space := get_world_3d().direct_space_state
        if space == null:
                return false
        var feet := global_position.y
        var probe := PhysicsRayQueryParameters3D.create(
                global_position + Vector3(0.0, MIN_STEP + 0.15 * STUD, 0.0),
                global_position + Vector3(0.0, MIN_STEP + 0.15 * STUD, 0.0) + dir * 1.4 * STUD,
                collision_mask)
        if space.intersect_ray(probe).is_empty():
                return false
        if test_move(global_transform, Vector3.UP * MAX_STEP):
                return false
        var over := global_position + Vector3.UP * MAX_STEP + dir * STEP_PROBE_AHEAD
        var down_ray := PhysicsRayQueryParameters3D.create(
                over, over + Vector3.DOWN * (MAX_STEP + 0.4 * STUD), collision_mask)
        var hit := space.intersect_ray(down_ray)
        if hit.is_empty():
                return false
        var lip: float = float(hit["position"].y) - feet
        if lip < MIN_STEP or lip > MAX_STEP + 0.01:
                return false
        move_and_collide(Vector3.UP * (lip + 0.06))
        move_and_collide(dir * STEP_FORWARD)
        var settle := move_and_collide(Vector3.DOWN * (lip + 0.2 * STUD))
        if settle != null and velocity.y < 0.0:
                velocity.y = 0.0
        grounded = true
        _step_visual = minf(_step_visual - lip, -lip)
        if _step_visual < -MAX_STEP:
                _step_visual = -MAX_STEP
        return true


func _update_fall_damage() -> void:
        if not alive:
                return
        if grounded:
                if _falling:
                        _falling = false
                        var drop := _fall_peak_y - global_position.y
                        var drop_studs := drop / STUD
                        if drop_studs > FALL_SAFE_HEIGHT:
                                hurt((drop_studs - FALL_SAFE_HEIGHT) * FALL_DMG_PER_STUD)
        else:
                _fall_peak_y = maxf(_fall_peak_y, global_position.y) if _falling else global_position.y
                _falling = true


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
        _stop_climb()
        avatar.call("burst", world, randi())


func respawn_at(pos: Vector3) -> void:
        alive = true
        health = MAX_HEALTH
        _regen_wait = 0.0
        _falling = false
        _stop_climb()
        _ladder_dismount = 0.0
        _step_visual = 0.0
        avatar.position.y = 0.0
        health_changed.emit(health, MAX_HEALTH)
        global_position = pos
        velocity = Vector3.ZERO
        heading = 0.0
        avatar.rotation.y = 0.0
        avatar.visible = true
        _dust(1.3)  # a little "you are back" puff at the spawn


## Trampolines — the classic bounce pad launch.
func _do_bounce() -> void:
        if not alive or _bounce_cd > 0.0:
                return
        _bounce_cd = BOUNCE_COOLDOWN
        velocity.y = BOUNCE_POWER
        _falling = true
        _fall_peak_y = global_position.y
        _play_jump_sound(0.9)
        _dust(1.4)


# ---------------------------------------------------------------- sounds

func _play_jump_sound(_pitch := 1.0) -> void:
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx != null:
                sfx.call("play_jump_3d", self)


func _play_land_sound() -> void:
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx != null:
                sfx.call("play_land_3d", self)


## Loops update: footsteps only while moving on the floor (Roblox Running
## spec: plastic steps at ~1.85), climb loop on ladders and stud edges, wind
## loop in a real fall. Everything positions 3D at the player.
func _update_loops() -> void:
        if _steps_loop == null or _climb_loop == null:
                return
        if not is_instance_valid(_steps_loop) or not is_instance_valid(_climb_loop):
                return
        var hspeed := Vector2(velocity.x, velocity.z).length()
        var walking := alive and grounded and not climbing and hspeed > 2.0 * STUD
        _steps_loop.playing = walking
        if walking:
                # Roblox runs the plastic loop at 1.85; scale a little with speed
                _steps_loop.pitch_scale = clampf(1.85 * (0.9 + hspeed / WALK_SPEED * 0.2), 1.4, 2.2)
        _climb_loop.playing = alive and climbing
        if _fall_loop != null and is_instance_valid(_fall_loop):
                var plummeting := alive and not grounded and not climbing and velocity.y < -FALL_WIND_SPEED
                _fall_loop.playing = plummeting


# ---------------------------------------------------------------- sensors

## TrussPart-style ladders are Area3D nodes on layer 16 in the "ladder" group.
## They are tracked (not counted) so the climb can keep its grip across the
## 1-3 stud gaps between ladder segments. The sensor is a TORSO-BAND capsule
## (waist to head, 1.7..4.1 studs) — NOT the whole body: brushing a low rung
## or a 2-stud step with your LEGS must not put you into the climb grip.
## Only when your TORSO reaches the volume does climbing engage (Roblox rule).
func _setup_ladder_sensor() -> void:
        var area := Area3D.new()
        area.name = "LadderSensor"
        area.collision_layer = 0
        area.collision_mask = 16
        area.monitorable = false
        var shape_node := CollisionShape3D.new()
        var shape := CapsuleShape3D.new()
        shape.radius = 1.15 * STUD
        shape.height = 2.4 * STUD
        shape_node.shape = shape
        shape_node.position = Vector3(0.0, 2.9 * STUD, 0.0)
        area.add_child(shape_node)
        add_child(area)
        area.area_entered.connect(func(other: Area3D) -> void:
                if other.is_in_group("ladder") and not _ladder_areas.has(other):
                        _ladder_areas.append(other))
        area.area_exited.connect(func(other: Area3D) -> void:
                _ladder_areas.erase(other))


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
        shape.radius = 1.45 * STUD
        shape.height = 5.4 * STUD
        shape_node.shape = shape
        shape_node.position = Vector3(0.0, 2.6 * STUD, 0.0)
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
