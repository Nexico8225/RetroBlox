class_name WorldBuilder
extends RefCounted
## Turns a place definition into a live 3D world.
##
## PARTS — dictionaries like:
##   { p=[x,y,z] center, s=[sx,sy,sz] size, c="RRGGBB", g="group", m="material",
##     shape="box|cyl|sphere", no_studs=true }
## Groups: spawn | kill | ladder | goal | checkpoint | bounce
## Materials: plastic (default) | metal | neon | wood | grass | dirt
##
## PROPS — the decorations that make a place feel built by a person:
##   { type="tree", p=[x,y,z] }                       trunk + ball canopy
##   { type="flower", p=[x,y,z], c="ff0000" }         petals + yellow center
##   { type="fence", p=[x,y,z], s=[len,1.2,0.3] }     wood posts + rails
##   { type="crate", p=[x,y,z], s=2 }                 wood box with frame
##   { type="cloud", p=[x,y,z], s=6 }                 puffy cloud cluster
##   { type="cloudpad", p=[x,y,z], s=[w,d] }          WALKABLE cloud platform
##   { type="sign", p=[x,y,z], text="..", title="..", face=[yaw] }  board
##   { type="pipe", p=[x,y,z], h=6 }                  classic green pipe
##   { type="arch", p=[x,y,z], yaw=deg }              NEW GAMES portal arch
##   { type="snow", p=[x,y,z], s=[w,h,d] }            snow mound (sphere-ish)
##   { type="coin", p=[x,y,z] }                       collectible Tix (coin.gd)
##
## Everything gets the classic stud texture via world triplanar mapping —
## one stud per unit, tinted by the part color, generated procedurally at
## runtime so the client needs zero texture files.

const StudColorEdge := Color("000000", 0.10)

const CoinScript := preload("res://scripts/world/coin.gd")

## SCALE — place definitions are authored in STUDS (classic Roblox units);
## they are built 1 stud = 1 Godot unit — the classic size.
## A 5-stud avatar is 5 units tall and every part keeps its stud numbers.
const STUD := 1.0

static var _stud_tex: ImageTexture


## Visual-only containers (props) build in stud units inside a group node
## scaled by STUD — zero risk of missing a literal, exact scale everywhere.
static func _scaled_group(root: Node3D, pos_units: Vector3) -> Node3D:
        var g := Node3D.new()
        g.position = pos_units
        g.scale = Vector3.ONE * STUD
        root.add_child(g)
        return g


## Build a whole place. Returns { root, spawns: Array[Vector3] }.
static func build(def: Dictionary) -> Dictionary:
        var root := Node3D.new()
        root.name = "World"

        # ---- sky + light ----
        var env := Environment.new()
        var sky := Sky.new()
        var sky_mat := ProceduralSkyMaterial.new()
        sky_mat.sky_top_color = Color(def.get("sky_top", "3d8fd1"))
        sky_mat.sky_horizon_color = Color(def.get("sky_horizon", "bfe0f5"))
        sky_mat.ground_bottom_color = Color(def.get("sky_ground", "2a5d38"))
        sky_mat.ground_horizon_color = Color(def.get("sky_horizon", "bfe0f5"))
        sky_mat.sun_angle_max = 30.0
        sky.sky_material = sky_mat
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 0.55
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        if bool(def.get("cloud_deck", false)):
                # the reference video's look: horizon melts into a white cloud sea
                env.fog_enabled = true
                env.fog_light_color = Color("eef6fd")
                env.fog_density = 0.0042
                env.fog_sky_affect = 0.28
        var world_env := WorldEnvironment.new()
        world_env.environment = env
        root.add_child(world_env)

        var sun := DirectionalLight3D.new()
        sun.name = "Sun"
        sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
        sun.light_energy = 0.85
        sun.shadow_enabled = true
        sun.directional_shadow_max_distance = 80.0
        root.add_child(sun)
        var settings: Node = Engine.get_main_loop().root.get_node_or_null("/root/Settings")
        if settings != null:
                sun.shadow_enabled = bool(settings.get("shadows"))
                settings.changed.connect(func(key: String, value: Variant) -> void:
                        if key == "shadows" and is_instance_valid(sun):
                                sun.shadow_enabled = bool(value))

        # ---- sea of clouds under the islands (the video signature) ----
        if bool(def.get("cloud_deck", false)):
                _cloud_deck(root)

        # ---- parts ----
        var spawns: Array[Vector3] = []
        var tex := stud_texture()
        for part in def.get("parts", []):
                _build_part(root, part, tex, spawns)

        # ---- props ----
        for prop in def.get("props", []):
                _build_prop(root, prop, tex)

        return { "root": root, "spawns": spawns }


