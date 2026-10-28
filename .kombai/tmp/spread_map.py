import re
import shutil
from pathlib import Path

P = Path("public/godot/RetroBloxPlayer/scenes/retroblox.tscn")
BACKUP = Path(".kombai/tmp/retroblox.tscn.orig")
BACKUP.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(P, BACKUP)

src = P.read_text(encoding="utf-8")
lines = src.split("\n")

# ---- index sections -------------------------------------------------------
starts = [i for i, l in enumerate(lines) if l.startswith("[")]
starts.append(len(lines))
sections = []
for a, b in zip(starts, starts[1:]):
    sections.append((a, b))

def sec_kind(a):
    l = lines[a]
    if l.startswith("[node "):
        return "node"
    if l.startswith("[ext_resource"):
        return "ext"
    if l.startswith("[sub_resource"):
        return "sub"
    if l.startswith("[gd_scene") or l.startswith("[gd_resource"):
        return "scene"
    return "other"

def sec_name(a):
    m = re.match(r'\[node name="([^"]+)"', lines[a])
    return m.group(1) if m else ""

def sec_parent(a):
    m = re.match(r'\[node name="[^"]+" type="[^"]+"(?: parent="([^"]*)")?', lines[a])
    return m.group(1) if m and m.group(1) else ""

BUILDING = {"BrickRed", "BrickYellow", "BrickBlue", "BrickGreen", "StepTest05", "StepTest10",
            "StepTest15", "StepTest20", "Stair1", "Stair2", "Stair3", "Stair4", "FortTop",
            "TowerWest", "TowerWestTop", "TowerEast", "TowerEastTop", "SkyBridge",
            "ClimbLadder", "ClimbLadderEast", "SlopeRamp"}
OBBY = {"DamageBrick", "KillBrick", "ObbyStep1", "ObbyStep2", "ObbyStep3", "ObbyStep4",
        "ObbyVictoryPlatform"}

DISTRICT_OFFSET = {
    "BuildingYard": (-96.0, 0.0, -24.0),
    "ObbyCourse": (86.0, 0.0, -52.0),
}

changed = []

# ---- 1. reparent building / obby parts into districts ----------------------
inserted = set()
for a, b in sections:
    if sec_kind(a) != "node":
        continue
    if sec_parent(a) != "World":
        continue
    nm = sec_name(a)
    district = None
    if nm in BUILDING:
        district = "BuildingYard"
    elif nm in OBBY:
        district = "ObbyCourse"
    if district is None:
        continue
    # rewrite parent
    lines[a] = re.sub(r'parent="World"', 'parent="World/%s"' % district, lines[a], count=1)
    # widen the obby spacing inside its new district so jumps are not cramped
    if district == "ObbyCourse":
        for j in range(a + 1, b):
            if lines[j].startswith("transform = Transform3D("):
                vals = [float(v) for v in lines[j][len("transform = Transform3D("):-1].split(",")]
                if len(vals) == 12:
                    vals[9] *= 1.5
                    vals[11] *= 1.35
                    lines[j] = "transform = Transform3D(" + ", ".join(repr(v) for v in vals) + ")"
    changed.append(nm)

# ---- 2. inject district roots right before their first child --------------
def district_block(name):
    ox, oy, oz = DISTRICT_OFFSET[name]
    return [
        '[node name="%s" type="Node3D" parent="World"]' % name,
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %r, %r, %r)" % (ox, oy, oz),
        "",
    ]

out = []
for i, line in enumerate(lines):
    if line.startswith("[node "):
        nm = sec_name(i)
        d = None
        if nm in BUILDING:
            d = "BuildingYard"
        elif nm in OBBY:
            d = "ObbyCourse"
        if d and d not in inserted and sec_parent(i).startswith("World/"):
            out.extend(district_block(d))
            inserted.add(d)
    out.append(line)
lines = out

# ---- 3. safe zone: centre it on spawn and widen the plaza -----------------
for i, l in enumerate(lines):
    if l.startswith('[node name="SafeZone"'):
        for j in range(i, min(i + 6, len(lines))):
            if lines[j].startswith("transform = Transform3D("):
                lines[j] = "transform = Transform3D(2.4, 0, 0, 0, 1, 0, 0, 0, 2.4, 0, 0, 0)"
                break
    if l.startswith('[node name="Playground"'):
        for j in range(i, min(i + 6, len(lines))):
            if lines[j].startswith("transform = Transform3D("):
                lines[j] = "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 58)"
                break
    if l.startswith('[node name="ItemSpawners"'):
        for j in range(i, min(i + 6, len(lines))):
            if lines[j].startswith("transform = Transform3D("):
                lines[j] = "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)"
                break

# ---- 4. add new ext_resources --------------------------------------------
last_ext = max(i for i, l in enumerate(lines) if l.startswith("[ext_resource"))
lines[last_ext + 1:last_ext + 1] = [
    '[ext_resource type="Script" path="res://scripts/world/world_config.gd" id="16_worldcfg"]',
    '[ext_resource type="Script" path="res://scripts/world/plaza_platform.gd" id="17_platform"]',
]

# ---- 5. append new districts ---------------------------------------------
def platform(name, parent, pos, size, color):
    return [
        '[node name="%s" type="StaticBody3D" parent="%s"]' % (name, parent),
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %r, %r, %r)" % pos,
        'script = ExtResource("17_platform")',
        "size = Vector3(%r, %r, %r)" % size,
        "color = Color(%r, %r, %r, 1)" % color,
        "",
    ]

