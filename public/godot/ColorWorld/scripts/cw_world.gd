extends Node3D
## ==================================================================
##  CW WORLD — one ColorWorld play session.
## ==================================================================
##
##  WHAT HAPPENS HERE (the whole game, in order):
##    1. setup(map_def) builds every part of the map as a WHITE UNSHADED
##       mesh with a BLACK OUTLINE (inverted-hull: a second pass that
##       renders the back faces grown a little, in black).
##    2. HOLD LEFT MOUSE on the world -> a brush sphere stamps COLOR onto
##       every triangle whose center is inside the brush radius (vertex
##       colors — the same trick the web version uses).
##    3. The HUD (CanvasLayer) shows Painted: N / total, a progress bar,
##       and the HINT button. 10 hints per map. Paint 100% -> COMPLETE!
##
##  CONTROLS:
##    LEFT mouse (hold)  paint
##    RIGHT mouse (drag) orbit the camera
##    WHEEL              zoom in / out
##    H                  hint (same as the button)
##
##  EDIT ME: brush radius, palette, hints per map — all constants below.
## ==================================================================

const HINTS_PER_MAP := 10          # the rule from the game design
const BRUSH_RADIUS := 1.1          # studs — how wide the brush paints
const HINT_RADIUS := 3.0           # hints fill a bigger blob
const STAMP_INTERVAL := 0.045      # seconds between brush stamps while held

## The colors a new brush stroke cycles through (happy primaries first).
const PALETTE := [
        Color("e8333f"), Color("1b6fae"), Color("38c172"), Color("e2b23a"),
        Color("8e44ad"), Color("e87a2e"), Color("e86bb0"), Color("27c7d8"),
]

signal request_menu            # back button
signal painted_changed(n: int, total: int)
signal hints_changed(n: int)
signal world_complete

# ---------------------------------------------------------------- state
var map_def: Dictionary = {}
var center := Vector3.ZERO
var painted := 0
var total := 0
var hints_left := HINTS_PER_MAP
var complete := false

# every paintable: { mi, body, arrays, colors, centroids: PackedVector3Array,
#                    face_verts: Array (per face -> 3 vertex indices),
#                    painted_faces: Dictionary, xf: Transform3D }
var _paintables: Array = []

# camera orbit
var _cam: Camera3D
var _orbit_yaw := 0.8
var _orbit_pitch := 0.5
var _orbit_dist := 46.0
var _orbiting := false
var _last_mouse := Vector2.ZERO

# brush
var _painting := false
var _stamp_cd := 0.0
var _palette_i := 0
var _stroke_color := Color("e8333f")

# HUD
var _hud: CanvasLayer
var _painted_label: Label
var _bar: ColorRect
var _bar_bg: ColorRect
var _hints_btn: Button
var _banner: Label

# ==================================================================
# BUILD
# ==================================================================

func setup(p_map: Dictionary) -> void:
        map_def = p_map
        hints_left = HINTS_PER_MAP
        painted = 0
        total = 0
        complete = false

        _build_sky()
        for part in map_def.get("parts", []):
                _build_part(part)
        _compute_center()
        _spawn_camera()
        _build_hud()
        _update_hud()

## Sky gradient + soft fog, straight from the map definition.
func _build_sky() -> void:
        var env := Environment.new()
        var sky := Sky.new()
        var mat := ProceduralSkyMaterial.new()
        mat.sky_top_color = Color(str(map_def.get("sky_top", "3f8fe0")))
        mat.sky_horizon_color = Color(str(map_def.get("sky_horizon", "cfe6f7")))
        mat.ground_bottom_color = Color(str(map_def.get("sky_horizon", "cfe6f7")))
        mat.ground_horizon_color = Color(str(map_def.get("sky_horizon", "cfe6f7")))
        sky.sky_material = mat
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color(1, 1, 1)
        env.ambient_light_energy = 1.0   # fullbright-ish: color reads TRUE
        var we := WorldEnvironment.new()
        we.environment = env
        add_child(we)

