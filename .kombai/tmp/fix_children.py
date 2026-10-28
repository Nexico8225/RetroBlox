import re
from pathlib import Path

P = Path("public/godot/RetroBloxPlayer/scenes/retroblox.tscn")
lines = P.read_text(encoding="utf-8").split("\n")

MOVED = {
    "BrickRed": "BuildingYard",
    "BrickYellow": "BuildingYard",
    "BrickBlue": "BuildingYard",
    "BrickGreen": "BuildingYard",
    "StepTest05": "BuildingYard",
    "StepTest10": "BuildingYard",
    "StepTest15": "BuildingYard",
    "StepTest20": "BuildingYard",
    "Stair1": "BuildingYard",
    "Stair2": "BuildingYard",
    "Stair3": "BuildingYard",
    "Stair4": "BuildingYard",
    "FortTop": "BuildingYard",
    "TowerWest": "BuildingYard",
    "TowerWestTop": "BuildingYard",
    "TowerEast": "BuildingYard",
    "TowerEastTop": "BuildingYard",
    "SkyBridge": "BuildingYard",
    "ClimbLadder": "BuildingYard",
    "ClimbLadderEast": "BuildingYard",
    "SlopeRamp": "BuildingYard",
    "DamageBrick": "ObbyCourse",
    "KillBrick": "ObbyCourse",
    "ObbyStep1": "ObbyCourse",
    "ObbyStep2": "ObbyCourse",
    "ObbyStep3": "ObbyCourse",
    "ObbyStep4": "ObbyCourse",
    "ObbyVictoryPlatform": "ObbyCourse",
}

fixed = 0
for idx in range(len(lines)):
    line = lines[idx]
    match = re.match(r'^\[node name="[^"]+" type="[^"]+" parent="World/([^"/]+)(/[^"]*)?"', line)
    if not match:
        continue
    root = match.group(1)
    rest = match.group(2) or ""
    district = MOVED.get(root)
    if district is None:
        continue
    old = 'parent="World/' + root + rest + '"'
    new = 'parent="World/' + district + "/" + root + rest + '"'
    lines[idx] = line.replace(old, new)
    fixed += 1

for idx in range(len(lines)):
    if lines[idx].startswith('[node name="Playground"'):
        if not lines[idx + 1].startswith("transform"):
            lines.insert(idx + 1, "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 58)")
            fixed += 1
        break

P.write_text("\n".join(lines), encoding="utf-8")
print("rewritten parent paths + playground transform:", fixed)
