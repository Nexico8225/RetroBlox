extends Node3D
## Game — one play session in one place. Builds the world, spawns YOU with
## your account avatar, runs the chat + presence loop (the internet's version
## of a game server: the RetroBlox platform relays everyone), and handles the
## classic flow: kill bricks, checkpoints, goals, oof, respawn.

const LocalPlayerScript := preload("res://scripts/player/local_player.gd")
const RemotePlayerScript := preload("res://scripts/player/remote_player.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")
const ChatBoxScript := preload("res://scripts/game/chat_box.gd")
const PlacesScript := preload("res://scripts/world/places.gd")
const WorldBuilderScript := preload("res://scripts/world/world_builder.gd")
const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const AvatarPortraitScript := preload("res://scripts/ui/avatar_portrait.gd")

const POLL_SECONDS := 2.5       # chat + presence feed
const HEARTBEAT_SECONDS := 4.0  # my presence out
const RESPAWN_SECONDS := 2.8

var place: Dictionary
var player            # LocalPlayer — untyped: custom members, dynamic calls
var camera_rig        # CameraRig
var chat              # ChatBox
var hud: CanvasLayer

var _health_fill: ColorRect
var _health_value: Label
var _menu: Control
var _players_tab: VBoxContainer
var _players_grid: GridContainer     # v3.9: the People page — a card grid, not a list
var _settings_tab: VBoxContainer
var _people_title: Label             # v3.9: "PEOPLE — 2 ONLINE" in the page header
var _time_label: Label               # v3.9: live session clock in the page header
var _fps_chip: Label                 # v3.9: MY fps, always visible in the rail
var _ping_chip: Label                # v3.9: MY ping, always visible in the rail
var _my_card_stats: Label            # v3.9: the stat line on my own card
var _fps_smooth := 60.0              # v3.9: eased fps so the chip doesn't flicker
var _menu_tick := 0.5                # v3.9: live stats refresh cadence
var _remote_stats: Dictionary = {}   # v3.9: userId -> {"ping": int, "fps": int}
var _portrait_cache: Dictionary = {} # v3.9: userId -> rendered avatar Texture2D
var _portrait_nodes: Dictionary = {} # v3.9: userId -> the card TextureRect to swap when ready
var _portrait_pending: Dictionary = {} # v3.9: renders already in flight
var _remotes: Dictionary = {}      # userId -> RemotePlayer
var _seen_messages: Dictionary = {} # message id -> true
var _spawns: Array[Vector3] = []
var _respawning := false
var _finished := false
var _poll_left := 0.6
var _beat_left := 1.2
var _menu_open := false
var _chat_badge: Label
var _chat_badge_panel: PanelContainer
var _toast_box: VBoxContainer
var _shift_check: CheckButton
var _center_cursor: TextureRect   # the visible mouse parked mid-screen in first person
var _loading: Control             # the v3.6 loading veil (no more load hitch)
var _session_start_ms := 0        # the match timer
var _last_ping_ms := 0            # last platform round-trip, shown as ping


func _ready() -> void:
        place = Session.current_place
        if place.is_empty():
                # the hub is retired: signing in drops you straight into the classic
                # baseplate — sign in and just play
                place = PlacesScript.by_id("baseplate")
        _session_start_ms = Time.get_ticks_msec()

        # ---- the loading veil goes up FIRST: the world + avatar + HUD are
        # built across a few frames now (no one-frame freeze) and this covers it
        _show_loading()
        await get_tree().process_frame

        var built: Dictionary = WorldBuilderScript.build(place)
        add_child(built["root"])
        _spawns = built["spawns"]
        if _spawns.is_empty():
                _spawns.append(Vector3(0.0, 6.0, 0.0) * WorldBuilderScript.STUD)
        # a frame between the world and the player splits the spike
        await get_tree().process_frame

        # ---- me ----
        player = LocalPlayerScript.new()
        add_child(player)
        player.global_position = _spawns[0]
        player.spawn_point = Transform3D(Basis(), _spawns[0])
        player.setup(Session.username)
        player.health_changed.connect(_on_health_changed)
        player.health_depleted.connect(_on_health_depleted)
        player.touched_group.connect(_on_touched_group)
        _dress_me()

        # ---- collectibles + sound bed ----
        _setup_audio()

        # ---- the classic cursors (uploaded RetroBlox hand, everywhere) ----
        RetroUI.apply_cursors()

        # ---- camera ----
        camera_rig = CameraRigScript.new()
        add_child(camera_rig)
        camera_rig.setup(player)
        camera_rig.set_ui_blocked(false)   # cursor free in third person
        camera_rig.first_person_changed.connect(_on_first_person)
        var settings: Node = get_node_or_null("/root/Settings")
        if settings != null:
                camera_rig.set_shift_locked(bool(settings.get("shift_lock")))

        _build_hud()

        chat.add_system("Welcome to %s!" % String(place.get("name", "the place")))
        if Session.is_guest:
                chat.add_system("You are a guest — watch the chat, sign up on RetroBlox to talk and show online.")
        else:
                chat.add_system("Chat + players are live across the internet. Say hi!")

        # let a frame fully DRAW the scene behind the veil (world shaders compile
        # while it is up), then lift it — the game appears smooth and ready
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
        _hide_loading()


## The v3.6 loading veil: dark steel + your wordmark + a status line. It
## hides the world/avatar/HUD build so loading feels instant instead of
## freezing for a beat.
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
        bg.color = Color(0.055, 0.07, 0.09)
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
        status.text = "Loading the classic place…"
        status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        status.add_theme_color_override("font_color", Color(0.66, 0.74, 0.82))
        if RetroUI.pixel_font() != null:
                status.add_theme_font_override("font", RetroUI.pixel_font())
                status.add_theme_font_size_override("font_size", 12)
        box.add_child(status)


func _hide_loading() -> void:
        if _loading == null or not is_instance_valid(_loading):
                return
        var veil := _loading
        _loading = null
        var tween := create_tween()
        tween.tween_property(veil, "modulate:a", 0.0, 0.3)
        tween.tween_callback(func() -> void:
                var layer := veil.get_parent()
                veil.queue_free()
                if layer != null and is_instance_valid(layer):
                        layer.queue_free())


# ---------------------------------------------------------------- dressing

