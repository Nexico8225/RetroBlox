extends SceneTree

## v12.1 shot — boot the REAL game and screenshot the RETRO NIGHT client:
## the dark slate ESC panel with the IDENTITY BLOCK (the full-body avatar
## render + the site PFP badge), the People page in TILES and in LIST view,
## the dark Settings page (with ACCOUNT Log Out — no EDIT THIS UI), the HUD
## (dark pills + the VERTICAL right-edge health bar), the chat with its
## always-visible type box, and the OLD login page. Plus: the site PFP
## fetch (letter avatar default), the bubble-fit check, the stairs verdict.

const PLACES := preload("res://scripts/world/places.gd")

const MY_UID := "cmts80l0k0000mkujqa50flhz"   # Nexico8225's RetroBlox account


func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var api: Node = root.get_node("/root/Api")
        var session: Node = root.get_node("/root/Session")
        # sign in as the REAL account — the avatar payload comes from the
        # live site, so the identity render + the in-world rig wear the real look
        var me_payload: Dictionary = await api.call("avatar_of", MY_UID)
        if bool(me_payload.get("ok", false)):
                session.call("sign_in", me_payload, MY_UID, "Nexico8225", "user")
                print("SITE_PAYLOAD_OK")
        else:
                session.call("set_guest")
                session.username = "Nexico8225"
                print("SITE_PAYLOAD_MISS (guest fallback)")
        session.current_place = PLACES.by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        if me == null:
                print("V1210_SHOTS_FAIL no player")
                quit(1)
                return
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        # the bubble-fit check: the exact overflow the screenshot showed
        me.call("show_bubble", "WWWWWWWW WWWWWWWW WWWWWWWW WWWWWWWW hello")
        for i in range(20):
                await process_frame
        var cache: Dictionary = game.get("_portrait_cache")
        var mine = cache.get(session.user_id, null)
        if mine != null:
                var t := mine as Texture2D
                print("PFP_READY %dx%d" % [t.get_width(), t.get_height()])
        else:
                print("PFP_MISSING")

        var shot: Image

        # ---- the centered ESC panel, People page (identity + tiles) ----
        game.call("_open_menu", "players")
        for i in range(20):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1210_menu_people_tiles.png")
        # the identity avatar render landed?
        var body: Dictionary = game.get("_body_cache")
        if body.has(session.user_id) and body[session.user_id] != null:
                var bt: Texture2D = body[session.user_id]
                print("IDENTITY_READY %dx%d" % [bt.get_width(), bt.get_height()])
        else:
                print("IDENTITY_PENDING")

        # ---- LIST view (the toggle rebuilds the roster) ----
        game.call("_set_people_view", "list")
        for i in range(8):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1210_menu_people_list.png")
        game.call("_set_people_view", "tiles")
        for i in range(4):
                await process_frame

        # settings page (MY PICTURE + ACCOUNT log out, dark)
        game.call("_open_menu", "settings")
        for i in range(8):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1210_menu_settings.png")

        # close menu — HUD with dark pills + the VERTICAL health bar right
        game.call("_toggle_menu")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1210_hud.png")

        # ---- the chat with the type box + a PFP line ----
        var chat_ctl: Control = game.get("chat")
        if chat_ctl != null:
                chat_ctl.call("open")
                chat_ctl.call("add_chat", "BubbleBob", 7, "this line wears my PFP!", "", false, "smokefriend")
                chat_ctl.call("add_chat", "Nexico8225", 8, "and mine has the site picture", "", true, session.user_id)
                for i in range(6):
                        await process_frame
                shot = root.get_viewport().get_texture().get_image()
                shot.save_png("user://shots/v1210_chat.png")
                chat_ctl.call("close")

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
        shot.save_png("user://shots/v1210_world.png")

        # ---- the login page ----
        var login: Node = load("res://scenes/login.tscn").instantiate()
        root.add_child(login)
        await process_frame
        await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1210_login.png")
        login.queue_free()
        print("V1210_SHOTS_OK")
        quit(0)
