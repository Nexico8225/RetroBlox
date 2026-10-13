# RetroBlox Player (Godot)

The official RetroBlox player for **Godot 4.5+**: sign in (or sign up, or
play as a guest) inside the game, spawn STRAIGHT into the classic
baseplate wearing your real account avatar, and chat with everyone online
through the RetroBlox platform API. v12.2 "THE OLD FRONT DOOR" — THE CLIENT GOES
DARK RETRO: the ESC menu is a deep translucent SLATE panel (the 2012
client's read — dark, calm, NOTHING blinding) with light ink everywhere so
every option stays readable, the BLUE GLOSS header strip (logo + RETROBLOX
+ live clock), folder tabs wearing REAL internet icon PNGs, the three GLOSS
keys — red Leave, steel Respawn, green Resume — and the IDENTITY BLOCK:
the menu opens on YOUR AVATAR, the full-body render of the exact look your
rig wears (320x448, 4x MSAA), with your SITE PFP badged on its
bottom-right corner. THE REAL PLAYER-PROFILE PFP: everyone's face loads
from retro-blox.vercel.app — GET /api/users/{id}/pfp — and accounts
without an upload wear the DEFAULT PFP, the site's letter avatar (your
initial on your stable color), exactly what the website gives new
accounts; your own custom URL (Settings → MY PICTURE) still wins. CHAT
LINES WEAR THE PFP: every line leads with the speaker's site picture +
their name in the classic bright palette on the dark glass float, and the
type box is ALWAYS visible — click it to type, click off (or ESC) and the
keyboard goes back to the game. THE THREE-LINE BUTTON IS GONE and the
UI editor is off the chat. THE HEALTH BAR IS VERTICAL on the right edge.
TILES + LIST views both work. LOG OUT lives in Settings → ACCOUNT.
Bubbles wrap by REAL font metrics (text can never spill off the plate)
and linger 12 seconds. The character collides as the REAL R6 hitbox —
a 2 x 5 x 1 stud box — and the arm animations EASE between poses, so
climbing and jumping never twitch. MORE SETTINGS: Show FPS, Show ping,
Maximum FPS (Unlimited/30/60/120/240, applied live), See player names,
Bunny hop (hold Space to keep bouncing), and RESET ALL SETTINGS — one red
key back to factory. The FPS/ping/version chip rides bottom-left ALWAYS
ON, and each stat hides when you say so. The world renders in TRUE colors
with the authentic Roblox studs. Stairs are DOUBLED (walk up 1- AND 2-stud
ledges like stairs), and the renderer ships 4x MSAA + anisotropic
filtering so nothing is blurry.

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

### The old front door — v12.2
- The chrome goes DARK RETRO: translucent slate surfaces (retro_theme.gd `NIGHT_*`), light ink, the SAME blue gloss chrome + green/red gloss keys — nothing blinds, everything reads
- The ESC menu: dark slate panel (translucent — the game breathes through), blue gloss header, folder tabs, dark People cards, gloss footer keys
- The IDENTITY BLOCK: your full-body avatar render + your site PFP badge (bottom-right corner) + name/@handle/live stats
- The chat is the dark glass float again; every line leads with the speaker's PFP; the type box is ALWAYS visible (click to type, click off to release)
- The health bar is VERTICAL on the right edge — navy track, green fill climbing from the bottom, the number chip on top
- The stats chip (FPS · ping · v12.2) is always on, bottom-left, dark
- One voice: ARIAL (Liberation Sans). The window opens COMPACT at 960x600

## The ESC menu — the RETRO NIGHT panel (v12.2)

The menu is ONE centered translucent slate card (about 64% of the screen —
the game stays visible behind it under a deep veil) with the site's BLUE
GLOSS header strip: the tilted red tile, the RETROBLOX wordmark and the
live session clock. The folder tabs — People · Settings — wear the REAL
internet icon PNGs; the open tab is the blue gloss with white ink. The
People page opens on the IDENTITY BLOCK — YOUR AVATAR, the full-body
render of the exact payload your rig wears, your SITE PFP badged on its
bottom-right corner, name + @handle + live FPS/ping beside it — then "In
this server" with the TILES / LIST view toggles (the active one glows
blue): tiles = the 3-wide card grid (PFP + name + @handle + live
ping/fps, your card wearing the classic blue ring), list = compact rows.
The footer is the site's own button trio: red Leave · steel Respawn ·
green Resume, each with the white key chip.

### MORE SETTINGS (v12.0) + ACCOUNT (v12.2)

- **PERFORMANCE** — Show FPS, Show ping (each hides its part of the stats
  chip live) and MAXIMUM FPS: Unlimited / 30 / 60 / 120 / 240, applied
  the moment you click (Engine.max_fps).
- **CHARACTER** — See player names (the nameplates above every avatar,
  yours and everyone's) and Bunny hop (hold Space to keep bouncing — the
  classic read; off means one jump per press).
- **RESET ALL SETTINGS** — the red gloss key: every option back to
  default, applied and saved, the page rebuilt in front of you.
- **ACCOUNT** — who is signed in, and the red **Log Out** key: the saved
  token is wiped and you land on the old login page.

### THE UI EDITOR — press F2 (power users)

The editor still lives behind **F2**: click any element (topbar, user
pill, health bar, toasts — the chat is OFF the editor now), drag to move,
scale, edit text, add your own labels, Save to `user://ui_config.json`.
The Settings page entry is gone (v12.2) — F2 is the door.

### Your face — your PFP, everywhere

The PFP engine wears the SITE'S OWN RULES, in this order: the URL YOU set
in Settings → MY PICTURE (wins over everything), then your account's
`avatarUrl` from retro-blox.vercel.app (loaded at login — the SAME face
the website shows, data URLs decode inline), then the DEFAULT PFP — the
site's letter avatar, your initial on your stable color, drawn in code
with the site's exact palette. Everyone else's face comes from the public
`GET /api/users/{id}/pfp` the same way: their upload if they set one, the
default letter avatar if they did not — exactly what the website shows
for them. Chat lines, cards, the topbar pill and the identity block's
badge all wear it; the 3D render lives only in the identity block, where
YOUR AVATAR is photographed full-body.

### The HUD (the real client's chrome)

- **Top-left keys** — TWO standalone rounded dark squares, the classic
  read: the RetroBlox logo and the chat bubble with the red unread badge
  (the three-line button is GONE). Esc and **R** open the menu too;
  **/** or Enter opens the chat.
- **Top-right pill** — your PFP + username + the settings gear (opens the
  menu's Settings page), parked exactly where the real client keeps them.
- The chat's TYPE BOX is ALWAYS visible — click it and you are typing
  (the log un-hides); CLICK OFF anywhere and the keyboard goes back to
  the game; ESC closes too. Messages said while the log is hidden stack
  the badge. Every line leads with the speaker's PFP. The input wears the
  authentic placeholder: "To chat click here or press / key".
- **Right edge** — the classic VERTICAL **Health** bar: deep navy track,
  the green fill climbing from the bottom, the number chip parked on top;
  drains red as you take fall damage and refills with the classic 1%/s
  regen.
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
- **ACCOUNT** — signed-in-as + the red **Log Out** key (wipes the saved
  session, lands on the login page).

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