func _dress_me() -> void:
        if Session.is_guest:
                return  # avatar already painted classic noob by the rig
        var payload := Session.my_avatar_data()
        if payload.is_empty():
                var me: Dictionary = await Api.get_me()
                if me.get("ok", false):
                        Session.avatar = me
                        payload = Session.my_avatar_data()
        await player.call("dress", Api, payload)


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
        if _menu_open:
                return
        # staged loading: _ready awaits across a few frames — the player may
        # not exist yet, sit tight until it does
        if player == null or not is_instance_valid(player):
                return
        # TYPING FREEZES YOU — while the chat box has the keyboard, WASD and
        # Space mean letters, not movement (classic chat behavior)
        var typing: bool = chat != null and is_instance_valid(chat) and chat.is_open
        var dir := Vector2.ZERO if typing else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        var jump := false if typing else Input.is_action_just_pressed("jump")
        var jump_held := false if typing else Input.is_action_pressed("jump")
        player.drive(delta, dir, camera_rig.drive_yaw() if camera_rig != null else 0.0, jump, camera_rig.shift_locked if camera_rig != null else false, camera_rig.first_person if camera_rig != null else false, jump_held)

        # fall into the void -> die (the oof knows). void_y is authored in studs.
        if player.alive and player.global_position.y < float(place.get("void_y", -40.0)) * WorldBuilderScript.STUD:
                player.die(self)
                _start_respawn()


func _process(delta: float) -> void:
        _poll_left -= delta
        if _poll_left <= 0.0:
                _poll_left = POLL_SECONDS
                _poll_feed()
        _beat_left -= delta
        if _beat_left <= 0.0:
                _beat_left = HEARTBEAT_SECONDS
                if not Session.is_guest and player != null and is_instance_valid(player):
                        # v3.9: my ping + fps ride along, so the whole server
                        # can see everyone's live stats on the People cards
                        Api.place_presence(String(place["id"]), player.global_position, player.heading,
                                _last_ping_ms, int(Engine.get_frames_per_second()))
        # v3.9: while the menu is up, its live readouts breathe every half second
        if _menu_open:
                _menu_tick -= delta
                if _menu_tick <= 0.0:
                        _menu_tick = 0.5
                        _update_live_stats()


func _unhandled_input(event: InputEvent) -> void:
        # ---- ESC menu keyboard shortcuts (classic and fast) ----
        if _menu_open and event is InputEventKey and event.is_pressed() and not event.is_echo() \
                        and not chat.is_open:
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
                _toggle_menu()
                get_viewport().set_input_as_handled()
        elif event.is_action_pressed("ui_text_submit") or (event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ENTER):
                if not _menu_open and chat != null and is_instance_valid(chat) and not chat.is_open:
                        chat.open()
                        camera_rig.set_ui_blocked(true)
                        get_viewport().set_input_as_handled()
        elif event is InputEventKey and event.is_pressed() and not event.is_echo() \
                        and (event as InputEventKey).keycode == KEY_R and not _menu_open \
                        and not chat.is_open:
                # v3.8: the R key opens the menu from the game (press R again
                # inside it to confirm the reset — same classic hotkeys)
                _open_menu("players")
                get_viewport().set_input_as_handled()
        elif event.is_action_pressed("toggle_players"):
                _open_menu("players")
                get_viewport().set_input_as_handled()
        elif event.is_action_pressed("shift_lock"):
                # classic SHIFT toggle — squares the character up to the camera
                camera_rig.set_shift_locked(not camera_rig.shift_locked)
                var st: Node = get_node_or_null("/root/Settings")
                if st != null:
                        st.call("set_key", "shift_lock", camera_rig.shift_locked)
                if _shift_check != null and is_instance_valid(_shift_check):
                        _shift_check.set_pressed_no_signal(camera_rig.shift_locked)
                get_viewport().set_input_as_handled()
        # NOTE: no click-to-capture — the cursor is ALWAYS usable in third
        # person now; the camera orbits with the RIGHT mouse button instead.


## First person: the camera becomes your eyes — hide the avatar (and its
## nameplate) so it never blocks the view. Your own chat bubble hides too,
## and the mouse APPEARS parked in the middle of the screen so you always
## know where your aim is.
func _on_first_person(active: bool) -> void:
        if player != null and is_instance_valid(player):
                player.avatar.visible = not active
                player.bubble.visible = not active
        if _center_cursor != null and is_instance_valid(_center_cursor):
                _center_cursor.visible = active


# ---------------------------------------------------------------- HUD

## The HUD from the reference video: a black rounded TOPBAR PILL (logo /
## chat with unread badge) top-left, a VERTICAL HEALTH BAR on the
## right, join toasts top-center,
## translucent dark chat top-left, and the retro ESC menu card in the center.
## v3.7: the pill is TRIMMED — logo + chat only. The menu lives on the ESC
## key ("esc menu"), no more three-line button or people button.
func _build_hud() -> void:
        hud = CanvasLayer.new()
        hud.name = "HUD"
        add_child(hud)

        # chat FIRST — the topbar's chat button + unread badge wire to it
        chat = ChatBoxScript.new()
        chat.submitted.connect(_on_chat_submit)
        chat.opened.connect(func() -> void: camera_rig.set_ui_blocked(true))
        chat.closed.connect(func() -> void:
                if not _menu_open:
                        camera_rig.set_ui_blocked(false))
        hud.add_child(chat)

        _build_topbar()
        _build_health()
        _build_center_cursor()

        # ---- top-center: join toasts ----
        _toast_box = VBoxContainer.new()
        _toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
        _toast_box.offset_top = 14.0
        _toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _toast_box.add_theme_constant_override("separation", 6)
        _toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
        hud.add_child(_toast_box)

        # ---- center: esc menu with Players + Settings tabs ----
        _menu = _build_menu()
        # the shared retro theme never reaches a CanvasLayer on its own —
        # hand it over so the menu buttons speak in the pixel voice too
        _menu.theme = RetroUI.shared
        hud.add_child(_menu)


# ---- topbar pill -------------------------------------------------------

func _build_topbar() -> void:
        var pill := PanelContainer.new()
        pill.name = "Topbar"
        pill.add_theme_stylebox_override("panel", _pill_style())
        pill.position = Vector2(12, 12)
        hud.add_child(pill)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        pill.add_child(row)

        var logo_btn := _pill_button("res://assets/icons/logo.png", "RetroBlox")
        logo_btn.pressed.connect(func() -> void:
                _notify("RetroBlox — %s" % String(place.get("name", "a classic place"))))
        row.add_child(logo_btn)

        # v3.7: just the chat button — ESC opens the menu, P opens the player
        # list, no three-line icon and no people/invite button on the pill
        var chat_btn := _pill_button("res://assets/icons/chat.png", "Chat (ENTER)")
        chat_btn.pressed.connect(func() -> void:
                # v3.6: a clean TOGGLE — the chat (log + type box together)
                # opens and closes as one thing, nothing left dangling
                if chat.is_open:
                        chat.close()
                else:
                        chat.open())
        chat.unread.connect(func(n: int) -> void:
                _chat_badge.text = "" if n <= 0 else str(n)
                if _chat_badge_panel != null and is_instance_valid(_chat_badge_panel):
                        _chat_badge_panel.visible = n > 0)
        var badge_holder := Control.new()
        badge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        badge_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
        badge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        chat_btn.add_child(badge_holder)
        _chat_badge = Label.new()
        _chat_badge.name = "ChatBadge"
        _chat_badge.text = ""
        _chat_badge.add_theme_font_size_override("font_size", 12)
        _chat_badge.add_theme_color_override("font_color", Color.WHITE)
        var badge_panel := PanelContainer.new()
        badge_panel.add_theme_stylebox_override("panel", _badge_style())
        badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        badge_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        badge_panel.offset_left = -4.0
        badge_panel.offset_right = 10.0
        badge_panel.offset_top = -6.0
        badge_panel.offset_bottom = 10.0
        badge_panel.add_child(_chat_badge)
        badge_holder.add_child(badge_panel)
        _chat_badge_panel = badge_panel
        badge_panel.visible = false   # no unread yet — no red dot
        row.add_child(chat_btn)

        # v3.7: the people/invite button is GONE — the player list lives in
        # the ESC menu (Players tab, still opens with P)


