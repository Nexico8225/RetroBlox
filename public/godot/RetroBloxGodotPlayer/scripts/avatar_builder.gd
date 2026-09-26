# AvatarBuilder — dresses the official R6IK model with a RetroBlox avatar.
#
# The rules are the SAME ones the website and the Unity SDK follow:
#   - head + arms take the BODY color (skin), torso takes the SHIRT color,
#     legs take the PANTS color
#   - avatar.colors overrides any part exactly (the site's Body Colors panel)
#   - shirt texture: 300x190 template -> zone-cropped onto torso + arms
#   - pants texture: 220x190 template -> zone-cropped onto both legs
#   - face: decal on the FRONT of the head (62% of the head at scale 1)
#   - 3D UGC: loaded from GLB, normalized to 1.6 max-dimension, then placed
#     EXACTLY where its creator left it — the platform never moves UGC
class_name AvatarBuilder
extends RefCounted

const RIG_HEIGHT := 5.0        # normalized rig height in world units
const UGC_IMPORT_SIZE := 1.6   # UGC max dimension before the placement applies
const FACE_RATIO := 0.62       # classic face size on the head front

# the same part aliases the website's renderer uses
const PART_ALIASES := {
        "head": ["head"],
        "torso": ["torso"],
        "armL": ["left arm", "leftarm", "arm_l", "l arm"],
        "armR": ["right arm", "rightarm", "arm_r", "r arm"],
        "legL": ["left leg", "leftleg", "leg_l", "l leg"],
        "legR": ["right leg", "rightleg", "leg_r", "r leg"],
}

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


## Find the body part MeshInstance3Ds inside an (instantiated) R6IK scene.
static func find_parts(root: Node) -> Dictionary:
        var parts := {}
        for mi in _all_mesh_instances(root):
                var n := _norm_name(mi.name)
                var gn := _norm_name(String(mi.mesh.get("resource_name")) if mi.mesh else "")
                for key in PART_ALIASES.keys():
                        if parts.has(key):
                                continue
                        for alias in PART_ALIASES[key]:
                                if n == alias or n.begins_with(alias + " ") or n.begins_with(alias + "_") or n.begins_with(alias + "."):
                                        parts[key] = mi
                                        break
                                elif gn != "" and (gn == alias or gn.begins_with(alias + " ") or gn.begins_with(alias + "_")):
                                        parts[key] = mi
                                        break
        return parts


static func _all_mesh_instances(root: Node) -> Array:
        var out := []
        var stack := [root]
        while stack.size() > 0:
                var node: Node = stack.pop_back()
                if node is MeshInstance3D:
                        out.append(node)
                for child in node.get_children():
                        stack.append(child)
        return out


static func _norm_name(name_in: String) -> String:
        var n := name_in.to_lower()
        var out := ""
        for i in n.length():
                var c := n[i]
                if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
                        out += c
                else:
                        out += " "
        return out.strip_edges()


## Paint one mesh a solid color (duplicates the material so instances stay unique).
static func paint(mesh_instance: MeshInstance3D, color: Color) -> void:
        if mesh_instance == null or mesh_instance.mesh == null:
                return
        for surface in mesh_instance.mesh.get_surface_count():
                var mat := mesh_instance.get_active_material(surface)
                if mat is BaseMaterial3D:
                        var m: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
                        m.albedo_texture = null
                        m.albedo_color = color
                        mesh_instance.set_surface_override_material(surface, m)
                else:
                        var m2 := StandardMaterial3D.new()
                        m2.albedo_color = color
                        mesh_instance.set_surface_override_material(surface, m2)


## Texture one mesh (optionally one region of a template via AtlasTexture).
static func texture_part(mesh_instance: MeshInstance3D, tex: Texture2D) -> void:
        if mesh_instance == null or mesh_instance.mesh == null or tex == null:
                return
        for surface in mesh_instance.mesh.get_surface_count():
                var mat := mesh_instance.get_active_material(surface)
                var m: BaseMaterial3D = null
                if mat is BaseMaterial3D:
                        m = (mat as BaseMaterial3D).duplicate()
                else:
                        m = StandardMaterial3D.new()
                m.albedo_texture = tex
                m.albedo_color = Color.WHITE
                mesh_instance.set_surface_override_material(surface, m)


