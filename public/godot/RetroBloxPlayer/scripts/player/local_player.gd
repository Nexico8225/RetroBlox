class_name LocalPlayer
extends CharacterBody3D
# Controls local player movement, capsule collision, 1-2 stud stepping, ladder climbing, health, and voice indicator.
signal health_changed(health: float, max_health: float)
signal health_depleted
signal touched_group(group: String, node: Node3D)
signal land_impact(speed: float)

const STUD := 1.0

const WALK_SPEED := 16.0 * STUD
const JUMP_SPEED := 50.0 * STUD
const GRAVITY := 196.2 * STUD
const ACCEL_GROUND := 145.0 * STUD
const ACCEL_AIR := 62.0 * STUD
const BRAKE_GROUND := 170.0 * STUD
const COYOTE_TIME := 0.08
const JUMP_BUFFER := 0.12

const MAX_STEP := 2.0 * STUD
const MIN_STEP := 0.05 * STUD
const STEP_FORWARD := 0.6 * STUD
const STEP_PROBE_AHEAD := 1.7 * STUD
const FLOOR_SNAP := 0.5 * STUD
const STEP_RISE_SPEED := 22.0 * STUD

const CLIMB_SPEED := 11.0 * STUD
const LADDER_JUMP := 24.0 * STUD
const LADDER_DISMOUNT := 0.25

const CLIMB_FACE_START := 0.35
const CLIMB_FACE_STAY := 0.20
const HUG_PRESSURE := 1.5 * STUD

const LAND_SOUND_FALL := 22.0 * STUD
const FALL_WIND_SPEED := 34.0 * STUD

const MAX_HEALTH := 100.0
const REGEN_DELAY := 5.0
const REGEN_RATE := 1.0
const FALL_SAFE_HEIGHT := 45.0
const FALL_DMG_PER_STUD := 4.0
const BOUNCE_POWER := 72.0 * STUD
const BOUNCE_COOLDOWN := 0.35

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")
const ChatBubbleScript := preload("res://scripts/player/chat_bubble.gd")
const RetroUI := preload("res://scripts/ui/retro_theme.gd")

enum ClimbKind { NONE, LADDER, WALL }

@export_group("Character Physics")
@export var walk_speed := WALK_SPEED
@export var jump_power := JUMP_SPEED
@export var max_step_studs := 2.0
@export var climb_speed := CLIMB_SPEED

@export_group("Editable Animations")
@export var walk_arm_swing := 0.82
@export var walk_leg_swing := 0.78
@export var walk_cycle_speed := 8.5
@export var jump_arm_angle := 2.75
@export var jump_leg_spread := 0.28
@export var climb_swing := 0.65

var display_name := "Guest"
var avatar: Node3D
var bubble: ChatBubble
var voice_indicator: Sprite3D
var voice_player: AudioStreamPlayer3D
var alive := true
var health := MAX_HEALTH
var heading := 0.0
var grounded := false
var climbing := false
var spawn_point := Transform3D()
var wants_chat_input := false
var dust_enabled := true

var _regen_wait := 0.0
var _falling := false
var _fall_peak_y := 0.0
var _ladder_areas: Array[Node3D] = []
var _ladder_sensor: Area3D = null
var _touch_sensor: Area3D = null
var _climb_kind: int = ClimbKind.NONE
var _climb_face := Vector3.ZERO
var _coyote := 0.0
var _jump_buffer_left := 0.0
var _rise_left := 0.0
var _rise_dir := Vector3.ZERO
var _rise_lip := 0.0
var _step_dir := Vector3.ZERO
var _bounce_cd := 0.0
var _time := 0.0
var _settings: Node = null
var _steps_loop: AudioStreamPlayer3D
var _climb_loop: AudioStreamPlayer3D
var _fall_loop: AudioStreamPlayer3D
var _ladder_dismount := 0.0
var _input_shiftlock := false
var _input_first_person := false
var _last_vy := 0.0
var _initialized_nodes := false
var _tex_voice_on: Texture2D
var _tex_voice_muted: Texture2D
var _tex_voice_levels: Array[Texture2D] = []