func _pill_button(icon_path: String, tip: String) -> Button:
        var b := Button.new()
        b.custom_minimum_size = Vector2(40, 34)
        b.focus_mode = Control.FOCUS_NONE
        b.tooltip_text = tip
        b.icon = load(icon_path)
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        b.expand_icon = true
        b.add_theme_stylebox_override("normal", _pill_btn_style(false))
        b.add_theme_stylebox_override("hover", _pill_btn_style(true))
        b.add_theme_stylebox_override("pressed", _pill_btn_style(true))
        return b


func _pill_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.055, 0.06, 0.07, 0.86)
        sb.set_corner_radius_all(22)
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 5.0
        sb.content_margin_bottom = 5.0
        return sb


func _pill_btn_style(hover: bool) -> StyleBox:
        # the authentic 2011 GLASS icon button (dark face, left shine) —
        # pulled from the public 2011-08 client archive
        var sb: StyleBoxTexture = RetroUI.glass_button(hover)
        if sb != null:
                return sb
        var flat := StyleBoxFlat.new()
        flat.bg_color = Color(1, 1, 1, 0.12) if hover else Color(0, 0, 0, 0)
        flat.set_corner_radius_all(16)
        return flat


func _badge_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("e2231a")
        sb.set_corner_radius_all(9)
        sb.content_margin_left = 5.0
        sb.content_margin_right = 5.0
        sb.content_margin_top = 1.0
        sb.content_margin_bottom = 1.0
        return sb


# ---- the health PLATE (right edge, docked like the topbar) --------------

func _build_health() -> void:
        # v3.8: the bar lives in a bevel PLATE docked to the right edge — the
        # same metallic family as the menu frame, nothing floats loose anymore
        var plate := PanelContainer.new()
        plate.name = "HealthBar"
        plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
        plate.add_theme_stylebox_override("panel", RetroUI.bevel_texture(Color("263441")))
        plate.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        plate.offset_left = -88.0
        plate.offset_right = -12.0
        plate.offset_top = -106.0
        plate.offset_bottom = 106.0
        hud.add_child(plate)
        var holder := VBoxContainer.new()
        holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.alignment = BoxContainer.ALIGNMENT_CENTER
        holder.add_theme_constant_override("separation", 6)
        plate.add_child(holder)

        var label := Label.new()
        label.text = "HEALTH"
        _pix(label, 8, Color(0.66, 0.78, 0.88))
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(label)

        # the bar: dark well + green fill rising from the bottom
        var track_holder := Control.new()
        track_holder.custom_minimum_size = Vector2(14, 150)
        track_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        track_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(track_holder)
        var track := ColorRect.new()
        track.color = Color(0.045, 0.07, 0.1, 0.92)
        track.mouse_filter = Control.MOUSE_FILTER_IGNORE
        track.set_anchors_preset(Control.PRESET_FULL_RECT)
        track_holder.add_child(track)
        _health_fill = ColorRect.new()
        _health_fill.color = Color("3fd432")
        _health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _health_fill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        _health_fill.offset_top = -150.0
        track_holder.add_child(_health_fill)

        _health_value = Label.new()
        _health_value.text = "100"
        _pix(_health_value, 8, Color(0.11, 0.16, 0.2))
        _health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var chip := PanelContainer.new()
        chip.add_theme_stylebox_override("panel", _chip_style())
        chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
        chip.add_child(_health_value)
        holder.add_child(chip)


func _chip_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        # cyan chip like the video's health readout
        sb.bg_color = Color("00d6c2")
        sb.set_corner_radius_all(8)
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 2.0
        sb.content_margin_bottom = 2.0
        return sb


# ---- the first-person center cursor --------------------------------------

## In first person the OS cursor is captured (hidden) so the camera can
## turn — this draws the uploaded RetroBlox Pointer parked in the MIDDLE of
## the screen, so your mouse visibly sits where you aim, exactly as asked.
func _build_center_cursor() -> void:
        _center_cursor = TextureRect.new()
        _center_cursor.name = "CenterCursor"
        var tex: Texture2D = load("res://assets/ui/cursor_pointer.png") if ResourceLoader.exists("res://assets/ui/cursor_pointer.png") else null
        if tex != null:
                _center_cursor.texture = tex
        _center_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _center_cursor.custom_minimum_size = Vector2(32, 32)
        _center_cursor.size = Vector2(32, 32)
        _center_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _center_cursor.set_anchors_preset(Control.PRESET_CENTER)
        _center_cursor.offset_left = -16.0
        _center_cursor.offset_right = 16.0
        _center_cursor.offset_top = -16.0
        _center_cursor.offset_bottom = 16.0
        _center_cursor.visible = false
        hud.add_child(_center_cursor)


# ---- toasts (top-center black pills) ------------------------------------

func _notify(text: String, with_sound := false) -> void:
        if _toast_box == null or not is_instance_valid(_toast_box):
                return
        var pill := PanelContainer.new()
        pill.add_theme_stylebox_override("panel", _pill_style())
        var l := Label.new()
        l.text = text
        l.add_theme_font_size_override("font_size", 14)
        l.add_theme_color_override("font_color", Color.WHITE)
        pill.add_child(l)
        _toast_box.add_child(pill)
        if with_sound:
                var sfx: Node = get_node_or_null("/root/Sfx")
                if sfx != null:
                        sfx.call("play_join")
        var tween := create_tween()
        tween.tween_interval(3.4)
        tween.tween_property(pill, "modulate:a", 0.0, 0.5)
        tween.tween_callback(pill.queue_free)


# ---------------------------------------------------------------- audio bed

## The wind bed on sky places (the music box is gone — you asked!). Loops
## via code-set WAV loop points and respects the SFX volume slider.
func _setup_audio() -> void:
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx == null:
                return
        if bool(place.get("wind", false)):
                var wind = sfx.call("make_screen_loop", "Wind")
                if wind != null:
                        add_child(wind)
                        wind.call("play")


