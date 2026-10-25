extends Node3D
# Main RetroBlox client session controller managing the 3D world, HUD, UI Studio, voice chat, and multiplayer sync.
const LocalPlayerScript := preload("res://scripts/player/local_player.gd")
const UIStudioScript := preload("res://scripts/ui/ui_studio.gd")
const RemotePlayerScript := preload("res://scripts/player/remote_player.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")
const ChatBoxScript := preload("res://scripts/game/chat_box.gd")
const PlacesScript := preload("res://scripts/world/places.gd")
const WorldBuilderScript := preload("res://scripts/world/world_builder.gd")
const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const AvatarViewerScript := preload("res://scripts/ui/avatar_viewer.gd")
const MenuIcons := preload("res://scripts/ui/menu_icons.gd")

const POLL_SECONDS := 2.0
const HEARTBEAT_SECONDS := 3.5
const RESPAWN_SECONDS := 2.0

var place: Dictionary
var player
var camera_rig
var chat
var hud: CanvasLayer

var _health_container: Control
var _health_fill: Panel
var _health_value: Label
var _health_hide_timer := 0.0
var _names_by_uid: Dictionary = {}
var _health_track_h := 220.0
var _menu: Control
var _menu_panel: PanelContainer
var _players_grid: GridContainer
var _settings_tab: VBoxContainer
var _people_title: Label
var _corner_stats: Label
var _fps_chip: PanelContainer
var _shift_hud_btn: Button
var _tab_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _fps_smooth := 60.0
var _stats_tick := 0.25
var _people_total := 1
var _viewers: Dictionary = {}
var _viewer_dressed: Dictionary = {}
var _viewer_pending: Dictionary = {}
var _remotes: Dictionary = {}
var _seen_messages: Dictionary = {}
var _pending_local_texts: Array[String] = []
var _chat_history_done := false
var _dressed_signature := ""
var _last_presence: Array = []
var _spawns: Array[Vector3] = []
var _respawning := false
var _finished := false
var _poll_left := 0.5
var _beat_left := 1.0
var _menu_open := false
var _chat_badge: Label
var _chat_badge_panel: PanelContainer
var _toast_box: VBoxContainer
var _shift_check: Button
var _fullscreen_switch: Button
var _voice_mute_switch: Button
var _mic_device_btn: Button
var _voice_topbar_btn: Button
var _ui_studio: Control
var _ui_editor_switch: Button
var _edit_ui_btn: Button
var _tex_mic_on: Texture2D
var _tex_mic_muted: Texture2D
var _tex_studio: Texture2D
var _tex_jump: Texture2D
var _center_cursor: TextureRect
var _loading: Control
var _session_start_ms := 0
var _last_ping_ms := 0
var _instance_id := ""
var _joined_at_unix := 0.0
var _dup_check_left := 0.2
var _disconnected := false
var _disconnect_overlay: Control
var _disco_mats: Array[ShaderMaterial] = []
var _disco_timer := 0.0
var _pad_notify_cooldown := 0.0

# Mobile Touch Controls state
var _mobile_root: Control
var _thumbstick_pad: Panel
var _thumbstick_knob: Panel
var _touch_jump_btn: Button
var _mobile_move_vec := Vector2.ZERO
var _mobile_jump_just_pressed := false
var _mobile_jump_held := false
var _joystick_touch_idx := -1
var _joystick_mouse_dragging := false


func _ready() -> void:
	randomize()
	var sess: Node = get_node_or_null("/root/Session")
	place = sess.current_place if sess != null else {}
	if place.is_empty():
		place = PlacesScript.by_id("baseplate")
	_session_start_ms = Time.get_ticks_msec()
	_joined_at_unix = Time.get_unix_time_from_system()
	_instance_id = "%d_%06d" % [int(_joined_at_unix), randi() % 1000000]

	_show_loading()
	await get_tree().process_frame

	# Use the editable 3D World nodes inside scenes/retroblox.tscn if present for baseplate,
	# or build procedurally if switching to another place id.
	var existing_world := get_node_or_null("World") as Node3D
	var existing_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	var existing_sun := get_node_or_null("Sun") as DirectionalLight3D
	var place_id := String(place.get("id", "baseplate"))

	if existing_world != null and existing_world.get_child_count() > 0 and place_id == "baseplate":
		if existing_env != null and existing_env.environment != null:
			WorldBuilderScript.configure_lighting(existing_env.environment, existing_sun, place)
		_spawns = WorldBuilderScript.prepare_scene_world(existing_world)
		var disco_node := existing_world.get_node_or_null("DiscoFloor") as Node3D
		if disco_node != null:
			_disco_mats.clear()
			var tex := WorldBuilderScript.stud_texture()
			var palette: Array[Color] = [
				Color("e03131"), Color("f59f00"), Color("2f9e44"),
				Color("1971c2"), Color("9c36b5"), Color("0ca678"),
			]
			var idx := 0
			for tile in disco_node.get_children():
				if tile is Node3D:
					for tc in tile.get_children():
						if tc is MeshInstance3D:
							var tmi := tc as MeshInstance3D
							var mat := WorldBuilderScript._part_material(palette[idx % palette.size()], "plastic", tex, false)
							tmi.material_override = mat
							if mat is ShaderMaterial:
								_disco_mats.append(mat as ShaderMaterial)
							idx += 1
	else:
		if existing_world != null:
			existing_world.queue_free()
		if existing_env != null:
			existing_env.queue_free()
		if existing_sun != null:
			existing_sun.queue_free()
		var built: Dictionary = WorldBuilderScript.build(place)
		add_child(built["root"])
		_spawns = built["spawns"]

	if _spawns.is_empty():
		_spawns.append(Vector3(0.0, 2.0, 0.0) * WorldBuilderScript.STUD)
	await get_tree().process_frame

	# Bind existing LocalPlayer node from scenes/game.tscn or create one
	player = get_node_or_null("LocalPlayer")
	if player == null:
		player = LocalPlayerScript.new()
		add_child(player)
	player.global_position = _spawns[0]
	player.spawn_point = Transform3D(Basis(), _spawns[0])
	player.setup(Session.username)
	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)
	if not player.health_depleted.is_connected(_on_health_depleted):
		player.health_depleted.connect(_on_health_depleted)
	if not player.touched_group.is_connected(_on_touched_group):
		player.touched_group.connect(_on_touched_group)
	_dress_me()

	_setup_audio()
	RetroUI.apply_cursors()

	# Bind existing CameraRig node from scenes/game.tscn or create one
	camera_rig = get_node_or_null("CameraRig")
	if camera_rig == null:
		camera_rig = CameraRigScript.new()
		add_child(camera_rig)
	camera_rig.setup(player)
	camera_rig.set_ui_blocked(false)
	if not camera_rig.first_person_changed.is_connected(_on_first_person):
		camera_rig.first_person_changed.connect(_on_first_person)

	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		camera_rig.set_shift_locked(bool(settings.get("shift_lock")))
		if not settings.changed.is_connected(_on_setting_changed):
			settings.changed.connect(_on_setting_changed)
	if String(place.get("cam", "")) == "topdown":
		camera_rig.set_mode("topdown")
	_apply_nameplates()

	_setup_hud()
	_sync_shiftlock_ui()
	_sync_mobile_ui()

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_hide_loading()


func _show_loading() -> void:
	_loading = Control.new()
	_loading.name = "LoadingVeil"
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	var layer := CanvasLayer.new()
	layer.name = "LoadingLayer"
	layer.layer = 90
	layer.add_child(_loading)
	add_child(layer)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = RetroUI.BG
	_loading.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_loading.add_child(box)

	var wm_path := "res://assets/ui/wordmark.png"
	if ResourceLoader.exists(wm_path):
		var wm := TextureRect.new()
		wm.texture = load(wm_path)
		wm.custom_minimum_size = Vector2(280, 76)
		wm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(wm)
	else:
		var t := Label.new()
		t.text = "RETROBLOX"
		box.add_child(t)

	var status := Label.new()
	status.name = "Status"
	status.text = "Loading classic place…"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", RetroUI.MENU_MUTED)
	var body: Font = RetroUI.source(400)
	if body != null:
		status.add_theme_font_override("font", body)
		status.add_theme_font_size_override("font_size", 13)
	box.add_child(status)


func _hide_loading() -> void:
	if _loading == null or not is_instance_valid(_loading):
		return
	var veil := _loading
	_loading = null
	var tween := create_tween()
	tween.tween_property(veil, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		var layer := veil.get_parent()
		veil.queue_free()
		if layer != null and is_instance_valid(layer):
			layer.queue_free())


func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"show_fps", "show_ping":
			_update_live_stats()
		"player_names":
			_apply_nameplates()
		"ui_opacity":
			_apply_ui_opacity()
		"fullscreen":
			if _fullscreen_switch != null and is_instance_valid(_fullscreen_switch):
				var settings: Node = get_node_or_null("/root/Settings")
				var on := bool(settings.get("fullscreen")) if settings != null else false
				_fullscreen_switch.set_pressed_no_signal(on)
				_style_switch(_fullscreen_switch, on)
		"voice_muted", "voice_enabled", "input_device":
			_sync_voice_ui()
		"shift_lock":
			_sync_shiftlock_ui()
		"mobile_controls":
			_sync_mobile_ui()
		"light_taps":
			_apply_light_taps()
		"graphics_quality":
			_apply_camera_quality_far()
		_:
			pass


func _apply_ui_opacity() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	var a := 1.0 if settings == null else clampf(float(settings.get("ui_opacity")), 0.3, 1.0)
	if _menu_panel != null and is_instance_valid(_menu_panel):
		_menu_panel.modulate = Color(1, 1, 1, a)
	if chat != null and is_instance_valid(chat):
		chat.modulate = Color(1, 1, 1, a)


func _dress_me() -> void:
	if Session.is_guest:
		return
	var payload := Session.my_avatar_data()
	if payload.is_empty():
		var me: Dictionary = await Api.get_me()
		if me.get("ok", false):
			Session.set_avatar(me)
			payload = Session.my_avatar_data()
	_dressed_signature = JSON.stringify(payload)
	await player.call("dress", Api, payload)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _disconnected:
		return
	var studio_open: bool = _ui_studio != null and is_instance_valid(_ui_studio) and _ui_studio.visible
	var typing: bool = chat != null and is_instance_valid(chat) and chat.is_open
	var block_move: bool = typing or _menu_open or studio_open
	var kb_dir := Vector2.ZERO if block_move else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := kb_dir + (Vector2.ZERO if block_move else _mobile_move_vec)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and bool(settings.get("invert_movement")):
		dir = -dir
	var jump := false if block_move else (Input.is_action_just_pressed("jump") or _mobile_jump_just_pressed)
	var jump_held := false if block_move else (Input.is_action_pressed("jump") or _mobile_jump_held)
	_mobile_jump_just_pressed = false
	player.drive(delta, dir, camera_rig.drive_yaw() if camera_rig != null else 0.0, jump, camera_rig.shift_locked if camera_rig != null else false, camera_rig.first_person if camera_rig != null else false, jump_held)

	if player.alive and player.global_position.y < float(place.get("void_y", -40.0)) * WorldBuilderScript.STUD:
		player.die(self)
		_start_respawn()


