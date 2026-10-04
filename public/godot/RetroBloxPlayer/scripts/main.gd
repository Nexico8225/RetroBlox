extends Node3D

## RetroBlox Player — the WEBSITE-SYNCED multiplayer world.
##
## Everything runs through https://retro-blox.vercel.app:
##   LOGIN      — accounts made on the website (or the Sign Up tab). There is
##                no guest mode: your account IS your player.
##   GAME SYNC  — after login the player downloads the place list and the map
##                of the game from the site (one game: Baseplate). Change the
##                game on the web and every player plays the new version.
##   MULTIPLAYER— every ~0.15s the player posts its position/yaw/animation to
##                POST /api/game/state and receives every other player plus
##                the new chat lines. Remote characters are smoothed, so the
##                ticking stays invisible.
##   CHAT       — press "/" or ENTER (classic), talk, everyone in the place
##                sees it in the chat log AND as a bubble over your head.
##
## Shift Lock included (SHIFT or the menu button): the camera locks to your
## right shoulder and the character squares up to the camera, classic style.
## Ladders: push forward to climb, back to slide down, SPACE to jump OFF.
##
## CREATORS — the world is still built from nodes and scenes: the web map
## spawns the very same RetroPart / SpawnLocation / RetroLadder scenes you
## place by hand in scenes/maps/ (see README). No website? The bundled
## Baseplate scene loads and you play solo.