# ---- the menu — the v3.10 GLOSSY CLASSIC CLIENT window -------------------
## The v3.9 client shell, now wearing the OLD-SITE look: the window itself
## is the authentic 2011 rounded plate (a real texture from the public
## 2011-08 client archive), the bars are banded gradient panels with hard
## dark edges, and every action key is a GLOSSY gradient button with a
## bold ink outline — shine band up top, hard gloss cut, dark base, white
## outlined pixel text. Same tight palette, way more retro.


func _build_menu() -> Control:
        var overlay := Control.new()
        overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.visible = false
        var dim := ColorRect.new()
        dim.color = Color(0.01, 0.02, 0.03, 0.72)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.add_child(dim)
        var shadow := PanelContainer.new()
        var sh_sb := StyleBoxFlat.new()
        sh_sb.bg_color = Color(0, 0, 0, 0)
        sh_sb.shadow_color = Color(0, 0, 0, 0.55)
        sh_sb.shadow_size = 16
        sh_sb.shadow_offset = Vector2(0, 6)
        shadow.add_theme_stylebox_override("panel", sh_sb)
        shadow.set_anchors_preset(Control.PRESET_CENTER)
        shadow.grow_horizontal = Control.GROW_DIRECTION_BOTH
        shadow.grow_vertical = Control.GROW_DIRECTION_BOTH
        overlay.add_child(shadow)
        # the client window — the authentic 2011 rounded plate texture
        var client := PanelContainer.new()
        client.name = "MenuWindow"
        client.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        client.add_theme_stylebox_override("panel", _client_style())
        shadow.add_child(client)
        var root := VBoxContainer.new()
        root.name = "MenuRoot"
        root.custom_minimum_size = Vector2(620, 0)
        root.add_theme_constant_override("separation", 0)
        client.add_child(root)

        # ---- title bar: wordmark on ink, place name, classic red close ----
        root.add_child(_menu_title_bar())

        # ---- body: nav rail on the left, pages on the right ----
        var body := HBoxContainer.new()
        body.name = "MenuBody"
        body.add_theme_constant_override("separation", 0)
        root.add_child(body)

        # LEFT RAIL — the structural break from the old top-tab card
        var rail := PanelContainer.new()
        rail.name = "NavRail"
        rail.add_theme_stylebox_override("panel", _rail_style())
        rail.custom_minimum_size = Vector2(112, 0)
        body.add_child(rail)
        var rail_box := VBoxContainer.new()
        rail_box.add_theme_constant_override("separation", 6)
        rail.add_child(rail_box)
        var people_nav := _nav_button("PEOPLE", "people")
        var settings_nav := _nav_button("SETTINGS", "gear")
        rail_box.add_child(people_nav)
        rail_box.add_child(settings_nav)
        # pinned to the rail's foot: YOUR live readout — fps + ping at a
        # glance no matter which page is open
        rail_box.add_child(_spacer())
        var you_plate := PanelContainer.new()
        you_plate.name = "YouPlate"
        you_plate.add_theme_stylebox_override("panel", _inset_style())
        rail_box.add_child(you_plate)
        var you_box := VBoxContainer.new()
        you_box.add_theme_constant_override("separation", 5)
        you_plate.add_child(you_box)
        var you_name := Label.new()
        you_name.text = "YOU"
        you_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _pix(you_name, 7, RetroUI.MENU_MUTED)
        you_box.add_child(you_name)
        _fps_chip = _stat_line(you_box, "FPS")
        _ping_chip = _stat_line(you_box, "PNG")
        var ver := Label.new()
        ver.text = "v3.10"
        ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _pix(ver, 7, RetroUI.MENU_FAINT)
        rail_box.add_child(ver)

        # ---- content column: page header + pages ----
        var pad := MarginContainer.new()
        pad.name = "ContentPad"
        pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        pad.add_theme_constant_override("margin_left", 14)
        pad.add_theme_constant_override("margin_right", 14)
        pad.add_theme_constant_override("margin_top", 12)
        pad.add_theme_constant_override("margin_bottom", 12)
        body.add_child(pad)
        var content := VBoxContainer.new()
        content.add_theme_constant_override("separation", 10)
        pad.add_child(content)
        var header := HBoxContainer.new()
        header.add_theme_constant_override("separation", 8)
        content.add_child(header)
        _people_title = Label.new()
        _people_title.text = "PEOPLE"
        _pix(_people_title, 10, RetroUI.MENU_INK)
        header.add_child(_people_title)
        header.add_child(_spacer())
        _time_label = Label.new()
        _pix(_time_label, 8, RetroUI.MENU_MUTED)
        header.add_child(_time_label)

        var pages := Control.new()
        pages.custom_minimum_size = Vector2(0, 396)
        content.add_child(pages)

        # PEOPLE page — the card GRID: portrait + name + live ping/fps
        _players_tab = VBoxContainer.new()
        _players_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
        pages.add_child(_players_tab)
        var scroll := ScrollContainer.new()
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        # v3.10 FIX: inside the tab's VBox the scroll collapsed to height 0
        # (VBox hands out MINIMUM heights) — the whole card grid was clipped
        # into nothing. Expand to own the page.
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
        _players_tab.add_child(scroll)
        _players_grid = GridContainer.new()
        _players_grid.name = "PeopleGrid"
        _players_grid.columns = 3
        _players_grid.add_theme_constant_override("h_separation", 10)
        _players_grid.add_theme_constant_override("v_separation", 10)
        _players_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(_players_grid)

        # SETTINGS page — the same controls in the client's quiet voice
        _settings_tab = _build_settings_tab()
        _settings_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
        _settings_tab.visible = false
        pages.add_child(_settings_tab)

        var set_tab := func(tab: String) -> void:
                _players_tab.visible = tab == "players"
                _settings_tab.visible = tab == "settings"
                _style_nav(people_nav, tab == "players")
                _style_nav(settings_nav, tab == "settings")
        people_nav.pressed.connect(func() -> void: set_tab.call("players"))
        settings_nav.pressed.connect(func() -> void: set_tab.call("settings"))
        _menu_switch = set_tab

        # ---- footer: the action keycaps + the keycap hint bar ----
        root.add_child(_menu_footer())
        set_tab.call("players")
        return overlay

## The menu's ONE pixel voice — every label goes through here, so the
## player list, hint bar and settings all speak Press Start 2P consistently.
func _pix(l: Label, size: int, color: Color) -> void:
        var f: Font = RetroUI.pixel_font()
        if f != null:
                l.add_theme_font_override("font", f)
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", color)


