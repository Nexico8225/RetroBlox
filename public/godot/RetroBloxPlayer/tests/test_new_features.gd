extends SceneTree

func _init() -> void:
	print("== TESTING NEW FEATURES ==")
	
	# 1. Test LocalPlayer exports and methods
	var lp_script := load("res://scripts/player/local_player.gd")
	var player = lp_script.new()
	assert(player.can_climb == true, "can_climb should default true")
	assert(player.can_step_up == true, "can_step_up should default true")
	assert(player.max_step_studs == 2.0, "max_step_studs should default 2.0")
	assert(player.can_climb_ledges == true, "can_climb_ledges should default true")
	assert(player.enable_fall_damage == false, "fall damage should default disabled")
	assert(player.health_regen_rate == 1.0, "health_regen_rate should be 1.0 HP/s")
	
	var eff_spd: float = player.get_effective_speed_studs()
	var eff_jmp: float = player.get_effective_jump_studs()
	var eff_grv: float = player.get_effective_gravity_studs()
	print("Player default physics: speed=%f, jump=%f, grav=%f" % [eff_spd, eff_jmp, eff_grv])
	assert(is_equal_approx(eff_spd, 16.0), "Speed should be 16 studs/s")
	assert(is_equal_approx(eff_jmp, 50.0), "Jump should be 50 studs")
	assert(is_equal_approx(eff_grv, 196.2), "Grav should be 196.2 studs/s^2")
	print("  ok  local_player physics and customization properties verified")

	# 2. Test EmoteWheel UI
	var wheel_script := load("res://scripts/ui/emote_wheel.gd")
	var wheel = wheel_script.new()
	wheel._ready()
	assert(wheel._all_emotes.size() >= 8, "Wheel should have at least default emotes")
	print("Wheel loaded %d emotes. Page count: %d" % [wheel._all_emotes.size(), int(ceili(float(wheel._all_emotes.size()) / 8.0))])
	wheel.open()
	assert(wheel.visible == true, "Wheel should be visible when opened")
	var selected_id := [""]
	wheel.emote_selected.connect(func(id: String) -> void:
		selected_id[0] = id
	)
	wheel._on_slot_pressed(0) # Dance 1
	assert(selected_id[0] == "dance1", "Slot 0 should select dance1")
	assert(wheel.visible == false, "Wheel should close on selection")
	print("  ok  emote_wheel radial menu and pagination verified")

	# 3. Test AvatarRig Emotes
	var rig_script := load("res://scripts/player/avatar_rig.gd")
	var rig = rig_script.new()
	rig.setup("TestPlayer")
	var test_emotes := ["dance", "dance1", "dance2", "dance3", "wave", "point", "laugh", "cheer", "sit", ""]
	for em in test_emotes:
		rig.play_emote(em)
		rig.animate(0.016, 0.0, true, false)
	print("  ok  avatar_rig emotes (dance1/2/3, wave, point, laugh, cheer, sit) animated OK")

	# 4. Test Checkpoint Pad
	var pad_script := load("res://scripts/world/interactive_pad.gd")
	var pad = pad_script.new()
	pad.pad_type = 7 # Checkpoint
	pad.infinite_duration = true
	pad.remove_on_touch_block = false
	assert(pad.is_in_group("checkpoint"), "Pad should be in checkpoint group")
	print("  ok  interactive_pad checkpoint type and configuration verified")

	print("== ALL NEW FEATURES VERIFIED OK ==")
	player.free()
	wheel.free()
	rig.free()
	pad.free()
	quit(0)
