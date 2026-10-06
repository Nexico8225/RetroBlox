extends Node
## Settings — the player's options, persisted at user://retroblox_settings.cfg
## and applied LIVE: audio bus volumes, camera FOV + sensitivity, sun shadows.
## Autoload "Settings". Every panel reads through here; nothing else stores.

const SAVE_PATH := "user://retroblox_settings.cfg"

signal changed(key: String, value: Variant)

var mouse_sensitivity := 1.0      # multiplier on the base look speed
var fov := 70.0                   # camera field of view
var master_volume := 1.0          # 0..1 -> Master bus
var sfx_volume := 1.0             # 0..1 -> SFX bus
var shadows := true               # sun shadows on/off (potato PCs)
var shift_lock := false           # default shift-lock state per session


func _ready() -> void:
        _ensure_buses()
        load_settings()
        apply_audio()


func _ensure_buses() -> void:
        if AudioServer.get_bus_index("SFX") == -1:
                AudioServer.add_bus()
                AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
                AudioServer.set_bus_send(AudioServer.get_bus_index("SFX"), "Master")


func load_settings() -> void:
        var cf := ConfigFile.new()
        if cf.load(SAVE_PATH) != OK:
                return
        mouse_sensitivity = clampf(float(cf.get_value("input", "mouse_sensitivity", 1.0)), 0.1, 3.0)
        fov = clampf(float(cf.get_value("camera", "fov", 70.0)), 40.0, 110.0)
        master_volume = clampf(float(cf.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
        sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
        shadows = bool(cf.get_value("graphics", "shadows", true))
        shift_lock = bool(cf.get_value("input", "shift_lock", false))


func save_settings() -> void:
        var cf := ConfigFile.new()
        cf.set_value("input", "mouse_sensitivity", mouse_sensitivity)
        cf.set_value("input", "shift_lock", shift_lock)
        cf.set_value("camera", "fov", fov)
        cf.set_value("audio", "master_volume", master_volume)
        cf.set_value("audio", "sfx_volume", sfx_volume)
        cf.set_value("graphics", "shadows", shadows)
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
                "shadows":
                        shadows = bool(value)
                "shift_lock":
                        shift_lock = bool(value)
                _:
                        return
        save_settings()
        changed.emit(key, value)
