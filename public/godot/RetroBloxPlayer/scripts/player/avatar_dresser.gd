class_name AvatarDresser
extends RefCounted
## Dresses an AvatarRig with a RetroBlox account avatar, fetched from the
## platform API. The rules are the SAME ones the website renderer follows:
##   - head + arms take the BODY color (skin), torso takes the SHIRT color,
##     legs take the PANTS color
##   - avatar.colors overrides any part exactly (the site's Body Colors panel)
##   - shirt texture: 300x190 template -> zone-cropped onto torso + arms
##   - pants texture: 220x190 template -> zone-cropped onto both legs
##   - face: decal quad on the FRONT of the head (62% of the head at scale 1)
##   - 3D UGC: GLB, normalized to 1.6, placed EXACTLY where its creator left
##     it, creator texture / tint / roughness / metallic applied like the site
##
## Pass api = null for a colors-only dry run (no network) — used by tests
## and by the guest path (which paints classic noob colors instead).

# official clothing template zones (300x190 shirt / 220x190 pants)
const SHIRT_W := 300
const SHIRT_H := 190
const SHIRT_TORSO := Rect2(80, 30, 120, 120)
const SHIRT_ARM_R := Rect2(10, 30, 60, 120)
const SHIRT_ARM_L := Rect2(210, 30, 60, 120)
const PANTS_W := 220
const PANTS_H := 190
const PANTS_LEG_R := Rect2(30, 30, 60, 120)
const PANTS_LEG_L := Rect2(120, 30, 60, 120)

const UGC_IMPORT_SIZE := 1.6     # UGC max dimension before the placement applies
# site placements are authored against the 5-stud rig — ours is 5 studs too,
# so UGC_SCALE is exactly 1.0
const UGC_SCALE := 1.0

# "this surface arrived with no real paint" threshold (raw sRGB ~0.97+)
const PAINT_EPSILON := 0.97

const SKIN_FALLBACK := Color("ffd34e")
const SHIRT_FALLBACK := Color("2e7dc4")
const PANTS_FALLBACK := Color("39516b")


## Dress an AvatarRig node from a payload like:
## { body, head, shirt, pants, accessories: [], colors: {...}|null, faceScale }
## Every network await can outlive the rig (respawn, scene change, remote
## player leaving) — so after EVERY await we re-check the node and quietly
## bail instead of crashing on a previously freed instance.
##
## FAST AVATAR: the four slot JSONs resolve first and the body colors paint
## immediately; then EVERY texture / face / GLB accessory streams in its own
## PARALLEL task — the whole dress takes as long as the slowest single
## download instead of the sum of all of them. Together with the Api caches
## a rejoin or respawn dresses from memory instantly.
static func apply(api, avatar_node, avatar_data: Dictionary) -> void:
        if not _alive(avatar_node):
                return
        var parts: Array = avatar_node.get("parts")
        if parts == null or parts.is_empty():
                return
        var colors: Dictionary = {}
        if avatar_data.get("colors", null) is Dictionary:
                colors = avatar_data["colors"]

        if api == null:
                # colors-only dry run (no network) — classic noob paint
                _paint_colors(avatar_node, colors, SKIN_FALLBACK, SHIRT_FALLBACK, PANTS_FALLBACK)
                return

        # ---- 1) resolve the four slot assets (small JSON round trips) ----
        var body_asset: Dictionary = await api.get_asset(String(avatar_data.get("body", "body_01")))
        var head_asset: Dictionary = await api.get_asset(String(avatar_data.get("head", "head_01")))
        var shirt_asset: Dictionary = await api.get_asset(String(avatar_data.get("shirt", "shirt_01")))
        var pants_asset: Dictionary = await api.get_asset(String(avatar_data.get("pants", "pants_01")))
        if not _alive(avatar_node):
                return

        # ---- 2) paint the body colors RIGHT NOW (identity before textures) ----
        _paint_colors(avatar_node, colors,
                _asset_color(body_asset, SKIN_FALLBACK),
                _asset_color(shirt_asset, SHIRT_FALLBACK),
                _asset_color(pants_asset, PANTS_FALLBACK))

        # ---- 3) stream every surface / face / model in PARALLEL ----
        _paint_shirt(api, avatar_node, shirt_asset)
        _paint_pants(api, avatar_node, pants_asset)
        _paint_face(api, avatar_node, head_asset, float(avatar_data.get("faceScale", 1.0)))
        var accessories: Array = avatar_data.get("accessories", [])
        for acc_id in accessories:
                _apply_accessory(api, avatar_node, String(acc_id))


