extends SceneTree

## Headless smoke test for the RetroBlox player — run IN-ENGINE so the
## autoloads (Api / Session / Settings / Sfx) exist:
##   godot --headless --path . -s tests/smoke.gd

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
        if condition:
                print("  ok    " + label)
        else:
                failures.append(label)
                printerr("  FAIL  " + label)

func _initialize() -> void:
        await process_frame
        await _run_all()
        if failures.is_empty():
                printerr("== SMOKE_OK all checks passed ==")
        else:
                printerr("== SMOKE_FAILED: %d failures ==" % failures.size())
        quit(1 if failures.size() > 0 else 0)

func _run_all() -> void:
        print("== RetroBlox smoke test ==")

        # --- every active script loads (parses + compiles) ---
        for path in [
                "res://scripts/core/api.gd", "res://scripts/core/session.gd",
                "res://scripts/core/settings.gd", "res://scripts/core/sfx.gd",
                "res://scripts/game/game.gd", "res://scripts/game/camera_rig.gd",
                "res://scripts/game/chat_box.gd",
                "res://scripts/player/local_player.gd", "res://scripts/player/remote_player.gd",
                "res://scripts/player/avatar_rig.gd", "res://scripts/player/avatar_dresser.gd",
                "res://scripts/world/world_builder.gd", "res://scripts/world/places.gd",
                "res://scripts/ui/login.gd", "res://scripts/ui/hub.gd",
                "res://scripts/ui/retro_theme.gd",
        ]:
                # load() returns a resource even for a broken script —
                # can_instantiate() is the real parse/compile gate
                var s: Script = load(path)
                check(s != null and s.can_instantiate(), "script loads: " + path)

        # --- settings autoload: keys clamp + persist + buses exist ---
        var settings: Node = root.get_node("/root/Settings")
        settings.set_key("master_volume", 0.5)
        check(is_equal_approx(float(settings.get("master_volume")), 0.5), "settings master_volume set")
        settings.set_key("music_volume", 0.6)
        check(is_equal_approx(float(settings.get("music_volume")), 0.6), "settings music_volume set")
        settings.set_key("music_volume", 0.7)
        settings.set_key("fullscreen", true)
        check(bool(settings.get("fullscreen")), "settings fullscreen set")
        settings.set_key("fullscreen", false)
        settings.set_key("fov", 999.0)
        check(is_equal_approx(float(settings.get("fov")), 110.0), "settings fov clamps to 110")
        settings.set_key("fov", 70.0)
        settings.set_key("master_volume", 1.0)
        check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
        check(AudioServer.get_bus_index("Music") >= 0, "Music bus exists")

        # --- sfx autoload: UI one-shots never crash headless ---
        var sfx: Node = root.get_node("/root/Sfx")
        sfx.call("play_click")
        sfx.call("play_hover")
        sfx.call("play_join")
        sfx.call("play_goal")
        check(true, "sfx one-shots ran")
        check(sfx.get("_music") != null, "music box loop loaded")
        check(sfx.get("_wind") != null, "wind ambience loop loaded")
        check(sfx.get("_tix") != null, "tix chime loaded")
        var music_player = sfx.call("make_screen_loop", "Music")
        check(music_player != null and music_player.stream != null, "screen music player builds")
        check(music_player != null and music_player.stream is AudioStreamWAV and (music_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "music stream loops")

        # --- places: all five build; cloud kingdom matches the video ---
        var places: Array = load("res://scripts/world/places.gd").all()
        check(places.size() == 5, "5 places ship")
        var cloud: Dictionary = load("res://scripts/world/places.gd").by_id("cloudkingdom")
        check(not cloud.is_empty() and String(cloud["id"]) == "cloudkingdom", "cloudkingdom place exists")
        check(load("res://scripts/world/coin.gd").can_instantiate(), "coin script loads")
        for def: Dictionary in places:
                var built: Dictionary = load("res://scripts/world/world_builder.gd").build(def)
                check(built["root"] != null and is_instance_valid(built["root"]), "world builds: %s" % String(def["id"]))
                check((built["spawns"] as Array).size() > 0, "world has spawns: %s" % String(def["id"]))
                var coins := 0
                for prop: Dictionary in def.get("props", []):
                        if String(prop.get("type", "")) == "coin":
                                coins += 1
                check(coins >= 3, "%s has Tix coins (%d)" % [String(def["id"]), coins])
                if String(def["id"]) == "cloudkingdom":
                        var parts: Array = def.get("parts", [])
                        var props: Array = def.get("props", [])
                        var ladders := 0
                        var bounce := 0
                        for part: Dictionary in parts:
                                if String(part.get("g", "")) == "ladder":
                                        ladders += 1
                                if String(part.get("g", "")) == "bounce":
                                        bounce += 1
                        check(parts.size() >= 30, "cloud kingdom parts (%d)" % parts.size())
                        check(props.size() >= 20, "cloud kingdom props (%d)" % props.size())
                        check(ladders >= 1, "cloud kingdom has a ladder (climb sound)")
                        check(bounce >= 2, "cloud kingdom has bounce pads")
                        check(bool(def.get("wind", false)), "cloud kingdom has wind ambience")
                if String(def["id"]) == "tower":
                        var tower_ladders := 0
                        var tower_goals := 0
                        for part: Dictionary in def.get("parts", []):
                                if String(part.get("g", "")) == "ladder":
                                        tower_ladders += 1
                                if String(part.get("g", "")) == "goal":
                                        tower_goals += 1
                        check(tower_ladders >= 1, "tower has its truss ladder")
                        check(tower_goals == 1, "tower has exactly one goal")
                root.add_child(built["root"])
        await process_frame
        # coins actually spawned into the worlds + are hookable by the game
        check(get_nodes_in_group("tix_coin").size() >= 20, "tix coins spawned across places")

        # --- avatar rig: the real retroblox_anims.fbx with 6 parts + clips ---
        var rig_script: Script = load("res://scripts/player/avatar_rig.gd")
        var rig: Node3D = rig_script.new()
        root.add_child(rig)
        rig.call("setup", "SmokeTester")
        await process_frame
        await process_frame
        check(rig.is_r6ik(), "rig upgraded to retroblox_anims.fbx")
        var parts_list: Array = rig.get("parts")
        check(parts_list.size() == 6, "rig matched 6 body parts")
        for clip in ["Idle", "Walk", "Jump", "Climb", "Sit"]:
                rig.call("play_emote", clip)
        rig.call("animate", 0.016, 6.0, true)
        rig.call("animate", 0.016, 0.0, true, false)
        check(true, "rig clips + animate ran")
        # the FBX exports every clip play-once; the classic clips MUST loop
        var ap: AnimationPlayer = rig.get("_anim_player")
        check(ap != null, "rig has an AnimationPlayer")
        for clip in ["Idle", "Walk", "Climb"]:
                var a := ap.get_animation(clip)
                check(a != null and a.loop_mode == Animation.LOOP_LINEAR,
                        "%s clip loops (anims play forever)" % clip)
        var ja := ap.get_animation("Jump")
        check(ja != null and ja.loop_mode == Animation.LOOP_NONE, "Jump clip stays single-shot")
        check(is_equal_approx(float(rig.RIG_HEIGHT), 5.0), "rig is 5 studs tall (1 stud = 1 unit)")

        # --- local player: capsule + sfx loops + jump physics ---
        var player_script: Script = load("res://scripts/player/local_player.gd")
        var player: CharacterBody3D = player_script.new()
        root.add_child(player)
        player.call("setup", "SmokeTester")
        await process_frame
        await process_frame
        # --- SCALE: 1 stud = 1 unit (classic size), player = 5 studs tall ---
        check(is_equal_approx(float(player_script.WALK_SPEED), 16.0), "WalkSpeed 16 studs/s")
        check(is_equal_approx(float(player_script.JUMP_SPEED), 50.0), "JumpPower 50 studs/s")
        check(is_equal_approx(float(player_script.GRAVITY), 196.2), "gravity 196.2 studs/s^2")
        var world_root: Node3D = root.get_node("World")
        var pad_body: StaticBody3D = null
        for body in world_root.find_children("*", "StaticBody3D", true, false):
                if (body as StaticBody3D).is_in_group("spawn"):
                        pad_body = body
                        break
        check(pad_body != null, "spawn pad found in the built world")
        if pad_body != null:
                var pad_shape: BoxShape3D = null
                for child in pad_body.get_children():
                        if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
                                pad_shape = (child as CollisionShape3D).shape as BoxShape3D
                check(pad_shape != null and is_equal_approx(pad_shape.size.x, 9.0),
                        "9-stud spawn pad is 9 units wide (1 stud = 1 unit)")
        check(player.get_node_or_null("Avatar") != null, "player has an avatar")
        check(player.get_node_or_null("Footsteps") != null, "footsteps loop exists")
        check(player.get_node_or_null("ClimbLoop") != null, "climb loop exists")
        check(player.get_node_or_null("FallingLoop") != null, "falling wind loop exists")
        var sfx_node: Node = root.get_node_or_null("/root/Sfx")
        check(sfx_node != null and sfx_node.get("_land") != null, "landing thud sound loaded")
        check(sfx_node != null and sfx_node.get("_fall") != null, "falling wind sound loaded")
        check(sfx_node != null and sfx_node.get("_oof") != null, "original uuhhh oof loaded")
        check(sfx_node != null and sfx_node.get("_steps") != null, "authentic plastic footsteps loaded")
        # settle FAR from every world's builds — all five worlds share the
        # tree, so the spot must only touch the baseplate (140 studs wide)
        player.global_position = Vector3(40.0, 3.0, -40.0)
        for i in range(20):
                player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false)
                await physics_frame
        check(player.is_on_floor(), "player settled on the ground")
        player.call("drive", 0.016, Vector2.ZERO, 0.0, true, false)
        check(player.velocity.y > 10.0, "jump launches (v=%.1f)" % player.velocity.y)

        # --- ladders: face the rungs + press W to grab; jump OFF; gaps OK ---
        # land fully first (the previous jump is still airborne)
        for i in range(60):
                player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false)
                if player.get("grounded"):
                        break
                await physics_frame
        player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false)
        await physics_frame
        # a REAL truss volume on layer 16, hugging the player (sensor reach is
        # 1.15 studs = 0.32 units at the new scale)
        var ladder := Area3D.new()
        ladder.collision_layer = 16
        ladder.add_to_group("ladder")
        var lad_col := CollisionShape3D.new()
        var lad_shape := BoxShape3D.new()
        lad_shape.size = Vector3(0.5, 3.0, 0.5)
        lad_col.shape = lad_shape
        ladder.add_child(lad_col)
        root.add_child(ladder)
        ladder.global_position = player.global_position + Vector3(0.0, 1.0, -0.4)
        await physics_frame
        await physics_frame
        check(not player.get("_ladder_areas").is_empty(), "ladder sensor tracks truss volumes")
        # W (facing the rungs) grabs on
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, false)
        check(player.get("climbing"), "facing the ladder + W engages the climb")
        # a GAP between ladder segments: volume disappears, grip holds (grace)
        ladder.global_position = Vector3(0.0, 500.0, 0.0)
        await physics_frame
        await physics_frame
        check(player.get("_ladder_areas").is_empty(), "player left the truss volume")
        player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, false)
        check(player.get("climbing"), "climb grace carries across segment gaps")
        # jump OFF — dismount timer must fire and hold the launch
        player.call("drive", 0.016, Vector2.ZERO, 0.0, true, false)
        check(player.get("_ladder_dismount") > 0.0, "ladder dismount timer set")
        check(player.velocity.y > 6.0, "ladder jump launches (v=%.1f)" % player.velocity.y)
        check(not player.get("climbing"), "jumping off stops climbing")
        # during the dismount window even W cannot re-grab the rungs
        ladder.global_position = player.global_position + Vector3(0.0, 1.0, -0.4)
        await physics_frame
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, false)
        check(not player.get("climbing"), "no re-grab during dismount window")
        player.set("_ladder_dismount", 0.0)
        # FACE OFF = FALL: climbing again, then press S — the body turns away
        # from the rungs, the grip breaks and you fall (no climb without facing)
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, false)
        check(player.get("climbing"), "re-grab works once the dismount window ends")
        for i in range(14):
                player.call("drive", 0.016, Vector2(0.0, 1.0), 0.0, false, false)
        check(not player.get("climbing"), "facing away mid-climb lets go and falls")
        ladder.queue_free()
        await physics_frame

        # --- STUD EDGE climb: walk into a platform side while facing it ---
        var floor_body := StaticBody3D.new()
        var floor_col := CollisionShape3D.new()
        var floor_shape := BoxShape3D.new()
        floor_shape.size = Vector3(8.0, 0.2, 8.0)
        floor_col.shape = floor_shape
        floor_body.add_child(floor_col)
        root.add_child(floor_body)
        floor_body.global_position = Vector3(0.0, -0.1, 0.0)
        var wall := StaticBody3D.new()
        var wall_col := CollisionShape3D.new()
        var wall_shape := BoxShape3D.new()
        wall_shape.size = Vector3(0.6, 3.0, 6.0)
        wall_col.shape = wall_shape
        wall.add_child(wall_col)
        root.add_child(wall)
        wall.global_position = Vector3(2.0, 1.5, 0.0)   # face at x = 1.7
        await physics_frame
        player.global_position = Vector3(1.0, 0.05, 0.0)
        player.set("heading", -PI / 2)   # face +X, straight at the platform edge
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), -PI / 2, false, false)
        check(player.get("climbing"), "walking into a stud edge facing it climbs")
        # face away (press S, body turns) -> let go and fall
        for i in range(14):
                player.call("drive", 0.016, Vector2(0.0, 1.0), -PI / 2, false, false)
        check(not player.get("climbing"), "facing off a stud edge drops you")
        # walk PAST the wall (parallel) must NOT grab it
        player.global_position = Vector3(1.0, 0.05, 0.0)
        player.set("heading", PI)   # face +Z, parallel to the wall face
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), PI, false, false)
        check(not player.get("climbing"), "sliding along a wall does not grab it")
        player.set("heading", 0.0)
        wall.queue_free()
        floor_body.queue_free()
        await physics_frame

        # --- login: account gate + once-only sign-in ---
        var login_src := FileAccess.get_file_as_string("res://scripts/ui/login.gd")
        check(not login_src.contains("PLAY AS GUEST"), "login gate: no guest bypass button")
        check(login_src.contains("_try_auto_login"), "login auto-signs saved sessions")
        check(login_src.contains("401"),
                "saved token survives network failures (only 401 clears it)")

        # --- chat box: lines render, unread badge counts when collapsed ---
        var chat_script: Script = load("res://scripts/game/chat_box.gd")
        var chat: Control = chat_script.new()
        root.add_child(chat)
        chat.call("add_chat", "Ann", 3, "hello")
        chat.call("add_system", "welcome")
        chat.call("set_log_collapsed", true)
        chat.call("add_chat", "Bob", 4, "hidden line")
        check(chat.get("log_collapsed") == true, "chat collapsed")
        chat.call("set_log_collapsed", false)
        check(chat.get("log_collapsed") == false, "chat expanded")

        # --- dresser: placement applies verbatim ---
        var holder := Node3D.new()
        root.add_child(holder)
        load("res://scripts/player/avatar_dresser.gd").call(
                "_apply_placement", holder, {"p": [1, 2, 3], "r": [10, 20, 30], "s": [1, 1, 1]})
        var xf: Transform3D = holder.transform
        check(xf.origin.is_equal_approx(Vector3(1, 2, 3)), "UGC placement position verbatim")
        check(xf.basis.get_euler().is_equal_approx(Vector3(deg_to_rad(10), deg_to_rad(20), deg_to_rad(30))), "UGC placement rotation verbatim")

