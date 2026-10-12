# RetroBlox Player (Godot)

The official RetroBlox player for **Godot 4.5+**: sign in (or sign up, or
play as a guest) inside the game, spawn STRAIGHT into the classic
baseplate wearing your real account avatar, and chat with everyone online
through the RetroBlox platform API. v11.0 "BLACK GLASS" — THE OLD LOGIN IS
BACK: the white card, the tilted red tile, the RETROBLOX wordmark, the
Log In / Sign Up tabs and the big CLASSIC GREEN Log In key, sitting on a
real photograph of the classic baseplate. THE ESC MENU IS BLACK GLASS: a
deep translucent-black rounded panel (the game stays live behind it) with
two tabs — People / Settings — wearing REAL internet icon PNGs, the
"In this server" card grid, and the footer keys [L] Leave / [R] Respawn /
[ESC] Resume with Resume in the classic green. GALLERY / REPORT / HELP
are gone. YOUR FACE IS YOUR AVATAR: every headshot in the client is your
ACCOUNT AVATAR from retro-blox.vercel.app — the same payload your 3D
character wears, rendered headshot-style in-engine (PFP == in-game avatar
== the site; the old bundled bacon thumbnail and the Roblox thumbnail API
are deleted for good), and you can still paste ANY image URL
(Settings → MY PICTURE or the editor). Bubbles wrap by REAL font metrics
(text can never spill off the plate) and linger 12 seconds. The character
collides as the REAL R6 hitbox — a 2 x 5 x 1 stud box — and the arm
animations EASE between poses, so climbing and jumping never twitch.
AND YOU CAN EDIT EVERYTHING: press **F2** and the UI Editor opens — click
any element, drag to move it, scale it, edit its text, add your own
labels, zoom the whole UI, then Save; your layout boots with you forever
(user://ui_config.json). The world renders in TRUE colors with the
authentic Roblox studs. Stairs are DOUBLED (walk up 1- AND 2-stud ledges
like stairs), and the renderer ships 4x MSAA + anisotropic filtering so
nothing is blurry.

### Icon + image credits (downloaded from the internet)

- `assets/icons/menu.png` — hamburger glyph, Pixabay (recolored white)
- `assets/icons/settings.png`, `people.png`, `chat.png`, `respawn.png` — Icons8 (iOS Glyph style, white)
- `assets/icons/close.png` — close badge, Pixabay
- `assets/ui/login_backdrop.jpg` — classic baseplate photograph (Reddit)

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
| Shift Lock | **Shift** toggles it live, or the Settings toggle. Locked on, the character squares up to the camera — look right / left / back and the body follows. Ladders still grab when you walk into them (v3.8 fixed the old phase-through). |
| Jump off a ladder | Space while climbing — you leap off the rungs and can't re-grab for a beat |
| Chat | Enter (or the chat pill button) — Enter sends |
| Chat commands | `/help`, `/e sit`, `/e stop` — local, never sent to the server |
| Menu / Players / Settings | Esc opens the menu, **R** also opens it (v3.8; R again inside confirms the reset) — P opens the People tab; **F2 opens the UI EDITOR** |

### Cursors — the classic white hand

The player uses the uploaded **RetroBlox Cursor / Pointer** everywhere the
mouse shows, and in first person the pointer parks visibly in the MIDDLE of
the screen so you always know where your aim is. Holding **Space** hops
over and over; 1-2 stud steps are GLIDED over like stairs — no teleport,
the character eases up the step exactly like Roblox.

### The 2008 look — v11.0
- Every surface: real 9-patch bevel (light TL rim, dark BR rim), SQUARE corners, gray chrome — baked in code (retro_theme.gd)
- One voice: ARIAL (Liberation Sans). The CLASSIC GREEN Log In / primary key. ROBLOX red danger. Classic Roblox blue accent.
- LOGIN: a draggable beveled window (title bar + close X) on a baseplate of studs, folder tabs, WHITE sunken wells, the classic green key
- The window opens COMPACT at 960x600 — never your whole screen
- People cards show LIVE ping + fps; your card wears the classic blue selection frame
- FIXED: the avatarUrl-null crash, the shift-lock race, the HTTP body type error, all editor warnings — the debugger is CLEAN

## The ESC menu — the REAL client panel (v11.0)

The menu is ONE centered dark panel (about 62% of the screen — the game
stays visible behind it) with the client's TOP TABS: People · Settings ·
Gallery · Report · Help, each with its icon, the open tab wearing the
white underline. The People tab carries **Invite Friends** (copies your
invite link), "In this server" with grid/list toggles, and the card grid:
PFP + name + @handle, exactly the real client's cards. The footer is the
reference action row: [L] Leave · [R] Respawn · [ESC] Resume — Resume in
fountain blue with the white key chip. Live FPS/ping/version sit in the
tiny corner chip, bottom-left.

### THE UI EDITOR — press F2, edit EVERYTHING (v11.0)

This client is YOURS. **F2** (or Settings → Edit anything) opens the
editor:

- **Click any element** — topbar, user pill, health bar, chat, toasts —
  and drag it anywhere; the green outline shows your selection.
- **X / Y / Scale** steppers fine-tune it; **Text** edits any button or
  label's words.
- **+ Add Label** drops YOUR OWN text detail anywhere on screen (your
  name, your clan tag, anything), editable + movable + deletable.
- **GLOBAL UI SCALE** zooms the entire client from 0.6× to 1.6×.
- **MY PICTURE (PFP URL)** — paste any image URL (web or data URL) and
  wear it on the topbar pill, your People card and Settings instantly.
- **Save** writes `user://ui_config.json` — your layout boots with you
  every time. **Reset All** wipes back to factory.

### Your face — your PFP, everywhere

The PFP engine wears YOUR picture in this order: the URL YOU set in the
editor (Settings → MY PICTURE), then your account's `avatarUrl` from
retro-blox.vercel.app (loaded at login — the SAME face the website
shows, data URLs decode inline), then the bundled headshot, then the
live Roblox thumbnail API, then the classic smiley. Other players'
site PFPs arrive via `/api/users/<name>/pfp` — everyone wears the face
they chose, not a bacon default.

### The HUD (the real client's chrome)

- **Top-left keys** — three standalone rounded dark squares, the reference
  read: the RetroBlox logo, the hamburger, the chat bubble with the red
  unread badge. Esc and **R** open the menu too; **/** or Enter opens
  the chat.
- **Top-right pill** — your username + the settings gear (opens the menu's
  Settings page), parked exactly where the real client keeps them.
- The chat starts hidden — ENTER, **/** or the chat pill opens the log AND
  the type box together, and closing removes both. Messages said while it
  is hidden stack the badge. The input wears the authentic placeholder:
  "To chat click here or press / key".
- **Bottom-center** — the classic horizontal **Health** bar: green fill,
  the number inside, drains red as you take fall damage and refills with
  the classic 1%/s regen.
- **Top-center** — near-black toast pills ("eh_raiderbomber joined you")
  when someone new appears in the place.
- **Chat bubbles** appear over the head of whoever is talking — you too —
  and they STACK the Roblox way: every message is its own bubble, the
  newest parks just above the head and older ones climb up, up to three
  at a time.
- **Login** — the Roblox sign-in card: a white rounded card (tilted red
  logo tile + RETROBLOX wordmark in bold Arial), sunken gray
  wells, the blue action key, and a deep backdrop with soft color glows.

### Settings (Esc → Settings)

Everything applies live and persists to `user://retroblox_settings.cfg`:

- Mouse sensitivity, camera FOV
- Master volume, sound-effect volume
- Sun shadows on/off, **Fullscreen**
- Shift-lock default
- **Animations** buttons — pose your character with the rig's own clips
  (Sit / Climb / Walk / Jump / Idle); moving cancels the pose.
- **MY PICTURE** — your PFP URL + Apply, or "Use my account picture".
- **EDIT THIS UI** — the F2 editor button + the global UI-scale slider.

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
