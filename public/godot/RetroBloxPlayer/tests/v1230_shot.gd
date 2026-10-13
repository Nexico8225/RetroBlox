extends SceneTree

## v12.3 shot — SIMPLE WORKS: boot the real game and screenshot the SIMPLE
## login (flat sky + bold wordmark + clean card), then prove the SIMPLE ESC
## menu shows every player as their real full-body AVATAR + name, and prove
## SHIFT LOCK IS INSTANT (the body snaps to the camera yaw in one frame).

const PLACES := preload("res://scripts/world/places.gd")

const MY_UID := "cmts80l0k0000mkujqa50flhz"   # Nexico8225's RetroBlox account


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await process_frame
	var api: Node = root.get_node("/root/Api")
	var session: Node = root.get_node("/root/Session")

	# ---- sign in with the REAL site payload (the golden-helmet look) ----
	var me_payload: Dictionary = await api.call("avatar_of", MY_UID)
	if bool(me_payload.get("ok", false)):
		session.call("sign_in", me_payload, MY_UID, "Nexico8225", "user")
		print("SITE_PAYLOAD_OK")
	else:
		print("SITE_PAYLOAD_MISS (offline — shots still run)")

	# ---- the SIMPLE login: flat sky + bold text wordmark + clean card ----
	var login: Node = load("res://scenes/login.tscn").instantiate()
	root.add_child(login)
	for i in range(6):
		await process_frame
	var shot: Image = root.get_viewport().get_texture().get_image()
	shot.save_png("user://shots/v1230_login.png")
	login.queue_free()
	print("LOGIN_SHOT_OK")

	# ---- the game: the SIMPLE ESC menu — every player as avatar + name ----
	session.current_place = PLACES.by_id("baseplate")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for i in range(30):
		await physics_frame
	for i in range(20):
		await process_frame

	# ---- SHIFT LOCK IS INSTANT: one drive frame with a fresh camera yaw
	# and the body heading must EQUAL the camera yaw already ----
	var player: Node = game.get("player")
	if player != null:
		var cam_yaw := 2.1
		player.call("drive", 0.016, Vector2.ZERO, cam_yaw, false, true)
		var heading: float = player.get("heading")
		print("SHIFT_SNAP %s (heading=%.3f cam_yaw=%.3f)" % [
				"INSTANT_OK" if absf(heading - cam_yaw) < 0.001 else "STILL_EASING", heading, cam_yaw])

	# open the ESC menu on the People page and give the avatar renders a beat
	game.call("_toggle_menu")
	for i in range(90):
		await process_frame
	shot = root.get_viewport().get_texture().get_image()
	shot.save_png("user://shots/v1230_menu.png")
	# did the grid wear a REAL full-body render?
	var body_cache: Dictionary = game.get("_body_cache")
	var rendered := 0
	for uid in body_cache.keys():
		var tex: Texture2D = body_cache[uid]
		if tex != null and tex.get_height() > 300:
			rendered += 1
	print("MENU_AVATARS %d rendered (320x448) of cache %d" % [rendered, body_cache.size()])
	print("V1230_SHOTS_OK")
	quit(0)
