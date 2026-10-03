extends Node3D

## RetroBlox Player — classic multiplayer world on a platform account.
## Sign in (or sign up) INSIDE the game, your account avatar loads from the
## RetroBlox website, and everyone in the room sees it. Shift Lock included.
const Player = preload("res://scripts/player.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const HudScene = preload("res://scenes/hud.tscn")
const AuthScreenScene = preload("res://scenes/auth_screen.tscn")
# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript = preload("res://scripts/retroblox_api.gd")
const VERSION: String = "RETROBLOX_1"
const DISCOVER: String = "RETROBLOX_1_DISCOVER"
const RESPAWN_SECONDS: float = 2.8

var players: Dictionary = {}
var pending_peers: Dictionary = {}
var peer: ENetMultiplayerPeer
var server_mode: bool = false
var dedicated: bool = false
var force_host: bool = false
var local_id: int = 0
var server_address: String = ""
var port: int = 42420
var discovery_port: int = 42421
var max_players: int = 32
var player_name: String = ""
var room_name: String = "RetroBlox Baseplate"
var phase: String = "starting"
var phase_time: float = 0.0
var discover_delay: float = 1.8
var probe_time: float = 0.0
var discovery: PacketPeerUDP
var discovery_listener: PacketPeerUDP
var snapshot_time: float = 0.0
var send_time: float = 0.0
var jump_serial: int = 0
var sequence: int = 0
var hud: CanvasLayer
var auth: CanvasLayer

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
var debug_stats: Dictionary = {"max_players_seen": 0, "chats_received": 0, "deaths_seen": 0, "respawns_seen": 0, "snapshots_received": 0}

# --- platform account ---
# The production RetroBlox site — sign-in, avatars, catalog. Override with
# the Server field on the login card, RETROBLOX_API, or --api= for self-hosts.
var api_url: String = "https://retro-blox.vercel.app"
var api_ref: RetrobloxApiScript
var platform_user_id: String = ""
var my_avatar: Dictionary = {}
var _avatar_cache: Dictionary = {}
var profile: ConfigFile

# --- settings ---
var shiftlock: bool = false
var mouse_sensitivity: float = 1.0
var volume_setting: float = 1.0
var shoulder_blend: float = 0.0
var _auth_done: bool = false

func _ready() -> void:
        randomize()
        # All game messages go through the server. Peer-to-peer relay/announcements
        # are unnecessary and can race when multiple clients disconnect together.
        multiplayer.server_relay = false
        _read_configuration()
        _setup_input()
        _apply_volume()
        if not dedicated:
                hud = HudScene.instantiate() as CanvasLayer
                add_child(hud)
                hud.chat_submitted.connect(send_chat)
                hud.resume_requested.connect(func(): hud.set_menu(false))
                hud.reset_requested.connect(request_reset)
                hud.quit_requested.connect(quit_game)
                hud.shiftlock_toggled.connect(_set_shiftlock)
                hud.sensitivity_changed.connect(_on_sensitivity_changed)
                hud.volume_changed.connect(_on_volume_changed)
                hud.room_label.text = room_name + "  /  Classic worlds, your way."
                hud.set_room_title(room_name)
                hud.set_sliders(mouse_sensitivity, volume_setting)
                hud.set_shiftlock(shiftlock)
                hud.add_chat("", "Welcome! Only connected players appear here.", true)
                # the door: sign in, sign up, or play as a guest
                auth = AuthScreenScene.instantiate() as CanvasLayer
                add_child(auth)
                auth.completed.connect(_on_auth_completed)
                auth.guest_requested.connect(_on_guest_requested)
                auth.set_api_url(api_url)
                auth.set_saved_username(str(profile.get_value("platform", "username", "")))
                _try_saved_token()
        multiplayer.peer_connected.connect(_peer_connected)
        multiplayer.peer_disconnected.connect(_peer_disconnected)
        multiplayer.connected_to_server.connect(_connected_to_server)
        multiplayer.connection_failed.connect(_connection_failed)
        multiplayer.server_disconnected.connect(_server_disconnected)
        if dedicated:
                _start_server()

func _read_configuration() -> void:
        var config := ConfigFile.new()
        config.load("res://network.cfg")
        # An adjacent config overrides the embedded one after export.
        if not OS.has_feature("editor"):
                var override_path := OS.get_executable_path().get_base_dir().path_join("network.cfg")
                if FileAccess.file_exists(override_path):
                        config.load(override_path)
        server_address = str(config.get_value("network", "server", "")).strip_edges()
        port = clampi(int(config.get_value("network", "port", 42420)), 1024, 65535)
        discovery_port = clampi(int(config.get_value("network", "discovery_port", 42421)), 1024, 65535)
        max_players = clampi(int(config.get_value("network", "max_players", 32)), 2, 64)
        room_name = str(config.get_value("game", "room_name", "RetroBlox Baseplate")).left(32)
        api_url = str(config.get_value("platform", "api_url", "https://retro-blox.vercel.app")).strip_edges().trim_suffix("/")

        profile = ConfigFile.new()
        if profile.load("user://profile.cfg") != OK:
                profile.set_value("player", "name", "Guest-%04d" % randi_range(1000, 9999))
                profile.save("user://profile.cfg")
        player_name = str(profile.get_value("player", "name", "Guest"))
        shiftlock = bool(profile.get_value("player", "shiftlock", false))
        mouse_sensitivity = clampf(float(profile.get_value("settings", "sensitivity", 1.0)), 0.4, 2.0)
        volume_setting = clampf(float(profile.get_value("settings", "volume", 1.0)), 0.0, 1.0)

        if not OS.get_environment("RETROBLOX_API").is_empty():
                api_url = OS.get_environment("RETROBLOX_API").strip_edges().trim_suffix("/")
        if not OS.get_environment("BLOCKYARD_SERVER").is_empty():
                server_address = OS.get_environment("BLOCKYARD_SERVER")
        for arg in OS.get_cmdline_user_args():
                if arg == "--server":
                        dedicated = true
                elif arg == "--host":
                        force_host = true
                elif arg.begins_with("--connect="):
                        server_address = arg.trim_prefix("--connect=")
                elif arg.begins_with("--port="):
                        port = clampi(arg.trim_prefix("--port=").to_int(), 1024, 65535)
                elif arg.begins_with("--name="):
                        player_name = arg.trim_prefix("--name=")
                elif arg.begins_with("--api="):
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

func _on_guest_requested() -> void:
        if _auth_done:
                return
        _auth_done = true
        api_ref = RetrobloxApiScript.new(api_url)  # token-less: still fetches PUBLIC avatars
        platform_user_id = ""
        my_avatar = {}
        player_name = "Guest-%04d" % randi_range(1000, 9999)
        if auth != null:
                auth.visible = false
        _begin_online()

func _finish_auth(api: RetrobloxApiScript, username: String, user_id: String, avatar: Dictionary) -> void:
        if _auth_done:
                return
        _auth_done = true
        api_ref = api
        platform_user_id = user_id
        my_avatar = avatar if avatar is Dictionary else {}
        player_name = username if not username.is_empty() else player_name
        profile.set_value("platform", "token", api.token)
        profile.set_value("platform", "username", username)
        profile.save("user://profile.cfg")
        # OFF the login card NOW — main.gd gates _process/_physics_process on
        # auth.visible, so leaving it up froze the whole game on this screen
        # (the "stuck at the page after logging in" bug).
        if auth != null:
                auth.visible = false
        if hud != null:
                hud.add_chat("", "Signed in as %s — wearing your account avatar." % player_name, true)
        _begin_online()

func _begin_online() -> void:
        if quitting:
                return
        if dedicated or force_host:
                _start_server()
        elif not server_address.is_empty():
                _connect_to(server_address)
        else:
                _begin_discovery()

# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
        if dedicated or hud == null:
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
        phase_time += delta
        _pump_discovery(delta)
        if phase == "connecting" and phase_time > 8.0:
                _schedule_retry("Server did not answer. Retrying…")
        elif phase == "retry" and phase_time > 3.0:
                if server_address.is_empty():
                        _begin_discovery()
                else:
                        _connect_to(server_address)
        for id in players:
                var p = players[id]
                if not server_mode and int(id) != local_id:
                        p.render_remote(delta)
                p.update_visuals(delta)
                if not server_mode and not p.alive:
                        p.respawn_left = maxf(p.respawn_left - delta, 0.0)
        if dedicated:
                return
        var local = players.get(local_id)
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
                hud.toast.text = "Rebuilding you… %.1f" % local.respawn_left if not local.alive else ""
                hud.reset_button.disabled = not local.alive
        else:
                hud.reset_button.disabled = true
                hud.toast.text = "Connecting to a real room…" if phase != "playing" else ""
        camera_pivot.rotation.y = camera_yaw
        spring_arm.rotation.x = camera_pitch
        spring_arm.spring_length = lerpf(spring_arm.spring_length, camera_distance, 1.0 - exp(-15.0 * delta))

func _physics_process(delta: float) -> void:
        if quitting or auth != null and auth.visible:
                return
        if phase != "playing":
                return
        var local = players.get(local_id)
        if local != null and local.alive and not dedicated:
                var direction := Vector2.ZERO
                if not hud.input_busy():
                        direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
                        if Input.is_action_just_pressed("jump"):
                                jump_serial += 1
                sequence += 1
                if server_mode:
                        _store_input(local_id, direction, camera_yaw, jump_serial, sequence, local.life_epoch, shiftlock)
                else:
                        local.drive(delta, direction, camera_yaw, jump_serial, shiftlock)
                        local.reconcile(delta)
                        send_time += delta
                        if send_time >= 1.0 / 30.0:
                                send_time = 0.0
                                _receive_input.rpc_id(1, direction, camera_yaw, jump_serial, sequence, local.life_epoch, shiftlock)
        if server_mode:
                for id in players.keys():
                        var p = players[id]
                        if p.alive:
                                p.input_age += delta
                                var direction: Vector2 = p.input_direction if p.input_age < 0.35 else Vector2.ZERO
                                p.drive(delta, direction, p.input_yaw, p.input_jump, p.input_shiftlock)
                                if p.global_position.y < -18.0:
                                        _kill_player(int(id))
                        else:
                                p.respawn_left -= delta
                                if p.respawn_left <= 0.0:
                                        var pos: Vector3 = arena.spawn_point(int(id) + p.life_epoch)
                                        var epoch: int = p.life_epoch + 1
                                        _life_event(int(id), true, pos, epoch, 0)
                                        _life_event.rpc(int(id), true, pos, epoch, 0)
                for id in pending_peers.keys():
                        pending_peers[id] = float(pending_peers[id]) + delta
                        if float(pending_peers[id]) > 10.0:
                                peer.disconnect_peer(int(id))
                                pending_peers.erase(id)
                snapshot_time += delta
                if snapshot_time >= 0.05:
                        snapshot_time = 0.0
                        var rows: Array = []
                        for id in players:
                                var p = players[id]
                                rows.append([int(id), p.global_position, p.velocity, p.heading, p.grounded, p.life_epoch])
                        if not multiplayer.get_peers().is_empty():
                                _snapshot.rpc(rows)

# ---------------------------------------------------------------- discovery

func _begin_discovery() -> void:
        _close_discovery()
        phase = "discovering"
        phase_time = 0.0
        discover_delay = randf_range(1.8, 2.6)
        probe_time = 1.0
        discovery = PacketPeerUDP.new()
        if discovery.bind(0) != OK:
                _start_server()
                return
        discovery.set_broadcast_enabled(true)
        _status("Finding a LAN game…", false)

func _pump_discovery(delta: float) -> void:
        if discovery_listener != null:
                # Bounded work per frame; ignore all unrelated LAN traffic.
                for _i in range(mini(discovery_listener.get_available_packet_count(), 32)):
                        var bytes := discovery_listener.get_packet()
                        if bytes.size() > 64 or bytes.get_string_from_utf8() != DISCOVER:
                                continue
                        var ip := discovery_listener.get_packet_ip()
                        var reply_port := discovery_listener.get_packet_port()
                        discovery_listener.set_dest_address(ip, reply_port)
                        discovery_listener.put_packet((VERSION + ":" + str(port)).to_utf8_buffer())
        if phase != "discovering" or discovery == null:
                return
        probe_time += delta
        if probe_time >= 0.35:
                probe_time = 0.0
                for address in ["127.0.0.1", "255.255.255.255"]:
                        discovery.set_dest_address(address, discovery_port)
                        discovery.put_packet(DISCOVER.to_utf8_buffer())
        for _i in range(mini(discovery.get_available_packet_count(), 32)):
                var bytes := discovery.get_packet()
                if bytes.size() > 64:
                        continue
                var message := bytes.get_string_from_utf8()
                var parts := message.split(":")
                if parts.size() == 2 and parts[0] == VERSION and parts[1].is_valid_int():
                        var offered_port: int = int(parts[1])
                        if offered_port < 1024 or offered_port > 65535:
                                continue
                        var ip := discovery.get_packet_ip()
                        port = offered_port
                        _close_discovery()
                        _connect_to(ip)
                        return
        if phase_time > discover_delay:
                _close_discovery()
                _start_server()

# ---------------------------------------------------------------- networking

func _start_server() -> void:
        _close_network()
        peer = ENetMultiplayerPeer.new()
        # Try a few ports in order — a zombie/stuck instance may hold the
        # default one. Hosting on the next free port beats looping forever
        # against a local "server" that can never accept us.
        var error: int = peer.create_server(port, max_players if dedicated else max_players - 1, 3)
        if error != OK and not dedicated and not force_host:
                for extra in range(1, 5):
                        port += 1
                        error = peer.create_server(port, max_players - 1, 3)
                        if error == OK:
                                break
        if error != OK:
                peer = null
                if dedicated or force_host:
                        push_error("Cannot listen on UDP %d (error %d). Is another server using it?" % [port, error])
                        _status("Could not host: UDP port is already in use.", false)
                        phase = "failed"
                        if dedicated:
                                get_tree().quit(1)
                else:
                        # Another local instance may have won the auto-host race.
                        _connect_to("127.0.0.1")
                return
        multiplayer.multiplayer_peer = peer
        server_mode = true
        local_id = 0 if dedicated else 1
        phase = "playing"
        phase_time = 0.0
        discovery_listener = PacketPeerUDP.new()
        if discovery_listener.bind(discovery_port) != OK:
                discovery_listener.close()
                discovery_listener = null
                print("LAN discovery unavailable; direct UDP joining still works.")
        if not dedicated:
                _spawn_player(1, _clean_name(player_name, 1), arena.spawn_point(0), true, 0, platform_user_id)
                _status("●  Hosting  /  UDP %d" % port, true)
                _system_notice("Your game is open — other players on this network can join now.")
        print("SERVER_READY port=%d dedicated=%s" % [port, str(dedicated)])

func _connect_to(address: String) -> void:
        _close_network()
        phase = "connecting"
        phase_time = 0.0
        peer = ENetMultiplayerPeer.new()
        var error := peer.create_client(address, port, 3)
        if error != OK:
                _schedule_retry("Could not reach the server. Retrying…")
                return
        multiplayer.multiplayer_peer = peer
        _status("Joining %s…" % address.left(40), false)

func _connected_to_server() -> void:
        local_id = multiplayer.get_unique_id()
        phase = "playing"
        phase_time = 0.0
        _status("●  Connected  /  " + room_name, true)
        _register_player.rpc_id(1, player_name, VERSION, platform_user_id)

func _connection_failed() -> void:
        _schedule_retry("Server unavailable. Retrying in 3 seconds…")

func _server_disconnected() -> void:
        if quitting:
                return
        _system_notice("The host disconnected. Finding your way back…")
        _schedule_retry("Disconnected. Reconnecting…")

func _schedule_retry(message: String) -> void:
        _close_network()
        _clear_players()
        phase = "retry"
        phase_time = 0.0
        _status(message, false)

func _close_discovery() -> void:
        if discovery != null:
                discovery.close()
                discovery = null

func _close_network() -> void:
        server_mode = false
        local_id = 0
        _close_discovery()
        if discovery_listener != null:
                discovery_listener.close()
                discovery_listener = null
        if peer != null:
                multiplayer.multiplayer_peer = null
                peer.close()
                peer = null
        pending_peers.clear()

func _clear_players() -> void:
        for p in players.values():
                p.queue_free()
        players.clear()
        for debris in debris_root.get_children():
                debris.queue_free()
        camera_initialized = false
        jump_serial = 0
        _update_roster()

func _peer_connected(id: int) -> void:
        if server_mode:
                pending_peers[id] = 0.0

func _peer_disconnected(id: int) -> void:
        if not server_mode:
                return
        pending_peers.erase(id)
        if players.has(id):
                var leaving_name: String = players[id].display_name
                _remove_player(id)
                # ENet removes the disconnected peer after this signal returns.
                # Defer broadcasts so they cannot target its already-closed channels.
                _announce_departure.call_deferred(id, leaving_name)

func _announce_departure(id: int, leaving_name: String) -> void:
        if not server_mode or quitting:
                return
        _remove_player.rpc(id)
        _system_notice(leaving_name + " left the game.")
        _system_notice.rpc(leaving_name + " left the game.")

@rpc("any_peer", "call_remote", "reliable", 0)
func _register_player(requested_name: String, version: String, user_id: String) -> void:
        if not server_mode:
                return
        var id := multiplayer.get_remote_sender_id()
        if id <= 1 or players.has(id):
                return
        if version != VERSION or players.size() >= max_players:
                peer.disconnect_peer(id)
                return
        pending_peers.erase(id)
        var safe_name := _clean_name(requested_name, id)
        for p in players.values():
                if p.display_name == safe_name:
                        safe_name = safe_name.left(12) + "-%04d" % (id % 10000)
                        break
        var position: Vector3 = arena.spawn_point(players.size())
        _spawn_player(id, safe_name, position, true, 0, user_id)
        var roster: Array = []
        for other_id in players:
                var p = players[other_id]
                roster.append([int(other_id), p.display_name, p.global_position, p.alive, p.life_epoch, p.platform_user_id])
        _roster.rpc_id(id, roster, room_name)
        _spawn_player.rpc(id, safe_name, position, true, 0, user_id)
        _system_notice(safe_name + " joined the game.")
        _system_notice.rpc(safe_name + " joined the game.")
        print("PLAYER_JOINED id=%d name=%s user=%s players=%d" % [id, safe_name, user_id, players.size()])

func _clean_name(value: String, id: int) -> String:
        var result := ""
        for c in value.left(80):
                var n := c.unicode_at(0)
                if (n >= 48 and n <= 57) or (n >= 65 and n <= 90) or (n >= 97 and n <= 122) or c in [" ", "-", "_"]:
                        result += c
                if result.length() >= 18:
                        break
        result = result.strip_edges()
        return result if not result.is_empty() else "Guest-%04d" % (id % 10000)

@rpc("authority", "call_remote", "reliable", 0)
func _roster(rows: Array, title: String) -> void:
        room_name = title
        for row in rows:
                _spawn_player(int(row[0]), str(row[1]), row[2], bool(row[3]), int(row[4]), str(row[5]))
        _status("●  Connected  /  " + room_name, true)
        if hud != null:
                hud.room_label.text = room_name + "  /  Classic worlds, your way."
                hud.set_room_title(room_name)

@rpc("authority", "call_remote", "reliable", 0)
func _spawn_player(id: int, safe_name: String, pos: Vector3, live: bool, epoch: int, user_id: String) -> void:
        if players.has(id):
                return
        var p = PlayerScene.instantiate() as Player
        # add to the tree first so the scene's nodes exist, then initialize
        player_root.add_child(p)
        p.initialize(id, safe_name)
        p.platform_user_id = user_id
        p.respawn_at(pos, epoch)
        p.alive = live
        p.avatar.visible = live
        p.respawn_left = RESPAWN_SECONDS if not live else 0.0
        players[id] = p
        if id == local_id:
                jump_serial = 0
                if hud != null:
                        p.health_changed.connect(hud.set_health)
                        p.health_depleted.connect(_on_local_health_depleted)
                        hud.set_health(p.health, p.MAX_HEALTH)
        _update_roster()
        # fetch + paint the account avatar (async; guests keep noob colors)
        _dress_player(p)

func _remove_player(id: int) -> void:
        if players.has(id):
                players[id].queue_free()
                players.erase(id)
        _update_roster()

func _update_roster() -> void:
        debug_stats["max_players_seen"] = maxi(int(debug_stats["max_players_seen"]), players.size())
        if hud == null:
                return
        var entries: Array = []
        for id in players:
                entries.append({"id": int(id), "name": players[id].display_name})
        hud.update_roster(entries, local_id)

# ---------------------------------------------------------------- avatars

## Fetch the RetroBlox account avatar for a player and paint it on.
## Guests (user_id == "") are skipped: they wear the classic noob colors.
func _dress_player(p) -> void:
        if p == null or not is_instance_valid(p) or p.platform_user_id.is_empty():
                return
        if api_ref == null:
                return
        var payload := {}
        if p.platform_user_id == platform_user_id and not my_avatar.is_empty():
                payload = my_avatar
        elif _avatar_cache.has(p.platform_user_id):
                payload = _avatar_cache[p.platform_user_id]
        else:
                var res: Dictionary = await api_ref.get_avatar(p.platform_user_id)
                if not is_instance_valid(p) or quitting:
                        return
                if res.get("ok", false) and res.get("avatar", {}) is Dictionary:
                        payload = res.get("avatar", {})
                        _avatar_cache[p.platform_user_id] = payload
        if payload.is_empty() or not is_instance_valid(p):
                return
        await p.dress_from_payload(api_ref, payload)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(direction: Vector2, yaw: float, jump: int, seq: int, epoch: int, use_shiftlock: bool) -> void:
        if server_mode:
                _store_input(multiplayer.get_remote_sender_id(), direction, yaw, jump, seq, epoch, use_shiftlock)

func _store_input(id: int, direction: Vector2, yaw: float, jump: int, seq: int, epoch: int, use_shiftlock: bool) -> void:
        if not players.has(id) or not direction.is_finite() or not is_finite(yaw):
                return
        var p = players[id]
        if not p.alive or epoch != p.life_epoch or seq <= p.last_sequence or jump < 0 or jump > 1000000000:
                return
        p.input_direction = direction.limit_length(1.0)
        p.input_yaw = wrapf(yaw, -PI, PI)
        p.input_jump = maxi(p.input_jump, jump)
        p.input_shiftlock = use_shiftlock
        p.last_sequence = seq
        p.input_age = 0.0

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(rows: Array) -> void:
        debug_stats["snapshots_received"] = int(debug_stats["snapshots_received"]) + 1
        for row in rows:
                var id: int = int(row[0])
                if not players.has(id):
                        continue
                var p = players[id]
                # Life changes arrive reliably. Ignore stale motion from another life.
                if int(row[5]) != p.life_epoch or not p.alive:
                        continue
                p.accept_snapshot(row[1], row[2], float(row[3]), bool(row[4]), id == local_id)

## Local health hit zero (a big fall) — the same reset/respawn flow as the
## menu's Reset button; the server stays the authority over the respawn.
func _on_local_health_depleted() -> void:
        var local = players.get(local_id)
        if local != null and local.alive:
                request_reset()

func request_reset() -> void:
        if hud != null:
                hud.set_menu(false)
        if phase != "playing" or not players.has(local_id):
                return
        if server_mode:
                _kill_player(local_id)
        else:
                _request_reset.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_reset() -> void:
        if server_mode:
                _kill_player(multiplayer.get_remote_sender_id())

func _kill_player(id: int) -> void:
        if not players.has(id) or not players[id].alive:
                return
        var p = players[id]
        var epoch: int = p.life_epoch + 1
        var seed_value: int = randi_range(1, 1000000)
        var pos: Vector3 = p.global_position
        _life_event(id, false, pos, epoch, seed_value)
        _life_event.rpc(id, false, pos, epoch, seed_value)

@rpc("authority", "call_remote", "reliable", 0)
func _life_event(id: int, live: bool, pos: Vector3, epoch: int, seed_value: int) -> void:
        if not players.has(id):
                return
        var p = players[id]
        if epoch <= p.life_epoch:
                return
        if live:
                p.respawn_at(pos, epoch)
                p.respawn_left = 0.0
                debug_stats["respawns_seen"] = int(debug_stats["respawns_seen"]) + 1
                if id == local_id:
                        jump_serial = 0
                        camera_initialized = false
        else:
                p.global_position = pos
                p.respawn_left = RESPAWN_SECONDS
                if dedicated:
                        p.alive = false
                        p.life_epoch = epoch
                        p.velocity = Vector3.ZERO
                        p.avatar.visible = false
                else:
                        p.die(debris_root, epoch, seed_value)
                debug_stats["deaths_seen"] = int(debug_stats["deaths_seen"]) + 1

func send_chat(message: String) -> void:
        if phase != "playing" or not players.has(local_id):
                _system_notice("You are not connected yet.")
                return
        if server_mode:
                _accept_chat(local_id, message)
        else:
                _request_chat.rpc_id(1, message)

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_chat(message: String) -> void:
        if server_mode:
                _accept_chat(multiplayer.get_remote_sender_id(), message)

func _accept_chat(id: int, message: String) -> void:
        if not players.has(id):
                return
        var p = players[id]
        var now: float = Time.get_ticks_msec() / 1000.0
        if now - p.chat_last < 0.8:
                return
        var clean := ""
        for c in message.left(512):
                var code := c.unicode_at(0)
                # Strip control/bidi characters. Display only plain text, never BBCode.
                if code >= 32 and code != 127 and not (code >= 0x200B and code <= 0x200F) and not (code >= 0x202A and code <= 0x202E) and not (code >= 0x2060 and code <= 0x206F):
                        clean += c
                if clean.length() >= 180:
                        break
        clean = clean.strip_edges()
        if clean.is_empty():
                return
        p.chat_last = now
        _chat_event(id, p.display_name, clean)
        _chat_event.rpc(id, p.display_name, clean)

@rpc("authority", "call_remote", "reliable", 0)
func _chat_event(id: int, sender_name: String, message: String) -> void:
        debug_stats["chats_received"] = int(debug_stats["chats_received"]) + 1
        if hud != null:
                hud.add_chat(sender_name, message)
        if players.has(id):
                players[id].show_message(message)

@rpc("authority", "call_remote", "reliable", 0)
func _system_notice(message: String) -> void:
        if hud != null:
                hud.add_chat("", message, true)

func _status(text: String, connected: bool) -> void:
        if hud != null:
                hud.set_status(text, connected)

func quit_game() -> void:
        if quitting:
                return
        quitting = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        # Give ENet a short chance to send a clean disconnect before closing sockets.
        if peer != null and not server_mode and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
                var server_peer := peer.get_peer(1)
                if server_peer != null:
                        server_peer.peer_disconnect()
                await get_tree().create_timer(0.15).timeout
        _close_network()
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