## One hotkey chip for the menu's bottom bar — a bevel keycap plus a muted
## action word next to it.
func _hint_chip(row: HBoxContainer, key: String, action: String) -> void:
        var cap := PanelContainer.new()
        cap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        cap.add_theme_stylebox_override("panel", RetroUI.bevel_texture(RetroUI.MENU_EDGE_HI))
        var kl := Label.new()
        kl.text = key
        _pix(kl, 8, Color.WHITE)
        cap.add_child(kl)
        row.add_child(cap)
        var al := Label.new()
        al.text = action
        _pix(al, 8, RetroUI.MENU_MUTED)
        row.add_child(al)


# ---- v3.9 classic client pieces ------------------------------------------

## The title bar: your wordmark straight on ink (no wooden sign — it's gone
## for good), the place name, and a classic red X key that resumes.
func _menu_title_bar() -> PanelContainer:
        var bar := PanelContainer.new()
        bar.name = "TitleBar"
        bar.add_theme_stylebox_override("panel", _title_bar_style())
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        bar.add_child(row)
        var wm_path := "res://assets/ui/wordmark.png"
        if ResourceLoader.exists(wm_path):
                var wm := TextureRect.new()
                wm.texture = load(wm_path)
                wm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                wm.custom_minimum_size = Vector2(132, 20)
                wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
                row.add_child(wm)
        else:
                var t := Label.new()
                t.text = "RETROBLOX"
                _pix(t, 10, RetroUI.MENU_RED)
                row.add_child(t)
        row.add_child(_spacer())
        var place_l := Label.new()
        place_l.name = "PlaceName"
        place_l.text = String(place.get("name", "a classic place")).to_upper()
        _pix(place_l, 8, RetroUI.MENU_MUTED)
        row.add_child(place_l)
        var close := Button.new()
        close.text = "X"
        close.custom_minimum_size = Vector2(32, 26)
        close.focus_mode = Control.FOCUS_NONE
        close.tooltip_text = "Resume (ESC)"
        close.add_theme_stylebox_override("normal", _gloss_btn(RetroUI.MENU_RED))
        close.add_theme_stylebox_override("hover", _gloss_btn(RetroUI.MENU_RED_HI))
        close.add_theme_stylebox_override("pressed", _gloss_btn(Color("8f1410"), true))
        for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                close.add_theme_color_override(st, Color.WHITE)
        close.add_theme_constant_override("outline_size", 2)
        close.add_theme_color_override("font_outline_color", RetroUI.INK_OUTLINE)
        close.add_theme_font_size_override("font_size", 8)
        close.pressed.connect(_toggle_menu)
        row.add_child(close)
        return bar


## The footer: the four action keys are GLOSSY gradient caps now — Resume
## is the classic green Play gloss (shine band + bold ink outline + white
## outlined text), Leave wears the red gloss, Reset/Log Out stay steel —
## plus the keycap hint bar underneath.
func _menu_footer() -> PanelContainer:
        var foot := PanelContainer.new()
        foot.name = "MenuFooter"
        foot.add_theme_stylebox_override("panel", _footer_style())
        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 7)
        foot.add_child(col)
        var actions := HBoxContainer.new()
        actions.add_theme_constant_override("separation", 8)
        col.add_child(actions)
        actions.add_child(_action_button("Resume", "play",
                Color("2fbf4f"), Color("3fd462"), Color("23863c"), _toggle_menu, 0, true))
        actions.add_child(_action_button("Reset Character", "reset",
                Color("4d566c"), Color("5d6880"), Color("3a4254"),
                func() -> void:
                        _toggle_menu()
                        if player.alive:
                                player.die(self)
                        _start_respawn(), 158))
        actions.add_child(_action_button("Leave", "door",
                Color("b3261e"), Color("d13a30"), Color("8f1d17"), _leave_game, 112))
        actions.add_child(_action_button("Log Out", "power",
                Color("4d566c"), Color("5d6880"), Color("3a4254"),
                func() -> void:
                        Api.clear_session()
                        Session.reset()
                        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
                        get_tree().change_scene_to_file("res://scenes/login.tscn"), 112))
        var hints := HBoxContainer.new()
        hints.alignment = BoxContainer.ALIGNMENT_CENTER
        hints.add_theme_constant_override("separation", 5)
        col.add_child(hints)
        _hint_chip(hints, "ENTER", "chat")
        _hint_chip(hints, "ESC", "resume")
        _hint_chip(hints, "R", "menu")
        _hint_chip(hints, "L", "leave")
        return foot


func _action_button(text: String, icon_kind: String, bg: Color, hover_bg: Color, pressed_bg: Color, handler: Callable, min_w := 0, expand := false) -> Button:
        var b := Button.new()
        b.text = text
        b.icon = RetroUI.icon_texture(icon_kind)
        b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        if expand:
                b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size = Vector2(maxi(min_w, 0), 46)
        b.focus_mode = Control.FOCUS_NONE
        # the classic GLOSS: shine band + bold ink outline + white outlined text
        b.add_theme_stylebox_override("normal", _gloss_btn(bg))
        b.add_theme_stylebox_override("hover", _gloss_btn(hover_bg))
        b.add_theme_stylebox_override("pressed", _gloss_btn(pressed_bg, true))
        for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                b.add_theme_color_override(st, Color.WHITE)
        b.add_theme_constant_override("outline_size", 2)
        b.add_theme_color_override("font_outline_color", RetroUI.INK_OUTLINE)
        b.add_theme_font_size_override("font_size", 10)
        b.pressed.connect(handler)
        return b


func _nav_button(text: String, icon_kind: String) -> Button:
        var b := Button.new()
        b.text = text
        b.icon = RetroUI.icon_texture(icon_kind)
        b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.custom_minimum_size = Vector2(0, 40)
        b.focus_mode = Control.FOCUS_NONE
        b.add_theme_font_size_override("font_size", 8)
        _style_nav(b, false)
        return b


## The nav rail's voice: white ink on both states (the old SETTINGS tab used
## to drown into the card — that complaint is dead), a red notch on the left
## edge marks the open page, and the OPEN page wears a steel-gloss gradient
## chip with a bold ink outline.
func _style_nav(b: Button, on: bool) -> void:
        b.set_pressed_no_signal(on)
        if on:
                var gloss: StyleBoxTexture = RetroUI.gloss_texture(Color("46506a"))
                gloss.content_margin_left = 10.0
                gloss.content_margin_right = 8.0
                gloss.content_margin_top = 8.0
                gloss.content_margin_bottom = 8.0
                b.add_theme_stylebox_override("normal", gloss)
                b.add_theme_stylebox_override("hover", gloss)
                b.add_theme_stylebox_override("pressed", gloss)
                b.add_theme_stylebox_override("hover_pressed", gloss)
        else:
                var normal := StyleBoxFlat.new()
                normal.bg_color = Color(0, 0, 0, 0)
                normal.border_width_left = 3
                normal.border_color = Color(0, 0, 0, 0)
                normal.content_margin_left = 10.0
                normal.content_margin_right = 8.0
                normal.content_margin_top = 10.0
                normal.content_margin_bottom = 10.0
                var hover := normal.duplicate()
                hover.bg_color = RetroUI.MENU_PANEL_HI
                b.add_theme_stylebox_override("normal", normal)
                b.add_theme_stylebox_override("hover", hover)
                b.add_theme_stylebox_override("pressed", normal)
                b.add_theme_stylebox_override("hover_pressed", normal)
        b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
                b.add_theme_color_override(st, RetroUI.MENU_INK)
        # the red open-page notch rides ON the gloss chip (styleboxes can't border)
        var notch := b.get_node_or_null("NavNotch")
        if on and notch == null:
                var bar := ColorRect.new()
                bar.name = "NavNotch"
                bar.color = RetroUI.MENU_RED
                bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
                bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
                bar.offset_right = 3.0
                bar.offset_left = 0.0
                b.add_child(bar)
        elif not on and notch != null:
                notch.queue_free()


