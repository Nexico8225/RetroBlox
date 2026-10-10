class_name Places
extends RefCounted
## The built-in places the new player ships with. Part format:
##   { p=[x,y,z], s=[sx,sy,sz], c="RRGGBB", g="spawn|kill|ladder|goal|checkpoint|bounce", m="plastic|metal|neon|wood" }
## Jumps are tuned to the classic physics (WalkSpeed 16 / JumpPower 50):
## a full flat jump clears ~12 studs; kill bricks and gaps stay 6-10 apart.


static func all() -> Array:
        return [cloud_kingdom(), baseplate(), obby(), skylands(), tower()]


static func by_id(id: String) -> Dictionary:
        for def in all():
                if def["id"] == id:
                        return def
        return cloud_kingdom()


## ---------------------------------------------------------------- Cloud Kingdom
## THE reference place — floating grass islands over a sea of clouds, the
## classic spawn pad, gardens, the leaderboard sign, the NEW GAMES portal,
## trampolines up to walkable clouds, a neon zig-zag climb, grey steps and
## a maroon summit with the gold goal. Built 1:1 after the reference video.

static func cloud_kingdom() -> Dictionary:
        return {
                "id": "cloudkingdom",
                "name": "Cloud Kingdom",
                "desc": "Islands above the clouds. Bounce up, cross the zig-zag, plant the flag.",
                "tile": "58b64c",
                "sky_top": "3f8fe0",
                "sky_horizon": "cfe6f7",
                "sky_ground": "b8d4ea",
                "void_y": -45.0,
                "cloud_deck": true,
                "wind": true,
                "parts": [
                        # ---- main island: grass top + layered dirt underside ----
                        { "p": [0, -1, 0], "s": [48, 2, 48], "c": "58b64c" },
                        { "p": [0, -5, 0], "s": [40, 6, 40], "c": "7c5230", "no_studs": true },
                        { "p": [0, -10.5, 0], "s": [28, 5, 28], "c": "6d4426", "no_studs": true },
                        { "p": [0, -16, 0], "s": [15, 6, 15], "c": "5d3a20", "no_studs": true },
                        # classic spawn: grey base + black pad on top (like the video)
                        { "p": [0, 0.5, 6], "s": [9, 1, 9], "c": "a8adb3", "g": "spawn" },
                        { "p": [0, 1.15, 6], "s": [5.6, 0.4, 5.6], "c": "23262b", "no_studs": true },
                        # brown lawn paths crossing the plaza (video's town crosswalks)
                        { "p": [0, 0.06, -2], "s": [10, 0.14, 46], "c": "8a5f3d" },
                        { "p": [-13, 0.06, 7], "s": [22, 0.14, 8], "c": "8a5f3d" },
                        { "p": [14, 0.06, -4], "s": [18, 0.14, 8], "c": "8a5f3d" },
                        # ---- portal island (north) ----
                        { "p": [0, -1, -36], "s": [20, 2, 18], "c": "58b64c" },
                        { "p": [0, -4.5, -36], "s": [16, 5, 14], "c": "7c5230", "no_studs": true },
                        { "p": [0, -9, -36], "s": [10, 4, 10], "c": "5d3a20", "no_studs": true },
                        { "p": [0, 3, -38], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
                        # ---- garden island (east, small) ----
                        { "p": [34, -1, 8], "s": [16, 2, 16], "c": "58b64c" },
                        { "p": [34, -4, 8], "s": [12, 4, 12], "c": "7c5230", "no_studs": true },
                        # striped bridge main -> garden (video's green/cyan/navy stripes)
                        { "p": [17.5, 0, 8], "s": [3, 1, 4], "c": "58b64c" },
                        { "p": [20.5, 0, 8], "s": [3, 1, 4], "c": "38e5e5" },
                        { "p": [23.5, 0, 8], "s": [3, 1, 4], "c": "1c2f8f" },
                        { "p": [26.5, 0, 8], "s": [3, 1, 4], "c": "38e5e5" },
                        # ---- high green island (northeast, reached via clouds) ----
                        { "p": [38, 16, -6], "s": [24, 2, 24], "c": "58b64c" },
                        { "p": [38, 12.5, -6], "s": [18, 5, 18], "c": "7c5230", "no_studs": true },
                        { "p": [38, 8.5, -6], "s": [11, 3, 11], "c": "5d3a20", "no_studs": true },
                        { "p": [38, 17.5, -6], "s": [6, 1, 6], "c": "a8adb3" },
                        { "p": [38, 18.05, -6], "s": [3.6, 0.4, 3.6], "c": "23262b", "g": "checkpoint", "no_studs": true },
                        # grey steps down its south edge (the video's stair look)
                        { "p": [38, 16, 8], "s": [8, 2, 4], "c": "b7bcc2" },
                        { "p": [38, 14, 12], "s": [8, 2, 4], "c": "b7bcc2" },
                        { "p": [38, 12, 16], "s": [8, 2, 4], "c": "b7bcc2" },
                        # ---- maroon summit + THE GOAL (video's dark red platforms) ----
                        { "p": [30, 23, -20], "s": [8, 1, 6], "c": "7e3040" },
                        { "p": [20, 25.5, -24], "s": [7, 1, 6], "c": "8e3547" },
                        { "p": [9, 28, -28], "s": [10, 1, 8], "c": "7e3040" },
                        { "p": [9, 29.2, -28], "s": [4.5, 0.9, 4.5], "c": "ffd700", "m": "metal", "g": "goal" },
                        # ---- the yellow zig-zag (neon slabs up the cliff) ----
                        { "p": [26, 17.6, 0], "s": [4, 0.7, 5], "c": "e8f513", "m": "neon" },
                        { "p": [30, 19.2, -4], "s": [5, 0.7, 4], "c": "e8f513", "m": "neon" },
                        { "p": [26, 20.8, -8], "s": [4, 0.7, 5], "c": "e8f513", "m": "neon" },
                        { "p": [30, 22.4, -13], "s": [5, 0.7, 4], "c": "e8f513", "m": "neon" },
                        # ---- cloud hop path: trampoline -> clouds -> high island ----
                        { "p": [16, 0.6, 14], "s": [7, 1.2, 7], "c": "2f6fd1", "m": "neon", "g": "bounce" },
                        # ---- blue launch pad west (video's dark blue slab) ----
                        { "p": [-14, 0.6, 16], "s": [5, 1.2, 10], "c": "1c2f8f", "m": "neon", "g": "bounce" },
                        # cyan landing platform (video frame 11)
                        { "p": [-20, 7, 26], "s": [12, 1, 12], "c": "38e5e5" },
                        # truss ladder: ground to the cyan platform (the climb!)
                        { "p": [-14.2, 3.6, 22.2], "s": [1.5, 8, 0.6], "c": "6b6f74", "g": "ladder" },
                ],
                "props": [
                        # ---- gardens on the main island ----
                        { "type": "flower", "p": [-6, 0, 2], "c": "e8333f" },
                        { "type": "flower", "p": [-8, 0, 5], "c": "e86bb0" },
                        { "type": "flower", "p": [-5, 0, 8], "c": "ffffff" },
                        { "type": "flower", "p": [6, 0, -2], "c": "e8333f" },
                        { "type": "flower", "p": [8, 0, -6], "c": "e86bb0" },
                        { "type": "flower", "p": [5, 0, -9], "c": "ffffff" },
                        { "type": "flower", "p": [-10, 0, -2], "c": "e86bb0" },
                        { "type": "flower", "p": [9, 0, 10], "c": "e8333f" },
                        # trees
                        { "type": "tree", "p": [-16, 0, -12], "h": 8 },
                        { "type": "tree", "p": [17, 0, -4], "h": 7 },
                        { "type": "tree", "p": [30, 0, 12], "h": 7.5 },
                        { "type": "tree", "p": [6, 0, -42], "h": 7 },
                        { "type": "tree", "p": [-7, 0, -42], "h": 7.5 },
                        # fences along the spawn plaza
                        { "type": "fence", "p": [-10, 0, 12], "s": [12, 1.4, 0.35], "yaw": 0 },
                        { "type": "fence", "p": [12, 0, -12], "s": [12, 1.4, 0.35], "yaw": 90 },
                        # crates + snow + pipe
                        { "type": "crate", "p": [-16, 1.2, 8], "s": [2.4, 2.4, 2.4] },
                        { "type": "crate", "p": [-16, 1.1, 11], "s": [2.2, 2.2, 2.2] },
                        { "type": "crate", "p": [-16, 3.5, 8], "s": [2.0, 2.0, 2.0] },
                        { "type": "snow", "p": [10, 1, 20], "s": [6, 1.6, 6] },
                        { "type": "pipe", "p": [-20, 0, 20], "h": 7, "r": 1.9 },
                        # the GLOBAL LEADERBOARD sign (cyan board, yellow title)
                        { "type": "sign", "p": [-17, 1.2, -4], "yaw": 40,
                                "title": "GLOBAL LEADERBOARD", "title_c": "ffd400",
                                "text": "Nexico8225  01d : 04h : 29m\nRetriBlox    00d : 15h : 24m\nalka__14     00d : 14h : 21m\ncardin624    00d : 12h : 40m\ncheese201    00d : 12h : 39m",
                                "w": 15, "h": 8 },
                        # walkable clouds up to the high island
                        { "type": "cloudpad", "p": [22, 9, 18], "s": [8, 8] },
                        { "type": "cloudpad", "p": [28, 12, 12], "s": [7, 7] },
                        { "type": "cloudpad", "p": [33, 14.6, 4], "s": [7, 7] },
                        { "type": "cloudpad", "p": [36, 16, -2], "s": [7, 7] },
                        # My House — wood box + roof + door + label
                        { "type": "house", "p": [14, 0, -16] },
                        { "type": "sign", "p": [14, 5.6, -13.1], "yaw": 0, "title": "My House", "title_c": "ffffff", "w": 8, "h": 1.6 },
                        # giant RETROBLOX letters board on the garden island (video's big red letters)
                        { "type": "sign", "p": [34, 4.2, 14.5], "yaw": 250, "title": "RETROBLOX", "title_c": "e2231a", "c": "ffffff", "w": 13, "h": 3.4 },
                        # NEW GAMES portal on the north island
                        { "type": "arch", "p": [0, 0, -41], "yaw": 0 },
                        # decor clouds drifting around
                        { "type": "cloud", "p": [-30, 8, -18], "s": 7 },
                        { "type": "cloud", "p": [26, 6, -30], "s": 8 },
                        { "type": "cloud", "p": [-38, 12, 8], "s": 6 },
                        { "type": "cloud", "p": [14, 20, 30], "s": 9 },
                        { "type": "cloud", "p": [-24, 3, 34], "s": 7 },
                        { "type": "cloud", "p": [44, 10, -28], "s": 7 },
                        { "type": "cloud", "p": [0, 26, 8], "s": 10 },
                        # ---- collectible Tix (touch to chime + count) ----
                ],
        }


## ---------------------------------------------------------------- Baseplate
## The classic gray baseplate: bricks to climb, a stairs fort, a truss tower,
## a trampoline and a metal shed. Pure sandbox.

static func baseplate() -> Dictionary:
        return {
                "id": "baseplate",
                "name": "Happy Baseplate",
                "desc": "The classic sandbox. Climb the fort, ride the trampoline, hang out.",
                "tile": "8f8f8f",
                "sky_top": "3d8fd1",
                "sky_horizon": "bfe0f5",
                "void_y": -40.0,
                "parts": [
                        { "p": [0, -0.5, 0], "s": [140, 1, 140], "c": "8f8f8f" },
                        # spawn pads
                        { "p": [0, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
                        { "p": [10, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
                        { "p": [-10, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
                        { "p": [0, 0.5, 10], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
                        # the classic brick pile
                        { "p": [14, 1, 6], "s": [4, 2, 2], "c": "c0392b" },
                        { "p": [18, 1.5, 6], "s": [3, 3, 3], "c": "e2b23a" },
                        { "p": [16, 4.5, 6], "s": [2.4, 3, 2.4], "c": "1b6fae" },
                        # stairs fort (2-stud risers walk right up)
                        { "p": [-18, 1, 0], "s": [6, 2, 6], "c": "a3a2a5" },
                        { "p": [-18, 3, 6], "s": [6, 2, 6], "c": "a3a2a5" },
                        { "p": [-18, 5, 12], "s": [6, 2, 6], "c": "a3a2a5" },
                        { "p": [-18, 7, 18], "s": [6, 2, 6], "c": "a3a2a5" },
                        { "p": [-18, 7.5, 30], "s": [10, 1, 14], "c": "98a1a8" },
                        # truss tower
                        { "p": [24, 9.5, 10], "s": [8, 1, 8], "c": "98a1a8" },
                        { "p": [24, 5, 14.3], "s": [1.5, 10, 0.6], "c": "6b6f74", "g": "ladder" },
                        # trampoline
                        { "p": [-8, 0.5, -14], "s": [6, 1, 6], "c": "2f9e44", "m": "neon", "g": "bounce" },
                        # metal shed (shiny!)
                        { "p": [8, 2, -20], "s": [6, 4, 6], "c": "aab4bd", "m": "metal" },
                        { "p": [8, 4.6, -20], "s": [7, 0.6, 7], "c": "8fa0ac", "m": "metal" },
                ],
                "props": [
                        # ---- collectible Tix ----
                ],
        }


## ---------------------------------------------------------------- Classic Obby
## Jumps, kill bricks, a narrow plank, a truss climb and a trampoline launch
## to the gold goal. Checkpoints keep it friendly.

static func obby() -> Dictionary:
        return {
                "id": "obby",
                "name": "Classic Obby",
                "desc": "Jumps, kill bricks, ladders and a trampoline finish. Reach the gold!",
                "tile": "e2574c",
                "sky_top": "2f7fbf",
                "sky_horizon": "a8d4f0",
                "void_y": -30.0,
                "parts": [
                        # start
                        { "p": [0, 0, 0], "s": [14, 2, 14], "c": "a3a2a5", "g": "spawn" },
                        # hops (tops 2 -> 3 -> 4)
                        { "p": [0, 1, 16], "s": [6, 2, 6], "c": "e2b23a" },
                        { "p": [3, 2, 30], "s": [6, 2, 6], "c": "e2b23a" },
                        { "p": [-3, 3, 44], "s": [6, 2, 6], "c": "e2b23a" },
                        # kill-brick bridge (hop the reds)
                        { "p": [0, 3, 60], "s": [6, 2, 24], "c": "a3a2a5" },
                        { "p": [0, 4.5, 54], "s": [2, 1, 2], "c": "c0392b", "g": "kill" },
                        { "p": [0, 4.5, 60], "s": [2, 1, 2], "c": "c0392b", "g": "kill" },
                        { "p": [0, 4.5, 66], "s": [2, 1, 2], "c": "c0392b", "g": "kill" },
                        # checkpoint one
                        { "p": [0, 3, 80], "s": [10, 2, 10], "c": "98a1a8" },
                        { "p": [0, 4.5, 80], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
                        # narrow plank
                        { "p": [0, 3, 93], "s": [2, 2, 20], "c": "a3a2a5" },
                        # truss climb (from plank top 4 up to platform top 7)
                        { "p": [0, 6, 116], "s": [12, 2, 12], "c": "98a1a8" },
                        { "p": [0, 3.5, 109.8], "s": [1.5, 7, 0.6], "c": "6b6f74", "g": "ladder" },
                        # checkpoint two
                        { "p": [-3, 7.5, 113], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
                        # trampoline launch to the goal island
                        { "p": [3, 7.5, 120], "s": [5, 1, 5], "c": "2f9e44", "m": "neon", "g": "bounce" },
                        { "p": [0, 16, 130], "s": [10, 2, 10], "c": "98a1a8" },
                        # THE GOLD GOAL
                        { "p": [0, 17.5, 130], "s": [5, 1, 5], "c": "ffd700", "m": "metal", "g": "goal" },
                ],
                "props": [
                        # ---- collectible Tix ----
                ],
        }


## ---------------------------------------------------------------- Skylands
## Floating islands over the void. Bridges, a trampoline launch between
## islands and a kill-plank finale.

static func skylands() -> Dictionary:
        return {
                "id": "skylands",
                "name": "Skylands",
                "desc": "Islands in the sky. Do not look down — the void is real.",
                "tile": "4caf50",
                "sky_top": "2a6fb8",
                "sky_horizon": "cfe6f7",
                "void_y": -40.0,
                "wind": true,
                "parts": [
                        # island one (spawn)
                        { "p": [0, 0, 0], "s": [20, 1, 20], "c": "4caf50" },
                        { "p": [0, -2, 0], "s": [16, 3, 16], "c": "795548" },
                        { "p": [0, 0.5, 0], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
                        # wood bridge
                        { "p": [0, 0, 20], "s": [3, 1, 16], "c": "a1665e", "m": "wood" },
                        # island two + checkpoint + trampoline up
                        { "p": [0, 0, 40], "s": [18, 1, 18], "c": "4caf50" },
                        { "p": [0, -2, 40], "s": [14, 3, 14], "c": "795548" },
                        { "p": [-4, 0.5, 40], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
                        { "p": [4, 0.5, 44], "s": [5, 1, 5], "c": "2f9e44", "m": "neon", "g": "bounce" },
                        # island three (metal landing)
                        { "p": [0, 11, 56], "s": [12, 1, 12], "c": "98a1a8" },
                        { "p": [0, 9, 56], "s": [9, 2, 9], "c": "757575", "m": "metal" },
                        { "p": [0, 11.5, 54], "s": [4, 1, 4], "c": "e2b23a", "g": "checkpoint" },
                        # kill plank
                        { "p": [0, 11, 68], "s": [2, 1, 10], "c": "a1665e", "m": "wood" },
                        { "p": [1.7, 11.6, 68], "s": [0.8, 0.5, 10], "c": "c0392b", "g": "kill" },
                        { "p": [-1.7, 11.6, 68], "s": [0.8, 0.5, 10], "c": "c0392b", "g": "kill" },
                        # island four — THE GOLD
                        { "p": [0, 11, 82], "s": [12, 1, 12], "c": "4caf50" },
                        { "p": [0, 9, 82], "s": [9, 2, 9], "c": "795548" },
                        { "p": [0, 11.5, 82], "s": [5, 1, 5], "c": "ffd700", "m": "metal", "g": "goal" },
                ],
                "props": [
                        # ---- collectible Tix ----
                ],
        }


## ---------------------------------------------------------------- Wobbly Tower
## A sunset climb: zig-zag steps over kill bricks, a truss ladder for the
## final pull, a bounce-pad shortcut and the gold goal on the summit.

static func tower() -> Dictionary:
        return {
                "id": "tower",
                "name": "Wobbly Tower",
                "desc": "Zig-zag up the sunset steps, dodge the kill bricks, reach the summit gold.",
                "tile": "b8b8c4",
                "sky_top": "4a3a8f",
                "sky_horizon": "e8895a",
                "sky_ground": "5a3a52",
                "void_y": -30.0,
                "wind": true,
                "parts": [
                        # base island
                        { "p": [0, -1, 0], "s": [22, 2, 22], "c": "8a8a96" },
                        { "p": [0, -4.5, 0], "s": [17, 5, 17], "c": "6d5a63", "no_studs": true },
                        { "p": [0, 0.5, 6], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" },
                        # ---- zig-zag steps up (each rise 2, run 6-8) ----
                        { "p": [0, 2, 13], "s": [5, 1, 5], "c": "c9856a" },
                        { "p": [5, 4, 19], "s": [5, 1, 5], "c": "c9856a" },
                        { "p": [0, 6, 25], "s": [5, 1, 5], "c": "c9856a" },
                        { "p": [-5, 8, 19], "s": [5, 1, 5], "c": "c9856a" },
                        { "p": [0, 10, 13], "s": [6, 1, 6], "c": "98a1a8", "g": "checkpoint" },
                        { "p": [-5, 12, 7], "s": [5, 1, 5], "c": "c9856a" },
                        { "p": [0, 14, 1], "s": [5, 1, 5], "c": "c9856a" },
                        # kill bricks guard the last stretch
                        { "p": [0, 13.2, 6.5], "s": [1.6, 0.8, 1.6], "c": "c0392b", "g": "kill" },
                        { "p": [-2.6, 15.2, 3.4], "s": [1.6, 0.8, 1.6], "c": "c0392b", "g": "kill" },
                        # truss ladder: ledge (top 14) up to the summit deck (top 20)
                        { "p": [4.9, 17, 1], "s": [1.5, 7, 0.6], "c": "6b6f74", "g": "ladder" },
                        # summit deck + THE GOLD
                        { "p": [0, 19.5, 0], "s": [12, 1, 12], "c": "7e3040" },
                        { "p": [0, 20.6, 0], "s": [5, 1, 5], "c": "ffd700", "m": "metal", "g": "goal" },
                        # bounce-pad shortcut from the base to step one-two
                        { "p": [-8, 0.6, -6], "s": [5, 1.2, 5], "c": "2f9e44", "m": "neon", "g": "bounce" },
                ],
                "props": [
                        # flags on the summit corners
                        { "type": "fence", "p": [-4.5, 20, -4.5], "s": [2, 1.4, 0.35], "yaw": 45 },
                        { "type": "fence", "p": [4.5, 20, 4.5], "s": [2, 1.4, 0.35], "yaw": 45 },
                        # the tower's welcome board
                        { "type": "sign", "p": [8, 3, 8], "yaw": 225, "title": "WOBBLY TOWER", "title_c": "ffd400", "text": "20 studs up.\nDo not look down.\nReach the summit gold!", "w": 10, "h": 5 },
                ],
        }
