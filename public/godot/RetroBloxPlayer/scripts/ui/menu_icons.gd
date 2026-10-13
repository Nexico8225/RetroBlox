extends Control
## MenuIcons — ONE hand-drawn MONOCHROME glyph, drawn in code (draw_polyline /
## draw_arc / draw_rect) so no texture ever loads and every glyph is pure
## white-on-nothing ink. The ESC menu's icon rail + every settings row speaks
## through these — set `kind`, drop it in a fixed-size box, done.
## All glyphs live on a 24x24 design grid and scale to the control.

## The glyph vocabulary (what the menu needs, nothing more).
const KINDS: Array = [
        "person", "gear", "mouse", "lock", "camera", "speaker", "note", "sun",
        "monitor", "gauge", "expand", "sync", "layers", "chart", "signal",
        "tag", "bubble", "bounce", "reset", "exit", "sliders", "invert",
]

var kind := "gear"
var ink := Color.WHITE

var _u := 1.0  # design-grid unit (px)
var _w := 1.5  # stroke width (px)


func _draw() -> void:
        var s := minf(size.x, size.y)
        if s <= 0.0:
                return
        _u = s / 24.0
        _w = maxf(1.3, _u * 1.35)
        match kind:
                "person": _person()
                "gear": _gear()
                "mouse": _mouse()
                "lock": _lock()
                "camera": _camera()
                "speaker": _speaker()
                "note": _note()
                "sun": _sun()
                "monitor": _monitor()
                "gauge": _gauge()
                "expand": _expand()
                "sync": _sync()
                "layers": _layers()
                "chart": _chart()
                "signal": _signal()
                "tag": _tag()
                "bubble": _bubble()
                "bounce": _bounce()
                "reset": _reset()
                "exit": _exit()
                "sliders": _sliders()
                "invert": _invert()


# ---- the design grid helpers ---------------------------------------------

func _pt(x: float, y: float) -> Vector2:
        return Vector2(x, y) * _u


func _line(a: Vector2, b: Vector2) -> void:
        draw_line(_pt(a.x, a.y), _pt(b.x, b.y), ink, _w, true)


func _poly(points: Array, closed := false) -> void:
        var pts: PackedVector2Array = []
        for p: Vector2 in points:
                pts.append(_pt(p.x, p.y))
        if closed:
                pts.append(_pt(points[0].x, points[0].y))
        draw_polyline(pts, ink, _w, true)


func _circle(c: Vector2, r: float, fill := false) -> void:
        if fill:
                draw_circle(_pt(c.x, c.y), r * _u, ink)
        else:
                draw_arc(_pt(c.x, c.y), r * _u, 0.0, TAU, 40, ink, _w, true)


func _arc(c: Vector2, r: float, from: float, to: float) -> void:
        draw_arc(_pt(c.x, c.y), r * _u, from, to, 24, ink, _w, true)


func _rect(r: Rect2, fill := false) -> void:
        draw_rect(Rect2(_pt(r.position.x, r.position.y), Vector2(r.size.x, r.size.y) * _u),
                        ink, fill, _w, true)


func _fade_rect(r: Rect2, alpha: float) -> void:
        draw_rect(Rect2(_pt(r.position.x, r.position.y), Vector2(r.size.x, r.size.y) * _u),
                        Color(ink.r, ink.g, ink.b, alpha), true)


func _arrow_tip(tip: Vector2, from_dir: Vector2) -> void:
        _poly([tip + from_dir.rotated(0.5) * 2.8, tip, tip + from_dir.rotated(-0.5) * 2.8])


# ---- the glyphs (24x24 design space) --------------------------------------

func _person() -> void:
        _circle(Vector2(12, 7.2), 3.1)
        _arc(Vector2(12, 18.6), 6.4, PI + 0.45, TAU - 0.45)
        _line(Vector2(6.2, 18.4), Vector2(6.2, 19.6))
        _line(Vector2(17.8, 18.4), Vector2(17.8, 19.6))


