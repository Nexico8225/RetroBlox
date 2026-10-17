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
const UiWidgetsScript := preload("res://scripts/editor/ui_widgets.gd")
const WorldBuilderScript := preload("res://scripts/world/world_builder.gd")
const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const AvatarViewerScript := preload("res://scripts/ui/avatar_viewer.gd")
const MenuIcons := preload("res://scripts/ui/menu_icons.gd")

const POLL_SECONDS := 2.5       # chat + presence feed
const HEARTBEAT_SECONDS := 4.0  # my presence out
const RESPAWN_SECONDS := 2.0    # v4.0: snappier classic respawn (was 2.8)

var place: Dictionary
var player            # LocalPlayer — untyped: custom members, dynamic calls
var camera_rig        # CameraRig
var chat              # ChatBox
var hud: CanvasLayer

var _health_fill: Panel              # the green fill inside the track
var _health_value: Label
var _names_by_uid: Dictionary = {}   # userId -> username (the People list)
var _health_track_h := 220.0         # v12.1: the VERTICAL right-edge bar height
var _menu: Control
var _menu_panel: PanelContainer      # v1.1: the card the UI OPACITY fades
var _players_grid: GridContainer     # the People page — the simple avatar grid
var _settings_tab: VBoxContainer
var _people_title: Label             # "Players — N" page heading
var _time_label: Label               # live session clock in the page header
var _corner_stats: Label             # the tiny FPS/ping/version chip (bottom-left)
var _tab_buttons: Dictionary = {}    # v9.0: tab id -> Button (top tabs)
var _pages: Dictionary = {}          # v9.0: tab id -> page Control
var _fps_smooth := 60.0              # v3.9: eased fps so the chip doesn't flicker
var _menu_tick := 0.5                # v3.9: live stats refresh cadence
var _people_total := 1               # v4.0: last known online count (header)
var _viewers: Dictionary = {}        # v12.4: userId -> the LIVE AvatarViewer (survives card rebuilds)
var _viewer_dressed: Dictionary = {} # v12.4: userId -> true once the viewer's rig wears the real look
var _viewer_pending: Dictionary = {} # v12.4: viewer payload jobs already in flight
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
# v14.0 STUDIO: the widgets YOU built in the UI Editor — health bars live
# here so every health tick repaints them too
var _custom_healthbars: Array = []
var _custom_health01 := 1.0
var _chat_badge: Label
var _chat_badge_panel: PanelContainer
var _toast_box: VBoxContainer
var _shift_check: Button
var _center_cursor: TextureRect   # the visible mouse parked mid-screen in first person
var _loading: Control             # the v3.6 loading veil (no more load hitch)
var _session_start_ms := 0        # the match timer
var _last_ping_ms := 0            # last platform round-trip, shown as ping

# ---- v13.0 THE PAINT BRUSH: the game world is a color world ----
# The 12 classic swatches (hex, no #): white is the eraser, black is ink,
# the rest are the bright plastic colors the old bricks shipped in.
const PAINT_COLORS := [
        "f2f3f3", "1b2a34", "c4281c", "e8752a", "f5cd30", "4b974b",
        "009999", "0d69ac", "6b327c", "e8bac8", "7c5c46", "635f62",
]
var _brush := Color("c4281c")    # the picked swatch (bright red ships picked)
var _paint_bar: PanelContainer  # the bottom-center palette
var _paint_swatch := {}         # hex -> Button (for the picked highlight)
var _paint_count: Label         # "12 / 33 painted" (paint-flagged places)
var _paint_total := 0           # paintable parts in this place
var _painted := {}              # instance_id -> true (parts I painted)
var _paint_done := false        # the WORLD COMPLETE banner fires once
var _build_mode := false        # v13.1 BUILD MODE: click to place bricks
var _built_root: Node3D         # every brick YOU place lives here


func _ready() -> void:
        # v15.0 ROLES: resolve what this account may edit (one cached GET —
        # players play; game devs get the editor scenes). Answers async.
        Session.check_dev()
        place = Session.current_place
        if place.is_empty():
                # v13.0: signing in drops you straight into COLOR WORLD — the world
                # born white that YOU paint brick by brick (the classic baseplate
                # and every other place still live in scripts/world/places.gd)
                place = PlacesScript.by_id("colorworld")
        _session_start_ms = Time.get_ticks_msec()

        # ---- the loading veil goes up FIRST: the world + avatar + HUD are
        # built across a few frames now (no one-frame freeze) and this covers it
        _show_loading()
        await get_tree().process_frame

        var built: Dictionary = WorldBuilderScript.build(place)
        add_child(built["root"])
        _spawns = built["spawns"]
        _tag_paintables(built["root"])   # v13.0: every part accepts the brush
        _built_root = Node3D.new()       # v13.1: bricks the player builds land here
        _built_root.name = "BuiltBricks"
        built["root"].add_child(_built_root)
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
                # v12.0: live-apply every setting the HUD/world speaks — the
                # corner chip, the nameplates — and name MY rig at spawn
                settings.changed.connect(_on_setting_changed)
        _apply_nameplates()

        _build_hud()

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

## v12.0: the Settings page flips — repaint the live HUD bits instantly.
## v1.1: UI OPACITY rides here too — the menu card + the chat float fade
## together, live, no reopen needed.
func _on_setting_changed(key: String, _value: Variant) -> void:
        match key:
                "show_fps", "show_ping":
                        _update_live_stats()
                "player_names":
                        _apply_nameplates()
                "ui_opacity":
                        _apply_ui_opacity()
                _:
                        pass


## v1.1 UI OPACITY — one dial for the menu card + the chat float.
func _apply_ui_opacity() -> void:
        var settings: Node = get_node_or_null("/root/Settings")
        var a := 1.0 if settings == null else clampf(float(settings.get("ui_opacity")), 0.3, 1.0)
        if _menu_panel != null and is_instance_valid(_menu_panel):
                _menu_panel.modulate = Color(1, 1, 1, a)
        if chat != null and is_instance_valid(chat):
                chat.modulate = Color(1, 1, 1, a)


func _dress_me() -> void:
        if Session.is_guest:
                _apply_saved_avatar_colors()  # v14.0: guests wear their saved look too
                return  # avatar already painted classic noob by the rig
        var payload := Session.my_avatar_data()
        if payload.is_empty():
                var me: Dictionary = await Api.get_me()
                if me.get("ok", false):
                        Session.set_avatar(me)
                        payload = Session.my_avatar_data()
        _dressed_signature = JSON.stringify(payload)
        await player.call("dress", Api, payload)
        _apply_saved_avatar_colors()  # v14.0: your editor colors go ON TOP


