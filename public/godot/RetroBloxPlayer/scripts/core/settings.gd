extends Node
# Manages user settings, audio buses, graphics presets (Low/Medium/High/Ultra), and window modes.
const SAVE_PATH := "user://retroblox_settings.cfg"

signal changed(key: String, value: Variant)

var mouse_sensitivity := 1.0
var fov := 70.0
var master_volume := 1.0
var sfx_volume := 1.0
var music_volume := 0.7
var voice_volume := 1.0
var voice_enabled := true
var voice_muted := true
var mic_sensitivity := 0.5
var input_device := "Default"
var mobile_controls := 2
var graphics_quality := 2
var shadows := true
var shift_lock := false
var fullscreen := false
var show_fps := true
var show_ping := true
var max_fps := 0
var player_names := true
var bunny_hop := true
var ui_opacity := 1.0
var invert_y := false
var invert_x := false
var invert_movement := false
var vsync := true
var render_scale := 1.0
var chat_bubbles := true
var light_taps := true
var ladder_auto_rotate := true
var ui_editor_enabled := true


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply_audio()
	apply_input_device()
	if fullscreen:
		apply_window()
	apply_max_fps()
	apply_vsync()
	apply_graphics_quality()
	apply_render_scale()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var ke := event as InputEventKey
		if ke.keycode == KEY_F11 or (ke.keycode == KEY_ENTER and ke.alt_pressed):
			set_key("fullscreen", not fullscreen)
			get_viewport().set_input_as_handled()


func _ensure_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.get_bus_index("SFX"), "Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Music"), "Master")
	if AudioServer.get_bus_index("Voice") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Voice")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Voice"), "Master")


func is_nexico() -> bool:
	var sess: Node = get_node_or_null("/root/Session")
	if sess == null:
		return false
	return String(sess.get("username")).to_lower() == "nexico8225"


func is_mobile_ui_active() -> bool:
	if not is_nexico():
		return false
	if mobile_controls == 1:
		return true
	if mobile_controls == 2:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func apply_input_device() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if input_device == "" or input_device == "Default":
		return
	var devs := AudioServer.get_input_device_list()
	if devs.has(input_device):
		AudioServer.input_device = input_device


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Engine.has_method("is_embedded_in_editor") and bool(Engine.call("is_embedded_in_editor")):
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
	voice_volume = clampf(float(cf.get_value("audio", "voice_volume", 1.0)), 0.0, 1.0)
	voice_enabled = bool(cf.get_value("audio", "voice_enabled", true))
	voice_muted = true
	mic_sensitivity = clampf(float(cf.get_value("audio", "mic_sensitivity", 0.5)), 0.0, 1.0)
	input_device = String(cf.get_value("audio", "input_device", "Default"))
	mobile_controls = clampi(int(cf.get_value("input", "mobile_controls", 2)), 0, 2)
	graphics_quality = clampi(int(cf.get_value("graphics", "graphics_quality", 2)), 0, 3)
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
	invert_x = bool(cf.get_value("input", "invert_x", false))
	invert_movement = bool(cf.get_value("input", "invert_movement", false))
	vsync = bool(cf.get_value("graphics", "vsync", true))
	render_scale = clampf(float(cf.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0)
	chat_bubbles = bool(cf.get_value("world", "chat_bubbles", true))
	light_taps = bool(cf.get_value("input", "light_taps", true))
	ladder_auto_rotate = bool(cf.get_value("input", "ladder_auto_rotate", true))
	ui_editor_enabled = bool(cf.get_value("ui", "ui_editor_enabled", true))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("input", "shift_lock", shift_lock)
	cf.set_value("input", "mobile_controls", mobile_controls)
	cf.set_value("input", "light_taps", light_taps)
	cf.set_value("input", "ladder_auto_rotate", ladder_auto_rotate)
	cf.set_value("ui", "ui_editor_enabled", ui_editor_enabled)
	cf.set_value("camera", "fov", fov)
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "voice_volume", voice_volume)
	cf.set_value("audio", "voice_enabled", voice_enabled)
	cf.set_value("audio", "voice_muted", voice_muted)
	cf.set_value("audio", "mic_sensitivity", mic_sensitivity)
	cf.set_value("audio", "input_device", input_device)
	cf.set_value("graphics", "graphics_quality", graphics_quality)
	cf.set_value("graphics", "shadows", shadows)
	cf.set_value("graphics", "fullscreen", fullscreen)
	cf.set_value("graphics", "max_fps", max_fps)
	cf.set_value("hud", "show_fps", show_fps)
	cf.set_value("hud", "show_ping", show_ping)
	cf.set_value("world", "player_names", player_names)
	cf.set_value("input", "bunny_hop", bunny_hop)
	cf.set_value("ui", "ui_opacity", ui_opacity)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("input", "invert_x", invert_x)
	cf.set_value("input", "invert_movement", invert_movement)
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
	var voice := AudioServer.get_bus_index("Voice")
	if voice >= 0:
		AudioServer.set_bus_volume_db(voice, linear_to_db(clampf(voice_volume, 0.0001, 1.0)))
		AudioServer.set_bus_mute(voice, not voice_enabled or voice_volume <= 0.001)


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
		"voice_volume":
			voice_volume = clampf(float(value), 0.0, 1.0)
			apply_audio()
		"voice_enabled":
			voice_enabled = bool(value)
			apply_audio()
		"voice_muted":
			voice_muted = bool(value)
		"mic_sensitivity":
			mic_sensitivity = clampf(float(value), 0.0, 1.0)
		"input_device":
			input_device = String(value)
			apply_input_device()
		"mobile_controls":
			if is_nexico():
				mobile_controls = clampi(int(value), 0, 2)
			else:
				mobile_controls = 2
		"graphics_quality":
			graphics_quality = clampi(int(value), 0, 3)
			apply_graphics_quality()
		"shadows":
			shadows = bool(value)
		"shift_lock":
			shift_lock = bool(value)
		"fullscreen":
			fullscreen = bool(value)
			apply_window()
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
		"invert_x":
			invert_x = bool(value)
		"invert_movement":
			invert_movement = bool(value)
		"vsync":
			vsync = bool(value)
			apply_vsync()
		"render_scale":
			render_scale = clampf(float(value), 0.5, 1.0)
			apply_render_scale()
		"chat_bubbles":
			chat_bubbles = bool(value)
		"light_taps":
			light_taps = bool(value)
		"ladder_auto_rotate":
			ladder_auto_rotate = bool(value)
		"ui_editor_enabled":
			ui_editor_enabled = bool(value)
		_:
			return
	save_settings()
	changed.emit(key, value)