static func _build_part(root: Node3D, part: Dictionary, tex: ImageTexture, spawns: Array[Vector3]) -> void:
        var p: Array = part.get("p", [0, 0, 0])
        var s: Array = part.get("s", [4, 1, 4])
        var group: String = part.get("g", "")
        var mat_kind: String = part.get("m", "plastic")
        # THE stud conversion: everything below lives in Godot units
        var pos := Vector3(float(p[0]), float(p[1]), float(p[2])) * STUD
        var size := Vector3(float(s[0]), float(s[1]), float(s[2])) * STUD
        var color := Color(part.get("c", "a3a2a5"))
        var shape: String = part.get("shape", "box")

        if group == "ladder":
                # pass-through climbable volume (TrussPart style)
                var lad := Area3D.new()
                lad.collision_layer = 16
                lad.collision_mask = 0
                lad.monitoring = false
                lad.add_to_group("ladder")
                var lc := CollisionShape3D.new()
                var lshape := BoxShape3D.new()
                lshape.size = size
                lc.shape = lshape
                lad.add_child(lc)
                lad.position = pos
                root.add_child(lad)
                _ladder_visual(root, pos, size)
                return

        var body := StaticBody3D.new()
        body.position = pos
        body.collision_layer = 1
        body.collision_mask = 0
        var shape_node := CollisionShape3D.new()
        var mesh_node := MeshInstance3D.new()
        var mesh: Mesh
        var col_shape: Shape3D
        match shape:
                "cyl":
                        var cyl := CylinderMesh.new()
                        cyl.height = size.y
                        cyl.top_radius = size.x * 0.5
                        cyl.bottom_radius = size.x * 0.5
                        mesh = cyl
                        var cshape := CylinderShape3D.new()
                        cshape.height = size.y
                        cshape.radius = size.x * 0.5
                        col_shape = cshape
                "sphere":
                        var sph := SphereMesh.new()
                        sph.radius = size.x * 0.5
                        sph.height = size.x
                        mesh = sph
                        var sshape := SphereShape3D.new()
                        sshape.radius = size.x * 0.5
                        col_shape = sshape
                _:
                        var box := BoxMesh.new()
                        box.size = size
                        mesh = box
                        var bshape := BoxShape3D.new()
                        bshape.size = size
                        col_shape = bshape
        shape_node.shape = col_shape
        body.add_child(shape_node)

        mesh_node.mesh = mesh
        mesh_node.material_override = _part_material(color, mat_kind, tex, part.get("no_studs", false))
        body.add_child(mesh_node)

        if group != "":
                body.add_to_group(group)
        if group == "spawn":
                spawns.append(pos + Vector3(0.0, size.y * 0.5 + 0.2 * STUD, 0.0))
                _spawn_pad_visual(root, pos, size)
        if group == "checkpoint":
                body.set_meta("spawn", pos + Vector3(0.0, size.y * 0.5 + 0.2 * STUD, 0.0))
        if group == "goal":
                _goal_sparkle(root, pos + Vector3(0.0, size.y * 0.5 + 0.6 * STUD, 0.0))
        root.add_child(body)


