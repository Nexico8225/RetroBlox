extends RefCounted
class_name UiFx
## ==================================================================
##  UIFX — CLICK + HOVER EFFECTS for custom widgets (v6.0 "UI STUDIO")
## ==================================================================
##  A widget's "fx" dictionary names what happens when you HOVER and
##  when you CLICK it, plus how strong and how fast:
##      { "click": "punch" | "bounce" | "none",
##        "hover": "scalerot" | "glow" | "fade" | "none",
##        "power": 1.4,        # 0.5 .. 3 — how big the move reads
##        "speed": 2.0 }       # 0.5 .. 3 — how fast it plays
##
##  Every effect is a TWEEN on the widget itself — no extra nodes, no
##  polling; the widget snaps back to its true pose when the effect ends.
##  The WEB editor (/ui-studio) previews the same names with CSS, so what
##  you tune there is what plays here.

const HOVER_FX: Array = ["none", "scalerot", "glow", "fade"]
const CLICK_FX: Array = ["none", "punch", "bounce"]


static func clean() -> Dictionary:
        return {"click": "none", "hover": "none", "power": 1.4, "speed": 2.0}


## Wire a built widget up with its fx. `live` = in the real game (the
## editor previews pass false so dragging doesn't punch the widget).
static func apply(node: Control, fx_in: Dictionary, live: bool) -> void:
        var fx: Dictionary = clean()
        for k in ["click", "hover", "power", "speed"]:
                if fx_in.has(k):
                        fx[k] = fx_in[k]
        if not live:
                return
        var power: float = clampf(float(fx.get("power", 1.4)), 0.5, 3.0)
        var speed: float = clampf(float(fx.get("speed", 2.0)), 0.5, 3.0)
        var click := String(fx.get("click", "none"))
        var hover := String(fx.get("hover", "none"))
        node.pivot_offset = node.size / 2.0
        node.resized.connect(func() -> void: node.pivot_offset = node.size / 2.0)
        if click == "punch":
                node.gui_input.connect(func(ev: InputEvent) -> void:
                        if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
                                        and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                                _punch(node, power, speed))
        elif click == "bounce":
                node.gui_input.connect(func(ev: InputEvent) -> void:
                        if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
                                        and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                                _bounce(node, power, speed))
        if hover == "scalerot":
                node.mouse_entered.connect(func() -> void: _scalerot(node, power, speed, true))
                node.mouse_exited.connect(func() -> void: _scalerot(node, power, speed, false))
        elif hover == "glow":
                node.mouse_entered.connect(func() -> void: _glow(node, power, speed, true))
                node.mouse_exited.connect(func() -> void: _glow(node, power, speed, false))
        elif hover == "fade":
                node.mouse_entered.connect(func() -> void: _fade(node, power, speed, true))
                node.mouse_exited.connect(func() -> void: _fade(node, power, speed, false))


## CLICK: PUNCH — the widget jumps to the cursor: a quick pop-in that
## slams past 1.0 and settles, like the button got punched.
static func _punch(node: Control, power: float, speed: float) -> void:
        var tw := node.create_tween()
        var peak := 1.0 + 0.22 * power
        tw.tween_property(node, "scale", Vector2.ONE * peak, 0.07 / speed)
        tw.tween_property(node, "scale", Vector2(0.94, 0.94), 0.05 / speed)
        tw.tween_property(node, "scale", Vector2.ONE, 0.11 / speed)


## CLICK: BOUNCE — a squash-and-stretch hop on the spot.
static func _bounce(node: Control, power: float, speed: float) -> void:
        var tw := node.create_tween()
        var amp := 0.18 * power
        tw.tween_property(node, "scale", Vector2(1.0 + amp, 1.0 - amp * 0.6), 0.08 / speed)
        tw.tween_property(node, "scale", Vector2(1.0 - amp * 0.5, 1.0 + amp * 0.8), 0.09 / speed)
        tw.tween_property(node, "scale", Vector2.ONE, 0.10 / speed)


## HOVER: SCALE THEN ROTATE — smooth swell with a tiny confident tilt;
## releasing the mouse settles it back exactly straight.
static func _scalerot(node: Control, power: float, speed: float, on: bool) -> void:
        var tw := node.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        var dur := 0.16 / speed
        if on:
                tw.set_parallel(true)
                tw.tween_property(node, "scale", Vector2.ONE * (1.0 + 0.07 * power), dur)
                tw.tween_property(node, "rotation", deg_to_rad(2.2 * power), dur)
        else:
                tw.set_parallel(true)
                tw.tween_property(node, "scale", Vector2.ONE, dur)
                tw.tween_property(node, "rotation", 0.0, dur)


## HOVER: GLOW — the widget brightens like it caught light.
static func _glow(node: Control, power: float, speed: float, on: bool) -> void:
        var tw := node.create_tween()
        var target := Color(1.0 + 0.16 * power, 1.0 + 0.16 * power, 1.0 + 0.12 * power) if on else Color.WHITE
        tw.tween_property(node, "modulate", target, 0.14 / speed)


## HOVER: FADE — the widget steps back (quiets) until you come back.
static func _fade(node: Control, power: float, speed: float, on: bool) -> void:
        var tw := node.create_tween()
        var target := Color.WHITE if on else Color(1.0, 1.0, 1.0, clampf(1.0 - 0.22 * power, 0.3, 1.0))
        tw.tween_property(node, "modulate", target, 0.14 / speed)
