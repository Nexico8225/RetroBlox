extends SceneTree

## v3.10 shot — boot the real game as a guest and screenshot the GLOSSY
## classic client: the People page with cards, then the footer's gloss keys.

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        session.current_place = load("res://scripts/world/places.gd").by_id("cloudkingdom")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        for i in range(10):
                await process_frame
        # open the menu on PEOPLE — gloss keys + plate window + cards
        game.call("_open_menu", "players")
        for i in range(8):
                await process_frame
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v310_menu_people.png")
        # settings page too
        game.call("_open_menu", "settings")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v310_menu_settings.png")
        # close the menu, shoot the topbar glass keys
        game.call("_toggle_menu")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v310_hud.png")
        print("V310_SHOTS_OK")
        quit(0)