func apply_graphics_quality() -> void:
	# 0 = Low (Extreme Optimization: 60+ FPS, shadows off, FSR 0.65x, distance culling)
	# 1 = Medium (Distance Blur & Fog Pixelation, FSR 0.82x, soft shadows)
	# 2 = High (Native 1.0x, 4x MSAA, full draw distance)
	# 3 = Ultra (Realistic Depth, 8x MSAA)
	match graphics_quality:
		0:
			shadows = false
			render_scale = 0.65
		1:
			shadows = true
			render_scale = 0.82
		2:
			shadows = true
			render_scale = 1.0
		3:
			shadows = true
			render_scale = 1.0

	if DisplayServer.get_name() != "headless":
		var vp := get_viewport()
		if vp != null:
			vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
			if graphics_quality <= 1:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				vp.fsr_sharpness = 0.15
			else:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

			match graphics_quality:
				0:
					vp.msaa_3d = Viewport.MSAA_DISABLED
					vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				1:
					vp.msaa_3d = Viewport.MSAA_2X
					vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
				2:
					vp.msaa_3d = Viewport.MSAA_4X
					vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				3:
					vp.msaa_3d = Viewport.MSAA_8X
					vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	changed.emit("shadows", shadows)
	changed.emit("render_scale", render_scale)
	changed.emit("graphics_preset_applied", graphics_quality)


func apply_max_fps() -> void:
	Engine.max_fps = maxi(max_fps, 0)


func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != mode:
		DisplayServer.window_set_vsync_mode(mode)


func apply_render_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)


func reset_all() -> void:
	mouse_sensitivity = 1.0
	fov = 70.0
	master_volume = 1.0
	sfx_volume = 1.0
	music_volume = 0.7
	voice_volume = 1.0
	voice_enabled = true
	voice_muted = true
	mic_sensitivity = 0.5
	input_device = "Default"
	mobile_controls = 2
	graphics_quality = 2
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
	invert_x = false
	invert_movement = false
	vsync = true
	render_scale = 1.0
	chat_bubbles = true
	light_taps = true
	ladder_auto_rotate = true
	ui_editor_enabled = true
	apply_audio()
	apply_input_device()
	apply_window()
	apply_max_fps()
	apply_vsync()
	apply_graphics_quality()
	apply_render_scale()
	save_settings()
	for key in ["mouse_sensitivity", "fov", "master_volume", "sfx_volume",
		"music_volume", "voice_volume", "voice_enabled", "voice_muted",
		"mic_sensitivity", "input_device", "mobile_controls",
		"graphics_quality", "shadows", "shift_lock",
		"fullscreen", "show_fps", "show_ping", "max_fps", "player_names",
		"bunny_hop", "ui_opacity", "invert_y", "invert_x", "invert_movement",
		"vsync", "render_scale", "chat_bubbles", "light_taps", "ladder_auto_rotate", "ui_editor_enabled"]:
		changed.emit(key, null)
