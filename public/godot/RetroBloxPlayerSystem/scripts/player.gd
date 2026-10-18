extends CharacterBody3D

## The classic player: capsule-free ROBLOX HITBOX, account avatar, chat
## bubble, ladders, Minecraft-style stairs. Built from scenes/player.tscn —
## instantiate that scene, add it to the tree, then call initialize(id, name).
## Remote players use render_remote().
##
## STUDS — 1 Godot unit = 1 Roblox stud (STUD_METERS = 0.28 m). The avatar
## is exactly 5 studs tall and the hitbox is the classic R6 hull: a flat
## 2 x 5 x 1 box that rotates with the character (torso + head; arms hang
## loose and never block you). Every constant below is in studs.

# classic movement — every number is @export so developers (and the map
# editor) can tune the feel per player scene without touching code.
@export_group("Movement")
@export var walk_speed: float = 16.0        # studs / second (classic WalkSpeed)
@export var jump_height: float = 6.0        # studs — apex of a fresh jump
@export var jump_up_gravity_scale: float = 0.82  # eased rise, honest fall
@export var gravity: float = 110.0          # studs / s² on the way down
@export var walk_acceleration: float = 145.0 # reach full speed in ~0.11s
@export var air_acceleration: float = 62.0  # real air control — steer mid-jump
@export var brake_ground: float = 170.0     # stop on release, classic style

# steps — walk over anything between a paper-thin lip and 3 studs, and
# pressing into a ledge pops you on top of it Minecraft-style
@export_group("Steps")
@export var max_step: float = 3.0
@export var min_step: float = 0.05
const STEP_REACH: float = 1.35          # must clear the hull depth or the
                                                                                # body never crosses the lip
const STEP_VISUAL_SPEED: float = 46.0   # how fast the body's visual catches up after a step

# ladders (TrussPart-style) — you only GRAB one when you face the climbable
# face and hold W. W climbs up, S climbs down, nothing = hang (the pose
# freezes), SPACE leaps away, and turning the camera away lets go.
@export_group("Climbing")
@export var can_climb: bool = true
@export var climb_speed: float = 9.0
@export var ladder_jump: float = 44.0   # the leap off a ladder
@export var ladder_push: float = 12.0   # horizontal shove away from the face

# sounds — slot names inside assets/sounds/ (mp3 beats wav when both exist)
@export_group("Sounds")
@export var play_footsteps: bool = true
@export var play_jump_sound: bool = true
@export var play_land_sound: bool = true
@export var jump_sound: String = "RetroBloxJump"
@export var walk_sound: String = "Walking"

# classic health — big falls hurt, 1%/s regen after five quiet seconds
# (the Roblox default), zero health routes into the normal respawn flow
signal health_changed(health: float, max_health: float)
signal health_depleted

const MAX_HEALTH: float = 100.0
const REGEN_DELAY: float = 5.0
const REGEN_RATE: float = 1.0        # per second (1% of max, the classic default)
const FALL_SAFE_HEIGHT: float = 45.0 # studs of clean drop before it starts to hurt
const FALL_DMG_PER_STUD: float = 4.0
const STUD_METERS: float = 0.28      # 1 stud = 0.28 meters, site-wide rule

# ROBLOX HITBOX — the classic R6 hull lives in scenes/player.tscn as a
# flat BoxShape3D (2 wide, 5 tall, 1 deep) that yaws with the character.
const HULL_SIZE: Vector3 = Vector3(2.0, 5.0, 1.0)

# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript := preload("res://scripts/retroblox_api.gd")
const AvatarPlatformScript := preload("res://scripts/avatar_platform.gd")
const RetroSounds := preload("res://scripts/sounds.gd")

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
var climb_moving: bool = false       # W/S actually riding (false = hanging pose)
var head_debris: Node3D = null       # the tumbling head the death camera rides
var _ladder_count: int = 0
var _ladder_areas: Array[Area3D] = []
var _active_zone: Area3D = null      # the ladder face currently being ridden
var _active_outward: Vector3 = Vector3.ZERO
var _climb_time: float = 0.0         # seconds on the ladder this ride
var _crest_now: bool = false         # rode off the top — vault after the move
var _climb_cooldown: float = 0.0     # grace after a leap so W cannot re-stick
var _wish_dir: Vector3 = Vector3.ZERO
var _step_visual: float = 0.0        # avatar's downward offset that eases out after a step

