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
var _toast_box: VBoxContainer
var _shift_check: CheckButton
var _tix_label: Label
var _tix_total := 0
var _tix_got := 0


func _ready() -> void:
        place = Session.current_place
        if place.is_empty():
                place = PlacesScript.by_id("baseplate")

        var built: Dictionary = WorldBuilderScript.build(place)
        add_child(built["root"])
        _spawns = built["spawns"]
        if _spawns.is_empty():
                _spawns.append(Vector3(0.0, 6.0, 0.0) * WorldBuilderScript.STUD)

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
        _hook_coins()
        _setup_audio()

        # ---- camera ----
        camera_rig = CameraRigScript.new()
        add_child(camera_rig)
        camera_rig.setup(player)
        camera_rig.set_mouse_captured(true)
        var settings: Node = get_node_or_null("/root/Settings")
        if settings != null:
                camera_rig.shift_locked = bool(settings.get("shift_lock"))

        _build_hud()

        chat.add_system("Welcome to %s!" % String(place.get("name", "the place")))
        if Session.is_guest:
                chat.add_system("You are a guest — watch the chat, sign up on RetroBlox to talk and show online.")
        else:
                chat.add_system("Chat + players are live across the internet. Say hi!")


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
        var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        var jump := Input.is_action_just_pressed("jump")
        player.drive(delta, dir, camera_rig.drive_yaw(), jump, camera_rig.shift_locked)

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
        if event.is_action_pressed("ui_cancel"):
                _toggle_menu()
                get_viewport().set_input_as_handled()
        elif event.is_action_pressed("ui_text_submit") or (event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ENTER):
                if not _menu_open and not chat.is_open:
                        chat.open()
                        camera_rig.set_mouse_captured(false)
                        get_viewport().set_input_as_handled()
        elif event.is_action_pressed("toggle_players"):
                _open_menu("players")
                get_viewport().set_input_as_handled()
        elif event.is_action_pressed("shift_lock"):
                # classic SHIFT toggle — squares the character up to the camera
                var on: bool = not camera_rig.shift_locked
                camera_rig.shift_locked = on
                var st: Node = get_node_or_null("/root/Settings")
                if st != null:
                        st.call("set_key", "shift_lock", on)
                if _shift_check != null and is_instance_valid(_shift_check):
                        _shift_check.set_pressed_no_signal(on)
                _notify("Shift lock ON — character follows the camera, ladders off" if on else "Shift lock OFF")
                get_viewport().set_input_as_handled()
        elif event is InputEventMouseButton and event.is_pressed():
                # click the world to recapture the mouse after menus / chat
                if not _menu_open and not chat.is_open and not camera_rig.is_mouse_captured():
                        camera_rig.set_mouse_captured(true)


# ---------------------------------------------------------------- HUD

## The HUD from the reference video: a black rounded TOPBAR PILL (logo /
## menu / chat with unread badge) top-left, a VERTICAL HEALTH BAR on the
## right, a hotbar slot bottom-center ("1 Tix Bag"), join toasts top-center,
## translucent dark chat bottom-left, and a dark settings card in the menu.
func _build_hud() -> void:
        hud = CanvasLayer.new()
        hud.name = "HUD"
        add_child(hud)

        # chat FIRST — the topbar's chat button + unread badge wire to it
        chat = ChatBoxScript.new()
        chat.submitted.connect(_on_chat_submit)
        chat.closed.connect(func() -> void:
                if not _menu_open:
                        camera_rig.set_mouse_captured(true))
        hud.add_child(chat)

        _build_topbar()
        _build_health()
        _build_hotbar()
        _build_tix_chip()

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

        var menu_btn := _pill_button("res://assets/icons/menu.png", "Menu (ESC)")
        menu_btn.pressed.connect(func() -> void: _toggle_menu())
        row.add_child(menu_btn)

        var chat_btn := _pill_button("res://assets/icons/chat.png", "Chat (ENTER)")
        chat_btn.pressed.connect(func() -> void:
                if chat.is_open:
                        chat.close()
                        chat.set_log_collapsed(not chat.log_collapsed)
                else:
                        chat.set_log_collapsed(false)
                        chat.open()
                        camera_rig.set_mouse_captured(false))
        chat.unread.connect(func(n: int) -> void:
                _chat_badge.text = "" if n <= 0 else str(n))
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
        row.add_child(chat_btn)

        var people_btn := _pill_button("res://assets/icons/people.png", "Players (P)")
        people_btn.pressed.connect(func() -> void:
                _open_menu("players"))
        row.add_child(people_btn)


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


# ---- hotbar (bottom-center: 1 Tix Bag) ----------------------------------