func _gear() -> void:
        _circle(Vector2(12, 12), 3.0)
        _circle(Vector2(12, 12), 6.1)
        for i in range(8):
                var a := TAU * float(i) / 8.0
                var d := Vector2(cos(a), sin(a))
                _line(Vector2(12, 12) + d * 6.1, Vector2(12, 12) + d * 8.6)


func _mouse() -> void:
        _poly([Vector2(8.4, 4.2), Vector2(15.6, 4.2), Vector2(15.6, 13.0),
                Vector2(8.4, 13.0), Vector2(8.4, 4.2)])
        _line(Vector2(12, 4.2), Vector2(12, 8.6))
        _line(Vector2(12, 15.4), Vector2(12, 19.8))
        _line(Vector2(9.6, 17.6), Vector2(14.4, 17.6))


func _lock() -> void:
        _rect(Rect2(6.6, 11.0, 10.8, 8.2))
        _arc(Vector2(12, 11.0), 3.5, PI, TAU)
        _circle(Vector2(12, 15.1), 1.1, true)


func _camera() -> void:
        _circle(Vector2(12, 12), 7.2)
        _circle(Vector2(12, 12), 1.4, true)
        for a in [0.0, PI * 0.5, PI, PI * 1.5]:
                var d := Vector2(cos(a), sin(a))
                _line(Vector2(12, 12) + d * 5.2, Vector2(12, 12) + d * 7.2)


func _speaker() -> void:
        _poly([Vector2(4.6, 9.6), Vector2(8.6, 9.6), Vector2(13.2, 5.6),
                Vector2(13.2, 18.4), Vector2(8.6, 14.4), Vector2(4.6, 14.4),
                Vector2(4.6, 9.6)])
        _arc(Vector2(14.6, 12.0), 2.7, -0.85, 0.85)
        _arc(Vector2(14.6, 12.0), 5.2, -0.85, 0.85)


func _note() -> void:
        _circle(Vector2(8.8, 17.2), 2.1)
        _circle(Vector2(16.0, 15.6), 2.1)
        _line(Vector2(10.9, 17.2), Vector2(10.9, 6.8))
        _line(Vector2(18.1, 15.6), Vector2(18.1, 5.6))
        _line(Vector2(10.9, 6.8), Vector2(18.1, 5.6))


func _sun() -> void:
        _circle(Vector2(12, 12), 4.0)
        for i in range(8):
                var a := TAU * float(i) / 8.0
                var d := Vector2(cos(a), sin(a))
                _line(Vector2(12, 12) + d * 5.9, Vector2(12, 12) + d * 8.3)


func _monitor() -> void:
        _poly([Vector2(4.6, 5.4), Vector2(19.4, 5.4), Vector2(19.4, 15.2),
                Vector2(4.6, 15.2), Vector2(4.6, 5.4)])
        _line(Vector2(12, 15.2), Vector2(12, 18.6))
        _line(Vector2(8.2, 19.0), Vector2(15.8, 19.0))


func _gauge() -> void:
        _arc(Vector2(12, 13.6), 7.2, PI + 0.5, TAU - 0.5)
        _line(Vector2(12, 13.6), Vector2(16.2, 9.4))
        _circle(Vector2(12, 13.6), 1.2, true)


func _expand() -> void:
        _poly([Vector2(4.6, 9.0), Vector2(4.6, 4.6), Vector2(9.0, 4.6)])
        _poly([Vector2(15.0, 4.6), Vector2(19.4, 4.6), Vector2(19.4, 9.0)])
        _poly([Vector2(19.4, 15.0), Vector2(19.4, 19.4), Vector2(15.0, 19.4)])
        _poly([Vector2(9.0, 19.4), Vector2(4.6, 19.4), Vector2(4.6, 15.0)])


func _sync() -> void:
        _arc(Vector2(12, 12), 6.6, -2.35, 0.6)
        _arc(Vector2(12, 12), 6.6, 0.8, 3.75)
        _arrow_tip(Vector2(12 + 6.6 * cos(0.6), 12 + 6.6 * sin(0.6)), Vector2(-sin(0.6), cos(0.6)))
        _arrow_tip(Vector2(12 + 6.6 * cos(3.75), 12 + 6.6 * sin(3.75)), Vector2(-sin(3.75), cos(3.75)))


