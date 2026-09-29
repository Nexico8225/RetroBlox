extends SceneTree
## probe_login.gd — reproduce the player's exact sign-in path against production.
## Run: godot --headless --path . --script res://tests/probe_login.gd

const ApiScript := preload("res://scripts/retroblox_api.gd")

var _steps := 0


func _initialize() -> void:
        # wait for the first frame so root/HTTPRequest are inside the tree
        await process_frame
        _run()


func _finish(code: int) -> void:
        print("PROBE_RESULT: %s (%d/5 steps passed)" % ["PASS" if code == 0 else "FAIL", _steps])
        quit(code)


func _run() -> void:
        # 0. raw HTTPRequest against the API — isolates TLS/DNS/engine issues
        var raw_ok := false
        var http := HTTPRequest.new()
        root.add_child(http)
        var err := http.request("https://retro-blox.vercel.app/api/platform/login",
                        PackedStringArray(["Content-Type: application/json"]),
                        HTTPClient.METHOD_POST,
                        JSON.stringify({"username": "raw_probe", "password": "x"}))
        if err == OK:
                var res: Array = await http.request_completed
                print("[0] raw engine HTTP -> result_code=%d status=%d body=%s" % [res[0], res[1], (res[3] as PackedByteArray).get_string_from_utf8().left(80)])
                raw_ok = res[0] == 0 and res[1] >= 200 and res[1] < 500
        else:
                print("[0] raw engine HTTP request() error: ", error_string(err))
        http.queue_free()
        if raw_ok:
                _steps += 1

        var api: RetrobloxApi = ApiScript.new("https://retro-blox.vercel.app")
        api.debug = true

        # 1. signup (fresh probe user each run)
        var user := "Probe%06d" % (randi() % 1000000)
        var signup: Dictionary = await api.signup(user, "probe123")
        if signup.get("ok", false):
                _steps += 1
                print("[1] signup OK -> %s (%s)" % [user, signup.get("userId", "?")])
        else:
                print("[1] signup FAIL -> ", signup.get("error", "?"))

        # 2. login with the fresh account
        var login: Dictionary = await api.login(user, "probe123")
        if login.get("ok", false) and not String(login.get("token", "")).is_empty():
                _steps += 1
                print("[2] login OK -> token len %d" % String(login.get("token", "")).length())
        else:
                print("[2] login FAIL -> ", login.get("error", "?"))

        # 3. login with WRONG password (must be a clean server message, no crash)
        var bad: Dictionary = await api.login(user, "definitely-wrong")
        if not bad.get("ok", false):
                _steps += 1
                print("[3] wrong-password handled -> ", bad.get("error", "?"))
        else:
                print("[3] wrong-password UNEXPECTEDLY OK")

        # 4. me with the token
        var me: Dictionary = await api.get_me()
        if me.get("ok", false) and me.has("avatar"):
                _steps += 1
                var av: Dictionary = me.get("avatar", {})
                print("[4] me OK -> %s avatar.body=%s" % [me.get("username", "?"), av.get("body", "?")])
        else:
                print("[4] me FAIL -> ", me.get("error", "?"))

        _finish(0 if _steps == 5 else 1)
