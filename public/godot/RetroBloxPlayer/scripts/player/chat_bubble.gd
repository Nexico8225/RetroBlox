class_name ChatBubble
extends Node3D
# Renders 3D billboard speech bubbles above characters when they chat.
# Scaled dynamically with camera distance to preserve legibility when zoomed out.
const SHOW_SECONDS := 10.0
const FADE_SECONDS := 1.2
const MAX_LINES := 4
const MAX_STACK := 3
const WRAP_WIDTH := 330.0
const MAX_CHARS := 160
const STACK_GAP := 0.28
const REFLOW_SPEED := 28.0
const BASE_LIFT := 0.18
const PLATE_CENTER_LIFT := 7.0
const TEXT_SIZE := 28
const BASE_PIXEL_SIZE := 0.0145

const REF_DISTANCE := 14.0
const MIN_SCALE := 0.85
const MAX_SCALE := 7.0
const FADE_START_DIST := 70.0
const MAX_VISIBLE_DIST := 95.0

static var _tex_cache: Dictionary = {}

static func _bubble_font() -> Font:
	var f: Font = null
	if ResourceLoader.exists("res://scripts/ui/retro_theme.gd"):
		var theme := load("res://scripts/ui/retro_theme.gd")
		f = theme.call("arial", 600)
	return f if f != null else ThemeDB.fallback_font

var _entries: Array[Dictionary] = []


func _init() -> void:
	position = Vector3(0.0, 5.85, 0.0)


