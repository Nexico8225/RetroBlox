extends Node
## Sfx — every sound the UI and character make, from ONE place.
## Autoload "Sfx".
##
## UI: the classic button CLICK and a soft HOVER tick play on every Button in
## the whole client (login, hub, HUD) — wired automatically via node_added.
## World: one-shot 3D sounds (jump) and looped 3D loops (footsteps / climb)
## are played by the player controller through the helpers here, so every
## player hears them positioned in the world.

const CLICK := "res://assets/sfx_click.mp3"
const HOVER := "res://assets/ui_hover.wav"
const JOIN := "res://assets/ui_join.wav"
const JUMP := "res://assets/sfx_jump.mp3"
const FOOTSTEPS := "res://assets/sfx_footsteps.mp3"

var _click: AudioStream
var _hover: AudioStream
var _join: AudioStream
var _jump: AudioStream
var _steps: AudioStream
var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
        _click = _load(CLICK)
        _hover = _load(HOVER)
        _join = _load(JOIN)
        _jump = _load(JUMP)
        _steps = _load(FOOTSTEPS)
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
        if _jump == null or at == null or not is_instance_valid(at):
                return
        var p := AudioStreamPlayer3D.new()
        p.name = "JumpSfx"
        p.stream = _jump
        p.bus = "SFX"
        p.max_distance = 60.0
        p.unit_size = 8.0
        p.volume_db = -2.0
        at.add_child(p)
        p.play()
        p.finished.connect(p.queue_free)


## A looped 3D loop (footsteps / climb). Caller keeps the node and sets
## playing on/off — volume_db and pitch stay under the caller's control.
func make_loop_3d(kind: String, at: Node3D) -> AudioStreamPlayer3D:
        var p := AudioStreamPlayer3D.new()
        p.name = kind
        p.bus = "SFX"
        if _steps != null:
                p.stream = _steps
        p.max_distance = 45.0
        p.unit_size = 7.0
        p.volume_db = -14.0
        at.add_child(p)
        return p