const Player = preload("res://scripts/player.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const HudScene = preload("res://scenes/hud.tscn")
const AuthScreenScene = preload("res://scenes/auth_screen.tscn")
# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript = preload("res://scripts/retroblox_api.gd")

const RESPAWN_SECONDS: float = 2.8
const TICK_SECONDS: float = 0.15        # the multiplayer heartbeat (~6.7/s)
const TICK_RETRY: float = 1.2           # slower heartbeat while the site is unreachable
const REMOTE_TIMEOUT: float = 12.0      # silent this long = left the game
const WALK_ANIM_SPEED: float = 16.0     # what a remote "walk" state animates at

# the world lives in main.tscn — Arena, Players, Debris and the CameraRig
@onready var arena: Node3D = $Arena
@onready var player_root: Node3D = $Players
@onready var debris_root: Node3D = $Debris
@onready var camera_pivot: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D

var camera_yaw: float = 0.0
var camera_pitch: float = -0.26
var camera_distance: float = 14.5   # studs — classic default zoom for a 5-stud character
var camera_initialized: bool = false
var quitting: bool = false

# --- the place being played ---
var place_slug: String = ""
var place_name: String = "Baseplate"

# --- players: account id (String) -> Player node; LOCAL included ---
var players: Dictionary = {}
var player_last_seen: Dictionary = {}   # uid -> msec when last present
var my_user_id: String = ""
var _display_name: String = "Player"

# --- the multiplayer heartbeat ---
var tick_time: float = 0.0
var ticking: bool = false               # a state request is in flight
var ticks_failed: int = 0               # consecutive failures (drives the status line)
var chat_cursor: String = ""            # serverTime of the last tick (chat "since")
var pending_chat: String = ""           # one queued message, sent on the next tick
var my_last_chat_ms: float = -100.0

var jump_serial: int = 0
var hud: CanvasLayer
var auth: CanvasLayer

# --- platform account ---
# The production RetroBlox site — sign-in, avatars, catalog, game sync. Override
# with the Server field on the login card, RETROBLOX_API, or --api= for self-hosts.
var api_url: String = "https://retro-blox.vercel.app"
var api_ref: RetrobloxApiScript
var profile: ConfigFile

# --- settings ---
var shiftlock: bool = false
var mouse_sensitivity: float = 1.0
var volume_setting: float = 1.0
var shoulder_blend: float = 0.0
var _auth_done: bool = false


func _ready() -> void:
        _read_configuration()
        _setup_input()
        _apply_volume()
        hud = HudScene.instantiate() as CanvasLayer
        add_child(hud)
        hud.chat_submitted.connect(send_chat)
        hud.resume_requested.connect(func(): hud.set_menu(false))
        hud.reset_requested.connect(request_reset)
        hud.quit_requested.connect(quit_game)
        hud.shiftlock_toggled.connect(_set_shiftlock)
        hud.sensitivity_changed.connect(_on_sensitivity_changed)
        hud.volume_changed.connect(_on_volume_changed)
        hud.room_label.text = "RetroBlox  /  loading games…"
        hud.set_room_title(place_name)
        hud.set_sliders(mouse_sensitivity, volume_setting)
        hud.set_shiftlock(shiftlock)
        hud.add_chat("", "Welcome to RetroBlox!", true)
        # the door: log in or sign up — the website account IS the player
        auth = AuthScreenScene.instantiate() as CanvasLayer
        add_child(auth)
        auth.completed.connect(_on_auth_completed)
        auth.set_api_url(api_url)
        auth.set_saved_username(str(profile.get_value("platform", "username", "")))
        _try_saved_token()

func _read_configuration() -> void:
        var config := ConfigFile.new()
        config.load("res://network.cfg")
        # An adjacent config overrides the embedded one after export.
        if not OS.has_feature("editor"):
                var override_path := OS.get_executable_path().get_base_dir().path_join("network.cfg")
                if FileAccess.file_exists(override_path):
                        config.load(override_path)
        api_url = str(config.get_value("platform", "api_url", "https://retro-blox.vercel.app")).strip_edges().trim_suffix("/")

        profile = ConfigFile.new()
        if profile.load("user://profile.cfg") != OK:
                profile.save("user://profile.cfg")
        shiftlock = bool(profile.get_value("player", "shiftlock", false))
        mouse_sensitivity = clampf(float(profile.get_value("settings", "sensitivity", 1.0)), 0.4, 2.0)
        volume_setting = clampf(float(profile.get_value("settings", "volume", 1.0)), 0.0, 1.0)

        if not OS.get_environment("RETROBLOX_API").is_empty():
                api_url = OS.get_environment("RETROBLOX_API").strip_edges().trim_suffix("/")
        for arg in OS.get_cmdline_user_args():
                if arg.begins_with("--api="):
                        api_url = arg.trim_prefix("--api=").trim_suffix("/")

func _setup_input() -> void:
        _bind_key("move_forward", KEY_W)
        _bind_key("move_forward", KEY_UP)
        _bind_key("move_back", KEY_S)
        _bind_key("move_back", KEY_DOWN)
        _bind_key("move_left", KEY_A)
        _bind_key("move_left", KEY_LEFT)
        _bind_key("move_right", KEY_D)
        _bind_key("move_right", KEY_RIGHT)
        _bind_key("jump", KEY_SPACE)

func _bind_key(action: String, key: Key) -> void:
        if not InputMap.has_action(action):
                InputMap.add_action(action)
        var event := InputEventKey.new()
        event.physical_keycode = key
        InputMap.action_add_event(action, event)

# ---------------------------------------------------------------- auth flow

func _try_saved_token() -> void:
        var saved_token := str(profile.get_value("platform", "token", ""))
        if saved_token.is_empty() or auth == null:
                return
        auth.set_status_text("Signing you in…")
        var probe := RetrobloxApiScript.new(api_url)
        probe.token = saved_token
        var me: Dictionary = await probe.get_me()
        if quitting or auth == null:
                return
        if me.get("ok", false) and not str(me.get("username", "")).is_empty():
                var av = me.get("avatar", {})
                auth.visible = false
                _finish_auth(probe, String(me.get("username", "")), String(me.get("userId", "")), av if av is Dictionary else {})
        else:
                # token expired or the site moved on — back to the form
                auth.set_status_text("")

func _on_auth_completed(api: RetrobloxApiScript, username: String, user_id: String, avatar: Dictionary) -> void:
        _finish_auth(api, username, user_id, avatar)

func _finish_auth(api: RetrobloxApiScript, username: String, user_id: String, avatar: Dictionary) -> void:
        if _auth_done:
                return
        _auth_done = true
        api_ref = api
        my_user_id = user_id
        _display_name = _clean_name(username, 1)
        profile.set_value("platform", "token", api.token)
        profile.set_value("platform", "username", username)
        profile.save("user://profile.cfg")
        if hud != null:
                hud.add_chat("", "Signed in as %s — loading the game from RetroBlox…" % username, true)
        _join_place(avatar)

func _clean_name(value: String, id: int) -> String:
        var result := ""
        for c in value.left(80):
                var n := c.unicode_at(0)
                if (n >= 48 and n <= 57) or (n >= 65 and n <= 90) or (n >= 97 and n <= 122) or c in [" ", "-", "_"]:
                        result += c
                if result.length() >= 18:
                        break
        result = result.strip_edges()
        return result if not result.is_empty() else "Player-%04d" % (id % 10000)

# ---------------------------------------------------------------- game sync

## LOGIN DONE → download the game from the website and join it.
func _join_place(avatar_payload: Dictionary) -> void:
        if hud != null:
                hud.set_status("Loading games from RetroBlox…", false)
        var places_res: Dictionary = {}
        if api_ref != null:
                places_res = await api_ref.get_places()
        if quitting:
                return

        var slug := ""
        var display := ""
        if places_res.get("ok", false):
                var places: Array = places_res.get("places", [])
                for entry in places:
                        var place: Dictionary = entry
                        if place.get("active", false) == false:
                                continue
                        slug = String(place.get("slug", ""))
                        display = String(place.get("name", ""))
                        break
        if slug.is_empty():
                # the website could not answer — play the bundled Baseplate solo;
                # the heartbeat keeps retrying so others still see you once it heals
                _system_notice("Could not load the games from RetroBlox — playing the local Baseplate copy.")
                _spawn_local(avatar_payload)
                return

        place_slug = slug
        if not display.is_empty():
                place_name = display
        var place_res: Dictionary = await api_ref.get_place(place_slug)
        if quitting:
                return
        if place_res.get("ok", false) and place_res.get("data", {}) is Dictionary:
                var err: String = arena.apply_map_data(place_res.get("data"))
                if err.is_empty():
                        place_name = String(place_res.get("name", place_name))
                else:
                        _system_notice("The web map could not be built (%s) — playing the local Baseplate copy." % err)
        else:
                _system_notice("Could not download the map — playing the local Baseplate copy.")

        if hud != null:
                hud.room_label.text = place_name + "  /  synced from retroblox web"
                hud.set_room_title(place_name)
        _spawn_local(avatar_payload)

func _spawn_local(avatar_payload: Dictionary) -> void:
        if hud != null and place_slug.is_empty():
                hud.room_label.text = place_name + "  /  offline copy"
        var p := _spawn_player(my_user_id, _display_name, arena.spawn_point(players.size()), avatar_payload)
        p.is_remote = false
        if hud != null:
                p.health_changed.connect(hud.set_health)
                p.health_depleted.connect(_on_local_health_depleted)
                hud.set_health(p.health, p.MAX_HEALTH)
                hud.set_status("●  " + place_name, true)
        tick_time = TICK_SECONDS  # first heartbeat fires immediately
        _update_roster()

# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
        if hud == null:
                return
        if auth != null and auth.visible:
                return  # the login card owns the keyboard until you are in
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        if hud.chat_entry.has_focus():
                                hud.chat_entry.release_focus()
                        elif hud.chat_open:
                                hud.toggle_chat(false)
                        else:
                                hud.set_menu(not hud.menu.visible)
                        get_viewport().set_input_as_handled()
                        return
                if event.keycode == KEY_ENTER and not hud.input_busy():
                        hud.begin_chat()
                        get_viewport().set_input_as_handled()
                        return
                if event.keycode == KEY_SLASH and not hud.input_busy():
                        # the classic: "/" pops the chat already in typing mode
                        # (handled BEFORE the GUI sees it, so the "/" itself is
                        # never typed into the box)
                        hud.begin_chat()
                        get_viewport().set_input_as_handled()
                        return
                if event.keycode == KEY_SHIFT and not hud.input_busy():
                        _set_shiftlock(not shiftlock)
                        get_viewport().set_input_as_handled()
        if hud.input_busy():
                return
        if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
                camera_yaw -= event.relative.x * 0.003 * mouse_sensitivity
                camera_pitch = clampf(camera_pitch - event.relative.y * 0.003 * mouse_sensitivity, -1.2, 0.8)
        if event is InputEventMouseButton and event.pressed:
                if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                        camera_distance = clampf(camera_distance - 1.4, 0.5, 30.0)
                elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        camera_distance = clampf(camera_distance + 1.4, 0.5, 30.0)

func _set_shiftlock(enabled: bool) -> void:
        shiftlock = enabled
        if hud != null:
                hud.set_shiftlock(enabled)
        profile.set_value("player", "shiftlock", enabled)
        profile.save("user://profile.cfg")

func _on_sensitivity_changed(value: float) -> void:
        mouse_sensitivity = value
        profile.set_value("settings", "sensitivity", value)
        profile.save("user://profile.cfg")

func _on_volume_changed(value: float) -> void:
        volume_setting = value
        _apply_volume()
        profile.set_value("settings", "volume", value)
        profile.save("user://profile.cfg")

func _apply_volume() -> void:
        if volume_setting <= 0.001:
                AudioServer.set_bus_mute(0, true)
        else:
                AudioServer.set_bus_mute(0, false)
                AudioServer.set_bus_volume_db(0, linear_to_db(volume_setting))

func _process(delta: float) -> void:
        if quitting:
                return
        # stay on the login card until you are through it
        if auth != null and auth.visible:
                return
        _pump_tick(delta)
        for uid in players:
                var p = players[uid]
                if uid != my_user_id:
                        p.render_remote(delta)
                p.update_visuals(delta)
        _fade_lost_players()
        var local = players.get(my_user_id)
        var busy: bool = hud.input_busy()
        var capture: bool = not busy and (shiftlock or camera_distance < 1.0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
        var wanted_mode: int = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
        if Input.mouse_mode != wanted_mode:
                Input.mouse_mode = wanted_mode
        hud.crosshair.visible = not busy and (shiftlock or camera_distance < 1.0)
        if local != null:
                var shoulder_target: float = 0.9 if shiftlock else 0.0
                shoulder_blend = lerpf(shoulder_blend, shoulder_target, 1.0 - exp(-10.0 * delta))
                # shift lock rests the camera on your right shoulder, classic style
                var right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
                var target: Vector3 = local.global_position + Vector3(0, 4.3, 0) + right * shoulder_blend
                if not camera_initialized:
                        camera_pivot.global_position = target
                        camera_initialized = true
                else:
                        camera_pivot.global_position = camera_pivot.global_position.lerp(target, 1.0 - exp(-18.0 * delta))
                local.avatar.visible = local.alive and camera_distance >= 1.0
                if not local.alive:
                        # the classic rebuild wait, then back on a spawn pad
                        local.respawn_left = maxf(local.respawn_left - delta, 0.0)
                        if local.respawn_left <= 0.0:
                                _respawn_local()
                hud.toast.text = "Rebuilding you… %.1f" % local.respawn_left if not local.alive else ""
                hud.reset_button.disabled = not local.alive
        else:
                hud.reset_button.disabled = true
                hud.toast.text = ""
        camera_pivot.rotation.y = camera_yaw
        spring_arm.rotation.x = camera_pitch
        spring_arm.spring_length = lerpf(spring_arm.spring_length, camera_distance, 1.0 - exp(-15.0 * delta))

func _physics_process(delta: float) -> void:
        if quitting or auth != null and auth.visible:
                return
        var local = players.get(my_user_id)
        if local != null and local.alive:
                var direction := Vector2.ZERO
                if not hud.input_busy():
                        direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
                        if Input.is_action_just_pressed("jump"):
                                jump_serial += 1
                local.drive(delta, direction, camera_yaw, jump_serial, shiftlock)
                local.reconcile(delta)
                # classic void death
                if local.global_position.y < -18.0:
                        local.hurt(9999.0)

## THE HEARTBEAT — send me, receive everyone + the chat.
func _pump_tick(delta: float) -> void:
        if players.get(my_user_id) == null:
                return
        tick_time += delta
        var interval: float = TICK_RETRY if ticks_failed > 0 else TICK_SECONDS
        if tick_time < interval or ticking:
                return
        tick_time = 0.0
        ticking = true
        var local = players[my_user_id]
        var payload: Dictionary = {
                "placeSlug": place_slug if not place_slug.is_empty() else "baseplate",
                "x": local.global_position.x,
                "y": local.global_position.y,
                "z": local.global_position.z,
                "yaw": local.heading,
                "state": _state_of(local),
                "shiftlock": shiftlock,
        }
        if not chat_cursor.is_empty():
                payload["since"] = chat_cursor
        if not pending_chat.is_empty():
                payload["chat"] = pending_chat
        var res: Dictionary = await api_ref.post_state(payload)
        ticking = false
        if quitting:
                return
        if not res.get("ok", false):
                ticks_failed = mini(ticks_failed + 1, 6)
                if hud != null:
                        hud.set_status("Reaching RetroBlox…", false)
                return
        if ticks_failed > 0:
                ticks_failed = 0
                if hud != null:
                        hud.set_status("●  " + place_name, true)
        pending_chat = ""
        chat_cursor = String(res.get("serverTime", chat_cursor))
        _apply_players(res.get("players", []))
        _apply_chat(res.get("chat", []))

## anim state word the website understands
func _state_of(local: Player) -> String:
        if local.climbing:
                return "climb"
        if not local.grounded:
                return "jump" if local.velocity.y > 2.0 else "fall"
        if Vector2(local.velocity.x, local.velocity.z).length() > 1.2:
                return "walk"
        return "idle"

# ---------------------------------------------------------------- players

func _apply_players(rows: Array) -> void:
        var now := Time.get_ticks_msec()
        for row in rows:
                if not (row is Dictionary):
                        continue
                var entry: Dictionary = row
                var uid := String(entry.get("userId", ""))
                if uid.is_empty() or uid == my_user_id:
                        continue
                player_last_seen[uid] = now
                if players.has(uid):
                        var p: Player = players[uid]
                        var walking := String(entry.get("state", "idle")) == "walk"
                        var vel := Vector3(WALK_ANIM_SPEED, 0.0, 0.0) if walking else Vector3.ZERO
                        var on_floor := String(entry.get("state", "idle")) in ["idle", "walk", "climb"]
                        p.accept_snapshot(
                                Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 10.0)), float(entry.get("z", 0.0))),
                                vel,
                                float(entry.get("yaw", 0.0)),
                                on_floor,
                                false,
                                String(entry.get("state", "idle")) == "climb"
                        )
                else:
                        var uname := _clean_name(String(entry.get("username", "Player")), hash(uid) % 10000)
                        _spawn_remote(uid, uname, Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 10.0)), float(entry.get("z", 0.0))))
        _update_roster()

