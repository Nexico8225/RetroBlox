# RetroBlox Player (Godot)

The official RetroBlox player for **Godot 4.5+**: sign in (or sign up, or
play as a guest) inside the game, spawn STRAIGHT into the classic
baseplate wearing your real account avatar, and chat with everyone online
through the RetroBlox platform API. The HUD, the sounds and the world are
built to match the 2016-classic reference — with RetroBlox's own UI on top.

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
| Chat commands | `/help`, `/e sit`, `/e stop` — local, never sent to the server |
| Menu / Players / Settings | Esc or the pill buttons |

### Cursors — the classic white hand

The player uses the uploaded **RetroBlox Cursor / Pointer** everywhere the
mouse shows, and in first person the pointer parks visibly in the MIDDLE of
the screen so you always know where your aim is. Holding **Space** hops
over and over; 1-2 stud steps are walked over like stairs.

### The HUD (the reference-video layout, original RetroBlox skin)

- **Top-left pill** — RetroBlox logo, menu, chat (with a red unread badge
  while the chat is tucked away) and players.
- The chat starts hidden — ENTER or the chat pill opens the log AND the
  type box together, and closing removes both. Messages said while it is
  hidden stack the badge.
- **Right edge** — the vertical **Health** bar with the value chip; it
  drains red as you take fall damage and refills with the classic 1%/s regen.
- **Top-center** — black toast pills ("eh_raiderbomber joined you") when
  someone new appears in the place.
- **Chat bubbles** appear over the head of whoever is talking — you too.

### Settings (Esc → Settings)

Everything applies live and persists to `user://retroblox_settings.cfg`:

- Mouse sensitivity, camera FOV
- Master volume, sound-effect volume
- Sun shadows on/off, **Fullscreen**
- Shift-lock default
- **Animations** buttons — pose your character with the rig's own clips
  (Sit / Climb / Walk / Jump / Idle); moving cancels the pose.

### Ambience

The sky places add an airy **wind ambience** bed, synthesized in-house —
no copyrighted audio anywhere. (The old music box is retired: the world is
quiet now by popular demand.)

### Sounds

All wired through the `SFX` audio bus (so the volume slider hits exactly
these): the authentic Roblox client files — the classic **jump** whoosh,
the **landing thud** after real air time, **plastic footsteps** at the
official 1.85 running pitch, the **climb** loop on ladders, the **wind
loop** in a long fall, the original **uuhhh oof** on death, and
click / hover ticks + a join chime on every UI surface. Buttons get the
sounds automatically — every screen, no wiring needed.

### Where you spawn

Signing in (or going guest) drops you STRAIGHT into the **Happy
Baseplate** — the classic sandbox with a brick pile, stairs fort, truss
tower, trampoline and metal shed. There is no game-picker anymore: this
player is the starting point for building your own games, so you are in
the world the moment you log in.

More sample places (Cloud Kingdom, Classic Obby, Skylands, Wobbly Tower)
are still defined in `scripts/world/places.gd` as reference material for
builders — load one by id and pass it to `Session.current_place` before
the game scene opens.

Every place is pure data (`scripts/world/places.gd`) turned into 3D by
`scripts/world/world_builder.gd`: boxes/cylinders/spheres with the
procedural 1-stud-per-unit texture, plus props (trees, flowers, fences,
crates, clouds, walkable cloud pads, signs, pipes, arches, houses, snow).
Groups make the gameplay: `spawn`, `kill`, `ladder`, `goal`,
`checkpoint`, `bounce`.

### Feel: dust + sparkles

Little touches that make it play like a real game: **dust puffs** on
takeoffs, hard landings, bounces and respawns; **gold sparkles** idling
above every goal pad. All CPUParticles3D — no shaders, runs on potato PCs.

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
godot --headless --path . -s tests/smoke.gd       # 70+ checks: scripts, places, coins, music, rig, player, chat, dresser
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
