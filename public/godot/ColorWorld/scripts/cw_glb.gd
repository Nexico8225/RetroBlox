class_name CwGlb
extends RefCounted
## ==================================================================
##  CW GLB — turns an uploaded community map (.glb file, glTF Binary)
##  into a ColorWorld map definition.
## ==================================================================
##
##  THE PIPELINE (all of it, no magic):
##    1. parse the GLB bytes with Godot's built-in GLTFDocument
##    2. walk the parsed scene, collect every MeshInstance3D
##    3. for EACH SURFACE of each mesh: grab its raw arrays and wrap it
##       as { arrays, xf } — the exact shape cw_world._build_part eats
##    4. normalize the scale: maps come from everywhere (meters, feet,
##       centimeters...) so the whole map is resized to a ~50-stud world
##    5. every surface is born WHITE — the paint is the player's job
##
##  Materials, textures and animations of the GLB are INTENTIONALLY
##  thrown away: ColorWorld is white + black outline. That is the game.
## ==================================================================

## Target world size (studs) after normalization.
const TARGET_SIZE := 50.0

static func to_map_def(map_name: String, bytes: PackedByteArray) -> Dictionary:
        var doc := GLTFDocument.new()
        var state := GLTFState.new()
        var err := doc.append_from_buffer(bytes, "", state)
        if err != OK:
                return {}
        var scene_root: Node3D = doc.generate_scene(state)
        if scene_root == null:
                return {}

        # ---- collect every surface of every mesh, with its world transform ----
        var surfaces: Array = []   # [ { arrays, xf } ... ]
        _collect(scene_root, Transform3D.IDENTITY, surfaces)
        if surfaces.is_empty():
                scene_root.free()
                return {}

        # ---- normalize the scale (meters / centimeters / feet -> studs) ----
        var lo := Vector3.INF
        var hi := -Vector3.INF
        for s in surfaces:
                var xf: Transform3D = s["xf"]
                var verts: PackedVector3Array = s["arrays"][Mesh.ARRAY_VERTEX]
                for v in verts:
                        var w: Vector3 = xf * v
                        lo = lo.min(w)
                        hi = hi.max(w)
        var extent := (hi - lo).length()
        if extent <= 0.001:
                scene_root.free()
                return {}
        var k := TARGET_SIZE / extent          # the one scale factor
        var shift := -(lo + hi) * 0.5          # re-center around the origin
        for s in surfaces:
                var xf: Transform3D = s["xf"]
                var scaled := Basis(Vector3.ONE * k) * xf.basis
                var origin := (xf.origin + shift) * k
                s["xf"] = Transform3D(scaled, origin)
                # outline thickness should follow the map's own scale
                s["grow"] = clampf(0.04 * k, 0.015, 0.2)

        scene_root.free()
        return {
                "id": "community",
                "name": map_name,
                "desc": "A community map (uploaded by a player)",
                "sky_top": "3f8fe0",
                "sky_horizon": "cfe6f7",
                "parts": surfaces,
        }

## Depth-first walk: every MeshInstance3D's every surface becomes one entry.
static func _collect(node: Node, parent_xf: Transform3D, out: Array) -> void:
        var xf := parent_xf
        if node is Node3D:
                xf = parent_xf * (node as Node3D).transform
        if node is MeshInstance3D:
                var mi := node as MeshInstance3D
                var mesh := mi.mesh
                if mesh != null:
                        for s in mesh.get_surface_count():
                                var arrays := mesh.surface_get_arrays(s)
                                if arrays[Mesh.ARRAY_VERTEX] == null:
                                        continue
                                out.append({ "arrays": arrays, "xf": xf })
        for child in node.get_children():
                _collect(child, xf, out)
