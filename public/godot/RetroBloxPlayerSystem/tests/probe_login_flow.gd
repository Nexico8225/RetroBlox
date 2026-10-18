extends SceneTree
## probe_login_flow.gd — the EXACT user-reported flow, end to end:
##   log in through the real auth card on the real main scene
##   -> the card MUST disappear (it used to say "Ready!" and stick forever,
##      freezing input/_process/_physics behind it)
##   -> the local player spawns wearing the ACCOUNT avatar incl. UGC hats
##      (not the noob look from the guest account).
## Phase A (setup_flow_probe.ts) created the account + equipped UGC hats.
## Run: godot --headless --path . --script res://tests/probe_login_flow.gd

var _steps := 0
var _creds := {}


func _initialize() -> void:
        await process_frame
        _run()


func _finish(code: int) -> void:
        print("PROBE_RESULT: %s (%d steps passed)" % ["PASS" if code == 0 else "FAIL", _steps])
        quit(code)


func _read_creds() -> bool:
        var f := FileAccess.open("/home/z/my-project/scripts/flow_probe_creds.json", FileAccess.READ)
        if f == null:
                print("[-] no creds file (run setup_flow_probe.ts first)")
                return false
        var parsed: Variant = JSON.parse_string(f.get_as_text())
        if parsed is Dictionary and parsed.has("username"):
                _creds = parsed
                return true
        return false


## Poll until the predicate holds or the timeout hits. Returns success.
func _until(what: String, seconds: float, predicate: Callable) -> bool:
        var left := seconds
        while left > 0.0:
                if predicate.call():
                        print("[+] %s (%.1fs)" % [what, seconds - left])
                        return true
                await create_timer(0.25).timeout
                left -= 0.25
        print("[-] TIMEOUT: %s" % what)
        return false


func _run() -> void:
        if not _read_creds():
                _finish(1)
                return
        print("[0] probe account: %s (expect %d UGC hats)" % [_creds.username, _creds.expectedUgc])

        # deterministic door: no saved token may auto-sign-in before we do
        DirAccess.remove_absolute("user://profile.cfg")

        var main_scene: PackedScene = load("res://main.tscn")
        var main = main_scene.instantiate()
        root.add_child(main)
        await process_frame
        await process_frame

        # 1. the door is up, baked-in website, no server box, login-only
        var auth = main.auth
        var card_ok: bool = auth != null \
                and auth.get_node_or_null("%ServerEdit") == null \
                and auth.get_node_or_null("%SignupTabBtn") == null \
                and auth.get_node_or_null("%UserEdit") != null \
                and auth.get_node_or_null("%PassEdit") != null \
                and String(auth._api_url) == "https://retro-blox.vercel.app"
        if card_ok:
                _steps += 1
                print("[1] card up: login-only, no server box, baked-in site URL")
        else:
                print("[-] card not as expected: auth=%s" % [auth != null])
                _finish(1)
                return

        # 2. empty submit must NOT fire completed or dismiss the card
        auth.get_node("%UserEdit").text = ""
        auth.get_node("%PassEdit").text = ""
        auth._submit()
        await process_frame
        if auth != null and auth.visible and String(auth._status.text).contains("Fill in"):
                _steps += 1
                print("[2] empty form stays put: \"%s\"" % auth._status.text)
        else:
                print("[-] empty form broke the card")
                _finish(1)
                return

        # 3. THE regression: real credentials -> card must leave the screen
        auth.get_node("%UserEdit").text = String(_creds.username)
        auth.get_node("%PassEdit").text = String(_creds.password)
        auth._submit()
        var gone: bool = await _until("card dismissed after login (the stuck-UI bug)", 25.0,
                func(): return main.auth == null)
        if not gone:
                if main.auth != null:
                        print("    card status now: \"%s\"" % String(main.auth._status.text))
                _finish(1)
                return
        _steps += 1

        # 4. main carried the login into the session state
        var me_ok: bool = main._auth_done \
                and main.api_ref != null \
                and String(main.platform_user_id) == String(_creds.userId) \
                and String(main.player_name) == String(_creds.username) \
                and main.my_avatar.has("accessories") \
                and int(main.my_avatar.accessories.size()) == int(_creds.expectedUgc)
        if me_ok:
                _steps += 1
                print("[4] session = %s, user %s, %d accessories in payload" % [main.player_name, main.platform_user_id, main.my_avatar.accessories.size()])
        else:
                print("[-] session state wrong: name=%s user=%s avatar=%s" % [main.player_name, main.platform_user_id, main.my_avatar.keys()])
                _finish(1)
                return

        # 5. the world actually starts: local player spawns (auto-host)
        var spawned: bool = await _until("local player spawned", 15.0,
                func(): return main.players.has(main.local_id))
        if not spawned:
                print("    phase=%s" % main.phase)
                _finish(1)
                return
        var p = main.players[main.local_id]
        if String(p.platform_user_id) == String(_creds.userId):
                _steps += 1
                print("[5] local player carries the platform user id")
        else:
                print("[-] local player user id=%s want=%s" % [p.platform_user_id, _creds.userId])
                _finish(1)
                return

        # 6. THE noob bug: UGC hats must actually be ON the avatar
        var ugc_names := func() -> Array:
                var out: Array = []
                for child in p.avatar.get_children():
                        if String(child.name).begins_with("UGCScaled_"):
                                out.append(String(child.name))
                return out
        var worn: bool = await _until("UGC hats applied to the avatar", 75.0,
                func(): return ugc_names.call().size() >= int(_creds.expectedUgc))
        var worn_list: Array = ugc_names.call()
        print("    worn UGC: %s" % ", ".join(worn_list))
        if worn:
                _steps += 1
                print("[6] avatar wears %d UGC items (not the noob look)" % worn_list.size())
        else:
                _finish(1)
                return

        _finish(0)