## Gold sparkles idling above a goal pad — the prize should look like one.
static func _goal_sparkle(root: Node3D, at: Vector3) -> void:
        var fx := CPUParticles3D.new()
        fx.name = "GoalSparkle"
        fx.amount = 14
        fx.lifetime = 1.6
        fx.preprocess = 1.2
        fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
        fx.emission_sphere_radius = 2.2 * STUD
        fx.direction = Vector3.UP
        fx.spread = 30.0
        fx.initial_velocity_min = 0.6 * STUD
        fx.initial_velocity_max = 1.6 * STUD
        fx.gravity = Vector3.ZERO
        fx.scale_amount_min = 0.06 * STUD
        fx.scale_amount_max = 0.16 * STUD
        fx.mesh = BoxMesh.new()
        (fx.mesh as BoxMesh).size = Vector3.ONE
        fx.color = Color("ffe37a")
        fx.position = at
        root.add_child(fx)


# ------------------------------------------------------------------ props

static func _build_prop(root: Node3D, prop: Dictionary, tex: ImageTexture) -> void:
        var p: Array = prop.get("p", [0, 0, 0])
        # prop origins convert to units here; sizes stay in studs for the
        # wrap-scaled visual builders, or convert below for physics props
        var pos := Vector3(float(p[0]), float(p[1]), float(p[2])) * STUD
        match String(prop.get("type", "")):
                "tree":
                        _tree(root, pos, float(prop.get("h", 7.0)))
                "flower":
                        _flower(root, pos, Color(prop.get("c", "e8333f")))
                "fence":
                        var fs: Array = prop.get("s", [6, 1.4, 0.35])
                        _fence(root, pos, Vector3(float(fs[0]), float(fs[1]), float(fs[2])), prop.get("yaw", 0.0))
                "crate":
                        var cs: Array = prop.get("s", [2.4, 2.4, 2.4])
                        _crate(root, pos, Vector3(float(cs[0]), float(cs[1]), float(cs[2])) * STUD)
                "cloud":
                        _cloud(root, pos, float(prop.get("s", 6.0)))
                "cloudpad":
                        var ps: Array = prop.get("s", [8, 8])
                        _cloudpad(root, pos, Vector2(float(ps[0]), float(ps[1])) * STUD, tex)
                "sign":
                        _sign(root, pos, String(prop.get("title", "")), String(prop.get("text", "")),
                                Vector2(float(prop.get("w", 14.0)), float(prop.get("h", 7.0))),
                                float(prop.get("yaw", 0.0)), prop.get("c", "27c7d8"), prop.get("title_c", "ffd400"))
                "pipe":
                        _pipe(root, pos, float(prop.get("h", 6.0)) * STUD, float(prop.get("r", 2.0)) * STUD)
                "arch":
                        _arch(root, pos, float(prop.get("yaw", 0.0)))
                "house":
                        _house(root, pos)
                "snow":
                        var ss: Array = prop.get("s", [5, 2, 5])
                        _snow(root, pos, Vector3(float(ss[0]), float(ss[1]), float(ss[2])))
                "coin":
                        # script .new() so the coin's _init runs (group + shape)
                        var coin: Area3D = CoinScript.new()
                        coin.position = pos
                        root.add_child(coin)


static func _tree(root: Node3D, pos: Vector3, h: float) -> void:
        # trunk (cylinder) + 2-3 stacked green spheres — the classic look.
        # Built in stud units inside a STUD-scaled group.
        var group := _scaled_group(root, pos)
        var trunk := MeshInstance3D.new()
        var tm := CylinderMesh.new()
        tm.height = h * 0.55
        tm.top_radius = 0.42
        tm.bottom_radius = 0.55
        trunk.mesh = tm
        trunk.material_override = _flat_mat(Color("8a5a33"), 0.92)
        trunk.position = Vector3(0.0, h * 0.275, 0.0)
        group.add_child(trunk)
        var leaf := Color("2e9e3e")
        var canopy := Node3D.new()
        canopy.position = Vector3(0.0, h * 0.55, 0.0)
        group.add_child(canopy)
        var blobs: Array = [
                [Vector3(0.0, 1.4, 0.0), 2.6],
                [Vector3(1.3, 0.6, 0.5), 1.9],
                [Vector3(-1.2, 0.7, -0.4), 1.8],
        ]
        for blob in blobs:
                var off: Vector3 = blob[0]
                var r: float = blob[1]
                var ball := MeshInstance3D.new()
                var bm := SphereMesh.new()
                bm.radius = r
                bm.height = r * 2.0
                ball.mesh = bm
                ball.material_override = _flat_mat(leaf, 0.85)
                ball.position = off
                canopy.add_child(ball)


