class_name MyPlace
extends RefCounted
## ==================================================================
##  MY PLACE — YOUR FIRST RETROBLOX MAP (a living template)
## ==================================================================
##
##  This file IS a working map. Open the game, open the place menu and
##  pick "My Place (template)" to walk around it. Then edit THIS file,
##  press F5, and your changes are live. That is the whole workflow.
##
##  A map is a Dictionary with 5 keys:
##
##      id      unique string (never reuse another place's id!)
##      name    shown in the place menu
##      desc    one line shown under the name
##      sky_*   the sky gradient + the ground fog color (hex, no #)
##      parts   the bricks: a plain Array of Dictionaries
##
##  EVERY BRICK (part):
##      p = [x, y, z]  center position, in STUDS (1 stud = 1 unit)
##      s = [sx, sy, sz]  size in studs (a classic brick is [4, 1.2, 2])
##      c = "RRGGBB"   color, hex WITHOUT the # ("ff0000" = red)
##      g = group      "spawn" | "kill" | "ladder" | "goal" | "checkpoint" | "bounce"
##      m = material   "plastic" (default) | "metal" | "neon" | "wood" | "grass" | "dirt"
##      shape =        "box" (default) | "cyl" | "sphere"
##      no_studs = true   hides the stud bumps (good for thin plates/walls)
##
##  WHAT THE GROUPS DO:
##      spawn       players appear here (make 1-4, spread out)
##      kill        touch = you fall apart (lava!) and respawn
##      ladder      climbable surface
##      goal        touch = win confetti
##      checkpoint  touch = your new respawn point
##      bounce      trampoline — flings you up
##
##  PROPS (decoration the world builder assembles for you) live in their
##  own "props" array next to "parts":
##      { "type": "tree",   "p": [x, y, z] }
##      { "type": "flower", "p": [x, y, z], "c": "e8333f" }
##      { "type": "fence",  "p": [x, y, z], "s": [len, 1.2, 0.3] }
##      { "type": "crate",  "p": [x, y, z], "s": 2 }
##      { "type": "cloud",  "p": [x, y, z], "s": 6 }
##      { "type": "cloudpad", "p": [x, y, z], "s": [w, d] }  (walkable cloud!)
##      { "type": "sign",   "p": [x, y, z], "text": "hello", "face": 180 }
##      { "type": "pipe",   "p": [x, y, z], "h": 6 }
##      { "type": "arch",   "p": [x, y, z] }
##      { "type": "snow",   "p": [x, y, z], "s": [w, h, d] }
##
##  JUMP MATH (WalkSpeed 16 / JumpPower 50, classic tuning):
##      a flat jump clears ~12 studs -> keep gaps 6-10 studs,
##      and 1-2 stud ledges step up automatically like stairs.
## ==================================================================

static func build() -> Dictionary:
        return {
                "id": "my_place",
                "name": "My Place (template)",
                "desc": "Edit scripts/world/my_place.gd and make it yours!",
                "tile": "58b64c",           # ground/fog tint
                "sky_top": "3f8fe0",        # sky gradient top
                "sky_horizon": "cfe6f7",    # sky gradient horizon
                "void_y": -40.0,            # fall below y=-40 -> respawn

                # =================================================================
                # PARTS = solid bricks you can stand on, climb, bounce off...
                # =================================================================
                "parts": [

                        # ---- 1. THE GROUND (always start with this) ----
                        { "p": [0, -0.5, 0], "s": [80, 1, 80], "c": "58b64c" },

                        # ---- 2. SPAWN PADS (players need somewhere to appear) ----
                        { "p": [0, 0.5, 20], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },

                        # ---- 3. (see PROPS below for the welcome sign) ----

                        # ---- 4. A little parkour course (copy these lines!) ----
                        { "p": [0, 0.5, 10], "s": [4, 1, 4], "c": "e2b23a" },
                        { "p": [0, 1.5, 2],  "s": [4, 1, 4], "c": "e8333f" },
                        { "p": [-6, 2.5, -6], "s": [4, 1, 4], "c": "1b6fae" },
                        { "p": [0, 3.5, -14], "s": [4, 1, 4], "c": "38c172" },

                        # ---- 5. A trampoline (bounce group flings you UP) ----
                        { "p": [10, 0.5, 0], "s": [6, 1, 6], "c": "8e44ad", "g": "bounce" },

                        # ---- 6. A lava moat (kill group) + a bridge over it ----
                        { "p": [0, -0.4, -26], "s": [80, 0.8, 8], "c": "e74c3c", "g": "kill" },
                        { "p": [0, 0.5, -26], "s": [4, 1, 8], "c": "b0562f", "no_studs": true },

                        # ---- 7. A climbable ladder tower ----
                        { "p": [-14, 4, -26], "s": [6, 8, 6], "c": "7f8c8d" },
                        { "p": [-10.8, 4, -26], "s": [0.4, 8, 1], "c": "5d6d7e", "g": "ladder", "no_studs": true },

                        # ---- 8. THE GOAL (gold, wins the game) ----
                        { "p": [-14, 8.5, -26], "s": [4, 1, 4], "c": "ffd700", "m": "metal", "g": "goal" },
                ],

                # =================================================================
                # PROPS = decorations (the builder assembles them for you)
                # =================================================================
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