var _speed_boost_timer := 0.0
var _speed_boost_mult := 1.65
var _gravity_boost_timer := 0.0
var _gravity_boost_mult := 0.42
var _jump_boost_mult := 1.25
var _climb_grace := 0.0
var _active_climb_speed := CLIMB_SPEED
var _touching_damage: Array[Node3D] = []
var _touching_heal: Array[Node3D] = []
var _damage_tick_cd := 0.0
var _heal_tick_cd := 0.0


func _init() -> void:
	name = "LocalPlayer"
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.65 * STUD
	floor_max_angle = deg_to_rad(65.0)
	floor_block_on_wall = false
	floor_constant_speed = true
	floor_stop_on_slope = true


func _ensure_nodes() -> void:
	if _initialized_nodes:
		return
	_initialized_nodes = true

	_tex_voice_levels.clear()
	for i in range(11):
		_tex_voice_levels.append(RetroUI.load_png_safe("res://assets/ui/voice_levels/level_%d.png" % i))
	_tex_voice_muted = RetroUI.load_png_safe("res://assets/ui/voice_bubble_muted.png")
	_tex_voice_on = _tex_voice_levels[0] if not _tex_voice_levels.is_empty() else RetroUI.load_png_safe("res://assets/ui/voice_bubble.png")

	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		add_child(col)
	if not (col.shape is CapsuleShape3D):
		var cap := CapsuleShape3D.new()
		cap.radius = 1.0 * STUD
		cap.height = 5.0 * STUD
		col.shape = cap
	col.position = Vector3(0.0, 2.5 * STUD, 0.0)

	avatar = get_node_or_null("Avatar") as Node3D
	if avatar == null or not avatar.has_method("animate"):
		if avatar != null:
			avatar.queue_free()
		avatar = AvatarRigScript.new()
		avatar.name = "Avatar"
		add_child(avatar)
	_sync_avatar_anim_exports()

	bubble = get_node_or_null("ChatBubble") as ChatBubble
	if bubble == null:
		bubble = ChatBubbleScript.new()
		bubble.name = "ChatBubble"
		add_child(bubble)

	voice_indicator = get_node_or_null("VoiceIndicator") as Sprite3D
	if voice_indicator == null:
		voice_indicator = Sprite3D.new()
		voice_indicator.name = "VoiceIndicator"
		add_child(voice_indicator)
	voice_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	voice_indicator.no_depth_test = true
	voice_indicator.pixel_size = 0.0075
	voice_indicator.shaded = false
	voice_indicator.position = Vector3(0.0, 6.55 * STUD, 0.0)
	voice_indicator.texture = _tex_voice_on
	voice_indicator.modulate = Color(1.0, 1.0, 1.0, 0.98)

	if get_node_or_null("LadderSensor") == null:
		_setup_ladder_sensor()
	if get_node_or_null("TouchSensor") == null:
		_setup_touch_sensor()


func _sync_avatar_anim_exports() -> void:
	if avatar == null or not is_instance_valid(avatar):
		return
	avatar.set("walk_arm_swing", walk_arm_swing)
	avatar.set("walk_leg_swing", walk_leg_swing)
	avatar.set("walk_cycle_speed", walk_cycle_speed)
	avatar.set("jump_arm_angle", jump_arm_angle)
	avatar.set("jump_leg_spread", jump_leg_spread)
	avatar.set("climb_swing", climb_swing)


func _ready() -> void:
	_ensure_nodes()
	_settings = get_node_or_null("/root/Settings")
	_setup_character_sfx()
	var vc: Node = get_node_or_null("/root/VoiceChat")
	if vc != null:
		if vc.has_method("make_voice_player_3d"):
			voice_player = vc.call("make_voice_player_3d", self)
		if vc.has_signal("speaking_changed") and not vc.is_connected("speaking_changed", _on_voice_speaking_changed):
			vc.connect("speaking_changed", _on_voice_speaking_changed)
		if vc.has_signal("mute_changed") and not vc.is_connected("mute_changed", _on_voice_mute_changed):
			vc.connect("mute_changed", _on_voice_mute_changed)
	if _settings != null and not _settings.changed.is_connected(_on_setting_changed):
		_settings.changed.connect(_on_setting_changed)
	_refresh_voice_bubble(0.0)


