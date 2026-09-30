extends SceneTree
## probe_auth_flow.gd — OFFLINE verification of the sign-in -> in-game flow.
## Replaces the old probe_login.gd, which CREATED AN ACCOUNT on production
## (bot accounts are banned). This probe never sends a request: it drives
## main.gd's own login handler with a token-less api object and watches the
## world come up (LAN discovery -> auto-host -> spawn -> viewer moment).
## Run: godot --headless --path . --script res://tests/probe_auth_flow.gd

const MainScene := preload("res://main.tscn")

var _checks := 0
var _fails: Array[String] = []


func _initialize() -> void:
	await process_frame
	_run()


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_checks += 1
		print("[PASS] %s" % name)
	else:
		_fails.append(name)
		print("[FAIL] %s %s" % [name, detail])


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame

	var auth: CanvasLayer = main.auth
	_check("login card shown at boot", auth != null and auth.visible)
	_check("sign-up tab hidden (sign-in only)", not auth.get_node("%SignupTabBtn").visible)
	_check("guest button hidden (accounts only)", not auth.get_node("%GuestBtn").visible)
	_check("server url locked (read-only)", not auth.get_node("%ServerEdit").editable)
	_check("server url is the official site", String(auth.get_node("%ServerEdit").text).begins_with("https://retro-blox.vercel.app"))

	# Drive the REAL login-success path with a token-less api object —
	# user_id is empty so no avatar fetch (and no network) ever happens.
	var api = main.RetrobloxApiScript.new("https://retro-blox.vercel.app")
	main._finish_auth(api, "FlowProbe", "", {}, "")

	_check("login hides the card", auth != null and not auth.visible)

	# Discovery (~1.8-2.6s) then auto-host; allow 10s total.
	# Before the auth-card fix this never left the "starting" phase.
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if main.phase == "playing" and main.local_id != 0 and main.players.has(main.local_id):
			break
	_check("world playing after login", main.phase == "playing")
	_check("local player spawned", main.local_id != 0 and main.players.has(main.local_id))
	if main.local_id != 0 and main.players.has(main.local_id):
		var me = main.players[main.local_id]
		_check("player named after the account", me.display_name == "FlowProbe", me.display_name)
		_check("avatar alive and visible in world", me.alive and me.avatar.visible)
	_check("avatar-viewer moment on first spawn", main.viewer_mode)
	_check("hosting a local room (server_mode)", main.server_mode)

	print("PROBE_RESULT: %s (%d checks passed)" % ["PASS" if _fails.is_empty() else "FAIL", _checks])
	quit(0 if _fails.is_empty() else 1)