static func _flower(root: Node3D, pos: Vector3, color: Color) -> void:
        # green stem + 4 petals (boxes in a cross) + yellow center — exactly
        # the little garden flowers every classic spawn town planted
        var group := _scaled_group(root, pos)
        var stem := MeshInstance3D.new()
        var sm := BoxMesh.new()
        sm.size = Vector3(0.16, 1.1, 0.16)
        stem.mesh = sm
        stem.material_override = _flat_mat(Color("3e9b3e"), 0.85)
        stem.position = Vector3(0.0, 0.55, 0.0)
        group.add_child(stem)
        var head := Node3D.new()
        head.position = Vector3(0.0, 1.2, 0.0)
        group.add_child(head)
        var petal := Color(color)
        var yellow := Color("ffd400")
        for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
                var pet := MeshInstance3D.new()
                var pm := BoxMesh.new()
                pm.size = Vector3(1.0, 0.42, 0.72)
                pet.mesh = pm
                pet.material_override = _flat_mat(petal, 0.8)
                pet.position = dir * 0.62
                head.add_child(pet)
        var center := MeshInstance3D.new()
        var cm := BoxMesh.new()
        cm.size = Vector3(0.62, 0.5, 0.62)
        center.mesh = cm
        center.material_override = _flat_mat(yellow, 0.8)
        head.add_child(center)


static func _fence(root: Node3D, pos: Vector3, size: Vector3, yaw_deg: float) -> void:
        var wood := Color("7a4b28")
        var group := _scaled_group(root, pos)
        group.rotation_degrees.y = yaw_deg
        var rail_len := size.x
        for off in [-0.28, 0.28]:
                var rail := MeshInstance3D.new()
                var rm := BoxMesh.new()
                rm.size = Vector3(rail_len, 0.22, 0.16)
                rail.mesh = rm
                rail.material_override = _flat_mat(wood, 0.9)
                rail.position = Vector3(0.0, size.y * (0.62 if off > 0 else 0.34), off)
                group.add_child(rail)
        var posts := int(rail_len / 2.4) + 1
        for i in range(posts):
                var px := -rail_len * 0.5 + (rail_len * float(i) / float(posts - 1)) if posts > 1 else 0.0
                var post := MeshInstance3D.new()
                var pm := BoxMesh.new()
                pm.size = Vector3(0.26, size.y + 0.3, 0.26)
                post.mesh = pm
                post.material_override = _flat_mat(wood.darkened(0.1), 0.9)
                post.position = Vector3(px, size.y * 0.5, 0.0)
                group.add_child(post)


static func _crate(root: Node3D, pos: Vector3, size: Vector3) -> void:
        var body := StaticBody3D.new()
        body.position = pos
        body.collision_layer = 1
        body.collision_mask = 0
        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        col.shape = shape
        body.add_child(col)
        var mi := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = size
        mi.mesh = mesh
        mi.material_override = _flat_mat(Color("a3703f"), 0.9)
        body.add_child(mi)
        root.add_child(body)
        # cross frame on every visible face reads as "crate" from anywhere
        var frame := Color("6d4523")
        for axis in range(3):
                for sign_i in [-1.0, 1.0]:
                        var bar := MeshInstance3D.new()
                        var bm := BoxMesh.new()
                        if axis == 0:
                                bm.size = Vector3(size.x * 1.02, 0.24 * STUD, 0.24 * STUD)
                                bar.position = Vector3(0.0, 0.0, sign_i * size.z * 0.51)
                        elif axis == 1:
                                bm.size = Vector3(0.24 * STUD, size.y * 1.02, 0.24 * STUD)
                                bar.position = Vector3(sign_i * size.x * 0.51, 0.0, 0.0)
                        else:
                                bm.size = Vector3(0.24 * STUD, 0.24 * STUD, size.z * 1.02)
                                bar.position = Vector3(0.0, sign_i * size.y * 0.51, 0.0)
                        bar.mesh = bm
                        bar.material_override = _flat_mat(frame, 0.9)
                        body.add_child(bar)


