class_name ChatBubble
extends Node3D
## ChatBubble — the classic white speech bubble above a player's head.
## Shared by the local player and remote players: `show_text("hi!")` pops
## the bubble for a few seconds, wrapped the classic way. The white rounded
## plate (with the little tail) is drawn once in code per line-count, so no
## extra asset files ride in the kit.

const SHOW_SECONDS := 4.5
const MAX_LINES := 3
const WRAP_AT := 18          # characters per line — the classic narrow bubble
const MAX_CHARS := 110       # hard trim before wrapping

## Textures are cached per line count (1..MAX_LINES).
static var _tex_cache: Dictionary = {}

var _sprite: Sprite3D
var _label: Label3D
var _left := 0.0


func _init() -> void:
        position = Vector3(0.0, 6.55, 0.0)   # just above the 5-stud avatar

        _sprite = Sprite3D.new()
        _sprite.name = "Plate"
        _sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        _sprite.pixel_size = 0.012           # 256 x ~154 px -> ~3.1 x ~1.85 studs
        _sprite.shaded = false
        _sprite.render_priority = 0
        _sprite.visible = false
        add_child(_sprite)

        _label = Label3D.new()
        _label.name = "Text"
        _label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        _label.pixel_size = 0.012
        _label.font_size = 24
        _label.outline_size = 0
        _label.modulate = Color(0.13, 0.14, 0.16)   # near-black ink on white
        _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _label.shaded = false
        _label.render_priority = 1                  # ink always on top of the plate
        _label.visible = false
        add_child(_label)


## Pop the bubble with a message. Wraps to max 3 short lines, classic style.
func show_text(message: String) -> void:
        var text := message.strip_edges()
        if text.length() > MAX_CHARS:
                text = text.substr(0, MAX_CHARS) + "…"
        var lines := _wrap(text)
        if lines.is_empty():
                return

        _sprite.texture = _plate_texture(lines.size())
        # squeeze the plate toward the text height (keeps the tail readable)
        var squeeze := 0.62 + 0.38 * float(lines.size()) / float(MAX_LINES)
        _sprite.scale = Vector3(1.0, squeeze, 1.0)
        _label.text = "\n".join(lines)

        _sprite.visible = true
        _label.visible = true
        _left = SHOW_SECONDS
        _sprite.modulate = Color(1, 1, 1, 1)
        _label.modulate.a = 1.0


func _process(delta: float) -> void:
        if _left <= 0.0:
                return
        _left -= delta
        if _left <= 0.0:
                _sprite.visible = false
                _label.visible = false
                return
        # gentle fade at the very end
        if _left < 0.4:
                var a := _left / 0.4
                _sprite.modulate.a = a
                _label.modulate.a = a


## Word-wrap into at most MAX_LINES short lines ("…" marks a cut).
func _wrap(text: String) -> Array[String]:
        var words := text.split(" ")
        var lines: Array[String] = []
        var current := ""
        for word in words:
                var piece := word
                # one very long word: chop it across whole lines
                while piece.length() > WRAP_AT:
                        if not current.is_empty():
                                lines.append(current)
                                current = ""
                                if lines.size() >= MAX_LINES:
                                        return _cut(lines)
                        lines.append(piece.substr(0, WRAP_AT))
                        piece = piece.substr(WRAP_AT)
                        if lines.size() >= MAX_LINES:
                                return _cut(lines)
                if piece.is_empty():
                        continue
                if current.is_empty():
                        current = piece
                elif current.length() + 1 + piece.length() <= WRAP_AT:
                        current += " " + piece
                else:
                        lines.append(current)
                        if lines.size() >= MAX_LINES:
                                return _cut(lines)
                        current = piece
        if not current.is_empty():
                if lines.size() >= MAX_LINES:
                        return _cut(lines)
                lines.append(current)
        return lines


func _cut(lines: Array[String]) -> Array[String]:
        lines[MAX_LINES - 1] += "…"
        return lines


## The white rounded plate with a tail, drawn per line count in code.
static func _plate_texture(line_count: int) -> ImageTexture:
        if _tex_cache.has(line_count):
                return _tex_cache[line_count]

        var w := 256
        var lines_h := 26 + 30 * clampi(line_count, 1, MAX_LINES)
        var rect := Rect2(8.0, 6.0, float(w) - 16.0, float(lines_h))
        var tail_h := 22.0
        var h := int(rect.end.y + tail_h)
        var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
        img.fill(Color(0, 0, 0, 0))

        var rad := 16.0
        var tail_l := Vector2(rect.get_center().x - 16.0, rect.end.y - 2.0)
        var tail_r := Vector2(rect.get_center().x + 16.0, rect.end.y - 2.0)
        var tail_tip := Vector2(rect.get_center().x, rect.end.y + tail_h - 2.0)

        for y in range(h):
                for x in range(w):
                        var p := Vector2(float(x) + 0.5, float(y) + 0.5)
                        var inside := _in_rounded_rect(p, rect, rad) or _in_triangle(p, tail_l, tail_r, tail_tip)
                        if not inside:
                                continue
                        var edge := _near_edge(p, rect, rad, tail_l, tail_r, tail_tip)
                        var col := Color(0.78, 0.81, 0.86) if edge else Color(0.985, 0.99, 1.0)
                        img.set_pixel(x, y, col)

        var tex := ImageTexture.create_from_image(img)
        _tex_cache[line_count] = tex
        return tex


## Signed-distance rounded-rectangle test (classic exact-inside check).
static func _in_rounded_rect(p: Vector2, r: Rect2, rad: float) -> bool:
        if p.x < r.position.x or p.x > r.end.x or p.y < r.position.y or p.y > r.end.y:
                return false
        var hw := r.size.x * 0.5 - rad
        var hh := r.size.y * 0.5 - rad
        var dx := absf(p.x - r.get_center().x) - hw
        var dy := absf(p.y - r.get_center().y) - hh
        if dx <= 0.0 and dy <= 0.0:
                return true
        dx = maxf(dx, 0.0)
        dy = maxf(dy, 0.0)
        return dx * dx + dy * dy <= rad * rad


static func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
        var d1 := _sign_side(p, a, b)
        var d2 := _sign_side(p, b, c)
        var d3 := _sign_side(p, c, a)
        var has_neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
        var has_pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
        return not (has_neg and has_pos)


static func _sign_side(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
        return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


## True within ~2.5px of the silhouette rim (draws the soft grey edge line).
static func _near_edge(p: Vector2, r: Rect2, rad: float, tl: Vector2, tr: Vector2, tip: Vector2) -> bool:
        if _in_triangle(p, tl, tr, tip):
                var mid := Vector2((tl.x + tr.x) * 0.5, (tl.y + tr.y) * 0.5)
                var sl := tl.lerp(mid, 0.4)
                var sr := tr.lerp(mid, 0.4)
                var st := tip.lerp(mid, 0.3)
                return not _in_triangle(p, sl, sr, st)
        return not _in_rounded_rect(p, r.grow(-2.5), maxf(rad - 2.5, 1.0))
