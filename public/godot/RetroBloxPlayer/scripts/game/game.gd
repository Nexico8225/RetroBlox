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

var _health_bar: ProgressBar
var _health_text: Label
var _player_list: PanelContainer
var _player_list_box: VBoxContainer
var _menu: Control
var _remotes: Dictionary = {}      # userId -> RemotePlayer
var _seen_messages: Dictionary = {} # message id -> true
var _spawn_index := 0
var _spawns: Array[Vector3] = []
var _respawning := false
var _finished := false
var _poll_left := 0.6
var _beat_left := 1.2
var _menu_open := false


func _ready() -> void:
        place = Session.current_place
        if place.is_empty():
                place = PlacesScript.by_id("baseplate")

        var built: Dictionary = WorldBuilderScript.build(place)
        add_child(built["root"])
        _spawns = built["spawns"]
        if _spawns.is_empty():
                _spawns.append(Vector3(0.0, 6.0, 0.0))

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

        # ---- camera ----
        camera_rig = CameraRigScript.new()
        add_child(camera_rig)
        camera_rig.setup(player)
        camera_rig.set_mouse_captured(true)

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

        # fall into the void -> die (the oof knows)
        if player.alive and player.global_position.y < float(place.get("void_y", -40.0)):
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
                _player_list.visible = not _player_list.visible
                get_viewport().set_input_as_handled()
        elif event is InputEventMouseButton and event.is_pressed():
                # click the world to recapture the mouse after menus / chat
                if not _menu_open and not chat.is_open and not camera_rig.is_mouse_captured():
                        camera_rig.set_mouse_captured(true)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
        hud = CanvasLayer.new()
        hud.name = "HUD"
        add_child(hud)

        # ---- top-left: place name + health ----
        var top := PanelContainer.new()
        top.add_theme_stylebox_override("panel", _dark_panel())
        top.position = Vector2(12, 12)
        hud.add_child(top)
        var top_box := VBoxContainer.new()
        top_box.custom_minimum_size = Vector2(230, 0)
        top.add_child(top_box)
        var place_label := Label.new()
        place_label.text = String(place.get("name", "RetroBlox"))
        place_label.add_theme_font_size_override("font_size", 16)
        place_label.add_theme_color_override("font_color", RetroUI.TEXT_INV)
        top_box.add_child(place_label)
        _health_bar = ProgressBar.new()
        _health_bar.custom_minimum_size = Vector2(0, 20)
        _health_bar.max_value = 100.0
        _health_bar.value = 100.0
        _health_bar.show_percentage = false
        top_box.add_child(_health_bar)
        _health_text = Label.new()
        _health_text.text = "100 / 100"
        _health_text.add_theme_font_size_override("font_size", 11)
        _health_text.add_theme_color_override("font_color", RetroUI.TEXT_INV)
        top_box.add_child(_health_text)

        # ---- bottom-left: chat ----
        chat = ChatBoxScript.new()
        chat.submitted.connect(_on_chat_submit)
        chat.closed.connect(func() -> void:
                if not _menu_open:
                        camera_rig.set_mouse_captured(true))
        hud.add_child(chat)

        # ---- bottom-right: hints ----
        var hints := PanelContainer.new()
        hints.add_theme_stylebox_override("panel", _dark_panel())
        hints.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        hints.offset_left = -342.0
        hints.offset_right = -12.0
        hints.offset_bottom = -12.0
        hud.add_child(hints)
        var hints_label := Label.new()
        hints_label.text = "WASD move · SPACE jump · SHIFT lock · ENTER chat · P players · ESC menu"
        hints_label.add_theme_font_size_override("font_size", 11)
        hints_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.93))
        hints.add_child(hints_label)

        # ---- right: player list (P) ----
        _player_list = PanelContainer.new()
        _player_list.add_theme_stylebox_override("panel", _dark_panel())
        _player_list.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        _player_list.offset_left = -240.0
        _player_list.offset_right = -12.0
        _player_list.offset_top = -160.0
        _player_list.offset_bottom = 160.0
        _player_list.visible = false
        hud.add_child(_player_list)
        _player_list_box = VBoxContainer.new()
        _player_list.add_child(_player_list_box)
        var pl_title := Label.new()
        pl_title.text = "PLAYERS"
        pl_title.add_theme_font_size_override("font_size", 13)
        pl_title.add_theme_color_override("font_color", RetroUI.GOLD)
        _player_list_box.add_child(pl_title)
        _refresh_player_list([])

        # ---- center: esc menu ----
        _menu = _build_menu()
        hud.add_child(_menu)


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
        var card := PanelContainer.new()
        card.set_anchors_preset(Control.PRESET_CENTER)
        card.grow_horizontal = Control.GROW_DIRECTION_BOTH
        card.grow_vertical = Control.GROW_DIRECTION_BOTH
        overlay.add_child(card)
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(280, 0)
        box.add_theme_constant_override("separation", 8)
        card.add_child(box)
        var title := Label.new()
        title.text = "GAME MENU"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_size_override("font_size", 18)
        box.add_child(title)

        var resume := Button.new()
        resume.text = "Resume"
        resume.pressed.connect(_toggle_menu)
        box.add_child(resume)

        var respawn := Button.new()
        respawn.text = "Respawn (reset character)"
        respawn.pressed.connect(func() -> void:
                _toggle_menu()
                if player.alive:
                        player.die(self)
                _start_respawn())
        box.add_child(respawn)

        var leave := Button.new()
        leave.text = "Leave Place"
        leave.theme_type_variation = "BtnRed"
        leave.pressed.connect(func() -> void:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
                get_tree().change_scene_to_file("res://scenes/hub.tscn"))
        box.add_child(leave)

        var hint := Label.new()
        hint.text = "Chat with ENTER — everyone online sees it."
        hint.add_theme_font_size_override("font_size", 11)
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(hint)
        return overlay


func _toggle_menu() -> void:
        _menu_open = not _menu_open
        _menu.visible = _menu_open
        if _menu_open:
                camera_rig.set_mouse_captured(false)
        else:
                camera_rig.set_mouse_captured(true)


# ---------------------------------------------------------------- events

func _on_health_changed(hp: float, max_hp: float) -> void:
        _health_bar.max_value = max_hp
        _health_bar.value = hp
        _health_text.text = "%d / %d" % [int(hp), int(max_hp)]


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
        if Session.is_guest:
                chat.add_system("Guests watch chat — sign up on retro-blox.vercel.app to talk!")
                return
        var res: Dictionary = await Api.place_chat_send(String(place["id"]), text)
        if res.get("ok", false) and res.get("message", null) is Dictionary:
                var msg: Dictionary = res["message"]
                _ingest_message(msg)
        else:
                chat.add_system(String(res.get("error", "Could not send the message.")))


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
                        chat.add_system("%s is here" % String(p.get("username", "Someone")))
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
        for child in _player_list_box.get_children():
                if child is Label and child.text != "PLAYERS":
                        child.queue_free()
        var names: Array[String] = [Session.display_tag()]
        for p in players:
                var uname := String(p.get("username", ""))
                if uname != "" and String(p.get("userId", "")) != Session.user_id:
                        var seq: Variant = p.get("seqId")
                        if seq is int and int(seq) > 0:
                                names.append("%s #%d" % [uname, int(seq)])
                        else:
                                names.append(uname)
        for n in names:
                var l := Label.new()
                l.text = n
                l.add_theme_font_size_override("font_size", 12)
                l.add_theme_color_override("font_color", RetroUI.TEXT_INV)
                _player_list_box.add_child(l)
