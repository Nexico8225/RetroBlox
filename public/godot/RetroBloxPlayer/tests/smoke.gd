extends SceneTree
# Headless smoke test for the RetroBlox SDK.

var failures: Array[String] = []


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok    " + label)
	else:
		failures.append(label)
		printerr("  FAIL  " + label)


func _initialize() -> void:
	await process_frame
	await _run_all()
	if failures.is_empty():
		printerr("== SMOKE_OK all checks passed ==")
	else:
		printerr("== SMOKE_FAILED: %d failures ==" % failures.size())
	quit(1 if failures.size() > 0 else 0)


func _run_all() -> void:
	print("== RetroBlox smoke test ==")

	for path in [
		"res://scripts/HOW_TO_EDIT.gd",
		"res://scripts/core/api.gd", "res://scripts/core/session.gd",
		"res://scripts/core/settings.gd", "res://scripts/core/sfx.gd",
		"res://scripts/core/voice_chat.gd",
		"res://scripts/game/game.gd", "res://scripts/game/camera_rig.gd",
		"res://scripts/game/chat_box.gd",
		"res://scripts/player/local_player.gd", "res://scripts/player/remote_player.gd",
		"res://scripts/player/chat_bubble.gd",
		"res://scripts/player/avatar_rig.gd", "res://scripts/player/avatar_dresser.gd",
		"res://scripts/world/world_builder.gd", "res://scripts/world/places.gd",
		"res://scripts/ui/login.gd",
		"res://scripts/ui/retro_theme.gd",
		"res://scripts/ui/ui_studio.gd",
		"res://scripts/ui/avatar_portrait.gd",
		"res://scripts/ui/avatar_viewer.gd",
	]:
		var s: Script = load(path)
		check(s != null and s.can_instantiate(), "script loads: " + path)

	var settings: Node = root.get_node("/root/Settings")
	settings.set_key("master_volume", 0.5)
	check(is_equal_approx(float(settings.get("master_volume")), 0.5), "settings master_volume set")
	settings.set_key("graphics_quality", 3)
	check(int(settings.get("graphics_quality")) == 3, "settings graphics_quality set")
	settings.set_key("light_taps", true)
	check(bool(settings.get("light_taps")), "settings light_taps set")
	settings.set_key("ladder_auto_rotate", true)
	check(bool(settings.get("ladder_auto_rotate")), "settings ladder_auto_rotate set")
	settings.set_key("ladder_auto_rotate", false)
	settings.set_key("master_volume", 1.0)
	check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
	check(AudioServer.get_bus_index("Voice") >= 0, "Voice bus exists")

	var vc: Node = root.get_node_or_null("/root/VoiceChat")
	check(vc != null, "VoiceChat autoload exists")

	var login_packed: PackedScene = load("res://scenes/login.tscn")
	var login_inst := login_packed.instantiate()
	check(login_inst.get_node_or_null("CenterContainer/MainColumn/LoginCard") != null, "login.tscn has editable LoginCard node")
	login_inst.free()

	var world_packed: PackedScene = load("res://scenes/game.tscn")
	var world_inst := world_packed.instantiate()
	check(world_inst.get_node_or_null("Baseplate") != null, "game.tscn has editable 3D Baseplate node")
	world_inst.free()

	var rbx_packed: PackedScene = load("res://scenes/retroblox.tscn")
	var rbx_inst := rbx_packed.instantiate()
	check(rbx_inst.get_node_or_null("World/Baseplate") != null, "retroblox.tscn instances World/Baseplate")
	check(rbx_inst.get_node_or_null("HUD/Topbar") != null, "retroblox.tscn has editable 2D HUD/Topbar node")
	rbx_inst.free()