# head-top health bar — appears when a player is hurt, fades away a moment
# after they are back to full (the classic Roblox above-head health bar)
var _hb_root: Node3D
var _hb_fill: MeshInstance3D
var _hb_fill_mesh: QuadMesh
var _hb_wait: float = 0.0
var _footstep_audio: AudioStreamPlayer3D
var _jump_audio: AudioStreamPlayer3D
var _land_audio: AudioStreamPlayer3D
var _bubble_bg: MeshInstance3D

const HB_WIDTH: float = 2.4          # studs
const HB_HEIGHT: float = 0.32
const HB_LINGER: float = 2.5         # seconds the bar stays after reaching full

func initialize(id: int, player_name: String) -> void:
        peer_id = id
        display_name = player_name
        name = "Player_%d" % id
        collision_layer = 4
        collision_mask = 1
        floor_snap_length = 0.5
        floor_max_angle = deg_to_rad(50.0)
        # wall glide: even the shallowest graze slides along the wall, the
        # classic feel when you run into something at an angle
        wall_min_slide_angle = 0.05
        max_slides = 6
        # the scene provides the hull, the avatar and the chat bubble
        avatar = get_node("Avatar")
        avatar.configure(id, player_name)
        bubble = get_node("ChatBubble")
        bubble.visible = false
        _setup_bubble()
        _setup_ladder_sensor()
        _setup_head_bar()
        _setup_sounds()

## Launch velocity for the classic jump: reach exactly `jump_height`
## studs with the eased rise gravity.
func _jump_velocity() -> float:
        return sqrt(2.0 * gravity * jump_up_gravity_scale * maxf(jump_height, 0.5))

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
        input_direction = direction
        var wish := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, camera_yaw)
        if wish.length() > 1.0:
                wish = wish.normalized()
        _wish_dir = wish

        # ---- ladders: grab ONLY by facing the climbable face and holding W.
        # While on: W up, S down, nothing hangs, SPACE leaps away, looking away
        # lets go. Riding S into the floor (after a beat) also lets go.
        # No gravity on the ladder.
        var was_climbing := climbing
        climbing = false
        climb_moving = false
        _crest_now = false
        if _climb_cooldown > 0.0:
                _climb_cooldown -= delta
        var ladder_outward := _nearest_ladder_outward(wish)
        if _ladder_count > 0 and can_climb and ladder_outward != Vector3.ZERO:
                var face_dot := wish.dot(ladder_outward)   # < 0 = pushing INTO the face
                var holding_w := direction.y < -0.2
                if jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        if was_climbing:
                                # the leap: up AND away from the wall, classic ladder jump-off
                                velocity = ladder_outward * ladder_push + Vector3.UP * ladder_jump
                                _play_jump()
                                _climb_cooldown = 0.45
                        elif grounded and is_on_floor():
                                velocity.y = _jump_velocity()
                                _play_jump()
                elif _climb_cooldown > 0.0:
                        pass   # just let go — fall normally
                elif was_climbing:
                        var cam_forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
                        if cam_forward.dot(ladder_outward) > 0.35:
                                # the CAMERA looked away from the ladder — hands come off
                                # (pressing S to descend is movement, not looking away)
                                _climb_cooldown = 0.3
                        elif direction.y > 0.2 and grounded and _climb_time > 0.3:
                                # rode S all the way down into the floor
                                _climb_cooldown = 0.2
                        else:
                                climbing = true
                                _climb_time += delta
                                _active_zone = _best_zone(wish)
                                _active_outward = ladder_outward
                                if direction.y < -0.2:
                                        velocity.y = climb_speed
                                        climb_moving = true
                                        # CREST: riding up with only ONE zone touched and its top
                                        # at our feet — vault onto the ledge after the move
                                        if _ladder_count <= 1 and _feet_at_crest(_active_zone):
                                                _crest_now = true
                                elif direction.y > 0.2:
                                        # S: descend — but when the body already hangs
                                        # BELOW the face's bottom edge there is nothing
                                        # left to hold: slide off, don't hover under it
                                        if global_position.y < _zone_face_bottom(_active_zone) - 0.3:
                                                _climb_cooldown = 0.2
                                        else:
                                                velocity.y = -climb_speed
                                                climb_moving = true
                                else:
                                        velocity.y = 0.0   # hang on the spot, pose frozen
                elif holding_w and face_dot < -0.3:
                        # THE GRAB: facing the face, holding W, touching the zone
                        climbing = true
                        climb_moving = true
                        _climb_time = 0.0
                        _active_zone = _best_zone(wish)
                        _active_outward = ladder_outward
                        velocity.y = climb_speed
                if climbing:
                        # strictly vertical: W/S only. Sideways wish is damped away —
                        # no strafing on ladders.
                        velocity.x = move_toward(velocity.x, 0.0, walk_acceleration * 4.0 * delta)
                        velocity.z = move_toward(velocity.z, 0.0, walk_acceleration * 4.0 * delta)

        if not climbing:
                # ---- ground / air movement, classic response ----
                var accel: float = walk_acceleration if is_on_floor() else air_acceleration
                var target := wish * walk_speed
                if wish.length_squared() < 0.005 and is_on_floor():
                        # no input on the ground: brake toward a clean stop
                        velocity.x = move_toward(velocity.x, 0.0, brake_ground * delta)
                        velocity.z = move_toward(velocity.z, 0.0, brake_ground * delta)
                else:
                        velocity.x = move_toward(velocity.x, target.x, accel * delta)
                        velocity.z = move_toward(velocity.z, target.z, accel * delta)
                if not is_on_floor():
                        # eased rise, honest fall — floaty up, snappy down
                        velocity.y -= gravity * (jump_up_gravity_scale if velocity.y > 0.0 else 1.0) * delta
                elif velocity.y < 0.0:
                        velocity.y = 0.0
                if jump_serial > consumed_jump:
                        consumed_jump = jump_serial
                        if is_on_floor():
                                velocity.y = _jump_velocity()
                                _play_jump()

        var fall_speed := velocity.y
        var was_grounded := grounded
        move_and_slide()
        grounded = is_on_floor()
        # CREST VAULT — riding up carried the body past the zone top: carry it
        # over the lip onto the ledge (the classic "vault" at the top of a truss)
        if _crest_now and climbing:
                climbing = false
                climb_moving = false
                velocity.y = minf(velocity.y, 0.0)
                velocity.x = 0.0
                velocity.z = 0.0
                move_and_collide(-_active_outward * 1.25)
                velocity += -_active_outward * 1.8
                _climb_cooldown = 0.5
        if play_land_sound and not was_grounded and grounded and fall_speed < -14.0 and _land_audio != null:
                _land_audio.play()
        # step-up runs when the wall test says so OR when the wish is strong but
        # we are barely moving — tiny lips can block without a wall slide event
        if grounded and (is_on_wall() or _is_blocked()):
                _attempt_step_up()
        # facing — shift lock squares up to the camera, otherwise face the run.
        # The HULL rotates with the character (Roblox style); the avatar child
        # stays at local zero.
        if use_shiftlock:
                heading = lerp_angle(heading, camera_yaw, 1.0 - exp(-14.0 * delta))
        elif wish.length_squared() > 0.005:
                heading = lerp_angle(heading, atan2(-wish.x, -wish.z), 1.0 - exp(-18.0 * delta))
        rotation.y = heading
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