func _on_setting_changed(key: String, _val: Variant) -> void:
	if key in ["voice_enabled", "voice_muted"]:
		_refresh_voice_bubble(0.0)


func _on_voice_mute_changed(_muted: bool) -> void:
	_refresh_voice_bubble(0.0)


func _on_voice_speaking_changed(_speaking: bool, level: float) -> void:
	_refresh_voice_bubble(level)


func _refresh_voice_bubble(level: float) -> void:
	if voice_indicator == null or not is_instance_valid(voice_indicator):
		return
	var vc_enabled := true if _settings == null else bool(_settings.get("voice_enabled"))
	if not vc_enabled or _input_first_person or not alive:
		voice_indicator.visible = false
		return
	var vc: Node = get_node_or_null("/root/VoiceChat")
	var muted := false if vc == null else bool(vc.call("is_muted"))
	var speaking := false if vc == null else bool(vc.call("is_speaking"))
	if muted or (not speaking and level <= 0.02):
		voice_indicator.visible = false
		return
	voice_indicator.visible = true
	var idx := clampi(int(round(level * 10.0)), 0, 10)
	if idx < _tex_voice_levels.size():
		voice_indicator.texture = _tex_voice_levels[idx]
	var s := 1.0 + clampf(level * 0.16, 0.0, 0.16)
	voice_indicator.scale = Vector3(s, s, s)


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
	_ensure_nodes()
	display_name = p_name
	avatar.call("setup", p_name)


func show_bubble(message: String) -> void:
	_ensure_nodes()
	bubble.show_text(message)


func dress(api, payload: Dictionary) -> void:
	_ensure_nodes()
	if payload.is_empty():
		return
	await AvatarDresserScript.apply(api, avatar, payload)


func _physics_process(delta: float) -> void:
	_time += delta
	if _bounce_cd > 0.0:
		_bounce_cd -= delta
	_update_loops()


func drive(delta: float, direction: Vector2, cam_yaw: float, just_pressed: bool, use_shiftlock: bool, first_person := false, jump_held := false) -> void:
	_ensure_nodes()
	if not alive:
		return
	_sync_avatar_anim_exports()
	_input_shiftlock = use_shiftlock
	if _input_first_person != first_person:
		_input_first_person = first_person
		_refresh_voice_bubble(0.0)
	var wish := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, cam_yaw)
	if wish.length() > 1.0:
		wish = wish.normalized()
	if wish.length_squared() > 0.005:
		_step_dir = wish.normalized()

	var hop_on := (_settings == null) or bool(_settings.get("bunny_hop"))
	if just_pressed:
		_jump_buffer_left = JUMP_BUFFER
	elif jump_held and hop_on and (grounded or _coyote > 0.0) and _climb_kind == ClimbKind.NONE:
		_jump_buffer_left = JUMP_BUFFER
	elif _jump_buffer_left > 0.0:
		_jump_buffer_left -= delta
	if grounded:
		_coyote = COYOTE_TIME
	elif _coyote > 0.0:
		_coyote -= delta

	if _ladder_dismount > 0.0:
		_ladder_dismount -= delta

	if _speed_boost_timer > 0.0:
		_speed_boost_timer -= delta
	if _gravity_boost_timer > 0.0:
		_gravity_boost_timer -= delta

	var auto_rot_ladder := true if _settings == null else bool(_settings.get("ladder_auto_rotate"))
	_update_climb(wish, delta, auto_rot_ladder)
	if _climb_kind != ClimbKind.NONE and auto_rot_ladder:
		heading = lerp_angle(heading, atan2(-_climb_face.x, -_climb_face.z), 1.0 - exp(-22.0 * delta))
	elif use_shiftlock or first_person:
		heading = cam_yaw
	elif wish.length_squared() > 0.005:
		heading = lerp_angle(heading, atan2(-wish.x, -wish.z), 1.0 - exp(-18.0 * delta))

	if _climb_kind != ClimbKind.NONE:
		_drive_climb(wish, delta)
	else:
		_drive_ground_air(wish, delta)
		_perform_step_up(wish, delta)

	move_and_slide()
	if _climb_kind == ClimbKind.NONE and is_on_floor() and is_on_wall():
		_perform_step_up(wish, delta)
	for i in range(get_slide_collision_count()):
		var sc := get_slide_collision(i)
		if sc != null and sc.get_collider() is Node3D:
			_on_touch_entered(sc.get_collider() as Node3D)
	if _touch_sensor != null and is_instance_valid(_touch_sensor):
		for b in _touch_sensor.get_overlapping_bodies():
			if b is Node3D:
				_on_touch_entered(b as Node3D)
	var was_grounded := grounded
	grounded = is_on_floor()
	if grounded and not was_grounded and _last_vy < -LAND_SOUND_FALL:
		_play_land_sound()
		_dust(clampf(-_last_vy / (40.0 * STUD), 1.0, 1.8))
		land_impact.emit(-_last_vy)

	_update_fall_damage()
	_update_brick_ticks(delta)
	if _regen_wait > 0.0:
		_regen_wait -= delta
	elif health < MAX_HEALTH:
		health = minf(health + REGEN_RATE * delta * 8.0, MAX_HEALTH)
		health_changed.emit(health, MAX_HEALTH)
	_last_vy = velocity.y
	avatar.rotation.y = heading
	if _ladder_sensor != null and is_instance_valid(_ladder_sensor):
		_ladder_sensor.rotation.y = heading
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var anim_speed := absf(velocity.y) if climbing else hspeed
	avatar.call("animate", delta, anim_speed, grounded, climbing)