func _process(delta: float) -> void:
	if _disconnected:
		return
	if _pad_notify_cooldown > 0.0:
		_pad_notify_cooldown -= delta
	if not _disco_mats.is_empty():
		_disco_timer += delta
		if _disco_timer >= 0.42:
			_disco_timer = 0.0
			var disco_colors: Array[Color] = [
				Color("e03131"), Color("f59f00"), Color("2f9e44"),
				Color("1971c2"), Color("9c36b5"), Color("0ca678"),
			]
			for i in range(_disco_mats.size()):
				var sm := _disco_mats[i]
				if sm != null:
					var c_idx := (i + int(floorf(float(Time.get_ticks_msec()) / 420.0))) % disco_colors.size()
					sm.set_shader_parameter("albedo", disco_colors[c_idx])
	_dup_check_left -= delta
	if _dup_check_left <= 0.0:
		_dup_check_left = 0.8
		if _check_duplicate_account():
			return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL_SECONDS
		_poll_feed()
	var vc_beat: Node = get_node_or_null("/root/VoiceChat")
	var is_sp := false if vc_beat == null else bool(vc_beat.call("is_speaking"))
	_beat_left -= delta
	if _beat_left <= 0.0 or (is_sp and _beat_left > 0.9):
		_beat_left = 0.9 if is_sp else HEARTBEAT_SECONDS
		if not Session.is_guest and player != null and is_instance_valid(player):
			var v_lvl := 0.0 if vc_beat == null else float(vc_beat.call("get_level"))
			var v_b64 := "" if vc_beat == null else String(vc_beat.call("pop_network_voice_packet"))
			Api.place_presence(String(place["id"]), player.global_position, player.heading,
				_last_ping_ms, int(Engine.get_frames_per_second()), is_sp, v_lvl, v_b64)
	_stats_tick -= delta
	if _stats_tick <= 0.0:
		_stats_tick = 0.25
		_update_live_stats()


func _try_click_overhead_voice_bubble(screen_pos: Vector2) -> bool:
	if _menu_open or player == null or not is_instance_valid(player) or not player.alive:
		return false
	var vi: Sprite3D = player.get("voice_indicator")
	if vi == null or not is_instance_valid(vi) or not vi.visible:
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(vi.global_position):
		return false
	var proj := cam.unproject_position(vi.global_position)
	if proj.distance_to(screen_pos) <= 34.0:
		var vc: Node = get_node_or_null("/root/VoiceChat")
		if vc != null:
			vc.call("toggle_mute")
			var muted := bool(vc.call("is_muted"))
			_notify("Microphone Muted" if muted else "Microphone Unmuted — Voice Chat Active", false)
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Click on overhead Voice Chat bubble above player's head to mute/unmute
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if _try_click_overhead_voice_bubble((event as InputEventMouseButton).position):
			get_viewport().set_input_as_handled()
			return

	# Click off chat to unfocus input while keeping the chat log visible
	if chat != null and is_instance_valid(chat) and chat.is_open \
			and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		chat.unfocus()
		get_viewport().set_input_as_handled()
		return

	# ESC menu keyboard shortcuts (L = Leave, R = Respawn)
	if _menu_open and event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (chat == null or not chat.is_open):
		var mkey := (event as InputEventKey).keycode
		if mkey == KEY_L:
			_leave_game()
			get_viewport().set_input_as_handled()
			return
		if mkey == KEY_R:
			_toggle_menu()
			if player.alive:
				player.die(self)
			_start_respawn()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_cancel"):
		if chat != null and chat.is_open:
			chat.unfocus()
		else:
			_toggle_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and ((event as InputEventKey).keycode == KEY_SLASH or (event as InputEventKey).physical_keycode == KEY_SLASH or (event as InputEventKey).unicode == 47):
		if not _menu_open and chat != null and is_instance_valid(chat) and not chat.is_open:
			chat.open()
			camera_rig.set_ui_blocked(true)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).keycode == KEY_V and not _menu_open \
			and (chat == null or not chat.is_open):
		var vc: Node = get_node_or_null("/root/VoiceChat")
		if vc != null:
			vc.call("toggle_mute")
			var muted := bool(vc.call("is_muted"))
			_notify("Microphone Muted" if muted else "Microphone Unmuted — Voice Chat Active", false)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shift_lock"):
		var focus_owner := get_viewport().gui_get_focus_owner()
		var in_text := (focus_owner is LineEdit or focus_owner is TextEdit)
		var chat_busy: bool = (chat != null and is_instance_valid(chat) and (bool(chat.is_open) or (chat.has_method("is_typing") and bool(chat.call("is_typing")))))
		if not _menu_open and not in_text and not chat_busy:
			_toggle_shiftlock()
		get_viewport().set_input_as_handled()


func _toggle_shiftlock() -> void:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return
	if _menu_open:
		return
	if chat != null and is_instance_valid(chat) and (chat.is_open or (chat.has_method("is_typing") and bool(chat.call("is_typing")))):
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	camera_rig.set_shift_locked(not camera_rig.shift_locked)
	var st: Node = get_node_or_null("/root/Settings")
	if st != null:
		st.call("set_key", "shift_lock", camera_rig.shift_locked)
	_sync_shiftlock_ui()


func _sync_shiftlock_ui() -> void:
	var locked: bool = camera_rig != null and is_instance_valid(camera_rig) and camera_rig.shift_locked
	var fp: bool = camera_rig != null and is_instance_valid(camera_rig) and camera_rig.first_person
	if _shift_check != null and is_instance_valid(_shift_check):
		_shift_check.set_pressed_no_signal(locked)
		_style_switch(_shift_check, locked)
	if _shift_hud_btn != null and is_instance_valid(_shift_hud_btn):
		_shift_hud_btn.modulate = Color(0.25, 0.85, 1.0, 1.0) if locked else Color(1, 1, 1, 0.82)
		_shift_hud_btn.tooltip_text = "Shift Lock: ON (Shift)" if locked else "Shift Lock: OFF (Shift)"
	if _center_cursor != null and is_instance_valid(_center_cursor):
		_center_cursor.visible = (locked or fp) and not _menu_open
		if locked:
			_center_cursor.texture = RetroUI.load_png_safe("res://assets/ui/shiftlock.png")
		elif fp:
			_center_cursor.texture = RetroUI.load_png_safe("res://assets/ui/cursor_pointer.png")


func _on_first_person(active: bool) -> void:
	if player != null and is_instance_valid(player):
		player.avatar.visible = not active
		player.bubble.visible = not active
	_sync_shiftlock_ui()


func _setup_hud() -> void:
	hud = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		hud = CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)

	# Bind or create ChatBox
	chat = hud.get_node_or_null("ChatBox")
	if chat == null:
		chat = ChatBoxScript.new()
		chat.name = "ChatBox"
		hud.add_child(chat)
	if not chat.submitted.is_connected(_on_chat_submit):
		chat.submitted.connect(_on_chat_submit)
	chat.opened.connect(func() -> void: camera_rig.set_ui_blocked(true))
	chat.closed.connect(func() -> void:
		if not _menu_open:
			camera_rig.set_ui_blocked(false))

	_tex_mic_on = RetroUI.load_png_safe("res://assets/icons/topbar_mic_on.png")
	_tex_mic_muted = RetroUI.load_png_safe("res://assets/icons/topbar_mic_muted.png")
	_tex_studio = RetroUI.load_png_safe("res://assets/icons/ui_studio.png")
	_tex_jump = RetroUI.load_png_safe("res://assets/icons/jump.png")
	_bind_or_build_topbar()
	_bind_or_build_fps_chip()
	_bind_or_build_health()
	_bind_or_build_mobile_controls()
	_bind_or_build_shiftlock_btn()
	_bind_or_build_center_cursor()
	_setup_ui_studio()

	_toast_box = hud.get_node_or_null("ToastBox") as VBoxContainer
	if _toast_box == null:
		_toast_box = VBoxContainer.new()
		_toast_box.name = "ToastBox"
		_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast_box.offset_top = 14.0
		_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast_box.add_theme_constant_override("separation", 6)
		_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
		hud.add_child(_toast_box)

	_menu = _build_menu()
	_menu.name = "EscMenu"
	_menu.theme = RetroUI.shared
	hud.add_child(_menu)
	_apply_ui_opacity()
	_sync_voice_ui()
	_apply_light_taps()
	_apply_camera_quality_far()
	_update_live_stats()


func _bind_or_build_topbar() -> void:
	var cluster := hud.get_node_or_null("Topbar") as HBoxContainer
	if cluster == null:
		cluster = HBoxContainer.new()
		cluster.name = "Topbar"
		cluster.position = Vector2(12, 12)
		cluster.add_theme_constant_override("separation", 6)
		hud.add_child(cluster)

	_voice_topbar_btn = cluster.get_node_or_null("VoiceMicButton") as Button
	if _voice_topbar_btn == null:
		_voice_topbar_btn = _topbar_key()
		_voice_topbar_btn.name = "VoiceMicButton"
		_voice_topbar_btn.tooltip_text = "Voice Chat (V)"
		cluster.add_child(_voice_topbar_btn)
	else:
		_style_topbar_btn(_voice_topbar_btn)
	_voice_topbar_btn.pressed.connect(func() -> void:
		var vc: Node = get_node_or_null("/root/VoiceChat")
		if vc != null:
			vc.call("toggle_mute")
			var muted := bool(vc.call("is_muted"))
			_notify("Microphone Muted" if muted else "Microphone Unmuted — Voice Chat Active", false))

	var logo_btn := cluster.get_node_or_null("MenuButton") as Button
	if logo_btn == null:
		logo_btn = _topbar_key()
		logo_btn.name = "MenuButton"
		logo_btn.tooltip_text = "Menu (ESC)"
		logo_btn.icon = load("res://assets/icons/logo.png")
		cluster.add_child(logo_btn)
	else:
		_style_topbar_btn(logo_btn)
	logo_btn.pressed.connect(func() -> void: _toggle_menu())

	var chat_btn := cluster.get_node_or_null("ChatButton") as Button
	if chat_btn == null:
		chat_btn = _topbar_key()
		chat_btn.name = "ChatButton"
		chat_btn.tooltip_text = "Chat (/)"
		chat_btn.icon = RetroUI.icon_png("chat", Color.WHITE)
		cluster.add_child(chat_btn)
	else:
		_style_topbar_btn(chat_btn)
		chat_btn.tooltip_text = "Chat (/)"
	chat_btn.pressed.connect(func() -> void:
		chat.toggle_window())

	_chat_badge_panel = chat_btn.get_node_or_null("BadgeHolder/ChatBadgePanel") as PanelContainer
	_chat_badge = chat_btn.get_node_or_null("BadgeHolder/ChatBadgePanel/ChatBadge") as Label
	if _chat_badge_panel != null:
		_chat_badge_panel.add_theme_stylebox_override("panel", _badge_style())
		_chat_badge_panel.visible = false
	chat.unread.connect(func(n: int) -> void:
		if _chat_badge != null:
			_chat_badge.text = "" if n <= 0 else str(n)
		if _chat_badge_panel != null and is_instance_valid(_chat_badge_panel):
			_chat_badge_panel.visible = n > 0)

	var old_studio_btn := cluster.get_node_or_null("UIStudioButton")
	if old_studio_btn != null:
		old_studio_btn.queue_free()

	var vc_node: Node = get_node_or_null("/root/VoiceChat")
	if vc_node != null:
		if not vc_node.is_connected("mute_changed", _on_voice_mute_changed):
			vc_node.connect("mute_changed", _on_voice_mute_changed)
		if not vc_node.is_connected("device_changed", _on_voice_device_changed):
			vc_node.connect("device_changed", _on_voice_device_changed)
		if vc_node.has_signal("remote_voice_packet") and not vc_node.is_connected("remote_voice_packet", _on_remote_voice_packet):
			vc_node.connect("remote_voice_packet", _on_remote_voice_packet)


func _on_remote_voice_packet(uid: String, pcm: PackedVector2Array, level: float) -> void:
	if _remotes.has(uid) and is_instance_valid(_remotes[uid]):
		_remotes[uid].call("push_voice_audio", pcm, level)


func _on_voice_mute_changed(_muted: bool) -> void:
	_sync_voice_ui()


func _on_voice_device_changed(_dev: String) -> void:
	_sync_voice_ui()


func _sync_voice_ui() -> void:
	var vc: Node = get_node_or_null("/root/VoiceChat")
	var muted := false if vc == null else bool(vc.call("is_muted"))
	if _voice_topbar_btn != null and is_instance_valid(_voice_topbar_btn):
		var ic := _tex_mic_muted if muted else _tex_mic_on
		if ic != null:
			_voice_topbar_btn.icon = ic
		_voice_topbar_btn.tooltip_text = "Voice Chat: Muted (V)" if muted else "Voice Chat: Active (V)"
	if _voice_mute_switch != null and is_instance_valid(_voice_mute_switch):
		_voice_mute_switch.set_pressed_no_signal(not muted)
		_style_switch(_voice_mute_switch, not muted)
	if _mic_device_btn != null and is_instance_valid(_mic_device_btn) and vc != null:
		_mic_device_btn.text = String(vc.call("get_input_device"))