## v14.0 PLAYER EDITOR hookup — whatever the Player Editor scene saved
## (user://avatar_colors.json) repaints MY rig: skin on the head, shirt
## over torso + arms, pants over the legs. Wears over the noob paint or
## on top of the site avatar, whatever you are.
func _apply_saved_avatar_colors() -> void:
        const PATH := "user://avatar_colors.json"
        if not FileAccess.file_exists(PATH) or player == null or not is_instance_valid(player):
                return
        var f := FileAccess.open(PATH, FileAccess.READ)
        if f == null:
                return
        var parsed: Variant = JSON.parse_string(f.get_as_text())
        if typeof(parsed) != TYPE_DICTIONARY:
                return
        var d: Dictionary = parsed
        var rig: Node = player.get("avatar")
        if rig == null or not is_instance_valid(rig):
                return
        for row in [["skin", [0]], ["shirt", [1, 2, 3]], ["pants", [4, 5]]]:
                var hex := String(d.get(String(row[0]), "")).trim_prefix("#")
                if hex.length() != 6:
                        continue
                for idx in row[1]:
                        rig.set_part_color(int(idx), Color(hex))


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
        # ---- CLICK-OFF closes the chat (you asked: click the type box to
        # type, click off to give the keyboard back to the game) ----
        if chat != null and is_instance_valid(chat) and chat.is_open \
                        and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
                chat.close()
                get_viewport().set_input_as_handled()
                return
        # ---- v13.1 BUILD MODE: the B key turns the world into your map
        # editor — click places a brick (in your brush color), CTRL+click
        # removes one you placed, B again is back to painting ----
        if event is InputEventKey and event.is_pressed() and not event.is_echo() \
                        and (event as InputEventKey).keycode == KEY_B and not _menu_open \
                        and chat != null and is_instance_valid(chat) and not chat.is_open:
                _toggle_build_mode()
                get_viewport().set_input_as_handled()
                return
        # ---- v13.0 THE PAINT BRUSH: LEFT CLICK paints the brick under the
        # cursor with the picked palette color (palette lives bottom-center;
        # buttons eat their own clicks so painting never fires on UI) ----
        if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
                        and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
                        and not _menu_open and chat != null and is_instance_valid(chat) \
                        and not chat.is_open and not chat.is_reading:
                _brush_click(event)
                return
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
## v12.1 RETRO NIGHT: the dark translucent topbar (logo / chat with unread
## badge), the VERTICAL health bar on the right edge, join toasts top-center,
## the dark glass chat with its always-visible type box, and the dark retro
## ESC menu in the center. THE THREE-LINE BUTTON IS GONE (you asked) — the
## logo key and the ESC key both open the menu.
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
        _build_stats_chip()
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

        # ---- v13.0: the paint palette — the game world is a color world ----
        _build_paint_bar()

        # ---- v14.0: YOUR widgets — whatever the UI Editor scene holds ----
        for n in UiWidgetsScript.spawn_all(hud, self):
                if n.has_meta("custom_health"):
                        _custom_healthbars.append(n)
                        (n as ProgressBar).value = _custom_health01 * 100.0

        # ---- center: esc menu with the icon rail (People / Settings) ----
        _menu = _build_menu()
        # the shared retro theme never reaches a CanvasLayer on its own —
        # hand it over so the menu buttons speak in the pixel voice too
        _menu.theme = RetroUI.shared
        hud.add_child(_menu)
        # v1.1: honor the saved UI OPACITY the moment the menu exists
        _apply_ui_opacity()


# ---- topbar ------------------------------------------------------------

## v12.1: the ALWAYS-ON stats chip — a dark translucent pill parked
## bottom-left: FPS / ping / version, each stat hiding itself when the
## Settings page says so (the classic Performance Stats read).
func _build_stats_chip() -> void:
        _corner_stats = Label.new()
        _corner_stats.name = "CornerStats"
        _corner_stats.text = "—"
        _text(_corner_stats, 12, Color.WHITE)
        var pill := PanelContainer.new()
        pill.name = "StatsChip"
        pill.add_theme_stylebox_override("panel", _pill_style())
        pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
        pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
        pill.offset_left = 12.0
        pill.offset_top = -34.0
        pill.offset_bottom = -10.0
        pill.add_child(_corner_stats)
        hud.add_child(pill)
        UiEditor.register("stats_chip", pill, false)

func _build_topbar() -> void:
        # ---- v12.1: the top-left cluster — TWO keys only: the logo and
        # the chat bubble with its unread badge. The three-line button is
        # GONE (you asked). Both the logo key and ESC open the menu.
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

        # the chat key — THE OLD BLUE ONE: the white bubble on the site's
        # blue gloss square, exactly the v12.0 topbar the owner wants back
        var chat_btn := _topbar_key()
        chat_btn.tooltip_text = "Chat (ENTER)"
        chat_btn.icon = RetroUI.icon_png("chat", Color.WHITE)
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

        # ---- the TOP-RIGHT USER PILL — name + the settings gear,
        # parked exactly where the real client keeps them
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
        _names_by_uid[Session.user_id] = Session.username
        var uname := Label.new()
        uname.name = "UserName"
        uname.text = Session.username
        uname.add_theme_font_override("font", RetroUI.gotham(600))
        uname.add_theme_font_size_override("font_size", 13)
        uname.add_theme_color_override("font_color", Color.WHITE)
        uname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        urow.add_child(uname)
        var gear_btn := Button.new()
        gear_btn.custom_minimum_size = Vector2(34, 34)
        gear_btn.focus_mode = Control.FOCUS_NONE
        gear_btn.tooltip_text = "Settings (ESC)"
        gear_btn.icon = RetroUI.icon_png("settings", Color.WHITE)
        gear_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        gear_btn.expand_icon = true
        gear_btn.add_theme_stylebox_override("normal", _dark_key_style(false))
        gear_btn.add_theme_stylebox_override("hover", _dark_key_style(true))
        gear_btn.add_theme_stylebox_override("pressed", _dark_key_style(true))
        gear_btn.pressed.connect(func() -> void: _open_menu("settings"))
        urow.add_child(gear_btn)
        UiEditor.register("user_pill", user_pill, false)


## One topbar key — the dark translucent bevel square with the light ink
## icon inside (the classic client's HUD squares).
func _topbar_key() -> Button:
        var b := Button.new()
        b.custom_minimum_size = Vector2(42, 34)
        b.focus_mode = Control.FOCUS_NONE
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        b.expand_icon = true
        b.add_theme_stylebox_override("normal", _dark_key_style(false))
        b.add_theme_stylebox_override("hover", _dark_key_style(true))
        b.add_theme_stylebox_override("pressed", _dark_key_style(true))
        return b


## The BLUE GLOSS HUD key face — v12.2: THE OLD CHAT ICON IS BACK. The
## topbar keys wear the site's blue header gloss again (the v12.0 read the
## owner calls "the blue one"), white ink on top, hover lifts it.
func _dark_key_style(hover: bool) -> StyleBox:
        return RetroUI.gloss(
                RetroUI.SITE_BLUE.lightened(0.06) if hover else RetroUI.SITE_BLUE,
                RetroUI.SITE_BLUE_DK, RetroUI.SITE_BLUE_DK.darkened(0.35), 8)


## The topbar/stats pill — the site's blue header gloss (the old read).
func _pill_style() -> StyleBox:
        var sb: StyleBoxTexture = RetroUI.gloss(RetroUI.SITE_BLUE, RetroUI.SITE_BLUE_DK,
                RetroUI.SITE_BLUE_DK.darkened(0.35), 8)
        sb.content_margin_left = 6.0
        sb.content_margin_right = 6.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


func _badge_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.MENU_RED
        sb.set_corner_radius_all(8)
        sb.content_margin_left = 5.0
        sb.content_margin_right = 5.0
        sb.content_margin_top = 1.0
        sb.content_margin_bottom = 1.0
        return sb


# ---- the health BAR (vertical, right edge — the classic client dock) -----

