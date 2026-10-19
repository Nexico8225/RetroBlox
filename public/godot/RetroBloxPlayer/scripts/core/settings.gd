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
var ui_opacity := 1.0             # v1.1: menu + chat opacity (0.3..1.0)
var invert_y := false             # v1.1: flip the camera's vertical look
var vsync := true                 # v1.1: vertical sync on/off
var render_scale := 1.0           # v1.1: 3D render scale (0.5..1.0, the FPS dial)
var chat_bubbles := true          # v1.1: the classic speech bubbles over heads


func _ready() -> void:
        _ensure_buses()
        load_settings()
        apply_audio()
        apply_window()
        apply_max_fps()
        apply_vsync()
        apply_render_scale()
        changed.connect(func(_k: String, _v: Variant) -> void:
                apply_window()
                apply_vsync()
                apply_render_scale())


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
        ui_opacity = clampf(float(cf.get_value("ui", "ui_opacity", 1.0)), 0.3, 1.0)
        invert_y = bool(cf.get_value("input", "invert_y", false))
        vsync = bool(cf.get_value("graphics", "vsync", true))
        render_scale = clampf(float(cf.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0)
        chat_bubbles = bool(cf.get_value("world", "chat_bubbles", true))


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
        cf.set_value("ui", "ui_opacity", ui_opacity)
        cf.set_value("input", "invert_y", invert_y)
        cf.set_value("graphics", "vsync", vsync)
        cf.set_value("graphics", "render_scale", render_scale)
        cf.set_value("world", "chat_bubbles", chat_bubbles)
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
                "ui_opacity":
                        ui_opacity = clampf(float(value), 0.3, 1.0)
                "invert_y":
                        invert_y = bool(value)
                "vsync":
                        vsync = bool(value)
                        apply_vsync()
                "render_scale":
                        render_scale = clampf(float(value), 0.5, 1.0)
                        apply_render_scale()
                "chat_bubbles":
                        chat_bubbles = bool(value)
                _:
                        return
        save_settings()
        changed.emit(key, value)


## v12.0: the FPS ceiling, applied live (0 = unlimited, vsync governs web).
func apply_max_fps() -> void:
        Engine.max_fps = maxi(max_fps, 0)


## v1.1: vertical sync, applied live (headless has no window to sync).
func apply_vsync() -> void:
        if DisplayServer.get_name() == "headless":
                return
        var mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
        if DisplayServer.window_get_vsync_mode() != mode:
                DisplayServer.window_set_vsync_mode(mode)


## v1.1: the 3D render scale, applied live — the honest FPS dial
## (0.5 = half resolution = the fastest, 1.0 = native).
func apply_render_scale() -> void:
        if DisplayServer.get_name() == "headless":
                return
        var vp := get_viewport()
        if vp != null:
                vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)


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
        ui_opacity = 1.0
        invert_y = false
        vsync = true
        render_scale = 1.0
        chat_bubbles = true
        apply_audio()
        apply_window()
        apply_max_fps()
        apply_vsync()
        apply_render_scale()
        save_settings()
        for key in ["mouse_sensitivity", "fov", "master_volume", "sfx_volume",
                "music_volume", "shadows", "shift_lock", "fullscreen",
                "show_fps", "show_ping", "max_fps", "player_names", "bunny_hop",
                "ui_opacity", "invert_y", "vsync", "render_scale", "chat_bubbles"]:
                changed.emit(key, null)
