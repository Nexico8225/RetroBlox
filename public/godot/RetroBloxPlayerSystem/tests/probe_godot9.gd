extends SceneTree

## godot-player-9 probe — the new feel fixes:
##   1. animation speed_scale no longer leaks (idle/climb keep their own rate)
##   2. chat entry uses the light inner style in BOTH states (typed text visible)
##   3. sound slots load (Hover / Walking loop), missing slots are silent-safe
##   4. head-top health bar appears on damage, stays hidden at full health
##   5. HUD chat panel anchored TOP-LEFT
##   6. nameplate can be hidden for the local player

var _failures := 0


func _initialize() -> void:
        await process_frame
        await process_frame

        # ---- 1) R6IK animation rate control ----
        var player_scene: PackedScene = load("res://scenes/player.tscn")
        var player = player_scene.instantiate()
        root.add_child(player)
        player.initialize(1, "Probe")
        await process_frame
        var avatar = player.avatar
        check(avatar.is_r6ik(), "avatar upgraded to the R6IK rig")
        if avatar.is_r6ik():
                # walk hard, then stop: the idle must NOT inherit the walk rate
                for _i in range(40):
                        avatar.animate(1.0 / 60.0, 16.0, true, false)
                var ap: AnimationPlayer = avatar._anim_player
                check(ap.current_animation == "Old_Walk", "walking uses Old_Walk (got %s)" % ap.current_animation)
                var walk_rate: float = ap.speed_scale
                check(walk_rate > 0.74 and walk_rate < 1.26, "walk rate ~1.0 (got %.2f)" % walk_rate)
                for _i in range(40):
                        avatar.animate(1.0 / 60.0, 0.0, true, false)
                var idle_rate: float = ap.speed_scale
                check(ap.current_animation == "Old_Idle", "stopped uses Old_Idle (got %s)" % ap.current_animation)
                check(idle_rate < 0.99, "idle rate does NOT inherit walk speed (got %.2f)" % idle_rate)
                # climb keeps a sane rate too
                for _i in range(30):
                        avatar.animate(1.0 / 60.0, 9.0, false, true)
                check(ap.current_animation == "Climb", "climbing uses Climb (got %s)" % ap.current_animation)
                check(ap.speed_scale > 0.59 and ap.speed_scale < 1.41, "climb rate bounded (got %.2f)" % ap.speed_scale)
        else:
                fail("R6IK rig missing — anim probe skipped")

        # ---- 4) head-top health bar ----
        var hb: Node3D = player.get_node_or_null("HealthBillboard")
        check(hb != null, "health billboard exists")
        if hb != null:
                check(not hb.visible, "health bar hidden at full health")
                player.update_visuals(1.0 / 60.0)
                player.hurt(40.0)
                player.update_visuals(1.0 / 60.0)
                check(hb.visible, "health bar shows after damage")
        player.queue_free()
        await process_frame

        # ---- 2 + 5) HUD: chat entry style + top-left chat panel ----
        var hud_scene: PackedScene = load("res://scenes/hud.tscn")
        var hud = hud_scene.instantiate()
        root.add_child(hud)
        await process_frame
        var entry: LineEdit = hud.chat_entry
        var focus_style: StyleBoxFlat = entry.get_theme_stylebox("focus") as StyleBoxFlat
        check(focus_style != null and focus_style.bg_color.v > 0.6,
                "focused chat entry is LIGHT (typed text visible)")
        var caret: Color = entry.get_theme_color("caret")
        check(caret.v < 0.5, "chat caret is dark on the light entry")
        var panel: PanelContainer = hud.chat_panel
        check(panel.anchor_top == 0.0 and panel.offset_top > 0.0,
                "chat panel anchored TOP-LEFT (top=%.0f)" % panel.offset_top)
        check(panel.offset_top >= 50.0, "chat panel sits below the toolbar")
        # unread badge flow still behaves
        hud.add_chat("Probe", "hello world")
        check(int(hud._unread) >= 0, "add_chat safe when chat hidden")
        hud.queue_free()
        await process_frame

        # ---- 3) sounds ----
        var RetroSounds := load("res://scripts/sounds.gd")
        var hover: AudioStream = RetroSounds.stream("Hover")
        check(hover != null, "Hover sound slot loads")
        var walk_loop: AudioStream = RetroSounds.stream("Walking", true)
        check(walk_loop != null, "Walking sound slot loads")
        if walk_loop is AudioStreamWAV:
                check((walk_loop as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
                        "Walking loops for footsteps")
        var missing: AudioStream = RetroSounds.stream("NotASlot")
        check(missing == null, "missing slots return null safely (no crash)")

        # ---- 6) nameplate hide for the local player ----
        var avatar_scene: PackedScene = load("res://scenes/avatar.tscn")
        var av2 = avatar_scene.instantiate()
        root.add_child(av2)
        await process_frame
        av2.configure(2, "Friend")
        av2.set_nameplate_visible(false)
        var plate: Label3D = av2.get_node("%Nameplate")
        check(not plate.visible, "nameplate hides for the local player")
        av2.set_nameplate_visible(true)
        check(plate.visible, "nameplate shows again for others")
        check(plate.pixel_size >= 0.008 and plate.pixel_size < 0.02, "nameplate is READABLE (pixel_size %.4f)" % plate.pixel_size)
        av2.queue_free()

        await process_frame
        if _failures == 0:
                print("ALL GODOT-9 PROBES PASSED")
                quit(0)
        else:
                print("GODOT9_PROBE_FAILED: %d failures" % _failures)
                quit(1)


func check(ok: bool, label: String) -> void:
        if ok:
                print("  ok    " + label)
        else:
                _failures += 1
                print("  FAIL  " + label)


func fail(label: String) -> void:
        _failures += 1
        print("  FAIL  " + label)
