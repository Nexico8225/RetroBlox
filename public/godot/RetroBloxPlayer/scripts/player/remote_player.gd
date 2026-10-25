extends Node3D
# Interpolates remote player positions, animations, chat bubbles, and distance-faded 3D voice chat.
const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")
const ChatBubbleScript := preload("res://scripts/player/chat_bubble.gd")
const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VOICE_MAX_DISTANCE := 65.0

var user_id := ""
var username := ""
var avatar: Node3D
var bubble: ChatBubble
var voice_indicator: Sprite3D
var voice_player: AudioStreamPlayer3D
var voice_active := true

var _target_pos := Vector3.ZERO
var _target_heading := 0.0
var _prev_pos := Vector3.ZERO
var _has_target := false
var _time := 0.0
var _anim_accum := 0.0
var _anim_clock := 0.0
var _voice_speak_timer := 0.0
var _voice_level := 0.0
var _last_voice_seq := 0
var _tex_voice_levels: Array[Texture2D] = []


func _init() -> void:
	avatar = AvatarRigScript.new()
	avatar.name = "Avatar"
	add_child(avatar)
	bubble = ChatBubbleScript.new()
	bubble.name = "ChatBubble"
	add_child(bubble)

	voice_indicator = Sprite3D.new()
	voice_indicator.name = "VoiceIndicator"
	voice_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	voice_indicator.no_depth_test = true
	voice_indicator.pixel_size = 0.0075
	voice_indicator.shaded = false
	voice_indicator.position = Vector3(0.0, 6.55, 0.0)
	for i in range(11):
		_tex_voice_levels.append(RetroUI.load_png_safe("res://assets/ui/voice_levels/level_%d.png" % i))
	voice_indicator.texture = _tex_voice_levels[0] if not _tex_voice_levels.is_empty() else RetroUI.load_png_safe("res://assets/ui/voice_bubble.png")
	voice_indicator.visible = false
	add_child(voice_indicator)


func _ready() -> void:
	var vc: Node = get_node_or_null("/root/VoiceChat")
	if vc != null and vc.has_method("make_voice_player_3d"):
		voice_player = vc.call("make_voice_player_3d", self)
	else:
		voice_player = AudioStreamPlayer3D.new()
		voice_player.name = "VoicePlayer3D"
		voice_player.bus = &"Voice"
		voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice_player.unit_size = 8.0
		voice_player.max_distance = 65.0
		voice_player.position = Vector3(0.0, 4.5, 0.0)
		add_child(voice_player)


func setup(p_user_id: String, p_name: String) -> void:
	user_id = p_user_id
	username = p_name
	name = "Remote_%s" % p_user_id
	avatar.call("setup", p_name)


func dress(api, payload: Dictionary) -> void:
	if payload.is_empty():
		return
	await AvatarDresserScript.apply(api, avatar, payload)


func push_voice_audio(pcm: PackedVector2Array, level: float) -> void:
	_voice_speak_timer = 0.65
	_voice_level = clampf(level, 0.08, 1.0)
	var settings: Node = get_node_or_null("/root/Settings")
	var vc_enabled := true if settings == null else bool(settings.get("voice_enabled"))
	if not vc_enabled or not voice_active or pcm.is_empty():
		return
	var vc: Node = get_node_or_null("/root/VoiceChat")
	if vc != null and vc.has_method("play_voice_packet") and voice_player != null:
		vc.call("play_voice_packet", voice_player, pcm)


func update_state(pos: Vector3, heading: float, is_speaking := false, voice_level := 0.0, voice_b64 := "", voice_seq := 0) -> void:
	_prev_pos = global_position if _has_target else pos
	_target_pos = pos
	_target_heading = heading
	if is_speaking:
		_voice_speak_timer = maxf(_voice_speak_timer, 1.5)
		_voice_level = maxf(_voice_level, clampf(voice_level, 0.15, 1.0))
	if voice_b64 != "" and (voice_seq == 0 or voice_seq != _last_voice_seq):
		_last_voice_seq = voice_seq
		var vc: Node = get_node_or_null("/root/VoiceChat")
		if vc != null and vc.has_method("decode_network_voice_packet"):
			var pcm: PackedVector2Array = vc.call("decode_network_voice_packet", voice_b64)
			if not pcm.is_empty():
				push_voice_audio(pcm, maxf(voice_level, 0.35))
	if not _has_target:
		global_position = pos
		_has_target = true


func _process(delta: float) -> void:
	_time += delta
	if _voice_speak_timer > 0.0:
		_voice_speak_timer -= delta
	else:
		_voice_level = move_toward(_voice_level, 0.0, delta * 3.0)
	if not _has_target:
		return
	var k := 1.0 - exp(-6.0 * delta)
	var before := global_position
	global_position = global_position.lerp(_target_pos, k)
	avatar.rotation.y = lerp_angle(avatar.rotation.y, _target_heading, 1.0 - exp(-10.0 * delta))

	# 3D Spatial Voice Distance Fade: fade both voice volume and overhead voice icon with distance
	var cam := get_viewport().get_camera_3d()
	var dist_fade := 1.0
	var on_stage := true
	if cam != null:
		var head := global_position + Vector3(0.0, 2.5, 0.0)
		var dist := global_position.distance_to(cam.global_position)
		on_stage = dist < 70.0 and cam.is_position_in_frustum(head)
		var t := clampf((dist - 4.0) / maxf(VOICE_MAX_DISTANCE - 4.0, 1.0), 0.0, 1.0)
		dist_fade = 0.0 if dist >= VOICE_MAX_DISTANCE else (1.0 - t) * (1.0 - t)

	var settings: Node = get_node_or_null("/root/Settings")
	var vc_enabled := true if settings == null else bool(settings.get("voice_enabled"))
	if voice_indicator != null and is_instance_valid(voice_indicator):
		var is_speaking := _voice_speak_timer > 0.0
		voice_indicator.visible = vc_enabled and voice_active and dist_fade > 0.02 and is_speaking
		voice_indicator.modulate = Color(1.0, 1.0, 1.0, dist_fade * 0.96)
		if is_speaking:
			var wave := maxf(_voice_level, absf(sin(_time * 10.0)) * 0.75)
			var lvl_idx := clampi(int(round(wave * 10.0)), 1, 10)
			if lvl_idx < _tex_voice_levels.size():
				voice_indicator.texture = _tex_voice_levels[lvl_idx]
			var pulse := 1.0 + (wave * 0.14)
			voice_indicator.scale = Vector3(pulse, pulse, pulse)

	if voice_player != null and is_instance_valid(voice_player):
		voice_player.volume_db = linear_to_db(maxf(dist_fade, 0.0001))

	_anim_accum += delta
	_anim_clock -= delta
	if on_stage or _anim_clock <= 0.0:
		var speed := before.distance_to(global_position) / maxf(delta, 0.0001)
		avatar.call("animate", maxf(_anim_accum, 0.0001), speed, true, false)
		_anim_accum = 0.0
		_anim_clock = 0.0 if on_stage else 0.25


func show_bubble(message: String) -> void:
	bubble.show_text(message)


func fade_out() -> void:
	queue_free()