func _build_health() -> void:
        # v12.1: THE VERTICAL HEALTH BAR, RIGHT EDGE — the classic client's
        # read: a deep navy track hugging the right side, the green fill
        # climbing from the bottom, the number chip parked on top of it.
        var track := Panel.new()
        track.name = "HealthBar"
        track.mouse_filter = Control.MOUSE_FILTER_IGNORE
        track.add_theme_stylebox_override("panel", _health_track_style())
        track.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        track.offset_left = -34.0
        track.offset_right = -14.0
        track.offset_top = -_health_track_h / 2.0
        track.offset_bottom = _health_track_h / 2.0
        hud.add_child(track)
        UiEditor.register("health", track, false)

        _health_fill = Panel.new()
        _health_fill.name = "Fill"
        _health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        # the green fill — a FLAT box so the color can lerp green -> red
        # with the health (a gloss texture could never tint)
        _health_fill.add_theme_stylebox_override("panel", _health_fill_style(1.0))
        _health_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
        _health_fill.offset_left = 3.0
        _health_fill.offset_top = 3.0
        _health_fill.offset_bottom = -3.0
        _health_fill.offset_right = -3.0
        track.add_child(_health_fill)

        # the number chip — right above the bar, always readable
        var chip := PanelContainer.new()
        chip.name = "HealthChip"
        chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var csb := StyleBoxFlat.new()
        csb.bg_color = Color(0.02, 0.035, 0.055, 0.72)
        csb.set_corner_radius_all(6)
        csb.anti_aliasing = true
        csb.set_border_width_all(1)
        csb.border_color = Color(1, 1, 1, 0.14)
        csb.content_margin_left = 7.0
        csb.content_margin_right = 7.0
        csb.content_margin_top = 2.0
        csb.content_margin_bottom = 2.0
        chip.add_theme_stylebox_override("panel", csb)
        chip.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        chip.grow_vertical = Control.GROW_DIRECTION_BOTH
        chip.offset_left = -34.0
        chip.offset_right = -14.0
        chip.offset_top = -_health_track_h / 2.0 - 30.0
        chip.offset_bottom = -_health_track_h / 2.0 - 6.0
        hud.add_child(chip)

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
        chip.add_child(_health_value)


func _health_track_style() -> StyleBox:
        # the deep navy inset the fill climbs inside
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("17242f")
        sb.set_corner_radius_all(6)
        sb.anti_aliasing = true
        sb.set_border_width_all(2)
        sb.border_color = Color(0, 0, 0, 0.55)
        sb.content_margin_left = 3.0
        sb.content_margin_right = 3.0
        sb.content_margin_top = 3.0
        sb.content_margin_bottom = 3.0
        return sb


## The fill face at a health ratio — green at full, red near empty.
func _health_fill_style(ratio: float) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("f44250").lerp(Color("00b06f"), ratio)
        sb.set_corner_radius_all(4)
        sb.anti_aliasing = true
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
        tween.tween_interval(3.4)
        tween.tween_property(pill, "modulate:a", 0.0, 0.5)
        tween.tween_callback(pill.queue_free)


func _toast_style() -> StyleBox:
        # v12.1: the dark translucent toast — the same float the chat wears
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


## v14.0 UI EDITOR hookup — your custom widgets talk back here: pressing
## one of your buttons (or submitting your text box) pops a toast. The
## HUD is yours; make it say things.
func _custom_widget_action(txt: String) -> void:
        _notify(txt, false)


# ---------------------------------------------------------------- paint brush
# v13.0 THE GAME WORLD IS A COLOR WORLD. Every part of every place accepts
# the brush: LEFT CLICK paints the brick under the cursor with the picked
# palette color. Paint is your own view of the world (client-side) — the
# classic feeling of coloring a baseplate, now built into the client.

## Tag every paintable part after the world builds. A part = a StaticBody3D
## with a MeshInstance3D child (exactly what WorldBuilder._build_part makes).
func _tag_paintables(world_root: Node) -> void:
        var stack: Array[Node] = [world_root]
        while not stack.is_empty():
                var n: Node = stack.pop_back()
                for c in n.get_children():
                        stack.append(c)
                if n is StaticBody3D:
                        for c in n.get_children():
                                if c is MeshInstance3D:
                                        n.add_to_group("paintable")
                                        _paint_total += 1
                                        break


## The bottom-center palette: PAINT + the 12 swatches (+ the painted counter
## in places flagged "paint": true). Swatch buttons eat their own clicks.
func _build_paint_bar() -> void:
        _paint_bar = PanelContainer.new()
        _paint_bar.name = "PaintBar"
        _paint_bar.add_theme_stylebox_override("panel", _toast_style())
        _paint_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        _paint_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _paint_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
        _paint_bar.offset_bottom = -12.0
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 5)
        _paint_bar.add_child(row)

        var title := Label.new()
        title.text = "PAINT"
        _text(title, 12, Color(1, 1, 1, 0.85))
        row.add_child(title)

        for hex in PAINT_COLORS:
                var hx := String(hex)
                var swatch := Button.new()
                swatch.custom_minimum_size = Vector2(24, 24)
                swatch.focus_mode = Control.FOCUS_NONE
                swatch.tooltip_text = "#" + hx
                swatch.add_theme_stylebox_override("normal", _paint_swatch_face(hx, false))
                swatch.add_theme_stylebox_override("hover", _paint_swatch_face(hx, false))
                swatch.add_theme_stylebox_override("pressed", _paint_swatch_face(hx, false))
                swatch.pressed.connect(_pick_paint.bind(hx))
                row.add_child(swatch)
                _paint_swatch[hx] = swatch
        _pick_paint("c4281c")   # bright red ships picked

        if bool(place.get("paint", false)):
                _paint_count = Label.new()
                _text(_paint_count, 12, Color("ffd400"))
                _paint_count.text = "0 / %d painted" % _paint_total
                row.add_child(_paint_count)
                _notify("This world is born WHITE — click a brick to paint it!", true)

        hud.add_child(_paint_bar)
        UiEditor.register("paint_bar", _paint_bar, false)


## A swatch face: the color itself, yellow-rimmed when it is the picked brush.
func _paint_swatch_face(hex: String, picked: bool) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(hex)
        sb.set_corner_radius_all(5)
        sb.set_border_width_all(3 if picked else 2)
        sb.border_color = Color("ffd400") if picked else Color(1, 1, 1, 0.22)
        return sb


func _pick_paint(hex: String) -> void:
        _brush = Color(hex)
        for key in _paint_swatch:
                var hx := String(key)
                var on := hx == hex
                var b: Button = _paint_swatch[key]
                b.add_theme_stylebox_override("normal", _paint_swatch_face(hx, on))
                b.add_theme_stylebox_override("hover", _paint_swatch_face(hx, on))
                b.add_theme_stylebox_override("pressed", _paint_swatch_face(hx, on))


## LEFT CLICK: in build mode you place / remove bricks, otherwise you paint.
func _brush_click(event: InputEvent) -> void:
        if _build_mode:
                _build_click(event as InputEventMouseButton)
        else:
                _paint_brick()


func _toggle_build_mode() -> void:
        _build_mode = not _build_mode
        if _build_mode:
                _notify("BUILD MODE — click places a brick in your brush color · CTRL+click removes one you built · B = back to painting", false)
        else:
                _notify("Back to the brush — click paints again.", false)


