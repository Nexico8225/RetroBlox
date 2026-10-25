extends Node
# Handles microphone capture, voice activity detection, UDP + HTTP multiplayer voice streaming, and 3D spatial voice playback.

signal speaking_changed(speaking: bool, level: float)
signal mute_changed(muted: bool)
signal device_changed(device_name: String)
signal remote_voice_packet(user_id: String, pcm: PackedVector2Array, level: float)

const VOICE_MIX_RATE := 11025.0
const NET_VOICE_RATE := 8000.0
const UDP_PORTS: Array[int] = [42855, 42856, 42857, 42858]

var current_level := 0.0

var _muted := true
var _speaking := false
var _effect_capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _record_bus_index := -1
var _settings: Node
var _speak_decay := 0.0
var _registered_players: Array[AudioStreamPlayer3D] = []
var _playbacks: Dictionary = {}

var _udp_rx: PacketPeerUDP
var _udp_tx: PacketPeerUDP
var _bound_port := -1
var _tx_accum_11k: PackedFloat32Array = PackedFloat32Array()
var _net_accum_8k: PackedByteArray = PackedByteArray()
var _resample_phase_11k := 0.0
var _resample_phase_8k := 0.0


func _ready() -> void:
	_settings = get_node_or_null("/root/Settings")
	if _settings != null:
		_muted = bool(_settings.get("voice_muted"))
	_setup_record_bus()
	_setup_udp()
	if not _muted:
		call_deferred("_setup_mic_player")


func _setup_udp() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	_udp_rx = PacketPeerUDP.new()
	for p in UDP_PORTS:
		if _udp_rx.bind(p, "*") == OK:
			_bound_port = p
			break
	_udp_tx = PacketPeerUDP.new()
	_udp_tx.set_broadcast_enabled(true)


func _setup_record_bus() -> void:
	_record_bus_index = AudioServer.get_bus_index("Record")
	if _record_bus_index == -1:
		AudioServer.add_bus()
		_record_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_record_bus_index, "Record")
		AudioServer.set_bus_mute(_record_bus_index, true)
		AudioServer.set_bus_send(_record_bus_index, "Master")

	for i in range(AudioServer.get_bus_effect_count(_record_bus_index)):
		var eff := AudioServer.get_bus_effect(_record_bus_index, i)
		if eff is AudioEffectCapture:
			_effect_capture = eff as AudioEffectCapture
			break

	if _effect_capture == null:
		_effect_capture = AudioEffectCapture.new()
		_effect_capture.buffer_length = 0.25
		AudioServer.add_bus_effect(_record_bus_index, _effect_capture)


func _stop_mic_player() -> void:
	if _mic_player != null and is_instance_valid(_mic_player):
		_mic_player.stop()
		_mic_player.stream = null
		_mic_player.queue_free()
		_mic_player = null
	if _effect_capture != null:
		_effect_capture.clear_buffer()
	_tx_accum_11k.clear()
	_net_accum_8k.clear()


func _setup_mic_player() -> void:
	_stop_mic_player()
	if _muted or DisplayServer.get_name() == "headless":
		return

	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "MicRecorder"
	_mic_player.bus = &"Record"
	_mic_player.stream = AudioStreamMicrophone.new()
	add_child(_mic_player)
	_mic_player.play()


func _process(delta: float) -> void:
	_poll_udp_rx()

	if _muted:
		if _speaking or current_level > 0.001:
			_speaking = false
			current_level = 0.0
			speaking_changed.emit(false, 0.0)
		return

	var raw_energy := 0.0
	var captured_samples := PackedVector2Array()
	if _effect_capture != null:
		var frames_avail := _effect_capture.get_frames_available()
		if frames_avail > 0:
			captured_samples = _effect_capture.get_buffer(frames_avail)
			if not captured_samples.is_empty():
				var sum_sq := 0.0
				var count := captured_samples.size()
				for i in range(count):
					var s := captured_samples[i]
					sum_sq += s.x * s.x + s.y * s.y
				var rms := sqrt(sum_sq / maxf(float(count * 2), 1.0))
				raw_energy = clampf(rms * 14.0, 0.0, 1.0)

	var sens := 0.5
	if _settings != null:
		sens = float(_settings.get("mic_sensitivity"))
	var gate := lerpf(0.14, 0.02, clampf(sens, 0.0, 1.0))

	if raw_energy > gate:
		_speak_decay = 0.4
		_speaking = true
	elif _speak_decay > 0.0:
		_speak_decay -= delta
		_speaking = true
	else:
		_speaking = false

	var target_lvl := raw_energy if _speaking else 0.0
	current_level = lerpf(current_level, target_lvl, 1.0 - exp(-20.0 * delta))
	speaking_changed.emit(_speaking, current_level)

	if _speaking and not captured_samples.is_empty():
		_encode_and_queue_mic(captured_samples)