static func _node_float(node: Object, prop_name: String, meta_name: String, default_val: float) -> float:
	if node == null or not is_instance_valid(node):
		return default_val
	var v: Variant = node.get(prop_name)
	if v is float or v is int:
		return float(v)
	if node.has_meta(meta_name):
		return float(node.get_meta(meta_name, default_val))
	return default_val


func _update_brick_ticks(delta: float) -> void:
	if not alive:
		return
	for i in range(_touching_damage.size() - 1, -1, -1):
		if not is_instance_valid(_touching_damage[i]):
			_touching_damage.remove_at(i)
	for i in range(_touching_heal.size() - 1, -1, -1):
		if not is_instance_valid(_touching_heal[i]):
			_touching_heal.remove_at(i)
	if _damage_tick_cd > 0.0:
		_damage_tick_cd -= delta
	elif not _touching_damage.is_empty():
		var brick := _touching_damage[0]
		var dmg := _node_float(brick, "damage_amount", "damage", 20.0)
		var cd := _node_float(brick, "damage_cooldown", "damage_cooldown", 0.55)
		hurt(dmg)
		_damage_tick_cd = cd
		touched_group.emit("damage", brick)
	if _heal_tick_cd > 0.0:
		_heal_tick_cd -= delta
	elif not _touching_heal.is_empty():
		var hbrick := _touching_heal[0]
		var h_amt := _node_float(hbrick, "heal_amount", "heal", 15.0)
		var h_cd := _node_float(hbrick, "heal_cooldown", "heal_cooldown", 0.45)
		if health < MAX_HEALTH:
			heal(h_amt)
		_heal_tick_cd = h_cd
		touched_group.emit("heal", hbrick)


func _prune_ladder_contacts() -> void:
	_ladder_areas.clear()
	if _ladder_sensor == null or not is_instance_valid(_ladder_sensor):
		return
	for b in _ladder_sensor.get_overlapping_bodies():
		if b is Node3D and b != self and _is_climbable_node(b as Node3D):
			if not _ladder_areas.has(b):
				_ladder_areas.append(b as Node3D)
	for a in _ladder_sensor.get_overlapping_areas():
		if a is Node3D and a != self and _is_climbable_node(a as Node3D):
			if not _ladder_areas.has(a):
				_ladder_areas.append(a as Node3D)
	for i in range(get_slide_collision_count()):
		var sc := get_slide_collision(i)
		if sc != null and sc.get_collider() is Node3D:
			var col_node := sc.get_collider() as Node3D
			if col_node != self and _is_climbable_node(col_node) and not _ladder_areas.has(col_node):
				_ladder_areas.append(col_node)