## True when the player is pushing hard but the body barely moves — the
## classic "stuck on the part edge" case the plain is_on_wall() test missed.
func _is_blocked() -> bool:
        if _wish_dir.length() < 0.5:
                return false
        var hvel := Vector3(velocity.x, 0.0, velocity.z).length()
        return hvel < walk_speed * 0.35

## STAIRS — walk over any ledge between min_step and max_step studs.
## Runs after move_and_slide when we ended up against a wall (or wedged on
## a part edge): measure the ledge with a downward ray from a raised
## position, and if the lip is in range and there is headroom, rise + reach
## over + settle onto the step — the Minecraft pop, stud-accurate.
func _attempt_step_up() -> void:
        var hvel := Vector3(velocity.x, 0.0, velocity.z)
        var dir := hvel
        if dir.length() >= 1.0:
                dir = dir.normalized()
        elif _wish_dir.length_squared() > 0.01:
                # wedged: velocity is near zero but the player is pushing — aim the
                # step at the WISH so stairs and ledges never trap you
                dir = _wish_dir.normalized()
        else:
                return
        var space := get_world_3d().direct_space_state
        if space == null:
                return
        var feet := global_position.y
        # 1) something low actually blocking straight ahead?
        var probe := PhysicsRayQueryParameters3D.create(
                global_position + Vector3(0.0, min_step + 0.15, 0.0),
                global_position + Vector3(0.0, min_step + 0.15, 0.0) + dir * (STEP_REACH + 0.05),
                collision_mask
        )
        if space.intersect_ray(probe).is_empty():
                return
        # 2) reach PAST the hull over the lip and measure the landing height
        #    with a ray — a short reach here is what used to wedge the body on
        #    the very edge of the part
        var over := global_position + Vector3.UP * max_step + dir * STEP_REACH
        var down_ray := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (max_step + 0.4), collision_mask)
        var hit := space.intersect_ray(down_ray)
        if hit.is_empty():
                return  # nothing to land on at that height — it is a tall wall
        var lip: float = float(hit["position"].y) - feet
        if lip < min_step or lip > max_step + 0.01:
                return  # too tall (or we are already level) — jump like classic
        # 3) headroom to rise exactly as far as the ledge demands — walking
        #    UNDER a low ceiling near a stair never slams you into it
        if test_move(global_transform, Vector3.UP * (lip + 0.06)):
                return
        # 4) execute: rise, reach over, settle. The body snaps; the avatar eases.
        move_and_collide(Vector3.UP * (lip + 0.06))
        move_and_collide(dir * STEP_REACH)
        var settle := move_and_collide(Vector3.DOWN * (lip + 0.3))
        if settle != null and velocity.y < 0.0:
                velocity.y = 0.0
        grounded = true
        _step_visual = minf(_step_visual - lip, -lip)
        if _step_visual < -max_step:
                _step_visual = -max_step

