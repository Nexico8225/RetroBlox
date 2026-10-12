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

const POLL_SECONDS := 2.5       # chat + presence feed
const HEARTBEAT_SECONDS := 4.0  # my presence out
const RESPAWN_SECONDS := 2.0    # v4.0: snappier classic respawn (was 2.8)

var place: Dictionary
var player            # LocalPlayer — untyped: custom members, dynamic calls
var camera_rig        # CameraRig
var chat              # ChatBox
var hud: CanvasLayer

var _health_fill: Panel              # v6.0: the rounded green fill inside the track
var _health_value: Label
var _topbar_pfp: TextureRect         # v8.0: the topbar user pill's PFP
var _names_by_uid: Dictionary = {}   # v8.0: userId -> username (PFP fetches)
var _health_track_w := 190.0         # v6.0: the bottom-center bar width
var _menu: Control
var _players_grid: GridContainer     # v3.9: the People page — a card grid, not a list
var _settings_tab: VBoxContainer
var _people_title: Label             # v9.0: "In this server · N" page heading
var _time_label: Label               # v3.9: live session clock in the page header
var _corner_stats: Label             # v9.0: the tiny FPS/ping/version chip (bottom-left)
var _my_card_stats: Label            # v3.9: the stat line on my own card
var _tab_buttons: Dictionary = {}    # v9.0: tab id -> Button (top tabs)
var _pages: Dictionary = {}          # v9.0: tab id -> page Control
var _pfp_preview: TextureRect        # v9.0: MY PICTURE preview in Settings
var _pfp_url_edit: LineEdit          # v9.0: the PFP URL field (Settings)
var _fps_smooth := 60.0              # v3.9: eased fps so the chip doesn't flicker
var _menu_tick := 0.5                # v3.9: live stats refresh cadence
var _remote_stats: Dictionary = {}   # v3.9: userId -> {"ping": int, "fps": int}
var _people_total := 1               # v4.0: last known online count (header)
var _portrait_cache: Dictionary = {} # v3.9: userId -> rendered avatar Texture2D
var _portrait_nodes: Dictionary = {} # v3.9: userId -> the card TextureRect to swap when ready
var _portrait_pending: Dictionary = {} # v3.9: renders already in flight
var _remotes: Dictionary = {}      # userId -> RemotePlayer
var _seen_messages: Dictionary = {} # message id -> true
var _chat_history_done := false     # v3.11: the first feed is history, not new lines
var _dressed_signature := ""       # v4.0: JSON of the avatar payload my rig wears
var _last_presence: Array = []     # v4.0: newest presence snapshot — the menu opens on it
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

        # ---- v9.0: MY PICTURE — the account's avatarUrl from
        # retro-blox.vercel.app arrives with the /me payload at login; the
        # Editor's own custom URL (saved in ui_config) wins over it.
        # Api.txt is null-safe: the platform returns "avatarUrl": null for
        # accounts without a site PFP, and String(null) hard-crashes.
        if not Session.is_guest:
                Pfp.set_site_pfp(Api.txt(Session.avatar.get("avatarUrl", "")))
        Pfp.pfp_changed.connect(func(_uid: String) -> void:
                _portrait_cache.erase(Session.user_id)
                _render_portrait(Session.user_id))
        UiEditor.edit_mode_changed.connect(func(on: bool) -> void:
                if on:
                        camera_rig.set_ui_blocked(true)
                elif not _menu_open and not chat.is_open:
                        camera_rig.set_ui_blocked(false))

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


## The v5.0 loading veil: midnight + your wordmark + a status line. It
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
        status.text = "Loading the classic place…"
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
                        Session.set_avatar(me)
                        payload = Session.my_avatar_data()
        _dressed_signature = JSON.stringify(payload)
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
                # v3.11: ESC closes READ MODE first — the menu toggle comes after
                if chat.is_reading:
                        chat.close_read()
                else:
                        _toggle_menu()
                get_viewport().set_input_as_handled()
        elif event.is_action_pressed("ui_text_submit") or (event is InputEventKey and event.is_pressed() and not event.is_echo() and ((event as InputEventKey).keycode == KEY_ENTER or (event as InputEventKey).keycode == KEY_SLASH)):
                # v6.0: the classic SLASH opens the chat too (the real client's
                # "press / key" promise on the input bar)
                if not _menu_open and chat != null and is_instance_valid(chat) and not chat.is_open:
                        chat.open()
                        camera_rig.set_ui_blocked(true)
                        get_viewport().set_input_as_handled()
        elif event is InputEventKey and event.is_pressed() and not event.is_echo() \
                        and (event as InputEventKey).keycode == KEY_F and not _menu_open \
                        and not chat.is_open:
                # v3.11: F READS the chat — log only, keyboard stays free,
                # you keep moving. F again (or ESC) hides it.
                chat.toggle_read()
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
                # (camera_rig builds across _ready's awaited frames — it can
                # still be Nil when input lands, so guard like the branches above)
                if camera_rig != null and is_instance_valid(camera_rig):
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

## The HUD in the midnight voice: a dark rounded TOPBAR PILL (logo /
## chat with unread badge) top-left, a VERTICAL HEALTH BAR on the right,
## join toasts top-center, dark translucent chat top-left, and the midnight
## arcade ESC menu in the center.
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
        UiEditor.register("chat", chat, false)

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
        UiEditor.register("toasts", _toast_box, false)

        # ---- center: esc menu with Players + Settings tabs ----
        _menu = _build_menu()
        # the shared retro theme never reaches a CanvasLayer on its own —
        # hand it over so the menu buttons speak in the pixel voice too
        _menu.theme = RetroUI.shared
        hud.add_child(_menu)


# ---- topbar pills -------------------------------------------------------