## One part -> one paintable white mesh + black outline + paintable body.
## Two kinds of parts are supported:
##   * DSL parts from cw_maps.gd  — { p, s, shape }
##   * raw GLB surfaces           — { arrays: Dictionary, xf: Transform3D, grow: float }
func _build_part(part: Dictionary) -> void:
        if part.has("arrays"):
                var x: Transform3D = part["xf"]
                var g: float = float(part.get("grow", 0.05))
                var rec := add_paintable_surface(self, part["arrays"], x, g)
                _paintables.append(rec)
                total += rec["face_count"]
                return
        var p: Array = part.get("p", [0, 0, 0])
        var s: Array = part.get("s", [4, 1, 4])
        var shape := str(part.get("shape", "box"))
        var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
        var size := Vector3(float(s[0]), float(s[1]), float(s[2]))

        var prim: PrimitiveMesh
        match shape:
                "cyl":
                        var c := CylinderMesh.new()
                        c.height = size.y
                        c.top_radius = size.x * 0.5
                        c.bottom_radius = size.z * 0.5
                        c.radial_segments = 20
                        prim = c
                "sphere":
                        var sp := SphereMesh.new()
                        sp.radius = size.x * 0.5
                        sp.height = size.y
                        sp.radial_segments = 20
                        sp.rings = 10
                        prim = sp
                _:
                        var b := BoxMesh.new()
                        b.size = size
                        prim = b

        var arrays := prim.get_mesh_arrays()
        var rec := add_paintable_surface(self, arrays, Transform3D(Basis(), pos),
                clampf(0.02 * maxf(size.x, maxf(size.y, size.z)), 0.02, 0.14))
        _paintables.append(rec)
        total += rec["face_count"]

## Shared factory: turns a mesh arrays Dictionary into a WHITE UNSHADED
## ArrayMesh with a BLACK OUTLINE and a trimesh body you can raycast.
## Used by built-in parts AND by community GLB maps (see cw_glb.gd).
## grow = the outline thickness in world units (bigger parts -> bigger).
static func add_paintable_surface(parent: Node3D, arrays: Dictionary, xf: Transform3D, grow: float) -> Dictionary:
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
        if indices.is_empty():
                # non-indexed geometry: the index is just 0..n
                indices.resize(verts.size())
                for i in verts.size():
                        indices[i] = i
                arrays[Mesh.ARRAY_INDEX] = indices

        # ---- vertex colors, born WHITE (they carry the paint later) ----
        var colors := PackedColorArray()
        colors.resize(verts.size())
        colors.fill(Color(1, 1, 1))
        arrays[Mesh.ARRAY_COLOR] = colors

        var am := ArrayMesh.new()
        am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

        # ---- the WHITE UNSHADED material (+ black outline via next_pass) ----
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color = Color(1, 1, 1)
        mat.vertex_color_use_as_albedo = true
        var outline := StandardMaterial3D.new()
        outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        outline.albedo_color = Color(0, 0, 0)
        outline.cull_mode = BaseMaterial3D.CULL_FRONT   # render back faces
        outline.grow = true                              # ... grown outward
        outline.grow_amount = grow
        mat.next_pass = outline

        # ---- the node ----
        var mi := MeshInstance3D.new()
        mi.mesh = am
        mi.material_override = mat
        mi.transform = xf
        parent.add_child(mi)

        # ---- trimesh body so rays can find us (face order == index order) --
        var body := StaticBody3D.new()
        var cs := CollisionShape3D.new()
        cs.shape = am.create_trimesh_shape()
        body.add_child(cs)
        mi.add_child(body)

        # ---- precompute per-face data for the brush ----
        var face_count := indices.size() / 3
        var centroids := PackedVector3Array()
        centroids.resize(face_count)
        var face_verts: Array = []
        face_verts.resize(face_count)
        for f in face_count:
                var a := indices[f * 3]
                var b := indices[f * 3 + 1]
                var c := indices[f * 3 + 2]
                face_verts[f] = [a, b, c]
                centroids[f] = (verts[a] + verts[b] + verts[c]) / 3.0

        var rec := {
                "mi": mi, "body": body, "arrays": arrays, "verts": verts,
                "indices": indices, "centroids": centroids, "face_verts": face_verts,
                "face_count": face_count, "painted_faces": {}, "xf": mi.global_transform,
        }
        body.set_meta("cw_rec", rec)
        return rec

## The orbit target = middle of everything the map built.
func _compute_center() -> void:
        if _paintables.is_empty():
                center = Vector3.ZERO
                return
        var lo := (_paintables[0]["xf"] * (_paintables[0]["centroids"][0] as Vector3))
        var hi := lo
        for rec in _paintables:
                var xf: Transform3D = rec["xf"]
                for c in rec["centroids"]:
                        var w: Vector3 = xf * (c as Vector3)
                        lo = lo.min(w)
                        hi = hi.max(w)
        center = (lo + hi) * 0.5

