#!/usr/bin/env python3
"""Publish v6 "UI STUDIO":
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

TEST_DESC = """THE FIRST GAME ON RETROBLOX — STUDIO scenes, ROLES, TOP-DOWN and now the UI STUDIO!

NEW IN V6:
- UI STUDIO (sidebar > UI Studio): the game owner composes a UI EVERY player sees —
  text, icons, images, and buttons that open real links. Click + hover FX: PUNCH,
  BOUNCE, smooth scale-then-rotate, GLOW, FADE — with power and speed dials. Your
  fx mix is YOUR fx. (Personal F2 edits in the player stay private to each user.)
- TWO new top-down places: the DUNGEON (four rooms, checkpoints, lava, a gold
  treasure vault) and the NEON GRID (laser walls, bounce chains, the pink core).
- SEVEN game templates on retro-blox.vercel.app/templates — download, STUDIO >
  OPEN GAME FILE, play, make it yours.
- Downloads now do the classic dance: a bare page opens, the download starts by
  itself, the tab closes.
- The smoke test ships GREEN (SMOKE_OK) — a parse error and a prop-size crash are fixed.

YOU SPAWN IN COLOR WORLD: the world is born WHITE, a 12-color palette sits at the bottom
of your screen, and LEFT CLICK paints any brick you aim at. Paint every part to hear
WORLD COMPLETE! The lighting is VIBRANT.

THE STUDIO (four scenes, one hub):
- PLAY GAME — the world itself, open to everyone.
- UI EDITOR — drag widgets, drop, recolor; game devs only.
- MAP EDITOR — build brick by brick in real 3D.
- PLAYER EDITOR — paint your avatar on your live rig.
The Studio shows your ROLE: GAME DEVS get every editor; PLAYERS get told how to
become one (publish ANY game on retro-blox.vercel.app — a Web game counts!).

DOWNLOADS, LABELED:
- Download Game File = colorworld.retroplace — the GAME FILE. Open it via STUDIO > OPEN GAME FILE.
- Download the SDK (the green button in Source Code) = the complete RetroBlox Player SDK for Godot 4.5+.

Log in, chat with everyone in the place, and make the world YOURS. Published by Nexico8225."""

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