static func _cloud(root: Node3D, pos: Vector3, scale: float) -> void:
        # pure decoration cloud — 3-4 white spheres, no collision
        var group := _scaled_group(root, pos)
        var white := Color(1.0, 1.0, 1.0, 1.0)
        var puffs: Array = [
                [Vector3(0, 0, 0), 2.6], [Vector3(2.2, -0.3, 0.6), 2.0],
                [Vector3(-2.1, -0.4, -0.5), 2.1], [Vector3(0.7, 0.8, -0.7), 1.7],
        ]
        for puff in puffs:
                var off: Vector3 = puff[0]
                var r: float = puff[1]
                var ball := MeshInstance3D.new()
                var bm := SphereMesh.new()
                bm.radius = r * scale * 0.22
                bm.height = r * scale * 0.44
                ball.mesh = bm
                var m := _flat_mat(white, 1.0)
                m.roughness = 1.0
                ball.material_override = m
                ball.position = off * scale * 0.35
                group.add_child(ball)


## A vast white cloud-sea far below the islands + big puffs drifting on it,
## like the reference video where every island floats on endless clouds.
static func _cloud_deck(root: Node3D) -> void:
        # built in stud units inside one STUD-scaled group
        var group := _scaled_group(root, Vector3.ZERO)
        var deck := MeshInstance3D.new()
        var dm := BoxMesh.new()
        dm.size = Vector3(900.0, 3.0, 900.0)
        deck.mesh = dm
        var m := _flat_mat(Color("f6fbff"), 1.0)
        deck.material_override = m
        deck.position = Vector3(0.0, -36.5, 0.0)
        deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        group.add_child(deck)
        # deterministic scatter of large puffs riding the deck
        var rng := RandomNumberGenerator.new()
        rng.seed = 20250704
        for i in range(26):
                var ang := rng.randf() * TAU
                var dist := rng.randf_range(55.0, 330.0)
                var pos := Vector3(cos(ang) * dist, rng.randf_range(-34.0, -27.0), sin(ang) * dist)
                _cloud(group, pos, rng.randf_range(9.0, 17.0))


## A WALKABLE cloud platform: solid box (studs on top) hidden under white
## puff spheres so players stand ON a cloud, not on a floating box.
static func _cloudpad(root: Node3D, pos: Vector3, size: Vector2, _tex: ImageTexture) -> void:
        var body := StaticBody3D.new()
        body.position = pos
        body.collision_layer = 1
        body.collision_mask = 0
        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(size.x, 1.2 * STUD, size.y)
        col.shape = shape
        body.add_child(col)
        var top := MeshInstance3D.new()
        var tm := BoxMesh.new()
        tm.size = Vector3(size.x, 1.2 * STUD, size.y)
        top.mesh = tm
        var white := Color("ffffff")
        var m := _flat_mat(white, 1.0)
        top.material_override = m
        body.add_child(top)
        root.add_child(body)
        # puff borders
        var rng := RandomNumberGenerator.new()
        rng.seed = int(pos.x * 7.0 + pos.z * 13.0) + 977
        var perim := int((size.x + size.y) * 0.5 / STUD)
        for i in range(perim * 2):
                var px := lerpf(-size.x * 0.5, size.x * 0.5, rng.randf())
                var pz := lerpf(-size.y * 0.5, size.y * 0.5, rng.randf())
                if absf(px) < size.x * 0.42 and absf(pz) < size.y * 0.42:
                        continue
                var r := rng.randf_range(1.1, 2.0) * STUD
                var ball := MeshInstance3D.new()
                var bm := SphereMesh.new()
                bm.radius = r
                bm.height = r * 2.0
                ball.mesh = bm
                ball.material_override = _flat_mat(white, 1.0)
                ball.position = Vector3(px, rng.randf_range(-0.9, -0.2) * STUD, pz)
                body.add_child(ball)


