class_name WorldBuilder
extends RefCounted
## Turns a place definition (a list of parts) into a live 3D world.
##
## Part rules — dictionaries like:
##   { p=[x,y,z] center, s=[sx,sy,sz] size, c="RRGGBB", g="group", m="material" }
## Groups: spawn | kill | ladder | goal | checkpoint | bounce
## Materials: plastic (default) | metal | neon | wood
##
## Everything gets the classic stud texture via world triplanar mapping —
## one stud per unit, tinted by the part color, generated procedurally at
## runtime so the client needs zero texture files.

const StudColorEdge := Color("000000", 0.10)

static var _stud_tex: ImageTexture


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
        env.ambient_light_energy = 1.0
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        var world_env := WorldEnvironment.new()
        world_env.environment = env
        root.add_child(world_env)

        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
        sun.light_energy = 1.15
        sun.shadow_enabled = true
        sun.directional_shadow_max_distance = 180.0
        root.add_child(sun)

        # ---- parts ----
        var spawns: Array[Vector3] = []
        var tex := stud_texture()
        for part in def.get("parts", []):
                var p: Array = part.get("p", [0, 0, 0])
                var s: Array = part.get("s", [4, 1, 4])
                var group: String = part.get("g", "")
                var mat_kind: String = part.get("m", "plastic")
                var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
                var size := Vector3(float(s[0]), float(s[1]), float(s[2]))
                var color := Color(part.get("c", "a3a2a5"))

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
                        continue

                var body := StaticBody3D.new()
                body.position = pos
                body.collision_layer = 1
                body.collision_mask = 0
                var shape_node := CollisionShape3D.new()
                var shape := BoxShape3D.new()
                shape.size = size
                shape_node.shape = shape
                body.add_child(shape_node)

                var mi := MeshInstance3D.new()
                var mesh := BoxMesh.new()
                mesh.size = size
                mi.mesh = mesh
                mi.material_override = _part_material(color, mat_kind, tex, part.get("no_studs", false))
                body.add_child(mi)

                if group != "":
                        body.add_to_group(group)
                if group == "spawn":
                        spawns.append(pos + Vector3(0.0, size.y * 0.5 + 0.2, 0.0))
                        _spawn_pad_visual(root, pos, size)
                if group == "checkpoint":
                        body.set_meta("spawn", pos + Vector3(0.0, size.y * 0.5 + 0.2, 0.0))
                root.add_child(body)

        return { "root": root, "spawns": spawns }


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
                m.uv1_scale = Vector3.ONE
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


## Spawn pads get the classic silver pad + subtle neon rim.
static func _spawn_pad_visual(root: Node3D, pos: Vector3, size: Vector3) -> void:
        var rim := MeshInstance3D.new()
        var rim_mesh := BoxMesh.new()
        rim_mesh.size = size + Vector3(0.3, 0.08, 0.3)
        rim.mesh = rim_mesh
        var m := StandardMaterial3D.new()
        m.albedo_color = Color("d9dde2")
        m.metallic = 0.6
        m.roughness = 0.4
        rim.material_override = m
        rim.position = pos + Vector3(0.0, size.y * 0.5 + 0.02, 0.0)
        root.add_child(rim)