func _build_topbar() -> void:
        # ---- v9.0: the REAL CLIENT's top-left cluster (the reference read):
        # three separate rounded dark keys with a small gap — the logo, the
        # hamburger, the chat bubble with its unread badge. Each opens what
        # the real client opens: the menu, the menu, the chat.
        var cluster := HBoxContainer.new()
        cluster.name = "Topbar"
        cluster.position = Vector2(12, 12)
        cluster.add_theme_constant_override("separation", 6)
        hud.add_child(cluster)

        # the logo key — the tilted square (opens the menu, like the real one)
        var logo_btn := _topbar_key()
        logo_btn.tooltip_text = "Menu (ESC)"
        logo_btn.icon = load("res://assets/icons/logo.png")
        logo_btn.pressed.connect(func() -> void: _toggle_menu())
        cluster.add_child(logo_btn)

        # the hamburger key — the REAL internet icon PNG (Pixabay, white ink)
        var burger_btn := _topbar_key()
        burger_btn.tooltip_text = "Menu (ESC)"
        burger_btn.icon = RetroUI.icon_png("menu", RetroUI.MENU_INK)
        burger_btn.pressed.connect(func() -> void: _toggle_menu())
        cluster.add_child(burger_btn)

        # the chat key — the REAL internet icon PNG (Icons8) + the red badge
        var chat_btn := _topbar_key()
        chat_btn.tooltip_text = "Chat (ENTER)"
        chat_btn.icon = RetroUI.icon_png("chat", RetroUI.MENU_INK)
        chat_btn.pressed.connect(func() -> void:
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
        badge_panel.offset_left = -6.0
        badge_panel.offset_right = 10.0
        badge_panel.offset_top = -8.0
        badge_panel.offset_bottom = 8.0
        badge_panel.add_child(_chat_badge)
        badge_holder.add_child(badge_panel)
        _chat_badge_panel = badge_panel
        badge_panel.visible = false   # no unread yet — no red dot
        cluster.add_child(chat_btn)
        UiEditor.register("topbar", cluster, false)

        # ---- v9.0: the TOP-RIGHT USER PILL — PFP + name + the settings
        # gear, parked exactly where the real client keeps them
        var user_pill := PanelContainer.new()
        user_pill.name = "UserPill"
        user_pill.add_theme_stylebox_override("panel", _pill_style())
        user_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        user_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        user_pill.offset_right = -12.0
        user_pill.offset_top = 12.0
        hud.add_child(user_pill)
        var urow := HBoxContainer.new()
        urow.add_theme_constant_override("separation", 6)
        user_pill.add_child(urow)
        # v8.0: YOUR REAL PFP leads the pill — the client's identity read
        var pfp_rect := TextureRect.new()
        pfp_rect.name = "UserPfp"
        pfp_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        pfp_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        pfp_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        pfp_rect.custom_minimum_size = Vector2(26, 26)
        pfp_rect.texture = RetroUI.head_icon()
        pfp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        urow.add_child(pfp_rect)
        _topbar_pfp = pfp_rect
        _names_by_uid[Session.user_id] = Session.username
        _render_portrait(Session.user_id)
        var uname := Label.new()
        uname.name = "UserName"
        uname.text = Session.username
        uname.add_theme_font_override("font", RetroUI.gotham(600))
        uname.add_theme_font_size_override("font_size", 13)
        uname.add_theme_color_override("font_color", RetroUI.MENU_INK)
        uname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        urow.add_child(uname)
        var gear_btn := Button.new()
        gear_btn.custom_minimum_size = Vector2(34, 34)
        gear_btn.focus_mode = Control.FOCUS_NONE
        gear_btn.tooltip_text = "Settings (ESC)"
        gear_btn.icon = RetroUI.icon_png("settings", RetroUI.MENU_MUTED)
        gear_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        gear_btn.expand_icon = true
        gear_btn.add_theme_stylebox_override("normal", _pill_btn_style(false))
        gear_btn.add_theme_stylebox_override("hover", _pill_btn_style(true))
        gear_btn.add_theme_stylebox_override("pressed", _pill_btn_style(true))
        gear_btn.pressed.connect(func() -> void: _open_menu("settings"))
        urow.add_child(gear_btn)
        UiEditor.register("user_pill", user_pill, false)


## One topbar key — the standalone rounded dark square the real client
## parks each HUD button in (black 65%, rounded 10, 42x34).
func _topbar_key() -> Button:
        var b := Button.new()
        b.custom_minimum_size = Vector2(42, 34)
        b.focus_mode = Control.FOCUS_NONE
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        b.expand_icon = true
        b.add_theme_stylebox_override("normal", _pill_btn_style(false))
        b.add_theme_stylebox_override("hover", _pill_btn_style(true))
        b.add_theme_stylebox_override("pressed", _pill_btn_style(true))
        return b


## The topbar pill (v10.0) — beveled translucent black, the old client's HUD.
func _pill_style() -> StyleBox:
        var sb := RetroUI.pill_style()
        sb.content_margin_left = 6.0
        sb.content_margin_right = 6.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


func _pill_btn_style(hover: bool) -> StyleBox:
        # beveled translucent HUD keys — the old client's topbar squares
        return RetroUI.raised(4, Color(0.0, 0.0, 0.0, 0.55)) if hover else RetroUI.raised(4, Color(0.0, 0.0, 0.0, 0.42))


func _badge_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.MENU_RED
        sb.set_corner_radius_all(8)
        sb.content_margin_left = 5.0
        sb.content_margin_right = 5.0
        sb.content_margin_top = 1.0
        sb.content_margin_bottom = 1.0
        return sb


# ---- the health BAR (bottom-center, the classic Roblox dock) ------------

func _build_health() -> void:
        # v6.0: the CLASSIC BOTTOM-CENTER health bar — a dark rounded track
        # with the green fill and the number inside, exactly where Roblox
        # has always parked it (the v5.0 right-edge plate is history)
        var track := Panel.new()
        track.name = "HealthBar"
        track.mouse_filter = Control.MOUSE_FILTER_IGNORE
        track.add_theme_stylebox_override("panel", _health_track_style())
        track.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        track.offset_left = -_health_track_w / 2.0
        track.offset_right = _health_track_w / 2.0
        track.offset_top = -30.0
        track.offset_bottom = -12.0
        hud.add_child(track)
        UiEditor.register("health", track, false)

        _health_fill = Panel.new()
        _health_fill.name = "Fill"
        _health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _health_fill.add_theme_stylebox_override("panel", RetroUI.raised(4, RetroUI.MENU_GREEN))
        _health_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
        _health_fill.offset_left = 3.0
        _health_fill.offset_top = 3.0
        _health_fill.offset_bottom = -3.0
        _health_fill.offset_right = -3.0
        track.add_child(_health_fill)

        _health_value = Label.new()
        _health_value.text = "100"
        _health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _health_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _health_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var num_font: Font = RetroUI.gotham(700)
        if num_font != null:
                _health_value.add_theme_font_override("font", num_font)
        _health_value.add_theme_font_size_override("font_size", 12)
        _health_value.add_theme_color_override("font_color", Color.WHITE)
        _health_value.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
        _health_value.add_theme_constant_override("shadow_offset_x", 0)
        _health_value.add_theme_constant_override("shadow_offset_y", 1)
        _health_value.set_anchors_preset(Control.PRESET_FULL_RECT)
        track.add_child(_health_value)


func _health_track_style() -> StyleBox:
        # v10.0: the sunken bevel track — the classic HUD health inset
        return RetroUI.sunken(4, Color(0.0, 0.0, 0.0, 0.72))


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
        pill.add_theme_stylebox_override("panel", _toast_style())
        var l := Label.new()
        l.text = text
        l.add_theme_font_size_override("font_size", 14)
        l.add_theme_color_override("font_color", RetroUI.MENU_INK)
        if RetroUI.source(400) != null:
                l.add_theme_font_override("font", RetroUI.source(400))
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


func _toast_style() -> StyleBox:
        # v8.0: the quiet black rounded toast
        var sb := RetroUI.glass(0.75)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
        return sb


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


# ---- the menu — the v11.0 BLACK GLASS CLIENT PANEL -------------------------
## The ESC menu is THE ROBLOX ESC MENU (the reference read): the game stays
## LIVE and VISIBLE behind a deep dim, and ONE centered BLACK GLASS panel
## (opacity, rounded, hairline edge) carries the two top tabs — People /
## Settings, wearing the REAL internet icons — the "In this server" card
## grid, and the footer keys [L] Leave / [R] Respawn / [ESC] Resume with
## Resume speaking the CLASSIC GREEN. NO fullscreen veil.


func _build_menu() -> Control:
        var overlay := Control.new()
        overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.visible = false

        # the soft dim — the world keeps breathing behind the panel
        var dim := ColorRect.new()
        dim.name = "Dim"
        dim.color = Color(0.0, 0.0, 0.0, 0.55)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.add_child(dim)

        # the centered panel — about 62% of the screen, never full-bleed
        var center := CenterContainer.new()
        center.name = "MenuCenter"
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.add_child(center)
        var panel := PanelContainer.new()
        panel.name = "MenuPanel"
        panel.custom_minimum_size = _menu_panel_size()
        panel.add_theme_stylebox_override("panel", _menu_panel_style())
        center.add_child(panel)

        var root := VBoxContainer.new()
        root.name = "MenuRoot"
        panel.add_child(root)

        # ---- THE TOP TABS — People · Settings (Gallery / Report / Help are
        # GONE — you asked). The tabs wear the REAL internet icon PNGs.
        var tabs := HBoxContainer.new()
        tabs.name = "Tabs"
        tabs.add_theme_constant_override("separation", 0)
        root.add_child(tabs)
        var tab_defs := [
                ["players", "People", "people"],
                ["settings", "Settings", "settings"],
        ]
        for td in tab_defs:
                var b := _tab_button(String(td[1]), String(td[2]))
                _tab_buttons[String(td[0])] = b
                tabs.add_child(b)

        # the 1px rule under the tab row (the client's quiet line)
        var rule := ColorRect.new()
        rule.name = "TabRule"
        rule.color = RetroUI.MENU_EDGE
        rule.custom_minimum_size = Vector2(0, 1)
        root.add_child(rule)

        # ---- the pages live in one margin box ----
        var body := MarginContainer.new()
        body.name = "MenuBody"
        body.size_flags_vertical = Control.SIZE_EXPAND_FILL
        body.add_theme_constant_override("margin_left", 22)
        body.add_theme_constant_override("margin_right", 22)
        body.add_theme_constant_override("margin_top", 14)
        body.add_theme_constant_override("margin_bottom", 10)
        root.add_child(body)
        var pages := Control.new()
        pages.name = "Pages"
        pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
        body.add_child(pages)

        # ---- PEOPLE — Invite Friends, "In this server", the card grid
        var players_page := VBoxContainer.new()
        players_page.name = "PeoplePage"
        players_page.set_anchors_preset(Control.PRESET_FULL_RECT)
        players_page.add_theme_constant_override("separation", 10)
        pages.add_child(players_page)
        _pages["players"] = players_page

        var invite := Button.new()
        invite.text = "Invite Friends"
        invite.icon = RetroUI.icon_texture("invite", RetroUI.MENU_INK)
        invite.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
        invite.custom_minimum_size = Vector2(0, 44)
        invite.focus_mode = Control.FOCUS_NONE
        invite.add_theme_stylebox_override("normal", _row_btn())
        invite.add_theme_stylebox_override("hover", _row_btn(RetroUI.MENU_PANEL_HI))
        invite.add_theme_stylebox_override("pressed", _row_btn(RetroUI.PANEL_DOWN, true))
        invite.add_theme_color_override("font_color", RetroUI.MENU_INK)
        invite.add_theme_color_override("font_hover_color", RetroUI.MENU_INK)
        invite.add_theme_color_override("font_pressed_color", RetroUI.MENU_INK)
        if RetroUI.gotham(600) != null:
                invite.add_theme_font_override("font", RetroUI.gotham(600))
        invite.add_theme_font_size_override("font_size", 14)
        invite.pressed.connect(func() -> void:
                _notify("Invite link copied — send retro-blox.vercel.app", true)
                DisplayServer.clipboard_set("https://retro-blox.vercel.app"))
        players_page.add_child(invite)

        var p_head := HBoxContainer.new()
        p_head.add_theme_constant_override("separation", 8)
        players_page.add_child(p_head)
        _people_title = Label.new()
        _people_title.text = "In this server"
        _title(_people_title, 17, RetroUI.MENU_INK)
        p_head.add_child(_people_title)
        p_head.add_child(_spacer())
        var grid_btn := _ghost_icon_btn("grid")
        var list_btn := _ghost_icon_btn("list")
        grid_btn.tooltip_text = "Grid view"
        list_btn.tooltip_text = "List view"
        grid_btn.pressed.connect(func() -> void: _players_grid.columns = 4)
        list_btn.pressed.connect(func() -> void: _players_grid.columns = 1)
        p_head.add_child(grid_btn)
        p_head.add_child(list_btn)

        var scroll := ScrollContainer.new()
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        # v3.10 FIX: inside the page's VBox the scroll collapsed to height 0
        # (VBox hands out MINIMUM heights) — expand to own the page.
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
        players_page.add_child(scroll)
        _players_grid = GridContainer.new()
        _players_grid.name = "PeopleGrid"
        _players_grid.columns = 4
        _players_grid.add_theme_constant_override("h_separation", 10)
        _players_grid.add_theme_constant_override("v_separation", 10)
        _players_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(_players_grid)

        # ---- SETTINGS — the game sliders + MY PICTURE + EDIT THIS UI
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

        # ---- the tiny corner chip (OUTSIDE the panel, bottom-left): the
        # live FPS/ping/version read the old menu parked in its rail
        _corner_stats = Label.new()
        _corner_stats.name = "CornerStats"
        _corner_stats.text = "—"
        _corner_stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
        _corner_stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
        _corner_stats.offset_left = 14.0
        _corner_stats.offset_top = -28.0
        _corner_stats.offset_bottom = -10.0
        _text(_corner_stats, 11, Color(1, 1, 1, 0.55))
        overlay.add_child(_corner_stats)

        # ---- the footer action row ----
        root.add_child(_menu_footer())
        set_tab.call("players")
        return overlay


## The panel's size — 62% wide (max 880), 78% tall (max 600): a panel on
## the game, never a screen-filling veil.
func _menu_panel_size() -> Vector2:
        var vp := Vector2(1280.0, 720.0)
        var viewport := get_viewport()
        if viewport != null:
                vp = viewport.get_visible_rect().size
        return Vector2(minf(vp.x * 0.64, 880.0), minf(vp.y * 0.80, 600.0))


## The panel face — v11.0 BLACK GLASS: deep translucent black, rounded 12,
## one hairline light edge. The retro soul lives in the Arial voice, the
## classic green key and the brick-red accents that sit on top of it.
func _menu_panel_style() -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.05, 0.05, 0.07, 0.90)
        sb.set_corner_radius_all(12)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.10)
        sb.shadow_color = Color(0, 0, 0, 0.5)
        sb.shadow_size = 18
        sb.content_margin_left = 0.0
        sb.content_margin_right = 0.0
        sb.content_margin_top = 0.0
        sb.content_margin_bottom = 0.0
        return sb


