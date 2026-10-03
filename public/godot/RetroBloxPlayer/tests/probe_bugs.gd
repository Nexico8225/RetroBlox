extends SceneTree

## probe_bugs.gd — reproduce the three reported bugs headless, no real
## accounts touched (guest flow + stubbed login via _finish_auth).
## Run: godot --headless --path . --script res://tests/probe_bugs.gd

var fails: Array[String] = []


func check(cond: bool, label: String) -> void:
        if cond:
                print("  ok    " + label)
        else:
                fails.append(label)
                printerr("  FAIL  " + label)


func _initialize() -> void:
        await process_frame
        _run()


func _run() -> void:
        print("== probe: three reported bugs ==")

        # ---------- BUG 3: guest flow ----------
        print("\n[guest] pressing Play as Guest…")
        var main_scene: PackedScene = load("res://main.tscn")
        var main = main_scene.instantiate()
        root.add_child(main)
        await process_frame
        await process_frame

        check(main.auth != null, "auth screen exists at boot")
        check(main.auth.visible, "auth screen visible at boot")

        # press the actual guest button signal path
        if main.auth != null:
                main.auth.guest_requested.emit()
        for i in range(60): # ~1s at 60fps headless
                await process_frame
        check(main.auth == null or not main.auth.visible, "guest: auth screen hidden after press")

        # guest goes discovery -> auto-host after ~2.6s; give it 5s
        for i in range(900):
                await process_frame
                if main.phase == "playing" and main.players.size() > 0:
                        break
        check(main.phase == "playing", "guest: phase reached playing (phase=%s)" % main.phase)
        var local = main.players.get(main.local_id)
        check(local != null, "guest: local player spawned (players=%d)" % main.players.size())
        if local != null:
                check(local.alive, "guest: local player alive")
                check(local.avatar != null and local.avatar.visible, "guest: avatar visible in world")

        # guest: HUD toolbar sanity (buttons must exist and be styled)
        var hud = main.hud
        check(hud != null, "guest: hud exists")
        if hud != null:
                var toolbar: Node = hud.root.get_node_or_null("Toolbar")
                check(toolbar != null, "guest: HUD toolbar built")
                if toolbar != null:
                        var row: Node = toolbar.get_node_or_null("Buttons")
                        check(row != null and row.get_child_count() == 3, "guest: toolbar has 3 buttons (has %d)" % (row.get_child_count() if row else 0))
                var chat_btn: Node = hud.root.get_node_or_null("Toolbar/Buttons/ChatButton")
                check(chat_btn != null, "guest: ChatButton reachable in toolbar")
                # classic style must have been applied (script error used to abort _ready)
                var chat_panel_style: StyleBox = hud.chat_panel.get_theme_stylebox("panel")
                check(chat_panel_style != null and chat_panel_style.bg_color == Color("d9dde0"),
                        "guest: classic style applied to chat panel (bg=%s)" % (chat_panel_style.bg_color if chat_panel_style else "null"))
                # menu must open/close without errors
                hud.set_menu(true)
                check(hud.menu.visible, "guest: ESC menu opens")
                hud.set_menu(false)
                check(not hud.menu.visible, "guest: ESC menu closes")
                hud.add_chat("Ann", "hi")
                check(hud.chat_log.text.contains("Ann: hi"), "guest: chat renders")

        main.queue_free()
        await process_frame
        await process_frame

        # ---------- BUG 2: login flow (stubbed, no real account) ----------
        print("\n[login] completing the login form (stubbed api)…")
        main = main_scene.instantiate()
        root.add_child(main)
        await process_frame
        await process_frame
        check(main.auth != null and main.auth.visible, "login: auth screen visible at boot")

        # simulate what auth_screen.gd does on a successful login:
        # it emits completed with a live RetrobloxApi. Use the real class with a
        # fake token — _finish_auth only stores it and saves the profile.
        var api = load("res://scripts/retroblox_api.gd").new("https://retro-blox.vercel.app")
        api.token = "stub-token-for-flow-test"
        main.auth.completed.emit(api, "FlowTester", "stub-user-id", {})
        await process_frame
        check(main.auth == null or not main.auth.visible,
                "login: auth screen hidden after completed signal")  # <-- currently FAILS (stuck at page)
        for i in range(900):
                await process_frame
                if main.phase == "playing" and main.players.size() > 0:
                        break
        check(main.phase == "playing", "login: phase reached playing (phase=%s)" % main.phase)
        local = main.players.get(main.local_id)
        check(local != null, "login: local player spawned (players=%d)" % main.players.size())

        print("")
        if fails.is_empty():
                print("== PROBE_OK all checks passed ==")
                quit(0)
        else:
                printerr("== PROBE_FAILED: %d failures ==" % fails.size())
                quit(1)