## One "TITLE value" line for the YOU plate — returns the value label.
func _stat_line(parent: VBoxContainer, title: String) -> Label:
        var row := HBoxContainer.new()
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 6)
        parent.add_child(row)
        var t := Label.new()
        t.text = title
        _pix(t, 7, RetroUI.MENU_FAINT)
        row.add_child(t)
        var v := Label.new()
        v.name = "Value"
        v.text = "—"
        _pix(v, 8, RetroUI.MENU_INK)
        row.add_child(v)
        return v


func _spacer() -> Control:
        var c := Control.new()
        c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        c.size_flags_vertical = Control.SIZE_EXPAND_FILL
        c.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return c


# ---- the player CARD — portrait + name + live ping/fps --------------------

## One People-page card. `ping` / `fps` may be null (no data yet) — the stat
## line reads "—". My own card wears the red ring.
func _player_card(uid: String, uname: String, is_me: bool, ping: Variant, fps: Variant) -> PanelContainer:
        var card := PanelContainer.new()
        card.name = "Card_" + uid
        card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_theme_stylebox_override("panel", _card_casing(is_me))
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 6)
        card.add_child(box)

        # the portrait well: checker floor, real avatar shot dropped in when
        # the render lands (head icon holds the seat until then)
        var well := PanelContainer.new()
        well.add_theme_stylebox_override("panel", _well_texture_style())
        well.custom_minimum_size = Vector2(0, 150)
        well.mouse_filter = Control.MOUSE_FILTER_IGNORE
        box.add_child(well)
        var portrait := TextureRect.new()
        portrait.name = "Portrait"
        portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        portrait.custom_minimum_size = Vector2(0, 142)
        portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
        portrait.texture = RetroUI.head_icon()
        well.add_child(portrait)
        _portrait_nodes[uid] = portrait

        var name_l := Label.new()
        name_l.text = uname + ("  (YOU)" if is_me else "")
        name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_l.clip_text = true
        name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        _pix(name_l, 8, RetroUI.MENU_INK if is_me else RetroUI.MENU_MUTED)
        box.add_child(name_l)

        var stats := Label.new()
        stats.name = "Stats"
        stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        stats.text = _card_stats_text(ping, fps)
        _pix(stats, 7, RetroUI.MENU_FAINT)
        box.add_child(stats)
        if is_me:
                _my_card_stats = stats
        return card


func _card_casing(is_me: bool) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.MENU_PANEL
        sb.set_border_width_all(3)   # BOLD outlines, the old-site way
        sb.border_color = RetroUI.MENU_RED if is_me else RetroUI.MENU_EDGE_HI
        sb.content_margin_left = 6.0
        sb.content_margin_right = 6.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 8.0
        return sb


func _well_texture_style() -> StyleBoxTexture:
        var sb := StyleBoxTexture.new()
        sb.texture = RetroUI.checker_texture()
        sb.content_margin_left = 4.0
        sb.content_margin_right = 4.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


func _card_stats_text(ping: Variant, fps: Variant) -> String:
        var p := "—"
        if ping != null and int(ping) > 0:
                p = "%dms" % int(ping)
        var f := "—"
        if fps != null and int(fps) > 0:
                f = str(int(fps))
        return "PNG %s  FPS %s" % [p, f]


## Fire the portrait pipeline for one uid — cached texture drops in
## instantly, a render in flight is never doubled, and the fallback head
## icon holds the card until the real shot arrives.
func _render_portrait(uid: String) -> void:
        if _portrait_cache.has(uid):
                var cached: Texture2D = _portrait_cache[uid]
                if cached != null and _portrait_nodes.has(uid) and is_instance_valid(_portrait_nodes[uid]):
                        (_portrait_nodes[uid] as TextureRect).texture = cached
                return
        if _portrait_pending.has(uid):
                return
        _portrait_pending[uid] = true
        _portrait_worker(uid)


## The async half — gathers the avatar payload (cache first, platform
## second), renders offscreen, then swaps the texture into the live card.
func _portrait_worker(uid: String) -> void:
        var payload: Dictionary = {}
        var api = null
        if Session.is_guest and uid == Session.user_id:
                pass   # guests wear the classic noob paint — no network
        elif uid == Session.user_id:
                payload = Session.my_avatar_data()
                api = Api
        else:
                payload = Session.cached_avatar(uid)
                api = Api
                if payload.is_empty():
                        var res: Dictionary = await Api.avatar_of(uid)
                        if res.get("ok", false):
                                Session.cache_avatar(uid, res)
                                payload = res
        var tex: Texture2D = await AvatarPortraitScript.render(self, api, payload)
        _portrait_pending.erase(uid)
        if tex == null:
                return
        _portrait_cache[uid] = tex
        if _portrait_nodes.has(uid) and is_instance_valid(_portrait_nodes[uid]):
                (_portrait_nodes[uid] as TextureRect).texture = tex


## The menu's pulse: rail chips + header clock + my card stat line breathe
## every half second while the menu is open.
func _update_live_stats() -> void:
        var fps := Engine.get_frames_per_second()
        if fps > 0:
                _fps_smooth = lerpf(_fps_smooth, float(fps), 0.35)
        if _fps_chip != null and is_instance_valid(_fps_chip):
                _fps_chip.text = str(int(roundf(_fps_smooth)))
        if _ping_chip != null and is_instance_valid(_ping_chip):
                _ping_chip.text = ("%dms" % _last_ping_ms) if _last_ping_ms > 0 else "—"
        if _time_label != null and is_instance_valid(_time_label):
                _time_label.text = "TIME %s" % _clock_text()
        if _my_card_stats != null and is_instance_valid(_my_card_stats):
                _my_card_stats.text = _card_stats_text(_last_ping_ms, int(_fps_smooth))