## One TOP TAB — icon + label centered, transparent; the OPEN tab speaks
## white and wears the 3px CLASSIC GREEN underline, the rest stay muted.
func _tab_button(label: String, icon_kind: String) -> Button:
        var b := Button.new()
        b.text = label
        b.set_meta("icon_kind", icon_kind)
        b.icon = RetroUI.icon_png(icon_kind, RetroUI.MENU_MUTED)
        b.expand_icon = true
        b.custom_minimum_size = Vector2(0, 46)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.focus_mode = Control.FOCUS_NONE
        _style_tab(b, false)
        return b


## One TOP TAB — the black glass read: the open tab is a lighter glass chip
## with the CLASSIC GREEN underline, the rest sit quiet and muted.
func _style_tab(b: Button, on: bool) -> void:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, 0.08) if on else Color(0, 0, 0, 0)
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        if on:
                sb.border_width_bottom = 3
                sb.border_color = RetroUI.GREEN
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 4.0
        b.add_theme_stylebox_override("normal", sb)
        var hb := StyleBoxFlat.new()
        hb.bg_color = Color(1, 1, 1, 0.08) if on else Color(1, 1, 1, 0.04)
        hb.set_corner_radius_all(8)
        hb.anti_aliasing = true
        if on:
                hb.border_width_bottom = 3
                hb.border_color = RetroUI.GREEN
        hb.content_margin_left = 10.0
        hb.content_margin_right = 10.0
        hb.content_margin_top = 6.0
        hb.content_margin_bottom = 4.0
        b.add_theme_stylebox_override("hover", hb)
        b.add_theme_stylebox_override("pressed", sb)
        b.add_theme_stylebox_override("hover_pressed", sb)
        b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        for st in ["font_color", "font_pressed_color"]:
                b.add_theme_color_override(st, RetroUI.MENU_INK if on else RetroUI.MENU_MUTED)
        b.add_theme_color_override("font_hover_color", RetroUI.MENU_INK)
        if RetroUI.gotham(600) != null:
                b.add_theme_font_override("font", RetroUI.gotham(600))
        b.add_theme_font_size_override("font_size", 14)
        var kind := "people"
        if b.has_meta("icon_kind"):
                kind = String(b.get_meta("icon_kind"))
        b.icon = RetroUI.icon_png(kind, RetroUI.MENU_INK if on else RetroUI.MENU_MUTED)


