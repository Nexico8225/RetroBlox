# RetroBlox Player (Godot)

The official RetroBlox player for **Godot 4.5+**: sign in (or sign up, or
play as a guest) inside the game, wear your real account avatar, explore
the built-in places, and chat with everyone online through the RetroBlox
platform API. The HUD, the sounds and the places are built to match the
2016-classic reference — with RetroBlox's own UI on top.

> One platform, every engine. Everything here is plain HTTP + JSON against
> `https://retro-blox.vercel.app` — the same API the website and the future
> SDK adapters use.

---

## 1. Just play it

Open this folder in Godot 4.5.1+, let imports finish, press **F5**. No
plugins, no external assets, everything ships in the folder.

- **Log In** — your existing RetroBlox account (same one as the website).
- **Sign Up** — create a new account without leaving the game.
- **Play as Guest** — classic noob colors, `Guest-1234` name, read-only chat.

The game remembers you — next launch signs you in automatically.

### Controls

| Action | Control |
|---|---|
| Move | WASD / arrow keys |
| Jump | Space |
| Orbit / zoom | Mouse + wheel (click the world to re-capture) |
| Shift Lock | **Shift** toggles it live (toast confirms), or the Settings toggle. Locked on, the character squares up to the camera — look right / left / back and the body follows. While locked, ladders are off: you walk straight past them. |
| Jump off a ladder | Space while climbing — you leap off the rungs and can't re-grab for a beat |
| Chat | Enter (or the chat pill button) — Enter sends |
| Menu / Players / Settings | Esc or the pill buttons |

### The HUD (the reference-video layout, original RetroBlox skin)

- **Top-left pill** — RetroBlox logo, menu, chat (with a red unread badge
  while the chat log is collapsed) and players.
- **Right edge** — the vertical **Health** bar with the value chip; it
  drains red as you take fall damage and refills with the classic 1%/s regen.
- **Bottom-center** — your hotbar slot, the **Tix Bag**.
- **Top-center** — black toast pills ("eh_raiderbomber joined you") when
  someone new appears in the place.
- **Chat bubbles** appear over the head of whoever is talking — you too.

### Settings (Esc → Settings)

Everything applies live and persists to `user://retroblox_settings.cfg`:

- Mouse sensitivity, camera FOV
- Master volume, sound-effect volume
- Sun shadows on/off
- Shift-lock default
- **Animations** buttons — pose your character with the rig's own clips
  (Sit / Climb / Walk / Jump / Idle); moving cancels the pose.

### Sounds

All wired through the `SFX` audio bus (so the volume slider hits exactly
these): the authentic Roblox client files — the classic **jump** whoosh,
the **landing thud** after real air time, **plastic footsteps** at the
official 1.85 running pitch, the **climb** loop on ladders, the **wind
loop** in a long fall, the original **uuhhh oof** on death, and
click / hover ticks + a join chime on every UI surface. Buttons get the
sounds automatically — every screen, no wiring needed.

### The places

| Place | What it is |
|---|---|
| **Cloud Kingdom** | THE reference place — floating grass islands over a sea of clouds: gardens, the GLOBAL LEADERBOARD sign, the NEW GAMES portal, My House, trampolines up to walkable clouds, a neon zig-zag, grey steps, a truss climb and a maroon summit with the gold goal. |
| Happy Baseplate | The classic sandbox: brick pile, stairs fort, truss tower, trampoline, metal shed. |
| Classic Obby | Jumps, kill bricks, narrow plank, truss climb, trampoline finish. |
| Skylands | Islands in the sky — bridges, launches, a kill-plank finale. |

Places are pure data (`scripts/world/places.gd`) turned into 3D by
`scripts/world/world_builder.gd`: boxes/cylinders/spheres with the
procedural 1-stud-per-unit texture, plus props (trees, flowers, fences,
crates, clouds, walkable cloud pads, signs, pipes, arches, houses, snow).
Groups make the gameplay: `spawn`, `kill`, `ladder`, `goal`, `checkpoint`,
`bounce`.

### The avatar uses retroblox_anims.fbx

Players wear `assets/models/retroblox_anims.fbx` — the classic block avatar
with real clips baked in: **Idle, Walk, Jump, Climb, Sit**. Walk and Climb
ride the player's speed, the jump clip holds its last frame mid-air. The
matcher accepts any naming (`Head2`, `Left Arm`, `torso_1`...), hides helper
meshes, and falls back to a code-built box rig until the FBX imports.

### 3D UGC appears FORWARDS

The website renders its rig facing +Z; this rig faces -Z (both come from the
same Blender export). Every catalog item is therefore wrapped in a 180° yaw
node in `avatar_dresser.gd` — the same trick the site uses on its own rig —
so placements land 1:1: a hat that reads forwards on the site reads forwards
in-game.

---

## 2. Headless checks

With Godot on PATH (or edit the paths):

```bash
godot --headless --path . -s tests/smoke.gd       # 40+ checks: scripts, places, rig, player, chat, dresser
godot --headless --path . -s tests/check_rig.gd   # rig loads the FBX + clips
```

`tests/screenshot.tscn` renders HUD + world shots to `user://shots/` when
run with a display (or Xvfb).

## 3. The platform API (one HTTP door, any engine)

`scripts/core/api.gd` (autoload `Api`) — the server URL is a constant on
purpose; this player is RetroBlox's own client:

- `POST /api/platform/login` / `signup` — account gate
- `GET  /api/platform/me` — profile + account avatar
- `GET  /api/users/{id}/avatar` — any player's avatar (public)
- `GET  /api/assets/{assetId}` — resolve color / image / GLB model
- `GET  /api/files/{fileId}` — raw asset bytes
- `GET/POST /api/placechat/{placeId}` — chat + presence (the internet relay)

Avatars dress through `scripts/player/avatar_dresser.gd`: body colors,
shirt/pants template zones (300x190 / 220x190), face decal, and 3D UGC from
GLB with the creator's placement applied verbatim (creator texture / tint /
metallic / roughness included — the data-wins rule).
