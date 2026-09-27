extends SceneTree

## Headless smoke test for the RetroBlox Godot player.
## Run with:  godot --headless -s tests/smoke.gd  (from the project folder)

var failures: Array[String] = []
var _ran := false

func check(condition: bool, label: String) -> void:
        if condition:
                print("  ok    " + label)
        else:
                failures.append(label)
                printerr("  FAIL  " + label)

func _process(_delta: float) -> bool:
        if _ran:
                return false
        _ran = true
        # run now that the tree is live (matches real gameplay)
        _run_all()
        quit(1 if failures.size() > 0 else 0)
        return true

func _run_all() -> void:
        print("== RetroBlox smoke test ==")

        # --- every script loads (parses) ---
        for path in [
                "res://scripts/retroblox_api.gd", "res://scripts/avatar.gd",
                "res://scripts/avatar_platform.gd", "res://scripts/player.gd",
                "res://scripts/auth_screen.gd", "res://scripts/hud.gd",
                "res://scripts/arena.gd", "res://scripts/main.gd",
        ]:
                check(load(path) != null, "script loads: " + path)

        # --- avatar scene: real nodes, working API ---
        var avatar_scene: PackedScene = load("res://scenes/avatar.tscn")
        check(avatar_scene != null, "scene loads: scenes/avatar.tscn")
        var avatar = avatar_scene.instantiate()
        check(avatar.get_node_or_null("HeadPivot") != null, "avatar scene has HeadPivot node")
        check(avatar.get_node_or_null("Nameplate") != null, "avatar scene has Nameplate node")
        root.add_child(avatar)
        avatar.configure(0, "Tester")
        check(avatar.parts.size() == 6, "avatar exposes 6 parts")
        check(avatar._part_sizes.size() == 6, "avatar collected 6 part sizes")
        if avatar.is_r6ik():
                var head_size: Vector3 = avatar._part_sizes[0]
                check(head_size.x > 0.9 and head_size.x < 1.4, "R6IK head normalized to classic scale (~1.2 studs wide)")
                check(avatar.get_node_or_null("R6IKModel") != null, "R6IK model mounted")
                check(avatar.get_node("HeadPivot").visible == false, "box fallback hidden in R6IK mode")
        else:
                check(avatar._part_sizes[0] == Vector3(0.95, 0.9, 0.85), "head size comes from the scene mesh")
        avatar.set_part_color(avatar.HEAD, Color("f5cd30"))
        avatar.set_display_name("SmokeTester")
        check(avatar._nameplate.text == "SmokeTester", "nameplate text updates")
        var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
        avatar.set_part_textured(avatar.TORSO, avatar.parts[1].mesh, tex)
        avatar.set_face(tex, 1.0)
        avatar.animate(0.016, 4.0, true)
        avatar.animate(0.016, 0.0, false)
        check(true, "avatar set_part_textured/set_face/animate ran")

        # --- player scene: capsule + avatar + bubble wired ---
        var player_scene: PackedScene = load("res://scenes/player.tscn")
        check(player_scene != null, "scene loads: scenes/player.tscn")
        var player = player_scene.instantiate()
        check(player.get_node_or_null("Avatar") != null, "player scene has Avatar instance")
        check(player.get_node_or_null("ChatBubble") != null, "player scene has ChatBubble node")
        check(player.get_node_or_null("Collision") != null, "player scene has Collision node")
        root.add_child(player)
        player.initialize(1, "SmokeTester")
        check(player.avatar != null and player.avatar.parts.size() == 6, "player.initialize wired the avatar")
        check(player.bubble != null, "player.initialize wired the chat bubble")
        check(player.name == "Player_1", "player named from peer id")
        check(is_equal_approx(player.collision_layer, 4), "player collision layer set")

        # --- auth + hud scenes: widgets present ---
        var auth_scene: PackedScene = load("res://scenes/auth_screen.tscn")
        var auth = auth_scene.instantiate()
        root.add_child(auth)
        check(auth.get_node_or_null("%SubmitBtn") != null, "auth scene has SubmitBtn")
        check(auth.get_node_or_null("%ServerEdit") != null, "auth scene has ServerEdit")
        auth.set_api_url("http://localhost:3000")
        check(auth._server_edit.text == "http://localhost:3000", "auth set_api_url works")
        auth._set_mode(true)
        check(auth._submit_btn.text == "Create Account", "auth signup mode toggles")
        auth.queue_free()

        var hud_scene: PackedScene = load("res://scenes/hud.tscn")
        var hud = hud_scene.instantiate()
        root.add_child(hud)
        check(hud.get_node_or_null("%ChatLog") != null, "hud scene has ChatLog")
        check(hud.get_node_or_null("%Menu") != null, "hud scene has Menu")
        check(hud.get_node_or_null("%ChatButton") != null, "hud scene has ChatButton")
        check(hud.get_node_or_null("%PeopleButton") != null, "hud scene has PeopleButton")
        check(hud.chat_panel.visible == false, "chat panel starts hidden")
        check(hud.roster_panel.visible == false, "roster panel starts hidden")
        hud.add_chat("Ann", "hello")
        check(hud.chat_log.text.contains("Ann: hello"), "hud add_chat renders")
        check(hud.chat_button.text == "1", "unread badge counts hidden chat")
        hud.toggle_chat(true)
        check(hud.chat_panel.visible and hud.chat_open, "chat button opens the panel")
        check(hud.chat_button.text == "", "opening chat clears the badge (icon-only button)")
        hud.toggle_chat(false)
        check(not hud.chat_panel.visible and not hud.chat_open, "chat button closes the panel")
        hud.toggle_people(true)
        check(hud.roster_panel.visible, "people button shows the roster")
        hud.update_roster([{"id": 1, "name": "Ann"}], 1)
        check(hud.count_label.text == "1 player", "hud roster count updates")
        hud.set_menu(true)
        check(hud.menu.visible, "hud menu opens")
        hud.set_menu(false)
        hud.queue_free()

        # --- main scene: arena + camera rig are real nodes ---
        var main_scene: PackedScene = load("res://main.tscn")
        check(main_scene != null, "scene loads: main.tscn")
        var main = main_scene.instantiate()
        check(main.get_node_or_null("Arena") != null, "main scene has Arena node")
        check(main.get_node_or_null("Players") != null, "main scene has Players node")
        check(main.get_node_or_null("Debris") != null, "main scene has Debris node")
        var arm: SpringArm3D = main.get_node_or_null("CameraRig/SpringArm3D")
        check(arm != null, "main scene has CameraRig/SpringArm3D")
        var cam: Camera3D = main.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
        check(cam != null and cam.fov == 70.0, "camera node with fov 70")
        root.add_child(main)
        check(main.arena != null, "main @onready wired arena")
        check(main.spring_arm != null, "main @onready wired spring arm")
        # scene starts at the classic zoom; runtime eases toward camera_distance (14.5)
        check(main.spring_arm.spring_length > 13.0 and main.spring_arm.spring_length < 15.5, "spring arm length from scene (classic zoom ~14)")
        main.queue_free()

        # --- api class: pure logic paths ---
        var api = load("res://scripts/retroblox_api.gd").new("http://localhost:3000/")
        check(api.base_url == "http://localhost:3000", "api trims trailing slash")
        var png := Image.create(4, 4, false, Image.FORMAT_RGBA8)
        var png_bytes: PackedByteArray = png.save_png_to_buffer()
        var decoded: Image = api.image_from_bytes(png_bytes)
        check(decoded != null and decoded.get_width() == 4, "api.image_from_bytes decodes PNG")
        check(api.image_from_bytes(PackedByteArray([1, 2, 3])) == null, "api.image_from_bytes rejects tiny input")

        # --- avatar_platform static helpers still duck-typed ---
        var platform = load("res://scripts/avatar_platform.gd")
        check(platform.get("zone_box") != null, "avatar_platform exposes zone_box")
        var mesh: ArrayMesh = platform.zone_box(Vector3(1, 2, 1), Rect2(0, 0, 300, 190), 300, 190)
        check(mesh != null and mesh.get_surface_count() == 1, "zone_box builds a mesh")

        avatar.queue_free()
        player.queue_free()
        main.queue_free()

        if failures.is_empty():
                print("== SMOKE_OK all checks passed ==")
        else:
                printerr("== SMOKE_FAILED: %d failures ==" % failures.size())