## Apply the full avatar (the payload the platform API returns:
## avatar = { body, head, shirt, pants, accessories: [], colors: {...}|null, faceScale })
static func apply(api: RetrobloxApi, model_root: Node3D, avatar: Dictionary) -> void:
        var parts := find_parts(model_root)
        if parts.is_empty():
                push_warning("[RetroBlox] No body parts found in the rig — check the FBX import.")
                return

        var colors: Dictionary = avatar.get("colors", {}) if avatar.get("colors", null) is Dictionary else {}

        # ---- 1) resolve the four slot assets (colors / images) ----
        var body_asset := await api.get_asset(String(avatar.get("body", "body_01")))
        var head_asset := await api.get_asset(String(avatar.get("head", "head_01")))
        var shirt_asset := await api.get_asset(String(avatar.get("shirt", "shirt_01")))
        var pants_asset := await api.get_asset(String(avatar.get("pants", "pants_01")))

        var skin := _asset_color(body_asset, "#FFD34E")
        var shirt_color := _asset_color(shirt_asset, "#2E7DC4")
        var pants_color := _asset_color(pants_asset, "#39516B")

        # ---- 2) per-part colors (the site's Body Colors panel wins) ----
        var part_color := {
                "head": _pick(colors, "head", skin),
                "torso": _pick(colors, "torso", shirt_color),
                "armL": _pick(colors, "armL", skin),
                "armR": _pick(colors, "armR", skin),
                "legL": _pick(colors, "legL", pants_color),
                "legR": _pick(colors, "legR", pants_color),
        }
        for key in part_color.keys():
                if parts.has(key):
                        paint(parts[key], part_color[key])

        # ---- 3) shirt texture — zone-crop the 300x190 template ----
        var shirt_url := _asset_image(shirt_asset)
        if shirt_url != "" and parts.has("torso"):
                var shirt_img := await api.load_image(shirt_url)
                if shirt_img != null:
                        var aspect := float(shirt_img.get_width()) / float(shirt_img.get_height())
                        var it := ImageTexture.create_from_image(shirt_img)
                        if absf(aspect - float(SHIRT_W) / float(SHIRT_H)) < 0.06:
                                texture_part(parts["torso"], _atlas(it, SHIRT_TORSO, SHIRT_W, SHIRT_H))
                                if parts.has("armR"):
                                        texture_part(parts["armR"], _atlas(it, SHIRT_ARM_R, SHIRT_W, SHIRT_H))
                                if parts.has("armL"):
                                        texture_part(parts["armL"], _atlas(it, SHIRT_ARM_L, SHIRT_W, SHIRT_H))
                        else:
                                # a free-drawn image — the whole texture wraps the torso
                                texture_part(parts["torso"], it)

        # ---- 4) pants texture — zone-crop the 220x190 template ----
        var pants_url := _asset_image(pants_asset)
        if pants_url != "" and (parts.has("legR") or parts.has("legL")):
                var pants_img := await api.load_image(pants_url)
                if pants_img != null:
                        var aspect := float(pants_img.get_width()) / float(pants_img.get_height())
                        var it := ImageTexture.create_from_image(pants_img)
                        if absf(aspect - float(PANTS_W) / float(PANTS_H)) < 0.06:
                                if parts.has("legR"):
                                        texture_part(parts["legR"], _atlas(it, PANTS_LEG_R, PANTS_W, PANTS_H))
                                if parts.has("legL"):
                                        texture_part(parts["legL"], _atlas(it, PANTS_LEG_L, PANTS_W, PANTS_H))

        # ---- 5) the face — decal on the FRONT of the head ----
        var face_url := _asset_image(head_asset)
        if face_url != "" and parts.has("head"):
                var face_img := await api.load_image(face_url)
                if face_img != null:
                        _add_face_decal(parts["head"], ImageTexture.create_from_image(face_img), float(avatar.get("faceScale", 1.0)))

        # ---- 6) 3D UGC accessories — GLB, normalized, placed EXACTLY ----
        var accessories: Array = avatar.get("accessories", [])
        for acc_id in accessories:
                var asset := await api.get_asset(String(acc_id))
                if not asset.get("ok", false):
                        continue
                var model_url := String(asset.get("asset", {}).get("modelUrl", ""))
                if model_url == "":
                        continue  # legacy image-only item — nothing 3D to wear
                var bytes := api.get_bytes(model_url)
                if bytes.is_empty():
                        push_warning("[RetroBlox] Could not download model for %s" % acc_id)
                        continue
                var doc := GLTFDocument.new()
                var state := GLTFState.new()
                var err := doc.append_from_buffer(bytes, "", state)
                if err != OK:
                        push_warning("[RetroBlox] GLB parse failed for %s (%d)" % [acc_id, err])
                        continue
                var scene: Node3D = doc.generate_scene(state) as Node3D
                if scene == null:
                        continue
                _normalize(scene, UGC_IMPORT_SIZE)
                var holder := Node3D.new()
                holder.name = "UGC_" + String(acc_id)
                holder.add_child(scene)
                _apply_placement(holder, asset.get("asset", {}).get("placement", null))
                model_root.add_child(holder)
                # creator texture / tint — texture beats color, exactly like the site
                var surface_asset: Dictionary = asset.get("asset", {})
                var tex_url := String(surface_asset.get("textureUrl", ""))
                var tint := String(surface_asset.get("color", ""))
                if tex_url != "":
                        var img := await api.load_image(tex_url)
                        if img != null:
                                _surface_texture(scene, ImageTexture.create_from_image(img))
                elif tint != "":
                        _surface_texture(scene, null, Color.from_string(tint, Color.WHITE))