## The body colors: head + arms = skin, torso = shirt, legs = pants; the
## site's Body Colors panel wins per part.
static func _paint_colors(avatar_node, colors: Dictionary, skin: Color, shirt_color: Color, pants_color: Color) -> void:
        avatar_node.call("set_part_color", avatar_node.get("HEAD"), _pick(colors, "head", skin))
        avatar_node.call("set_part_color", avatar_node.get("TORSO"), _pick(colors, "torso", shirt_color))
        avatar_node.call("set_part_color", avatar_node.get("ARM_L"), _pick(colors, "armL", skin))
        avatar_node.call("set_part_color", avatar_node.get("ARM_R"), _pick(colors, "armR", skin))
        avatar_node.call("set_part_color", avatar_node.get("LEG_L"), _pick(colors, "legL", pants_color))
        avatar_node.call("set_part_color", avatar_node.get("LEG_R"), _pick(colors, "legR", pants_color))


## Shirt texture — zone-crop the 300x190 template onto torso + arms.
static func _paint_shirt(api, avatar_node, shirt_asset: Dictionary) -> void:
        var shirt_url := _asset_image(shirt_asset)
        if shirt_url == "":
                return
        var shirt_img: Image = await api.load_image(shirt_url)
        if not _alive(avatar_node):
                return
        if shirt_img != null:
                var tex := ImageTexture.create_from_image(shirt_img)
                var aspect := float(shirt_img.get_width()) / float(maxf(shirt_img.get_height(), 1.0))
                var template := absf(aspect - float(SHIRT_W) / float(SHIRT_H)) < 0.06
                _textured_part(avatar_node, int(avatar_node.get("TORSO")), tex,
                        SHIRT_TORSO if template else Rect2(), SHIRT_W, SHIRT_H)
                _textured_part(avatar_node, int(avatar_node.get("ARM_R")), tex,
                        SHIRT_ARM_R if template else Rect2(), SHIRT_W, SHIRT_H)
                _textured_part(avatar_node, int(avatar_node.get("ARM_L")), tex,
                        SHIRT_ARM_L if template else Rect2(), SHIRT_W, SHIRT_H)


## Pants texture — zone-crop the 220x190 template onto both legs.
static func _paint_pants(api, avatar_node, pants_asset: Dictionary) -> void:
        var pants_url := _asset_image(pants_asset)
        if pants_url == "":
                return
        var pants_img: Image = await api.load_image(pants_url)
        if not _alive(avatar_node):
                return
        if pants_img != null:
                var tex := ImageTexture.create_from_image(pants_img)
                var aspect := float(pants_img.get_width()) / float(maxf(pants_img.get_height(), 1.0))
                var template := absf(aspect - float(PANTS_W) / float(PANTS_H)) < 0.06
                _textured_part(avatar_node, int(avatar_node.get("LEG_R")), tex,
                        PANTS_LEG_R if template else Rect2(), PANTS_W, PANTS_H)
                _textured_part(avatar_node, int(avatar_node.get("LEG_L")), tex,
                        PANTS_LEG_L if template else Rect2(), PANTS_W, PANTS_H)


## Face decal on the FRONT of the head.
static func _paint_face(api, avatar_node, head_asset: Dictionary, face_scale: float) -> void:
        var face_url := _asset_image(head_asset)
        if face_url == "":
                return
        var face_img: Image = await api.load_image(face_url)
        if not _alive(avatar_node):
                return
        if face_img != null:
                avatar_node.call("set_face", ImageTexture.create_from_image(face_img), face_scale)


