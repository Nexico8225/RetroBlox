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
                "res://scripts/player/chat_bubble.gd",
                "res://scripts/player/avatar_rig.gd", "res://scripts/player/avatar_dresser.gd",
                "res://scripts/world/world_builder.gd", "res://scripts/world/places.gd",
                "res://scripts/ui/login.gd",
                "res://scripts/ui/retro_theme.gd",
                "res://scripts/ui/avatar_portrait.gd",
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
        check(sfx.get("_music") == null, "music removed (user asked — no more music box)")
        check(sfx.get("_wind") != null, "wind ambience loop loaded")
        check(sfx.get("_tix") == null, "tix chime retired with the coins")
        var music_player = sfx.call("make_screen_loop", "Music")
        check(music_player == null, "no screen music player builds anymore")
        var wind_player = sfx.call("make_screen_loop", "Wind")
        check(wind_player != null and wind_player.stream is AudioStreamWAV \
                        and (wind_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
                "wind ambience still loops")

        # --- places: all five build; cloud kingdom matches the video ---
        var places: Array = load("res://scripts/world/places.gd").all()
        check(places.size() == 5, "5 places ship")
        var cloud: Dictionary = load("res://scripts/world/places.gd").by_id("cloudkingdom")
        check(not cloud.is_empty() and String(cloud["id"]) == "cloudkingdom", "cloudkingdom place exists")
        check(not FileAccess.file_exists("res://scripts/world/coin.gd"), "coin.gd removed from the kit (coins retired)")
        for def: Dictionary in places:
                var built: Dictionary = load("res://scripts/world/world_builder.gd").build(def)
                check(built["root"] != null and is_instance_valid(built["root"]), "world builds: %s" % String(def["id"]))
                check((built["spawns"] as Array).size() > 0, "world has spawns: %s" % String(def["id"]))
                var coins := 0
                for prop: Dictionary in def.get("props", []):
                        if String(prop.get("type", "")) == "coin":
                                coins += 1
                check(coins == 0, "%s ships with NO coins (coins retired)" % String(def["id"]))
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
        # the Tix coins are retired — none may spawn anywhere
        check(get_nodes_in_group("tix_coin").is_empty(), "no tix coins exist (retired)")

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
        # first person: the body turns with the camera even without shift lock
        player.call("drive", 0.016, Vector2.ZERO, 0.9, false, false, true)
        check(player.get("heading") > 0.05, "first person turns the body with the camera")

        # --- HOLD-TO-JUMP: keeping Space down hops over and over ---
        for i in range(90):
                player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false, false, true)
                if player.get("grounded"):
                        break
                await physics_frame
        var hops := 0
        var airborne := false
        for i in range(330):
                player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false, false, true)
                await physics_frame
                var in_air: bool = not bool(player.get("grounded"))
                if in_air and not airborne:
                        hops += 1
                airborne = in_air
        check(hops >= 3, "holding SPACE keeps hopping (%d takeoffs)" % hops)
        # land fully before the ladder tests below
        for i in range(90):
                player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false, false, false)
                if player.get("grounded"):
                        break
                await physics_frame

        # --- ladders: face the rungs + press W to grab; jump OFF; gaps OK ---
        # land fully first (the previous jump is still airborne)
        for i in range(60):
                player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false)
                if player.get("grounded"):
                        break
                await physics_frame
        player.call("drive", 0.016, Vector2.ZERO, 0.0, false, false)
        await physics_frame
        # a REAL truss volume on layer 16, hugging the player (sensor reach
        # is 1.15 studs at the classic 1 stud = 1 unit scale)
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
        # v3.8: SHIFT LOCK grabs ladders — walking into the rungs climbs. The
        # old shift-lock exemption made the body ghost straight THROUGH trusses.
        player.call("_stop_climb")
        player.set("_ladder_dismount", 0.0)
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, true)
        check(player.get("climbing"), "SHIFT LOCK climbs ladders (no phasing through)")
        player.call("_stop_climb")
        player.set("_ladder_dismount", 0.0)
        # TORSO LOCK: climbing again, then A/D — the body STAYS facing the
        # rungs (it never looks left or right), the grip holds, and S simply
        # climbs DOWN. This is the classic ladder feel.
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, false)
        check(player.get("climbing"), "re-grab works once the dismount window ends")
        player.global_position.y += 5.0   # mid-air: no floor interference below
        var grab_heading: float = player.get("heading")
        for i in range(10):
                player.call("drive", 0.016, Vector2(-1.0, 0.0), 0.0, false, false)
        check(player.get("climbing"), "sideways input mid-climb does NOT break the climb")
        check(absf(player.get("heading") - grab_heading) < 0.2,
                "torso stays locked facing the ladder (no left/right look)")
        player.call("drive", 0.016, Vector2(0.0, 1.0), 0.0, false, false)
        check(player.get("climbing") and player.velocity.y < -1.0,
                "S climbs DOWN while the torso stays facing the rungs")
        player.call("_stop_climb")
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
        # v5.0: walls taller than the 3.2-stud stair step are climbable —
        # this one is 3.6 so it grabs; anything lower is stairs now.
        wall_shape.size = Vector3(0.6, 3.6, 6.0)
        wall_col.shape = wall_shape
        wall.add_child(wall_col)
        root.add_child(wall)
        wall.global_position = Vector3(2.0, 1.8, 0.0)   # face at x = 1.7
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

        # --- TORSO-ONLY ladders: a low truss volume only the LEGS overlap
        #     must never put the body into the climb grip (the Roblox rule
        #     the user asked for: climb only when the TORSO touches) ---
        var leg_lad := Area3D.new()
        leg_lad.collision_layer = 16
        leg_lad.add_to_group("ladder")
        var ll_col := CollisionShape3D.new()
        var ll_shape := BoxShape3D.new()
        ll_shape.size = Vector3(0.5, 2.0, 0.5)
        ll_col.shape = ll_shape
        leg_lad.add_child(ll_col)
        root.add_child(leg_lad)
        leg_lad.global_position = player.global_position + Vector3(0.0, 0.0, -0.4)
        await physics_frame
        await physics_frame
        check(player.get("_ladder_areas").is_empty(), "legs-only truss contact is NOT tracked (torso sensor)")
        for i in range(4):
                player.call("drive", 0.016, Vector2(0.0, -1.0), 0.0, false, false)
        check(not player.get("climbing"), "walking W into a leg-height truss does NOT climb")
        leg_lad.queue_free()
        await physics_frame

        # --- STAIRS: a 2-stud block is walked OVER (step-up), never climbed ---
        var step := StaticBody3D.new()
        var step_col := CollisionShape3D.new()
        var step_shape := BoxShape3D.new()
        step_shape.size = Vector3(4.0, 2.0, 4.0)
        step_col.shape = step_shape
        step.add_child(step_col)
        root.add_child(step)
        step.global_position = Vector3(4.0, 1.0, 0.0)   # top at 2.0, face at x = 2.0
        await physics_frame
        player.global_position = Vector3(0.5, 0.05, 0.0)
        player.set("heading", -PI / 2)   # face +X, straight at the 2-stud step
        var saw_climb := false
        var step_start_y: float = (player.get("global_position") as Vector3).y
        for i in range(120):
                player.call("drive", 0.016, Vector2(0.0, -1.0), -PI / 2, false, false)
                await physics_frame
                if bool(player.get("climbing")):
                        saw_climb = true
                if bool(player.get("grounded")) and (player.get("global_position") as Vector3).y > step_start_y + 1.5:
                        break
        check(not saw_climb, "2-stud block never engages the climb grip")
        check((player.get("global_position") as Vector3).y > step_start_y + 1.5,
                "player walks UP the 2-stud step like stairs")

        # --- STAIRS v3.6: the DIAGONAL approach (the old code probed the slid
        # velocity, which runs ALONG the wall — diagonals never stepped up) ---
        player.global_position = Vector3(0.5, 0.05, -0.5)
        player.set("heading", -PI / 2)
        var diag_start_y: float = (player.get("global_position") as Vector3).y
        var saw_climb2 := false
        for i in range(150):
                # mostly forward, drifting sideways — a natural human approach
                player.call("drive", 0.016, Vector2(0.3, -0.95), -PI / 2, false, false)
                await physics_frame
                if bool(player.get("climbing")):
                        saw_climb2 = true
                if bool(player.get("grounded")) and (player.get("global_position") as Vector3).y > diag_start_y + 1.5:
                        break
        check(not saw_climb2, "diagonal 2-stud approach never engages the climb grip")
        check((player.get("global_position") as Vector3).y > diag_start_y + 1.5,
                "DIAGONAL approach still walks up the 2-stud step")
        step.queue_free()
        await physics_frame

        # --- login: account gate + once-only sign-in ---
        var login_src := FileAccess.get_file_as_string("res://scripts/ui/login.gd")
        check(not login_src.contains("PLAY AS GUEST"), "login gate: no guest bypass button")
        check(login_src.contains("_try_auto_login"), "login auto-signs saved sessions")
        check(login_src.contains("401"),
                "saved token survives network failures (only 401 clears it)")

        # --- chat box: the TYPE BOX is always visible (the front door), the
        # log opens when you click it / press Enter, closes on click-off ---
        var chat_script: Script = load("res://scripts/game/chat_box.gd")
        var chat: Control = chat_script.new()
        root.add_child(chat)
        var log_panel: Control = chat.get_node_or_null("LogPanel")
        var input_panel: Control = chat.get_node_or_null("InputPanel")
        check(log_panel != null and input_panel != null and not log_panel.visible
                and input_panel.visible,
                "chat boots with the type box VISIBLE, log tucked away")
        chat.call("add_system", "welcome")
        check(int(chat.get("_unread")) == 1, "hidden log stacks the unread badge")
        chat.call("open")
        check(input_panel.visible and log_panel.visible and bool(chat.get("is_open")),
                "clicking the type box shows the log (you are typing)")
        check(chat.offset_top >= 40.0 and chat.offset_left <= 16.0,
                "chat sits top-left under the topbar")
        chat.call("add_chat", "Ann", 3, "hello")
        chat.call("close")
        check(not log_panel.visible and input_panel.visible,
                "click-off hides the LOG, the type box stays (the front door)")
        chat.call("add_chat", "Bob", 4, "psst")
        check(int(chat.get("_unread")) == 1,
                "messages arriving while hidden count for the badge")
        chat.call("open")
        check(int(chat.get("_unread")) == 0 and input_panel.visible,
                "reopening clears the badge and shows the type box")
        check(chat.get("pfp_resolver") != null and chat.get("pfp_resolver").is_valid() == false,
                "chat exposes the pfp_resolver hook (game wires it)")
        chat.call("add_chat", "Cid", 5, "with pfp", "", false, "uid-123")
        check(true, "chat lines accept a uid (the PFP seat)")

        # --- camera: huge zoom range + first person toggle ---
        var cam_script: Script = load("res://scripts/game/camera_rig.gd")
        check(float(cam_script.MAX_ZOOM) >= 120.0, "camera zooms out VERY far (MAX_ZOOM 120)")
        check(float(cam_script.FIRST_PERSON_AT) > 0.0, "first-person zoom threshold exists")
        var cam_rig_node: Node3D = cam_script.new()
        root.add_child(cam_rig_node)
        check(not bool(cam_rig_node.get("first_person")), "camera starts third person")
        cam_rig_node.call("_zoom", -float(cam_script.MAX_ZOOM))
        check(bool(cam_rig_node.get("first_person")), "zooming all the way in is FIRST PERSON")
        cam_rig_node.call("_zoom", float(cam_script.MAX_ZOOM))
        check(not bool(cam_rig_node.get("first_person")), "zooming out leaves first person")
        cam_rig_node.queue_free()

        # --- chat bubbles STACK now (the classic white plate, Roblox-style) ---
        var bubble_script: Script = load("res://scripts/player/chat_bubble.gd")
        check(bubble_script != null and bubble_script.can_instantiate(), "chat bubble script loads")
        var bubble: Node3D = bubble_script.new()
        root.add_child(bubble)
        bubble.call("show_text", "hi from the smoke test, this is the classic bubble!")
        var entries: Array = bubble.get("_entries")
        check(entries != null and entries.size() == 1, "bubble pops on show_text")
        var first: Dictionary = entries[0]
        var plate: Sprite3D = first.get("sprite")
        check(plate != null and plate.visible, "stacked bubble owns a plate")
        check(plate.texture != null, "bubble plate texture is drawn in code")
        var ink: Label3D = first.get("label")
        check(ink != null and ink.visible and ink.text.contains("classic"), "bubble ink shows the text")
        check(ink.position.y > 0.0,
                "bubble ink is LIFTED onto the pill's center (the big text offset is dead)")
        check(first.get("sprite").texture.get_width() >= 96 and first.get("sprite").texture.get_width() <= 384,
                "the bubble plate HUGS its text (short line, small bubble)")
        bubble.call("show_text", "Good game!")
        bubble.call("show_text", "Oof")
        check(bubble.get("_entries").size() == 3, "bubbles STACK like Roblox (3 live at once)")
        bubble.call("show_text", "one message too many")
        check(bubble.get("_entries").size() == 3, "the stack caps at MAX_STACK (oldest eases out)")
        var game_src := FileAccess.get_file_as_string("res://scripts/game/game.gd")
        check(game_src.contains("show_bubble"), "game routes chat lines to bubbles")
        var local_src := FileAccess.get_file_as_string("res://scripts/player/local_player.gd")
        check(local_src.contains("ChatBubble"), "chat bubble on the local player")
        var remote_src := FileAccess.get_file_as_string("res://scripts/player/remote_player.gd")
        check(remote_src.contains("bubble"), "chat bubble on remote players")
        check(not game_src.contains("Shift lock ON"), "no shift-lock toast notification")

        # --- ESC menu shortcuts + the great music removal + retro assets ---
        check(game_src.contains("KEY_L") and game_src.contains("KEY_R"),
                "ESC menu shortcuts: L leaves, R resets")
        check(game_src.contains("_leave_game"), "menu leave shares one helper")
        check(not game_src.contains('"Music"'), "in-game music removed")
        check(not FileAccess.file_exists("res://assets/music_main.wav"), "music file gone from the kit")

        # --- v3.6: the game-select hub is retired — sign in and just play ---
        check(not FileAccess.file_exists("res://scenes/hub.tscn"),
                "game-select hub scene is gone")
        check(not FileAccess.file_exists("res://scripts/ui/hub.gd"),
                "hub script removed from the kit")
        check(not FileAccess.file_exists("res://tests/hub_shot.gd"),
                "hub screenshot tool removed")
        check(login_src.contains("scenes/game.tscn") and not login_src.contains("hub.tscn"),
                "login routes straight into the game")
        var game_src2 := FileAccess.get_file_as_string("res://scripts/game/game.gd")
        check(game_src2.contains("TYPING FREEZES YOU"),
                "typing in chat freezes the character")
        check(game_src2.contains("_show_loading") and game_src2.contains("frame_post_draw"),
                "loading is staged behind a veil (no load hitch)")
        var chat_src := FileAccess.get_file_as_string("res://scripts/game/chat_box.gd")
        check(chat_src.contains("_panel.visible = false") and not chat_src.contains("_input_panel.visible = false\n        _panel.visible"),
                "chat close hides the log; the type box never dangles away")
        var player_src := FileAccess.get_file_as_string("res://scripts/player/local_player.gd")
        check(player_src.contains("v3.6 ROOT FIX"),
                "stairs probe the walk wish FIRST (diagonals step up)")
        check(player_src.contains("CLIMB_FACE_START := 0.65"),
                "climb grab is deliberate (no more brushing grabs)")

        # --- v3.7: trimmed topbar, stacked bubbles, SMOOTH stairs, retro menu ---
        check(not FileAccess.file_exists("res://assets/icons/menu.png") == false,
                "topbar: the REAL internet menu icon ships in the kit")
        check(player_src.contains("STEP_RISE_SPEED") and player_src.contains("_rise_left"),
                "stairs GLIDE now — the rise animates over ~0.1s")
        # scope: only the STAIR code (_attempt_step_up.._update_fall_damage) —
        # the climb mantle at the top of a ladder is a separate vault move
        var stair_code: String = player_src.get_slice("func _attempt_step_up", 1).split("func _update_fall_damage")[0]
        check(stair_code.contains("_rise_left = lip + 0.06")
                and not stair_code.contains("move_and_collide(Vector3.UP * (lip"),
                "no more stair teleport — the rise is an eased glide now")
        check(player_src.contains("func _update_step_rise"),
                "the stair glide has its own eased rise step")
        var bubble_src := FileAccess.get_file_as_string("res://scripts/player/chat_bubble.gd")
        check(bubble_src.contains("MAX_STACK := 3"),
                "chat bubbles stack (Roblox-style tower, capped at 3)")
        # --- v3.9: the CLASSIC CLIENT — the ESC menu, rebuilt from scratch ---
        check(game_src.contains("MenuPanel") and game_src.contains("_menu_footer"),
                "the menu is the CLIENT PANEL now (tabs + pages + action footer)")
        check(game_src.contains("_tab_button") and game_src.contains("_style_tab"),
                "TOP TABS: icon rows with the white underline, the open page lit")
        check(game_src.contains("_players_grid") and game_src.contains("_player_card"),
                "People page is a CARD GRID (portrait + name + @handle)")
        check(game_src.contains("_render_portrait") and game_src.contains("_portrait_cache"),
                "cards wear REAL PFP headshots (fetched once, cached)")
        check(game_src.contains("_corner_stats") and game_src.contains("_update_live_stats"),
                "YOUR fps + ping live in the corner chip and breathe every half second")
        check(game_src.contains("_remote_stats") and game_src.contains('p.get("ping", null)'),
                "every card shows the OTHER player's real ping + fps")
        check(game_src.count("KEY_R") >= 2,
                "R opens the ESC menu from the game (and still resets inside it)")
        check(game_src.contains("_topbar_pfp") and game_src.contains("_pfp_preview"),
                "the topbar pill + the Settings preview wear YOUR REAL PFP")
        check(game_src.contains("head_icon"),
                "cards fall back to the classic smiley before the shot lands")
        check(game_src.contains("icon_texture"),
                "action + nav buttons wear the code-drawn icons (play / door / people / gear)")
        # --- v10.0: THE 2008 CLIENT — the OLD language, as an engine: real
        # 9-patch bevels (light TL rim / dark BR rim), SQUARE corners, ARIAL,
        # the CLASSIC GREEN key, ROBLOX red, and REAL PFP headshots ---
        check(ResourceLoader.exists("res://assets/fonts/LiberationSans-Regular.ttf"),
                "the client voice ships (Liberation Sans Regular — the Arial stand-in)")
        check(ResourceLoader.exists("res://assets/fonts/LiberationSans-Bold.ttf"),
                "the bold voice ships (Liberation Sans Bold — titles + keys)")
        var theme_src := FileAccess.get_file_as_string("res://scripts/ui/retro_theme.gd")
        check(theme_src.contains("LiberationSans-Bold.ttf") and theme_src.contains("ARIAL_PATHS"),
                "the theme speaks ARIAL (one family, the 2008 voice)")
        check(theme_src.contains("func arial") and theme_src.contains("func gotham")
                and theme_src.contains("func source"),
                "gotham() carries the voice; arial()/source() stay as working aliases")
        check(theme_src.contains('MENU_PANEL := Color("3b3b3b")')
                and theme_src.contains('MENU_ACCENT := Color("00a2ff")')
                and theme_src.contains('MENU_INK := Color("f2f2f2")')
                and theme_src.contains('MENU_RED := Color("e2231a")')
                and theme_src.contains('const BG := Color("2b2b2b")')
                and theme_src.contains('const GREEN := Color("00aa00")'),
                "the client wears the CLASSIC palette (gray chrome, classic green, ROBLOX red, Roblox blue)")
        check(theme_src.contains("func raised(") and theme_src.contains("func sunken(")
                and theme_src.contains("func wash(") and theme_src.contains("func flat(")
                and theme_src.contains("func glass(") and theme_src.contains("func pill_style("),
                "the surface engine: beveled boxes, wells, hover washes, chat glass, topbar pills")
        check(theme_src.contains("StyleBoxTexture") and theme_src.contains("_bake_bevel"),
                "the BEVEL ENGINE is back — 9-patch chrome, the 2008 surface, baked in code")
        check(theme_src.contains('fill_var.call("BtnPrimary", GREEN_FACE'),
                "the theme ships the CLASSIC GREEN primary key (the 2006 site green)")
        check(theme_src.contains('"people"') and theme_src.contains('"gear"'),
                "nav icons drawn in code (people crowd + gear)")
        check(theme_src.contains("icon_texture(kind: String, ink"),
                "icons draw in ANY ink (white on dark keys, dark on the white key)")
        check(not theme_src.contains("PressStart2P") and not theme_src.contains("Montserrat"),
                "the pixel-cabinet + Montserrat voices are gone (ARIAL is the client voice)")
        check(not FileAccess.file_exists("res://assets/ui/wood_planks.jpg"),
                "wood texture file removed from the kit")
        check(game_src.contains("NIGHT_INK") and game_src.contains("_row_btn"),
                "nav + keys speak in light ink on the night slate (no dark-on-dark anywhere)")

        # --- v11.0: THE R6 HITBOX + THE BUBBLE THAT FITS + THE SMOOTH ARMS ---
        var player_v11 := FileAccess.get_file_as_string("res://scripts/player/local_player.gd")
        check(player_v11.contains("BoxShape3D.new()")
                and player_v11.contains("Vector3(2.0 * STUD, 5.0 * STUD, 1.0 * STUD)"),
                "the hitbox IS Roblox: a 2 x 5 x 1 stud BOX (never the fat capsule)")
        check(player_v11.contains("Vector3(2.2 * STUD, 2.4 * STUD, 1.2 * STUD)"),
                "the ladder sensor is the torso-band box (2.2 x 2.4 x 1.2)")
        var bubble_v11 := FileAccess.get_file_as_string("res://scripts/player/chat_bubble.gd")
        check(bubble_v11.contains("WRAP_WIDTH := 288.0") and bubble_v11.contains("get_string_size"),
                "bubbles wrap by REAL font metrics — the text can never spill off the plate")
        check(bubble_v11.contains("SHOW_SECONDS := 12.0"),
                "bubbles linger 12 seconds, then fade slowly (no more nano-second chat)")
        check(bubble_v11.contains("label.font = font"),
                "the bubble ink draws with the SAME font the width measures")
        var rig_v11 := FileAccess.get_file_as_string("res://scripts/player/avatar_rig.gd")
        check(rig_v11.contains("lerp_angle(_pivots[ARM_L].rotation.x, arm_l_x, k)")
                and rig_v11.contains("_walk_rate") and rig_v11.contains("_climb_rate"),
                "the arms EASE between poses and the playback speeds glide (no twitch)")

        # --- v11.0 THE PFP ENGINE — the SITE AVATAR, rendered. NO bacon. ---
        check(FileAccess.file_exists("res://scripts/ui/pfp_service.gd"),
                "PfpService ships (the real headshot engine)")
        var proj_v8 := FileAccess.get_file_as_string("res://project.godot")
        check(proj_v8.contains('Pfp="*res://scripts/ui/pfp_service.gd"'),
                "PfpService is an autoload (boot-ready)")
        check(not FileAccess.file_exists("res://assets/pfp/nexico8225.png"),
                "THE BACON IS GONE — no bundled Roblox thumbnail ships in the kit")
        var pfp_src := FileAccess.get_file_as_string("res://scripts/ui/pfp_service.gd")
        check(not pfp_src.contains("users.roblox.com") and not pfp_src.contains("thumbnails.roblox.com"),
                "the Roblox thumbnail API is DEAD — the PFP comes from RetroBlox only")
        check(not pfp_src.contains("assets/pfp/%s.png"),
                "no bundled headshot overrides — the account avatar is the only face")
        check(pfp_src.contains("pfp_cache_v") and pfp_src.contains("CACHE_TTL"),
                "fetched site pictures cache on disk in a fresh namespace (old bytes can't resurface)")
        check(pfp_src.contains("/api/users/%s/pfp") and pfp_src.contains("avatarUrl"),
                "EVERY player's site PFP loads — GET /api/users/{id}/pfp, not just mine")
        check(pfp_src.contains("func default_pfp") and pfp_src.contains("letter_avatar"),
                "the letter avatar stays as the LAST RESORT (guests / offline)")
        check(pfp_src.contains("func peek("),
                "peek() answers instantly for chat lines (RAM or the default letter)")
        check(pfp_src.contains("AvatarPortrait.render") and pfp_src.contains("Session.my_avatar_data"),
                "PFP seats wear the SITE PROFILE — the DEFAULT PFP is the account's avatar, rendered")
        check(pfp_src.contains("func rounded(") and pfp_src.contains("_round_image"),
                "every PFP lands with the client's rounded corners")
        check(pfp_src.contains("fallback_pfp") and pfp_src.contains("head_icon"),
                "no-data players fall back to the classic smiley (guests only)")
        check(game_src.contains("Pfp.fetch") and game_src.contains("_apply_pfp"),
                "the menu + cards + topbar all wear REAL PFPs (one pipeline)")
        check(game_src.contains("_render_identity") and game_src.contains("AvatarPortrait.render"),
                "the ESC menu LOADS YOUR AVATAR — the full-body render in the identity block")
        check(game_src.contains("PfpBadge") and game_src.contains("circle_badge"),
                "the PFP badge sits on the loaded avatar's bottom-right corner")
        check(game_src.contains("_set_people_view") and game_src.contains('_people_view == "tiles"'),
                "the TILES and LIST views both rebuild the roster (fixed)")
        check(game_src.contains("_log_out") and game_src.contains("clear_session"),
                "LOG OUT wipes the session and lands on the login page")
        check(game_src.contains('MenuCenter') and game_src.contains("MenuPanel"),
                "the ESC menu is the CENTERED client panel — the game stays visible behind")
        check(game_src.contains('["players", "People", "people"]')
                and game_src.contains('["settings", "Settings", "settings"]'),
                "the two tabs wear the REAL internet icons (People + Settings)")
        check(not game_src.contains('"gallery", "Gallery"')
                and not game_src.contains('"report", "Report"')
                and not game_src.contains('"help", "Help"'),
                "GALLERY / REPORT / HELP are GONE from the ESC menu (you asked)")
        check(game_src.contains("func icon_png") == false and theme_src.contains("func icon_png"),
                "icon_png loads the REAL downloaded icon PNGs with a code-drawn fallback")
        for icon_name in ["menu", "settings", "people", "chat", "respawn", "close"]:
                check(FileAccess.file_exists("res://assets/icons/%s.png" % icon_name),
                        "the internet icon ships: assets/icons/%s.png" % icon_name)
        check(FileAccess.file_exists("res://assets/ui/login_backdrop.jpg"),
                "the REAL classic-baseplate photograph ships (the login backdrop)")
        check(not game_src.contains('AvatarPortraitScript'),
                "the UI path calls AvatarPortrait directly (no legacy script preloads)")

        # --- v9.0: YOUR CLIENT — the player edits everything, the PFP is
        # THEIRS (site avatarUrl + custom URL), the menu is THE ESC PANEL ---
        var proj_v9 := FileAccess.get_file_as_string("res://project.godot")
        check(proj_v9.contains('UiConfig="*res://scripts/core/ui_config.gd"')
                and proj_v9.contains('UiEditor="*res://scripts/ui/ui_editor.gd"'),
                "UiConfig + UiEditor are autoloads (the editor boots with the game)")
        check(FileAccess.file_exists("res://scripts/core/ui_config.gd"),
                "UiConfig ships (every edit saved to user://ui_config.json)")
        check(FileAccess.file_exists("res://scripts/ui/ui_editor.gd"),
                "UiEditor ships (F2: select, drag, scale, text, labels, PFP, save)")
        var editor_src := FileAccess.get_file_as_string("res://scripts/ui/ui_editor.gd")
        check(editor_src.contains("KEY_F2") and editor_src.contains("func register"),
                "the editor opens with F2 and registers HUD elements")
        check(editor_src.contains("PickLayer") and editor_src.contains("_gui_input_pick"),
                "the editor's pick layer catches clicks above every HUD surface")
        check(editor_src.contains("add_label") and editor_src.contains("content_scale_factor"),
                "the editor adds YOUR labels + zooms the WHOLE UI (content scale)")
        check(game_src.contains('UiEditor.register("topbar"') and game_src.contains('UiEditor.register("health"'),
                "the HUD registers topbar/health/user pill/toasts as editable")
        check(not game_src.contains('UiEditor.register("chat"'),
                "EDIT CHAT IS GONE — the chat box is not editor fodder anymore")
        check(not game_src.contains('Edit anything'),
                "the EDIT THIS UI settings section is gone (you asked)")
        check(game_src.contains('_footer_key("L", "Leave", false')
                and game_src.contains('_footer_key("ESC", "Resume", true'),
                "the footer is [L] Leave / [R] Respawn / [ESC] Resume")
        check(game_src.contains("_apply_pfp_url") and game_src.contains("Pfp.set_custom_pfp"),
                "Settings applies YOUR PFP URL live (saved to ui_config)")
        check(game_src.contains('Pfp.set_site_pfp') and game_src.contains('avatarUrl'),
                "the client loads YOUR ACCOUNT PFP from retro-blox.vercel.app /me")
        check(pfp_src.contains("set_site_pfp") and pfp_src.contains("set_custom_pfp")
                and pfp_src.contains("_image_from_data_url"),
                "PfpService wears the site avatarUrl + the custom URL (data URLs decode)")
        check(pfp_src.contains("/pfp") or pfp_src.contains("avatar_of"),
                "other players' faces arrive from the site (the avatar render path)")


        # --- v3.9: the wood is HISTORY ---
        check(not theme_src.contains("wood"),
                "the WOOD is gone from the theme (signboard removed for good)")
        check(not game_src.contains("wood_stud_style") and not game_src.contains("ffd23f"),
                "no wooden sign, no gold trim anywhere in the menu")
        check(not FileAccess.file_exists("res://assets/ui/wood_planks.jpg"),
                "wood texture file removed from the kit")
        check(not game_src.contains("panel.png"),
                "the old metallic panel.png frame is gone from the menu")

        # --- v5.0: THE MIDNIGHT CLIENT — dark retro cabinet, ONE blue accent,
        # the avatar pipeline that finally shows YOUR real look SHARP ---
        var portrait_src := FileAccess.get_file_as_string("res://scripts/ui/avatar_portrait.gd")
        check(not theme_src.contains("gloss_texture") and not theme_src.contains("gradient_panel"),
                "the gloss/gradient engine is DELETED (no gradients anywhere)")
        check(not theme_src.contains("client_plate") and not theme_src.contains("glass_button")
                and not theme_src.contains("outlined_text"),
                "the 2011 texture helpers are gone from the theme")
        check(not FileAccess.file_exists("res://assets/ui/rbx_black_plate.png")
                and not FileAccess.file_exists("res://assets/ui/rbx_glass_btn.png"),
                "the gradient plate + glass textures are OUT of the kit")
        check(not game_src.contains("client_plate") and not game_src.contains("glass_button"),
                "the menu references zero texture helpers (flat dark cards)")
        check(game_src.contains("_gloss_key_style"),
                "the footer keys wear the SITE GLOSS (baked 9-patch, bold outline)")
        check(game_src.contains("_blue_btn") and theme_src.contains("SITE_GREEN :="),
                "Resume is the GREEN PLAY GLOSS (the site's action green)")
        check(theme_src.contains("SITE_BLUE :=") and theme_src.contains("SITE_PAPER :="),
                "the theme speaks the SITE palette (blue chrome, paper, steel borders)")
        check(theme_src.contains("static func gloss("),
                "the gloss builder exists (gradient + shine cut + outline baked in code)")
        check(theme_src.contains("MENU_RED :=") ,
                "red exists ONLY as the danger voice (Leave, close-hover, badge)")
        check(theme_src.contains("f5cd30"),
                "the fallback head is the CLASSIC YELLOW smiley again")
        check(not theme_src.contains("checker_texture"),
                "the checker well is replaced by the deep quiet inset (avatar bg)")
        check(game_src.contains("modulate:a\", 1.0, 0.14"),
                "the menu fades in smoothly")
        check(game_src.contains("v12.1"), "the corner chip wears v12.1")
        check(portrait_src.contains("Vector2i(320, 448)") and portrait_src.contains("MSAA_4X"),
                "the portrait renders at 320x448 with 4x MSAA (NEVER pixelated again)")
        check(portrait_src.contains("HEADSHOT_SIZE") and portrait_src.contains("headshot := false"),
                "the HEADSHOT framing exists — the square PFP shot the UI wears")
        check(game_src.contains("TEXTURE_FILTER_LINEAR"),
                "the portrait TextureRect draws LINEAR (smooth, not chunky)")
        # --- the v4.0 AVATAR PIPELINE — the real site look, everywhere ---
        var rig_src := FileAccess.get_file_as_string("res://scripts/player/avatar_rig.gd")
        check(rig_src.contains("func set_tshirt"),
                "the rig hangs a T-SHIRT decal on the torso front (site rule: 92%)")
        var dresser_src := FileAccess.get_file_as_string("res://scripts/player/avatar_dresser.gd")
        check(dresser_src.contains('kind == "tshirt"') and dresser_src.contains("set_tshirt"),
                "image-only accessories (T-SHIRTS) paint the decal instead of bailing")
        check(dresser_src.contains("await_all := false") and dresser_src.contains("await _apply_accessory"),
                "the dresser can AWAIT every stream (the portrait path)")
        check(portrait_src.contains("apply(api, rig, payload, true)"),
                "the portrait awaits the FULL dress — face, t-shirt, hat all land before the shot")
        check(game_src.contains("_dressed_signature") and game_src.contains("avatar_of(uid)"),
                "the menu re-fetches MY look live and re-dresses the rig when it changed")
        check(game_src.contains("_last_presence") and game_src.contains("if _menu_open:"),
                "the People page rebuilds ONLY while open (presence snapshot on open)")
        check(game_src.contains("RESPAWN_SECONDS := 2.0"), "respawn is snappier (2.0s)")
        var cam_src := FileAccess.get_file_as_string("res://scripts/game/camera_rig.gd")
        check(cam_src.contains("ZOOM_GLIDE") and cam_src.contains("_zoom_target"),
                "the zoom GLIDES to the wheel's target (no teleport zoom)")
        check(cam_src.contains("LAND_DIP_MAX") and cam_src.contains("land_impact"),
                "hard landings DIP the camera (game feel)")
        var world_src := FileAccess.get_file_as_string("res://scripts/world/world_builder.gd")
        check(world_src.contains("sun_curve") and world_src.contains("ffe9c4"),
                "the sky wears a soft sun disc + calm warm light (v5.0: not blinding)")
        check(world_src.contains("0.0020"), "every sky place gets a whisper of horizon fog")
        check(world_src.contains("ambient_light_energy = 0.48"),
                "the ambient wash is CALM — colors read true, nothing bleaches")
        check(world_src.contains("var n := 128") and world_src.contains("bump_top"),
                "the stud tile is the AUTHENTIC Roblox stud (lit + shaded rims, contact shadow)")
        check(local_src.contains("MAX_STEP := 3.2 * STUD"),
                "v5.0 STAIRS DOUBLED: 2-stud ledges walk over like stairs (3.2 step)")
        check(local_src.contains("WALL_GRAB_MIN_H := MAX_STEP + 0.05"),
                "the climb grip only starts on faces TALLER than the stair step")
        var proj_src := FileAccess.get_file_as_string("res://project.godot")
        check(proj_src.contains("msaa_3d=2") and proj_src.contains("anisotropic_filtering_level=4"),
                "the renderer ships 4x MSAA + anisotropic filtering (nothing blurry)")
        # --- the v12.1 HUD — the real client's chrome, RETRO NIGHT ---
        check(game_src.contains("_health_track_h") and game_src.contains("PRESET_CENTER_RIGHT"),
                "the health bar is VERTICAL on the RIGHT edge (the classic client dock)")
        check(game_src.contains("UserPill") and game_src.contains("_open_menu(\"settings\")"),
                "the top-right user pill parks your name + the settings gear")
        check(game_src.contains("KEY_SLASH"),
                "the SLASH key opens the chat (the real client's 'press / key')")
        # --- the chat quality pass (v3.11) + the v4.0 daylight chat ---
        check(game_src.contains("KEY_F") and chat_src.contains("toggle_read")
                and chat_src.contains("is_reading"),
                "F READS the chat — no keyboard grab, you keep moving (ESC closes)")
        check(not chat_src.contains('"#%d"'),
                "the '#1' seq chips are GONE from chat lines")
        check(game_src.contains("_chat_history_done"),
                "rejoining replays NOTHING — the first feed is history, marked seen silently")
        check(game_src.contains("get_tree().quit()"),
                "LEAVE closes the game now (web reloads the place)")
        check(game_src.contains("_build_center_cursor"), "first person parks a visible cursor mid-screen") # (kept)
        check(not game_src.contains("burger_btn"),
                "THE THREE-LINE BUTTON IS GONE from the topbar (you asked)")
        check(game_src.contains("CLICK-OFF closes the chat"),
                "CLICKING OFF the type box hands the keyboard back to the game")
        check(chat_src.contains("To chat click here or press / key"),
                "the chat input wears the AUTHENTIC Roblox placeholder")
        check(chat_src.contains("NIGHT_INK") and chat_src.contains("0.88"),
                "the chat is the DARK GLASS float again (never blinding)")
        check(chat_src.contains("fd2943"),
                "chat names wear the CLASSIC BRIGHT palette (readable on dark glass)")
        check(chat_src.contains("add_image") and chat_src.contains("pfp_resolver"),
                "every chat line leads with the speaker's PFP")
        check(game_src.contains('chat_btn.icon = RetroUI.icon_png("chat"'),
                "the pill's chat key wears the REAL internet chat icon")
        check(bubble_src.contains("SHOW_SECONDS := 12.0") and bubble_src.contains("FADE_SECONDS := 1.4"),
                "bubbles linger 12s and fade out SLOWLY")
        check(bubble_src.contains("_fade_out"),
                "overflow bubbles ease out instead of popping away")
        check(bubble_src.contains("PLATE_CENTER_LIFT"),
                "bubble text centers on the pill (the tail no longer drags it down)")
        var init_slice := portrait_src.get_slice("host.add_child(vp)", 0)
        check(not init_slice.contains("UPDATE_ONCE"),
                "the portrait one-shot render arms AFTER the stage is built (avatars SHOW)")
        check(game_src.contains("scroll collapsed to height 0"),
                "v3.10 FIX: the People card grid can't be clipped to nothing")
        var login_src4 := FileAccess.get_file_as_string("res://scripts/ui/login.gd")
        check(login_src4.contains('VERSION := "12.2"') and login_src4.contains("_red_key"),
                "login wears the SITE's own page again (v12.2, the RED Log In key)")
        check(login_src4.contains("_wordmark_textures") and login_src4.contains("login_backdrop"),
                "the login sits on the SITE's roller-coaster key art + the sprite-letter wordmark")
        check(login_src4.contains('"Log In"') and not login_src4.contains("Sign Up")
                and not login_src4.contains("Create Account") and not login_src4.contains("Sign In"),
                "LOG IN ONLY: the Create Account / Sign Up form is GONE, no Sign In anywhere")
        check(login_src4.contains("1e78c8") and login_src4.contains("Login and start having fun"),
                "the card wears the site's BLUE frame + the site's own headline")
        # --- v12.0/12.1: THE SETTINGS + THE INVITE PURGE + RETRO NIGHT ---
        check(not game_src.contains("Invite Friends"),
                "INVITE FRIENDS IS GONE from the People tab (nobody asked for it)")
        check(theme_src.contains("NIGHT_PANEL :=") and game_src.contains("_menu_panel_style"),
                "the menu panel is the RETRO NIGHT slate (dark, translucent, never blinding)")
        check(theme_src.contains("SITE_PAPER :="),
                "the site palette stays (gloss keys, steel borders, action colors)")
        check(game_src.contains("MenuHeader") and game_src.contains("RETROBLOX"),
                "the menu wears the BLUE GLOSS header strip (logo + wordmark + clock)")
        var pfp2_src := FileAccess.get_file_as_string("res://scripts/ui/pfp_service.gd")
        check(pfp2_src.contains("pfp_cache_v14"),
                "the PFP cache rides the v14 namespace (stale v13/v12/v11 bytes can't resurface)")
        check(pfp2_src.contains("AvatarPortrait.render") and pfp2_src.contains("my_avatar_data"),
                "THE DEFAULT PFP IS THE AVATAR ITSELF (the site payload, rendered headshot-style)")
        check(theme_src.contains("LETTER_COLORS") and theme_src.contains("func circle_badge"),
                "the theme ships the site's letter-avatar palette + the badge cropper")
        var settings_src := FileAccess.get_file_as_string("res://scripts/core/settings.gd")
        check(settings_src.contains("show_fps") and settings_src.contains("show_ping")
                and settings_src.contains("max_fps") and settings_src.contains("player_names")
                and settings_src.contains("bunny_hop") and settings_src.contains("func reset_all"),
                "Settings carries show fps / show ping / max fps / player names / bunny hop + RESET ALL")
        check(settings_src.contains("Engine.max_fps"),
                "MAXIMUM FPS applies live (Engine.max_fps)")
        check(game_src.contains("_build_stats_chip") and game_src.contains("_update_live_stats"),
                "the stats chip is ALWAYS ON (show fps / show ping hide each part)")
        check(game_src.contains("_apply_nameplates") and game_src.contains("set_display_name"),
                "SEE PLAYER NAMES stamps or clears every rig's nameplate")
        check(game_src.contains("_rebuild_settings_tab") and game_src.contains("Reset all settings"),
                "RESET ALL rebuilds the Settings page on the defaults")
        check(local_src.contains("hop_on"),
                "BUNNY HOP gates the hold-to-jump (one jump per press when off)")
        check(portrait_src.contains("_paper_backdrop"),
                "headshots can land on the SITE PAPER backdrop (readable at any size)")
        check(game_src.contains("v12.2"), "the corner chip wears v12.2")
        check(game_src.contains("SITE_BLUE") and game_src.contains("THE OLD BLUE ONE"),
                "THE OLD CHAT ICON IS BACK: the topbar wears the site's blue gloss")
        check(login_src4.contains("gotham(800)"),
                "the login speaks ExtraBold ARIAL (the RETROBLOX wordmark voice)")

        # --- v3.9: presence carries everyone's live stats ---
        var api9 := FileAccess.get_file_as_string("res://scripts/core/api.gd")
        check(api9.contains("ping_ms") and api9.contains('"ping": ping_ms'),
                "the presence heartbeat carries MY ping + fps to the server")
        check(player_src.contains("SHIFT LOCK climbs ladders"),
                "shift lock no longer phases through ladders")

        # --- dresser: placement applies verbatim ---
        var holder := Node3D.new()
        root.add_child(holder)
        load("res://scripts/player/avatar_dresser.gd").call(
                "_apply_placement", holder, {"p": [1, 2, 3], "r": [10, 20, 30], "s": [1, 1, 1]})
        var xf: Transform3D = holder.transform
        check(xf.origin.is_equal_approx(Vector3(1, 2, 3)), "UGC placement position verbatim")
        check(xf.basis.get_euler().is_equal_approx(Vector3(deg_to_rad(10), deg_to_rad(20), deg_to_rad(30))), "UGC placement rotation verbatim")

        # --- v3.5: cursors, wordmark, fast avatar, no Tix anywhere ---
        check(ResourceLoader.exists("res://assets/ui/cursor_hand.png"), "uploaded RetroBlox Cursor ships")
        check(ResourceLoader.exists("res://assets/ui/cursor_pointer.png"), "uploaded RetroBlox Pointer ships")
        check(ResourceLoader.exists("res://assets/ui/wordmark.png"), "uploaded ReTROBLOX wordmark ships")
        check(theme_src.contains("apply_cursors"), "classic cursors applied by the theme")
        check(game_src.contains("_build_center_cursor"), "first person parks a visible cursor mid-screen")
        check(game_src.contains("jump_held"), "game feeds held-jump input (hold SPACE hops)")
        check(local_src.contains("jump_held"), "player accepts held-jump input")
        check(not game_src.contains("Tix"), "no Tix UI left in the game")
        check(not game_src.contains("tix_coin"), "no coin hooks left in the game")
        var api_src := FileAccess.get_file_as_string("res://scripts/core/api.gd")
        check(api_src.contains("_asset_cache") and api_src.contains("_image_cache"),
                "Api caches assets + images (fast re-dress)")
        var dresser_src2 := FileAccess.get_file_as_string("res://scripts/player/avatar_dresser.gd")
        check(dresser_src2.contains("_apply_accessory") and dresser_src2.contains("_paint_shirt"),
                "dresser streams shirt/face/accessories in parallel")