## BUILD MODE placement: ray out of the camera, sit a 4x1x4 stud brick flush
## on the face you aim at (grid-snapped), wearing the current brush color.
## CTRL+click removes a brick YOU placed (the map itself stays untouchable).
func _build_click(mb: InputEventMouseButton) -> void:
        var cam: Camera3D = get_viewport().get_camera_3d()
        if cam == null:
                return
        var mp := get_viewport().get_mouse_position()
        if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.is_first_person():
                mp = get_viewport().get_visible_rect().size * 0.5
        var from := cam.project_ray_origin(mp)
        var query := PhysicsRayQueryParameters3D.create(
                from, from + cam.project_ray_normal(mp) * 300.0, 1)
        var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty():
                return
        var body: Object = hit.get("collider")
        if body == null or not (body is StaticBody3D):
                return
        if mb.ctrl_pressed or mb.meta_pressed:
                # demolish — only bricks the player built, never the authored map
                if (body as Node).has_meta("built"):
                        (body as Node).queue_free()
                        _notify("Brick removed.", false)
                return
        # place: offset the brick half its size along the face normal so it
        # sits EXACTLY on the surface, then grid-snap the footprint
        var n: Vector3 = hit.get("normal", Vector3.UP)
        var half := Vector3(absf(n.x) * 2.0, absf(n.y) * 0.5, absf(n.z) * 2.0)
        var center: Vector3 = (hit.get("position", Vector3.ZERO) as Vector3) + Vector3(n.x * half.x, n.y * half.y, n.z * half.z)
        center.x = roundf(center.x)
        center.z = roundf(center.z)
        var brick := StaticBody3D.new()
        brick.collision_layer = 1
        brick.collision_mask = 0
        var cs := CollisionShape3D.new()
        var sh := BoxShape3D.new()
        sh.size = Vector3(4, 1, 4)
        cs.shape = sh
        brick.add_child(cs)
        var mi := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(4, 1, 4)
        mi.mesh = bm
        var m := StandardMaterial3D.new()
        m.albedo_color = _brush
        m.roughness = 0.78
        m.albedo_texture = WorldBuilderScript.stud_texture()
        m.uv1_triplanar = true
        m.uv1_world_triplanar = true
        m.uv1_scale = Vector3.ONE / WorldBuilderScript.STUD
        mi.material_override = m
        brick.add_child(mi)
        brick.position = center
        brick.add_to_group("paintable")   # the brush works on it too
        brick.set_meta("built", true)     # ...but it never counts as world progress
        _built_root.add_child(brick)


func _paint_brick() -> void:
        var cam: Camera3D = get_viewport().get_camera_3d()
        if cam == null:
                return
        var mp := get_viewport().get_mouse_position()
        if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.is_first_person():
                mp = get_viewport().get_visible_rect().size * 0.5
        var from := cam.project_ray_origin(mp)
        var query := PhysicsRayQueryParameters3D.create(
                from, from + cam.project_ray_normal(mp) * 300.0, 1)
        var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty():
                return
        var body: Object = hit.get("collider")
        if body == null or not (body is StaticBody3D) or not (body as Node).is_in_group("paintable"):
                return
        var mesh_node: MeshInstance3D = null
        for c in (body as Node).get_children():
                if c is MeshInstance3D:
                        mesh_node = c
                        break
        if mesh_node == null or mesh_node.material_override == null:
                return
        var mat := mesh_node.material_override as StandardMaterial3D
        if mat == null:
                return
        mat.albedo_color = _brush
        if mat.emission_enabled:
                mat.emission = _brush   # neon parts keep glowing in the NEW color
        if not _painted.has((body as Node).get_instance_id()) \
                        and not (body as Node).has_meta("built"):
                _painted[(body as Node).get_instance_id()] = true
                _update_paint_count()


func _update_paint_count() -> void:
        if _paint_count == null or not is_instance_valid(_paint_count):
                return
        _paint_count.text = "%d / %d painted" % [_painted.size(), _paint_total]
        if not _paint_done and _paint_total > 0 and _painted.size() >= _paint_total:
                _paint_done = true
                _notify("WORLD COMPLETE — you painted every brick!", true)
                _paint_count.text = "ALL PAINTED!"


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


# ---- the menu — v1 THE SIMPLE CARD ----------------------------------------
## A COMPACT, FLAT, QUIET card — nothing like the old banner panel. No
## RETROBLOX header, no clock, no gloss tabs, no key chips. One small
## centered dark card: two plain text tabs (People / Settings), the
## PEOPLE GRID (every player's LIVE AVATAR — drag to spin, wheel to zoom
## — with their NAME under it), and three flat buttons: Leave, Respawn,
## Resume. Simple UI beats busy UI.


func _build_menu() -> Control:
        var overlay := Control.new()
        overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.visible = false

        # the deep veil — the world keeps breathing behind the panel
        var dim := ColorRect.new()
        dim.name = "Dim"
        dim.color = RetroUI.NIGHT_VEIL
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.add_child(dim)

        # the centered panel — KINDA BIGGER (your order), still not full-bleed
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

        # ---- v1.1 THE TAB RAIL — the ROBLOX layout: a slim icon rail down
        # the LEFT (a person glyph for People, a gear for Settings), the
        # page on the right. Icons carry the menu now — black & white,
        # hand-drawn in code, no gloss, no banner, no clock.
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
                ["studio", "Studio", "layers"],
                ["settings", "Settings", "gear"],
        ]
        for td in tab_defs:
                var b := _tab_button(String(td[1]), String(td[2]))
                _tab_buttons[String(td[0])] = b
                rail.add_child(b)

        # the 1px rule between the rail and the page (the quiet divide)
        var rule := ColorRect.new()
        rule.name = "TabRule"
        rule.color = RetroUI.MENU_EDGE
        rule.custom_minimum_size = Vector2(1, 0)
        rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
        root.add_child(rule)

        # ---- the right column: the pages + the footer action row ----
        var right := VBoxContainer.new()
        right.name = "MenuRight"
        right.size_flags_vertical = Control.SIZE_EXPAND_FILL
        right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        root.add_child(right)
        var body := MarginContainer.new()
        body.name = "MenuBody"
        body.size_flags_vertical = Control.SIZE_EXPAND_FILL
        body.add_theme_constant_override("margin_left", 14)
        body.add_theme_constant_override("margin_right", 14)
        body.add_theme_constant_override("margin_top", 12)
        body.add_theme_constant_override("margin_bottom", 10)
        right.add_child(body)
        var pages := Control.new()
        pages.name = "Pages"
        pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
        pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        body.add_child(pages)

        # ---- PEOPLE — SIMPLE + ALIVE: a heading, then ONE grid.
        # Every card is a player: their real AVATAR LIVE on a 3D stage
        # (drag to spin them around, wheel to zoom in close) with their
        # NAME under it. No PFP fetches — the avatar IS the picture.
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
        # v3.10 FIX: inside the page's VBox the scroll collapsed to height 0
        # (VBox hands out MINIMUM heights) — expand to own the page.
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

        # ---- SETTINGS — the redesigned icon-row page + ACCOUNT (Log Out)
        _settings_tab = _build_settings_tab()
        _settings_tab.name = "SettingsPage"
        _settings_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
        _settings_tab.visible = false
        pages.add_child(_settings_tab)
        _pages["settings"] = _settings_tab

        # ---- v14.0 STUDIO — the organized edit page: a door per scene ----
        var studio_page := VBoxContainer.new()
        studio_page.name = "StudioPage"
        studio_page.set_anchors_preset(Control.PRESET_FULL_RECT)
        studio_page.add_theme_constant_override("separation", 8)
        studio_page.visible = false
        pages.add_child(studio_page)
        _pages["studio"] = studio_page
        var s_head := Label.new()
        s_head.text = "Studio"
        _title(s_head, 18, RetroUI.NIGHT_INK)
        studio_page.add_child(s_head)
        var s_hint := Label.new()
        s_hint.text = "Four editor scenes — for GAME DEVS. Players play; publish any game on the site and the editors unlock. Edits save to this device and ride with you."
        _text(s_hint, 12, RetroUI.NIGHT_INK_MUTED)
        s_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        studio_page.add_child(s_hint)
        for door in [
                ["UI EDITOR", "Drag & drop widgets to rebuild the client UI", "res://scenes/ui_editor.tscn"],
                ["MAP EDITOR", "Build maps brick by brick — your map becomes My Place", "res://scenes/map_editor.tscn"],
                ["PLAYER EDITOR", "Paint your avatar's skin, shirt and pants", "res://scenes/player_editor.tscn"],
        ]:
                var btn := Button.new()
                btn.text = "%s   ·   %s" % [door[0], door[1]]
                btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                btn.custom_minimum_size = Vector2(0, 40)
                btn.focus_mode = Control.FOCUS_NONE
                btn.add_theme_stylebox_override("normal", _row_btn(false))
                btn.add_theme_stylebox_override("hover", _row_btn(true))
                btn.add_theme_stylebox_override("pressed", _row_btn(false))
                if RetroUI.gotham(600) != null:
                        btn.add_theme_font_override("font", RetroUI.gotham(600))
                btn.add_theme_font_size_override("font_size", 13)
                btn.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
                btn.add_theme_color_override("font_hover_color", Color.WHITE)
                var scene_path := String(door[2])
                btn.pressed.connect(func() -> void:
                        # v15.0: editor doors are for GAME DEVS — players play
                        if not Session.is_dev:
                                _notify("GAME DEVS ONLY — %s is an editor scene. Publish any game on retro-blox.vercel.app and it unlocks." % String(door[0]))
                                return
                        get_tree().change_scene_to_file(scene_path))
                studio_page.add_child(btn)
        var s_note := Label.new()
        s_note.text = "The full STUDIO hub — with Open Game File — lives on the login screen."
        _text(s_note, 11, RetroUI.NIGHT_INK_FAINT)
        studio_page.add_child(s_note)

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

        # ---- the footer action row ----
        right.add_child(_menu_footer())
        set_tab.call("players")
        return overlay