## A quiet ghost icon button (the grid/list view toggles).
func _ghost_icon_btn(kind: String) -> Button:
        var b := Button.new()
        b.custom_minimum_size = Vector2(34, 34)
        b.focus_mode = Control.FOCUS_NONE
        b.icon = RetroUI.icon_texture(kind, RetroUI.MENU_MUTED)
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        b.expand_icon = true
        b.add_theme_stylebox_override("normal", _row_btn(Color(0, 0, 0, 0)))
        b.add_theme_stylebox_override("hover", _row_btn(Color(1, 1, 1, 0.07)))
        b.add_theme_stylebox_override("pressed", _row_btn(Color(1, 1, 1, 0.07)))
        return b

## The menu's text voices (v8.0): BOTH speak the Montserrat family —
## `_title` bold, `_text` regular — inside the client's dark surfaces.
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


## The client's action row — EXACTLY the reference: [L] Leave · [R] Respawn
## · [ESC] Resume, three equal keys; the key chip rides inside each one and
## Resume speaks the fountain blue with the sparkle.
func _menu_footer() -> VBoxContainer:
        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 6)
        var actions := HBoxContainer.new()
        actions.name = "ActionRow"
        actions.add_theme_constant_override("separation", 10)
        col.add_child(actions)
        actions.add_child(_footer_key("L", "Leave", false, func() -> void: _leave_game()))
        actions.add_child(_footer_key("R", "Respawn", false,
                func() -> void:
                        _toggle_menu()
                        if player.alive:
                                player.die(self)
                        _start_respawn()))
        actions.add_child(_footer_key("ESC", "Resume", true, func() -> void: _toggle_menu()))
        return col