## One 3D UGC accessory: GLB, normalized, placed EXACTLY where its creator
## left it. Runs as its own parallel task.
static func _apply_accessory(api, avatar_node, acc_id: String) -> void:
        var asset: Dictionary = await api.get_asset(acc_id)
        if not _alive(avatar_node):
                return
        if not asset.get("ok", false):
                return
        var surface_asset: Dictionary = asset.get("asset", {})
        var model_url := String(surface_asset.get("modelUrl", ""))
        if model_url == "":
                return
        var bytes: PackedByteArray = await api.get_bytes(model_url)
        if not _alive(avatar_node):
                return
        if bytes.is_empty():
                push_warning("[RetroBlox] Could not download model for %s" % acc_id)
                return
        var doc := GLTFDocument.new()
        var state := GLTFState.new()
        var err := doc.append_from_buffer(bytes, "", state)
        if err != OK:
                push_warning("[RetroBlox] GLB parse failed for %s (%d)" % [acc_id, err])
                return
        var scene: Node3D = doc.generate_scene(state) as Node3D
        if scene == null:
                return
        _enable_vertex_colors(scene)
        _normalize(scene, UGC_IMPORT_SIZE)
        var inner := Node3D.new()
        inner.name = "UGC_" + acc_id
        inner.add_child(scene)
        _apply_placement(inner, surface_asset.get("placement", null))
        var holder := Node3D.new()
        holder.name = "UGCScaled_" + acc_id
        holder.scale = Vector3.ONE * UGC_SCALE
        holder.add_child(inner)
        # The website renders its rig FACING +Z (it turns the Blender
        # model around after import); this rig faces -Z. UGC placement
        # is authored in the site's +Z space, so without a correction
        # every item lands MIRRORED — hats read backwards. A 180° yaw
        # wrapper (the same trick loadRig() uses on the site) maps the
        # whole placement — position AND rotation — into this rig's
        # space, so items appear forwards here exactly like the site.
        var yaw := Node3D.new()
        yaw.name = "UGCYaw_" + acc_id
        yaw.rotation.y = PI
        yaw.add_child(holder)
        avatar_node.add_child(yaw)
        # creator texture / tint — THE ROBLOX RULE, DATA WINS
        var tex_url := String(surface_asset.get("textureUrl", ""))
        var tint := String(surface_asset.get("color", ""))
        if tex_url != "":
                var img: Image = await api.load_image(tex_url)
                if not _alive(avatar_node) or not is_instance_valid(scene):
                        return
                if img != null:
                        _surface_texture(scene, ImageTexture.create_from_image(img))
        elif tint != "":
                var paint := Color.from_string(tint, Color.TRANSPARENT)
                if paint != Color.TRANSPARENT and is_instance_valid(scene):
                        _surface_texture(scene, null, paint)
        # creator surface finish — the site's Metallic / Roughness sliders
        var rough_v: Variant = surface_asset.get("roughness", null)
        var metal_v: Variant = surface_asset.get("metallic", null)
        if rough_v != null or metal_v != null:
                _surface_finish(scene, rough_v, metal_v)


# ---------------------------------------------------------------- helpers

## True only when the node still exists — the dressing coroutine can resume
## after its target was freed (respawn / leave / remote despawn).
static func _alive(n: Variant) -> bool:
        # validity FIRST — Godot 4.7 throws "Left operand of 'is' is a
        # previously freed instance" when `is` touches a freed object
        return is_instance_valid(n) and n is Node


static func _textured_part(avatar_node, part_index: int, tex: Texture2D, zone: Rect2, tw: int, th: int) -> void:
        var sizes: Array = avatar_node.get("_part_sizes")
        var size: Vector3 = sizes[part_index]
        var mesh := zone_box(size, zone, tw, th)
        avatar_node.call("set_part_textured", part_index, mesh, tex)