## The panel's size — v1.1 KINDA BIGGER (your order): a real menu now,
## max 680 x 580 — the avatar stages get room, the settings breathe.
func _menu_panel_size() -> Vector2:
        var vp := Vector2(1280.0, 720.0)
        var viewport := get_viewport()
        if viewport != null:
                vp = viewport.get_visible_rect().size
        return Vector2(minf(vp.x * 0.58, 680.0), minf(vp.y * 0.84, 580.0))


## The panel face — v1 THE SIMPLE CARD: one deep, quiet, near-opaque
## dark surface with a hairline border. No gloss, no bevel, no glow.
func _menu_panel_style() -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.045, 0.058, 0.075, 0.97)
        sb.set_corner_radius_all(12)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.09)
        sb.shadow_color = Color(0, 0, 0, 0.45)
        sb.shadow_size = 28
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 12.0
        sb.content_margin_bottom = 12.0
        return sb


## One RAIL TAB — v1.1: an icon square (the hand-drawn glyph on top, the
## word under it). No gloss, no banner — the open tab is a white-ink glyph
## on a faint white pill, the rest stay muted gray.
func _tab_button(label: String, icon_kind: String) -> Button:
        var b := Button.new()
        b.tooltip_text = label
        b.custom_minimum_size = Vector2(70, 60)
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


## The rail tab faces — v1.1 MONOCHROME: flat quiet squares, the active
## one lifts (faint white pill) while its glyph + word light up white and
## the rest stay muted gray.
func _style_tab(b: Button, on: bool) -> void:
        var sb := StyleBoxFlat.new()
        sb.set_corner_radius_all(10)
        sb.anti_aliasing = true
        sb.bg_color = Color(1, 1, 1, 0.09) if on else Color(0, 0, 0, 0)
        sb.expand_margin_left = 4.0
        sb.expand_margin_right = 4.0
        b.add_theme_stylebox_override("normal", sb)
        var hb := StyleBoxFlat.new()
        hb.set_corner_radius_all(10)
        hb.anti_aliasing = true
        hb.bg_color = Color(1, 1, 1, 0.13) if on else Color(1, 1, 1, 0.05)
        hb.expand_margin_left = 4.0
        hb.expand_margin_right = 4.0
        b.add_theme_stylebox_override("hover", hb)
        b.add_theme_stylebox_override("pressed", sb)
        b.add_theme_stylebox_override("hover_pressed", sb)
        b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        var ink := Color.WHITE if on else Color(0.62, 0.66, 0.72)
        var glyph: Control = b.get_node_or_null("Glyph")
        if glyph != null and is_instance_valid(glyph):
                glyph.set("ink", ink)
        var l: Label = b.get_node_or_null("TabLabel")
        if l != null and is_instance_valid(l):
                _title(l, 12, ink, 600)


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


## The action row — v1.1 BLACK & WHITE (your order: no too much colors):
## three equal flat buttons — Leave · Respawn · Resume — all gray on the
## dark card, and RESUME is the primary: a WHITE button with black ink,
## exactly how the Roblox menu marks its main action. No red, no blue.
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


## One footer button — v1.1 FLAT MONOCHROME: one quiet face, one hover
## lift, no icons, no gloss, no key chips. Resume inverts (white face,
## black ink) — the primary carries itself.
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
        var ink := Color(0.92, 0.93, 0.95)
        if key == "ESC":
                ink = Color(0.07, 0.08, 0.10)
        for st in ["font_color", "font_hover_color"]:
                b.add_theme_color_override(st, ink)
        b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.7) if key != "ESC" else Color(0.1, 0.1, 0.12, 0.8))
        if RetroUI.gotham(600) != null:
                b.add_theme_font_override("font", RetroUI.gotham(600))
        b.add_theme_font_size_override("font_size", 13)
        b.pressed.connect(handler)
        return b


## The v1.1 flat footer faces — GRAY only, on the dark card: Leave wears a
## white hairline (the exit), Respawn stays plain, Resume is the WHITE card.
func _flat_key_face(key: String, hover: bool) -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        match key:
                "L":
                        sb.bg_color = Color(1, 1, 1, 0.07 if hover else 0.045)
                        sb.set_border_width_all(1)
                        sb.border_color = Color(1, 1, 1, 0.30 if hover else 0.20)
                "ESC":
                        sb.bg_color = Color(0.96, 0.96, 0.97) if hover else Color.WHITE
                _:
                        sb.bg_color = Color(1, 1, 1, 0.09 if hover else 0.05)
                        sb.set_border_width_all(1)
                        sb.border_color = Color(1, 1, 1, 0.10)
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


## The wide NIGHT row button — dark face, steel hairline, the hover lift,
## the pressed sink.
func _row_btn(hover := false, _pushed := false) -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.NIGHT_CARD_HI if hover else RetroUI.NIGHT_CARD
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = RetroUI.NIGHT_EDGE_LO
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