func _clock_text() -> String:
        var secs := int((Time.get_ticks_msec() - _session_start_ms) / 1000.0)
        return "%02d:%02d" % [floori(secs / 60.0), secs % 60]


# ---- the client's one-voice surfaces --------------------------------------

## The window: the authentic 2011 rounded plate (bold outline baked into
## the texture), flat ink fallback when the archive texture is missing.
func _client_style() -> StyleBox:
        var plate: StyleBoxTexture = RetroUI.client_plate()
        if plate != null:
                plate.content_margin_left = 5.0
                plate.content_margin_right = 5.0
                plate.content_margin_top = 5.0
                plate.content_margin_bottom = 5.0
                return plate
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.MENU_BG
        sb.set_border_width_all(3)
        sb.border_color = RetroUI.INK_OUTLINE
        sb.set_corner_radius_all(10)
        sb.content_margin_left = 4.0
        sb.content_margin_right = 4.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


func _title_bar_style() -> StyleBox:
        # banded gradient bar, light lip on top + hard dark edge below
        return RetroUI.gradient_panel(Color("272c3a"), Color("171a23"), RetroUI.MENU_EDGE_DARK, Color("3a4152"))


func _rail_style() -> StyleBox:
        # gradient rail with a BOLD dark right edge separating it from the page
        return RetroUI.gradient_panel(Color("20242f"), Color("14161d"), Color(0, 0, 0, 0), Color(0, 0, 0, 0), RetroUI.MENU_EDGE_DARK)


func _footer_style() -> StyleBox:
        return RetroUI.gradient_panel(Color("20242f"), Color("14161d"), Color(0, 0, 0, 0), RetroUI.MENU_EDGE_DARK)


func _inset_style() -> StyleBox:
        var sb := RetroUI.gradient_panel(Color("1b1e27"), Color("101218"))
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


## The gloss button wrapper — content margins tuned for chunky caps.
func _gloss_btn(bg: Color, pushed := false) -> StyleBoxTexture:
        var sb: StyleBoxTexture = RetroUI.gloss_texture(bg, pushed)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 7.0 if pushed else 9.0
        return sb


## Leave the place — with the hub retired, Leave rejoins the classic place
## fresh (a full scene reload). The menu's L shortcut lands here too.
func _leave_game() -> void:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        get_tree().change_scene_to_file("res://scenes/game.tscn")


var _menu_switch: Callable = func(_t: String) -> void: pass


func _open_menu(tab: String) -> void:
        if not _menu_open:
                _toggle_menu()
        if _menu_open:
                _menu_switch.call(tab)


## The settings page: mouse, camera, audio, graphics — saved to disk and
## applied live. Plus the classic Animations buttons for the rig's clips.
func _build_settings_tab() -> VBoxContainer:
        var tab := VBoxContainer.new()
        tab.add_theme_constant_override("separation", 6)
        var settings: Node = get_node_or_null("/root/Settings")

        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        tab.add_child(row)

        # left column: sliders
        var left := VBoxContainer.new()
        left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        left.add_theme_constant_override("separation", 7)
        row.add_child(left)

        _slider_row(left, "Mouse sensitivity", 0.1, 3.0,
                float(settings.get("mouse_sensitivity")) if settings != null else 1.0,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("mouse_sensitivity", v))
        _slider_row(left, "Camera FOV", 40.0, 110.0,
                float(settings.get("fov")) if settings != null else 70.0,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("fov", v))
        _slider_row(left, "Master volume", 0.0, 1.0,
                float(settings.get("master_volume")) if settings != null else 1.0,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("master_volume", v))
        _slider_row(left, "Sound effects", 0.0, 1.0,
                float(settings.get("sfx_volume")) if settings != null else 1.0,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("sfx_volume", v))

        # right column: toggles + animations
        var right := VBoxContainer.new()
        right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        right.add_theme_constant_override("separation", 7)
        row.add_child(right)

        var shadows := CheckButton.new()
        shadows.text = "Sun shadows"
        shadows.button_pressed = bool(settings.get("shadows")) if settings != null else true
        shadows.focus_mode = Control.FOCUS_NONE
        shadows.toggled.connect(func(on: bool) -> void:
                if settings != null:
                        settings.set_key("shadows", on))
        right.add_child(shadows)

        var fullscreen := CheckButton.new()
        fullscreen.text = "Fullscreen"
        fullscreen.button_pressed = bool(settings.get("fullscreen")) if settings != null else false
        fullscreen.focus_mode = Control.FOCUS_NONE
        fullscreen.toggled.connect(func(on: bool) -> void:
                if settings != null:
                        settings.set_key("fullscreen", on))
        right.add_child(fullscreen)

        var shift := CheckButton.new()
        shift.text = "Shift lock (also SHIFT key)"
        shift.button_pressed = bool(settings.get("shift_lock")) if settings != null else false
        shift.focus_mode = Control.FOCUS_NONE
        shift.toggled.connect(func(on: bool) -> void:
                if settings != null:
                        settings.set_key("shift_lock", on)
                camera_rig.shift_locked = on)
        right.add_child(shift)
        _shift_check = shift

        var anim_title := Label.new()
        anim_title.text = "Animations"
        _pix(anim_title, 9, RetroUI.MENU_MUTED)
        right.add_child(anim_title)
        var grid := GridContainer.new()
        grid.columns = 3
        grid.add_theme_constant_override("h_separation", 4)
        grid.add_theme_constant_override("v_separation", 4)
        right.add_child(grid)
        for anim in ["Sit", "Climb", "Walk", "Jump", "Idle", "Stop"]:
                var b := Button.new()
                b.text = anim
                b.custom_minimum_size = Vector2(64, 28)
                b.focus_mode = Control.FOCUS_NONE
                b.add_theme_stylebox_override("normal", _bevel_btn(Color("3a4050")))
                b.add_theme_stylebox_override("hover", _bevel_btn(Color("4a5164")))
                b.add_theme_stylebox_override("pressed", _bevel_btn(Color("2b303c"), true))
                b.add_theme_color_override("font_color", Color.WHITE)
                b.add_theme_font_size_override("font_size", 9)
                var clip: String = "" if anim == "Stop" else anim
                b.pressed.connect(func() -> void:
                        if player != null and is_instance_valid(player):
                                player.avatar.call("play_emote", clip))
                grid.add_child(b)
        # v3.8: the settings page speaks the same pixel voice as everything else
        var pix: Font = RetroUI.pixel_font()
        if pix != null:
                for cb in [shadows, fullscreen, shift]:
                        cb.add_theme_font_override("font", pix)
                        cb.add_theme_font_size_override("font_size", 8)
        # v3.9: white ink on the dark client — readable toggles
        for cb in [shadows, fullscreen, shift]:
                cb.add_theme_color_override("font_color", RetroUI.MENU_INK)
                cb.add_theme_color_override("font_hover_color", RetroUI.MENU_INK)
                cb.add_theme_color_override("font_pressed_color", RetroUI.MENU_INK)
        return tab


