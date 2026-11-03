class_name CwMaps
extends RefCounted
## ==================================================================
##  CW MAPS — the built-in ColorWorld maps.
## ==================================================================
##
##  A map is ONE Dictionary:
##      id / name / desc   shown in the menu
##      sky_top / sky_horizon  the gradient behind the world
##      parts              the bricks (ALL of them get painted white!)
##
##  PART FORMAT (same DSL as the RetroBlox SDK's world builder):
##      p = [x, y, z]  center in studs     s = [sx, sy, sz] size in studs
##      shape = "box" | "cyl" | "sphere"   cyl stands upright, y = height
##
##  Color? You don't pick colors HERE — every part is born WHITE and the
##  PLAYER paints it. That is the whole game!
##
##  Add your own map: copy a function, change the parts, add it to all().

static func all() -> Array:
        return [sunny_village(), robot_park(), space_base()]

static func by_id(id: String) -> Dictionary:
        for def in all():
                if def["id"] == id:
                        return def
        return sunny_village()

## ---------------------------------------------------------------- 1
## A little town: houses with roofs, a pond, trees and a market square.
static func sunny_village() -> Dictionary:
        return {
                "id": "village",
                "name": "Sunny Village",
                "desc": "Houses, a pond and a market square waiting for paint.",
                "sky_top": "3f8fe0",
                "sky_horizon": "cfe6f7",
                "parts": [
                        # the ground
                        { "p": [0, -0.5, 0], "s": [70, 1, 70], "shape": "box" },
                        # house 1 (walls + door + roof)
                        { "p": [-16, 3, -12], "s": [12, 6, 10] },
                        { "p": [-16, 6.8, -12], "s": [13, 1.6, 11], "shape": "cyl" },
                        { "p": [-16, 2, -6.9], "s": [3, 4, 0.4] },
                        # house 2
                        { "p": [10, 2.5, -16], "s": [9, 5, 9] },
                        { "p": [10, 5.6, -16], "s": [10, 1.4, 10], "shape": "cyl" },
                        # house 3
                        { "p": [16, 2, 8], "s": [8, 4, 8] },
                        { "p": [16, 4.6, 8], "s": [9, 1.2, 9], "shape": "cyl" },
                        # the pond
                        { "p": [0, 0.06, 14], "s": [16, 0.3, 12], "shape": "cyl" },
                        # trees (trunk + ball)
                        { "p": [-6, 2, 6], "s": [1.2, 4, 1.2], "shape": "cyl" },
                        { "p": [-6, 5.4, 6], "s": [4.4, 4.4, 4.4], "shape": "sphere" },
                        { "p": [4, 2, -4], "s": [1.2, 4, 1.2], "shape": "cyl" },
                        { "p": [4, 5.4, -4], "s": [4.4, 4.4, 4.4], "shape": "sphere" },
                        { "p": [-24, 2, 10], "s": [1.2, 4, 1.2], "shape": "cyl" },
                        { "p": [-24, 5.4, 10], "s": [4.4, 4.4, 4.4], "shape": "sphere" },
                        # market stalls
                        { "p": [0, 1.5, -2], "s": [6, 0.4, 3] },
                        { "p": [-3.4, 2.8, -2], "s": [0.4, 2.8, 0.4] },
                        { "p": [3.4, 2.8, -2], "s": [0.4, 2.8, 0.4] },
                        { "p": [0, 3.2, -2], "s": [7, 0.4, 4] },
                        { "p": [12, 1.5, 4], "s": [5, 0.4, 3] },
                        { "p": [9.8, 2.6, 4], "s": [0.4, 2.4, 0.4] },
                        { "p": [14.2, 2.6, 4], "s": [0.4, 2.4, 0.4] },
                        # a little bridge over the pond
                        { "p": [0, 0.7, 14], "s": [2.4, 0.4, 16] },
                        { "p": [-1.1, 1.5, 14], "s": [0.3, 1.4, 16] },
                        { "p": [1.1, 1.5, 14], "s": [0.3, 1.4, 16] },
                        # well in the square
                        { "p": [-6, 1, -6], "s": [3, 2, 3], "shape": "cyl" },
                ],
        }

