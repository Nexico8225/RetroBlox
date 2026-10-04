extends SceneTree

## Touch controls validation — run with:
##   godot --headless --path . --script res://tests/validate_touch.gd
##
## Checks the HUD touch layer: joystick tracking math, vector convention
## (y<0 = forward, matching Input.get_vector), jump/reset wiring, and the
## camera-drag reservation logic. Pure HUD-level; no network.

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
        var hud_scene: PackedScene = load("res://scenes/hud.tscn")
        var hud = hud_scene.instantiate()
        root.add_child(hud)
        await process_frame

        # ---- layer + nodes exist
        check("touch layer hidden by default", hud._touch_layer.visible == false)
        hud.set_touch_enabled(true)
        check("touch layer shows", hud._touch_layer.visible == true)
        check("joystick exists", hud._joystick != null)
        check("jump button exists", hud._jump_btn != null)
        check("reset button exists", hud._touch_reset_btn != null)
        check("shiftlock button exists", hud._touch_shift_btn != null)

        # ---- joystick tracking (read the joystick's own vector — the HUD
        # syncs it to hud.joystick_vector once per frame)
        var joy = hud._joystick as Control
        var center: Vector2 = joy.size * 0.5
        joy._track(center + Vector2(0, -40))   # push up = forward
        check("joystick forward is y<0", joy.vector.y < -0.5, str(joy.vector))
        check("joystick x stays zero", is_zero_approx(joy.vector.x))
        joy._track(center + Vector2(44, 0))    # full right
        check("joystick right is x>0", joy.vector.x > 0.9, str(joy.vector))
        check("joystick clamps to radius", joy.vector.length() <= 1.001)
        joy._track(center + Vector2(0, 400))   # way outside clamps to max
        check("joystick clamps overshoot", is_equal_approx(joy.vector.length(), 1.0))
        joy._center_knob()
        check("joystick release recenters", joy.vector == Vector2.ZERO)
        await process_frame
        check("hud syncs joystick vector each frame", hud.joystick_vector == Vector2.ZERO)

        # ---- jump button emits the signal
        var jumps: Array[int] = []
        hud.jump_pressed.connect(func(): jumps.append(1))
        hud._jump_btn.button_down.emit()
        check("jump button emits jump_pressed", jumps.size() == 1)

        # ---- reservation: camera must not steal UI touches
        var joy_rect: Rect2 = joy.get_global_rect()
        var center_point: Vector2 = joy_rect.get_center()
        check("joystick center reserved", hud.is_point_reserved(center_point))
        var jump_rect: Rect2 = hud._jump_btn.get_global_rect()
        check("jump button reserved", hud.is_point_reserved(jump_rect.get_center()))
        check("free space not reserved", not hud.is_point_reserved(Vector2(200, 200)) or hud.chat_panel.visible)

        # hidden layer's controls no longer reserve
        hud.set_touch_enabled(false)
        check("hidden joystick not reserved", not hud.is_point_reserved(center_point))

        print("%d passed, %d failed" % [passed, failed])
        quit(1 if failed > 0 else 0)