func _update_climb(wish: Vector3, delta: float, _auto_rot_ladder: bool) -> void:
	_prune_ladder_contacts()

	if _climb_kind != ClimbKind.NONE and grounded and wish.dot(_climb_face) < -0.15:
		_stop_climb()
		return

	if _climb_kind == ClimbKind.LADDER:
		if not _ladder_areas.is_empty():
			var lad: Node3D = _nearest_ladder()
			_active_climb_speed = _node_float(lad, "climb_speed", "climb_speed", climb_speed)
			var face := _toward(lad)
			if face != Vector3.ZERO and face.dot(_climb_face) > -0.5:
				_climb_face = face
			_climb_grace = 0.12
			return
		# Left the ladder volume at the top: step cleanly onto the top platform without launching into the sky
		var was_climbing_up := velocity.y > 0.5 * STUD
		var f := _climb_face
		if was_climbing_up and _try_mantle():
			return
		_stop_climb()
		if was_climbing_up:
			velocity.y = 0.0
			_jump_buffer_left = 0.0
			_coyote = 0.0
			velocity.x = f.x * walk_speed * 0.78
			velocity.z = f.z * walk_speed * 0.78
		return

	if _climb_kind == ClimbKind.WALL:
		var normal := _wall_hit_along(_climb_face)
		if normal != Vector3.ZERO:
			_climb_face = -normal
			_climb_grace = 0.35
			return
		_climb_grace -= delta
		if wish.dot(_climb_face) > 0.15 and _try_mantle():
			return
		if _climb_grace <= 0.0 or wish.dot(_climb_face) < -0.15:
			var was_up := velocity.y > 0.5 * STUD
			var wf := _climb_face
			_stop_climb()
			if was_up:
				velocity.y = 0.0
				velocity.x = wf.x * walk_speed * 0.75
				velocity.z = wf.z * walk_speed * 0.75
		return

	if _ladder_dismount > 0.0:
		return

	if not _ladder_areas.is_empty():
		var lad2: Node3D = _nearest_ladder()
		var face_to_lad := _toward(lad2)
		if face_to_lad != Vector3.ZERO:
			var forward := Vector3(-sin(heading), 0.0, -cos(heading))
			var moving_into := wish.dot(face_to_lad) > 0.05 or (not grounded and forward.dot(face_to_lad) >= 0.0)
			if moving_into:
				_climb_kind = ClimbKind.LADDER
				_climb_face = face_to_lad
				_active_climb_speed = _node_float(lad2, "climb_speed", "climb_speed", climb_speed)
				_climb_grace = 0.12
				return

	# Rung towers (like Stair1..4) and climbable vertical stud faces taller than max_step_studs
	if wish.length_squared() > 0.04:
		var wall_normal := _wall_hit_along(wish, max_step_studs + 0.15)
		if wall_normal != Vector3.ZERO:
			var wface := -wall_normal
			var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
			if wish.dot(wface) > 0.45 and fwd.dot(wface) >= 0.35:
				_climb_kind = ClimbKind.WALL
				_climb_face = wface
				_active_climb_speed = climb_speed
				_climb_grace = 0.35


func _wall_hit_along(dir: Vector3, min_h := 0.0) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.001:
		return Vector3.ZERO
	d = d.normalized()
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.ZERO
	for raw_h: float in [1.1, 1.65, 2.2, 2.75, 3.3, 3.85]:
		if raw_h < min_h:
			continue
		var from := global_position + Vector3.UP * (raw_h * STUD)
		var query := PhysicsRayQueryParameters3D.create(from, from + d * (2.6 * STUD), collision_mask)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var col_obj: Variant = hit.get("collider", null)
		if col_obj is Node3D:
			var cn := col_obj as Node3D
			if _is_climbable_node(cn) or cn.name.begins_with("Stair"):
				var normal: Vector3 = hit["normal"]
				if absf(normal.y) < 0.4:
					return normal
	return Vector3.ZERO