static func _sign(root: Node3D, pos: Vector3, title: String, body_text: String, board: Vector2, yaw_deg: float, board_color: String, title_color: String) -> void:
        var group := _scaled_group(root, pos)
        group.rotation_degrees.y = yaw_deg
        # two posts
        for sx in [-board.x * 0.38, board.x * 0.38]:
                var post := MeshInstance3D.new()
                var pm := BoxMesh.new()
                pm.size = Vector3(0.5, board.y, 0.5)
                post.mesh = pm
                post.material_override = _flat_mat(Color("4f6f8f"), 0.6)
                post.position = Vector3(sx, 0.0, 0.0)
                group.add_child(post)
        # board
        var board_node := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(board.x, board.y, 0.5)
        board_node.mesh = bm
        var m := _flat_mat(Color(board_color), 0.55)
        board_node.material_override = m
        board_node.position = Vector3(0.0, board.y * 0.75, 0.0)
        group.add_child(board_node)
        # title + body labels (billboarded text on the board face)
        if title != "":
                var title_label := Label3D.new()
                title_label.text = title
                title_label.font_size = 220
                title_label.pixel_size = 0.004
                title_label.outline_size = 18
                title_label.modulate = Color(title_color)
                title_label.outline_modulate = Color("123a44")
                title_label.position = Vector3(0.0, board.y * 1.12, 0.32)
                group.add_child(title_label)
        if body_text != "":
                var body_label := Label3D.new()
                body_label.text = body_text
                body_label.font_size = 120
                body_label.pixel_size = 0.004
                body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
                body_label.modulate = Color("eafcff")
                body_label.outline_size = 8
                body_label.outline_modulate = Color(0.05, 0.15, 0.18, 0.8)
                body_label.position = Vector3(-board.x * 0.44, board.y * 0.72, 0.32)
                group.add_child(body_label)


static func _pipe(root: Node3D, pos: Vector3, h: float, r: float) -> void:
        var green := Color("2ea82e")
        var shaft := StaticBody3D.new()
        shaft.position = pos + Vector3(0.0, h * 0.5, 0.0)
        shaft.collision_layer = 1
        shaft.collision_mask = 0
        var col := CollisionShape3D.new()
        var shape := CylinderShape3D.new()
        shape.height = h
        shape.radius = r
        col.shape = shape
        shaft.add_child(col)
        var mi := MeshInstance3D.new()
        var mesh := CylinderMesh.new()
        mesh.height = h
        mesh.top_radius = r
        mesh.bottom_radius = r
        mi.mesh = mesh
        mi.material_override = _flat_mat(green, 0.55)
        shaft.add_child(mi)
        root.add_child(shaft)
        # rim
        var rim := MeshInstance3D.new()
        var rm := CylinderMesh.new()
        rm.height = 1.2 * STUD
        rm.top_radius = r * 1.16
        rm.bottom_radius = r * 1.16
        rim.mesh = rm
        rim.material_override = _flat_mat(green.darkened(0.05), 0.55)
        rim.position = pos + Vector3(0.0, h - 0.4 * STUD, 0.0)
        root.add_child(rim)