func show_text(message: String) -> void:
	var text := message.strip_edges()
	if text.length() > MAX_CHARS:
		text = text.substr(0, MAX_CHARS) + "…"
	var lines := _wrap(text)
	if lines.is_empty():
		return

	# Match perspective distance scale immediately on creation
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dist := REF_DISTANCE
	if cam != null and is_instance_valid(cam):
		dist = cam.global_position.distance_to(global_position)
	var dist_scale := clampf(dist / REF_DISTANCE, MIN_SCALE, MAX_SCALE)
	scale = Vector3(dist_scale, dist_scale, dist_scale)
	visible = dist < MAX_VISIBLE_DIST

	while _entries.size() >= MAX_STACK:
		_fade_out(0)

	var font := _bubble_font()
	var max_w := 0.0
	for ln in lines:
		max_w = maxf(max_w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x)
	var w := clampi((int(max_w) + 56 + 9) & ~15, 120, 480)
	var tex := _plate_texture(lines.size(), w)
	var squeeze := 0.65 + 0.35 * float(lines.size()) / float(MAX_LINES)
	var height := tex.get_height() * BASE_PIXEL_SIZE * squeeze
	var initial_y := BASE_LIFT + height * 0.5

	var sprite := Sprite3D.new()
	sprite.name = "Plate"
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = BASE_PIXEL_SIZE
	sprite.shaded = false
	sprite.render_priority = 10
	sprite.scale = Vector3(1.0, squeeze, 1.0)
	sprite.modulate = Color(1, 1, 1, 1.0)
	sprite.position = Vector3(0.0, initial_y, 0.0)
	add_child(sprite)

	var label := Label3D.new()
	label.name = "Text"
	label.text = "\n".join(lines)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = BASE_PIXEL_SIZE
	label.font = font
	label.font_size = TEXT_SIZE
	label.outline_size = 0
	label.modulate = Color(0.13, 0.14, 0.16, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.shaded = false
	label.render_priority = 11
	label.position = Vector3(0.0, initial_y + PLATE_CENTER_LIFT * BASE_PIXEL_SIZE * squeeze, 0.0)
	add_child(label)

	_entries.append({
		"sprite": sprite, "label": label,
		"left": SHOW_SECONDS, "height": height, "y": initial_y,
		"squeeze": squeeze,
	})


func _process(delta: float) -> void:
	if _entries.is_empty():
		return

	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dist := REF_DISTANCE
	if cam != null and is_instance_valid(cam):
		dist = cam.global_position.distance_to(global_position)

	# Dynamic perspective scaling: expands with distance so it maintains
	# a constant readable size on the screen as the player zooms out
	var dist_scale := clampf(dist / REF_DISTANCE, MIN_SCALE, MAX_SCALE)
	scale = Vector3(dist_scale, dist_scale, dist_scale)

	# Distance fade: disappears if very far away (between FADE_START_DIST and MAX_VISIBLE_DIST)
	var dist_alpha := 1.0
	if dist >= MAX_VISIBLE_DIST:
		dist_alpha = 0.0
	elif dist > FADE_START_DIST:
		dist_alpha = (MAX_VISIBLE_DIST - dist) / (MAX_VISIBLE_DIST - FADE_START_DIST)

	if dist_alpha <= 0.001:
		visible = false
	else:
		visible = true

	var died: Array[int] = []
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		e["left"] = float(e["left"]) - delta
		var a := 1.0
		if float(e["left"]) < 0.0:
			died.append(i)
			a = 0.0
		elif float(e["left"]) < FADE_SECONDS:
			a = float(e["left"]) / FADE_SECONDS
		var final_a := a * dist_alpha
		var spr: Sprite3D = e["sprite"]
		if spr != null and is_instance_valid(spr):
			spr.modulate.a = final_a
		var lab: Label3D = e["label"]
		if lab != null and is_instance_valid(lab):
			lab.modulate.a = final_a
	for i in range(died.size() - 1, -1, -1):
		_retire(died[i])
	if _entries.is_empty():
		return

	var cursor := 0.0
	for k in range(_entries.size() - 1, -1, -1):
		var e: Dictionary = _entries[k]
		var h: float = e["height"]
		var sq: float = e.get("squeeze", 1.0)
		var target := cursor + BASE_LIFT + h * 0.5
		var y: float = lerpf(float(e["y"]), target, 1.0 - exp(-REFLOW_SPEED * delta))
		e["y"] = y
		var spr: Sprite3D = e["sprite"]
		if spr != null and is_instance_valid(spr):
			spr.position = Vector3(0.0, y, 0.0)
		var lab: Label3D = e["label"]
		if lab != null and is_instance_valid(lab):
			lab.position = Vector3(0.0, y + PLATE_CENTER_LIFT * BASE_PIXEL_SIZE * sq, 0.0)
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


func _fade_out(index: int) -> void:
	var e: Dictionary = _entries[index]
	_entries.remove_at(index)
	var spr: Sprite3D = e["sprite"]
	var lab: Label3D = e["label"]
	var tw := create_tween()
	tw.set_parallel(true)
	if spr != null and is_instance_valid(spr):
		tw.tween_property(spr, "modulate:a", 0.0, 0.35)
	if lab != null and is_instance_valid(lab):
		tw.tween_property(lab, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void:
		if spr != null and is_instance_valid(spr):
			spr.queue_free()
		if lab != null and is_instance_valid(lab):
			lab.queue_free())


func _wrap(text: String) -> Array[String]:
	var font := _bubble_font()
	var words := text.split(" ")
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var piece := word
		while _line_width(font, piece) > WRAP_WIDTH:
			var take := _fit_px(font, piece, WRAP_WIDTH)
			if take < 1:
				break
			if not current.is_empty():
				lines.append(current)
				current = ""
				if lines.size() >= MAX_LINES:
					return _cut(lines)
			lines.append(piece.substr(0, take))
			piece = piece.substr(take)
			if lines.size() >= MAX_LINES:
				return _cut(lines)
		if piece.is_empty():
			continue
		var candidate := piece if current.is_empty() else current + " " + piece
		if _line_width(font, candidate) <= WRAP_WIDTH:
			current = candidate
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


static func _line_width(font: Font, s: String) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x


static func _fit_px(font: Font, s: String, max_w: float) -> int:
	var lo := 0
	var hi := s.length()
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _line_width(font, s.substr(0, mid)) <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _cut(lines: Array[String]) -> Array[String]:
	lines[MAX_LINES - 1] += "…"
	return lines


static func _plate_texture(line_count: int, w := 256) -> ImageTexture:
	var key := "%d_%d" % [line_count, w]
	if _tex_cache.has(key):
		return _tex_cache[key]

	var lines_h := 32 + 36 * clampi(line_count, 1, MAX_LINES)
	var rect := Rect2(10.0, 8.0, float(w) - 20.0, float(lines_h))
	var tail_h := 24.0
	var h := int(rect.end.y + tail_h)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rad := 18.0
	var tail_l := Vector2(rect.get_center().x - 18.0, rect.end.y - 2.0)
	var tail_r := Vector2(rect.get_center().x + 18.0, rect.end.y - 2.0)
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
	_tex_cache[key] = tex
	return tex


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


static func _near_edge(p: Vector2, r: Rect2, rad: float, tl: Vector2, _tr: Vector2, tip: Vector2) -> bool:
	if _in_triangle(p, tl, _tr, tip):
		var mid := Vector2((tl.x + _tr.x) * 0.5, (tl.y + _tr.y) * 0.5)
		var sl := tl.lerp(mid, 0.4)
		var sr := _tr.lerp(mid, 0.4)
		var st := tip.lerp(mid, 0.3)
		return not _in_triangle(p, sl, sr, st)
	return not _in_rounded_rect(p, r.grow(-2.8), maxf(rad - 2.8, 1.0))