func _encode_and_queue_mic(samples: PackedVector2Array) -> void:
	var in_rate := maxf(AudioServer.get_mix_rate(), 8000.0)
	var step_11k := in_rate / VOICE_MIX_RATE
	var step_8k := in_rate / NET_VOICE_RATE
	var n := samples.size()

	while _resample_phase_11k < float(n):
		var idx := int(_resample_phase_11k)
		var s := samples[idx]
		var mono := clampf((s.x + s.y) * 0.75, -1.0, 1.0)
		_tx_accum_11k.append(mono)
		_resample_phase_11k += step_11k
	_resample_phase_11k -= float(n)

	while _resample_phase_8k < float(n):
		var idx2 := int(_resample_phase_8k)
		var s2 := samples[idx2]
		var mono2 := clampf((s2.x + s2.y) * 0.75, -1.0, 1.0)
		var q8 := clampi(int(roundf((mono2 * 0.5 + 0.5) * 255.0)), 0, 255)
		_net_accum_8k.append(q8)
		_resample_phase_8k += step_8k
	_resample_phase_8k -= float(n)

	# Keep at most 1.2s of 8kHz audio for HTTP relay
	if _net_accum_8k.size() > 9600:
		_net_accum_8k = _net_accum_8k.slice(_net_accum_8k.size() - 9600)

	# Broadcast 45ms UDP chunks (~500 samples at 11.025 kHz) for real-time low-latency playback
	while _tx_accum_11k.size() >= 500:
		var chunk := _tx_accum_11k.slice(0, 500)
		_tx_accum_11k = _tx_accum_11k.slice(500)
		_broadcast_udp_chunk(chunk)


func _broadcast_udp_chunk(chunk: PackedFloat32Array) -> void:
	if _udp_tx == null:
		return
	var sess: Node = get_node_or_null("/root/Session")
	var uid := "" if sess == null else String(sess.get("user_id"))
	if uid == "":
		return
	var uid_bytes := uid.to_utf8_buffer()
	if uid_bytes.size() > 64:
		uid_bytes = uid_bytes.slice(0, 64)
	var pkt := StreamPeerBuffer.new()
	pkt.put_data("RBVC".to_ascii_buffer())
	pkt.put_u8(uid_bytes.size())
	pkt.put_data(uid_bytes)
	pkt.put_float(current_level)
	pkt.put_u16(chunk.size())
	for i in range(chunk.size()):
		var s16 := clampi(int(roundf(chunk[i] * 32767.0)), -32767, 32767)
		pkt.put_16(s16)
	var raw := pkt.data_array
	for p in UDP_PORTS:
		if p != _bound_port:
			_udp_tx.set_dest_address("127.0.0.1", p)
			_udp_tx.put_packet(raw)
		_udp_tx.set_dest_address("255.255.255.255", p)
		_udp_tx.put_packet(raw)


func _poll_udp_rx() -> void:
	if _udp_rx == null:
		return
	var sess: Node = get_node_or_null("/root/Session")
	var my_uid := "" if sess == null else String(sess.get("user_id"))
	while _udp_rx.get_available_packet_count() > 0:
		var raw := _udp_rx.get_packet()
		if raw.size() < 12:
			continue
		if raw.slice(0, 4).get_string_from_ascii() != "RBVC":
			continue
		var sp := StreamPeerBuffer.new()
		sp.data_array = raw
		sp.seek(4)
		var uid_len := sp.get_u8()
		if uid_len <= 0 or sp.get_position() + uid_len + 6 > raw.size():
			continue
		var uid := raw.slice(5, 5 + uid_len).get_string_from_utf8()
		if uid == "" or uid == my_uid:
			continue
		sp.seek(5 + uid_len)
		var lvl := sp.get_float()
		var sample_count := sp.get_u16()
		if sample_count <= 0 or sp.get_position() + sample_count * 2 > raw.size():
			continue
		var pcm := PackedVector2Array()
		pcm.resize(sample_count)
		for i in range(sample_count):
			var f := float(sp.get_16()) / 32767.0
			pcm[i] = Vector2(f, f)
		remote_voice_packet.emit(uid, pcm, lvl)


