extends SceneTree

## THE LOGIN HANDOFF PROBE — guards the exact bug the owner kept hitting:
## log in, the card says "Ready!", and the game never takes over.
##
## Simulates a successful sign-in straight into the running game:
##   1. main.tscn boots to the auth card
##   2. auth_screen._submit-style completion fires (completed signal)
##   3. the card MUST leave the screen and the game MUST start
##   4. the watchdog rescues any path that completes but never starts
## Run with:
##   godot --headless --path . --script res://tests/probe_handoff.gd

var failures: Array = []


func _ok(condition: bool, label: String) -> void:
        if condition:
                print("ok: ", label)
        else:
                failures.append(label)
                print("FAIL: ", label)


func _initialize() -> void:
        await process_frame
        var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
        root.add_child(main)
        # let _ready run: auth card instantiates, saved-token probe starts
        for _i in range(6):
                await process_frame

        var auth: Node = main.get("auth")
        _ok(auth != null, "main boots to the login card")

        if auth != null:
                # ---- 1. the card is visible and the game is gated behind it
                _ok(auth.visible, "login card visible on boot")

                # ---- 2. simulate a successful login (local token, no network:
                #         get_me is NOT awaited inside _finish_auth)
                var api = preload("res://scripts/retroblox_api.gd").new("https://retro-blox.vercel.app")
                main._on_auth_completed(api, "HandoffProbe", "probe-user-id", {})

                await process_frame
                await process_frame

                # ---- 3. THE DOOR CLOSES: card freed, game takes over
                _ok(main.get("auth") == null,
                        "login card is dismissed right after sign-in")
                _ok(not main.get("_auth_done") == false, "auth marked done")
                _ok(String(main.get("player_name")) == "HandoffProbe",
                        "player takes the account username")

                # ---- 4. the game actually starts: auto-host path
                var deadline := Time.get_ticks_msec() + 8000
                while Time.get_ticks_msec() < deadline:
                        await process_frame
                        if String(main.get("phase")) == "playing" and main.get("local_id") != 0:
                                break
                _ok(String(main.get("phase")) == "playing", "game reaches the playing phase")
                _ok(main.get("local_id") != 0, "a local player exists")
                var players: Dictionary = main.get("players")
                var local = players.get(main.get("local_id"))
                _ok(local != null, "local player spawned in the world")
                if local != null:
                        _ok(local.avatar.visible, "avatar visible in third person")
                        _ok(local.avatar.get("parts") != null and local.avatar.parts.size() == 6,
                                "avatar rig wired")

                # ---- 5. the guest path also dismisses the card
                var auth2: Node = main.get("auth")
                _ok(auth2 == null, "no card can come back after auth")

        main.queue_free()
        await process_frame
        if failures.is_empty():
                print("HANDOFF PROBE OK")
                quit(0)
        else:
                for failure in failures:
                        print("FAIL: ", failure)
                quit(1)