func _spawn_camera() -> void:
        _cam = Camera3D.new()
        _cam.fov = 60.0
        add_child(_cam)
        _apply_camera()

func _apply_camera() -> void:
        var dir := Vector3(
                cos(_orbit_pitch) * sin(_orbit_yaw),
                sin(_orbit_pitch),
                cos(_orbit_pitch) * cos(_orbit_yaw))
        _cam.position = center + dir * _orbit_dist
        _cam.look_at(center, Vector3.UP)

# ==================================================================
# INPUT + PAINTING
# ==================================================================

func _unhandled_input(event: InputEvent) -> void:
        if complete:
                return
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT:
                        if mb.pressed:
                                _painting = true
                                _stroke_color = PALETTE[_palette_i % PALETTE.size()]
                                _palette_i += 1
                                _stamp_cd = 0.0        # paint THIS frame
                        else:
                                _painting = false
                elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
                        _orbiting = mb.pressed
                        _last_mouse = mb.position
                elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
                        _orbit_dist = maxf(10.0, _orbit_dist - 3.0)
                        _apply_camera()
                elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        _orbit_dist = minf(120.0, _orbit_dist + 3.0)
                        _apply_camera()
        elif event is InputEventMouseMotion:
                var mm := event as InputEventMouseMotion
                if _orbiting:
                        _orbit_yaw -= (mm.position.x - _last_mouse.x) * 0.008
                        _orbit_pitch = clampf(_orbit_pitch + (mm.position.y - _last_mouse.y) * 0.006, 0.08, 1.45)
                        _last_mouse = mm.position
                        _apply_camera()
        elif event is InputEventKey:
                var k := event as InputEventKey
                if k.pressed and k.keycode == KEY_H:
                        hint()

func _physics_process(delta: float) -> void:
        if _painting and not complete:
                _stamp_cd -= delta
                if _stamp_cd <= 0.0:
                        _stamp_cd = STAMP_INTERVAL
                        _stamp_brush()

## One brush stamp: ray from the camera through the mouse, then color
## EVERY triangle whose world-space center sits inside the brush sphere.
func _stamp_brush() -> void:
        var mouse := get_viewport().get_mouse_position()
        var from := _cam.project_ray_origin(mouse)
        var dir := _cam.project_ray_normal(mouse)
        var space := get_world_3d().direct_space_state

        var ray := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0)
        var hit := space.intersect_ray(ray)
        if hit.is_empty():
                return
        var hit_pos: Vector3 = hit["position"]

        # sphere query around the hit -> touches EVERY nearby paintable,
        # so a brush on a wall edge colors the roof touching it too
        var sphere := SphereShape3D.new()
        sphere.radius = BRUSH_RADIUS
        var q := PhysicsShapeQueryParameters3D.new()
        q.shape = sphere
        q.transform = Transform3D(Basis(), hit_pos)
        var hits := space.intersect_shape(q, 32)
        var any := false
        for h in hits:
                var body: Node = h["collider"]
                var rec: Dictionary = body.get_meta("cw_rec", {}) if body.has_meta("cw_rec") else {}
                if rec.is_empty():
                        continue
                if _paint_faces_near(rec, hit_pos, BRUSH_RADIUS, _stroke_color):
                        any = true
        if any:
                _update_hud()

## The paint itself: mark faces inside the radius, write the color into
## the vertex colors, rebuild the (small) ArrayMesh surface.
func _paint_faces_near(rec: Dictionary, world_pos: Vector3, radius: float, color: Color) -> bool:
        var xf: Transform3D = rec["xf"]
        var centroids: PackedVector3Array = rec["centroids"]
        var painted_faces: Dictionary = rec["painted_faces"]
        var verts: PackedVector3Array = rec["verts"]
        var colors: PackedColorArray = rec["arrays"][Mesh.ARRAY_COLOR]
        var face_verts: Array = rec["face_verts"]
        var changed := false
        for f in rec["face_count"]:
                if painted_faces.has(f):
                        continue
                var world_c: Vector3 = xf * (centroids[f] as Vector3)
                if world_c.distance_to(world_pos) <= radius:
                        painted_faces[f] = true
                        painted += 1
                        changed = true
                        for vi in face_verts[f]:
                                colors[vi] = color
        if changed:
                var am: ArrayMesh = rec["mi"].mesh
                am.clear_surfaces()
                am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rec["arrays"])
        return changed