func _slider_row(parent: VBoxContainer, label_text: String, minv: float, maxv: float, value: float, on_change: Callable) -> void:
        var l := Label.new()
        l.text = "%s  —  %.2f" % [label_text, value]
        _pix(l, 8, RetroUI.MENU_MUTED)
        parent.add_child(l)
        var s := HSlider.new()
        s.min_value = minv
        s.max_value = maxv
        s.step = 0.01
        s.value = value
        s.custom_minimum_size = Vector2(0, 20)
        s.focus_mode = Control.FOCUS_NONE
        s.value_changed.connect(func(v: float) -> void:
                l.text = "%s  —  %.2f" % [label_text, v]
                on_change.call(v))
        parent.add_child(s)


## v3.9 RETRO KEYCAP — a TRUE bevel: the face is drawn pixel by pixel
## (near-black outline, LIGHT top/left edge, DARK bottom/right edge — the
## raised 2006 keycap) and `pushed` flips the bevel so the key sinks.
func _bevel_btn(bg: Color, pushed := false) -> StyleBoxTexture:
        var sb: StyleBoxTexture = RetroUI.bevel_texture(bg, pushed)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 7.0 if pushed else 9.0
        return sb


func _toggle_menu() -> void:
        if _menu == null or not is_instance_valid(_menu):
                return
        _menu_open = not _menu_open
        _menu.visible = _menu_open
        if _menu_open:
                camera_rig.set_ui_blocked(true)
                _refresh_player_list([])
                _update_live_stats()
        else:
                camera_rig.set_ui_blocked(false)


# ---------------------------------------------------------------- events

func _on_health_changed(hp: float, max_hp: float) -> void:
        var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
        _health_value.text = str(int(roundf(hp)))
        var c := Color("e2231a").lerp(Color("3fd432"), ratio)
        _health_fill.color = c
        # the vertical bar drains from the top
        _health_fill.offset_top = -150.0 * ratio


func _on_health_depleted() -> void:
        if not _respawning:
                _start_respawn()


func _on_touched_group(group: String, node: Node3D) -> void:
        if group == "kill" and player.alive:
                player.die(self)
                chat.add_system("Oof!")
                _start_respawn()
        elif group == "checkpoint":
                var pos: Variant = node.get_meta("spawn", null)
                if pos is Vector3:
                        player.spawn_point = Transform3D(Basis(), pos)
                        chat.add_system("Checkpoint reached!")
        elif group == "goal" and not _finished:
                _finished = true
                chat.add_system("*** You reached the goal — classic victory! ***")


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


# ---------------------------------------------------------------- chat + presence

func _on_chat_submit(text: String) -> void:
        var trimmed := text.strip_edges()
        if trimmed.begins_with("/"):
                _handle_command(trimmed)
                return
        if Session.is_guest:
                chat.add_system("Guests watch chat — sign up on retro-blox.vercel.app to talk!")
                return
        var res: Dictionary = await Api.place_chat_send(String(place["id"]), trimmed)
        if res.get("ok", false) and res.get("message", null) is Dictionary:
                var msg: Dictionary = res["message"]
                _ingest_message(msg)
        else:
                chat.add_system(String(res.get("error", "Could not send the message.")))


## Local chat commands — they never leave the client.
func _handle_command(command: String) -> void:
        var parts := command.split(" ", false)
        var cmd := String(parts[0]).to_lower()
        if cmd == "/help":
                chat.add_system("Commands: /e sit · /e stop · /help")
                chat.add_system("SHIFT = shift lock · SPACE jumps off ladders · P = players")
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
        # v3.8: the round-trip of this poll IS the ping readout
        var t0 := Time.get_ticks_msec()
        var res: Dictionary = await Api.place_chat_get(String(place["id"]))
        _last_ping_ms = int(Time.get_ticks_msec() - t0)
        if not res.get("ok", false):
                return
        for msg in res.get("messages", []):
                _ingest_message(msg)
        _reconcile_players(res.get("players", []))


func _ingest_message(msg: Dictionary) -> void:
        var id := String(msg.get("id", ""))
        if id == "" or _seen_messages.has(id):
                return
        _seen_messages[id] = true
        var uid := String(msg.get("userId", ""))
        var uname := String(msg.get("username", "?"))
        var seq := int(msg.get("seqId", 0)) if msg.get("seqId") != null else 0
        var text := String(msg.get("text", ""))
        chat.add_chat(uname, seq, text, "", uid == Session.user_id)
        # the classic bubble pops over the speaker's head
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
                if uid == "" or uid == Session.user_id:
                        continue
                seen[uid] = true
                # v3.9: pocket everyone's live ping/fps for the People cards
                _remote_stats[uid] = {
                        "ping": p.get("ping", null),
                        "fps": p.get("fps", null),
                }
                var pos_arr: Array = p.get("pos", [0, 0, 0])
                var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
                if _remotes.has(uid):
                        _remotes[uid].update_state(pos, float(p.get("heading", 0.0)))
                else:
                        var rp := RemotePlayerScript.new()
                        add_child(rp)
                        rp.setup(uid, String(p.get("username", "Player")))
                        rp.update_state(pos, float(p.get("heading", 0.0)))
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
                        _remote_stats.erase(uid)
        _refresh_player_list(players)


func _dress_remote(rp: Node3D, uid: String) -> void:
        var res: Dictionary = await Api.avatar_of(uid)
        if res.get("ok", false) and is_instance_valid(rp):
                Session.cache_avatar(uid, res)
                await rp.dress(Api, res)


## The People page: a GRID of cards — me first (red ring), then everyone
## the presence feed reports. Rebuilt per poll; portraits come from cache
## or start their async render.
func _refresh_player_list(players: Array) -> void:
        if _players_grid == null or not is_instance_valid(_players_grid):
                return
        _portrait_nodes.clear()
        for child in _players_grid.get_children():
                child.queue_free()
        var total := 1 + players.size()
        if _people_title != null and is_instance_valid(_people_title):
                _people_title.text = "PEOPLE — %d ONLINE" % total
        # my card first — the red-ringed one
        _players_grid.add_child(_player_card(Session.user_id, Session.username, true,
                _last_ping_ms, int(_fps_smooth)))
        _render_portrait(Session.user_id)
        for p in players:
                var uid := String(p.get("userId", ""))
                var uname := String(p.get("username", ""))
                if uid == "" or uid == Session.user_id or uname == "":
                        continue
                var st: Dictionary = _remote_stats.get(uid, {})
                _players_grid.add_child(_player_card(uid, uname, false,
                        st.get("ping", null), st.get("fps", null)))
                _render_portrait(uid)
        _update_live_stats()