func _try_mantle() -> bool:
	var f := Vector3(_climb_face.x, 0.0, _climb_face.z).normalized()
	if f.length_squared() < 0.01:
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var over := global_position + f * (1.35 * STUD) + Vector3.UP * (2.6 * STUD)
	var down := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (3.2 * STUD), collision_mask)
	var hit := space.intersect_ray(down)
	if hit.is_empty():
		return false
	var lip: float = float(hit["position"].y) - global_position.y
	if lip < -0.5 * STUD or lip > 2.6 * STUD:
		return false
	if lip > 0.0:
		move_and_collide(Vector3.UP * (lip + 0.08))
	move_and_collide(f * (1.35 * STUD))
	velocity = Vector3.ZERO
	_stop_climb()
	grounded = true
	return true


func _drive_climb(wish: Vector3, delta: float) -> void:
	var up_amount := wish.dot(_climb_face)
	if _jump_buffer_left > 0.0:
		_jump_buffer_left = 0.0
		_ladder_dismount = LADDER_DISMOUNT
		velocity.y = LADDER_JUMP * 0.65
		velocity.x = -_climb_face.x * 7.0 * STUD
		velocity.z = -_climb_face.z * 7.0 * STUD
		_stop_climb()
		return
	var spd := _active_climb_speed if _active_climb_speed > 0.0 else climb_speed
	if up_amount > 0.12:
		velocity.y = spd
		climbing = true
	elif up_amount < -0.12:
		velocity.y = -spd
		climbing = true
	else:
		velocity.y = 0.0
		climbing = true
	# Do not push deep into gaps between ladder rungs; if capsule catches on an overhead rung lip, nudge outward
	if velocity.y > 0.0:
		var up_step := Vector3.UP * (velocity.y * delta + 0.10 * STUD)
		if test_move(global_transform, up_step):
			var back_dir := -Vector3(_climb_face.x, 0.0, _climb_face.z).normalized()
			for push_out: float in [0.12, 0.25, 0.40, 0.58]:
				var shift := back_dir * (push_out * STUD)
				if not test_move(global_transform, shift):
					var cand := global_transform.translated(shift)
					if not test_move(cand, up_step):
						global_transform = cand
						break
	var hug := 0.0 if is_on_wall() else 1.4 * STUD
	velocity.x = _climb_face.x * hug
	velocity.z = _climb_face.z * hug


func _stop_climb() -> void:
	_climb_kind = ClimbKind.NONE
	climbing = false
	_climb_grace = 0.0


func _nearest_ladder() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for lad in _ladder_areas:
		if not is_instance_valid(lad):
			continue
		var d := lad.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = lad
	return best


func _toward(lad: Node3D) -> Vector3:
	if lad == null or not is_instance_valid(lad):
		return Vector3.ZERO
	var to := lad.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0016:
		return Vector3(-sin(heading), 0.0, -cos(heading))
	return to.normalized()


func _drive_ground_air(wish: Vector3, delta: float) -> void:
	var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	var spd_mult := _speed_boost_mult if _speed_boost_timer > 0.0 else 1.0
	var grav_mult := _gravity_boost_mult if _gravity_boost_timer > 0.0 else 1.0
	var target := wish * (walk_speed * spd_mult)
	if wish.length_squared() < 0.005 and is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, BRAKE_GROUND * delta)
		velocity.z = move_toward(velocity.z, 0.0, BRAKE_GROUND * delta)
	else:
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * grav_mult * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	var can_jump: bool = is_on_floor() or _coyote > 0.0 or is_on_wall()
	if _jump_buffer_left > 0.0 and can_jump:
		_jump_buffer_left = 0.0
		_coyote = 0.0
		velocity.y = jump_power * (_jump_boost_mult if _gravity_boost_timer > 0.0 else 1.0)
		_play_jump_sound()
		_dust()