func _build_hotbar() -> void:
        var slot := Button.new()
        slot.name = "HotbarSlot"
        slot.focus_mode = Control.FOCUS_NONE
        slot.tooltip_text = "Tix Bag — your classic wallet"
        slot.add_theme_stylebox_override("normal", _hotbar_style())
        slot.add_theme_stylebox_override("hover", _hotbar_style())
        slot.add_theme_stylebox_override("pressed", _hotbar_style())
        slot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        slot.offset_left = -44.0
        slot.offset_right = 44.0
        slot.offset_top = -96.0
        slot.offset_bottom = -8.0
        slot.pressed.connect(func() -> void: _notify("The Tix Bag jingles. Chat is free forever."))
        hud.add_child(slot)
        var num := Label.new()
        num.text = "1"
        num.add_theme_font_size_override("font_size", 11)
        num.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
        num.position = Vector2(6, 4)
        num.mouse_filter = Control.MOUSE_FILTER_IGNORE
        slot.add_child(num)
        var name_label := Label.new()
        name_label.text = "Tix Bag"
        name_label.add_theme_font_size_override("font_size", 12)
        name_label.add_theme_color_override("font_color", Color.WHITE)
        name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        name_label.offset_top = -30.0
        name_label.offset_bottom = -12.0
        name_label.offset_left = -44.0
        name_label.offset_right = 44.0
        name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        slot.add_child(name_label)


func _hotbar_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.05, 0.07, 0.09, 0.55)
        sb.set_corner_radius_all(4)
        sb.border_color = Color(1, 1, 1, 0.22)
        sb.set_border_width_all(1)
        return sb


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


# ---- tix counter (top-right gold chip) ----------------------------------

func _build_tix_chip() -> void:
        var chip := PanelContainer.new()
        chip.name = "TixChip"
        chip.tooltip_text = "Collect every Tix hidden in the place!"
        chip.add_theme_stylebox_override("panel", _tix_style())
        chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        chip.offset_left = -150.0
        chip.offset_right = -14.0
        chip.offset_top = 12.0
        chip.offset_bottom = 42.0
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 7)
        chip.add_child(row)
        var icon := Label.new()
        icon.text = "Tix"
        icon.add_theme_font_size_override("font_size", 14)
        icon.add_theme_color_override("font_color", Color("5a3c00"))
        row.add_child(icon)
        _tix_label = Label.new()
        _tix_label.text = "0 / 0"
        _tix_label.add_theme_font_size_override("font_size", 14)
        _tix_label.add_theme_color_override("font_color", Color("3d2c00"))
        row.add_child(_tix_label)
        hud.add_child(chip)
        _update_tix()


func _tix_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        # a little gold coin of a chip
        sb.bg_color = Color("ffd23f")
        sb.set_corner_radius_all(14)
        sb.border_color = Color("b98a00")
        sb.set_border_width_all(2)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


# ---------------------------------------------------------------- audio bed

## The music box everywhere, wind on the sky places. Both loop via code-set
## WAV loop points and respect the Music / SFX volume sliders.
func _setup_audio() -> void:
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx == null:
                return
        var music = sfx.call("make_screen_loop", "Music")
        if music != null:
                add_child(music)
                music.call("play")
        if bool(place.get("wind", false)):
                var wind = sfx.call("make_screen_loop", "Wind")
                if wind != null:
                        add_child(wind)
                        wind.call("play")


# ---------------------------------------------------------------- tix coins

## Every "coin" prop registers itself in the tix_coin group — count them,
## wire the chime + counter, and fanfare when the place is swept clean.
func _hook_coins() -> void:
        for coin in get_tree().get_nodes_in_group("tix_coin"):
                _tix_total += 1
                coin.connect("collected", _on_tix_collected)
        _update_tix()


func _on_tix_collected(_coin: Area3D) -> void:
        _tix_got += 1
        _update_tix()
        if _tix_total > 0 and _tix_got >= _tix_total:
                var sfx: Node = get_node_or_null("/root/Sfx")
                if sfx != null:
                        sfx.call("play_goal")
                chat.add_system("*** ALL %d TIX COLLECTED — you legend! ***" % _tix_total)
                _notify("All Tix collected!", true)