# ==================================================================
# HINTS — 10 per map. A hint fills a bigger blob around a random
# unpainted face, so you never get stuck hunting the last spots.
# ==================================================================

func hint() -> void:
        if complete or hints_left <= 0:
                return
        var unpainted: Array[int] = []
        for rec in _paintables:
                for f in rec["face_count"]:
                        if not rec["painted_faces"].has(f):
                                unpainted.append(int(f))
        if unpainted.is_empty():
                return
        var pick := unpainted[randi() % unpainted.size()]
        var rec := {}
        # find which record owns this face index (they were appended in order)
        for r in _paintables:
                if (r["face_count"] as int) > pick:
                        rec = r
                        break
                pick -= r["face_count"]
        if rec.is_empty():
                return
        var xf: Transform3D = rec["xf"]
        var world_c: Vector3 = xf * (rec["centroids"][pick] as Vector3)
        var hint_color := PALETTE[_palette_i % PALETTE.size()]
        _palette_i += 1
        for r in _paintables:
                _paint_faces_near(r, world_c, HINT_RADIUS, hint_color)
        hints_left -= 1
        _update_hud()
        if painted >= total:
                _win()

# ==================================================================
# HUD
# ==================================================================

func _build_hud() -> void:
        _hud = CanvasLayer.new()
        add_child(_hud)

        # painted counter + progress bar (top-left)
        var panel := PanelContainer.new()
        panel.position = Vector2(12, 12)
        _hud.add_child(panel)
        var vb := VBoxContainer.new()
        panel.add_child(vb)
        _painted_label = Label.new()
        _painted_label.add_theme_font_size_override("font_size", 18)
        vb.add_child(_painted_label)
        _bar_bg = ColorRect.new()
        _bar_bg.color = Color(0, 0, 0, 0.35)
        _bar_bg.custom_minimum_size = Vector2(220, 12)
        vb.add_child(_bar_bg)
        _bar = ColorRect.new()
        _bar.color = Color("38c172")
        _bar.position = Vector2(1, 1)
        _bar.size = Vector2(0, 10)
        _bar_bg.add_child(_bar)

        # hint button (top-right) — 10 per map
        _hints_btn = Button.new()
        _hints_btn.text = "Hint (%d left) [H]" % hints_left
        _hints_btn.add_theme_font_size_override("font_size", 14)
        _hints_btn.pressed.connect(hint)
        _hints_btn.anchor_left = 1.0
        _hints_btn.anchor_right = 1.0
        _hints_btn.offset_left = -190.0
        _hints_btn.offset_right = -12.0
        _hints_btn.offset_top = 12.0
        _hud.add_child(_hints_btn)

        # back to menu (bottom-left)
        var back := Button.new()
        back.text = "< Menu"
        back.add_theme_font_size_override("font_size", 13)
        back.anchor_top = 1.0
        back.anchor_bottom = 1.0
        back.offset_left = 12.0
        back.offset_right = 96.0
        back.offset_top = -44.0
        back.offset_bottom = -12.0
        back.pressed.connect(func() -> void: request_menu.emit())
        _hud.add_child(back)

        # completion banner (hidden until 100%)
        _banner = Label.new()
        _banner.text = "WORLD COMPLETE!"
        _banner.add_theme_font_size_override("font_size", 54)
        _banner.add_theme_color_override("font_color", Color("ffd700"))
        _banner.add_theme_color_override("font_outline_color", Color.BLACK)
        _banner.add_theme_constant_override("outline_size", 10)
        _banner.visible = false
        _hud.add_child(_banner)
        _banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _update_hud() -> void:
        if _painted_label == null:
                return
        var pct := 0
        if total > 0:
                pct = int(100.0 * painted / total)
        _painted_label.text = "Painted: %d / %d  (%d%%)" % [painted, total, pct]
        var w: float = 218.0 * (float(painted) / maxf(1.0, float(total)))
        _bar.size = Vector2(w, 10)
        _hints_btn.text = "Hint (%d left) [H]" % hints_left
        _hints_btn.disabled = hints_left <= 0
        if painted >= total and not complete:
                _win()

func _win() -> void:
        if complete:
                return
        complete = true
        _banner.visible = true
        world_complete.emit()
