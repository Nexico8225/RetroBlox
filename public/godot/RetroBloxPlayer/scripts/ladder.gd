@tool
class_name RetroLadder
extends RetroPart

## A classic TrussPart-style climbable ladder. Solid like a part, but while
## you touch it you can climb: push forward to go up, back to go down,
## SPACE to jump off. The rig's Climb animation plays while you climb.
##
## Default size is the classic truss 2 x 12 x 1. Make sure the top overlaps
## the platform edge so players can crest over onto it.

@export var rungs := true:
        set(value):
                rungs = value
                _rebuild_rungs()


var _rung_root: Node3D
var _climb_area: Area3D


func _ready() -> void:
        super()
        _make_climb_area()
        _rebuild_rungs()


## The climb zone — an Area3D a little larger than the part, on collision
## layer 16 (the "ladder" layer the player's sensor listens on).
func _make_climb_area() -> void:
        if _climb_area != null:
                _climb_area.queue_free()
        _climb_area = Area3D.new()
        _climb_area.name = "ClimbArea"
        _climb_area.collision_layer = 16
        _climb_area.collision_mask = 0
        _climb_area.monitoring = false
        _climb_area.add_to_group("ladder")
        var shape_node := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size + Vector3(1.2, 0.4, 1.6)
        shape_node.shape = shape
        _climb_area.add_child(shape_node)
        add_child(_climb_area)


func _rebuild_rungs() -> void:
        if not is_inside_tree():
                return
        if _rung_root != null:
                _rung_root.queue_free()
        if _climb_area != null:
                var shape_node := _climb_area.get_child(0) as CollisionShape3D
                if shape_node != null:
                        (shape_node.shape as BoxShape3D).size = size + Vector3(1.2, 0.4, 1.6)
        # the TrussPart look — grey diagonal lattice on EVERY face
        _apply_truss_material()
        if not rungs:
                return
        # THE REAL TRUSS: corner rails, horizontal rungs every stud and
        # alternating diagonal braces on all four faces, merged into ONE
        # mesh (one draw call) so it reads as a climbable truss from every
        # angle, not a flat slab with a faint texture.
        _rung_root = MeshInstance3D.new()
        _rung_root.name = "Rungs"
        (_rung_root as MeshInstance3D).mesh = _build_lattice_mesh()
        _rung_root.material_override = _lattice_material()
        add_child(_rung_root)


static var _lattice_mat: StandardMaterial3D

static func _lattice_material() -> StandardMaterial3D:
        if _lattice_mat == null:
                _lattice_mat = StandardMaterial3D.new()
                _lattice_mat.albedo_color = Color("b9bcc2")   # classic silver truss
                _lattice_mat.roughness = 0.6
                _lattice_mat.metallic = 0.25
        return _lattice_mat