## ---------------------------------------------------------------- 2
## A friendly giant robot in a playground of ramps and gears.
static func robot_park() -> Dictionary:
        return {
                "id": "robotpark",
                "name": "Robot Park",
                "desc": "A giant friendly robot, ramps, gears and a slide.",
                "sky_top": "7ec8f2",
                "sky_horizon": "e8f6ff",
                "parts": [
                        { "p": [0, -0.5, 0], "s": [70, 1, 70] },
                        # THE ROBOT: legs, hips, torso, arms, head, antenna
                        { "p": [-5, 5, -14], "s": [6, 10, 6] },
                        { "p": [5, 5, -14], "s": [6, 10, 6] },
                        { "p": [0, 11, -14], "s": [18, 3, 8] },
                        { "p": [0, 17, -14], "s": [12, 8, 7] },
                        { "p": [-9.5, 16.5, -14], "s": [5, 9, 5] },
                        { "p": [9.5, 16.5, -14], "s": [5, 9, 5] },
                        { "p": [-9.5, 11.5, -14], "s": [4, 2, 4], "shape": "sphere" },
                        { "p": [9.5, 11.5, -14], "s": [4, 2, 4], "shape": "sphere" },
                        { "p": [0, 23, -14], "s": [8, 5, 7] },
                        { "p": [0, 27, -14], "s": [1, 3, 1], "shape": "cyl" },
                        { "p": [0, 29.2, -14], "s": [1.6, 1.6, 1.6], "shape": "sphere" },
                        # eyes + chest dial
                        { "p": [-2, 23.5, -10.4], "s": [1.4, 1.4, 0.5], "shape": "cyl" },
                        { "p": [2, 23.5, -10.4], "s": [1.4, 1.4, 0.5], "shape": "cyl" },
                        { "p": [0, 17, -10.4], "s": [3, 3, 0.6], "shape": "cyl" },
                        # playground: ramp steps up to the hip deck
                        { "p": [12, 1, -6], "s": [6, 2, 6] },
                        { "p": [12, 3, -12], "s": [6, 2, 6] },
                        { "p": [8, 5, -14], "s": [6, 2, 10] },
                        # the slide
                        { "p": [-16, 4, 2], "s": [2.5, 8, 2.5] },
                        { "p": [-19, 3, 6], "s": [9, 0.5, 4] },
                        # gears (fat cylinders)
                        { "p": [18, 2, 8], "s": [4, 1, 4], "shape": "cyl" },
                        { "p": [24, 3, -2], "s": [6, 1, 6], "shape": "cyl" },
                        { "p": [-22, 1.5, -12], "s": [5, 1, 5], "shape": "cyl" },
                        # seesaw + bench
                        { "p": [0, 1.2, 10], "s": [14, 0.4, 2] },
                        { "p": [0, 0.6, 10], "s": [1, 1.2, 1.6] },
                        { "p": [-14, 0.7, 14], "s": [8, 0.4, 2] },
                        { "p": [-17.4, 1.6, 14], "s": [0.4, 1.6, 2] },
                        { "p": [-10.6, 1.6, 14], "s": [0.4, 1.6, 2] },
                ],
        }

## ---------------------------------------------------------------- 3
## A moonbase: rocket, pads, radar dish and floating rocks.
static func space_base() -> Dictionary:
        return {
                "id": "spacebase",
                "name": "Space Base",
                "desc": "A moonbase with a rocket, radar dish and low gravity vibes.",
                "sky_top": "0a1030",
                "sky_horizon": "3a4a80",
                "parts": [
                        # grey moon dust
                        { "p": [0, -0.5, 0], "s": [80, 1, 80] },
                        # launch pad
                        { "p": [0, 0.6, 0], "s": [18, 1.2, 18], "shape": "cyl" },
                        # THE ROCKET: body, nose, fins, legs, window
                        { "p": [0, 10, 0], "s": [7, 18, 7], "shape": "cyl" },
                        { "p": [0, 20.5, 0], "s": [5, 5, 5], "shape": "sphere" },
                        { "p": [0, 25, 0], "s": [2, 4, 2], "shape": "cyl" },
                        { "p": [0, 27.5, 0], "s": [2.5, 2.5, 2.5], "shape": "sphere" },
                        { "p": [4.4, 2.4, 0], "s": [0.8, 4.8, 4] },
                        { "p": [-4.4, 2.4, 0], "s": [0.8, 4.8, 4] },
                        { "p": [0, 2.4, 4.4], "s": [4, 4.8, 0.8] },
                        { "p": [0, 2.4, -4.4], "s": [4, 4.8, 0.8] },
                        { "p": [0, 13, 3.6], "s": [2.4, 2.4, 0.6], "shape": "cyl" },
                        # radar dish
                        { "p": [-20, 1.5, -14], "s": [2, 3, 2], "shape": "cyl" },
                        { "p": [-20, 5, -14], "s": [8, 0.8, 8], "shape": "sphere" },
                        # habitat domes
                        { "p": [16, 2.4, 10], "s": [10, 5, 10], "shape": "sphere" },
                        { "p": [26, 1.4, 2], "s": [6, 3, 6], "shape": "sphere" },
                        # tubes connecting them
                        { "p": [21, 1.4, 6], "s": [10, 1.6, 1.6], "shape": "cyl" },
                        { "p": [21, 1.4, 6], "s": [1.6, 1.6, 10], "shape": "cyl" },
                        # floating rocks (crates? no — boxes in the AIR)
                        { "p": [-8, 9, -22], "s": [4, 2, 4] },
                        { "p": [-14, 13, -26], "s": [3, 1.6, 3] },
                        { "p": [-19, 17, -30], "s": [2, 1.2, 2] },
                        # flag on the summit of the rocks
                        { "p": [-19, 19.5, -30], "s": [0.3, 2.6, 0.3] },
                        { "p": [-17.8, 20.2, -30], "s": [2.2, 1.2, 0.15] },
                        # fuel tanks
                        { "p": [8, 2, -12], "s": [2.4, 4, 2.4], "shape": "cyl" },
                        { "p": [11, 2, -12], "s": [2.4, 4, 2.4], "shape": "cyl" },
                ],
        }
