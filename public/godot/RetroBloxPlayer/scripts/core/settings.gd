extends Node
## Settings — the player's options, persisted at user://retroblox_settings.cfg
## and applied LIVE: audio bus volumes, camera FOV + sensitivity, sun shadows,
## fullscreen. Autoload "Settings". Every panel reads through here; nothing
## else stores.

const SAVE_PATH := "user://retroblox_settings.cfg"

signal changed(key: String, value: Variant)

var mouse_sensitivity := 1.0      # multiplier on the base look speed
var fov := 70.0                   # camera field of view
var master_volume := 1.0          # 0..1 -> Master bus
var sfx_volume := 1.0             # 0..1 -> SFX bus
var music_volume := 0.7           # 0..1 -> Music bus
var shadows := true               # sun shadows on/off (potato PCs)
var shift_lock := false           # default shift-lock state per session
var fullscreen := false           # borderless fullscreen on next launch + live
var show_fps := true              # v12.0: FPS in the corner stats chip
var show_ping := true             # v12.0: ping in the corner stats chip
var max_fps := 0                  # v12.0: 0 = unlimited, else Engine.max_fps
var player_names := true          # v12.0: nameplates above every avatar
var bunny_hop := true             # v12.0: holding Space keeps hopping (classic)


func _ready() -> void:
        _ensure_buses()
        load_settings()
        apply_audio()
        apply_window()
        apply_max_fps()
        changed.connect(func(_k: String, _v: Variant) -> void: apply_window())


func _ensure_buses() -> void:
        if AudioServer.get_bus_index("SFX") == -1:
                AudioServer.add_bus()
                AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
                AudioServer.set_bus_send(AudioServer.get_bus_index("SFX"), "Master")
        if AudioServer.get_bus_index("Music") == -1:
                AudioServer.add_bus()
                AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
                AudioServer.set_bus_send(AudioServer.get_bus_index("Music"), "Master")


func apply_window() -> void:
        # headless (CI / tests) has no real window to move around
        if DisplayServer.get_name() == "headless":
                return
        var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
        if DisplayServer.window_get_mode() != mode:
                DisplayServer.window_set_mode(mode)


func load_settings() -> void:
        var cf := ConfigFile.new()
        if cf.load(SAVE_PATH) != OK:
                return
        mouse_sensitivity = clampf(float(cf.get_value("input", "mouse_sensitivity", 1.0)), 0.1, 3.0)
        fov = clampf(float(cf.get_value("camera", "fov", 70.0)), 40.0, 110.0)
        master_volume = clampf(float(cf.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
        sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
        music_volume = clampf(float(cf.get_value("audio", "music_volume", 0.7)), 0.0, 1.0)
        shadows = bool(cf.get_value("graphics", "shadows", true))
        shift_lock = bool(cf.get_value("input", "shift_lock", false))
        fullscreen = bool(cf.get_value("graphics", "fullscreen", false))
        show_fps = bool(cf.get_value("hud", "show_fps", true))
        show_ping = bool(cf.get_value("hud", "show_ping", true))
        max_fps = int(cf.get_value("graphics", "max_fps", 0))
        player_names = bool(cf.get_value("world", "player_names", true))
        bunny_hop = bool(cf.get_value("input", "bunny_hop", true))


func save_settings() -> void:
        var cf := ConfigFile.new()
        cf.set_value("input", "mouse_sensitivity", mouse_sensitivity)
        cf.set_value("input", "shift_lock", shift_lock)
        cf.set_value("camera", "fov", fov)
        cf.set_value("audio", "master_volume", master_volume)
        cf.set_value("audio", "sfx_volume", sfx_volume)
        cf.set_value("audio", "music_volume", music_volume)
        cf.set_value("graphics", "shadows", shadows)
        cf.set_value("graphics", "fullscreen", fullscreen)
        cf.set_value("graphics", "max_fps", max_fps)
        cf.set_value("hud", "show_fps", show_fps)
        cf.set_value("hud", "show_ping", show_ping)
        cf.set_value("world", "player_names", player_names)
        cf.set_value("input", "bunny_hop", bunny_hop)
        cf.save(SAVE_PATH)


func apply_audio() -> void:
        var master := AudioServer.get_bus_index("Master")
        if master >= 0:
                AudioServer.set_bus_volume_db(master, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
                AudioServer.set_bus_mute(master, master_volume <= 0.001)
        var sfx := AudioServer.get_bus_index("SFX")
        if sfx >= 0:
                AudioServer.set_bus_volume_db(sfx, linear_to_db(clampf(sfx_volume, 0.0001, 1.0)))
                AudioServer.set_bus_mute(sfx, sfx_volume <= 0.001)
        var music := AudioServer.get_bus_index("Music")
        if music >= 0:
                AudioServer.set_bus_volume_db(music, linear_to_db(clampf(music_volume, 0.0001, 1.0)))
                AudioServer.set_bus_mute(music, music_volume <= 0.001)


func set_key(key: String, value: Variant) -> void:
        match key:
                "mouse_sensitivity":
                        mouse_sensitivity = clampf(float(value), 0.1, 3.0)
                "fov":
                        fov = clampf(float(value), 40.0, 110.0)
                "master_volume":
                        master_volume = clampf(float(value), 0.0, 1.0)
                        apply_audio()
                "sfx_volume":
                        sfx_volume = clampf(float(value), 0.0, 1.0)
                        apply_audio()
                "music_volume":
                        music_volume = clampf(float(value), 0.0, 1.0)
                        apply_audio()
                "shadows":
                        shadows = bool(value)
                "shift_lock":
                        shift_lock = bool(value)
                "fullscreen":
                        fullscreen = bool(value)
                "show_fps":
                        show_fps = bool(value)
                "show_ping":
                        show_ping = bool(value)
                "max_fps":
                        max_fps = maxi(int(value), 0)
                        apply_max_fps()
                "player_names":
                        player_names = bool(value)
                "bunny_hop":
                        bunny_hop = bool(value)
                _:
                        return
        save_settings()
        changed.emit(key, value)


## v12.0: the FPS ceiling, applied live (0 = unlimited, vsync governs web).
func apply_max_fps() -> void:
        Engine.max_fps = maxi(max_fps, 0)


## v12.0 — RESET ALL SETTINGS: every key back to its default, saved, and
## every listener told. The Settings tab rebuilds its controls off this.
func reset_all() -> void:
        mouse_sensitivity = 1.0
        fov = 70.0
        master_volume = 1.0
        sfx_volume = 1.0
        music_volume = 0.7
        shadows = true
        shift_lock = false
        fullscreen = false
        show_fps = true
        show_ping = true
        max_fps = 0
        player_names = true
        bunny_hop = true
        apply_audio()
        apply_window()
        apply_max_fps()
        save_settings()
        for key in ["mouse_sensitivity", "fov", "master_volume", "sfx_volume",
                "music_volume", "shadows", "shift_lock", "fullscreen",
                "show_fps", "show_ping", "max_fps", "player_names", "bunny_hop"]:
                changed.emit(key, null)