def sign(name, parent, pos, text, size, color):
    return [
        '[node name="%s" type="Label3D" parent="%s"]' % (name, parent),
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %r, %r, %r)" % pos,
        "billboard = 1",
        "modulate = Color(%r, %r, %r, 1)" % color,
        'text = "%s"' % text,
        "font_size = %d" % size,
        "outline_size = 12",
        "",
    ]

def spawner(name, parent, pos, item_type):
    return [
        '[node name="%s" type="StaticBody3D" parent="%s" groups=["item_spawner"]]' % (name, parent),
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %r, %r, %r)" % pos,
        'script = ExtResource("15_spawner")',
        "item_type = %d" % item_type,
        "respawn_cooldown = 1.5",
        "",
    ]

new = []
new += [
    '[node name="WorldConfig" type="Node3D" parent="World"]',
    'script = ExtResource("16_worldcfg")',
    "safe_zone_radius = 26.0",
    "safe_zone_height = 30.0",
    "safe_zone_heal_per_sec = 4.0",
    "safe_zone_clears_effects = true",
    "item_respawn_cooldown = 1.5",
    "override_spawner_cooldowns = true",
    "gear_ring_radius = 16.0",
    "plaza_sign_height = 12.0",
    "",
]

# Food court (south west)
new += ['[node name="FoodCourt" type="Node3D" parent="World"]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -72, 0, 52)", ""]
new += platform("CourtPlatform", "World/FoodCourt", (0, 0.5, 0), (34, 1, 26), (0.96, 0.83, 0.47))
new += sign("CourtSign", "World/FoodCourt", (0, 9.0, 12), "FOOD COURT  -  EAT TO HEAL", 44, (1.0, 0.72, 0.42))
new += spawner("BurgerPad", "World/FoodCourt", (-10, 0.9, -4), 19)
new += spawner("SandwichPad", "World/FoodCourt", (0, 0.9, -4), 20)
new += spawner("ColaPad", "World/FoodCourt", (10, 0.9, -4), 21)
new += spawner("GhostPad", "World/FoodCourt", (-5, 0.9, 6), 18)
new += spawner("SpicyPad", "World/FoodCourt", (5, 0.9, 6), 17)

# Grapple range (south east)
new += ['[node name="GrappleRange" type="Node3D" parent="World"]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 74, 0, 52)", ""]
new += platform("RangeFloor", "World/GrappleRange", (0, 0.5, 0), (36, 1, 30), (0.55, 0.78, 0.9))
new += platform("TowerLow", "World/GrappleRange", (-11, 9.0, -6), (9, 1, 9), (0.75, 0.85, 0.95))
new += platform("TowerMid", "World/GrappleRange", (0, 19.0, 2), (9, 1, 9), (0.78, 0.88, 0.97))
new += platform("TowerHigh", "World/GrappleRange", (11, 31.0, -6), (10, 1, 10), (0.82, 0.9, 0.99))
new += sign("RangeSign", "World/GrappleRange", (0, 6.0, 13), "GRAPPLE RANGE  -  AIM AND CLICK", 42, (0.81, 0.96, 0.53))
new += spawner("GrapplePadA", "World/GrappleRange", (-6, 0.9, 10), 16)
new += spawner("GrapplePadB", "World/GrappleRange", (6, 0.9, 10), 16)

# Combat arena (north)
new += ['[node name="CombatArena" type="Node3D" parent="World"]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -92)", ""]
new += platform("ArenaFloor", "World/CombatArena", (0, 0.5, 0), (54, 1, 44), (0.72, 0.42, 0.42))
new += platform("ArenaWallN", "World/CombatArena", (0, 4.0, -22), (54, 8, 1), (0.55, 0.3, 0.3))
new += platform("ArenaWallS1", "World/CombatArena", (-18, 4.0, 22), (18, 8, 1), (0.55, 0.3, 0.3))
new += platform("ArenaWallS2", "World/CombatArena", (18, 4.0, 22), (18, 8, 1), (0.55, 0.3, 0.3))
new += platform("ArenaWallW", "World/CombatArena", (-27, 4.0, 0), (1, 8, 44), (0.55, 0.3, 0.3))
new += platform("ArenaWallE", "World/CombatArena", (27, 4.0, 0), (1, 8, 44), (0.55, 0.3, 0.3))
new += platform("ArenaPodium", "World/CombatArena", (0, 2.0, -14), (12, 3, 8), (0.85, 0.6, 0.35))
new += sign("ArenaSign", "World/CombatArena", (0, 11.0, 16), "DUEL ARENA  -  SUPER SWORD AND SPICY SAUCE", 42, (1.0, 0.85, 0.35))
new += spawner("SuperSwordPad", "World/CombatArena", (-8, 0.9, 12), 8)
new += spawner("SpicyPadArena", "World/CombatArena", (8, 0.9, 12), 17)
new += spawner("SwordPadArena", "World/CombatArena", (0, 0.9, 12), 5)

lines.extend([""] + new)

P.write_text("\n".join(lines), encoding="utf-8")
print("reparented:", len(changed), sorted(changed))
print("districts injected:", sorted(inserted))
print("new scene bytes:", P.stat().st_size)