## Players the server stopped seeing for REMOTE_TIMEOUT seconds went home.
func _fade_lost_players() -> void:
        var now := Time.get_ticks_msec()
        var gone: Array[String] = []
        for uid in players:
                if uid == my_user_id:
                        continue
                var seen: int = int(player_last_seen.get(uid, 0))
                if seen > 0 and now - seen > int(REMOTE_TIMEOUT * 1000.0):
                        gone.append(uid)
        for uid in gone:
                var uname := "Someone"
                if players.has(uid):
                        uname = players[uid].display_name
                        players[uid].queue_free()
                        players.erase(uid)
                player_last_seen.erase(uid)
                _system_notice(uname + " left the game.")
                _update_roster()

func _spawn_player(uid: String, uname: String, pos: Vector3, avatar_payload: Dictionary) -> Player:
        var p = PlayerScene.instantiate() as Player
        # add to the tree first so the scene's nodes exist, then initialize
        player_root.add_child(p)
        p.initialize(hash(uid) & 0x7fffffff, uname)
        p.platform_user_id = uid
        p.respawn_at(pos, 0)
        players[uid] = p
        _dress_player(p, avatar_payload)
        return p

func _spawn_remote(uid: String, uname: String, pos: Vector3) -> void:
        var p := _spawn_player(uid, uname, pos, {})
        p.is_remote = true
        p.snap_remote(pos)
        _system_notice(uname + " joined the game.")

