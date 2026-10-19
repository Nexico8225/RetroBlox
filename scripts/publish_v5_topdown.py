#!/usr/bin/env python3
"""Publish v5 "TOP-DOWN":
1) Test (Game #1): source = the rebuilt RetroBlox Player SDK zip (v5: top-down
   camera mode, Brick Arena place, game-templates exporter) + a description that
   mentions the new /templates page and the top-down place.
   Build stays the colorworld.retroplace game file.
One file per request (Vercel 4.5MB body limit)."""
import requests

BASE = "https://retro-blox.vercel.app"
USER = "Nexico8225"
PASSWORD = "Nexico.2014"
TEST_ID = "cmv9mnnhf0003jm08pua6gzop"

KIT_ZIP = "/home/z/my-project/public/godot/retroblox-godot-player.zip"

TEST_DESC = """THE FIRST GAME ON RETROBLOX — five SCENES in one STUDIO, ROLES, and now TOP-DOWN!

YOU SPAWN IN COLOR WORLD: the world is born WHITE, a 12-color palette sits at the bottom
of your screen, and LEFT CLICK paints any brick you aim at. Paint every part to hear
WORLD COMPLETE! The lighting is VIBRANT — loud saturated bricks, bright sky, the classic look.

NEW IN V5 — TOP-DOWN + TEMPLATES:
- The new BRICK ARENA place plays TOP-DOWN: the camera parks high above you and WASD
  moves on the screen like a board game. Maze, lava, bounce shortcuts, a gold vault.
- The site has a GAME TEMPLATES page: retro-blox.vercel.app/templates — download ready-made
  game files (top-down arena, paint world, obby, baseplate) and open them with STUDIO >
  OPEN GAME FILE. Make your own game from a template today!

THE STUDIO (four scenes, one hub):
- PLAY GAME — the world itself, open to everyone.
- UI EDITOR — DRAG a widget from the shelf, DROP it on the stage, move it, recolor it. SAVE — your widgets spawn in the real game HUD.
- MAP EDITOR — build brick by brick in real 3D: sizes, materials, spawn + kill + ladder + goal + bounce groups. SAVE — your map becomes MY PLACE.
- PLAYER EDITOR — spin your avatar, paint skin / shirt / pants, wear it everywhere.
The Studio shows your ROLE when it opens: GAME DEVS get every editor; PLAYERS get the doors locked — publish ANY game on retro-blox.vercel.app (a Web game counts!) and every editor unlocks on your device.

DOWNLOADS, LABELED:
- Download Game File = colorworld.retroplace — the GAME FILE. Open it via STUDIO > OPEN GAME FILE.
- Download the SDK (the green button in Source Code) = the complete RetroBlox Player SDK for Godot 4.5+ — every script, all scenes, the Studio. THAT is the SDK.

Log in with your RetroBlox account, chat with everyone in the place, collect Tix, and
make the world YOURS. Published by Nexico8225."""

s = requests.Session()
r = s.post(f"{BASE}/api/auth/login", json={"username": USER, "password": PASSWORD}, timeout=60)
r.raise_for_status()
tok = r.json().get("token")
auth = {"Authorization": f"Bearer {tok}"}
print("login ok")


def err(res):
    try:
        return res.json()
    except Exception:
        return res.text[:200]


# Test: new SDK as source, then the description (separate requests)
with open(KIT_ZIP, "rb") as f:
    r = s.patch(
        f"{BASE}/api/games/{TEST_ID}",
        headers=auth,
        files={"sourceFile": ("RetroBlox-Player-SDK-source.zip", f, "application/zip")},
        timeout=300,
    )
print("Test source PATCH:", r.status_code, err(r) if r.status_code >= 300 else "ok")

r = s.patch(
    f"{BASE}/api/games/{TEST_ID}",
    headers=auth,
    data={"description": TEST_DESC},
    timeout=120,
)
print("Test desc PATCH:", r.status_code, err(r) if r.status_code >= 300 else "ok")