func _perform_step_up(wish: Vector3, delta: float) -> void:
	if (not is_on_floor() and _coyote <= 0.0) or wish.length_squared() < 0.005:
		return
	var step_h := maxf(max_step_studs, 2.05) * STUD
	var move_dir := wish.normalized()
	var horiz_step := move_dir * maxf(Vector2(velocity.x, velocity.z).length() * delta, 0.38 * STUD)
	if not test_move(global_transform, horiz_step):
		return
	if test_move(global_transform, Vector3.UP * step_h):
		return
	var up_xform := global_transform.translated(Vector3.UP * step_h)
	if test_move(up_xform, horiz_step):
		return
	var forward_xform := up_xform.translated(horiz_step)
	var down_res := KinematicCollision3D.new()
	if test_move(forward_xform, Vector3.DOWN * (step_h + 0.15 * STUD), down_res):
		var actual_step := step_h - down_res.get_travel().length()
		if actual_step >= 0.04 * STUD and actual_step <= step_h + 0.08:
			global_transform = forward_xform.translated(Vector3.DOWN * down_res.get_travel().length())
			if velocity.y < 0.0:
				velocity.y = 0.0


func _dust(strength := 1.0) -> void:
	if not dust_enabled or not alive:
		return
	if _settings != null and int(_settings.get("graphics_quality")) <= 1:
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
	puff.initial_velocity_max = 5.0 * STUD * strength
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


func die(world: Node3D) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	health_changed.emit(health, MAX_HEALTH)
	velocity = Vector3.ZERO
	_stop_climb()
	if voice_indicator != null and is_instance_valid(voice_indicator):
		voice_indicator.visible = false
	avatar.call("burst", world, randi())


func respawn_at(pos: Vector3) -> void:
	_ensure_nodes()
	alive = true
	health = MAX_HEALTH
	_regen_wait = 0.0
	_falling = false
	_stop_climb()
	_ladder_dismount = 0.0
	_rise_left = 0.0
	_touching_damage.clear()
	_touching_heal.clear()
	_damage_tick_cd = 0.0
	_heal_tick_cd = 0.0
	avatar.position.y = 0.0
	health_changed.emit(health, MAX_HEALTH)
	global_position = pos
	velocity = Vector3.ZERO
	heading = 0.0
	avatar.rotation.y = 0.0
	avatar.visible = true
	_refresh_voice_bubble(0.0)
	_dust(1.3)


func _do_bounce(custom_power := BOUNCE_POWER) -> void:
	if not alive or _bounce_cd > 0.0:
		return
	_bounce_cd = BOUNCE_COOLDOWN
	velocity.y = custom_power
	_falling = true
	_fall_peak_y = global_position.y
	_play_jump_sound(0.9)
	_dust(1.4)


func _play_jump_sound(_pitch := 1.0) -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.call("play_jump_3d", self)


func _play_land_sound() -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.call("play_land_3d", self)


func _update_loops() -> void:
	if _steps_loop == null or _climb_loop == null:
		return
	if not is_instance_valid(_steps_loop) or not is_instance_valid(_climb_loop):
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var walking := alive and grounded and not climbing and hspeed > 2.0 * STUD
	_steps_loop.playing = walking
	if walking:
		_steps_loop.pitch_scale = clampf(1.85 * (0.9 + hspeed / walk_speed * 0.2), 1.4, 2.2)
	_climb_loop.playing = alive and climbing
	if _fall_loop != null and is_instance_valid(_fall_loop):
		var plummeting := alive and not grounded and not climbing and velocity.y < -FALL_WIND_SPEED
		_fall_loop.playing = plummeting


static func _is_climbable_node(other: Node3D) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	if other.is_in_group("ladder") or other.is_in_group("climb"):
		return true
	var nm := other.name.to_lower()
	if nm.contains("ladder") or nm.contains("climb") or nm.contains("truss"):
		return true
	var par := other.get_parent()
	if par is Node3D:
		var pn := (par as Node3D).name.to_lower()
		if par.is_in_group("ladder") or par.is_in_group("climb") or pn.contains("ladder") or pn.contains("climb") or pn.contains("truss"):
			return true
	if other is CollisionObject3D and (((other as CollisionObject3D).collision_layer & 16) != 0):
		return true
	return false