func _update_roster() -> void:
        if hud == null:
                return
        var entries: Array = []
        for uid in players:
                entries.append({"id": uid, "name": players[uid].display_name})
        hud.update_roster(entries, my_user_id)

## Fetch the RetroBlox account avatar for a player and paint it on.
## `preloaded` skips the round-trip for the local player (from /platform/me).
func _dress_player(p, preloaded: Dictionary = {}) -> void:
        if p == null or not is_instance_valid(p) or p.platform_user_id.is_empty():
                return
        if api_ref == null:
                return
        var payload := preloaded
        if payload.is_empty():
                payload = await api_ref.get_avatar(p.platform_user_id)
                if not is_instance_valid(p) or quitting:
                        return
        if not payload.get("ok", true) or not is_instance_valid(p):
                return
        var avatar_data: Dictionary = payload.get("avatar", {}) if payload.get("avatar", {}) is Dictionary else {}
        if avatar_data.is_empty():
                return
        await p.dress_from_payload(api_ref, avatar_data)

# ---------------------------------------------------------------- chat

func send_chat(message: String) -> void:
        var now_ms := Time.get_ticks_msec() / 1000.0
        var clean := _sanitize_chat(message)
        if clean.is_empty() or players.get(my_user_id) == null:
                return
        if now_ms - my_last_chat_ms < 0.8:
                return
        my_last_chat_ms = now_ms
        pending_chat = clean
        # optimistic display — the server echo for myself is skipped
        hud.add_chat(_display_name, clean)
        players[my_user_id].show_message(clean)