func _layers() -> void:
        # the OPACITY glyph: three bars at 100% / 55% / 25% — the setting itself
        _fade_rect(Rect2(4.6, 4.8, 14.8, 3.4), 1.0)
        _fade_rect(Rect2(4.6, 10.3, 14.8, 3.4), 0.55)
        _fade_rect(Rect2(4.6, 15.8, 14.8, 3.4), 0.25)


func _chart() -> void:
        _poly([Vector2(4.8, 4.2), Vector2(4.8, 19.2), Vector2(19.6, 19.2)])
        _poly([Vector2(7.4, 15.4), Vector2(10.6, 10.2), Vector2(13.4, 13.0), Vector2(18.2, 6.4)])


func _signal() -> void:
        _circle(Vector2(6.4, 18.0), 1.3, true)
        _arc(Vector2(6.4, 18.0), 4.0, -1.15, -0.25)
        _arc(Vector2(6.4, 18.0), 7.0, -1.15, -0.25)
        _arc(Vector2(6.4, 18.0), 10.0, -1.15, -0.25)


func _tag() -> void:
        _rect(Rect2(4.2, 6.6, 15.6, 10.8))
        _circle(Vector2(9.4, 10.8), 1.5)
        _arc(Vector2(9.4, 15.0), 2.4, PI, TAU)
        _line(Vector2(13.6, 10.2), Vector2(17.0, 10.2))
        _line(Vector2(13.6, 13.6), Vector2(16.2, 13.6))


func _bubble() -> void:
        _poly([Vector2(4.4, 5.6), Vector2(19.6, 5.6), Vector2(19.6, 15.6),
                Vector2(11.2, 15.6), Vector2(8.0, 19.2), Vector2(8.0, 15.6),
                Vector2(4.4, 15.6), Vector2(4.4, 5.6)])
        _line(Vector2(8.0, 9.0), Vector2(16.0, 9.0))
        _line(Vector2(8.0, 12.2), Vector2(13.6, 12.2))


func _bounce() -> void:
        _line(Vector2(4.0, 19.6), Vector2(20.0, 19.6))
        _arc(Vector2(8.2, 15.4), 4.2, PI, TAU)
        _arc(Vector2(15.6, 9.6), 4.2, PI, TAU)


func _reset() -> void:
        _arc(Vector2(12, 12), 6.8, 0.7, TAU - 0.55)
        _arrow_tip(Vector2(12 + 6.8 * cos(0.7), 12 + 6.8 * sin(0.7)), Vector2(-sin(0.7), cos(0.7)))


func _exit() -> void:
        _poly([Vector2(5.6, 4.6), Vector2(14.0, 4.6), Vector2(14.0, 19.4),
                Vector2(5.6, 19.4), Vector2(5.6, 4.6)])
        _line(Vector2(11.4, 12.0), Vector2(19.2, 12.0))
        _arrow_tip(Vector2(19.2, 12.0), Vector2(-1, 0))


func _sliders() -> void:
        _line(Vector2(4.4, 7.4), Vector2(19.6, 7.4))
        _circle(Vector2(9.2, 7.4), 2.0, true)
        _line(Vector2(4.4, 12.0), Vector2(19.6, 12.0))
        _circle(Vector2(15.4, 12.0), 2.0, true)
        _line(Vector2(4.4, 16.6), Vector2(19.6, 16.6))
        _circle(Vector2(7.0, 16.6), 2.0, true)


func _invert() -> void:
        _line(Vector2(12, 4.6), Vector2(12, 19.4))
        _arrow_tip(Vector2(12, 4.6), Vector2(0, 1))
        _arrow_tip(Vector2(12, 19.4), Vector2(0, -1))
        _line(Vector2(6.8, 8.4), Vector2(6.8, 15.6))
        _arrow_tip(Vector2(6.8, 8.4), Vector2(0, 1))
