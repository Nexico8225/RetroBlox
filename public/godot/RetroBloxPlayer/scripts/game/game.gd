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
const RESPAWN_SECONDS := 2.8

var place: Dictionary
var player            # LocalPlayer — untyped: custom members, dynamic calls
var camera_rig        # CameraRig
var chat              # ChatBox
var hud: CanvasLayer

var _health_fill: ColorRect
var _health_value: Label
var _menu: Control
var _menu_card: PanelContainer
var _players_tab: VBoxContainer
var _settings_tab: VBoxContainer
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


func _ready() -> void:
        place = Session.current_place
        if place.is_empty():
                # the hub is retired: signing in drops you straight into the classic
                # baseplate — sign in and just play
                place = PlacesScript.by_id("baseplate")

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
                        Api.place_presence(String(place["id"]), player.global_position, player.heading)


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


func _pill_btn_style(hover: bool) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, 0.12) if hover else Color(0, 0, 0, 0)
        sb.set_corner_radius_all(16)
        return sb


func _badge_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("e2231a")
        sb.set_corner_radius_all(9)
        sb.content_margin_left = 5.0
        sb.content_margin_right = 5.0
        sb.content_margin_top = 1.0
        sb.content_margin_bottom = 1.0
        return sb


# ---- vertical health bar (right edge, like the video) -------------------

func _build_health() -> void:
        var holder := VBoxContainer.new()
        holder.name = "HealthBar"
        holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        holder.offset_left = -74.0
        holder.offset_right = -14.0
        holder.offset_top = -120.0
        holder.offset_bottom = 120.0
        holder.alignment = BoxContainer.ALIGNMENT_CENTER
        holder.add_theme_constant_override("separation", 4)
        hud.add_child(holder)

        # the bar: white track + green fill rising from the bottom
        var track_holder := Control.new()
        track_holder.custom_minimum_size = Vector2(10, 150)
        track_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        track_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(track_holder)
        var track := ColorRect.new()
        track.color = Color(1, 1, 1, 0.85)
        track.mouse_filter = Control.MOUSE_FILTER_IGNORE
        track.set_anchors_preset(Control.PRESET_FULL_RECT)
        track_holder.add_child(track)
        _health_fill = ColorRect.new()
        _health_fill.color = Color("3fd432")
        _health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _health_fill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        _health_fill.offset_top = -150.0
        track_holder.add_child(_health_fill)

        var label := Label.new()
        label.text = "Health"
        label.add_theme_font_size_override("font_size", 17)
        label.add_theme_color_override("font_color", Color("1b3fbf"))
        label.add_theme_color_override("font_outline_color", Color.WHITE)
        label.add_theme_constant_override("outline_size", 6)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        holder.add_child(label)

        _health_value = Label.new()
        _health_value.text = "100"
        _health_value.add_theme_font_size_override("font_size", 14)
        _health_value.add_theme_color_override("font_color", Color.WHITE)
        _health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var chip := PanelContainer.new()
        chip.add_theme_stylebox_override("panel", _chip_style())
        chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


# ---- the menu (dark card, Players + Settings tabs) ----------------------


func _dark_panel() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.07, 0.11, 0.16, 0.82)
        sb.set_border_width_all(2)
        sb.border_color = Color(0.02, 0.05, 0.08, 0.9)
        sb.set_corner_radius_all(4)
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