# ---- the player CARD — v12.3 SIMPLE: the avatar + the name ---------------

## One People-page card: the player's LIVE AVATAR (a real 3D rig you can
## drag to spin and zoom — the classic noob holds the seat until their
## look lands) and their NAME. That's the whole card. MY card wears the
## classic blue ring.
func _player_card(uid: String, uname: String, is_me: bool) -> PanelContainer:
        var card := PanelContainer.new()
        card.name = "Card_" + uid
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        # v9.0 FIX: the grid stretches its columns, but children only claim
        # their MINIMUM width unless they ask for more — without this the
        # cards collapse into skinny bars
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        card.add_theme_stylebox_override("panel", _card_casing(is_me))
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 7)
        card.add_child(box)

        # the avatar stage — the player's LIVE avatar: drag to spin them,
        # wheel to zoom. The rig dresses once per session and the camera
        # angle survives every 2.5s roster refresh (the viewer is cached).
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
        _title(name_l, 14, RetroUI.NIGHT_INK, 600)
        box.add_child(name_l)
        return card


func _card_casing(is_me: bool) -> StyleBox:
        # v1.1: the dark slate card — raised bevel face, steel hairline;
        # MY card wears the WHITE ring now (black & white only — the old
        # blue ring retired with the color order)
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.NIGHT_CARD
        sb.set_corner_radius_all(10)
        sb.anti_aliasing = true
        sb.set_border_width_all(2)
        sb.border_color = RetroUI.NIGHT_EDGE_LO
        if is_me:
                sb.border_color = Color.WHITE
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 10.0
        return sb


## The stage well — the deep night inset the LIVE avatar stands on.
func _well_texture_style() -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.NIGHT_WELL
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = RetroUI.NIGHT_EDGE_LO
        sb.content_margin_left = 4.0
        sb.content_margin_right = 4.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


## v12.4 THE LIVE PEOPLE — every card hosts the player's real rig on its
## own 3D stage. The VIEWER is cached per uid (your spin/zoom survive the
## roster refreshes; the rig dresses once per session) and the stage
## renders ONLY while the menu is open. No PFP anywhere — the avatar IS
## the picture.
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


## Resolve the player's payload (mine from the session, everyone else's
## from the public avatar endpoint, both cached) and hand it to the rig
## on their stage. An empty payload retries on the next roster refresh.
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


## The menu's pulse: the corner chip + header clock breathe every half
## second while the menu is open.
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
                if want_ping:
                        parts.append("PING %s" % (("%dms" % _last_ping_ms) if _last_ping_ms > 0 else "—"))
                parts.append("v1")
                _corner_stats.text = "   ·   ".join(parts)
        if _time_label != null and is_instance_valid(_time_label):
                _time_label.text = _clock_text()


## The page heading — the People page carries the live count like the real
## client's server roster.
func _update_people_title() -> void:
        if _people_title == null or not is_instance_valid(_people_title):
                return
        _people_title.text = "Players — %d" % _people_total


func _clock_text() -> String:
        var secs := int((Time.get_ticks_msec() - _session_start_ms) / 1000.0)
        return "%02d:%02d" % [floori(secs / 60.0), secs % 60]


# ---- the client's one-voice surfaces --------------------------------------


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


