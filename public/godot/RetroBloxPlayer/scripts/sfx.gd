extends Node
## Sfx — RetroBlox original sound bank (autoload as "Sfx").
## Every sound is synthesized in-repo (scripts/make_game_sounds.py) — nothing ripped.
##
## The bank loads at RUNTIME (load(), not preload): preloading .wav from an
## autoload compiles BEFORE the first --import has imported the wavs, which
## used to poison the very first project open with "no resource loaders"
## errors. By load-time the import has long finished, so this just works.

const SOUND_PATHS := {
        "ui_click": "res://assets/audio/ui_click.wav",
        "ui_hover": "res://assets/audio/ui_hover.wav",
        "ui_open": "res://assets/audio/ui_open.wav",
        "ui_close": "res://assets/audio/ui_close.wav",
        "ui_error": "res://assets/audio/ui_error.wav",
        "chat_send": "res://assets/audio/chat_send.wav",
        "chat_receive": "res://assets/audio/chat_receive.wav",
        "coin": "res://assets/audio/coin.wav",
        "respawn": "res://assets/audio/respawn.wav",
        "jump": "res://assets/audio/jump.wav",
        "land": "res://assets/audio/land.wav",
        "swing": "res://assets/audio/swing.wav",
        "hit": "res://assets/audio/hit.wav",
        "explosion": "res://assets/audio/explosion.wav",
        "brick_place": "res://assets/audio/brick_place.wav",
        "brick_pop": "res://assets/audio/brick_pop.wav",
        "oof": "res://assets/oof.wav",
}

var _bank: Dictionary = {}
var _ui_bus := "Master"
var _world_bus := "Master"

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        for key in SOUND_PATHS:
                var stream := load(SOUND_PATHS[key]) as AudioStream
                if stream != null:
                        _bank[key] = stream
        for info in [["UI", "Master"], ["World", "Master"]]:
                if AudioServer.get_bus_index(info[0]) == -1:
                        var i := AudioServer.bus_count
                        AudioServer.add_bus(i)
                        AudioServer.set_bus_name(i, info[0])
                        AudioServer.set_bus_send(i, info[1])
        _ui_bus = "UI" if AudioServer.get_bus_index("UI") != -1 else "Master"
        _world_bus = "World" if AudioServer.get_bus_index("World") != -1 else "Master"

## 2D sound for menu/chat interactions — routed to the UI bus.
func ui(key: String, volume_db: float = 0.0) -> void:
        var stream: AudioStream = _bank.get(key)
        if stream == null:
                return
        var p := AudioStreamPlayer.new()
        p.stream = stream
        p.bus = _ui_bus
        p.volume_db = volume_db
        add_child(p)
        p.finished.connect(p.queue_free)
        p.play()

## Positional 3D sound — attach under `parent` so it can play then free.
func at(key: String, pos: Vector3, parent: Node, volume_db: float = 0.0) -> void:
        var stream: AudioStream = _bank.get(key)
        if stream == null or parent == null or not parent.is_inside_tree():
                return
        var p := AudioStreamPlayer3D.new()
        p.stream = stream
        p.bus = _world_bus
        p.volume_db = volume_db
        p.unit_size = 14.0
        parent.add_child(p)
        p.global_position = pos
        p.finished.connect(p.queue_free)
        p.play()

func set_volume(bus_name: String, linear: float) -> void:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx != -1:
                AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
