# RetroSounds — one tiny door to every sound in the player.
#
# Slots live in assets/sounds/ named after what they do: Hover, OOF,
# RetroBloxJump, Walking. mp3 wins when present (drop the real mp3 in and
# it is used instantly), wav is the fallback. Nothing is loaded until the
# first call, so a fresh project parses cleanly before Godot imports assets.
class_name RetroSounds
extends RefCounted

const DIR := "res://assets/sounds/"

static var _cache: Dictionary = {}


## Load a slot by name ("Hover", "RetroBloxJump"...). Returns null when the
## slot has no file yet — callers must tolerate silence.
static func stream(slot: String, looped: bool = false) -> AudioStream:
        var key := slot + ("#loop" if looped else "")
        if _cache.has(key):
                return _cache[key]
        var found: AudioStream = null
        for ext: String in ["mp3", "ogg", "wav"]:
                var path: String = DIR + slot + "." + ext
                if ResourceLoader.exists(path):
                        found = load(path) as AudioStream
                        break
        if found != null and looped:
                if found is AudioStreamMP3:
                        (found as AudioStreamMP3).loop = true
                elif found is AudioStreamOggVorbis:
                        (found as AudioStreamOggVorbis).loop = true
                elif found is AudioStreamWAV:
                        var wav := found as AudioStreamWAV
                        wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
                        wav.loop_begin = 0
                        wav.loop_end = wav.data.size() / 2  # 16-bit mono frames
        _cache[key] = found
        return found


## A ready-to-play non-positional player (UI sounds).
static func ui_player(slot: String, volume_db: float = -8.0) -> AudioStreamPlayer:
        var player := AudioStreamPlayer.new()
        player.name = "Sfx_" + slot
        player.stream = stream(slot)
        player.volume_db = volume_db
        player.bus = "Master"
        return player


## A ready-to-play 3D player (world sounds like jump / footsteps).
static func world_player(slot: String, volume_db: float = -6.0, looped: bool = false) -> AudioStreamPlayer3D:
        var player := AudioStreamPlayer3D.new()
        player.name = "Sfx_" + slot
        player.stream = stream(slot, looped)
        player.volume_db = volume_db
        player.max_distance = 45.0
        player.unit_size = 12.0
        player.bus = "Master"
        return player
