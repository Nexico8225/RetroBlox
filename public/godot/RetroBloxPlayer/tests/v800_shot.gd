extends SceneTree

## v8.0 shot — boot the REAL game and screenshot the REAL CLIENT: the
## People page (cards must wear REAL PFP headshots — the bundled
## Nexico8225 headshot lands with ZERO network), the settings page, the
## HUD (topbar pills + user pill + bottom-center health bar), and the
## login page. Then the stairs verdict: walk the REAL Happy Baseplate
## fort — four 2-stud risers — straight up, no jumping, no climbing grip.

const PLACES := preload("res://scripts/world/places.gd")

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        # verify the PFP engine end-to-end: pretend the account name is the
        # shipped one — the BUNDLED headshot must land instantly, no network
        session.username = "Nexico8225"
        session.current_place = PLACES.by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        if me == null:
                print("V800_SHOTS_FAIL no player")
                quit(1)
                return
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        me.call("show_bubble", "hi")
        # the topbar already kicked my PFP fetch at build time — give it a beat
        for i in range(20):
                await process_frame
        var cache: Dictionary = game.get("_portrait_cache")
        var mine = cache.get(session.user_id, null)
        if mine != null:
                var t := mine as Texture2D
                print("PFP_READY %dx%d" % [t.get_width(), t.get_height()])
                var img := t.get_image()
                var px := img.get_pixel(int(t.get_width() / 2.0), int(t.get_height() * 0.28))
                print("PFP_FACE_PX %s" % px)   # the bacon-hair head is warm-toned
        else:
                print("PFP_MISSING")
        # ---- the client menu, People page ----
        game.call("_open_menu", "players")
        for i in range(14):
                await process_frame
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v800_menu_people.png")
        # settings page
        game.call("_open_menu", "settings")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v800_menu_settings.png")
        # HUD + bubble
        game.call("_toggle_menu")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v800_hud.png")

        # ---- THE STAIRS VERDICT: the real fort risers, straight up ----
        game.set("_menu_open", true)
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
        shot.save_png("user://shots/v800_stairs.png")

        # ---- world beauty shot ----
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
        shot.save_png("user://shots/v800_world.png")

        # ---- the login page ----
        var login: Node = load("res://scenes/login.tscn").instantiate()
        root.add_child(login)
        await process_frame
        await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v800_login.png")
        login.queue_free()
        print("V800_SHOTS_OK")
        quit(0)
