extends SceneTree

## Settings + quality validation — run with:
##   godot --headless --path . --script res://tests/validate_settings.gd
##
## Boots the real main scene (login card up, game not joined), then checks
## that every quality preset lands the right renderer state and that the
## touch-mode resolution works. No server, no account, no network.

var passed: int = 0
var failed: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
        if ok:
                passed += 1
                print("PASS  ", name)
        else:
                failed += 1
                print("FAIL  ", name, "  ", detail)

func _initialize() -> void:
        var main_scene: PackedScene = load("res://main.tscn")
        var main = main_scene.instantiate()
        root.add_child(main)
        await process_frame
        await process_frame

        var vp: Viewport = root

        # ---- presets write the expected renderer state
        main.touch_active = false
        main.quality_preset = "low"
        main._apply_quality()
        check("low: draw scale 0.65", is_equal_approx(main.render_scale, 0.65))
        check("low: shadows off", main.shadows_on == false)
        check("low: sun shadow disabled", main.arena._sun.shadow_enabled == false)
        check("low: shadow distance 60", is_equal_approx(main.arena._sun.directional_shadow_max_distance, 60.0))
        check("low: viewport scaling applied", is_equal_approx(vp.scaling_3d_scale, 0.65))
        check("low: fps cap 60", Engine.max_fps == 60)

        main.quality_preset = "medium"
        main._apply_quality()
        check("medium: draw scale 0.85", is_equal_approx(main.render_scale, 0.85))
        check("medium: shadows on", main.shadows_on == true)
        check("medium: viewport scaling applied", is_equal_approx(vp.scaling_3d_scale, 0.85))
        check("medium: msaa off", vp.msaa_3d == Viewport.MSAA_DISABLED)

        main.quality_preset = "high"
        main._apply_quality()
        check("high: draw scale 1.0", is_equal_approx(main.render_scale, 1.0))
        check("high: full-res scale passthrough", is_equal_approx(vp.scaling_3d_scale, 1.0))
        check("high: msaa 2x", vp.msaa_3d == Viewport.MSAA_2X)
        check("high: no fps cap", Engine.max_fps == 0)
        check("high: fov applied to camera", is_equal_approx(main.camera.fov, main.fov_setting))

        # ---- custom keeps manual values
        main.quality_preset = "custom"
        main.render_scale = 0.5
        main.shadows_on = true
        main._apply_quality()
        check("custom: keeps draw scale", is_equal_approx(vp.scaling_3d_scale, 0.5))
        check("custom: bilinear scaling mode", vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR)
        check("custom: keeps shadows", main.arena._sun.shadow_enabled == true)
        check("custom: caps fps at sub-full scale", Engine.max_fps == 60)

        # ---- touch resolution
        main.touch_mode = "on"
        check("touch on: forced", main._resolve_touch() == true)
        main.touch_mode = "off"
        check("touch off: forced", main._resolve_touch() == false)
        main.touch_mode = "auto"
        # headless has no touchscreen — auto resolves false
        check("touch auto: none in headless", main._resolve_touch() == false)

        # ---- hud card reflects state + touch layer follows
        main.touch_mode = "on"
        main.touch_active = main._resolve_touch()
        main.hud.set_touch_enabled(main.touch_active)
        check("touch on: layer visible", main.hud._touch_layer.visible == true)
        main.touch_mode = "off"
        main.touch_active = main._resolve_touch()
        main.hud.set_touch_enabled(main.touch_active)
        check("touch off: layer hidden", main.hud._touch_layer.visible == false)

        # ---- settings card exists in the menu + fps counter
        check("menu has Settings… button", main.hud.get_node("%LeaveBtn").get_parent().get_node_or_null("SettingsButton") != null)
        main.hud.open_settings()
        check("settings card opens", main.hud.settings_open == true and main.hud._settings_panel.visible == true)
        main.hud.close_settings()
        check("settings card closes", main.hud.settings_open == false and main.hud._settings_panel.visible == false)
        main.hud.set_show_fps(true)
        check("fps counter shows", main.hud._fps_label.get_parent().visible == true)
        main.hud.set_show_fps(false)
        check("fps counter hides", main.hud._fps_label.get_parent().visible == false)

        main.free()
        print("%d passed, %d failed" % [passed, failed])
        quit(1 if failed > 0 else 0)