static func _arch(root: Node3D, pos: Vector3, yaw_deg: float) -> void:
        # the NEW GAMES portal: two brick pillars, arch top, sign, blue swirl
        var group := _scaled_group(root, pos)
        group.rotation_degrees.y = yaw_deg
        var brick := Color("c86a2e")
        for sx in [-3.2, 3.2]:
                var pillar := MeshInstance3D.new()
                var pm := BoxMesh.new()
                pm.size = Vector3(1.6, 10.0, 1.6)
                pillar.mesh = pm
                pillar.material_override = _flat_mat(brick, 0.85)
                pillar.position = Vector3(sx, 5.0, 0.0)
                group.add_child(pillar)
        var top := MeshInstance3D.new()
        var tm := BoxMesh.new()
        tm.size = Vector3(8.0, 2.2, 1.8)
        top.mesh = tm
        top.material_override = _flat_mat(brick, 0.85)
        top.position = Vector3(0.0, 10.8, 0.0)
        group.add_child(top)
        var board_mesh := MeshInstance3D.new()
        var sm := BoxMesh.new()
        sm.size = Vector3(5.2, 1.1, 0.5)
        board_mesh.mesh = sm
        board_mesh.material_override = _flat_mat(Color("20232a"), 0.7)
        board_mesh.position = Vector3(0.0, 12.4, 0.0)
        group.add_child(board_mesh)
        var sign_text := Label3D.new()
        sign_text.text = "NEW GAMES"
        sign_text.font_size = 96
        sign_text.pixel_size = 0.006
        sign_text.modulate = Color("7ee0ff")
        sign_text.position = Vector3(0.0, 12.4, 0.3)
        group.add_child(sign_text)
        # the portal surface — glowing blue disc
        var portal := MeshInstance3D.new()
        var pm2 := BoxMesh.new()
        pm2.size = Vector3(5.0, 9.0, 0.3)
        portal.mesh = pm2
        var glow := _flat_mat(Color("1b6fae"), 0.2)
        glow.emission_enabled = true
        glow.emission = Color("2f9ee8")
        glow.emission_energy_multiplier = 1.6
        portal.material_override = glow
        portal.position = Vector3(0.0, 4.6, 0.0)
        group.add_child(portal)


static func _house(root: Node3D, pos: Vector3) -> void:
        # the classic tiny spawn-town house: wood walls, dark roof slab, door
        var group := _scaled_group(root, pos)
        var wall := Color("c9a06a")
        var walls := MeshInstance3D.new()
        var wm := BoxMesh.new()
        wm.size = Vector3(10, 7, 8)
        walls.mesh = wm
        walls.material_override = _flat_mat(wall, 0.9)
        walls.position = Vector3(0.0, 3.5, 0.0)
        group.add_child(walls)
        var roof := MeshInstance3D.new()
        var rm := BoxMesh.new()
        rm.size = Vector3(11.4, 1.4, 9.4)
        roof.mesh = rm
        roof.material_override = _flat_mat(Color("8a2f2f"), 0.85)
        roof.position = Vector3(0.0, 7.7, 0.0)
        group.add_child(roof)
        var door := MeshInstance3D.new()
        var dm := BoxMesh.new()
        dm.size = Vector3(2.2, 4.4, 0.3)
        door.mesh = dm
        door.material_override = _flat_mat(Color("5d3a20"), 0.9)
        door.position = Vector3(0.0, 2.2, 4.05)
        group.add_child(door)
        var knob := MeshInstance3D.new()
        var km := SphereMesh.new()
        km.radius = 0.16
        km.height = 0.32
        knob.mesh = km
        knob.material_override = _flat_mat(Color("ffd400"), 0.4)
        knob.position = Vector3(0.7, 2.2, 4.25)
        group.add_child(knob)
        for wx in [-4.0, 4.0]:
                var window := MeshInstance3D.new()
                var wm2 := BoxMesh.new()
                wm2.size = Vector3(1.8, 1.8, 0.24)
                window.mesh = wm2
                window.material_override = _flat_mat(Color("9ed3f0"), 0.2)
                window.position = Vector3(wx, 4.2, 4.05)
                group.add_child(window)