# ---------------------------------------------------------------- helpers

static func _asset_color(asset_res: Dictionary, fallback: String) -> Color:
        var c := "#00000000"
        if asset_res.get("ok", false) and asset_res.get("asset", {}).get("color", "") is String:
                c = asset_res["asset"]["color"]
        if c == "#00000000" or c == "":
                return Color.from_string(fallback, Color.WHITE)
        return Color.from_string(c, Color.from_string(fallback, Color.WHITE))


static func _asset_image(asset_res: Dictionary) -> String:
        if asset_res.get("ok", false) and asset_res.get("asset", {}) is Dictionary:
                var url: Variant = asset_res["asset"].get("imageUrl", "")
                return String(url) if url != null else ""
        return ""


static func _pick(colors: Dictionary, key: String, fallback: Color) -> Color:
        if colors.has(key) and String(colors[key]) != "":
                return Color.from_string(String(colors[key]), fallback)
        return fallback


static func _atlas(src: Texture2D, zone: Rect2, tw: int, th: int) -> AtlasTexture:
        var at := AtlasTexture.new()
        at.atlas = src
        at.region = Rect2(zone.position.x, zone.position.y, zone.size.x, zone.size.y)
        return at


## The face decal: a quad hovering just off the head's front surface.
static func _add_face_decal(head_mesh: MeshInstance3D, tex: Texture2D, face_scale: float) -> void:
        var aabb := head_mesh.mesh.get_aabb()
        var max_dim := maxf(aabb.size.x, aabb.size.y)
        var w := max_dim * FACE_RATIO * clampf(face_scale, 0.5, 2.0)
        var quad := MeshInstance3D.new()
        quad.name = "FaceDecal"
        var mesh := QuadMesh.new()
        mesh.size = Vector2(w, w)
        quad.mesh = mesh
        var m := StandardMaterial3D.new()
        m.albedo_texture = tex
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        m.cull_mode = BaseMaterial3D.CULL_DISABLED
        quad.material_override = m
        # the head's front-center point, in the head node's PARENT space
        var front_in_head := Vector3(aabb.get_center().x, aabb.get_center().y, aabb.end.z)
        var front_parent := head_mesh.transform * front_in_head
        front_parent.z += maxf(aabb.size.z, 0.1) * 0.012
        if head_mesh.get_parent():
                head_mesh.get_parent().add_child(quad)
                quad.position = front_parent


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
                var xform := mi.global_transform if mi.is_inside_tree() else _relative_xform(root, mi)
                aabb = xform * aabb
                if first:
                        total = aabb
                        first = false
                else:
                        total = total.merge(aabb)
        return total


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


static func _surface_texture(root: Node, tex: Texture2D, tint := Color.TRANSPARENT) -> void:
        for mi in _all_mesh_instances(root):
                if mi.mesh == null:
                        continue
                for surface in mi.mesh.get_surface_count():
                        var mat := mi.get_active_material(surface)
                        var m: BaseMaterial3D = null
                        if mat is BaseMaterial3D:
                                m = (mat as BaseMaterial3D).duplicate()
                        else:
                                m = StandardMaterial3D.new()
                        if tex != null:
                                m.albedo_texture = tex
                                m.albedo_color = Color.WHITE
                        elif tint != Color.TRANSPARENT:
                                m.albedo_texture = null
                                m.albedo_color = tint
                        mi.set_surface_override_material(surface, m)
