extends SceneTree

## v6.0 shot — boot the REAL game as a guest and screenshot the BLOX
## client: the People page (portrait MUST render at 320x448, fully dressed,
## header mini-avatar in place), the settings page, the HUD (topbar pills +
## bottom-center health bar + bubble), and the login card. Then the stairs
## verdict: walk the REAL Happy Baseplate fort — four 2-stud risers —
## straight up, no jumping, no climbing grip, like stairs.

const PLACES := preload("res://scripts/world/places.gd")

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        session.current_place = PLACES.by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        if me == null:
                print("V600_SHOTS_FAIL no player")
                quit(1)
                return
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        me.call("show_bubble", "hi")
        for i in range(10):
                await process_frame
        # ---- the blox menu, People page ----
        game.call("_open_menu", "players")
        for i in range(14):
                await process_frame
        var cache: Dictionary = game.get("_portrait_cache")
        var mine = cache.get(session.user_id, null)
        if mine != null:
                print("PORTRAIT_RENDERED %dx%d" % [(mine as Texture2D).get_width(), (mine as Texture2D).get_height()])
        else:
                print("PORTRAIT_MISSING")
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v600_menu_people.png")
        # settings page
        game.call("_open_menu", "settings")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v600_menu_settings.png")
        # HUD + bubble
        game.call("_toggle_menu")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v600_hud.png")

        # ---- THE STAIRS VERDICT: the real fort risers, straight up ----
        # game._physics_process drives from Input; park it and drive the same
        # call the game makes, so the REAL world geometry is under test.
        game.set("_menu_open", true)
        # stand east of the fort, face -X at the first riser (face at x=-15)
        me.global_position = Vector3(-12.5, 0.05, 0.0)
        me.set("heading", PI / 2)
        var start_y: float = me.global_position.y
        var saw_climb := false
        for i in range(240):
                me.call("drive", 0.016, Vector2(0.0, -1.0), PI / 2, false, false)
                await physics_frame
                if bool(me.get("climbing")):
                        saw_climb = true
                var gy: float = (me.get("global_position") as Vector3).y
                if bool(me.get("grounded")) and gy > start_y + 1.5:
                        break
        var top_y: float = (me.get("global_position") as Vector3).y
        print("STAIRS_2STUD %s (y %.2f -> %.2f, climb_grip=%s)" % [
                "OK" if top_y > start_y + 1.5 else "FAIL", start_y, top_y, str(saw_climb)])
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v600_stairs.png")

        # ---- world beauty shot: pull back and show the studded fort ----
        game.set("_menu_open", false)
        var rig = game.get("camera_rig")
        if rig != null:
                me.global_position = Vector3(-14.0, 2.4, -6.0)
                me.set("heading", 0.0)
                for i in range(40):
                        me.call("drive", 0.016, Vector2(0.0, 0.0), 0.0, false, false)
                        await physics_frame
        for i in range(8):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v600_world.png")

        # ---- the blox login card ----
        var login: Node = load("res://scenes/login.tscn").instantiate()
        root.add_child(login)
        await process_frame
        await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v600_login.png")
        login.queue_free()
        print("V600_SHOTS_OK")
        quit(0)