func _apply_chat(rows: Array) -> void:
        for row in rows:
                if not (row is Dictionary):
                        continue
                var entry: Dictionary = row
                var uid := String(entry.get("userId", ""))
                var uname := String(entry.get("username", "Player"))
                var text := String(entry.get("text", ""))
                if uid == my_user_id or text.is_empty():
                        continue
                hud.add_chat(_clean_name(uname, 0), text)
                if players.has(uid):
                        players[uid].show_message(text)

func _sanitize_chat(message: String) -> String:
        var clean := ""
        for c in message.left(512):
                var code := c.unicode_at(0)
                # Strip control/bidi characters. Display only plain text, never BBCode.
                if code >= 32 and code != 127 and not (code >= 0x200B and code <= 0x200F) and not (code >= 0x202A and code <= 0x202E) and not (code >= 0x2060 and code <= 0x206F):
                        clean += c
                if clean.length() >= 180:
                        break
        return clean.strip_edges()

func _system_notice(message: String) -> void:
        if hud != null:
                hud.add_chat("", message, true)

# ---------------------------------------------------------------- life & death

## Local health hit zero (a big fall or the menu's Reset button) — the same
## classic flow: break apart, wait, rebuild on a spawn pad.
func _on_local_health_depleted() -> void:
        var local = players.get(my_user_id)
        if local == null or not local.alive:
                return
        local.die(debris_root, local.life_epoch + 1, randi_range(1, 1000000))
        local.respawn_left = RESPAWN_SECONDS

func request_reset() -> void:
        if hud != null:
                hud.set_menu(false)
        var local = players.get(my_user_id)
        if local != null and local.alive:
                local.hurt(9999.0)

func _respawn_local() -> void:
        var local = players.get(my_user_id)
        if local == null or local.alive:
                return
        local.respawn_at(arena.spawn_point(players.size() + local.life_epoch), local.life_epoch + 1)
        jump_serial = 0
        camera_initialized = false

func quit_game() -> void:
        if quitting:
                return
        quitting = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        # tell the website we left (best effort — never blocks the exit)
        if api_ref != null:
                api_ref.post_state_nowait({ "placeSlug": place_slug if not place_slug.is_empty() else "baseplate", "leave": true })
        get_tree().quit()

func _notification(what: int) -> void:
        if what == NOTIFICATION_WM_CLOSE_REQUEST:
                quit_game()
        elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
                # alt-tabbing must NOT pause or open the menu — the game keeps
                # running, multiplayer included. Only release held movement keys
                # so the character does not keep walking while you are away.
                for action in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
                        Input.action_release(action)