## One footer key: the label + a bordered key chip hugging the left edge.
## `primary` wears the fountain blue with a WHITE chip — the reference read.
func _footer_key(key: String, label: String, primary: bool, handler: Callable) -> Button:
        var b := Button.new()
        b.text = label
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size = Vector2(0, 50)
        b.focus_mode = Control.FOCUS_NONE
        # v11.0: the keys carry the REAL internet icons — Respawn wears the
        # restart arrow at KEY size (the 140px source would fill the button)
        if key == "R":
                b.icon = RetroUI.icon_png_sized("respawn", 22)
                b.expand_icon = false
        elif primary:
                b.icon = RetroUI.icon_texture("star", RetroUI.MENU_INK)
                b.expand_icon = false
        if primary:
                b.add_theme_stylebox_override("normal", _blue_btn(false))
                b.add_theme_stylebox_override("hover", _blue_btn(true))
                b.add_theme_stylebox_override("pressed", _blue_btn(true))
        else:
                b.add_theme_stylebox_override("normal", _row_btn())
                b.add_theme_stylebox_override("hover", _row_btn(RetroUI.MENU_PANEL_HI))
                b.add_theme_stylebox_override("pressed", _row_btn(RetroUI.PANEL_DOWN, true))
        for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                b.add_theme_color_override(st, RetroUI.MENU_INK)
        b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
        if RetroUI.gotham(600) != null:
                b.add_theme_font_override("font", RetroUI.gotham(600))
        b.add_theme_font_size_override("font_size", 14)
        # the key chip — a small bordered square parked left of center
        var chip := PanelContainer.new()
        chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var csb := StyleBoxFlat.new()
        csb.bg_color = Color.WHITE if primary else Color(0, 0, 0, 0.25)
        csb.set_corner_radius_all(4)
        csb.set_border_width_all(1)
        csb.border_color = RetroUI.MENU_INK if primary else Color(1, 1, 1, 0.45)
        csb.content_margin_left = 5.0
        csb.content_margin_right = 5.0
        csb.content_margin_top = 2.0
        csb.content_margin_bottom = 2.0
        chip.add_theme_stylebox_override("panel", csb)
        var kl := Label.new()
        kl.text = key
        kl.add_theme_font_override("font", RetroUI.gotham(600))
        kl.add_theme_font_size_override("font_size", 11)
        kl.add_theme_color_override("font_color", RetroUI.MENU_PANEL if primary else RetroUI.MENU_INK)
        chip.add_child(kl)
        b.add_child(chip)
        # park the chip at the button's left inset, vertically centered
        chip.set_anchors_preset(Control.PRESET_CENTER_LEFT)
        chip.grow_horizontal = Control.GROW_DIRECTION_END
        chip.grow_vertical = Control.GROW_DIRECTION_BOTH
        chip.position = Vector2(14, 0)
        chip.reset_size()
        chip.offset_left = 14.0
        chip.offset_top = -12.0
        chip.offset_bottom = 12.0
        b.pressed.connect(handler)
        return b


## The wide dark row button (Invite Friends, footer keys) — translucent
## black glass that lifts on hover and sinks when pressed.
func _row_btn(_face := Color(0.0, 0.0, 0.0, 0.42), pushed := false) -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.10, 0.10, 0.12, 0.85) if pushed else Color(1, 1, 1, 0.07)
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.07)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 9.0
        sb.content_margin_bottom = 9.0
        return sb


## THE CLASSIC GREEN KEY — Resume: the 2006 action green, white ink.
func _blue_btn(hover := false) -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("46a83c") if hover else Color("3e9c35")
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.18)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 9.0
        sb.content_margin_bottom = 9.0
        return sb


## HELP is gone (you asked) — the keys live on the Respawn/Leave chips and
## the F2 hint rides the Settings page.

func _spacer() -> Control:
        var c := Control.new()
        c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        c.size_flags_vertical = Control.SIZE_EXPAND_FILL
        c.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return c


# ---- the player CARD — PFP + name + @handle, the reference read ----------

## One People-page card: the square PFP well, the name, the @handle — the
## exact anatomy of the real client's "In this server" cards.
func _player_card(uid: String, uname: String, is_me: bool, ping: Variant = null, fps: Variant = null) -> PanelContainer:
        var card := PanelContainer.new()
        card.name = "Card_" + uid
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        # v9.0 FIX: the grid stretches its columns, but children only claim
        # their MINIMUM width unless they ask for more — without this the
        # cards collapse into skinny bars
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        card.custom_minimum_size = Vector2(140, 0)
        card.add_theme_stylebox_override("panel", _card_casing(is_me))
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 7)
        card.add_child(box)

        # the PFP well: the player's OWN picture drops in when the fetch
        # lands (the classic smiley holds the seat until then)
        var well := PanelContainer.new()
        well.add_theme_stylebox_override("panel", _well_texture_style())
        well.custom_minimum_size = Vector2(0, 150)
        well.mouse_filter = Control.MOUSE_FILTER_IGNORE
        well.clip_contents = true
        box.add_child(well)
        var portrait := TextureRect.new()
        portrait.name = "Portrait"
        portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        portrait.custom_minimum_size = Vector2(0, 142)
        portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
        portrait.texture = RetroUI.head_icon()
        well.add_child(portrait)
        _portrait_nodes[uid] = portrait

        var name_l := Label.new()
        name_l.text = uname
        name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_l.clip_text = true
        name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        _title(name_l, 13, RetroUI.MENU_INK, 600)
        box.add_child(name_l)

        # the @handle — the real client shows the plain @username under the name
        var handle := Label.new()
        handle.name = "Handle"
        handle.text = "@%s" % uname
        handle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        handle.clip_text = true
        handle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        _text(handle, 12, RetroUI.MENU_FAINT)
        box.add_child(handle)

        # v10.0: the live stats line — ping + fps ride the presence feed, so
        # every card can show them (mine updates live via _my_card_stats)
        var stats := Label.new()
        stats.name = "Stats"
        stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        stats.clip_text = true
        _text(stats, 11, RetroUI.MENU_FAINT)
        box.add_child(stats)
        if is_me:
                _my_card_stats = stats   # the live-stats hook rides this label
        var p_txt := ""
        var f_txt := ""
        if ping != null and ping is int and int(ping) > 0:
                p_txt = "%dms" % int(ping)
        elif ping is float:
                p_txt = "%dms" % int(ping)
        if fps != null and (fps is int or fps is float) and float(fps) > 0.0:
                f_txt = "%dfps" % int(fps)
        var parts: PackedStringArray = []
        if p_txt != "":
                parts.append(p_txt)
        if f_txt != "":
                parts.append(f_txt)
        stats.text = " · ".join(parts) if parts.size() > 0 else "—"
        return card