func _build_menu() -> Control:
        var overlay := Control.new()
        overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.visible = false
        var dim := ColorRect.new()
        dim.color = Color(0.02, 0.05, 0.09, 0.68)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.add_child(dim)
        # v3.7 RETRO MENU — the steel plate now sits inside a chunky "client
        # shell": a deep-navy case with a gold pinline, sharp corners, and
        # keycap-bevel buttons that sink when pressed. Pure 2006.
        var frame := PanelContainer.new()
        frame.name = "MenuFrame"
        frame.add_theme_stylebox_override("panel", _menu_frame_style())
        frame.set_anchors_preset(Control.PRESET_CENTER)
        frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
        frame.grow_vertical = Control.GROW_DIRECTION_BOTH
        overlay.add_child(frame)
        _menu_card = PanelContainer.new()
        _menu_card.add_theme_stylebox_override("panel", _card_style())
        frame.add_child(_menu_card)
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(460, 0)
        box.add_theme_constant_override("separation", 10)
        _menu_card.add_child(box)

        # the menu crown: YOUR uploaded ReTROBLOX wordmark (red-outlined
        # classic letters) over a wooden signboard header — pure 2011 energy
        var wordmark_path := "res://assets/ui/wordmark.png"
        if ResourceLoader.exists(wordmark_path):
                var sign := PanelContainer.new()
                sign.add_theme_stylebox_override("panel", RetroUI.wood_style())
                var wm := TextureRect.new()
                wm.texture = load(wordmark_path)
                wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                wm.custom_minimum_size = Vector2(0, 56)
                wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
                sign.add_child(wm)
                box.add_child(sign)
                # the gold pinline under the sign — the retro case's trim line
                var trim := ColorRect.new()
                trim.color = Color("ffd23f")
                trim.custom_minimum_size = Vector2(0, 2)
                trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
                box.add_child(trim)
        else:
                var title := Label.new()
                title.text = "RETROBLOX"
                title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                title.add_theme_color_override("font_color", Color.WHITE)
                var pixel: Font = RetroUI.pixel_font()
                if pixel != null:
                        title.add_theme_font_override("font", pixel)
                        title.add_theme_font_size_override("font_size", 15)
                        title.add_theme_color_override("font_color", Color("ffd23f"))
                else:
                        title.add_theme_font_size_override("font_size", 22)
                box.add_child(title)
        var sub := Label.new()
        sub.text = String(place.get("name", "a classic place"))
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_color_override("font_color", Color("9fc1d4"))
        var sub_pixel: Font = RetroUI.pixel_font()
        if sub_pixel != null:
                sub.add_theme_font_override("font", sub_pixel)
                sub.add_theme_font_size_override("font_size", 9)
        else:
                sub.add_theme_font_size_override("font_size", 12)
        box.add_child(sub)

        # ---- tabs — chunky retro keycaps, green when selected ----
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 6)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        var players_btn := Button.new()
        players_btn.text = "PLAYERS"
        players_btn.toggle_mode = true
        players_btn.custom_minimum_size = Vector2(126, 34)
        players_btn.focus_mode = Control.FOCUS_NONE
        var settings_btn := Button.new()
        settings_btn.text = "SETTINGS"
        settings_btn.toggle_mode = true
        settings_btn.custom_minimum_size = Vector2(126, 34)
        settings_btn.focus_mode = Control.FOCUS_NONE
        for tab_btn in [players_btn, settings_btn]:
                tab_btn.add_theme_stylebox_override("normal", _tab_bevel(false))
                tab_btn.add_theme_stylebox_override("hover", _tab_bevel(false, true))
                tab_btn.add_theme_stylebox_override("pressed", _tab_bevel(true))
                tab_btn.add_theme_stylebox_override("hover_pressed", _tab_bevel(true))
                tab_btn.add_theme_font_size_override("font_size", 10)
        tabs.add_child(players_btn)
        tabs.add_child(settings_btn)

        # ---- pages ----
        var pages := Control.new()
        pages.custom_minimum_size = Vector2(0, 260)
        box.add_child(pages)
        _players_tab = VBoxContainer.new()
        _players_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
        _players_tab.add_theme_constant_override("separation", 4)
        pages.add_child(_players_tab)
        _settings_tab = _build_settings_tab()
        _settings_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
        pages.add_child(_settings_tab)

        var set_tab := func(tab: String) -> void:
                _players_tab.visible = tab == "players"
                _settings_tab.visible = tab == "settings"
                players_btn.button_pressed = tab == "players"
                settings_btn.button_pressed = tab == "settings"
        players_btn.pressed.connect(func() -> void: set_tab.call("players"))
        settings_btn.pressed.connect(func() -> void: set_tab.call("settings"))
        _menu_switch = set_tab

        # ---- actions row ----
        var actions := HBoxContainer.new()
        actions.add_theme_constant_override("separation", 8)
        box.add_child(actions)
        var resume := Button.new()
        resume.text = "Resume"
        resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        resume.custom_minimum_size = Vector2(0, 44)
        resume.focus_mode = Control.FOCUS_NONE
        resume.add_theme_stylebox_override("normal", _bevel_btn(Color("2f9e44")))
        resume.add_theme_stylebox_override("hover", _bevel_btn(Color("37b64f")))
        resume.add_theme_stylebox_override("pressed", _bevel_btn(Color("278139"), true))
        resume.add_theme_color_override("font_color", Color.WHITE)
        resume.add_theme_font_size_override("font_size", 11)
        resume.pressed.connect(_toggle_menu)
        actions.add_child(resume)

        var respawn := Button.new()
        respawn.text = "Reset Character"
        respawn.custom_minimum_size = Vector2(150, 44)
        respawn.focus_mode = Control.FOCUS_NONE
        respawn.add_theme_stylebox_override("normal", _bevel_btn(Color("3a4b58")))
        respawn.add_theme_stylebox_override("hover", _bevel_btn(Color("48606f")))
        respawn.add_theme_stylebox_override("pressed", _bevel_btn(Color("2c3944"), true))
        respawn.add_theme_color_override("font_color", Color.WHITE)
        respawn.add_theme_font_size_override("font_size", 11)
        respawn.pressed.connect(func() -> void:
                _toggle_menu()
                if player.alive:
                        player.die(self)
                _start_respawn())
        actions.add_child(respawn)

        var leave := Button.new()
        leave.text = "Leave"
        leave.custom_minimum_size = Vector2(110, 44)
        leave.focus_mode = Control.FOCUS_NONE
        leave.add_theme_stylebox_override("normal", _bevel_btn(Color("b3261e")))
        leave.add_theme_stylebox_override("hover", _bevel_btn(Color("d13a30")))
        leave.add_theme_stylebox_override("pressed", _bevel_btn(Color("8f1d17"), true))
        leave.add_theme_color_override("font_color", Color.WHITE)
        leave.add_theme_font_size_override("font_size", 11)
        leave.pressed.connect(_leave_game)
        actions.add_child(leave)

        # LOG OUT — wipes the saved session and returns to the login gate
        var logout := Button.new()
        logout.text = "Log Out"
        logout.custom_minimum_size = Vector2(110, 44)
        logout.focus_mode = Control.FOCUS_NONE
        logout.add_theme_stylebox_override("normal", _bevel_btn(Color("4a3a55")))
        logout.add_theme_stylebox_override("hover", _bevel_btn(Color("5c4a6b")))
        logout.add_theme_stylebox_override("pressed", _bevel_btn(Color("3a2d44"), true))
        logout.add_theme_color_override("font_color", Color.WHITE)
        logout.add_theme_font_size_override("font_size", 11)
        logout.pressed.connect(func() -> void:
                Api.clear_session()
                Session.reset()
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
                get_tree().change_scene_to_file("res://scenes/login.tscn"))
        actions.add_child(logout)

        var hint := Label.new()
        hint.text = "ENTER chat · ESC resume · R reset character · L leave"
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hint.add_theme_color_override("font_color", Color(0.55, 0.64, 0.72))
        var hint_pixel: Font = RetroUI.pixel_font()
        if hint_pixel != null:
                hint.add_theme_font_override("font", hint_pixel)
                hint.add_theme_font_size_override("font_size", 8)
        else:
                hint.add_theme_font_size_override("font_size", 11)
        box.add_child(hint)
        set_tab.call("players")
        return overlay


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
        anim_title.add_theme_font_size_override("font_size", 13)
        anim_title.add_theme_color_override("font_color", Color(0.72, 0.8, 0.87))
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
                b.add_theme_stylebox_override("normal", _bevel_btn(Color("3a4b58")))
                b.add_theme_stylebox_override("hover", _bevel_btn(Color("48606f")))
                b.add_theme_stylebox_override("pressed", _bevel_btn(Color("2c3944"), true))
                b.add_theme_color_override("font_color", Color.WHITE)
                b.add_theme_font_size_override("font_size", 9)
                var clip: String = "" if anim == "Stop" else anim
                b.pressed.connect(func() -> void:
                        if player != null and is_instance_valid(player):
                                player.avatar.call("play_emote", clip))
                grid.add_child(b)
        return tab