func _bind_or_build_mobile_controls() -> void:
	_mobile_root = hud.get_node_or_null("MobileControls") as Control
	if _mobile_root == null:
		_mobile_root = Control.new()
		_mobile_root.name = "MobileControls"
		_mobile_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mobile_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_mobile_root)

	_thumbstick_pad = _mobile_root.get_node_or_null("ThumbstickPad") as Panel
	if _thumbstick_pad == null:
		_thumbstick_pad = Panel.new()
		_thumbstick_pad.name = "ThumbstickPad"
		_thumbstick_pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_thumbstick_pad.offset_left = 28.0
		_thumbstick_pad.offset_top = -168.0
		_thumbstick_pad.offset_right = 168.0
		_thumbstick_pad.offset_bottom = -28.0
		_mobile_root.add_child(_thumbstick_pad)

	var pad_sb := StyleBoxFlat.new()
	pad_sb.bg_color = Color(0.06, 0.08, 0.11, 0.48)
	pad_sb.set_corner_radius_all(70)
	pad_sb.set_border_width_all(2)
	pad_sb.border_color = Color(1, 1, 1, 0.28)
	_thumbstick_pad.add_theme_stylebox_override("panel", pad_sb)

	_thumbstick_knob = _thumbstick_pad.get_node_or_null("ThumbstickKnob") as Panel
	if _thumbstick_knob == null:
		_thumbstick_knob = Panel.new()
		_thumbstick_knob.name = "ThumbstickKnob"
		_thumbstick_knob.set_anchors_preset(Control.PRESET_CENTER)
		_thumbstick_knob.offset_left = -28.0
		_thumbstick_knob.offset_top = -28.0
		_thumbstick_knob.offset_right = 28.0
		_thumbstick_knob.offset_bottom = 28.0
		_thumbstick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_thumbstick_pad.add_child(_thumbstick_knob)

	var knob_sb := StyleBoxFlat.new()
	knob_sb.bg_color = Color(0.95, 0.97, 1.0, 0.78)
	knob_sb.set_corner_radius_all(28)
	knob_sb.set_border_width_all(2)
	knob_sb.border_color = Color(0.1, 0.12, 0.15, 0.5)
	_thumbstick_knob.add_theme_stylebox_override("panel", knob_sb)

	_thumbstick_pad.modulate.a = 0.0
	_thumbstick_pad.gui_input.connect(_on_thumbstick_gui_input)

	_touch_jump_btn = _mobile_root.get_node_or_null("TouchJumpButton") as Button
	if _touch_jump_btn == null:
		_touch_jump_btn = Button.new()
		_touch_jump_btn.name = "TouchJumpButton"
		_touch_jump_btn.focus_mode = Control.FOCUS_NONE
		_touch_jump_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_touch_jump_btn.offset_left = -148.0
		_touch_jump_btn.offset_top = -136.0
		_touch_jump_btn.offset_right = -64.0
		_touch_jump_btn.offset_bottom = -52.0
		_mobile_root.add_child(_touch_jump_btn)
	_touch_jump_btn.text = ""
	_touch_jump_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_touch_jump_btn.expand_icon = true
	if _tex_jump != null:
		_touch_jump_btn.icon = _tex_jump

	var jump_normal := StyleBoxFlat.new()
	jump_normal.bg_color = Color(0.08, 0.10, 0.14, 0.65)
	jump_normal.set_corner_radius_all(42)
	jump_normal.set_border_width_all(2)
	jump_normal.border_color = Color(1, 1, 1, 0.42)
	jump_normal.content_margin_left = 14.0
	jump_normal.content_margin_right = 14.0
	jump_normal.content_margin_top = 14.0
	jump_normal.content_margin_bottom = 14.0
	var jump_pressed := jump_normal.duplicate() as StyleBoxFlat
	jump_pressed.bg_color = Color(0.22, 0.65, 1.0, 0.82)
	_touch_jump_btn.add_theme_stylebox_override("normal", jump_normal)
	_touch_jump_btn.add_theme_stylebox_override("hover", jump_normal)
	_touch_jump_btn.add_theme_stylebox_override("pressed", jump_pressed)
	_touch_jump_btn.add_theme_color_override("font_color", Color.WHITE)
	_touch_jump_btn.button_down.connect(func() -> void:
		_mobile_jump_just_pressed = true
		_mobile_jump_held = true)
	_touch_jump_btn.button_up.connect(func() -> void:
		_mobile_jump_held = false)


func _on_thumbstick_gui_input(event: InputEvent) -> void:
	var pad_size := _thumbstick_pad.size
	var center := pad_size * 0.5
	var max_r := maxf(minf(pad_size.x, pad_size.y) * 0.5 - 18.0, 24.0)
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_joystick_touch_idx = st.index
			_update_thumbstick_pos(st.position - center, max_r)
		elif st.index == _joystick_touch_idx:
			_joystick_touch_idx = -1
			_reset_thumbstick()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joystick_touch_idx:
			_update_thumbstick_pos(sd.position - center, max_r)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_joystick_mouse_dragging = true
				_update_thumbstick_pos(mb.position - center, max_r)
			else:
				_joystick_mouse_dragging = false
				_reset_thumbstick()
	elif event is InputEventMouseMotion and _joystick_mouse_dragging:
		var mm := event as InputEventMouseMotion
		_update_thumbstick_pos(mm.position - center, max_r)


func _update_thumbstick_pos(delta_vec: Vector2, max_r: float) -> void:
	if _thumbstick_pad != null and is_instance_valid(_thumbstick_pad):
		var target_a := 1.0
		if _ui_studio != null and _ui_studio.has_method("get_element_alpha"):
			target_a = float(_ui_studio.call("get_element_alpha", "Joystick"))
		_thumbstick_pad.modulate.a = target_a
	var clamped := delta_vec.limit_length(max_r)
	if _thumbstick_knob != null and is_instance_valid(_thumbstick_knob):
		_thumbstick_knob.offset_left = -28.0 + clamped.x
		_thumbstick_knob.offset_top = -28.0 + clamped.y
		_thumbstick_knob.offset_right = 28.0 + clamped.x
		_thumbstick_knob.offset_bottom = 28.0 + clamped.y
	_mobile_move_vec = (clamped / max_r) if clamped.length() > 4.0 else Vector2.ZERO


func _reset_thumbstick() -> void:
	_mobile_move_vec = Vector2.ZERO
	if _thumbstick_pad != null and is_instance_valid(_thumbstick_pad):
		var studio_open := _ui_studio != null and _ui_studio.visible
		_thumbstick_pad.modulate.a = 0.85 if studio_open else 0.0
	if _thumbstick_knob != null and is_instance_valid(_thumbstick_knob):
		_thumbstick_knob.offset_left = -28.0
		_thumbstick_knob.offset_top = -28.0
		_thumbstick_knob.offset_right = 28.0
		_thumbstick_knob.offset_bottom = 28.0


func _setup_ui_studio() -> void:
	if hud == null:
		return
	_ui_studio = UIStudioScript.new()
	hud.add_child(_ui_studio)
	var topbar_node := hud.get_node_or_null("Topbar")
	_ui_studio.call("setup", hud, {
		"Topbar": topbar_node,
		"MenuButton": topbar_node.get_node_or_null("MenuButton") if topbar_node != null else null,
		"ChatButton": topbar_node.get_node_or_null("ChatButton") if topbar_node != null else null,
		"VoiceMicButton": _voice_topbar_btn,
		"ChatBox": chat,
		"FpsChip": _fps_chip,
		"HealthBar": _health_container,
		"ShiftLock": _shift_hud_btn,
		"Joystick": _thumbstick_pad,
		"JumpButton": _touch_jump_btn,
	})
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		_ui_studio.call("set_layout_enabled", bool(settings.get("ui_editor_enabled")))
	_ui_studio.connect("studio_closed", func(reopen_esc: bool) -> void:
		if reopen_esc:
			_open_menu("settings")
		elif camera_rig != null and is_instance_valid(camera_rig):
			camera_rig.set_ui_blocked(_menu_open))


func _open_ui_editor_from_settings() -> void:
	if _ui_studio == null or not is_instance_valid(_ui_studio):
		return
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and not bool(settings.get("ui_editor_enabled")):
		settings.set_key("ui_editor_enabled", true)
		_ui_studio.call("set_layout_enabled", true)
		if _ui_editor_switch != null and is_instance_valid(_ui_editor_switch):
			_ui_editor_switch.set_pressed_no_signal(true)
			_style_switch(_ui_editor_switch, true)
	if _menu_open:
		_toggle_menu()
	_ui_studio.call("open_studio", true)
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.set_ui_blocked(true)


func _apply_light_taps() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	var on := true if settings == null else bool(settings.get("light_taps"))
	var mode := BaseButton.ACTION_MODE_BUTTON_PRESS if on else BaseButton.ACTION_MODE_BUTTON_RELEASE
	if hud != null:
		for node in hud.find_children("*", "BaseButton", true, false):
			var btn := node as BaseButton
			if btn != null:
				btn.action_mode = mode


func _apply_camera_quality_far() -> void:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return
	var cam := camera_rig.get_node_or_null("Pivot/SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		return
	var settings: Node = get_node_or_null("/root/Settings")
	var q := 2 if settings == null else int(settings.get("graphics_quality"))
	match q:
		0: cam.far = 350.0
		1: cam.far = 750.0
		2: cam.far = 1400.0
		3: cam.far = 2200.0


func _sync_mobile_ui() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	var show_mobile := false if settings == null else bool(settings.call("is_mobile_ui_active"))
	if _mobile_root != null and is_instance_valid(_mobile_root):
		_mobile_root.visible = show_mobile
	if not show_mobile:
		_reset_thumbstick()
		_mobile_jump_held = false


func _bind_or_build_fps_chip() -> void:
	_fps_chip = hud.get_node_or_null("FpsChip") as PanelContainer
	if _fps_chip == null:
		_fps_chip = PanelContainer.new()
		_fps_chip.name = "FpsChip"
		_fps_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_fps_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_fps_chip.offset_right = -12.0
		_fps_chip.offset_top = 12.0
		hud.add_child(_fps_chip)
	_fps_chip.add_theme_stylebox_override("panel", _retro_hud_style())
	_corner_stats = _fps_chip.get_node_or_null("CornerStats") as Label
	if _corner_stats == null:
		_corner_stats = Label.new()
		_corner_stats.name = "CornerStats"
		_fps_chip.add_child(_corner_stats)
	_title(_corner_stats, 12, Color.WHITE, 700)
	_names_by_uid[Session.user_id] = Session.username


func _bind_or_build_shiftlock_btn() -> void:
	_shift_hud_btn = hud.get_node_or_null("ShiftLockButton") as Button
	if _shift_hud_btn == null:
		_shift_hud_btn = Button.new()
		_shift_hud_btn.name = "ShiftLockButton"
		_shift_hud_btn.custom_minimum_size = Vector2(40, 40)
		_shift_hud_btn.focus_mode = Control.FOCUS_NONE
		_shift_hud_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_shift_hud_btn.offset_left = -52.0
		_shift_hud_btn.offset_top = -52.0
		_shift_hud_btn.offset_right = -12.0
		_shift_hud_btn.offset_bottom = -12.0
		_shift_hud_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_shift_hud_btn.expand_icon = true
		hud.add_child(_shift_hud_btn)
	_shift_hud_btn.icon = RetroUI.load_png_safe("res://assets/ui/shiftlock.png")
	_style_topbar_btn(_shift_hud_btn)
	_shift_hud_btn.pressed.connect(_toggle_shiftlock)


func _topbar_key() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(42, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	_style_topbar_btn(b)
	return b


func _style_topbar_btn(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _dark_key_style(false))
	b.add_theme_stylebox_override("hover", _dark_key_style(true))
	b.add_theme_stylebox_override("pressed", _dark_key_style(true))


func _dark_key_style(hover: bool) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.125, 0.16, 0.92) if hover else Color(0.045, 0.058, 0.078, 0.86)
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.26) if hover else Color(1, 1, 1, 0.14)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func _retro_hud_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.058, 0.078, 0.86)
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func _badge_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = RetroUI.MENU_RED
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	sb.content_margin_left = 5.0
	sb.content_margin_right = 5.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	return sb