func _card_casing(is_me: bool) -> StyleBox:
        # v11.0: the black glass card — a lighter glass slab on the dark
        # panel, hairline edge, rounded 10; MY card wears the CLASSIC BLUE
        # selection frame the real client draws around your own row
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, 0.06)
        sb.set_corner_radius_all(10)
        sb.anti_aliasing = true
        sb.set_border_width_all(2)
        sb.border_color = Color(1, 1, 1, 0.08)
        if is_me:
                sb.border_color = RetroUI.BLUE
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 10.0
        return sb


## The PFP well — the deeper inset the headshot sits on.
func _well_texture_style() -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0, 0, 0, 0.55)
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.content_margin_left = 4.0
        sb.content_margin_right = 4.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


## Fire the PFP pipeline for one uid — cached texture drops in instantly,
## a fetch in flight is never doubled, and the fallback head icon holds
## the card until the real headshot arrives. `redress` also re-checks MY
## account look so the in-world rig stays live (the UI shows the PFP).
func _render_portrait(uid: String, redress := false) -> void:
        if _portrait_cache.has(uid):
                _apply_pfp(uid)
                return
        if _portrait_pending.has(uid):
                return
        _portrait_pending[uid] = true
        _pfp_worker(uid, redress)


## The async half — the REAL headshot pipeline: bundled override first
## (zero network for shipped players), then Roblox's own thumbnail API,
## then the classic smiley. NO 3D renders in the UI, ever again.
func _pfp_worker(uid: String, redress := false) -> void:
        if redress and uid == Session.user_id and not Session.is_guest:
                # the RIG still re-dresses live when the account look changed
                # on the site (no relog needed) — the UI above shows the PFP
                var fresh: Dictionary = await Api.avatar_of(uid)
                if fresh.get("ok", false) and fresh.get("avatar", null) is Dictionary:
                        var payload: Dictionary = fresh["avatar"]
                        Session.set_avatar(fresh)
                        Session.cache_avatar(uid, fresh)
                        var sig := JSON.stringify(payload)
                        if sig != _dressed_signature and player != null and is_instance_valid(player):
                                _dressed_signature = sig
                                player.call("dress", Api, payload)
        var uname := String(_names_by_uid.get(uid, ""))
        if uid == Session.user_id:
                uname = Session.username
        var tex: Texture2D = await Pfp.fetch(uid, uname)
        _portrait_pending.erase(uid)
        if tex == null:
                return
        _portrait_cache[uid] = tex
        _apply_pfp(uid)


## Swap a landed PFP into every live seat: the card node, (for me) the
## topbar user pill and the Settings preview.
func _apply_pfp(uid: String) -> void:
        var tex: Texture2D = _portrait_cache.get(uid, null)
        if tex == null:
                return
        if _portrait_nodes.has(uid) and is_instance_valid(_portrait_nodes[uid]):
                (_portrait_nodes[uid] as TextureRect).texture = tex
        if uid == Session.user_id:
                if _topbar_pfp != null and is_instance_valid(_topbar_pfp):
                        _topbar_pfp.texture = tex
                if _pfp_preview != null and is_instance_valid(_pfp_preview):
                        _pfp_preview.texture = tex


## The menu's pulse: the corner chip + header clock breathe every half
## second while the menu is open.
func _update_live_stats() -> void:
        var fps := Engine.get_frames_per_second()
        if fps > 0:
                _fps_smooth = lerpf(_fps_smooth, float(fps), 0.35)
        if _corner_stats != null and is_instance_valid(_corner_stats):
                var ping := ("%dms" % _last_ping_ms) if _last_ping_ms > 0 else "—"
                _corner_stats.text = "FPS %d   ·   PING %s   ·   v11.0" % [int(roundf(_fps_smooth)), ping]
        if _time_label != null and is_instance_valid(_time_label):
                _time_label.text = _clock_text()


## The page heading — the People page carries the live count like the real
## client's server roster.
func _update_people_title() -> void:
        if _people_title == null or not is_instance_valid(_people_title):
                return
        _people_title.text = "In this server — %d" % _people_total


func _clock_text() -> String:
        var secs := int((Time.get_ticks_msec() - _session_start_ms) / 1000.0)
        return "%02d:%02d" % [floori(secs / 60.0), secs % 60]


# ---- the client's one-voice surfaces --------------------------------------

## The one DARK key face — flat rounded-8, lighter on hover, PANEL_DOWN when
## pushed. Every default menu key is built on this.
func _key_btn(face := Color("424242"), pushed := false) -> StyleBox:
        var sb: StyleBox = RetroUI.sunken(4, RetroUI.PANEL_DOWN) if pushed else RetroUI.raised(4, face)
        sb.content_margin_left = 16.0
        sb.content_margin_right = 16.0
        sb.content_margin_top = 9.0 if pushed else 10.0
        sb.content_margin_bottom = 9.0 if pushed else 10.0
        return sb


## THE WHITE KEY — the real client's primary read: white face, dark ink.
func _white_btn(hover := false, pushed := false) -> StyleBox:
        var face := Color("e2e2e2") if hover else Color("ffffff")
        if pushed:
                face = Color("cfcfcf")
        var sb: StyleBox = RetroUI.flat(8, face)
        sb.content_margin_left = 16.0
        sb.content_margin_right = 16.0
        sb.content_margin_top = 9.0 if pushed else 10.0
        sb.content_margin_bottom = 9.0 if pushed else 10.0
        return sb


## The identity row's close key — a quiet ghost that blushes red on hover.
func _close_btn(hot := false) -> StyleBoxFlat:
        var sb: StyleBoxFlat = RetroUI.flat(8, Color(0.96, 0.26, 0.31, 0.14)) if hot else RetroUI.wash(0.0, 8)
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb



