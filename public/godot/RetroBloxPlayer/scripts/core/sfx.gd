extends Node
## Sfx — every sound the UI and character make, from ONE place.
## Autoload "Sfx".
##
## CHARACTER SOUNDS = the authentic Roblox client files (2018 client dump,
## the same files the official RbxCharacterSounds script plays):
##   jump      = action_jump.mp3            (the classic whoosh)
##   land      = action_jump_land.mp3       (landing thud)
##   footsteps = action_footsteps_plastic.mp3 @ ~1.85 (Roblox Running spec)
##   climb     = action_footsteps_plastic.mp3 looped, higher pitch
##   falling   = action_falling.mp3         (wind loop, Roblox FreeFalling)
##   oof       = uuhhh.mp3                  (THE original death sound)
## UI: the classic button CLICK and a soft HOVER tick play on every Button in
## the whole client (login, hub, HUD) — wired automatically via node_added.
## NOTE: the music box is GONE (removed by popular demand) — only the sky
## wind ambience remains of the screen loops.

const CLICK := "res://assets/sfx_click.mp3"
const HOVER := "res://assets/ui_hover.wav"
const JOIN := "res://assets/ui_join.wav"
const WIND := "res://assets/amb_wind.wav"           # sky ambience (cloud places)
const JUMP_PREFS: Array[String] = [
        "res://assets/rbx_action_jump.mp3",      # authentic client file
        "res://assets/sfx_jump.mp3",             # older kit fallback
]
const STEPS_PREFS: Array[String] = [
        "res://assets/rbx_action_footsteps_plastic.mp3",
        "res://assets/sfx_footsteps.mp3",
]
const LAND_PREFS: Array[String] = [
        "res://assets/rbx_action_jump_land.mp3",
]
const FALL_PREFS: Array[String] = [
        "res://assets/rbx_action_falling.mp3",
]
const OOF_PREFS: Array[String] = [
        "res://assets/rbx_uuhhh.mp3",            # the original oof
        "res://assets/oof.wav",
]
const TIX_PREFS: Array[String] = [
        "res://assets/sfx_tix.wav",              # original coin chime
]
const GOAL_PREFS: Array[String] = [
        "res://assets/sfx_goal.wav",             # original victory fanfare
]

var _click: AudioStream
var _hover: AudioStream
var _join: AudioStream
var _jump: AudioStream
var _steps: AudioStream
var _land: AudioStream
var _fall: AudioStream
var _oof: AudioStream
var _tix: AudioStream
var _goal: AudioStream
var _wind: AudioStream
var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
        _click = _load(CLICK)
        _hover = _load(HOVER)
        _join = _load(JOIN)
        _jump = _load_first(JUMP_PREFS)
        _steps = _load_first(STEPS_PREFS)
        _land = _load_first(LAND_PREFS)
        _fall = _load_first(FALL_PREFS)
        _oof = _load_first(OOF_PREFS)
        _tix = _load_first(TIX_PREFS)
        _goal = _load_first(GOAL_PREFS)
        _wind = _load(WIND)
        for i in range(6):
                var p := AudioStreamPlayer.new()
                p.bus = "SFX"
                add_child(p)
                _pool.append(p)
        get_tree().node_added.connect(_on_node_added)


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


## Click on EVERY button press, hover tick on mouse-over — the whole client
## gets the classic UI sounds without each screen remembering to ask.
func _on_node_added(node: Node) -> void:
        if node is BaseButton:
                var b := node as BaseButton
                if b.is_in_group("no_ui_sfx"):
                        return
                b.pressed.connect(play_click, CONNECT_DEFERRED)
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
                p.volume_db = -6.0
                p.play()


func play_hover() -> void:
        if _hover != null:
                var p := _grab()
                p.stream = _hover
                p.volume_db = -10.0
                p.play()


func play_join() -> void:
        if _join != null:
                var p := _grab()
                p.stream = _join
                p.volume_db = -6.0
                p.play()


## One-shot 3D jump sound, parented at the jumping player.
func play_jump_3d(at: Node3D) -> void:
        _play_one_shot_3d(_jump, "JumpSfx", at, -2.0)


## One-shot 3D landing thud (Roblox plays this after air time).
func play_land_3d(at: Node3D) -> void:
        _play_one_shot_3d(_land, "LandSfx", at, -6.0)


## The original oof, positioned at the broken avatar.
func play_oof_3d(at: Node3D) -> void:
        _play_one_shot_3d(_oof, "OofSfx", at, -1.0)


## Coin chime at the collected Tix.
func play_tix_3d(at: Node3D) -> void:
        _play_one_shot_3d(_tix, "TixSfx", at, -2.0)


## Victory fanfare — non positional, it is YOUR win.
func play_goal() -> void:
        if _goal != null:
                var p := _grab()
                p.stream = _goal
                p.volume_db = -3.0
                p.play()


func _play_one_shot_3d(stream: AudioStream, kind: String, at: Node3D, db: float) -> void:
        if stream == null or at == null or not is_instance_valid(at):
                return
        var p := AudioStreamPlayer3D.new()
        p.name = kind
        p.stream = stream
        p.bus = "SFX"
        p.max_distance = 60.0
        p.unit_size = 8.0
        p.volume_db = db
        at.add_child(p)
        p.play()
        p.finished.connect(p.queue_free)


## A looped 3D loop (footsteps / climb / falling wind). Caller keeps the node
## and sets playing on/off — pitch and volume stay under the caller's control.
func make_loop_3d(kind: String, at: Node3D) -> AudioStreamPlayer3D:
        var p := AudioStreamPlayer3D.new()
        p.name = kind
        p.bus = "SFX"
        match kind:
                "FallingLoop":
                        p.stream = _fall
                        p.volume_db = -10.0
                        p.max_distance = 50.0
                        p.unit_size = 9.0
                _:
                        p.stream = _steps
                        p.volume_db = -14.0
                        p.max_distance = 45.0
                        p.unit_size = 7.0
        at.add_child(p)
        return p


## A NON-positional looped player for the whole-screen ambience: the sky
## wind ("SFX" bus). The "Music" kind intentionally returns null now — the
## music box was removed. Loop points are set on the stream itself.
func make_screen_loop(kind: String) -> AudioStreamPlayer:
        if kind != "Wind":
                return null
        var p := AudioStreamPlayer.new()
        p.name = kind
        p.stream = _looped(_wind)
        p.bus = "SFX"
        p.volume_db = -13.0
        return p


## Force WAV loop points in code so the ambience/music loop no matter what the
## import defaults say.
func _looped(stream: AudioStream) -> AudioStream:
        if stream is AudioStreamWAV:
                var wav := stream as AudioStreamWAV
                if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
                        wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
                        wav.loop_begin = 0
                        var bytes_per_frame := 2  # 16-bit mono
                        wav.loop_end = int(wav.data.size() / float(bytes_per_frame))
        return stream