func _bind_or_build_health() -> void:
	_health_container = hud.get_node_or_null("HealthBarContainer") as Control
	if _health_container == null:
		_health_container = Control.new()
		_health_container.name = "HealthBarContainer"
		hud.add_child(_health_container)
	_health_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_health_container.offset_left = -216.0
	_health_container.offset_right = -14.0
	_health_container.offset_top = 12.0
	_health_container.offset_bottom = 38.0
	_health_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_container.visible = true

	var old_chip := _health_container.get_node_or_null("HealthChip")
	if old_chip != null:
		old_chip.queue_free()

	var track := _health_container.get_node_or_null("HealthBar") as Panel
	if track == null:
		track = Panel.new()
		track.name = "HealthBar"
		_health_container.add_child(track)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.offset_left = 0.0
	track.offset_right = 0.0
	track.offset_top = 0.0
	track.offset_bottom = 0.0
	track.add_theme_stylebox_override("panel", _health_track_style())

	_health_fill = track.get_node_or_null("Fill") as Panel
	if _health_fill == null:
		_health_fill = Panel.new()
		_health_fill.name = "Fill"
		track.add_child(_health_fill)
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_fill.anchor_left = 0.0
	_health_fill.anchor_top = 0.0
	_health_fill.anchor_bottom = 1.0
	_health_fill.anchor_right = 1.0
	_health_fill.offset_left = 3.0
	_health_fill.offset_top = 3.0
	_health_fill.offset_bottom = -3.0
	_health_fill.offset_right = -3.0
	_health_fill.add_theme_stylebox_override("panel", _health_fill_style(1.0))

	_health_value = track.get_node_or_null("HealthValue") as Label
	if _health_value == null:
		_health_value = Label.new()
		_health_value.name = "HealthValue"
		track.add_child(_health_value)
	_health_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_value.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_value.offset_left = 0.0
	_health_value.offset_top = 0.0
	_health_value.offset_right = 0.0
	_health_value.offset_bottom = 0.0
	_health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_value.text = "HP: 100 / 100"
	_title(_health_value, 12, Color.WHITE, 700)
	_health_value.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_health_value.add_theme_constant_override("shadow_offset_x", 1)
	_health_value.add_theme_constant_override("shadow_offset_y", 1)


func _health_track_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.16, 0.82)
	sb.set_corner_radius_all(6)
	sb.anti_aliasing = true
	sb.set_border_width_all(2)
	sb.border_color = Color(0.28, 0.38, 0.48, 0.95)
	sb.content_margin_left = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	return sb


func _health_fill_style(ratio: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("ef4444").lerp(Color("22c55e"), ratio)
	sb.set_corner_radius_all(4)
	sb.anti_aliasing = true
	return sb


func _bind_or_build_center_cursor() -> void:
	_center_cursor = hud.get_node_or_null("CenterCursor") as TextureRect
	if _center_cursor == null:
		_center_cursor = TextureRect.new()
		_center_cursor.name = "CenterCursor"
		hud.add_child(_center_cursor)
	_center_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_center_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_center_cursor.custom_minimum_size = Vector2(38, 38)
	_center_cursor.size = Vector2(38, 38)
	_center_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_cursor.set_anchors_preset(Control.PRESET_CENTER)
	_center_cursor.offset_left = -19.0
	_center_cursor.offset_right = 19.0
	_center_cursor.offset_top = -19.0
	_center_cursor.offset_bottom = 19.0
	_center_cursor.visible = false


func _notify(text: String, with_sound := false) -> void:
	if _toast_box == null or not is_instance_valid(_toast_box):
		return
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _toast_style())
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color.WHITE)
	if RetroUI.source(400) != null:
		l.add_theme_font_override("font", RetroUI.source(400))
	pill.add_child(l)
	_toast_box.add_child(pill)
	if with_sound:
		var sfx: Node = get_node_or_null("/root/Sfx")
		if sfx != null:
			sfx.call("play_join")
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(pill, "modulate:a", 0.0, 0.45)
	tween.tween_callback(pill.queue_free)


func _toast_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.035, 0.055, 0.78)
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _setup_audio() -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx == null:
		return
	if bool(place.get("wind", false)):
		var wind = sfx.call("make_screen_loop", "Wind")
		if wind != null:
			add_child(wind)
			wind.call("play")


func _build_menu() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = RetroUI.NIGHT_VEIL
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size = _menu_panel_size()
	panel.add_theme_stylebox_override("panel", _menu_panel_style())
	center.add_child(panel)
	_menu_panel = panel

	var root := HBoxContainer.new()
	root.name = "MenuRoot"
	panel.add_child(root)

	var rail := VBoxContainer.new()
	rail.name = "Tabs"
	rail.custom_minimum_size = Vector2(78, 0)
	rail.add_theme_constant_override("separation", 6)
	root.add_child(rail)
	var tab_defs := [
		["players", "People", "person"],
		["settings", "Settings", "gear"],
	]
	for td in tab_defs:
		var b := _tab_button(String(td[1]), String(td[2]))
		_tab_buttons[String(td[0])] = b
		rail.add_child(b)

	var rule := ColorRect.new()
	rule.name = "TabRule"
	rule.color = RetroUI.MENU_EDGE
	rule.custom_minimum_size = Vector2(1, 0)
	rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(rule)

	var right := VBoxContainer.new()
	right.name = "MenuRight"
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var body := MarginContainer.new()
	body.name = "MenuBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 24)
	body.add_theme_constant_override("margin_right", 24)
	body.add_theme_constant_override("margin_top", 18)
	body.add_theme_constant_override("margin_bottom", 16)
	right.add_child(body)
	var pages := Control.new()
	pages.name = "Pages"
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pages)

	var players_page := VBoxContainer.new()
	players_page.name = "PeoplePage"
	players_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	players_page.add_theme_constant_override("separation", 10)
	pages.add_child(players_page)
	_pages["players"] = players_page

	var p_head := HBoxContainer.new()
	p_head.add_theme_constant_override("separation", 8)
	players_page.add_child(p_head)
	_people_title = Label.new()
	_people_title.text = "Players"
	_title(_people_title, 18, RetroUI.NIGHT_INK)
	p_head.add_child(_people_title)
	p_head.add_child(_spacer())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	players_page.add_child(scroll)
	_players_grid = GridContainer.new()
	_players_grid.name = "PeopleGrid"
	_players_grid.columns = 3
	_players_grid.add_theme_constant_override("h_separation", 12)
	_players_grid.add_theme_constant_override("v_separation", 12)
	_players_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players_grid)

	_settings_tab = _build_settings_tab()
	_settings_tab.name = "SettingsPage"
	_settings_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_tab.visible = false
	pages.add_child(_settings_tab)
	_pages["settings"] = _settings_tab

	var set_tab := func(tab: String) -> void:
		for key in _pages.keys():
			var page: Control = _pages[key]
			if is_instance_valid(page):
				page.visible = key == tab
		for key in _tab_buttons.keys():
			_style_tab(_tab_buttons[key], key == tab)
		_update_people_title()
	for td in tab_defs:
		var tab_id := String(td[0])
		_tab_buttons[tab_id].pressed.connect(func() -> void: set_tab.call(tab_id))
	_menu_switch = set_tab

	right.add_child(_menu_footer())
	set_tab.call("players")
	return overlay


func _menu_panel_size() -> Vector2:
	var vp := Vector2(1280.0, 720.0)
	var viewport := get_viewport()
	if viewport != null:
		vp = viewport.get_visible_rect().size
	return Vector2(minf(vp.x * 0.84, 980.0), minf(vp.y * 0.86, 680.0))


func _menu_panel_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = RetroUI.NIGHT_PANEL
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 24
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	return sb


func _tab_button(label: String, icon_kind: String) -> Button:
	var b := Button.new()
	b.tooltip_text = label
	b.custom_minimum_size = Vector2(74, 60)
	b.focus_mode = Control.FOCUS_NONE
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var icon := MenuIcons.new()
	icon.name = "Glyph"
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	var l := Label.new()
	l.name = "TabLabel"
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	_style_tab(b, false)
	return b


func _style_tab(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(12)
	sb.bg_color = Color(0.84, 0.92, 1.0, 0.24) if on else Color(1, 1, 1, 0.03)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.75, 0.89, 1.0, 0.55) if on else Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("normal", sb)
	var hb := sb.duplicate() as StyleBoxFlat
	hb.bg_color = Color(0.84, 0.92, 1.0, 0.30) if on else Color(1, 1, 1, 0.10)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover_pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Color.WHITE if on else Color(0.68, 0.72, 0.78)
	var glyph: Control = b.get_node_or_null("VBoxContainer/Glyph")
	if glyph == null:
		glyph = b.find_child("Glyph", true, false) as Control
	if glyph != null and is_instance_valid(glyph):
		glyph.set("ink", ink)
		glyph.queue_redraw()
	var l: Label = b.find_child("TabLabel", true, false) as Label
	if l != null and is_instance_valid(l):
		_title(l, 12, ink, 700)


func _title(l: Label, size: int, color: Color, weight := 700) -> void:
	var f: Font = RetroUI.gotham(weight)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _text(l: Label, size: int, color: Color) -> void:
	var f: Font = RetroUI.gotham(400)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _menu_footer() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var actions := HBoxContainer.new()
	actions.name = "ActionRow"
	actions.add_theme_constant_override("separation", 10)
	col.add_child(actions)
	actions.add_child(_footer_key("L", "Leave Game (L)", false, func() -> void: _leave_game()))
	actions.add_child(_footer_key("R", "Reset Character (R)", false,
		func() -> void:
			_toggle_menu()
			if player.alive:
				player.die(self)
			_start_respawn()))
	actions.add_child(_footer_key("ESC", "Resume Game (ESC)", true, func() -> void: _toggle_menu()))
	return col


func _footer_key(key: String, _label: String, _primary: bool, handler: Callable) -> Button:
	var b := Button.new()
	b.text = _label
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_NONE
	var face := _flat_key_face(key, false)
	var face_hover := _flat_key_face(key, true)
	b.add_theme_stylebox_override("normal", face)
	b.add_theme_stylebox_override("hover", face_hover)
	b.add_theme_stylebox_override("pressed", face)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Color("0a0d12") if key == "ESC" else Color.WHITE
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, ink)
	if RetroUI.gotham(700) != null:
		b.add_theme_font_override("font", RetroUI.gotham(700))
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(handler)
	return b


func _flat_key_face(key: String, hover: bool) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(1)
	match key:
		"L":
			sb.bg_color = Color("ef4444") if hover else Color("dc2626")
			sb.border_color = Color(1.0, 0.72, 0.72, 0.45)
		"ESC":
			sb.bg_color = Color("ffffff") if hover else Color("f3f4f6")
			sb.border_color = Color(1, 1, 1, 0.9)
		_:
			sb.bg_color = Color(1, 1, 1, 0.15) if hover else Color(1, 1, 1, 0.08)
			sb.border_color = Color(1, 1, 1, 0.28) if hover else Color(1, 1, 1, 0.16)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _player_card(uid: String, uname: String, is_me: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Card_" + uid
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_casing(is_me))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	card.add_child(box)

	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", _well_texture_style())
	well.custom_minimum_size = Vector2(0, 150)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.clip_contents = true
	box.add_child(well)
	_attach_viewer(well, uid)

	var name_l := Label.new()
	name_l.text = uname
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title(name_l, 14, RetroUI.NIGHT_INK, 700)
	box.add_child(name_l)
	return card