## Leave = CLOSE THE GAME (v3.11, exactly as asked): the window quits on
## desktop. The web build can't close its own tab, so there Leave reloads
## the place instead. The menu's L shortcut lands here too.
func _leave_game() -> void:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        if OS.has_feature("web"):
                get_tree().change_scene_to_file("res://scenes/game.tscn")
        else:
                get_tree().quit()


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
        _title(anim_title, 13, RetroUI.MENU_MUTED, 600)
        right.add_child(anim_title)
        var grid := GridContainer.new()
        grid.columns = 3
        grid.add_theme_constant_override("h_separation", 6)
        grid.add_theme_constant_override("v_separation", 6)
        right.add_child(grid)
        for anim in ["Sit", "Climb", "Walk", "Jump", "Idle", "Stop"]:
                var b := Button.new()
                b.text = anim
                b.custom_minimum_size = Vector2(72, 34)
                b.focus_mode = Control.FOCUS_NONE
                b.add_theme_stylebox_override("normal", _key_btn())
                b.add_theme_stylebox_override("hover", _key_btn(RetroUI.MENU_PANEL_HI))
                b.add_theme_stylebox_override("pressed", _key_btn(RetroUI.PANEL_DOWN, true))
                b.add_theme_color_override("font_color", RetroUI.MENU_INK)
                if RetroUI.source(600) != null:
                        b.add_theme_font_override("font", RetroUI.source(600))
                b.add_theme_font_size_override("font_size", 12)
                var clip: String = "" if anim == "Stop" else anim
                b.pressed.connect(func() -> void:
                        if player != null and is_instance_valid(player):
                                player.avatar.call("play_emote", clip))
                grid.add_child(b)
        # v6.0: the settings page speaks the Source Sans voice — quiet toggles
        var book: Font = RetroUI.source(400)
        if book != null:
                for cb in [shadows, fullscreen, shift]:
                        cb.add_theme_font_override("font", book)
                        cb.add_theme_font_size_override("font_size", 13)
        for cb in [shadows, fullscreen, shift]:
                cb.add_theme_color_override("font_color", RetroUI.MENU_INK)
                cb.add_theme_color_override("font_hover_color", RetroUI.MENU_INK)
                cb.add_theme_color_override("font_pressed_color", RetroUI.MENU_INK)

        # ---- v9.0: MY PICTURE — your PFP URL, applied EVERYWHERE live ----
        tab.add_child(_hspace(6))
        var pfp_title := Label.new()
        pfp_title.text = "MY PICTURE"
        _title(pfp_title, 13, RetroUI.MENU_MUTED, 600)
        tab.add_child(pfp_title)
        var pfp_row := HBoxContainer.new()
        pfp_row.add_theme_constant_override("separation", 12)
        tab.add_child(pfp_row)
        var preview_frame := PanelContainer.new()
        preview_frame.add_theme_stylebox_override("panel", RetroUI.flat(8, RetroUI.WELL))
        preview_frame.custom_minimum_size = Vector2(56, 56)
        preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
        preview_frame.clip_contents = true
        pfp_row.add_child(preview_frame)
        _pfp_preview = TextureRect.new()
        _pfp_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        _pfp_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _pfp_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        _pfp_preview.texture = RetroUI.head_icon()
        _pfp_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
        preview_frame.add_child(_pfp_preview)
        if _portrait_cache.has(Session.user_id) and _portrait_cache[Session.user_id] != null:
                _pfp_preview.texture = _portrait_cache[Session.user_id]
        var pfp_col := VBoxContainer.new()
        pfp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        pfp_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        pfp_col.add_theme_constant_override("separation", 6)
        pfp_row.add_child(pfp_col)
        _pfp_url_edit = LineEdit.new()
        _pfp_url_edit.placeholder_text = "Paste an image URL (or data URL) — your face, everywhere"
        _pfp_url_edit.text = UiConfig.pfp_url
        _pfp_url_edit.custom_minimum_size = Vector2(0, 36)
        _pfp_url_edit.text_submitted.connect(func(t: String) -> void: _apply_pfp_url(t))
        pfp_col.add_child(_pfp_url_edit)
        var pfp_btns := HBoxContainer.new()
        pfp_btns.add_theme_constant_override("separation", 8)
        pfp_col.add_child(pfp_btns)
        var pfp_apply := Button.new()
        pfp_apply.text = "Apply"
        pfp_apply.custom_minimum_size = Vector2(110, 34)
        pfp_apply.focus_mode = Control.FOCUS_NONE
        pfp_apply.add_theme_stylebox_override("normal", _row_btn(Color("1f4a2a")))
        pfp_apply.add_theme_stylebox_override("hover", _row_btn(Color("276038")))
        pfp_apply.add_theme_stylebox_override("pressed", _row_btn(Color("173821"), true))
        pfp_apply.add_theme_color_override("font_color", RetroUI.MENU_INK)
        if RetroUI.gotham(600) != null:
                pfp_apply.add_theme_font_override("font", RetroUI.gotham(600))
        pfp_apply.add_theme_font_size_override("font_size", 13)
        pfp_apply.pressed.connect(func() -> void: _apply_pfp_url(_pfp_url_edit.text))
        pfp_btns.add_child(pfp_apply)
        var pfp_clear := Button.new()
        pfp_clear.text = "Use my account picture"
        pfp_clear.custom_minimum_size = Vector2(190, 34)
        pfp_clear.focus_mode = Control.FOCUS_NONE
        pfp_clear.add_theme_stylebox_override("normal", _row_btn())
        pfp_clear.add_theme_stylebox_override("hover", _row_btn(RetroUI.MENU_PANEL_HI))
        pfp_clear.add_theme_stylebox_override("pressed", _row_btn(RetroUI.PANEL_DOWN, true))
        pfp_clear.add_theme_color_override("font_color", RetroUI.MENU_MUTED)
        if RetroUI.gotham(600) != null:
                pfp_clear.add_theme_font_override("font", RetroUI.gotham(600))
        pfp_clear.add_theme_font_size_override("font_size", 13)
        pfp_clear.pressed.connect(func() -> void:
                _pfp_url_edit.text = ""
                _apply_pfp_url(""))
        pfp_btns.add_child(pfp_clear)

        # ---- v9.0: EDIT THIS UI — the player's own editor ----
        tab.add_child(_hspace(6))
        var edit_title := Label.new()
        edit_title.text = "EDIT THIS UI"
        _title(edit_title, 13, RetroUI.MENU_MUTED, 600)
        tab.add_child(edit_title)
        var edit_row := HBoxContainer.new()
        edit_row.add_theme_constant_override("separation", 12)
        tab.add_child(edit_row)
        var edit_btn := Button.new()
        edit_btn.text = "Edit anything (F2)"
        edit_btn.icon = RetroUI.icon_texture("pencil", RetroUI.MENU_INK)
        edit_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
        edit_btn.expand_icon = true
        edit_btn.custom_minimum_size = Vector2(190, 40)
        edit_btn.focus_mode = Control.FOCUS_NONE
        edit_btn.add_theme_stylebox_override("normal", _row_btn(Color("1f4a2a")))
        edit_btn.add_theme_stylebox_override("hover", _row_btn(Color("276038")))
        edit_btn.add_theme_stylebox_override("pressed", _row_btn(Color("173821"), true))
        edit_btn.add_theme_color_override("font_color", RetroUI.MENU_INK)
        if RetroUI.gotham(600) != null:
                edit_btn.add_theme_font_override("font", RetroUI.gotham(600))
        edit_btn.add_theme_font_size_override("font_size", 14)
        edit_btn.pressed.connect(func() -> void:
                _toggle_menu()
                UiEditor.set_enabled(true))
        edit_row.add_child(edit_btn)
        var scale_col := VBoxContainer.new()
        scale_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scale_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        scale_col.add_theme_constant_override("separation", 4)
        edit_row.add_child(scale_col)
        var scale_l := Label.new()
        scale_l.text = "UI scale — %.2f" % UiConfig.ui_scale
        _text(scale_l, 13, RetroUI.MENU_MUTED)
        scale_col.add_child(scale_l)
        var scale_s := HSlider.new()
        scale_s.min_value = 0.6
        scale_s.max_value = 1.6
        scale_s.step = 0.05
        scale_s.value = UiConfig.ui_scale
        scale_s.custom_minimum_size = Vector2(0, 20)
        scale_s.focus_mode = Control.FOCUS_NONE
        scale_s.value_changed.connect(func(v: float) -> void:
                scale_l.text = "UI scale — %.2f" % v
                UiConfig.ui_scale = v
                UiConfig.save_config()
                get_tree().root.content_scale_factor = v)
        scale_col.add_child(scale_s)
        return tab