func _setup_ladder_sensor() -> void:
	var area := Area3D.new()
	area.name = "LadderSensor"
	area.collision_layer = 0
	area.collision_mask = 16 | 1
	area.monitoring = true
	area.monitorable = false
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8 * STUD, 3.0 * STUD, 2.8 * STUD)
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, 2.6 * STUD, 0.0)
	area.add_child(shape_node)
	add_child(area)
	_ladder_sensor = area
	var on_enter := func(other: Node3D) -> void:
		if other != self and _is_climbable_node(other) and not _ladder_areas.has(other):
			_ladder_areas.append(other)
	var on_exit := func(other: Node3D) -> void:
		_ladder_areas.erase(other)
	area.area_entered.connect(on_enter)
	area.area_exited.connect(on_exit)
	area.body_entered.connect(on_enter)
	area.body_exited.connect(on_exit)


func _on_touch_entered(other: Node3D) -> void:
	if other == null or other == self or not is_instance_valid(other):
		return
	if other.is_in_group("kill") or other.get("insta_kill") == true:
		touched_group.emit("kill", other)
		return
	if other.is_in_group("insta_heal") or other.get("insta_heal") == true:
		if health < MAX_HEALTH:
			heal(MAX_HEALTH)
		touched_group.emit("insta_heal", other)
		return
	if other.is_in_group("damage"):
		if not _touching_damage.has(other):
			_touching_damage.append(other)
		if _damage_tick_cd <= 0.0:
			var dmg := _node_float(other, "damage_amount", "damage", 20.0)
			var cd := _node_float(other, "damage_cooldown", "damage_cooldown", 0.55)
			hurt(dmg)
			_damage_tick_cd = cd
			touched_group.emit("damage", other)
		return
	if other.is_in_group("heal"):
		if not _touching_heal.has(other):
			_touching_heal.append(other)
		if _heal_tick_cd <= 0.0:
			var h_amt := _node_float(other, "heal_amount", "heal", 15.0)
			var h_cd := _node_float(other, "heal_cooldown", "heal_cooldown", 0.45)
			if health < MAX_HEALTH:
				heal(h_amt)
			_heal_tick_cd = h_cd
			touched_group.emit("heal", other)
		return
	for g in ["goal", "checkpoint", "bounce", "speed_pad", "gravity_pad"]:
		if other.is_in_group(g):
			if g == "bounce":
				var bp := _node_float(other, "bounce_power", "bounce_power", BOUNCE_POWER)
				_do_bounce(bp * STUD)
				return
			if g == "speed_pad":
				_speed_boost_mult = _node_float(other, "speed_multiplier", "speed_multiplier", 1.65)
				_speed_boost_timer = _node_float(other, "speed_duration", "speed_duration", 10.0)
				_dust(1.5)
				touched_group.emit(g, other)
				return
			if g == "gravity_pad":
				_gravity_boost_mult = _node_float(other, "gravity_multiplier", "gravity_multiplier", 0.42)
				_jump_boost_mult = _node_float(other, "jump_boost_multiplier", "jump_boost_multiplier", 1.25)
				_gravity_boost_timer = _node_float(other, "gravity_duration", "gravity_duration", 10.0)
				_dust(1.5)
				touched_group.emit(g, other)
				return
			touched_group.emit(g, other)
			return


func _on_touch_exited(other: Node3D) -> void:
	_touching_damage.erase(other)
	_touching_heal.erase(other)


func _setup_touch_sensor() -> void:
	var area := Area3D.new()
	area.name = "TouchSensor"
	area.collision_layer = 0
	area.collision_mask = 1 | 16
	area.monitoring = true
	area.monitorable = false
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.35 * STUD
	shape.height = 5.6 * STUD
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, 2.4 * STUD, 0.0)
	area.add_child(shape_node)
	add_child(area)
	_touch_sensor = area
	area.body_entered.connect(_on_touch_entered)
	area.body_exited.connect(_on_touch_exited)
	area.area_entered.connect(_on_touch_entered)
	area.area_exited.connect(_on_touch_exited)