func _card_casing(is_me: bool) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.84, 0.92, 1.0, 0.55) if is_me else Color(1, 1, 1, 0.12)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 10.0
	return sb


func _well_texture_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.85)
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


func _attach_viewer(well: PanelContainer, uid: String) -> void:
	var viewer = null
	if _viewers.has(uid) and is_instance_valid(_viewers[uid]):
		viewer = _viewers[uid]
		var old = viewer.get_parent()
		if old != null and is_instance_valid(old):
			old.remove_child(viewer)
	else:
		viewer = AvatarViewerScript.new()
		_viewers[uid] = viewer
	well.add_child(viewer)
	if not _viewer_dressed.get(uid, false) and not _viewer_pending.has(uid):
		_viewer_payload_job(uid)


func _viewer_payload_job(uid: String) -> void:
	_viewer_pending[uid] = true
	var payload: Dictionary = {}
	if uid == Session.user_id:
		payload = Session.my_avatar_data()
		if payload.is_empty() and not Session.is_guest:
			var me: Dictionary = await Api.get_me()
			if me.get("ok", false):
				Session.set_avatar(me)
				payload = Session.my_avatar_data()
	else:
		payload = Session.cached_avatar(uid)
		if payload.is_empty():
			var res: Dictionary = await Api.avatar_of(uid)
			if res.get("ok", false):
				var raw: Variant = res.get("avatar", null)
				if raw is Dictionary:
					Session.cache_avatar(uid, raw)
					payload = raw
	_viewer_pending.erase(uid)
	if payload.is_empty():
		return
	if _viewers.has(uid) and is_instance_valid(_viewers[uid]):
		await _viewers[uid].dress(Api, payload)
		_viewer_dressed[uid] = true


func _update_live_stats() -> void:
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		_fps_smooth = lerpf(_fps_smooth, float(fps), 0.35)
	if _corner_stats != null and is_instance_valid(_corner_stats):
		var settings: Node = get_node_or_null("/root/Settings")
		var want_fps := true if settings == null else bool(settings.get("show_fps"))
		var want_ping := true if settings == null else bool(settings.get("show_ping"))
		var parts: PackedStringArray = []
		if want_fps:
			parts.append("FPS %d" % int(roundf(_fps_smooth)))
		if want_ping and _last_ping_ms > 0:
			parts.append("%dms" % _last_ping_ms)
		if _fps_chip != null and is_instance_valid(_fps_chip):
			_fps_chip.visible = not parts.is_empty()
		_corner_stats.text = "  ·  ".join(parts) if not parts.is_empty() else ""


func _update_people_title() -> void:
	if _people_title == null or not is_instance_valid(_people_title):
		return
	_people_title.text = "Players — %d" % _people_total


func _release_account_lock() -> void:
	var acct := Session.username.strip_edges().to_lower()
	if acct == "" or Session.is_guest:
		return
	var lock_path := "user://active_account_lock.cfg"
	var cf := ConfigFile.new()
	if cf.load(lock_path) == OK:
		if String(cf.get_value(acct, "instance_id", "")) == _instance_id:
			cf.erase_section(acct)
			cf.save(lock_path)


func _check_duplicate_account() -> bool:
	if _disconnected or Session.is_guest:
		return _disconnected
	var acct := Session.username.strip_edges().to_lower()
	if acct == "":
		return false
	var lock_path := "user://active_account_lock.cfg"
	var now := Time.get_unix_time_from_system()
	var my_pid := OS.get_process_id()
	var cf := ConfigFile.new()
	if cf.load(lock_path) == OK and cf.has_section(acct):
		var other_id := String(cf.get_value(acct, "instance_id", ""))
		var other_pid := int(cf.get_value(acct, "pid", 0))
		var other_joined := float(cf.get_value(acct, "joined_at", now))
		var other_seen := float(cf.get_value(acct, "last_seen", 0.0))
		var other_alive := other_pid > 0 and other_pid != my_pid and OS.is_process_running(other_pid)
		if other_alive and other_id != "" and other_id != _instance_id and (now - other_seen) < 3.5:
			if other_joined <= _joined_at_unix:
				_disconnect_duplicate_account()
				return true
	cf.set_value(acct, "instance_id", _instance_id)
	cf.set_value(acct, "pid", my_pid)
	cf.set_value(acct, "joined_at", _joined_at_unix)
	cf.set_value(acct, "last_seen", now)
	cf.save(lock_path)
	return false