## Apply the PFP URL typed in Settings — saves to ui_config, repaints seats.
func _apply_pfp_url(url: String) -> void:
        url = url.strip_edges()
        UiConfig.pfp_url = url
        UiConfig.save_config()
        Pfp.set_custom_pfp(url)
        _notify("My picture updated" if url != "" else "Back to my account picture", false)


func _hspace(h: int) -> Control:
        var c := Control.new()
        c.custom_minimum_size = Vector2(0, h)
        return c


func _slider_row(parent: VBoxContainer, label_text: String, minv: float, maxv: float, value: float, on_change: Callable) -> void:
        var l := Label.new()
        l.text = "%s  —  %.2f" % [label_text, value]
        _text(l, 13, RetroUI.MENU_MUTED)
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


## Crop the top-center square out of a full-body portrait — the headshot
## the menu header wears (the real client's menu read).
func _headshot_of(tex: Texture2D) -> ImageTexture:
        if tex == null:
                return null
        var img: Image = tex.get_image()
        if img == null or img.is_empty():
                return null
        var w := img.get_width()
        var h := img.get_height()
        # the rig's head rides the top of the shot, roughly centered —
        # take a 0.72-wide square from just under the top edge
        var side := int(w * 0.72)
        var x0 := clampi(int(w * 0.5 - side * 0.5), 0, maxi(w - side, 0))
        var y0 := int(h * 0.04)
        var crop := img.get_region(Rect2i(x0, y0, side, mini(side, h - y0)))
        return ImageTexture.create_from_image(crop)


func _toggle_menu() -> void:
        if _menu == null or not is_instance_valid(_menu):
                return
        _menu_open = not _menu_open
        _menu.visible = _menu_open
        if _menu_open:
                # v3.11: the window breathes in — a quick smooth fade
                _menu.modulate.a = 0.0
                create_tween().tween_property(_menu, "modulate:a", 1.0, 0.14)
                camera_rig.set_ui_blocked(true)
                # v4.0: render the pocketed presence snapshot RIGHT AWAY —
                # the roster is on screen the moment the menu opens
                _refresh_player_list(_last_presence)
                _update_live_stats()
                # v6.0: the header's headshot pulls from the cache first,
                # then rides the same portrait pipeline as the cards
                if _topbar_pfp != null and is_instance_valid(_topbar_pfp):
                        if _portrait_cache.has(Session.user_id) and _portrait_cache[Session.user_id] != null:
                                _apply_pfp(Session.user_id)
                        else:
                                _render_portrait(Session.user_id, true)
        else:
                _menu.modulate.a = 1.0
                camera_rig.set_ui_blocked(false)


# ---------------------------------------------------------------- events

func _on_health_changed(hp: float, max_hp: float) -> void:
        var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
        _health_value.text = str(int(roundf(hp)))
        var c := Color("f44250").lerp(Color("00b06f"), ratio)
        var sb: StyleBoxFlat = _health_fill.get_theme_stylebox("panel")
        if sb != null:
                sb.bg_color = c
        # the horizontal bar drains from the RIGHT (the classic read)
        var inner := _health_track_w - 6.0
        _health_fill.offset_right = -3.0 - inner * (1.0 - ratio)


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
                chat.add_system(Api.txt(res.get("error", ""), "Could not send the message."))


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
        var msgs: Array = res.get("messages", [])
        if not _chat_history_done:
                # v3.11 REJOIN FIX: the feed's first answer is the place's
                # last 60 lines — HISTORY from before you joined. Mark it all
                # seen silently so reopening the game never re-spams your old
                # chat (and never re-pops those bubbles over your head).
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
                _names_by_uid[uid] = String(p.get("username", ""))
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
        # v4.0 PERF: the People page is only visible with the menu open —
        # rebuilding its cards (and re-hanging portrait nodes) every 2.5s
        # poll while playing was pure garbage churn. Pocket the snapshot;
        # opening the menu renders it instantly, live polls keep it fresh.
        _last_presence = players
        if _menu_open:
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
        _people_total = total
        _update_people_title()
        # my card first — the blue-ringed one
        _players_grid.add_child(_player_card(Session.user_id, Session.username, true,
                _last_ping_ms, int(_fps_smooth)))
        _render_portrait(Session.user_id)
        for p in players:
                var uid := String(p.get("userId", ""))
                var uname := String(p.get("username", ""))
                if uid == "" or uid == Session.user_id or uname == "":
                        continue
                _names_by_uid[uid] = uname
                var st: Dictionary = _remote_stats.get(uid, {})
                _players_grid.add_child(_player_card(uid, uname, false,
                        st.get("ping", null), st.get("fps", null)))
                _render_portrait(uid)
        _update_live_stats()
