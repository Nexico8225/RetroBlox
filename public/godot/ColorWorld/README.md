# ColorWorld (Godot) — made with the RetroBlox SDK

Everything is **WHITE with a BLACK outline** — grab your brush, hold the
left mouse button and PAINT THE WORLD. The screen counts how much you
painted, every map gives you **10 hints**, and painting 100% wins.

Built on the **RetroBlox SDK**: the same plain-HTTP API the website uses
(login, Player IDs, community maps, play counters). Nothing here is a
black box — every file is small, commented, and meant to be edited by a
human (or by ChatGPT).

## Run it

1. Install **Godot 4.5+** (free, godotengine.org).
2. Import this folder's `project.godot`, press **F5**. That's it.

## Controls

| Input | Action |
|-------|--------|
| **Hold Left mouse** | paint (each new stroke = a new color) |
| **Right mouse drag** | orbit the camera |
| **Mouse wheel** | zoom |
| **H** (or the button) | hint — 10 per map |
| **< Menu** | back to the menu |

## The files (and what to say to ChatGPT about each)

```
project.godot              the project (autoloads CwApi, main scene)
icon.svg                   the icon
scenes/colorworld.tscn     one node + one script — the game builds itself in code
scripts/
  colorworld.gd            main controller: menu <-> world switching
  cw_menu.gd               the menu: built-in maps, COMMUNITY MAP PLAY, sign-in
  cw_world.gd              THE GAME: white+outline builder, brush, HUD, hints
  cw_maps.gd               the 3 built-in maps as simple part lists
  cw_glb.gd                uploaded .glb maps -> white paintable world
  cw_api.gd                RetroBlox SDK HTTP door (autoload "CwApi")
```

Copy-paste recipes:

- **"Add a bigger brush / more colors"** — edit the constants at the top
  of `cw_world.gd` (`BRUSH_RADIUS`, `PALETTE`).
- **"Add a new built-in map"** — copy a function in `cw_maps.gd`, change
  the parts, add it to `all()`. Parts are `{ "p": [x,y,z], "s": [sx,sy,sz],
  "shape": "box|cyl|sphere" }` in studs.
- **"Change hints to 5"** — `HINTS_PER_MAP` in `cw_world.gd`.
- **"Make the outline thicker"** — the `grow` material in
  `cw_world.add_paintable_surface()`.
- **"Play a sound when I finish"** — fill in `_on_complete()` in
  `colorworld.gd`.

## How it talks to the SDK (`cw_api.gd`)

| Call | Used for |
|------|----------|
| `POST /api/platform/login` | the optional sign-in — you get your **Player ID** (`#1`, `#2`, join order) |
| `GET /api/colormaps` | **COMMUNITY MAP PLAY**: every map players uploaded on the website |
| `GET /api/files/{id}` | downloads the community map's GLB + its placeholder image |
| `POST /api/games/{id}/play` | the play counter on your game's page |

## Community maps

Upload a `.glb` on **retro-blox.vercel.app/colorworld** ("Upload a map"),
then it appears in this game's menu under COMMUNITY MAP PLAY — with the
placeholder image you gave it. Every mesh in the GLB is turned white
with a black outline and becomes paintable; scale is normalized
automatically (meters, centimeters, feet — anything becomes a ~50-stud
world).

## Publish YOUR ColorWorld

1. Zip this folder's contents (`project.godot` at the zip root).
2. retro-blox.vercel.app → **Create** → engine **Godot** → upload it.
3. Upload the same zip as **Source Code** (remixing is the point).
4. Put your game's ids into `GAME_ID` / `GAME_SEQ` in `colorworld.gd`,
   re-zip, re-upload — the play counter and Game ID badge come alive.

> The full RetroBlox SDK (multiplayer player, avatars, chat, more maps)
> lives on the site: **retro-blox.vercel.app/sdk** — download the Player
> SDK zip and everything in this project still applies.