## Merged lattice geometry: corner rails + per-stud rungs + alternating
## diagonals on every face, all in one ArrayMesh.
func _build_lattice_mesh() -> ArrayMesh:
        var verts := PackedVector3Array()
        var norms := PackedVector3Array()
        var indices := PackedInt32Array()
        var w := maxf(size.x, 0.2)
        var h := maxf(size.y, 0.2)
        var d := maxf(size.z, 0.2)
        var bar := 0.14      # lattice bar thickness (studs)
        var out := 0.05      # bars sit just proud of the face
        var hw := w * 0.5
        var hd := d * 0.5

        # 4 corner rails, full height
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        _add_box(verts, norms, indices, Basis.IDENTITY,
                                Vector3(sx * (hw - bar * 0.5), 0.0, sz * (hd - bar * 0.5)),
                                Vector3(bar, h, bar))

        # rungs around the perimeter at every stud boundary
        var segments := maxi(int(round(h)), 1)
        var seg_h := h / float(segments)
        for i in range(segments + 1):
                var y := -h * 0.5 + float(i) * seg_h
                for sz in [-1.0, 1.0]:   # front / back rungs
                        _add_box(verts, norms, indices, Basis.IDENTITY,
                                Vector3(0.0, y, sz * (hd + out)),
                                Vector3(w - bar * 2.0, bar, bar * 0.9))
                for sx in [-1.0, 1.0]:   # left / right rungs
                        _add_box(verts, norms, indices, Basis.IDENTITY,
                                Vector3(sx * (hw + out), y, 0.0),
                                Vector3(bar * 0.9, bar, d - bar * 2.0))

        # alternating diagonal braces, one per segment per face
        var span_x := maxf(w - bar * 2.0, 0.1)
        var span_z := maxf(d - bar * 2.0, 0.1)
        for i in range(segments):
                var y0 := -h * 0.5 + float(i) * seg_h
                var ym := y0 + seg_h * 0.5
                var flip := i % 2 == 1
                # front / back faces: diagonal in the X-Y plane (rotate about Z)
                var ang_xz := atan2(seg_h, span_x)
                var len_x := sqrt(span_x * span_x + seg_h * seg_h)
                for sz in [-1.0, 1.0]:
                        var bz := Basis(Vector3(0, 0, 1), -ang_xz if flip else ang_xz)
                        _add_box(verts, norms, indices, bz,
                                Vector3(0.0, ym, sz * (hd + out)),
                                Vector3(len_x, bar, bar * 0.9))
                # left / right faces: diagonal in the Z-Y plane (rotate about X)
                var ang_zy := atan2(seg_h, span_z)
                var len_z := sqrt(span_z * span_z + seg_h * seg_h)
                for sx in [-1.0, 1.0]:
                        var bx := Basis(Vector3(1, 0, 0), ang_zy if flip else -ang_zy)
                        _add_box(verts, norms, indices, bx,
                                Vector3(sx * (hw + out), ym, 0.0),
                                Vector3(bar * 0.9, bar, len_z))

        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = verts
        arrays[Mesh.ARRAY_NORMAL] = norms
        arrays[Mesh.ARRAY_INDEX] = indices
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        return mesh


## Append one oriented box (6 faces, 24 verts) into merged arrays.
static func _add_box(verts: PackedVector3Array, norms: PackedVector3Array, indices: PackedInt32Array,
                basis: Basis, origin: Vector3, box: Vector3) -> void:
        var h := box * 0.5
        # normal, texture-right, texture-down per face (same winding as zone_box)
        var faces := [
                [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0)],
                [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
                [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)],
                [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],
                [Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
                [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
        ]
        for f in faces:
                var n: Vector3 = f[0]
                var u: Vector3 = f[1]
                var v: Vector3 = f[2]
                var center := n * h
                var hu := absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z
                var hv := absf(v.x) * h.x + absf(v.y) * h.y + absf(v.z) * h.z
                var tl := center - u * hu - v * hv
                var tr := center + u * hu - v * hv
                var br := center + u * hu + v * hv
                var bl := center - u * hu + v * hv
                var base := verts.size()
                for corner in [tl, tr, br, bl]:
                        verts.push_back(basis * corner + origin)
                var wn := basis * n
                for _i in range(4):
                        norms.push_back(wn)
                for idx in [base, base + 3, base + 2, base, base + 2, base + 1]:
                        indices.push_back(idx)


## THE TRUSS — a procedural diagonal-lattice texture (the classic
## TrussPart cross-brace), wrapped on every face via triplanar mapping at
## one lattice cell per stud. Reads as "climbable" at a glance.
func _apply_truss_material() -> void:
        if _material == null:
                return
        _material.albedo_texture = _make_truss_texture()
        _material.albedo_color = Color.WHITE
        _material.uv1_triplanar = true
        # triplanar UVs follow world units: one texture tile per 2 studs,
        # the tile holds a 2x2 lattice grid -> one cell per stud
        _material.uv1_scale = Vector3.ONE * 0.5
        _material.roughness = 0.85


static var _truss_tex: ImageTexture

static func _make_truss_texture() -> ImageTexture:
        if _truss_tex != null:
                return _truss_tex
        var s := 128
        var img := Image.create(s, s, false, Image.FORMAT_RGB8)
        var base := Color("8f9297")
        var dark := Color("54575c")
        var light := Color("a6a9ae")
        var span := 64      # 2 lattice crossings per tile -> 1 cell per stud
        var bar := 9        # lattice bar thickness in pixels
        for y in range(s):
                for x in range(s):
                        var d1 := posmod(x + y, span)
                        var d2 := posmod(x - y, span)
                        var c := base
                        if d1 < bar or d2 < bar:
                                c = dark
                        elif d1 == bar or d2 == bar:
                                c = light
                        img.set_pixel(x, y, c)
        _truss_tex = ImageTexture.create_from_image(img)
        return _truss_tex