## Build a box mesh whose every face samples `zone` out of a tw x th texture.
## An empty zone means the FULL texture wraps each face.
static func zone_box(size: Vector3, zone: Rect2, tw: int, th: int) -> ArrayMesh:
        var rect := zone
        if rect.size.x <= 0.0 or rect.size.y <= 0.0:
                rect = Rect2(0, 0, tw, th)
        var u0 := rect.position.x / float(tw)
        var v0 := rect.position.y / float(th)
        var u1 := (rect.position.x + rect.size.x) / float(tw)
        var v1 := (rect.position.y + rect.size.y) / float(th)

        var half := size * 0.5
        var faces := [
                [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0)],   # front (-Z)
                [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)],     # back
                [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)],    # right
                [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],    # left
                [Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],      # top
                [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],    # bottom
        ]

        var verts := PackedVector3Array()
        var norms := PackedVector3Array()
        var uvs := PackedVector2Array()
        var indices := PackedInt32Array()

        for face in faces:
                var normal: Vector3 = face[0]
                var u_axis: Vector3 = face[1]
                var v_axis: Vector3 = face[2]
                var center := Vector3(normal.x * half.x, normal.y * half.y, normal.z * half.z)
                var hu := absf(u_axis.x) * half.x + absf(u_axis.y) * half.y + absf(u_axis.z) * half.z
                var hv := absf(v_axis.x) * half.x + absf(v_axis.y) * half.y + absf(v_axis.z) * half.z
                var tl := center - u_axis * hu - v_axis * hv
                var t_r := center + u_axis * hu - v_axis * hv
                var br := center + u_axis * hu + v_axis * hv
                var bl := center - u_axis * hu + v_axis * hv
                var base := verts.size()
                for corner in [tl, t_r, br, bl]:
                        verts.push_back(corner)
                for _i in range(4):
                        norms.push_back(normal)
                for uv in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]:
                        uvs.push_back(uv)
                for idx in [base, base + 3, base + 2, base, base + 2, base + 1]:
                        indices.push_back(idx)

        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = verts
        arrays[Mesh.ARRAY_NORMAL] = norms
        arrays[Mesh.ARRAY_TEX_UV] = uvs
        arrays[Mesh.ARRAY_INDEX] = indices
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        return mesh


static func _asset_color(asset_res: Dictionary, fallback: Color) -> Color:
        var c := "#00000000"
        if asset_res.get("ok", false) and asset_res.get("asset", {}).get("color", "") is String:
                c = asset_res["asset"]["color"]
        if c == "#00000000" or c == "":
                return fallback
        return Color.from_string(c, fallback)


static func _asset_image(asset_res: Dictionary) -> String:
        if asset_res.get("ok", false) and asset_res.get("asset", {}) is Dictionary:
                var url: Variant = asset_res["asset"].get("imageUrl", "")
                return String(url) if url != null else ""
        return ""


static func _pick(colors: Dictionary, key: String, fallback: Color) -> Color:
        if colors.has(key) and String(colors[key]) != "":
                return Color.from_string(String(colors[key]), fallback)
        return fallback


## Normalize a node to max_dimension = size (the same import rule the site uses).
static func _normalize(root: Node3D, size: float) -> void:
        var aabb := _combined_aabb(root)
        if aabb.size.length() < 0.0001:
                return
        var max_dim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
        if max_dim < 0.0001:
                return
        root.scale = Vector3.ONE * (size / max_dim)


static func _combined_aabb(root: Node3D) -> AABB:
        var total := AABB()
        var first := true
        for mi in _all_mesh_instances(root):
                var aabb: AABB = mi.mesh.get_aabb() if mi.mesh else AABB()
                var xform: Transform3D = mi.global_transform if mi.is_inside_tree() else _relative_xform(root, mi)
                aabb = xform * aabb
                if first:
                        total = aabb
                        first = false
                else:
                        total = total.merge(aabb)
        return total