# ---------------------------------------------------------------- ladders

## World-space outward normal of a climb zone's climbable face
## (resolves through rotated ladders — probe_obby guards this).
func _ladder_outward_of(zone: Area3D) -> Vector3:
        var local := zone.get_meta("outward", Vector3.BACK) as Vector3
        return (zone.global_transform.basis * local).normalized()

## The best-matching touched ladder face: the one most directly in front
## of where the player is pushing (wish). ZERO when nothing is touched.
func _nearest_ladder_outward(wish: Vector3) -> Vector3:
        var best := Vector3.ZERO
        var best_score := -2.0
        for zone in _ladder_areas:
                if zone == null or not is_instance_valid(zone):
                        continue
                var outward := _ladder_outward_of(zone)
                var score := wish.dot(-outward) if wish.length_squared() > 0.01 else 0.0
                if score > best_score:
                        best_score = score
                        best = outward
        return best


func _best_zone(wish: Vector3) -> Area3D:
        var best: Area3D = null
        var best_score := -2.0
        for zone in _ladder_areas:
                if zone == null or not is_instance_valid(zone):
                        continue
                var outward := _ladder_outward_of(zone)
                var score := wish.dot(-outward) if wish.length_squared() > 0.01 else 0.0
                if score > best_score:
                        best_score = score
                        best = zone
        return best


## World-space top of a climb zone's box shape.
func _zone_top_y(zone: Area3D) -> float:
        var top := -INF
        if zone == null or not is_instance_valid(zone):
                return top
        for child in zone.get_children():
                var node := child as CollisionShape3D
                if node == null or not (node.shape is BoxShape3D):
                        continue
                var half: Vector3 = (node.shape as BoxShape3D).size * 0.5
                for sx in [1.0, -1.0]:
                        for sy in [1.0, -1.0]:
                                for sz in [1.0, -1.0]:
                                        var corner := node.global_transform * Vector3(half.x * sx, half.y * sy, half.z * sz)
                                        top = maxf(top, corner.y)
        return top


## True when the body has ridden up to (or past) the zone's top — time to
## vault onto the ledge.
func _feet_at_crest(zone: Area3D) -> bool:
        var top := _zone_top_y(zone)
        return top != -INF and global_position.y >= top - 0.25

## Lowest point of the climbable FACE the zone belongs to (the part's
## bottom edge — the classic "slide off the bottom of the truss" line).
func _zone_face_bottom(zone: Area3D) -> float:
        var part := zone.get_parent() if is_instance_valid(zone) else null
        if part is RetroPart:
                return (part as RetroPart).global_position.y - (part as RetroPart).size.y * 0.5
        return -INF

## Distance from the body center to a climb zone's climbable face plane
## (positive = in front of the face). Probe contract: `_face_gap`.
func _face_gap(zone: Area3D) -> float:
        var outward := _ladder_outward_of(zone)
        var part := zone.get_parent()
        var half := 0.0
        if part is RetroPart:
                var s: Vector3 = (part as RetroPart).size
                half = 0.5 * (absf(outward.x) * s.x + absf(outward.y) * s.y + absf(outward.z) * s.z)
        var face_point: Vector3 = part.global_position + outward * half
        return (global_position - face_point).dot(outward)

