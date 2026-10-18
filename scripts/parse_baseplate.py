#!/usr/bin/env python3
"""Parse scenes/maps/classic_baseplate.tscn and emit the WEB map JSON.

The website is the source of truth for games (one game: Baseplate). This
script converts the hand-built Godot scene into the JSON the seed ships so
the web copy plays EXACTLY like the original scene. Run it again after
editing the .tscn, then paste the output into src/lib/baseplate-map.ts.

Format (all units are studs, 1 Godot unit = 1 stud):
  parts[]   {"name","p":[x,y,z] center,"s":[w,h,d],"color":"#rrggbb"}
  spawns[]  same shape (SpawnLocation pads, default 6x1x6 grey)
  ladders[] same shape (RetroLadder trusses, rungs decorative)
"""
import json
import re
import sys

TSCN = "/home/z/my-project/public/godot/RetroBloxPlayer/scenes/maps/classic_baseplate.tscn"
OUT = "/home/z/my-project/src/lib/baseplate-map.json"

# ext_resource id -> kind
EXT_KIND = {
    "1_part": "part",
    "2_spawn": "spawn",
    "3_ladder": "ladder",
}

# scene-level defaults the scripts apply at runtime
DEFAULTS = {
    "part": {"s": [4.0, 1.0, 2.0], "color": [0.639216, 0.635294, 0.647059]},  # a3a2a5
    "spawn": {"s": [6.0, 1.0, 6.0], "color": [0.639216, 0.635294, 0.647059]},
    "ladder": {"s": [2.0, 12.0, 1.0], "color": [0.388235, 0.4, 0.415686]},    # 63666a
}


def parse_color(text: str):
    nums = [float(n) for n in re.findall(r"-?\d+\.?\d*(?:e-?\d+)?", text)]
    while len(nums) < 4:
        nums.append(1.0)
    return nums[:3]


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c * 255))) for c in rgb)


def parse_tscn(path: str):
    ext_kind = {}
    nodes = []
    current = None
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            m = re.match(r'\[ext_resource type="PackedScene" path="res://scenes/(\w+)\.tscn" id="([^"]+)"\]', line)
            if m:
                scene, eid = m.groups()
                ext_kind[eid] = {"part": "part", "spawn_location": "spawn", "ladder": "ladder"}.get(scene, scene)
                continue
            m = re.match(r'\[node name="([^"]+)"(?: parent="([^"]*)")?(?: instance=ExtResource\("([^"]+)"\))?\]', line)
            if m:
                name, parent, inst = m.groups()
                current = {
                    "name": name,
                    "parent": parent or "",
                    "kind": ext_kind.get(inst) if inst else None,
                    "position": None,
                    "size": None,
                    "color": None,
                }
                if current["kind"]:
                    nodes.append(current)
                continue
            if current is None or current["kind"] is None:
                continue
            m = re.match(r"position = Vector3\(([^)]+)\)", line)
            if m:
                current["position"] = [float(v) for v in m.group(1).split(",")]
                continue
            m = re.match(r"size = Vector3\(([^)]+)\)", line)
            if m:
                current["size"] = [float(v) for v in m.group(1).split(",")]
                continue
            m = re.match(r"color = Color\(([^)]+)\)", line)
            if m:
                current["color"] = parse_color(m.group(1))
                continue
    return nodes


def main() -> int:
    nodes = parse_tscn(TSCN)
    out = {"version": 1, "name": "Baseplate", "parts": [], "spawns": [], "ladders": []}
    for node in nodes:
        kind = node["kind"]
        defaults = DEFAULTS[kind]
        entry = {
            "name": node["name"],
            "p": node["position"] or [0.0, 0.0, 0.0],
            "s": node["size"] or defaults["s"],
            "color": to_hex(node["color"] or defaults["color"]),
        }
        out["ladders" if kind == "ladder" else "spawns" if kind == "spawn" else "parts"].append(entry)

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")

    counts = {k: len(out[k]) for k in ("parts", "spawns", "ladders")}
    print(f"parsed {len(nodes)} nodes -> {OUT}  {counts}")
    if not out["spawns"] or not out["parts"]:
        print("ERROR: map came out empty", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