func _update_tix() -> void:
        if _tix_label != null and is_instance_valid(_tix_label):
                _tix_label.text = "%d / %d" % [_tix_got, _tix_total]


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
        dim.color = Color(0.02, 0.05, 0.09, 0.6)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.add_child(dim)
        _menu_card = PanelContainer.new()
        _menu_card.add_theme_stylebox_override("panel", _card_style())
        _menu_card.set_anchors_preset(Control.PRESET_CENTER)
        _menu_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _menu_card.grow_vertical = Control.GROW_DIRECTION_BOTH
        overlay.add_child(_menu_card)
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(460, 0)
        box.add_theme_constant_override("separation", 10)
        _menu_card.add_child(box)

        var title := Label.new()
        title.text = "RETROBLOX"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_size_override("font_size", 22)
        title.add_theme_color_override("font_color", Color.WHITE)
        box.add_child(title)
        var sub := Label.new()
        sub.text = String(place.get("name", "a classic place"))
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", Color(0.62, 0.72, 0.8))
        box.add_child(sub)

        # ---- tabs ----
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 6)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        var players_btn := Button.new()
        players_btn.text = "Players"
        players_btn.toggle_mode = true
        players_btn.custom_minimum_size = Vector2(120, 30)
        players_btn.focus_mode = Control.FOCUS_NONE
        var settings_btn := Button.new()
        settings_btn.text = "Settings"
        settings_btn.toggle_mode = true
        settings_btn.custom_minimum_size = Vector2(120, 30)
        settings_btn.focus_mode = Control.FOCUS_NONE
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
        resume.custom_minimum_size = Vector2(0, 40)
        resume.focus_mode = Control.FOCUS_NONE
        resume.add_theme_stylebox_override("normal", _menu_btn_style(Color("2f9e44")))
        resume.add_theme_stylebox_override("hover", _menu_btn_style(Color("37b64f")))
        resume.add_theme_stylebox_override("pressed", _menu_btn_style(Color("278139")))
        resume.add_theme_color_override("font_color", Color.WHITE)
        resume.pressed.connect(_toggle_menu)
        actions.add_child(resume)

        var respawn := Button.new()
        respawn.text = "Reset Character"
        respawn.custom_minimum_size = Vector2(150, 40)
        respawn.focus_mode = Control.FOCUS_NONE
        respawn.add_theme_stylebox_override("normal", _menu_btn_style(Color("3a4b58")))
        respawn.add_theme_stylebox_override("hover", _menu_btn_style(Color("48606f")))
        respawn.add_theme_stylebox_override("pressed", _menu_btn_style(Color("2c3944")))
        respawn.add_theme_color_override("font_color", Color.WHITE)
        respawn.pressed.connect(func() -> void:
                _toggle_menu()
                if player.alive:
                        player.die(self)
                _start_respawn())
        actions.add_child(respawn)

        var leave := Button.new()
        leave.text = "Leave"
        leave.custom_minimum_size = Vector2(110, 40)
        leave.focus_mode = Control.FOCUS_NONE
        leave.add_theme_stylebox_override("normal", _menu_btn_style(Color("b3261e")))
        leave.add_theme_stylebox_override("hover", _menu_btn_style(Color("d13a30")))
        leave.add_theme_stylebox_override("pressed", _menu_btn_style(Color("8f1d17")))
        leave.add_theme_color_override("font_color", Color.WHITE)
        leave.pressed.connect(func() -> void:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
                get_tree().change_scene_to_file("res://scenes/hub.tscn"))
        actions.add_child(leave)

        # LOG OUT — wipes the saved session and returns to the login gate
        var logout := Button.new()
        logout.text = "Log Out"
        logout.custom_minimum_size = Vector2(110, 40)
        logout.focus_mode = Control.FOCUS_NONE
        logout.add_theme_stylebox_override("normal", _menu_btn_style(Color("4a3a55")))
        logout.add_theme_stylebox_override("hover", _menu_btn_style(Color("5c4a6b")))
        logout.add_theme_stylebox_override("pressed", _menu_btn_style(Color("3a2d44")))
        logout.add_theme_color_override("font_color", Color.WHITE)
        logout.pressed.connect(func() -> void:
                Api.clear_session()
                Session.reset()
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
                get_tree().change_scene_to_file("res://scenes/login.tscn"))
        actions.add_child(logout)

        var hint := Label.new()
        hint.text = "Chat with ENTER — everyone online sees it. Esc closes this menu."
        hint.add_theme_font_size_override("font_size", 11)
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hint.add_theme_color_override("font_color", Color(0.55, 0.64, 0.72))
        box.add_child(hint)
        set_tab.call("players")
        return overlay


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
        _slider_row(left, "Music", 0.0, 1.0,
                float(settings.get("music_volume")) if settings != null else 0.7,
                func(v: float) -> void:
                        if settings != null:
                                settings.set_key("music_volume", v))

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
                b.custom_minimum_size = Vector2(64, 26)
                b.focus_mode = Control.FOCUS_NONE
                b.add_theme_stylebox_override("normal", _menu_btn_style(Color("3a4b58")))
                b.add_theme_stylebox_override("hover", _menu_btn_style(Color("48606f")))
                b.add_theme_stylebox_override("pressed", _menu_btn_style(Color("2c3944")))
                b.add_theme_color_override("font_color", Color.WHITE)
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


func _menu_btn_style(bg: Color) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.set_corner_radius_all(8)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
        return sb


func _card_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.075, 0.10, 0.13, 0.97)
        sb.set_corner_radius_all(10)
        sb.border_color = Color(1, 1, 1, 0.08)
        sb.set_border_width_all(1)
        sb.content_margin_left = 18.0
        sb.content_margin_right = 18.0
        sb.content_margin_top = 14.0
        sb.content_margin_bottom = 14.0
        return sb


func _toggle_menu() -> void:
        _menu_open = not _menu_open
        _menu.visible = _menu_open
        if _menu_open:
                camera_rig.set_mouse_captured(false)
                _refresh_player_list([])
        else:
                camera_rig.set_mouse_captured(true)


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
        # bubble over the right avatar
        if uid == Session.user_id:
                player.show_bubble(text)
        elif _remotes.has(uid):
                _remotes[uid].show_bubble(text)


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