## Ladder sensor — one Area3D hugging the body; TrussPart-style ladders are
## Area3D nodes on layer 16 in the "ladder" group. Touched zones are TRACKED
## so the climb gate can face-check the actual climbable face.
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
                        _ladder_count += 1
                        if not _ladder_areas.has(other):
                                _ladder_areas.append(other))
        area.area_exited.connect(func(other: Area3D) -> void:
                if other.is_in_group("ladder"):
                        _ladder_count = maxi(_ladder_count - 1, 0)
                        _ladder_areas.erase(other))

# ---------------------------------------------------------------- avatar fx

## Head-top health bar — two billboarded quads. Shows whenever the player is
## below full health, then lingers a moment and disappears once healed.
func _setup_head_bar() -> void:
        _hb_root = Node3D.new()
        _hb_root.name = "HealthBillboard"
        _hb_root.position = Vector3(0.0, 6.55, 0.0)
        _hb_root.visible = false
        add_child(_hb_root)
        var bg := MeshInstance3D.new()
        bg.name = "Track"
        var bg_mesh := QuadMesh.new()
        bg_mesh.size = Vector2(HB_WIDTH, HB_HEIGHT)
        bg.mesh = bg_mesh
        bg.material_override = _hb_material(Color(0.055, 0.09, 0.11, 0.82))
        _hb_root.add_child(bg)
        _hb_fill = MeshInstance3D.new()
        _hb_fill.name = "Fill"
        _hb_fill_mesh = QuadMesh.new()
        _hb_fill_mesh.size = Vector2(HB_WIDTH, HB_HEIGHT)
        _hb_fill.mesh = _hb_fill_mesh
        _hb_fill.material_override = _hb_material(Color("02b757"))
        _hb_fill.position = Vector3(0.0, 0.0, -0.02)  # a hair in front: no z-fighting
        _hb_root.add_child(_hb_fill)

func _hb_material(color: Color) -> StandardMaterial3D:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = color
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
        mat.no_depth_test = false
        mat.render_priority = 10
        return mat

func _update_head_bar(delta: float) -> void:
        if _hb_root == null:
                return
        var ratio := clampf(health / MAX_HEALTH, 0.0, 1.0)
        if alive and ratio < 0.995:
                _hb_wait = 0.0
                _hb_root.visible = true
        elif _hb_wait < HB_LINGER:
                _hb_wait += delta
                _hb_root.visible = true
                if _hb_wait >= HB_LINGER:
                        _hb_root.visible = false
        var w: float = maxf(HB_WIDTH * ratio - 0.08, 0.001)
        _hb_fill_mesh.size = Vector2(w, HB_HEIGHT - 0.08)
        # keep the fill glued to the left edge as it shrinks
        _hb_fill.position = Vector3(-(HB_WIDTH - 0.08) * 0.5 + w * 0.5, 0.0, -0.02)
        (_hb_fill.material_override as StandardMaterial3D).albedo_color = \
                Color("e2231a").lerp(Color("02b757"), ratio)

## Jump + footstep sounds — 3D, so nearby players hear them too.
func _setup_sounds() -> void:
        if play_jump_sound:
                _jump_audio = RetroSounds.world_player(jump_sound, -6.0)
                if _jump_audio.stream == null:
                        _jump_audio = null
                else:
                        _jump_audio.position = Vector3(0.0, 3.0, 0.0)
                        add_child(_jump_audio)
        if play_footsteps:
                _footstep_audio = RetroSounds.world_player(walk_sound, -14.0, true)
                if _footstep_audio.stream == null:
                        _footstep_audio = null
                else:
                        _footstep_audio.position = Vector3(0.0, 0.2, 0.0)
                        add_child(_footstep_audio)
        _land_audio = RetroSounds.world_player("land", -8.0)
        if _land_audio.stream == null:
                _land_audio = null
        else:
                _land_audio.position = Vector3(0.0, 0.2, 0.0)
                add_child(_land_audio)

func _play_jump() -> void:
        if play_jump_sound and _jump_audio != null:
                _jump_audio.play()

func _update_footsteps() -> void:
        if not play_footsteps or _footstep_audio == null:
                return
        var moving: bool = alive and grounded \
                and Vector3(velocity.x, 0.0, velocity.z).length() > 2.0 \
                and not climbing
        if moving and not _footstep_audio.playing:
                _footstep_audio.play()
        elif not moving and _footstep_audio.playing:
                _footstep_audio.stop()