func pop_network_voice_packet() -> String:
	if _net_accum_8k.is_empty():
		return ""
	var out := Marshalls.raw_to_base64(_net_accum_8k)
	_net_accum_8k.clear()
	return out


func decode_network_voice_packet(b64: String) -> PackedVector2Array:
	if b64 == "":
		return PackedVector2Array()
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return PackedVector2Array()
	var in_len := raw.size()
	var out_len := int(roundf(float(in_len) * (VOICE_MIX_RATE / NET_VOICE_RATE)))
	if out_len <= 0:
		return PackedVector2Array()
	var pcm := PackedVector2Array()
	pcm.resize(out_len)
	for i in range(out_len):
		var src_f := float(i) * (NET_VOICE_RATE / VOICE_MIX_RATE)
		var idx0 := clampi(int(src_f), 0, in_len - 1)
		var idx1 := mini(idx0 + 1, in_len - 1)
		var frac := src_f - float(idx0)
		var s0 := (float(raw[idx0]) / 255.0 - 0.5) * 2.0
		var s1 := (float(raw[idx1]) / 255.0 - 0.5) * 2.0
		var s := lerpf(s0, s1, frac)
		pcm[i] = Vector2(s, s)
	return pcm


func is_muted() -> bool:
	return _muted


func set_muted(val: bool) -> void:
	if _muted == val:
		return
	_muted = val
	if _settings != null:
		_settings.set_key("voice_muted", _muted)
	if _muted:
		_stop_mic_player()
		_speaking = false
		current_level = 0.0
		speaking_changed.emit(false, 0.0)
	else:
		_setup_mic_player()
	mute_changed.emit(_muted)


func toggle_mute() -> bool:
	set_muted(not _muted)
	return _muted


func is_speaking() -> bool:
	return _speaking and not _muted


func get_level() -> float:
	return current_level if (_speaking and not _muted) else 0.0


func get_input_devices() -> PackedStringArray:
	if DisplayServer.get_name() == "headless":
		return PackedStringArray(["Default"])
	var list := AudioServer.get_input_device_list()
	if list.is_empty():
		return PackedStringArray(["Default"])
	return list


func get_input_device() -> String:
	if DisplayServer.get_name() == "headless":
		return "Default"
	var dev := AudioServer.get_input_device()
	return "Default" if dev == "" else dev


func set_input_device(device_name: String) -> void:
	_stop_mic_player()
	if DisplayServer.get_name() != "headless":
		AudioServer.set_input_device(device_name)
	if _settings != null:
		_settings.set_key("input_device", device_name)
	if not _muted:
		call_deferred("_setup_mic_player")
	device_changed.emit(device_name)


func make_voice_player_3d(parent: Node3D) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "VoicePlayer3D"
	player.bus = &"Voice"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 10.0
	player.max_distance = 70.0
	player.position = Vector3(0.0, 4.5, 0.0)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VOICE_MIX_RATE
	gen.buffer_length = 0.65
	player.stream = gen

	parent.add_child(player)
	player.play()
	_registered_players.append(player)
	_playbacks[player] = player.get_stream_playback()
	return player


func play_voice_packet(player: AudioStreamPlayer3D, pcm: PackedVector2Array) -> void:
	if player == null or not is_instance_valid(player) or pcm.is_empty():
		return
	if not player.playing:
		player.play()
	var pb: AudioStreamGeneratorPlayback = _playbacks.get(player)
	if pb == null:
		pb = player.get_stream_playback()
		_playbacks[player] = pb
	if pb == null:
		return
	var avail := pb.get_frames_available()
	if avail <= 0:
		return
	if pcm.size() <= avail:
		pb.push_buffer(pcm)
	else:
		pb.push_buffer(pcm.slice(0, avail))
