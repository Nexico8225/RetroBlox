class_name ChatBubble
extends Node3D
## ChatBubble — the classic white speech bubble above a player's head.
## Shared by the local player and remote players: `show_text("hi!")` pops
## the bubble for a few seconds, wrapped the classic way. The white rounded
## plate (with the little tail) is drawn once in code per line-count, so no
## extra asset files ride in the kit.
##
## v3.7: bubbles STACK the Roblox way — every message becomes its OWN
## bubble. The newest parks just above the head and older bubbles climb
## upward ("Good game" over "Oof"), each fading on its own clock. Up to
## MAX_STACK bubbles show at once; a new message retires the oldest early
## so the tower never grows forever.

const SHOW_SECONDS := 4.5
const MAX_LINES := 3
const MAX_STACK := 3          # bubbles visible at once, Roblox-style
const WRAP_AT := 18           # characters per line — the classic narrow bubble
const MAX_CHARS := 110        # hard trim before wrapping
const STACK_GAP := 0.24       # studs between stacked bubbles
const REFLOW_SPEED := 16.0    # how fast bubbles glide into their stack slot
const BASE_LIFT := 0.35       # newest bubble tail sits this far above the node

## Textures are cached per line count (1..MAX_LINES).
static var _tex_cache: Dictionary = {}

## Live stack, OLDEST first: {sprite, label, left, height, y}. y is the
## current (gliding) local center height of the bubble.
var _entries: Array[Dictionary] = []


func _init() -> void:
        position = Vector3(0.0, 6.55, 0.0)   # just above the 5-stud avatar


## Pop a NEW bubble onto the stack (never replaces the old ones — they
## climb up and fade in order, like Roblox).
func show_text(message: String) -> void:
        var text := message.strip_edges()
        if text.length() > MAX_CHARS:
                text = text.substr(0, MAX_CHARS) + "…"
        var lines := _wrap(text)
        if lines.is_empty():
                return

        # the tower never grows forever: retire the oldest bubble early
        while _entries.size() >= MAX_STACK:
                _retire(0)

        var tex := _plate_texture(lines.size())
        var squeeze := 0.62 + 0.38 * float(lines.size()) / float(MAX_LINES)
        var height := tex.get_height() * 0.012 * squeeze

        var sprite := Sprite3D.new()
        sprite.name = "Plate"
        sprite.texture = tex
        sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        sprite.pixel_size = 0.012           # 256 px wide -> ~3.1 studs
        sprite.shaded = false
        sprite.render_priority = 0
        sprite.scale = Vector3(1.0, squeeze, 1.0)
        sprite.modulate = Color(1, 1, 1, 0.0)   # fades in over the first beat
        add_child(sprite)

        var label := Label3D.new()
        label.name = "Text"
        label.text = "\n".join(lines)
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.pixel_size = 0.012
        label.font_size = 24
        label.outline_size = 0
        label.modulate = Color(0.13, 0.14, 0.16, 0.0)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.shaded = false
        label.render_priority = 1           # ink always on top of the plate
        add_child(label)

        # spawn at the head slot (0.0) and glide up to wherever the stack
        # puts it — new bubbles feel like they POP out of the character
        _entries.append({
                "sprite": sprite, "label": label,
                "left": SHOW_SECONDS, "height": height, "y": 0.0,
        })


func _process(delta: float) -> void:
        if _entries.is_empty():
                return
        # lifetimes + per-bubble fade
        var died: Array[int] = []
        for i in range(_entries.size()):
                var e: Dictionary = _entries[i]
                e["left"] = float(e["left"]) - delta
                var a := 1.0
                if float(e["left"]) < 0.0:
                        died.append(i)
                        a = 0.0
                elif float(e["left"]) < 0.4:
                        a = float(e["left"]) / 0.4   # gentle fade at the very end
                elif float(e["left"]) > SHOW_SECONDS - 0.12:
                        a = (SHOW_SECONDS - float(e["left"])) / 0.12   # pop in
                var spr: Sprite3D = e["sprite"]
                spr.modulate.a = a
                var lab: Label3D = e["label"]
                lab.modulate.a = a
        for i in range(died.size() - 1, -1, -1):
                _retire(died[i])
        if _entries.is_empty():
                return

        # stack slots: the NEWEST bubble owns the spot just above the head,
        # every older one sits a bubble + gap higher (Roblox "Good game"/"Oof")
        var cursor := 0.0
        for k in range(_entries.size() - 1, -1, -1):
                var e: Dictionary = _entries[k]
                var h: float = e["height"]
                var target := cursor + BASE_LIFT + h * 0.5
                # glide toward the slot — the whole tower reflows smoothly
                var y: float = lerpf(float(e["y"]), target, 1.0 - exp(-REFLOW_SPEED * delta))
                e["y"] = y
                var spr: Sprite3D = e["sprite"]
                spr.position = Vector3(0.0, y, 0.0)
                var lab: Label3D = e["label"]
                lab.position = Vector3(0.0, y, 0.0)
                cursor += h + STACK_GAP


func _retire(index: int) -> void:
        var e: Dictionary = _entries[index]
        _entries.remove_at(index)
        var spr: Sprite3D = e["sprite"]
        if spr != null and is_instance_valid(spr):
                spr.queue_free()
        var lab: Label3D = e["label"]
        if lab != null and is_instance_valid(lab):
                lab.queue_free()


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