func _slider_row(parent: VBoxContainer, label_text: String, minv: float, maxv: float, value: float, on_change: Callable) -> void:
        var l := Label.new()
        l.text = "%s  —  %.2f" % [label_text, value]
        l.add_theme_font_size_override("font_size", 12)
        l.add_theme_color_override("font_color", Color(0.8, 0.87, 0.92))
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


## v3.7 RETRO KEYCAP — chunky bevel button: sharp corners, a thick darker
## bottom edge and a hard drop shadow; `pushed` sinks the keycap for the
## pressed state. This is the signature look of the new ESC menu.
func _bevel_btn(bg: Color, pushed := false) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.set_corner_radius_all(2)
        sb.border_color = bg.darkened(0.5)
        sb.set_border_width_all(2)
        sb.border_width_bottom = 3 if pushed else 6   # the keycap edge
        sb.shadow_color = Color(0, 0, 0, 0.4)
        sb.shadow_size = 0
        sb.shadow_offset = Vector2(0, 1) if pushed else Vector2(0, 3)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 7.0
        sb.content_margin_bottom = 6.0 if pushed else 8.0
        return sb


## v3.7 RETRO TAB — the menu's tab keycaps: steel when idle, classic green
## when selected, both with the chunky bottom edge.
func _tab_bevel(on: bool, hovered := false) -> StyleBoxFlat:
        var sb := _bevel_btn(Color("2f9e44") if on else (Color("42586a") if hovered else Color("1d2833")))
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 5.0
        return sb


