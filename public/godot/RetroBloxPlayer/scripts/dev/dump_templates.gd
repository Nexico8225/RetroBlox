extends SceneTree
## Dumps the built-in places as downloadable .retroplace game templates.
## Run:  godot --headless --path . --script res://scripts/dev/dump_templates.gd
## Output: /home/z/my-project/public/templates/*.retroplace
## Single source of truth: the SAME data the kit ships (places.gd + MyPlace).

const OUT_DIR := "/home/z/my-project/public/templates"


func _init() -> void:
        var PlacesScript := load("res://scripts/world/places.gd")
        var MyPlaceScript := load("res://scripts/world/my_place.gd")
        DirAccess.make_dir_recursive_absolute(OUT_DIR)

        var defs: Array = [
                PlacesScript.topdown_arena(),
                PlacesScript.topdown_dungeon(),
                PlacesScript.topdown_neon(),
                PlacesScript.obby(),
                PlacesScript.baseplate(),
                PlacesScript.color_world(),
                MyPlaceScript.build(),
        ]
        var names: Array = [
                "top-down-arena.retroplace",
                "top-down-dungeon.retroplace",
                "top-down-neon-grid.retroplace",
                "classic-obby.retroplace",
                "baseplate.retroplace",
                "paint-world.retroplace",
                "my-place.retroplace",
        ]

        for i in defs.size():
                var d: Dictionary = defs[i]
                var out := {
                        "format": "retroblox-place-1",
                        "name": String(d.get("name", "Template")),
                        "desc": String(d.get("desc", "")),
                        "sky_top": String(d.get("sky_top", "3d8fd1")),
                        "sky_horizon": String(d.get("sky_horizon", "bfe0f5")),
                        "sky_ground": String(d.get("sky_ground", "2a5d38")),
                        "parts": d.get("parts", []),
                }
                if String(d.get("cam", "")) != "":
                        out["cam"] = String(d.get("cam"))
                if bool(d.get("paint", false)):
                        out["paint"] = true
                var props: Variant = d.get("props", [])
                if typeof(props) == TYPE_ARRAY and not (props as Array).is_empty():
                        out["props"] = props
                var path := OUT_DIR + "/" + String(names[i])
                var f := FileAccess.open(path, FileAccess.WRITE)
                if f == null:
                        push_error("could not write " + path)
                        continue
                f.store_string(JSON.stringify(out, "  "))
                f.close()
                print("WROTE %s (%d parts)" % [path, (out["parts"] as Array).size()])

        quit(0)
