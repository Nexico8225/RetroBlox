extends SceneTree

## Boot the REAL game scene as a guest in Cloud Kingdom and screenshot the
## real HUD (game.gd's _build_hud, not a replica) — now with the classic
## chat bubbles over both heads, a fake remote player, and the steel ESC menu.

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        session.current_place = load("res://scripts/world/places.gd").by_id("cloudkingdom")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        # let it build HUD + settle physics
        for i in range(30):
                await physics_frame
        var hud: CanvasLayer = game.get("hud")
        print("HUD: ", hud != null, " children=", hud.get_child_count() if hud != null else 0)

        # a fake friend joins (exercises the presence reconcile path)
        var me: Node3D = game.get("player")
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        for i in range(10):
                await process_frame

        # classic bubbles over BOTH heads
        me.call("show_bubble", "hi! this bubble is so classic")
        var remotes: Dictionary = game.get("_remotes")
        if remotes.has("smokefriend"):
                remotes["smokefriend"].call("show_bubble", "welcome to cloud kingdom!!")
        print("BUBBLES: me=", me.get("bubble").get("_sprite").visible,
                " remote=", remotes.has("smokefriend"))
        print("MOUSE MODE: ", Input.get_mouse_mode(), " (0=visible 2=captured)")
        for i in range(4):
                await process_frame
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/real_game_hud.png")

        # open the menu (settings tab) and shoot it too — steel card + pixel title
        game.call("_open_menu", "settings")
        for i in range(5):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/real_game_settings.png")
        print("REAL_GAME_SHOTS_OK")
        quit(0)
