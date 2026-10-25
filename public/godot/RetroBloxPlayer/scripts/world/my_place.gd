class_name MyPlace
extends RefCounted
# Custom place definition helper for building worlds in script.
static func build() -> Dictionary:
        const SAVE_PATH := "user://my_map.json"
        if FileAccess.file_exists(SAVE_PATH):
                var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
                if f != null:
                        var parsed: Variant = JSON.parse_string(f.get_as_text())
                        if typeof(parsed) == TYPE_DICTIONARY:
                                var saved: Dictionary = parsed
                                var raw: Variant = saved.get("parts", [])
                                if typeof(raw) == TYPE_ARRAY and (raw as Array).size() > 0:
                                        var def := template()
                                        def["parts"] = raw
                                        def["props"] = []   # the template's props do not fit YOUR map
                                        def["name"] = "My Place"
                                        def["desc"] = "The map YOU built in the Map Editor."
                                        return def
        return template()


static func template() -> Dictionary:
        return {
                "id": "my_place",
                "name": "My Place (template)",
                "desc": "Edit scripts/world/my_place.gd and make it yours!",
                "tile": "58b64c",           # ground/fog tint
                "sky_top": "3f8fe0",        # sky gradient top
                "sky_horizon": "cfe6f7",    # sky gradient horizon
                "void_y": -40.0,            # fall below y=-40 -> respawn

                # PARTS = solid bricks you can stand on, climb, bounce off...
                "parts": [

                        { "p": [0, -0.5, 0], "s": [80, 1, 80], "c": "58b64c" },

                        { "p": [0, 0.5, 20], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },


                        { "p": [0, 0.5, 10], "s": [4, 1, 4], "c": "e2b23a" },
                        { "p": [0, 1.5, 2],  "s": [4, 1, 4], "c": "e8333f" },
                        { "p": [-6, 2.5, -6], "s": [4, 1, 4], "c": "1b6fae" },
                        { "p": [0, 3.5, -14], "s": [4, 1, 4], "c": "38c172" },

                        { "p": [10, 0.5, 0], "s": [6, 1, 6], "c": "8e44ad", "g": "bounce" },

                        { "p": [0, -0.4, -26], "s": [80, 0.8, 8], "c": "e74c3c", "g": "kill" },
                        { "p": [0, 0.5, -26], "s": [4, 1, 8], "c": "b0562f", "no_studs": true },

                        { "p": [-14, 4, -26], "s": [6, 8, 6], "c": "7f8c8d" },
                        { "p": [-10.8, 4, -26], "s": [0.4, 8, 1], "c": "5d6d7e", "g": "ladder", "no_studs": true },

                        { "p": [-14, 8.5, -26], "s": [4, 1, 4], "c": "ffd700", "m": "metal", "g": "goal" },
                ],

                # PROPS = decorations (the builder assembles them for you)
                "props": [
                        { "type": "sign", "p": [4, 0, 20], "text": "Welcome to MY place!", "yaw": 180 },
                        { "type": "tree", "p": [16, 0, 16] },
                        { "type": "tree", "p": [-20, 0, 8] },
                        { "type": "flower", "p": [8, 0, 12], "c": "e8333f" },
                        { "type": "flower", "p": [-8, 0, 14], "c": "e86bb0" },
                        { "type": "fence", "p": [0, 0, 34], "s": [40, 1.2, 0.3] },
                        { "type": "crate", "p": [6, 0, 6], "s": 2 },
                ],
        }
