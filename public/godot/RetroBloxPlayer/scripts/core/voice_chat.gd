extends Node
# Handles microphone capture, voice activity detection, input device switching, and 3D spatial voice playback.

signal speaking_changed(speaking: bool, level: float)
signal mute_changed(muted: bool)
signal device_changed(device_name: String)

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


func _ready() -> void:
	_settings = get_node_or_null("/root/Settings")
	if _settings != null:
		_muted = bool(_settings.get("voice_muted"))
	_setup_record_bus()
	if not _muted:
		call_deferred("_setup_mic_player")


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
	if _muted:
		if _speaking or current_level > 0.001:
			_speaking = false
			current_level = 0.0
			speaking_changed.emit(false, 0.0)
		return

	var raw_energy := 0.0
	if _effect_capture != null:
		var frames_avail := _effect_capture.get_frames_available()
		if frames_avail > 0:
			var samples := _effect_capture.get_buffer(frames_avail)
			if not samples.is_empty():
				var sum_sq := 0.0
				var count := samples.size()
				for i in range(count):
					var s := samples[i]
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
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	player.stream = gen

	parent.add_child(player)
	player.play()
	_registered_players.append(player)
	_playbacks[player] = player.get_stream_playback()
	return player


func play_voice_packet(player: AudioStreamPlayer3D, pcm: PackedVector2Array) -> void:
	if player == null or not is_instance_valid(player):
		return
	var pb: AudioStreamGeneratorPlayback = _playbacks.get(player)
	if pb == null:
		pb = player.get_stream_playback()
		_playbacks[player] = pb
	if pb != null and pb.can_push_buffer(pcm.size()):
		pb.push_buffer(pcm)
