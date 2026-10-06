extends SceneTree
## Smoke test — validates the whole player without a display or network:
##   1. every script under res://scripts compiles
##   2. the retro theme builds
##   3. every built-in place builds with at least one spawn point
##   4. the avatar rig builds (box mode), paints, animates, takes a face
##   5. the dresser does a colors-only dry run (api = null, no network)
## Run:  Godot --headless --path . -s res://tests/smoke.gd
## Exit code 0 = all good.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")
const PlacesScript := preload("res://scripts/world/places.gd")
const WorldBuilderScript := preload("res://scripts/world/world_builder.gd")


func _initialize() -> void:
        var failures: Array[String] = []

        # ---- 1) compile everything ----
        var scripts := _collect_scripts("res://scripts")
        print("[smoke] compiling %d scripts…" % scripts.size())
        for path in scripts:
                var s: Script = load(path)
                if s == null:
                        failures.append("compile failed: " + path)
                elif not s.can_instantiate():
                        # abstract/utility scripts still compile; can_instantiate can be
                        # false for RefCounted static classes — only fail on null
                        pass
        print("[smoke]   compiled %d scripts, %d failure(s)" % [scripts.size(), failures.size()])

        # ---- 2) theme ----
        var theme: Theme = RetroUI.make_theme()
        if theme == null:
                failures.append("theme build failed")
        else:
                print("[smoke] theme OK (variations: BtnGreen, Card, DarkPanel…)")

        # ---- 3) places ----
        for def in PlacesScript.all():
                var built: Dictionary = WorldBuilderScript.build(def)
                var root: Node3D = built["root"]
                var spawns: Array = built["spawns"]
                var id := String(def["id"])
                if root.get_child_count() == 0:
                        failures.append("place %s built nothing" % id)
                elif spawns.is_empty():
                        failures.append("place %s has no spawn points" % id)
                else:
                        print("[smoke] place %s OK (%d nodes, %d spawns)" % [id, root.get_child_count(), spawns.size()])
                root.free()

        # ---- 4) avatar rig (box mode) ----
        var rig: Node3D = AvatarRigScript.new()
        root.add_child(rig)
        rig.call("setup", "SmokeTest")
        var parts: Array = rig.get("parts")
        if parts.is_empty():
                failures.append("avatar rig built no parts")
        else:
                rig.call("set_part_color", 0, Color("f5cd30"))
                rig.call("set_part_color", 1, Color("0d69ac"))
                var face := _procedural_face()
                rig.call("set_face", ImageTexture.create_from_image(face), 1.0)
                rig.call("animate", 0.016, 8.0, true, false)
                rig.call("animate", 0.016, 0.0, false, false)
                var zone_mesh: Mesh = AvatarDresserScript.zone_box(Vector3(2, 2, 1), Rect2(80, 30, 120, 120), 300, 190)
                if zone_mesh == null:
                        failures.append("zone_box returned null")
                else:
                        rig.call("set_part_textured", 1, zone_mesh, ImageTexture.create_from_image(face))
                print("[smoke] avatar rig OK (parts: %d, r6ik: %s)" % [parts.size(), str(rig.call("is_r6ik"))])

        # ---- 5) dresser dry run (colors only, no network) ----
        var payload := {
                "body": "body_01", "head": "head_01", "shirt": "shirt_01", "pants": "pants_01",
                "accessories": [], "colors": { "torso": "#c0392b", "legL": "#1b6fae" }, "faceScale": 1.0,
        }
        AvatarDresserScript.apply(null, rig, payload)
        var torso_color: Color = (parts[1] as MeshInstance3D).material_override.albedo_color
        if torso_color != Color("c0392b"):
                failures.append("dresser colors-only run did not apply torso color (got %s)" % str(torso_color))
        else:
                print("[smoke] dresser dry run OK (torso -> %s)" % str(torso_color))
        rig.queue_free()

        # ---- verdict ----
        if failures.is_empty():
                print("[smoke] ALL PASS")
                quit(0)
        else:
                for f in failures:
                        printerr("[smoke] FAIL: " + f)
                quit(1)


func _collect_scripts(dir_path: String) -> Array[String]:
        var out: Array[String] = []
        var dir := DirAccess.open(dir_path)
        if dir == null:
                return out
        dir.list_dir_begin()
        var file := dir.get_next()
        while file != "":
                var full := dir_path + "/" + file
                if dir.current_is_dir() and not file.begins_with("."):
                        out.append_array(_collect_scripts(full))
                elif file.ends_with(".gd"):
                        out.append(full)
                file = dir.get_next()
        dir.list_dir_end()
        return out


## A tiny classic smiley so set_face has something real to chew on.
func _procedural_face() -> Image:
        var n := 64
        var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
        for y in range(n):
                for x in range(n):
                        img.set_pixel(x, y, Color(0, 0, 0, 0))
        var eye := Rect2i(14, 20, 8, 12)
        var eye2 := Rect2i(42, 20, 8, 12)
        img.fill_rect(eye, Color.BLACK)
        img.fill_rect(eye2, Color.BLACK)
        for x in range(20, 44):
                var dy := int(sqrt(maxf(0.0, 400.0 - float(x - 32) * float(x - 32))) * 0.35)
                img.set_pixel(x, 38 + dy, Color.BLACK)
                img.set_pixel(x, 39 + dy, Color.BLACK)
        return img