static func _all_mesh_instances(root: Node) -> Array:
        var out := []
        var stack: Array = [root]
        while stack.size() > 0:
                var node: Node = stack.pop_back()
                if node is MeshInstance3D:
                        out.append(node)
                for child in node.get_children():
                        stack.append(child)
        return out


static func _relative_xform(root: Node3D, node: Node3D) -> Transform3D:
        var t := Transform3D()
        var n: Node = node
        while n != null and n != root:
                if n is Node3D:
                        t = (n as Node3D).transform * t
                n = n.get_parent()
        return t


## The creator's placement: p = position, r = degrees, s = scale — applied
## VERBATIM. The platform NEVER auto-fits or repositions UGC.
static func _apply_placement(holder: Node3D, placement: Variant) -> void:
        if placement == null or not (placement is Dictionary):
                return
        var p: Array = placement.get("p", [0, 0, 0])
        var r: Array = placement.get("r", [0, 0, 0])
        var s: Array = placement.get("s", [1, 1, 1])
        if p.size() == 3:
                holder.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
        if r.size() == 3:
                holder.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
        if s.size() == 3:
                holder.scale = Vector3(float(s[0]), float(s[1]), float(s[2]))


## FACE-CORNER DATA: make sure per-vertex colors (Blender vertex paint) show.
static func _enable_vertex_colors(root: Node) -> void:
        for mi in _all_mesh_instances(root):
                if mi.mesh == null:
                        continue
                for surface: int in range(mi.mesh.get_surface_count()):
                        var fmt: int = mi.mesh.surface_get_format(surface)
                        if (fmt & Mesh.ARRAY_FORMAT_COLOR) == 0:
                                continue
                        var mat: Material = mi.get_active_material(surface)
                        if mat is BaseMaterial3D:
                                var bm := mat as BaseMaterial3D
                                if not bm.vertex_color_use_as_albedo:
                                        bm.vertex_color_use_as_albedo = true


## Creator paint with THE ROBLOX RULE — DATA WINS (like SurfaceAppearance).
static func _surface_texture(root: Node, tex: Texture2D, tint := Color.TRANSPARENT) -> void:
        for mi in _all_mesh_instances(root):
                if mi.mesh == null:
                        continue
                for surface: int in range(mi.mesh.get_surface_count()):
                        var mat: Material = mi.get_active_material(surface)
                        var m: BaseMaterial3D = null
                        if mat is BaseMaterial3D:
                                m = (mat as BaseMaterial3D).duplicate()
                        else:
                                m = StandardMaterial3D.new()
                        if tex != null:
                                if m.albedo_texture != null:
                                        continue
                                m.albedo_texture = tex
                                m.albedo_color = Color.WHITE
                        elif tint != Color.TRANSPARENT:
                                if m.albedo_texture != null:
                                        continue
                                var c := m.albedo_color
                                if c.r < PAINT_EPSILON or c.g < PAINT_EPSILON or c.b < PAINT_EPSILON:
                                        continue
                                m.albedo_color = tint
                        else:
                                continue
                        mi.set_surface_override_material(surface, m)


## Creator surface finish (Metallic / Roughness sliders, 0..1) — an explicit
## override beats whatever the GLB carries, on every surface, exactly like
## the website and ItemThumb3D render the same item.
static func _surface_finish(root: Node, roughness_v: Variant, metallic_v: Variant) -> void:
        for mi in _all_mesh_instances(root):
                if mi.mesh == null:
                        continue
                for surface: int in range(mi.mesh.get_surface_count()):
                        var mat: Material = mi.get_active_material(surface)
                        if mat == null or not (mat is BaseMaterial3D):
                                continue
                        var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
                        if roughness_v != null:
                                m.roughness = clampf(float(roughness_v), 0.0, 1.0)
                        if metallic_v != null:
                                m.metallic = clampf(float(metallic_v), 0.0, 1.0)
                        mi.set_surface_override_material(surface, m)