## The settings page — v1.1 THE COMPLETE REDESIGN (your order: "make a
## redesign to the settings and add way more settings... using Icons and
## a complete new redesign"). Every row carries a hand-drawn black &
## white ICON, every toggle is a pill SWITCH, sliders fill white, and the
## labels are HUMAN — "Bunny Hop", not "Bunny hop (hold Space to keep
## bouncing)". Way more settings, too: UI OPACITY, Invert Camera Y,
## VSync, Render Scale, Chat Bubbles join the crew — 18 live controls,
## all saved to disk. Black & white only.
func _build_settings_tab() -> VBoxContainer:
        var tab := VBoxContainer.new()
        tab.add_theme_constant_override("separation", 6)
        var settings: Node = get_node_or_null("/root/Settings")

        # the page SCROLLS — 18 settings is a lot of good
        var scroll := ScrollContainer.new()
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        var page := VBoxContainer.new()
        page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        page.add_theme_constant_override("separation", 10)
        scroll.add_child(page)
        tab.add_child(scroll)

        # ---- CONTROLS ------------------------------------------------
        _section(page, "mouse", "CONTROLS")
        _slider_row(page, "mouse", "Mouse Sensitivity", 0.1, 3.0,
                float(settings.get("mouse_sensitivity")) if settings != null else 1.0,
                func(v: float) -> String: return "%.2fx" % v,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("mouse_sensitivity", v))
        _row_toggle(page, "invert", "Invert Camera Y",
                bool(settings.get("invert_y")) if settings != null else false,
                func(on: bool) -> void:
                        if settings != null:
                                settings.set_key("invert_y", on))
        _shift_check = _row_toggle(page, "lock", "Shift Lock",
                bool(settings.get("shift_lock")) if settings != null else false,
                func(on: bool) -> void:
                        if settings != null:
                                settings.set_key("shift_lock", on)
                        camera_rig.shift_locked = on)

        # ---- CAMERA --------------------------------------------------
        _section(page, "camera", "CAMERA")
        _slider_row(page, "camera", "Field of View", 40.0, 110.0,
                float(settings.get("fov")) if settings != null else 70.0,
                func(v: float) -> String: return "%d°" % int(roundf(v)),
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("fov", v))

        # ---- AUDIO ---------------------------------------------------
        _section(page, "speaker", "AUDIO")
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
        _slider_row(page, "note", "Music", 0.0, 1.0,
                float(settings.get("music_volume")) if settings != null else 0.7,
                _fmt_pct,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("music_volume", v))

        # ---- GRAPHICS ------------------------------------------------
        _section(page, "monitor", "GRAPHICS")
        _row_toggle(page, "sun", "Sun Shadows",
                bool(settings.get("shadows")) if settings != null else true,
                func(on: bool) -> void:
                        if settings != null:
                                settings.set_key("shadows", on))
        _slider_row(page, "monitor", "Render Scale", 0.5, 1.0,
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
        _row_toggle(page, "expand", "Fullscreen",
                bool(settings.get("fullscreen")) if settings != null else false,
                func(on: bool) -> void:
                        if settings != null:
                                settings.set_key("fullscreen", on))
        _row_toggle(page, "sync", "VSync",
                bool(settings.get("vsync")) if settings != null else true,
                func(on: bool) -> void:
                        if settings != null:
                                settings.set_key("vsync", on))

        # ---- INTERFACE -----------------------------------------------
        _section(page, "layers", "INTERFACE")
        _slider_row(page, "layers", "UI Opacity", 0.3, 1.0,
                float(settings.get("ui_opacity")) if settings != null else 1.0,
                _fmt_pct,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("ui_opacity", v))
        _row_toggle(page, "chart", "Show FPS",
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

        # ---- CHARACTER -----------------------------------------------
        _section(page, "bounce", "CHARACTER")
        _row_toggle(page, "bounce", "Bunny Hop",
                bool(settings.get("bunny_hop")) if settings != null else true,
                func(on: bool) -> void:
                        if settings != null:
                                settings.set_key("bunny_hop", on))
        _row_chips(page, "person", "Play Animation",
                [["Sit", "Sit"], ["Climb", "Climb"], ["Walk", "Walk"],
                ["Jump", "Jump"], ["Idle", "Idle"], ["Stop", ""]],
                0,
                func(v: int) -> void: pass,
                func(txt: String) -> void:
                        if player != null and is_instance_valid(player):
                                player.avatar.call("play_emote", txt))

        # ---- ACCOUNT — who is signed in, and the ways OUT ------------
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
        # v13.1: THE UI EDITOR, discoverable — the same editor the F2 key
        # opens: drag any element, edit text, add labels, scale the client
        var uirow := _row(page, "reset", "Edit any part of the UI")
        var ui_btn := Button.new()
        ui_btn.text = "Open UI Editor (F2)"
        ui_btn.custom_minimum_size = Vector2(170, 30)
        ui_btn.focus_mode = Control.FOCUS_NONE
        ui_btn.add_theme_stylebox_override("normal", _hairline_btn_face(false))
        ui_btn.add_theme_stylebox_override("hover", _hairline_btn_face(true))
        ui_btn.add_theme_stylebox_override("pressed", _hairline_btn_face(false))
        for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                ui_btn.add_theme_color_override(st, Color(0.92, 0.93, 0.95))
        if RetroUI.gotham(600) != null:
                ui_btn.add_theme_font_override("font", RetroUI.gotham(600))
        ui_btn.add_theme_font_size_override("font_size", 12)
        ui_btn.pressed.connect(func() -> void:
                # v15.0: UI editing is a game-dev power — players play
                if not Session.is_dev:
                        _notify("GAME DEVS ONLY — the UI editor is an editor scene. Publish any game on retro-blox.vercel.app and it unlocks.")
                        return
                _toggle_menu()
                UiEditor.toggle())
        uirow.add_child(ui_btn)
        var danger := _row(page, "reset", "Start everything over")
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
                camera_rig.shift_locked = false
                _apply_nameplates()
                _update_live_stats()
                _rebuild_settings_tab()
                _notify("All settings reset", true))
        danger.add_child(reset_btn)
        return tab


# ---- v1.1 settings helpers — the icon row kit -----------------------------

## One section header: a small glyph + the caps title, quiet gray.
func _section(page: VBoxContainer, kind: String, text: String) -> void:
        var head := HBoxContainer.new()
        head.add_theme_constant_override("separation", 7)
        page.add_child(head)
        var ic := MenuIcons.new()
        ic.kind = kind
        ic.custom_minimum_size = Vector2(15, 15)
        ic.ink = Color(0.55, 0.58, 0.64)
        ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
        head.add_child(ic)
        var l := Label.new()
        l.text = text
        _title(l, 12, Color(0.55, 0.58, 0.64), 700)
        head.add_child(l)


## One settings row: the icon, the human label, and room on the right for
## the caller's control (a switch, a slider, chips...). Returns the row.
func _row(parent: VBoxContainer, kind: String, label_text: String) -> HBoxContainer:
        var r := HBoxContainer.new()
        r.add_theme_constant_override("separation", 10)
        parent.add_child(r)
        var ic := MenuIcons.new()
        ic.kind = kind
        ic.custom_minimum_size = Vector2(18, 18)
        ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
        r.add_child(ic)
        var l := Label.new()
        l.text = label_text
        l.clip_text = true
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        _text(l, 13, RetroUI.NIGHT_INK)
        r.add_child(l)
        return r


## A pill SWITCH row (the toggle voice of the new page): white pill +
## black ON when live, faint dark pill + gray OFF otherwise. Fully
## monochrome — no green, no blue.
func _row_toggle(parent: VBoxContainer, kind: String, label_text: String, value: bool, on_toggle: Callable) -> Button:
        var r := _row(parent, kind, label_text)
        var sw := Button.new()
        sw.toggle_mode = true
        sw.button_pressed = value
        sw.custom_minimum_size = Vector2(56, 24)
        sw.focus_mode = Control.FOCUS_NONE
        _style_switch(sw, value)
        sw.toggled.connect(func(on: bool) -> void:
                _style_switch(sw, on)
                on_toggle.call(on))
        r.add_child(sw)
        return sw


func _style_switch(sw: Button, on: bool) -> void:
        var face := StyleBoxFlat.new()
        face.set_corner_radius_all(12)
        face.anti_aliasing = true
        face.content_margin_left = 12.0
        face.content_margin_right = 12.0
        face.content_margin_top = 3.0
        face.content_margin_bottom = 3.0
        if on:
                face.bg_color = Color.WHITE
        else:
                face.bg_color = Color(1, 1, 1, 0.07)
                face.set_border_width_all(1)
                face.border_color = Color(1, 1, 1, 0.16)
        sw.add_theme_stylebox_override("normal", face)
        var hv := face.duplicate() as StyleBoxFlat
        if on:
                hv.bg_color = Color(0.85, 0.86, 0.89)
        else:
                hv.bg_color = Color(1, 1, 1, 0.12)
        sw.add_theme_stylebox_override("hover", hv)
        sw.add_theme_stylebox_override("pressed", face)
        sw.text = "ON" if on else "OFF"
        sw.add_theme_color_override("font_color", Color(0.07, 0.08, 0.10) if on else RetroUI.NIGHT_INK_MUTED)
        sw.add_theme_color_override("font_hover_color", Color(0.07, 0.08, 0.10) if on else RetroUI.NIGHT_INK)
        sw.add_theme_color_override("font_pressed_color", Color(0.07, 0.08, 0.10) if on else RetroUI.NIGHT_INK_MUTED)
        if RetroUI.gotham(700) != null:
                sw.add_theme_font_override("font", RetroUI.gotham(700))
        sw.add_theme_font_size_override("font_size", 10)


## A slider row — icon, human label, the WHITE slider, and the value in
## human units (percents, degrees, multipliers) on the right.
func _slider_row(parent: VBoxContainer, kind: String, label_text: String, minv: float, maxv: float, value: float, fmt: Callable, on_change: Callable) -> void:
        var r := _row(parent, kind, label_text)
        var s := HSlider.new()
        s.min_value = minv
        s.max_value = maxv
        s.step = 0.01
        s.value = value
        s.custom_minimum_size = Vector2(130, 20)
        s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        s.focus_mode = Control.FOCUS_NONE
        _paper_slider(s)
        r.add_child(s)
        var v := Label.new()
        v.text = String(fmt.call(value))
        v.custom_minimum_size = Vector2(46, 0)
        v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        _text(v, 12, RetroUI.NIGHT_INK_MUTED)
        r.add_child(v)
        s.value_changed.connect(func(val: float) -> void:
                v.text = String(fmt.call(val))
                on_change.call(val))


## A chip row (Max FPS, Play Animation): small square chips, the picked
## one wears the WHITE face with black ink — the monochrome pick mark.
func _row_chips(parent: VBoxContainer, kind: String, label_text: String, opts: Array, value: int, on_pick: Callable, on_text: Callable = Callable()) -> void:
        var r := _row(parent, kind, label_text)
        var chips := HBoxContainer.new()
        chips.add_theme_constant_override("separation", 5)
        r.add_child(chips)
        var btns: Array[Button] = []
        for opt in opts:
                var val: Variant = opt[1]
                var cb := Button.new()
                cb.text = String(opt[0])
                cb.custom_minimum_size = Vector2(0, 26)
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


## Paint the chip row for VALUE picks (Max FPS): the picked chip inverts.
func _style_chips(btns: Array[Button], value: int) -> void:
        for b in btns:
                if not is_instance_valid(b):
                        continue
                var on: bool = int(b.get_meta("chip_value")) == value
                b.add_theme_stylebox_override("normal", _chip_face(on))
                b.add_theme_stylebox_override("hover", _chip_face(on, true))
                b.add_theme_stylebox_override("pressed", _chip_face(on))
                var ink := Color(0.07, 0.08, 0.10) if on else RetroUI.NIGHT_INK_MUTED
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st, ink)


