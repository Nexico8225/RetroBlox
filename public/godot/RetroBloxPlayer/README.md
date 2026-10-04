# RetroBlox Godot Player — web-synced multiplayer

The official RetroBlox player for **Godot 4.5+**: log in with your RetroBlox
account, wear your account avatar (including your own 3D UGC), and play the
**Baseplate** together with everyone else. The game itself is **synced from
the RetroBlox website** — the site owns the games, this player downloads and
runs them.

It is also a **starter kit for your own games** — every piece ships as a
Godot **scene** built from plain nodes you can drag into any project: the
block avatar, the player, the login card, the HUD, the part/spawn/ladder
builders, and a small HTTP client class that talks to the RetroBlox platform.

> **Login only.** There is no guest mode — your RetroBlox account IS your
> player. Accounts made on the website work here, and accounts made here
> (Sign Up tab) work on the website.

---

## 1. Just play it

Install [Godot 4.5.1](https://godotengine.org/download/archive/4.5.1-stable/)
(or any newer Godot 4.5+), open the project folder, let imports finish,
press **F5**. No plugins, no external assets.

The game opens on the login card:

- **Log In** — your existing RetroBlox account. Your avatar (body colors,
  shirt, pants, face, 3D UGC) loads from the website.
- **Sign Up** — create a brand-new account without leaving the game.

Then it downloads the game list from the website and drops you into
**Baseplate** with everyone else who is online.

### Controls

| Input | Action |
| --- | --- |
| W A S D / arrows | Move (classic WalkSpeed 16, JumpPower 50) |
| Space | Jump — climb a ladder and press Space to **jump OFF** |
| Shift | **Shift Lock** on/off (also in the ESC menu) |
| Right mouse (hold) | Free-look camera |
| Mouse wheel | Zoom in/out (all the way in = first person) |
| `/` or Enter | **Chat** — everyone in the place sees it live |
| Esc | Release chat focus / open the menu |

### Shift Lock

Press **Shift** (or toggle it in the menu): the cursor locks to the screen
center, the camera rests on your right shoulder, and your character squares
up to the camera direction while strafing — exactly the classic feel. The
setting is remembered between sessions.

### Ladders

RetroLadder (truss) parts are climbable: walk into one and push **forward**
to climb up, **back** to climb down, and press **Space** to jump off. The
rig's Climb animation plays while you climb.

---

## 2. How the web sync works

```
   retroblox website (source of truth)          this player
   ┌────────────────────────────────┐          ┌────────────────────┐
   │ GET  /api/game/places          │ ◀─────── │ after login: list  │
   │ GET  /api/game/places/baseplate│ ◀─────── │ download the map   │
   │ POST /api/game/state  ~7x/s    │ ◀─────── │ pos/yaw/anim/chat  │
   │      -> other players + chat   │ ───────▶ │ smoothed, rendered │
   └────────────────────────────────┘          └────────────────────┘
```

- The map (every part, spawn pad, ladder) is stored **on the website** — one
  game ships today: `baseplate`. Edit the place on the web and the next
  launch plays the new version.
- Multiplayer runs over plain HTTPS through the site — **no port forwarding,
  no LAN setup**. Your client posts its position ~7 times per second and
  receives everyone else's; remote characters are smoothed so it feels instant.
- Chat is part of the same loop: messages land in the website's chat store
  and are delivered to every player in the place (with a spam guard).
- If the website cannot be reached, the bundled Baseplate scene loads so you
  can still play solo; the player keeps retrying in the background.

Point the player at a different website (self-host): the Server field on the
login card, `RETROBLOX_API=<url>` or `--api=<url>`.

---

## 3. For creators — nodes and scenes

The world is built from the SAME scenes on the web and in the editor:

| Scene | Node | What it does |
| --- | --- | --- |
| `scenes/part.tscn` | `RetroPart` | One classic studded block (size + color in the inspector) |
| `scenes/spawn_location.tscn` | `SpawnLocation` | Spawn pad — players appear on these round-robin |
| `scenes/ladder.tscn` | `RetroLadder` | Climbable truss with rungs |
| `scenes/maps/classic_baseplate.tscn` | — | The classic map, hand-built from the three nodes above |

To build your own place: open any map scene (or make a new one), drag in
`part.tscn` / `spawn_location.tscn` / `ladder.tscn`, and set `size` +
`color` in the inspector. Everything is in **studs** (1 unit = 1 stud, a
player is 5 studs tall). Players step over ledges up to 3 studs, so
staircases just work — stack 1-stud steps.

The web-sync path spawns these very same scenes from the website's map JSON:

```json
{
  "parts":   [{ "name": "Baseplate", "p": [0,-1,0], "s": [128,2,128], "color": "#287f47" }],
  "spawns":  [{ "name": "Spawn1",    "p": [-6,0.5,-6], "s": [6,1,6],  "color": "#a3a2a5" }],
  "ladders": [{ "name": "Truss",     "p": [-14.5,6,0], "s": [2,12,1],  "color": "#63666a" }]
}
```

`scripts/arena.gd` builds either source: `apply_map_data()` (web JSON) or the
bundled `classic_baseplate.tscn` (offline fallback). The map you edit as
nodes in the editor converts to that JSON 1:1 with
`scripts/parse_baseplate.py` (in the website repo).

### Player + avatar scenes

- `scenes/player.tscn` — the character: capsule physics + avatar + chat
  bubble. `initialize(id, name)` for locals, `render_remote()` for network
  players.
- `scenes/avatar.tscn` + `scripts/avatar.gd` — the six-part classic rig.
  In R6IK mode it uses the REAL catalog model (`assets/models/R6IK.fbx`) with
  the site's own part-matching rules; the box rig is the fallback.
- `scripts/avatar_platform.gd` — dresses the avatar from the platform
  payload (body colors, shirt/pants templates, face decal, 3D UGC placed
  EXACTLY where the creator left it — site-space mapped, so UGC never wears
  backwards).

### Scripts map

| Script | Role |
| --- | --- |
| `scripts/main.gd` | The whole game flow: login → download game → build world → multiplayer heartbeat → chat → respawn |
| `scripts/player.gd` | Classic movement (WalkSpeed 16 / JumpPower 50 / gravity 196.2), step-up, ladders, fall damage, health |
| `scripts/arena.gd` | Sky + sun + the map (web JSON or scene) |
| `scripts/retroblox_api.gd` | The one HTTP door: login, signup, me, avatars, assets, files, game sync |
| `scripts/hud.gd` | Classic old-Roblox HUD: toolbar, chat, player list, health, ESC menu, Shift Lock toggle |
| `scripts/auth_screen.gd` | The login / signup card (remembers the last username + token) |

---

## 4. Animations — swapping in new ones

The rig ships with the old-Roblox clips `Old_Idle`, `Old_Walk`, `Old_Jump`
and `Climb` inside `assets/models/R6IK.fbx`, driven by the rig's own
AnimationPlayer (`scripts/avatar.gd`).

Making your own anims? Two supported routes:

1. **Replace the built-in clips** — animate the R6IK rig in Blender, export
   the FBX over `assets/models/R6IK.fbx` with the SAME clip names. Nothing
   else to change; walk/climb are auto speed-scaled to the movement.
2. **A different rig** — keep `scenes/avatar.tscn`'s box rig animating
   procedurally, or point `avatar.gd`'s `ANIM_*` constants at your new clip
   names. Clip names live in ONE place (top of `scripts/avatar.gd`), so a
   swap is a four-line change.

---

## 5. Self-hosting / SDK notes

- Everything talks to the same platform API the website exposes — see the
  endpoint list at the top of `scripts/retroblox_api.gd`.
- The game sync endpoints are public read (`/api/game/places*`); presence
  and chat require a login token (`POST /api/game/state`).
- `tests/probe_web_game.gd` is a full headless E2E: login → avatar → game
  list → map → two players seeing each other → chat round trip → rate
  limit → leave → placement math. Point it at any server:
  change `API_URL`, then
  `godot --headless --path . --script res://tests/probe_web_game.gd`.

### Troubleshooting

- **"Could not reach the server"** — check the Server field / your internet.
  The exact network reason is printed.
- **Wrong colors / white UGC** — creators: export `.glb` from Blender (or
  FBX with Path Mode "Copy" + "Embed Textures"). The site converter warns at
  upload when a model carries no material colors.
- **Stale install** — re-download the kit zip from the site; old zips had
  missing scenes/icons.
