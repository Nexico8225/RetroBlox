extends Node
# Plays classic 2D UI sounds and 3D character audio loops.

const CLICK_PREFS: Array[String] = [
	"res://assets/SFX/sfx_click.mp3",
	"res://assets/sfx_click.mp3",
]
const HOVER_PREFS: Array[String] = [
	"res://assets/SFX/ui_hover.wav",
	"res://assets/ui_hover.wav",
]
const JOIN_PREFS: Array[String] = [
	"res://assets/SFX/ui_join.wav",
	"res://assets/ui_join.wav",
]
const WIND_PREFS: Array[String] = [
	"res://assets/SFX/amb_wind.wav",
	"res://assets/amb_wind.wav",
]
const JUMP_PREFS: Array[String] = [
	"res://assets/SFX/rbx_action_jump.mp3",
	"res://assets/SFX/sfx_jump.mp3",
	"res://assets/rbx_action_jump.mp3",
	"res://assets/sfx_jump.mp3",
]
const STEPS_PREFS: Array[String] = [
	"res://assets/SFX/rbx_action_footsteps_plastic.mp3",
	"res://assets/SFX/sfx_footsteps.mp3",
	"res://assets/rbx_action_footsteps_plastic.mp3",
	"res://assets/sfx_footsteps.mp3",
]
const LAND_PREFS: Array[String] = [
	"res://assets/SFX/rbx_action_jump_land.mp3",
	"res://assets/rbx_action_jump_land.mp3",
]
const FALL_PREFS: Array[String] = [
	"res://assets/SFX/rbx_action_falling.mp3",
	"res://assets/rbx_action_falling.mp3",
]
const OOF_PREFS: Array[String] = [
	"res://assets/SFX/rbx_uuhhh.mp3",
	"res://assets/SFX/oof.wav",
	"res://assets/rbx_uuhhh.mp3",
	"res://assets/oof.wav",
]
const GOAL_PREFS: Array[String] = [
	"res://assets/SFX/sfx_goal.wav",
	"res://assets/sfx_goal.wav",
]

var _click: AudioStream
var _hover: AudioStream
var _join: AudioStream
var _jump: AudioStream
var _steps: AudioStream
var _land: AudioStream
var _fall: AudioStream
var _oof: AudioStream
var _goal: AudioStream
var _wind: AudioStream
var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_sfx_bus()
	_click = _load_first(CLICK_PREFS)
	_hover = _load_first(HOVER_PREFS)
	_join = _load_first(JOIN_PREFS)
	_jump = _load_first(JUMP_PREFS)
	_steps = _load_first(STEPS_PREFS)
	_land = _load_first(LAND_PREFS)
	_fall = _load_first(FALL_PREFS)
	_oof = _load_first(OOF_PREFS)
	_goal = _load_first(GOAL_PREFS)
	_wind = _load_first(WIND_PREFS)

	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	get_tree().node_added.connect(_on_node_added)


func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.get_bus_index("SFX"), "Master")


func _load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _load_first(paths: Array[String]) -> AudioStream:
	for path in paths:
		var s := _load(path)
		if s != null:
			return s
	return null


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		if b.is_in_group("no_ui_sfx"):
			return
		if not b.pressed.is_connected(play_click):
			b.pressed.connect(play_click, CONNECT_DEFERRED)
		if not b.mouse_entered.is_connected(play_hover):
			b.mouse_entered.connect(play_hover, CONNECT_DEFERRED)


func _grab() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]


func play_click() -> void:
	if _click != null:
		var p := _grab()
		p.stream = _click
		p.volume_db = -4.0
		p.play()


func play_hover() -> void:
	if _hover != null:
		var p := _grab()
		p.stream = _hover
		p.volume_db = -8.0
		p.play()


func play_join() -> void:
	if _join != null:
		var p := _grab()
		p.stream = _join
		p.volume_db = -4.0
		p.play()


func play_jump_3d(at: Node3D) -> void:
	_play_one_shot_3d(_jump, "JumpSfx", at, 0.0)


func play_land_3d(at: Node3D) -> void:
	_play_one_shot_3d(_land, "LandSfx", at, -2.0)


func play_oof_3d(at: Node3D) -> void:
	_play_one_shot_3d(_oof, "OofSfx", at, 2.0)


func play_goal() -> void:
	if _goal != null:
		var p := _grab()
		p.stream = _goal
		p.volume_db = -2.0
		p.play()


func _play_one_shot_3d(stream: AudioStream, kind: String, at: Node3D, db: float) -> void:
	if stream == null or at == null or not is_instance_valid(at):
		return
	var p := AudioStreamPlayer3D.new()
	p.name = kind
	p.stream = stream
	p.bus = "SFX"
	p.max_distance = 100.0
	p.unit_size = 12.0
	p.volume_db = db
	at.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func make_loop_3d(kind: String, at: Node3D) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = kind
	p.bus = "SFX"
	match kind:
		"FallingLoop":
			p.stream = _looped(_fall)
			p.volume_db = -6.0
			p.max_distance = 80.0
			p.unit_size = 10.0
		"ClimbLoop":
			p.stream = _looped(_steps)
			p.volume_db = -6.0
			p.max_distance = 60.0
			p.unit_size = 10.0
		_:
			p.stream = _looped(_steps)
			p.volume_db = -5.0
			p.max_distance = 60.0
			p.unit_size = 10.0
	at.add_child(p)
	return p


func make_screen_loop(kind: String) -> AudioStreamPlayer:
	if kind != "Wind":
		return null
	var p := AudioStreamPlayer.new()
	p.name = kind
	p.stream = _looped(_wind)
	p.bus = "SFX"
	p.volume_db = -10.0
	return p


func _looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			var bytes_per_frame := 2
			wav.loop_end = int(wav.data.size() / float(bytes_per_frame))
	elif stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		mp3.loop = true
	elif stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
	return stream