## The Animation chips are momentary (no persistent pick) — all quiet.
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
        sb.set_corner_radius_all(7)
        sb.anti_aliasing = true
        sb.content_margin_left = 9.0
        sb.content_margin_right = 9.0
        sb.content_margin_top = 3.0
        sb.content_margin_bottom = 3.0
        if on:
                sb.bg_color = Color(0.85, 0.86, 0.89) if hover else Color.WHITE
        else:
                sb.bg_color = Color(1, 1, 1, 0.12 if hover else 0.06)
                sb.set_border_width_all(1)
                sb.border_color = Color(1, 1, 1, 0.16 if hover else 0.10)
        return sb


## The Log Out face — the WHITE pill (the account's primary action).
func _white_btn_face(hover: bool) -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.bg_color = Color(0.85, 0.86, 0.89) if hover else Color.WHITE
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 5.0
        sb.content_margin_bottom = 5.0
        return sb


## The Reset face — dark with a white hairline (the careful action).
func _hairline_btn_face(hover: bool) -> StyleBox:
        var sb := StyleBoxFlat.new()
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.bg_color = Color(1, 1, 1, 0.08 if hover else 0.045)
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.28 if hover else 0.18)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 5.0
        sb.content_margin_bottom = 5.0
        return sb


## The percent voice — "80%" (volumes, opacity, render scale).
func _fmt_pct(v: float) -> String:
        return "%d%%" % int(roundf(v * 100.0))


## v12.1 — LOG OUT: the session is wiped (the saved token too) and the
## client lands back on the OLD LOGIN PAGE — the white RETROBLOX card with
## the classic Log In key, ready for whoever signs in next.
func _log_out() -> void:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        Api.clear_session()
        Session.reset()
        get_tree().change_scene_to_file("res://scenes/login.tscn")


## v12.0 — RESET: rebuild the whole Settings page so every slider, check
## and chip re-reads the (now default) Settings values.
func _rebuild_settings_tab() -> void:
        if _settings_tab == null or not is_instance_valid(_settings_tab):
                return
        for child in _settings_tab.get_children():
                child.queue_free()
        var fresh := _build_settings_tab()
        fresh.name = "SettingsPageInner"
        fresh.set_anchors_preset(Control.PRESET_FULL_RECT)
        _settings_tab.add_child(fresh)


## v12.0 — SEE PLAYER NAMES: stamps (or clears) every rig's nameplate,
## mine and everyone the presence feed knows about.
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


func _hspace(_h: int) -> Control:
        # kept for older callers — the new settings page builds its own spacing
        var c := Control.new()
        return c


## v1.1: the slider voice on the NIGHT panel — a deep groove with the
## WHITE fill (black & white only now, visible on dark).
func _paper_slider(s: HSlider) -> void:
        var groove := StyleBoxFlat.new()
        groove.bg_color = RetroUI.NIGHT_EDGE_LO
        groove.set_corner_radius_all(3)
        groove.content_margin_top = 3.0
        groove.content_margin_bottom = 3.0
        s.add_theme_stylebox_override("slider", groove)
        s.add_theme_stylebox_override("grabber_area", RetroUI.flat(3, Color.WHITE))
        s.add_theme_stylebox_override("grabber_area_highlight", RetroUI.flat(3, Color(0.85, 0.86, 0.89)))


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
                # the roster is on screen the moment the menu opens, and every
                # card kicks its (cached) avatar render from here
                _refresh_player_list(_last_presence)
                _update_live_stats()
        else:
                _menu.modulate.a = 1.0
                camera_rig.set_ui_blocked(false)


# ---------------------------------------------------------------- events

func _on_health_changed(hp: float, max_hp: float) -> void:
        var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
        _custom_health01 = ratio
        _health_value.text = str(int(roundf(hp)))
        # v12.1: the VERTICAL bar — the fill CLIMBS from the bottom edge and
        # its face lerp green -> red with the health
        var sb: StyleBoxFlat = _health_fill_style(ratio)
        _health_fill.add_theme_stylebox_override("panel", sb)
        var inner := _health_track_h - 6.0
        _health_fill.offset_top = 3.0 + inner * (1.0 - ratio)
        # v14.0: the UI Editor's health bar widgets breathe with you too
        for hb in _custom_healthbars:
                if is_instance_valid(hb):
                        (hb as ProgressBar).value = ratio * 100.0


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
        chat.add_chat(uname, seq, text, "", uid == Session.user_id, uid)
        # the classic bubble pops over the speaker's head — v1.1: the CHAT
        # BUBBLES setting can silence them (the chat log still carries all)
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
                if uid == "" or uid == Session.user_id:
                        continue
                seen[uid] = true
                _names_by_uid[uid] = String(p.get("username", ""))
                var pos_arr: Array = p.get("pos", [0, 0, 0])
                var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
                if _remotes.has(uid):
                        _remotes[uid].update_state(pos, float(p.get("heading", 0.0)))
                else:
                        var rp := RemotePlayerScript.new()
                        add_child(rp)
                        rp.setup(uid, String(p.get("username", "Player")))
                        # v12.0: a joiner respects the SEE PLAYER NAMES setting
                        var setg: Node = get_node_or_null("/root/Settings")
                        if setg != null and not bool(setg.get("player_names")):
                                rp.get("avatar").call("set_display_name", "")
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
                # v12.3 FIX: the dresser (and the portrait renderer) want the
                # INNER avatar payload — colors/body/shirt/pants — not the
                # full response wrapper. The old code fed them the wrapper
                # and remote players dressed as plain noobs.
                var raw: Variant = res.get("avatar", null)
                var payload: Dictionary = raw if raw is Dictionary else {}
                Session.cache_avatar(uid, payload)
                await rp.dress(Api, payload)


## The People page: me first (the blue ring), then everyone the presence
## feed reports — ONE simple grid of LIVE avatar cards, rebuilt only while
## the menu is open; the viewers are cached so nothing re-dresses.
func _refresh_player_list(players: Array) -> void:
        if _players_grid == null or not is_instance_valid(_players_grid):
                return
        for child in _players_grid.get_children():
                child.queue_free()
        var total := 1 + players.size()
        _people_total = total
        _update_people_title()
        var seen := {}
        # my card first — the blue-ringed one
        _players_grid.add_child(_player_card(Session.user_id, Session.username, true))
        seen[Session.user_id] = true
        for p in players:
                var uid := String(p.get("userId", ""))
                var uname := String(p.get("username", ""))
                if uid == "" or uid == Session.user_id or uname == "":
                        continue
                _names_by_uid[uid] = uname
                seen[uid] = true
                _players_grid.add_child(_player_card(uid, uname, false))
        # anyone who left: their stage goes with them
        for uid in _viewers.keys():
                if not seen.has(uid):
                        if is_instance_valid(_viewers[uid]):
                                _viewers[uid].queue_free()
                        _viewers.erase(uid)
                        _viewer_dressed.erase(uid)
                        _viewer_pending.erase(uid)
        _update_live_stats()