static func _snow(root: Node3D, pos: Vector3, size: Vector3) -> void:
        var group := _scaled_group(root, pos)
        var mound := MeshInstance3D.new()
        var sm := SphereMesh.new()
        sm.radius = size.x * 0.5
        sm.height = size.y * 2.0
        mound.mesh = sm
        mound.material_override = _flat_mat(Color("f4fbff"), 1.0)
        mound.position = Vector3(0.0, -size.y * 0.35, 0.0)
        group.add_child(mound)


# ---------------------------------------------------------------- materials

## The classic stud: a subtle circle grid, 1 stud per world unit, triplanar.
static func stud_texture() -> ImageTexture:
        if _stud_tex != null and is_instance_valid(_stud_tex):
                return _stud_tex
        var n := 64
        var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
        var base := Color(1.0, 1.0, 1.0)
        var ring := Color(0.86, 0.86, 0.86)
        var face := Color(0.965, 0.965, 0.965)
        var center := float(n) * 0.5
        var radius := float(n) * 0.30
        for y in range(n):
                for x in range(n):
                        var d := Vector2(float(x) + 0.5 - center, float(y) + 0.5 - center).length()
                        if d > radius + 1.0:
                                img.set_pixel(x, y, base)
                        elif d > radius:
                                img.set_pixel(x, y, ring)
                        elif d > radius - 2.0:
                                img.set_pixel(x, y, ring.lerp(face, 0.5))
                        else:
                                img.set_pixel(x, y, face)
        _stud_tex = ImageTexture.create_from_image(img)
        return _stud_tex


static func _flat_mat(color: Color, roughness: float) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = color
        m.roughness = roughness
        return m


static func _part_material(color: Color, kind: String, tex: ImageTexture, no_studs: bool) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        match kind:
                "metal":
                        m.albedo_color = color
                        m.metallic = 0.88
                        m.roughness = 0.32
                        m.metallic_specular = 0.9
                "neon":
                        m.albedo_color = color
                        m.emission_enabled = true
                        m.emission = color
                        m.emission_energy_multiplier = 1.4
                        m.roughness = 0.6
                "wood":
                        m.albedo_color = color.darkened(0.08)
                        m.roughness = 0.92
                _:
                        m.albedo_color = color
                        m.roughness = 0.78
        if kind == "plastic" and not no_studs:
                m.albedo_texture = tex
                m.uv1_triplanar = true
                m.uv1_world_triplanar = true
                # one stud tile per unit = one stud per stud at STUD 1.0
                m.uv1_scale = Vector3.ONE / STUD
                m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        return m


## Ladders look like the classic truss: crossed rails via a dark grid color.
static func _ladder_visual(root: Node3D, pos: Vector3, size: Vector3) -> void:
        var mi := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = size
        mi.mesh = mesh
        var m := StandardMaterial3D.new()
        m.albedo_color = Color("6b6f74")
        m.metallic = 0.75
        m.roughness = 0.45
        mi.material_override = m
        mi.position = pos
        # visually thinner than the climb volume
        mi.scale = Vector3(0.35, 1.0, 0.35)
        root.add_child(mi)


## Spawn pads get the classic silver plate UNDER the creator's pad — a thin
## flat rim, not a slab (a thick rim would bury the black pad on top).
static func _spawn_pad_visual(root: Node3D, pos: Vector3, size: Vector3) -> void:
        var rim := MeshInstance3D.new()
        var rim_mesh := BoxMesh.new()
        rim_mesh.size = Vector3(size.x + 0.4 * STUD, 0.1 * STUD, size.z + 0.4 * STUD)
        rim.mesh = rim_mesh
        var m := StandardMaterial3D.new()
        m.albedo_color = Color("d9dde2")
        m.metallic = 0.6
        m.roughness = 0.4
        rim.material_override = m
        rim.position = pos + Vector3(0.0, size.y * 0.5 + 0.03 * STUD, 0.0)
        root.add_child(rim)