func _disconnect_duplicate_account() -> void:
	if _disconnected:
		return
	_disconnected = true
	if _menu_open:
		_toggle_menu()
	if _ui_studio != null and is_instance_valid(_ui_studio) and _ui_studio.visible:
		_ui_studio.call("close_studio")
	if chat != null and is_instance_valid(chat) and chat.is_open:
		chat.unfocus()
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.set_ui_blocked(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_disconnect_overlay = Control.new()
	_disconnect_overlay.name = "DisconnectedOverlay"
	_disconnect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disconnect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(_disconnect_overlay)

	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.0, 0.0, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disconnect_overlay.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disconnect_overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 230)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.14, 0.15, 0.17, 0.98)
	card_sb.border_color = Color(1, 1, 1, 0.18)
	card_sb.set_border_width_all(1)
	card_sb.set_corner_radius_all(12)
	card_sb.shadow_color = Color(0, 0, 0, 0.55)
	card_sb.shadow_size = 24
	card_sb.content_margin_left = 28.0
	card_sb.content_margin_right = 28.0
	card_sb.content_margin_top = 24.0
	card_sb.content_margin_bottom = 24.0
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "Disconnected"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title(title, 22, Color.WHITE, 700)
	vbox.add_child(title)

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.15)
	rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(rule)

	var msg := Label.new()
	msg.text = "Same account launched game from another window or device.\nOnly one instance of '%s' can play at a time.\n(Error Code: 273)" % Session.username
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text(msg, 14, Color(0.85, 0.87, 0.90))
	vbox.add_child(msg)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var logout_btn := Button.new()
	logout_btn.text = "Log Out"
	logout_btn.custom_minimum_size = Vector2(160, 38)
	logout_btn.focus_mode = Control.FOCUS_NONE
	logout_btn.add_theme_stylebox_override("normal", _hairline_btn_face(false))
	logout_btn.add_theme_stylebox_override("hover", _hairline_btn_face(true))
	logout_btn.add_theme_stylebox_override("pressed", _hairline_btn_face(false))
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		logout_btn.add_theme_color_override(st, Color.WHITE)
	if RetroUI.gotham(600) != null:
		logout_btn.add_theme_font_override("font", RetroUI.gotham(600))
	logout_btn.add_theme_font_size_override("font_size", 14)
	logout_btn.pressed.connect(_log_out)
	btn_row.add_child(logout_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Game"
	leave_btn.custom_minimum_size = Vector2(160, 38)
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.add_theme_stylebox_override("normal", _white_btn_face(false))
	leave_btn.add_theme_stylebox_override("hover", _white_btn_face(true))
	leave_btn.add_theme_stylebox_override("pressed", _white_btn_face(false))
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		leave_btn.add_theme_color_override(st, Color(0.08, 0.09, 0.11))
	if RetroUI.gotham(700) != null:
		leave_btn.add_theme_font_override("font", RetroUI.gotham(700))
	leave_btn.add_theme_font_size_override("font_size", 14)
	leave_btn.pressed.connect(_leave_game)
	btn_row.add_child(leave_btn)


func _exit_tree() -> void:
	_release_account_lock()


func _leave_game() -> void:
	_release_account_lock()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if OS.has_feature("web"):
		get_tree().change_scene_to_file("res://scenes/login.tscn")
	else:
		get_tree().quit()


var _menu_switch: Callable = func(_t: String) -> void: pass


func _open_menu(tab: String) -> void:
	if not _menu_open:
		_toggle_menu()
	if _menu_open:
		_menu_switch.call(tab)


func _build_settings_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.add_theme_constant_override("separation", 6)
	var settings: Node = get_node_or_null("/root/Settings")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	tab.add_child(scroll)

	_section(page, "mouse", "CONTROLS & MOBILE")
	_slider_row(page, "mouse", "Mouse / Touch Sensitivity", 0.1, 3.0,
		float(settings.get("mouse_sensitivity")) if settings != null else 1.0,
		func(v: float) -> String: return "%.2fx" % v,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("mouse_sensitivity", v))
	_row_toggle(page, "invert", "Invert Camera Y (Vertical)",
		bool(settings.get("invert_y")) if settings != null else false,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("invert_y", on))
	_row_toggle(page, "invert", "Invert Camera X (Horizontal)",
		bool(settings.get("invert_x")) if settings != null else false,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("invert_x", on))
	_row_toggle(page, "invert", "Invert Movement Controls (WASD)",
		bool(settings.get("invert_movement")) if settings != null else false,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("invert_movement", on))
	_shift_check = _row_toggle(page, "lock", "Shift Lock Switch (Shift)",
		bool(settings.get("shift_lock")) if settings != null else false,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("shift_lock", on)
			camera_rig.set_shift_locked(on)
			_sync_shiftlock_ui())
	_row_toggle(page, "mouse", "Light Taps (Instant Button Response)",
		bool(settings.get("light_taps")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("light_taps", on))
	_row_toggle(page, "sliders", "Auto-Face Ladder on Approach",
		bool(settings.get("ladder_auto_rotate")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("ladder_auto_rotate", on))

	var studio_row := _row(page, "layers", "UI Editor & Custom HUD Layout")
	var ui_ed_on := bool(settings.get("ui_editor_enabled")) if settings != null else true
	_ui_editor_switch = Button.new()
	_ui_editor_switch.toggle_mode = true
	_ui_editor_switch.button_pressed = ui_ed_on
	_ui_editor_switch.custom_minimum_size = Vector2(68, 32)
	_ui_editor_switch.focus_mode = Control.FOCUS_NONE
	_style_switch(_ui_editor_switch, ui_ed_on)
	_ui_editor_switch.toggled.connect(func(on: bool) -> void:
		_style_switch(_ui_editor_switch, on)
		if settings != null:
			settings.set_key("ui_editor_enabled", on)
		if _ui_studio != null and is_instance_valid(_ui_studio):
			_ui_studio.call("set_layout_enabled", on)
		if _edit_ui_btn != null and is_instance_valid(_edit_ui_btn):
			_edit_ui_btn.disabled = not on
			_edit_ui_btn.modulate.a = 1.0 if on else 0.45)
	studio_row.add_child(_ui_editor_switch)

	_edit_ui_btn = Button.new()
	_edit_ui_btn.text = "Edit UI"
	if _tex_studio != null:
		_edit_ui_btn.icon = _tex_studio
		_edit_ui_btn.expand_icon = true
	_edit_ui_btn.custom_minimum_size = Vector2(118, 32)
	_edit_ui_btn.focus_mode = Control.FOCUS_NONE
	_edit_ui_btn.disabled = not ui_ed_on
	_edit_ui_btn.modulate.a = 1.0 if ui_ed_on else 0.45
	_edit_ui_btn.add_theme_stylebox_override("normal", _hairline_btn_face(false))
	_edit_ui_btn.add_theme_stylebox_override("hover", _hairline_btn_face(true))
	_edit_ui_btn.add_theme_stylebox_override("pressed", _hairline_btn_face(false))
	_edit_ui_btn.add_theme_stylebox_override("disabled", _hairline_btn_face(false))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		_edit_ui_btn.add_theme_color_override(st, Color(0.95, 0.96, 0.98))
	if RetroUI.gotham(600) != null:
		_edit_ui_btn.add_theme_font_override("font", RetroUI.gotham(600))
	_edit_ui_btn.add_theme_font_size_override("font_size", 13)
	_edit_ui_btn.pressed.connect(_open_ui_editor_from_settings)
	studio_row.add_child(_edit_ui_btn)
	if Session.username.to_lower() == "nexico8225":
		var mobile_opts: Array = [["PC", 2], ["Mobile", 1], ["Auto", 0]]
		_row_chips(page, "sliders", "Switch Device (Nexico8225 Exclusive)", mobile_opts,
			int(settings.get("mobile_controls")) if settings != null else 2,
			func(v: int) -> void:
				if settings != null:
					settings.set_key("mobile_controls", v))

	_section(page, "monitor", "GRAPHICS & DISPLAY")
	_fullscreen_switch = _row_toggle(page, "expand", "Fullscreen Mode (F11)",
		bool(settings.get("fullscreen")) if settings != null else false,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("fullscreen", on))
	var quality_opts: Array = [["Low", 0], ["Medium", 1], ["High", 2], ["Ultra", 3]]
	_row_chips(page, "sliders", "Graphics Quality", quality_opts,
		int(settings.get("graphics_quality")) if settings != null else 2,
		func(v: int) -> void:
			if settings != null:
				settings.set_key("graphics_quality", v))
	_row_toggle(page, "sun", "Sun Shadows",
		bool(settings.get("shadows")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("shadows", on))
	_slider_row(page, "monitor", "3D Render Scale", 0.5, 1.0,
		float(settings.get("render_scale")) if settings != null else 1.0,
		_fmt_pct,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("render_scale", v))
	var fps_opts: Array = [["Unlimited", 0], ["30", 30], ["60", 60], ["120", 120], ["240", 240]]
	_row_chips(page, "gauge", "Max FPS", fps_opts,
		int(settings.get("max_fps")) if settings != null else 0,
		func(v: int) -> void:
			if settings != null:
				settings.set_key("max_fps", v))
	_row_toggle(page, "sync", "VSync",
		bool(settings.get("vsync")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("vsync", on))

	_section(page, "mic", "VOICE CHAT & AUDIO")
	_row_toggle(page, "mic", "Voice Chat Enabled",
		bool(settings.get("voice_enabled")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("voice_enabled", on))
	var vc: Node = get_node_or_null("/root/VoiceChat")
	var mic_active := true if vc == null else not bool(vc.call("is_muted"))
	_voice_mute_switch = _row_toggle(page, "mic", "Microphone Active (V / Click Overhead Icon)",
		mic_active,
		func(on: bool) -> void:
			if vc != null:
				vc.call("set_muted", not on))

	# Microphone Input Device Selector
	var dev_row := _row(page, "mic", "Microphone Input Device")
	_mic_device_btn = Button.new()
	var current_dev := "Default" if vc == null else String(vc.call("get_input_device"))
	_mic_device_btn.text = current_dev
	_mic_device_btn.custom_minimum_size = Vector2(210, 28)
	_mic_device_btn.clip_text = true
	_mic_device_btn.focus_mode = Control.FOCUS_NONE
	_mic_device_btn.add_theme_stylebox_override("normal", _hairline_btn_face(false))
	_mic_device_btn.add_theme_stylebox_override("hover", _hairline_btn_face(true))
	_mic_device_btn.add_theme_stylebox_override("pressed", _hairline_btn_face(false))
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		_mic_device_btn.add_theme_color_override(st, Color(0.95, 0.96, 0.98))
	if RetroUI.gotham(600) != null:
		_mic_device_btn.add_theme_font_override("font", RetroUI.gotham(600))
	_mic_device_btn.add_theme_font_size_override("font_size", 12)
	_mic_device_btn.pressed.connect(func() -> void:
		if vc == null:
			return
		var devs: PackedStringArray = vc.call("get_input_devices")
		if devs.is_empty():
			return
		var cur := String(vc.call("get_input_device"))
		var idx := devs.find(cur)
		var next_dev := devs[(idx + 1) % devs.size()]
		vc.call("set_input_device", next_dev)
		_mic_device_btn.text = next_dev
		_notify("Microphone Input: %s" % next_dev, false))
	dev_row.add_child(_mic_device_btn)

	_slider_row(page, "mic", "Voice Chat Volume (3D Spatial)", 0.0, 1.0,
		float(settings.get("voice_volume")) if settings != null else 1.0,
		_fmt_pct,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("voice_volume", v))
	_slider_row(page, "sliders", "Mic Input Sensitivity", 0.0, 1.0,
		float(settings.get("mic_sensitivity")) if settings != null else 0.5,
		_fmt_pct,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("mic_sensitivity", v))
	_slider_row(page, "speaker", "Master Volume", 0.0, 1.0,
		float(settings.get("master_volume")) if settings != null else 1.0,
		_fmt_pct,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("master_volume", v))
	_slider_row(page, "speaker", "Sound Effects", 0.0, 1.0,
		float(settings.get("sfx_volume")) if settings != null else 1.0,
		_fmt_pct,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("sfx_volume", v))

	_section(page, "camera", "CAMERA & INTERFACE")
	_slider_row(page, "camera", "Field of View", 40.0, 110.0,
		float(settings.get("fov")) if settings != null else 70.0,
		func(v: float) -> String: return "%d°" % int(roundf(v)),
		func(v: float) -> void:
			if settings != null:
				settings.set_key("fov", v))
	_slider_row(page, "layers", "UI Opacity", 0.3, 1.0,
		float(settings.get("ui_opacity")) if settings != null else 1.0,
		_fmt_pct,
		func(v: float) -> void:
			if settings != null:
				settings.set_key("ui_opacity", v))
	_row_toggle(page, "chart", "Show FPS (Top-Right)",
		bool(settings.get("show_fps")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("show_fps", on))
	_row_toggle(page, "signal", "Show Ping",
		bool(settings.get("show_ping")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("show_ping", on))
	_row_toggle(page, "tag", "Player Names",
		bool(settings.get("player_names")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("player_names", on))
	_row_toggle(page, "bubble", "Chat Bubbles",
		bool(settings.get("chat_bubbles")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("chat_bubbles", on))
	_row_toggle(page, "bounce", "Bunny Hop (Hold Space / Jump)",
		bool(settings.get("bunny_hop")) if settings != null else true,
		func(on: bool) -> void:
			if settings != null:
				settings.set_key("bunny_hop", on))

	_section(page, "person", "ACCOUNT")
	var acct := _row(page, "tag", "Signed in as %s" % Session.username)
	var out_btn := Button.new()
	out_btn.text = "Log Out"
	out_btn.custom_minimum_size = Vector2(110, 30)
	out_btn.focus_mode = Control.FOCUS_NONE
	out_btn.add_theme_stylebox_override("normal", _white_btn_face(false))
	out_btn.add_theme_stylebox_override("hover", _white_btn_face(true))
	out_btn.add_theme_stylebox_override("pressed", _white_btn_face(false))
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		out_btn.add_theme_color_override(st, Color(0.08, 0.09, 0.11))
	if RetroUI.gotham(600) != null:
		out_btn.add_theme_font_override("font", RetroUI.gotham(600))
	out_btn.add_theme_font_size_override("font_size", 12)
	out_btn.pressed.connect(_log_out)
	acct.add_child(out_btn)

	var danger := _row(page, "reset", "Restore Default Options")
	var reset_btn := Button.new()
	reset_btn.text = "Reset All Settings"
	reset_btn.custom_minimum_size = Vector2(170, 30)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_stylebox_override("normal", _hairline_btn_face(false))
	reset_btn.add_theme_stylebox_override("hover", _hairline_btn_face(true))
	reset_btn.add_theme_stylebox_override("pressed", _hairline_btn_face(false))
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		reset_btn.add_theme_color_override(st, Color(0.92, 0.93, 0.95))
	if RetroUI.gotham(600) != null:
		reset_btn.add_theme_font_override("font", RetroUI.gotham(600))
	reset_btn.add_theme_font_size_override("font_size", 12)
	reset_btn.pressed.connect(func() -> void:
		if settings != null:
			settings.call("reset_all")
		camera_rig.set_shift_locked(false)
		_sync_shiftlock_ui()
		_sync_mobile_ui()
		_apply_nameplates()
		_update_live_stats()
		call_deferred("_rebuild_settings_tab")
		_notify("All settings reset", true))
	danger.add_child(reset_btn)
	return tab


func _section(page: VBoxContainer, kind: String, text: String) -> void:
	if page.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		page.add_child(gap)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 9)
	page.add_child(head)
	var ic := MenuIcons.new()
	ic.kind = kind
	ic.custom_minimum_size = Vector2(18, 18)
	ic.ink = Color(0.62, 0.67, 0.74)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ic)
	var l := Label.new()
	l.text = text
	_title(l, 14, Color(0.62, 0.67, 0.74), 700)
	head.add_child(l)


func _row(parent: VBoxContainer, kind: String, label_text: String) -> HBoxContainer:
	var card := PanelContainer.new()
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(1, 1, 1, 0.04)
	card_sb.border_color = Color(1, 1, 1, 0.09)
	card_sb.set_border_width_all(1)
	card_sb.set_corner_radius_all(10)
	card_sb.content_margin_left = 14.0
	card_sb.content_margin_right = 14.0
	card_sb.content_margin_top = 8.0
	card_sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", card_sb)
	parent.add_child(card)

	var r := HBoxContainer.new()
	r.custom_minimum_size = Vector2(0, 34)
	r.add_theme_constant_override("separation", 14)
	card.add_child(r)
	var ic := MenuIcons.new()
	ic.kind = kind
	ic.custom_minimum_size = Vector2(20, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(ic)
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text(l, 15, RetroUI.NIGHT_INK)
	r.add_child(l)
	return r


func _row_toggle(parent: VBoxContainer, kind: String, label_text: String, value: bool, on_toggle: Callable) -> Button:
	var r := _row(parent, kind, label_text)
	var sw := Button.new()
	sw.toggle_mode = true
	sw.button_pressed = value
	sw.custom_minimum_size = Vector2(68, 32)
	sw.focus_mode = Control.FOCUS_NONE
	_style_switch(sw, value)
	sw.toggled.connect(func(on: bool) -> void:
		_style_switch(sw, on)
		on_toggle.call(on))
	r.add_child(sw)
	return sw


func _style_switch(sw: Button, on: bool) -> void:
	var face := StyleBoxFlat.new()
	face.set_corner_radius_all(8)
	face.set_border_width_all(1)
	face.content_margin_left = 12.0
	face.content_margin_right = 12.0
	face.content_margin_top = 3.0
	face.content_margin_bottom = 3.0
	if on:
		face.bg_color = Color("22c55e")
		face.border_color = Color("86efac")
	else:
		face.bg_color = Color(1, 1, 1, 0.08)
		face.border_color = Color(1, 1, 1, 0.16)
	sw.add_theme_stylebox_override("normal", face)
	var hv := face.duplicate() as StyleBoxFlat
	hv.bg_color = Color("34d399") if on else Color(1, 1, 1, 0.14)
	sw.add_theme_stylebox_override("hover", hv)
	sw.add_theme_stylebox_override("pressed", face)
	sw.text = "ON" if on else "OFF"
	var ink := Color.WHITE if on else RetroUI.NIGHT_INK_MUTED
	sw.add_theme_color_override("font_color", ink)
	sw.add_theme_color_override("font_hover_color", Color.WHITE)
	sw.add_theme_color_override("font_pressed_color", ink)
	if RetroUI.gotham(700) != null:
		sw.add_theme_font_override("font", RetroUI.gotham(700))
	sw.add_theme_font_size_override("font_size", 11)


func _slider_row(parent: VBoxContainer, kind: String, label_text: String, minv: float, maxv: float, value: float, fmt: Callable, on_change: Callable) -> void:
	var r := _row(parent, kind, label_text)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	_paper_slider(s)
	r.add_child(s)
	var v := Label.new()
	v.text = String(fmt.call(value))
	v.custom_minimum_size = Vector2(56, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text(v, 14, RetroUI.NIGHT_INK_MUTED)
	r.add_child(v)
	s.value_changed.connect(func(val: float) -> void:
		v.text = String(fmt.call(val))
		on_change.call(val))


func _row_chips(parent: VBoxContainer, kind: String, label_text: String, opts: Array, value: int, on_pick: Callable, on_text: Callable = Callable()) -> void:
	var r := _row(parent, kind, label_text)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	r.add_child(chips)
	var btns: Array[Button] = []
	for opt in opts:
		var val: Variant = opt[1]
		var cb := Button.new()
		cb.text = String(opt[0])
		cb.custom_minimum_size = Vector2(68, 32)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_meta("chip_value", opt[1])
		var is_text_pick: bool = on_text.is_valid()
		cb.pressed.connect(func() -> void:
			on_pick.call(val)
			if is_text_pick:
				on_text.call(String(opt[1]))
			else:
				_style_chips(btns, int(val)))
		chips.add_child(cb)
		btns.append(cb)
	if on_text.is_valid():
		_style_chips_textless(btns)
	else:
		_style_chips(btns, value)


func _style_chips(btns: Array[Button], value: int) -> void:
	for b in btns:
		if not is_instance_valid(b):
			continue
		var on: bool = int(b.get_meta("chip_value")) == value
		b.add_theme_stylebox_override("normal", _chip_face(on))
		b.add_theme_stylebox_override("hover", _chip_face(on, true))
		b.add_theme_stylebox_override("pressed", _chip_face(on))
		var ink := Color("0a0d12") if on else RetroUI.NIGHT_INK_MUTED
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, ink)


func _style_chips_textless(btns: Array[Button]) -> void:
	for b in btns:
		if not is_instance_valid(b):
			continue
		b.add_theme_stylebox_override("normal", _chip_face(false))
		b.add_theme_stylebox_override("hover", _chip_face(false, true))
		b.add_theme_stylebox_override("pressed", _chip_face(false))
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, RetroUI.NIGHT_INK)


func _chip_face(on: bool, hover := false) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.content_margin_left = 9.0
	sb.content_margin_right = 9.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	if on:
		sb.bg_color = Color("ffffff") if hover else Color("f3f4f6")
		sb.border_color = Color(1, 1, 1, 0.9)
	else:
		sb.bg_color = Color(1, 1, 1, 0.14) if hover else Color(1, 1, 1, 0.06)
		sb.border_color = Color(1, 1, 1, 0.18)
	return sb


func _white_btn_face(hover: bool) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.bg_color = Color("ffffff") if hover else Color("f3f4f6")
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func _hairline_btn_face(hover: bool) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.bg_color = Color(1, 1, 1, 0.14) if hover else Color(1, 1, 1, 0.07)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.28) if hover else Color(1, 1, 1, 0.16)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func _fmt_pct(v: float) -> String:
	return "%d%%" % int(roundf(v * 100.0))


func _log_out() -> void:
	_release_account_lock()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Api.clear_session()
	Session.reset()
	get_tree().change_scene_to_file("res://scenes/login.tscn")


func _rebuild_settings_tab() -> void:
	if _settings_tab == null or not is_instance_valid(_settings_tab):
		return
	for child in _settings_tab.get_children():
		child.queue_free()
	var fresh := _build_settings_tab()
	fresh.name = "SettingsPageInner"
	fresh.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_tab.add_child(fresh)


func _apply_nameplates() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	var on := true if settings == null else bool(settings.get("player_names"))
	if player != null and is_instance_valid(player) and player.avatar != null:
		player.avatar.call("set_display_name", Session.username if on else "")
	for uid in _remotes.keys():
		var rp: Node3D = _remotes[uid]
		if rp == null or not is_instance_valid(rp):
			continue
		var rig: Node3D = rp.get("avatar")
		if rig != null and is_instance_valid(rig):
			rig.call("set_display_name",
				String(_names_by_uid.get(uid, "")) if on else "")


func _paper_slider(s: HSlider) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(1, 1, 1, 0.14)
	groove.set_corner_radius_all(4)
	groove.content_margin_top = 4.0
	groove.content_margin_bottom = 4.0
	s.add_theme_stylebox_override("slider", groove)
	s.add_theme_stylebox_override("grabber_area", RetroUI.flat(4, Color("38bdf8")))
	s.add_theme_stylebox_override("grabber_area_highlight", RetroUI.flat(4, Color("7dd3fc")))


func _toggle_menu() -> void:
	if _menu == null or not is_instance_valid(_menu):
		return
	_menu_open = not _menu_open
	_menu.visible = _menu_open
	if _menu_open:
		_menu.modulate.a = 0.0
		create_tween().tween_property(_menu, "modulate:a", 1.0, 0.14)
		camera_rig.set_ui_blocked(true)
		_refresh_player_list(_last_presence)
		_update_live_stats()
	else:
		_menu.modulate.a = 1.0
		camera_rig.set_ui_blocked(false)
	_sync_shiftlock_ui()


func _on_health_changed(hp: float, max_hp: float) -> void:
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	if _health_value != null:
		_health_value.text = "HP: %d / %d" % [int(roundf(hp)), int(roundf(max_hp))]
	if _health_fill != null:
		var sb: StyleBoxFlat = _health_fill_style(ratio)
		_health_fill.add_theme_stylebox_override("panel", sb)
		_health_fill.anchor_left = 0.0
		_health_fill.anchor_top = 0.0
		_health_fill.anchor_bottom = 1.0
		_health_fill.anchor_right = ratio
		_health_fill.offset_left = 3.0
		_health_fill.offset_top = 3.0
		_health_fill.offset_bottom = -3.0
		_health_fill.offset_right = -3.0 if ratio > 0.02 else 3.0
		_health_fill.visible = ratio > 0.005
	if _health_container != null and is_instance_valid(_health_container):
		_health_container.visible = true


func _on_health_depleted() -> void:
	if player != null and is_instance_valid(player) and player.alive:
		player.die(self)
		chat.add_system("Oof! Took too much damage!")
	if not _respawning:
		_start_respawn()


func _on_touched_group(group: String, node: Node3D) -> void:
	if group == "kill" and player.alive:
		player.die(self)
		chat.add_system("Oof! Touched Kill Brick!")
		_start_respawn()
	elif group == "checkpoint":
		var pos: Variant = node.get_meta("spawn", null)
		if pos is Vector3:
			player.spawn_point = Transform3D(Basis(), pos)
			chat.add_system("Checkpoint reached!")
	elif group == "goal" and not _finished:
		_finished = true
		chat.add_system("*** You reached the goal — classic victory! ***")


static func _add_3d_label(parent: Node3D, text_str: String, offset: Vector3, col := Color.WHITE) -> void:
	var lbl := Label3D.new()
	lbl.text = text_str
	lbl.font_size = 64
	lbl.pixel_size = 0.0045
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = col
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.position = offset
	parent.add_child(lbl)


func _build_fun_playground_additions(world_root: Node3D) -> void:
	if world_root == null:
		return
	var tex := WorldBuilderScript.stud_texture()

	# 1. Walkable Slope Ramp (28 deg incline) leading up to a scenic overlook deck
	if world_root.get_node_or_null("SlopeRamp") == null:
		var ramp := StaticBody3D.new()
		ramp.name = "SlopeRamp"
		ramp.position = Vector3(-6.0, 2.1, 14.0)
		ramp.rotation_degrees = Vector3(26.0, 0.0, 0.0)
		var r_col := CollisionShape3D.new()
		var r_shape := BoxShape3D.new()
		r_shape.size = Vector3(5.0, 0.8, 11.0)
		r_col.shape = r_shape
		ramp.add_child(r_col)
		var r_mi := MeshInstance3D.new()
		var r_mesh := BoxMesh.new()
		r_mesh.size = r_shape.size
		r_mi.mesh = r_mesh
		r_mi.material_override = WorldBuilderScript._part_material(Color("4dabf7"), "plastic", tex, false)
		ramp.add_child(r_mi)
		world_root.add_child(ramp)

		WorldBuilderScript._build_part(world_root, { "p": [-6, 4.2, 21.5], "s": [7, 0.8, 6], "c": "339af0" }, tex, _spawns)

	# 2. Classic Speed Coil Pad (Cyan Neon) & Gravity Coil Pad (Purple Neon)
	if world_root.get_node_or_null("SpeedCoilPad") == null:
		var sp_pad := StaticBody3D.new()
		sp_pad.name = "SpeedCoilPad"
		sp_pad.position = Vector3(15.0, 0.3, -8.0)
		sp_pad.add_to_group("speed_pad")
		var sp_col := CollisionShape3D.new()
		var sp_sh := BoxShape3D.new()
		sp_sh.size = Vector3(4.0, 0.6, 4.0)
		sp_col.shape = sp_sh
		sp_pad.add_child(sp_col)
		var sp_mi := MeshInstance3D.new()
		var sp_m := BoxMesh.new()
		sp_m.size = sp_sh.size
		sp_mi.mesh = sp_m
		sp_mi.material_override = WorldBuilderScript._part_material(Color("00d2ff"), "neon", tex, true)
		sp_pad.add_child(sp_mi)
		_add_3d_label(sp_pad, "SPEED PAD (1.65x)", Vector3(0, 1.5, 0), Color("72e8ff"))
		world_root.add_child(sp_pad)

		var gr_pad := StaticBody3D.new()
		gr_pad.name = "GravityCoilPad"
		gr_pad.position = Vector3(21.0, 0.3, -8.0)
		gr_pad.add_to_group("gravity_pad")
		var gr_col := CollisionShape3D.new()
		var gr_sh := BoxShape3D.new()
		gr_sh.size = Vector3(4.0, 0.6, 4.0)
		gr_col.shape = gr_sh
		gr_pad.add_child(gr_col)
		var gr_mi := MeshInstance3D.new()
		var gr_m := BoxMesh.new()
		gr_m.size = gr_sh.size
		gr_mi.mesh = gr_m
		gr_mi.material_override = WorldBuilderScript._part_material(Color("9c36b5"), "neon", tex, true)
		gr_pad.add_child(gr_mi)
		_add_3d_label(gr_pad, "GRAVITY PAD (LOW GRAV)", Vector3(0, 1.5, 0), Color("e599f7"))
		world_root.add_child(gr_pad)

	# 3. Interactive Bricks Row: Damage Brick, Kill Brick, Heal Brick, Insta-Heal Brick
	var brick_defs := [
		{ "name": "DamageBrick", "group": "damage", "pos": Vector3(-9.0, 0.3, -8.0), "col": Color("f76707"), "label": "DAMAGE BRICK (-20 HP)", "meta_k": "damage", "meta_v": 20.0 },
		{ "name": "KillBrick", "group": "kill", "pos": Vector3(-3.0, 0.3, -8.0), "col": Color("e03131"), "label": "KILL BRICK (INSTA-KILL)", "meta_k": "", "meta_v": 0.0 },
		{ "name": "HealBrick", "group": "heal", "pos": Vector3(3.0, 0.3, -8.0), "col": Color("37b24d"), "label": "HEAL BRICK (+15 HP)", "meta_k": "heal", "meta_v": 15.0 },
		{ "name": "InstaHealBrick", "group": "insta_heal", "pos": Vector3(9.0, 0.3, -8.0), "col": Color("0ca678"), "label": "INSTA-HEAL (100% HP)", "meta_k": "", "meta_v": 0.0 },
	]
	for bd in brick_defs:
		var existing := world_root.get_node_or_null(String(bd["name"])) as Node3D
		if existing != null:
			var emi := existing.get_node_or_null("MeshInstance3D") as MeshInstance3D
			if emi != null:
				emi.material_override = WorldBuilderScript._part_material(bd["col"], "plastic", tex, false)
			continue
		var b := StaticBody3D.new()
		b.name = String(bd["name"])
		b.position = bd["pos"]
		b.add_to_group(String(bd["group"]))
		if String(bd["meta_k"]) != "":
			b.set_meta(String(bd["meta_k"]), float(bd["meta_v"]))
		var bc := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4.0, 0.6, 4.0)
		bc.shape = bs
		b.add_child(bc)
		var bmi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		bmi.mesh = bm
		bmi.material_override = WorldBuilderScript._part_material(bd["col"], "plastic", tex, false)
		b.add_child(bmi)
		_add_3d_label(b, String(bd["label"]), Vector3(0, 1.5, 0), (bd["col"] as Color).lightened(0.35))
		world_root.add_child(b)

	# 4. Climbable Ladder & Platform (Torso-touch climb -> smooth top dismount onto platform)
	if world_root.get_node_or_null("LadderTowerPlatform") == null:
		var plat := StaticBody3D.new()
		plat.name = "LadderTowerPlatform"
		plat.position = Vector3(0.0, 8.0, -19.0)
		var pc := CollisionShape3D.new()
		var ps := BoxShape3D.new()
		ps.size = Vector3(7.0, 1.0, 7.0)
		pc.shape = ps
		plat.add_child(pc)
		var pmi := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = ps.size
		pmi.mesh = pm
		pmi.material_override = WorldBuilderScript._part_material(Color("495057"), "plastic", tex, false)
		plat.add_child(pmi)
		world_root.add_child(plat)

		var lad := StaticBody3D.new()
		lad.name = "ClimbLadder"
		lad.position = Vector3(0.0, 4.25, -15.1)
		lad.collision_layer = 1 | 16
		lad.add_to_group("ladder")
		var lc := CollisionShape3D.new()
		var ls := BoxShape3D.new()
		ls.size = Vector3(2.2, 8.5, 0.8)
		lc.shape = ls
		lad.add_child(lc)
		var lmi := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = ls.size
		lmi.mesh = lm
		lmi.material_override = WorldBuilderScript._part_material(Color("f59f00"), "plastic", tex, false)
		lad.add_child(lmi)
		_add_3d_label(lad, "CLIMB LADDER", Vector3(0, 5.2, 0), Color("ffd43b"))
		world_root.add_child(lad)

	# 5. Moveable Platforms (Point A <-> Point B: one Always Move, one Move When Player Stands On It)
	if world_root.get_node_or_null("MovingPlatformAlways") == null:
		var mp_script := load("res://scripts/world/moving_platform.gd")
		if mp_script != null:
			var mp1: Node3D = mp_script.new()
			mp1.name = "MovingPlatformAlways"
			mp1.position = Vector3(22.0, 0.6, -2.0)
			mp1.set("block_size", Vector3(5.0, 0.8, 5.0))
			mp1.set("block_color", Color("f5cd30"))
			mp1.set("point_a", Vector3.ZERO)
			mp1.set("point_b", Vector3(0.0, 0.0, 14.0))
			mp1.set("move_mode", 0)
			mp1.set("easing", "SineInOut")
			mp1.set("move_duration", 3.0)
			mp1.set("wait_time", 0.7)
			_add_3d_label(mp1, "MOVING PLATFORM (ALWAYS MOVE)", Vector3(0, 1.8, 0), Color("ffe066"))
			world_root.add_child(mp1)

			var mp2: Node3D = mp_script.new()
			mp2.name = "MovingPlatformOnStand"
			mp2.position = Vector3(29.0, 0.6, -2.0)
			mp2.set("block_size", Vector3(5.0, 0.8, 5.0))
			mp2.set("block_color", Color("0d69ac"))
			mp2.set("point_a", Vector3.ZERO)
			mp2.set("point_b", Vector3(0.0, 5.0, 14.0))
			mp2.set("move_mode", 1)
			mp2.set("move_on_player_stand", true)
			mp2.set("easing", "CubicInOut")
			mp2.set("move_duration", 2.8)
			_add_3d_label(mp2, "MOVING PLATFORM (STAND TO MOVE)", Vector3(0, 1.8, 0), Color("74c0fc"))
			world_root.add_child(mp2)

	# 6. Animated Classic Roblox Disco Dance Floor (4x4 color-cycling stud tiles)
	if world_root.get_node_or_null("DiscoFloor") == null:
		var disco_root := Node3D.new()
		disco_root.name = "DiscoFloor"
		disco_root.position = Vector3(-16.0, 0.15, -18.0)
		world_root.add_child(disco_root)
		_disco_mats.clear()
		var palette: Array[Color] = [
			Color("e03131"), Color("f59f00"), Color("2f9e44"),
			Color("1971c2"), Color("9c36b5"), Color("0ca678"),
		]
		for gx in range(4):
			for gz in range(4):
				var tile := StaticBody3D.new()
				tile.position = Vector3((gx - 1.5) * 3.0, 0.0, (gz - 1.5) * 3.0)
				var tc := CollisionShape3D.new()
				var ts := BoxShape3D.new()
				ts.size = Vector3(2.92, 0.3, 2.92)
				tc.shape = ts
				tile.add_child(tc)
				var tmi := MeshInstance3D.new()
				var tm := BoxMesh.new()
				tm.size = ts.size
				tmi.mesh = tm
				var init_col: Color = palette[(gx * 4 + gz) % palette.size()]
				var mat := WorldBuilderScript._part_material(init_col, "plastic", tex, false)
				tmi.material_override = mat
				if mat is ShaderMaterial:
					_disco_mats.append(mat as ShaderMaterial)
				tile.add_child(tmi)
				disco_root.add_child(tile)


func _start_respawn() -> void:
	if _respawning:
		return
	_respawning = true
	var timer := get_tree().create_timer(RESPAWN_SECONDS)
	timer.timeout.connect(func() -> void:
		_respawning = false
		if player == null or not is_instance_valid(player):
			return
		player.respawn_at(player.spawn_point.origin))


func _on_chat_submit(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return
	if trimmed.begins_with("/"):
		_handle_command(trimmed)
		return

	chat.add_chat(Session.username, Session.seq_id, trimmed, "", true, Session.user_id)
	var settings_node: Node = get_node_or_null("/root/Settings")
	var allow_bubbles := true if settings_node == null else bool(settings_node.get("chat_bubbles"))
	if allow_bubbles and player != null and is_instance_valid(player):
		player.show_bubble(trimmed)

	if Session.is_guest:
		return

	_pending_local_texts.append(trimmed)
	var res: Dictionary = await Api.place_chat_send(String(place["id"]), trimmed)
	if res.get("ok", false) and res.get("message", null) is Dictionary:
		var msg: Dictionary = res["message"]
		var mid := Api.txt(msg.get("id", ""))
		if mid != "":
			_seen_messages[mid] = true
	_pending_local_texts.erase(trimmed)


func _handle_command(command: String) -> void:
	var parts := command.split(" ", false)
	var cmd := String(parts[0]).to_lower()
	if cmd == "/help":
		chat.add_system("Commands: /e sit · /e stop · /help")
		chat.add_system("Press / to chat · SHIFT = shift lock · V = voice mic · F11 = fullscreen")
	elif cmd == "/e":
		var emote := String(parts[1]).to_lower() if parts.size() > 1 else ""
		match emote:
			"sit":
				if player != null and is_instance_valid(player):
					player.avatar.call("play_emote", "Sit")
				chat.add_system("You sit down. (move to stand up)")
			"stop", "stand":
				if player != null and is_instance_valid(player):
					player.avatar.call("play_emote", "")
			"dance", "wave", "point":
				chat.add_system("The classic rig knows Sit — try /e sit")
			_:
				chat.add_system("Unknown emote — try /e sit or /e stop")
	else:
		chat.add_system("Unknown command — try /help")


func _poll_feed() -> void:
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await Api.place_chat_get(String(place["id"]))
	_last_ping_ms = int(Time.get_ticks_msec() - t0)
	if not res.get("ok", false):
		return
	var msgs: Array = res.get("messages", [])
	if not _chat_history_done:
		_chat_history_done = true
		for msg in msgs:
			var mid := Api.txt(msg.get("id", ""))
			if mid != "":
				_seen_messages[mid] = true
	else:
		for msg in msgs:
			_ingest_message(msg)
	_reconcile_players(res.get("players", []))


func _ingest_message(msg: Dictionary) -> void:
	var id := Api.txt(msg.get("id", ""))
	if id == "" or _seen_messages.has(id):
		return
	_seen_messages[id] = true
	var uid := Api.txt(msg.get("userId", ""))
	var uname := Api.txt(msg.get("username", "?"), "?")
	var seq := int(msg.get("seqId", 0)) if msg.get("seqId") != null else 0
	var text := Api.txt(msg.get("text", ""))
	if uid == Session.user_id and _pending_local_texts.has(text):
		_pending_local_texts.erase(text)
		return
	chat.add_chat(uname, seq, text, "", uid == Session.user_id, uid)
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node != null and not bool(settings_node.get("chat_bubbles")):
		return
	if uid == Session.user_id:
		if player != null and is_instance_valid(player):
			player.show_bubble(text)
	elif _remotes.has(uid):
		var rp: Node3D = _remotes[uid]
		if is_instance_valid(rp):
			rp.show_bubble(text)


func _reconcile_players(players: Array) -> void:
	var seen: Dictionary = {}
	for p in players:
		var uid := String(p.get("userId", ""))
		var uname_check := String(p.get("username", ""))
		if uid == "" or uid == Session.user_id or uname_check.to_lower() == Session.username.to_lower():
			var p_inst := String(p.get("instanceId", ""))
			if p_inst != "" and p_inst != _instance_id:
				var p_joined := float(p.get("joinedAt", _joined_at_unix + 10.0))
				if p_joined <= _joined_at_unix:
					_disconnect_duplicate_account()
					return
			continue
		seen[uid] = true
		_names_by_uid[uid] = String(p.get("username", ""))
		var pos_arr: Array = p.get("pos", [0, 0, 0])
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var speaking := bool(p.get("speaking", false))
		var v_level := float(p.get("voiceLevel", 0.0))
		var v_b64 := String(p.get("voice", ""))
		var v_seq := int(p.get("voiceSeq", 0))
		if _remotes.has(uid):
			_remotes[uid].update_state(pos, float(p.get("heading", 0.0)), speaking, v_level, v_b64, v_seq)
		else:
			var rp := RemotePlayerScript.new()
			add_child(rp)
			rp.setup(uid, String(p.get("username", "Player")))
			var setg: Node = get_node_or_null("/root/Settings")
			if setg != null and not bool(setg.get("player_names")):
				rp.get("avatar").call("set_display_name", "")
			rp.update_state(pos, float(p.get("heading", 0.0)), speaking, v_level, v_b64, v_seq)
			_remotes[uid] = rp
			var uname := String(p.get("username", "Someone"))
			chat.add_system("%s is here" % uname)
			_notify("%s joined you" % uname, true)
			var payload := Session.cached_avatar(uid)
			if payload.is_empty():
				_dress_remote(rp, uid)
			else:
				rp.dress(Api, payload)
	for uid in _remotes.keys():
		if not seen.has(uid):
			var rp: Node3D = _remotes[uid]
			rp.fade_out()
			_remotes.erase(uid)
	_last_presence = players
	_people_total = 1 + _remotes.size()
	_update_people_title()
	if _menu_open:
		_refresh_player_list(players)


func _dress_remote(rp: Node3D, uid: String) -> void:
	var res: Dictionary = await Api.avatar_of(uid)
	if res.get("ok", false) and is_instance_valid(rp):
		var raw: Variant = res.get("avatar", null)
		var payload: Dictionary = raw if raw is Dictionary else {}
		Session.cache_avatar(uid, payload)
		await rp.dress(Api, payload)


func _refresh_player_list(players: Array) -> void:
	if _players_grid == null or not is_instance_valid(_players_grid):
		return
	for child in _players_grid.get_children():
		child.queue_free()
	var seen := {}
	_players_grid.add_child(_player_card(Session.user_id, Session.username, true))
	seen[Session.user_id] = true
	for p in players:
		var uid := String(p.get("userId", ""))
		var uname := String(p.get("username", ""))
		if uid == "" or uid == Session.user_id or uname == "" or uname.to_lower() == Session.username.to_lower() or seen.has(uid):
			continue
		_names_by_uid[uid] = uname
		seen[uid] = true
		_players_grid.add_child(_player_card(uid, uname, false))
	_people_total = seen.size()
	_update_people_title()
	for uid in _viewers.keys():
		if not seen.has(uid):
			if is_instance_valid(_viewers[uid]):
				_viewers[uid].queue_free()
			_viewers.erase(uid)
			_viewer_dressed.erase(uid)
			_viewer_pending.erase(uid)
	_update_live_stats()