## The chat bubble, sized to be READ from across the baseplate: a big white
## rounded card with chunky outlined text, floating well above the name.
func _setup_bubble() -> void:
        bubble.font_size = 42
        bubble.pixel_size = 0.011
        bubble.outline_size = 16
        bubble.outline_modulate = Color(0.09, 0.15, 0.19, 1.0)
        bubble.modulate = Color(0.12, 0.17, 0.2, 1.0)
        bubble.position = Vector3(0.0, 7.7, 0.0)
        bubble.no_depth_test = true
        bubble.render_priority = 20
        var quad := QuadMesh.new()
        quad.size = Vector2(6.6, 2.5)
        _bubble_bg = MeshInstance3D.new()
        _bubble_bg.name = "BubbleCard"
        _bubble_bg.mesh = quad
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = _rounded_card_texture()
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
        mat.no_depth_test = true
        mat.render_priority = 19
        _bubble_bg.material_override = mat
        _bubble_bg.position = Vector3(0.0, 7.7, 0.0)
        _bubble_bg.visible = false
        add_child(_bubble_bg)

## A white speech-card texture with soft rounded corners, generated once.
static var _card_cache: ImageTexture = null
static func _rounded_card_texture() -> ImageTexture:
        if _card_cache != null:
                return _card_cache
        var w := 256
        var h := 96
        var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
        var radius := 20.0
        for y in range(h):
                for x in range(w):
                        var px := float(x) + 0.5
                        var py := float(y) + 0.5
                        var cx := clampf(px, radius, float(w) - radius)
                        var cy := clampf(py, radius, float(h) - radius)
                        var d := Vector2(px - cx, py - cy).length()
                        var a := clampf(radius - d + 1.0, 0.0, 1.0)
                        img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.95 * a))
        _card_cache = ImageTexture.create_from_image(img)
        return _card_cache

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
        rotation.y = heading
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
                var anim_speed := absf(velocity.y) if climbing \
                        else Vector2(velocity.x, velocity.z).length()
                avatar.animate(delta, anim_speed, grounded, climbing, climb_moving)
                _update_footsteps()
        _update_head_bar(delta)
        if bubble_remaining > 0.0:
                bubble_remaining -= delta
                var show := alive and bubble_remaining > 0.0
                bubble.visible = show
                if _bubble_bg != null:
                        _bubble_bg.visible = show

## Remote players get their health from the host's snapshot rows.
func set_remote_health(value: float) -> void:
        health = clampf(value, 0.0, MAX_HEALTH)

func show_message(message: String) -> void:
        # Plain text only: markup cannot be injected. Wide, readable wrapping —
        # the bubble card underneath is sized for three 22-character lines.
        var words := message.split(" ")
        var lines: Array[String] = []
        var current := ""
        for word in words:
                if current.length() + word.length() > 22 and not current.is_empty():
                        lines.append(current)
                        current = ""
                current += (" " if not current.is_empty() else "") + word.left(22)
                if lines.size() >= 3:
                        break
        if lines.size() < 3 and not current.is_empty():
                lines.append(current)
        bubble.text = "\n".join(lines)
        bubble_remaining = 5.5
        bubble.visible = alive
        if _bubble_bg != null:
                _bubble_bg.visible = alive

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
        if _footstep_audio != null and _footstep_audio.playing:
                _footstep_audio.stop()
        if _hb_root != null:
                _hb_root.visible = false
                _hb_wait = HB_LINGER
        velocity = Vector3.ZERO
        correction = Vector3.ZERO
        input_direction = Vector2.ZERO
        climbing = false
        climb_moving = false
        bubble.visible = false
        if _bubble_bg != null:
                _bubble_bg.visible = false
        # the parts tumble as debris; the death camera rides the head
        head_debris = avatar.burst(world, seed_value)

func respawn_at(pos: Vector3, epoch: int) -> void:
        life_epoch = epoch
        alive = true
        health = MAX_HEALTH
        regen_wait = 0.0
        falling = false
        climbing = false
        climb_moving = false
        head_debris = null
        _climb_cooldown = 0.0
        _step_visual = 0.0
        _hb_wait = HB_LINGER  # the bar starts hidden on a fresh life
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
        rotation.y = 0.0
        avatar.rotation.y = 0.0
        avatar.visible = true
        bubble.visible = false
        bubble_remaining = 0.0
        if _bubble_bg != null:
                _bubble_bg.visible = false