## v3.7 RETRO CASE — the menu now sits in a deep-navy shell with a dark-gold
## pinline and a wide soft shadow, like a 2006 client window.
func _menu_frame_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.045, 0.062, 0.09)
        sb.set_corner_radius_all(4)
        sb.border_color = Color("8a6d1d")
        sb.set_border_width_all(3)
        sb.shadow_color = Color(0, 0, 0, 0.55)
        sb.shadow_size = 16
        sb.shadow_offset = Vector2(0, 5)
        sb.content_margin_left = 5.0
        sb.content_margin_right = 5.0
        sb.content_margin_top = 5.0
        sb.content_margin_bottom = 5.0
        return sb


func _card_style() -> StyleBox:
        # the ESC menu wears the real brushed-steel plate (an internet image),
        # darkened so the light text stays crisp — pure 2006 client vibes
        var tex: Texture2D = RetroUI.steel_texture()
        if tex != null:
                var sb := StyleBoxTexture.new()
                sb.texture = tex
                sb.modulate_color = Color(0.6, 0.66, 0.76, 0.98)
                sb.content_margin_left = 18.0
                sb.content_margin_right = 18.0
                sb.content_margin_top = 14.0
                sb.content_margin_bottom = 14.0
                return sb
        var flat := StyleBoxFlat.new()
        flat.bg_color = Color(0.075, 0.10, 0.13, 0.97)
        flat.set_corner_radius_all(10)
        flat.border_color = Color(1, 1, 1, 0.08)
        flat.set_border_width_all(1)
        flat.content_margin_left = 18.0
        flat.content_margin_right = 18.0
        flat.content_margin_top = 14.0
        flat.content_margin_bottom = 14.0
        return flat


func _toggle_menu() -> void:
        if _menu == null or not is_instance_valid(_menu):
                return
        _menu_open = not _menu_open
        _menu.visible = _menu_open
        if _menu_open:
                camera_rig.set_ui_blocked(true)
                _refresh_player_list([])
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
        var res: Dictionary = await Api.place_chat_get(String(place["id"]))
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
        _refresh_player_list(players)


func _dress_remote(rp: Node3D, uid: String) -> void:
        var res: Dictionary = await Api.avatar_of(uid)
        if res.get("ok", false) and is_instance_valid(rp):
                Session.cache_avatar(uid, res)
                await rp.dress(Api, res)


func _refresh_player_list(players: Array) -> void:
        for child in _players_tab.get_children():
                child.queue_free()
        var title := Label.new()
        var total := 1 + players.size()
        title.text = "%d %s in %s" % [total, "player" if total == 1 else "players", String(place.get("name", "the place"))]
        title.add_theme_font_size_override("font_size", 14)
        title.add_theme_color_override("font_color", Color.WHITE)
        _players_tab.add_child(title)
        _add_player_row(Session.display_tag(), true)
        for p in players:
                var uname := String(p.get("username", ""))
                if uname == "" or String(p.get("userId", "")) == Session.user_id:
                        continue
                _add_player_row(uname, false)


func _add_player_row(text: String, is_me: bool) -> void:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        var dot := ColorRect.new()
        dot.custom_minimum_size = Vector2(10, 10)
        dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        dot.color = Color("3fd432") if is_me else Color("5aa8e8")
        row.add_child(dot)
        var l := Label.new()
        l.text = text + ("  (you)" if is_me else "")
        l.add_theme_font_size_override("font_size", 13)
        l.add_theme_color_override("font_color", Color(0.88, 0.93, 0.97))
        row.add_child(l)
        _players_tab.add_child(row)
