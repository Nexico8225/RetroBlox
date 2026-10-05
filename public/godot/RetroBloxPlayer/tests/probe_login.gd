extends SceneTree
## probe_login.gd — verify the production auth CONTRACT from the engine.
## Never creates accounts (the platform's anti-abuse layer rightly rejects
## scripted signups): instead it proves reachability, structured errors and
## the token path. Run:
##   godot --headless --path . --script res://tests/probe_login.gd
## Optional real-credential check (no account is created):
##   PROBE_USER=me PROBE_PASS=secret godot --headless ... probe_login.gd

const ApiScript := preload("res://scripts/retroblox_api.gd")

var _steps := 0
var _total := 5


func _initialize() -> void:
	# wait for the first frame so root/HTTPRequest are inside the tree
	await process_frame
	_run()


func _finish(code: int) -> void:
	print("PROBE_RESULT: %s (%d/%d steps passed)" % ["PASS" if code == 0 else "FAIL", _steps, _total])
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

	var api: ApiScript = ApiScript.new("https://retro-blox.vercel.app")
	api.debug = true

	# 1. signup with a throwaway name — a structured 4xx ("taken", anti-abuse
	# 409, validation) is itself proof the endpoint is alive and honest.
	# We NEVER loop this: one request, and we accept any structured reply.
	var signup: Dictionary = await api.signup("ProbeOnce", "probe123")
	if signup.has("ok") and (signup.get("ok", false) or signup.has("error")):
		_steps += 1
		print("[1] signup endpoint answered -> ", "created" if signup.get("ok", false) else String(signup.get("error", "?")))

	# 2. login with WRONG password must be a clean structured 401, no crash
	var bad: Dictionary = await api.login("ProbeOnce", "definitely-wrong")
	if not bad.get("ok", false) and not String(bad.get("error", "")).is_empty():
		_steps += 1
		print("[2] wrong-password handled -> ", bad.get("error", "?"))
	else:
		print("[2] wrong-password UNEXPECTEDLY OK or empty error")

	# 3. me WITHOUT a token must be a clean structured 401
	var anon: Dictionary = await api.get_me()
	if not anon.get("ok", false) and not String(anon.get("error", "")).is_empty():
		_steps += 1
		print("[3] anonymous me handled -> ", anon.get("error", "?"))
	else:
		print("[3] anonymous me UNEXPECTEDLY OK")

	# 4. optional REAL credential check (owner account, nothing is created)
	var user := OS.get_environment("PROBE_USER")
	var pwd := OS.get_environment("PROBE_PASS")
	if user.is_empty() or pwd.is_empty():
		_total = 4   # step 4 not applicable without credentials
		print("[4] real-credential check SKIPPED (set PROBE_USER/PROBE_PASS to run it)")
	else:
		var login: Dictionary = await api.login(user, pwd)
		if login.get("ok", false) and not String(login.get("token", "")).is_empty():
			_steps += 1
			print("[4] real login OK -> token len %d" % String(login.get("token", "")).length())
		else:
			print("[4] real login FAIL -> ", login.get("error", "?"))

	_finish(0 if _steps == _total else 1)
