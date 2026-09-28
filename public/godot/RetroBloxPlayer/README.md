# RetroBlox Game Kit — Player + Dev Kit

The official RetroBlox player system for **Godot 4.5+**: a classic six-part
multiplayer world that logs players into their RetroBlox account **inside
the game** and spawns them wearing their real account avatar at true stud
scale — **1 stud = 0.28 meters**, the character exactly **5 studs (1.4 m)**.

It is also the **starter kit for your own games** — every piece ships as a
Godot **scene** you can drag into any project, and every behavior knob is an
**Inspector export**. Nothing is locked inside scripts: the UI, the map, the
animations and the sounds are all nodes you edit visually.

> **One platform, every engine.** The Godot kit ships first. The same
> platform API is engine-agnostic (plain HTTP + JSON), so Unity, Unreal,
> Flax and Source2 adapters are planned next — see the roadmap at the bottom.

---

## 1. Just play it

Install [Godot 4.5.1](https://godotengine.org/download/archive/4.5.1-stable/)
(or any newer Godot 4.5+), open the project folder, let imports finish,
press **F5**. No plugins, no external assets.

The game opens on the login card:

- **Log In** — your existing RetroBlox account. Your account avatar (body
  colors, shirt, pants, face, 3D UGC) loads from the website. There is no
  server box — the card always points at `retro-blox.vercel.app`.
- **Play as Guest** — no account; classic noob colors, "Guest-1234" name.
  Accounts are created on the website, not in the game.

**Log in once and you stay logged in** — the saved token signs you in
automatically on every launch. **Log Out** lives in the ESC menu (it wipes
the saved session and lands you back on the login card). As soon as a login
succeeds the card comes down by itself and drops you into the world wearing
your account avatar, UGC hats included.

| Action | Control |
|---|---|
| Move | WASD or arrow keys |
| Jump | Space |
| Orbit the camera | Hold right mouse button and drag |
| Zoom / first person | Mouse wheel (clamped — you can't zoom off the map) |
| **Shift Lock** | Shift (or toggle it in the Esc menu) |
| Chat | **/** (already in typing mode) or Enter, then Enter to send |
| Menu / close chat focus | Esc |

Internet play: run a build with `-- --server` on a machine with a public IP,
open **UDP 42420** (+42421 for LAN discovery), and set
`server="YOUR_SERVER_IP"` in the `network.cfg` beside the players' builds.
Point the login card at any RetroBlox site with `-- --api=https://your-site`.

### The avatar uses the real catalog model (R6IK)

In-game players wear **`assets/models/R6IK.fbx`** — the exact rig the
website's catalog and avatar editor render — normalized to exactly **5
studs**, with the real Old_Idle / Old_Walk / Old_Jump / Climb clips. UGC
hats and accessories are applied **verbatim** at site scale (the game rig
and the site rig are both 5 studs, so the scale factor is 1.0 — what you
see in the catalog is what sits on your head). If the FBX has not been
imported yet (a brand-new project), the kit falls back to its built-in box
rig automatically and upgrades the moment Godot imports the model.

Making your own rig? Export an FBX with the same part names —
`Head`, `Torso`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg` — and
drop it in `assets/models/`; the alias matcher (same rules as the site's
`rig.ts`) finds the parts, hides helper meshes, and everything (painting,
clothing zones, face decals, debris) keeps working.

### Sounds are built in

The player ships with a small retro sound set (synthesized, license-free):
**jump, land, footsteps** on every character, and **click / hover / open /
close / success / deny** on the UI. Every sound is an AudioStreamPlayer
**node inside the scenes** — mute it, swap the WAV, or add more in the
editor. The player's `play_footsteps / play_jump_sound / play_land_sound`
exports toggle them per game.

### Lighting: bright, flat, classic — but never oversaturated

The old-renderer recipe: one strong white sun (tops are the brightest
face), flat grey ambient, LINEAR tonemap, and a gentle global saturation
pull-back (0.8) so colors stay classic-pastel instead of electric.

### Troubleshooting sign-in

- **"Incorrect username or password"** — accounts are shared with the
  website, so the same name + password work. No account yet? Create one
  free at `retro-blox.vercel.app` — the game logs in, it does not sign up.
- **"Could not reach …"** — check your internet; the game talks to
  `https://retro-blox.vercel.app` (baked in — nothing to configure).
- **Signing in works but the error comes back** — delete
  `user://profile.cfg` (Godot's *Project → Open User Data Folder*) to
  clear a stale saved token, then log in again.

---

## 2. Build YOUR game with the kit (nodes + exports)

The kit's whole point: **other devs build games on this**. Everything is
meant to be edited in the Godot editor — visually, as nodes — with scripts
only wiring behavior.

### The UI is nodes, not code

Open `scenes/hud.tscn` and you will find the entire interface as a node
tree: the top-left **toolbar** (menu / chat / people icon buttons), the
**health bar** (top right), the chat panel, the player roster, the help
panel, the toast + crosshair, and the whole **ESC menu card** — including
the "Playing as …" account line and the **Log Out** button. Restyle any
panel by editing its StyleBox in the Inspector; move anything by dragging.

- **UI animations**: the `UIAnim` AnimationPlayer node carries
  `menu_open` / `menu_close` (the menu fade). Edit or add tracks visually.
- **UI sounds**: the `UISounds` node holds ClickSound / HoverSound /
  OpenSound / CloseSound players. Swap the streams to reskin the sound.
- The login card (`scenes/auth_screen.tscn`) is the same deal: its
  `card_in` fade lives on its own `UIAnim`, its sounds on `UISounds`.

### The map is nodes too

Maps are scenes of `scenes/part.tscn` instances (the `RetroPart` block —
set `size` and `color` in the Inspector, collision + mesh build
themselves), `scenes/spawn_location.tscn` pads, and `scenes/ladder.tscn`
trusses. `scenes/maps/classic_baseplate.tscn` is the demo; copy it and
build your own world, or point `scripts/arena.gd`'s `MAP_SCENE_PATH` at
yours. `RetroPart` is a `@tool` script — parts render live in the editor.

| Scene | What it gives you |
|---|---|
| `scenes/avatar.tscn` | The six-part block avatar (head/torso/arms/legs + nameplate + face). Paintable, textureable, animatable. |
| `scenes/player.tscn` | CharacterBody3D with capsule (exactly 5 studs), avatar, chat bubble and the 3D sound nodes. |
| `scenes/auth_screen.tscn` | The login card: login-only, saved-token auto sign-in, card_in animation, UI sounds. |
| `scenes/hud.tscn` | The whole interface as nodes + UI animations + UI sounds. |
| `scenes/ladder.tscn` | The classic truss — climbable out of the box. |
| `scenes/part.tscn` | The RetroPart building block (studs, stairs, walls, rungs). |
| `scenes/maps/classic_baseplate.tscn` | The demo map — stairs, gap slabs, ladder tower, floating ledges. |
| `main.tscn` | The demo game: arena + player spawns + camera rig + HUD + auth. |

### Tune the player in the Inspector

Select any `scenes/player.tscn` instance (or set them per-game from code —
`player.walk_speed = 24.0`) and edit:

| Export | Default | Meaning |
|---|---|---|
| `walk_speed` | 16.0 | studs / second (classic WalkSpeed) |
| `walk_acceleration` | 145.0 | ground response |
| `air_acceleration` | 110.0 | mid-air steering (obby-ready) |
| `ground_braking` | 170.0 | stopping power |
| `jump_height` | 6.0 | how high the jump peaks, in studs |
| `gravity` | 196.2 | studs / s² (classic) |
| `jump_up_gravity_scale` | 0.6 | < 1 = the rise is eased — a soft, readable arc instead of the old snap; the fall stays full-gravity |
| `can_climb` | true | the kill switch: no ladders / ledges at all |
| `climb_speed` | 9.0 | studs / second up and down |
| `ladder_jump` / `ladder_push` | 46 / 13 | the leap off a climbable |
| `play_footsteps` / `play_jump_sound` / `play_land_sound` | true | built-in sound toggles |

### Climbing: ladders AND thin platforms

You never need a script to make something climbable. Two silhouettes are
recognized automatically after the map loads:

1. **The classic ladder** — plain rungs 1–3 studs deep, held ~1 stud off a
   wall (the classic truss build). Climb face = the side away from the wall.
2. **The open ledge** — a **thin platform (1 stud = 0.28 m deep, up to 3)**
   whose face sits in open space. **Stack them with 1 stud vertical gaps and
   the climb chains through the gaps** — climb off the first stud, onto the
   second above it, all the way up. Walk to the edge, face it, press `W`.

The rules while climbing: only FACING the face + pressing W engages it
(backwards/left/right never sticks you on); W = up, S = down, no input =
hang; riding past the top vaults you onto the surface; sliding past the
bottom lets go; **SPACE leaps off** (up and away, with a cooldown so you
fall back instead of re-sticking). A part flush against a wall is just a
wall — it stays unclimbable. `scenes/ladder.tscn` (the grey truss) works
the same way with zero setup.

### Minimal example — your own game with accounts + avatars

Create a new scene, instance `scenes/auth_screen.tscn` and
`scenes/player.tscn`, then attach a small script:

```gdscript
extends Node3D

func _ready() -> void:
        var auth := $AuthScreen
        auth.completed.connect(_on_signed_in)
        auth.guest_requested.connect(_on_guest)
        auth.set_api_url("https://your-retroblox-site.example")  # optional; default is the official site

func _on_signed_in(_api, username: String, _user_id: String, _avatar: Dictionary) -> void:
        _spawn_player(username)

func _on_guest() -> void:
        _spawn_player("Guest-%04d" % (randi() % 10000))

func _spawn_player(player_name: String) -> void:
        $AuthScreen.visible = false
        var player := preload("res://scenes/player.tscn").instantiate()
        add_child(player)                      # add to the tree FIRST
        player.initialize(1, player_name)      # then configure
        player.global_position = Vector3(0, 0.1, 0)
```

The demo's `scripts/main.gd` does the same thing plus multiplayer — read it
as the full example.

Prefer learning from something runnable? Open
`examples/mini_game/mini_game.tscn` and press **F6** — a login card, your
account avatar on a platform, and 8 coins to collect, in one small scene.
See `examples/mini_game/README.md` for the walkthrough.

### Painting the avatar (the same rules the website uses)

`scripts/avatar_platform.gd` dresses an avatar from a platform payload —
body colors, shirt/pants template zones (300x190 / 220x190), the face decal,
and 3D UGC accessories loaded from GLB with the creator's exact placement
at 1:1 scale:

```gdscript
await AvatarPlatform.apply(api, player.avatar, avatar_payload)
```

Or paint it yourself — no account needed:

```gdscript
player.avatar.set_part_color(player.avatar.HEAD, Color("f5cd30"))
```

Every part also has `set_part_textured()` (custom UV-stamped clothing mesh +
texture) and `set_face()` (decal quad on the head front).

### Making UGC in Blender — materials that survive

The kit loads catalog UGC from GLB, and GLB materials come through exactly
(StandardMaterial3D albedo). If YOUR item shows up plain white, the colors
never made it into the file — Blender only exports colors it can carry.
The 60-second recipe:

1. Shading workspace → select your object → New Material.
2. It is a **Principled BSDF** by default — set **Base Color** to grey,
   brown, whatever. One material per color (grey body + brown trim = two
   materials). Colors ONLY export from Principled BSDF Base Color — the
   little "Viewport Display" color swatch does NOT export, and other
   shader nodes (Diffuse BSDF etc.) export as WHITE.
3. **Best export: File → Export → glTF 2.0 (.glb)** — Format "glTF Binary".
   Principled colors and image textures always survive this path, and the
   uploader takes .glb directly.
4. FBX also works: File → Export → FBX, defaults are fine for flat colors.
   The site converts it to GLB in your browser and keeps the paint. If your
   material uses an IMAGE texture, either use .glb (embeds it) or, in the
   FBX exporter, set Path Mode to **Copy** and tick **Embed Textures** —
   otherwise the texture file is left behind on your PC and the item is
   white again.

The uploader warns you at publish time when a model lands with no material
colors, and the catalog's Texture / Flat color pickers can always paint a
model that has none.

### The platform API (one HTTP door, any engine)

`scripts/retroblox_api.gd` is a plain RefCounted HTTP client. The same
endpoints are what every future engine adapter will call:

- `POST /api/platform/login` — log in (JSON, CORS-open)
- `GET  /api/platform/me` — your profile + account avatar (Bearer token)
- `GET  /api/users/{id}/avatar` — any player's avatar (public)
- `GET  /api/assets/{assetId}` — resolve an asset id into color/image/model
- `GET  /api/files/{fileId}` — raw asset bytes (PNG/JPG/WEBP/GLB)

### Testing your changes

A headless smoke test covers every scene and script:

```
godot --headless -s tests/smoke.gd
```

It ends with `SMOKE_OK` when all checks pass. The climbing contract (facing
gate, W/S ride, jump-off, stacked chaining, floating thin platforms, sizes,
UGC scale) has its own physics probe:

```
godot --headless --path . --script res://tests/probe_climb.gd
```

The node-editability contract (UI as scene nodes, animations, sounds, map
nodes) is guarded by:

```
godot --headless --path . --script res://tests/probe_nodes.gd
```

A tiny guard fails if an input action ever goes missing from
`project.godot` (movement reads `move_left/right/forward/back` + `jump`):

```
godot --headless --path . --script res://tests/validate_actions.gd
```

The login flow gets its own end-to-end probe (real site, real card, real
avatar dressing — it signs up a fresh account, equips free catalog hats,
logs in through the card and checks the card leaves the screen and the
UGC actually lands on the player):

```
godot --headless --path . --script res://tests/probe_login_flow.gd
```

---

## 3. Source map

| Path | Role |
|---|---|
| `main.tscn` | The demo game tree: Arena, Players, Debris, CameraRig |
| `scenes/avatar.tscn` | The block avatar rig (edit sizes visually) |
| `scenes/player.tscn` | Capsule + Avatar instance + ChatBubble + 3D sounds |
| `scenes/auth_screen.tscn` | The login card (restyle visually) |
| `scenes/hud.tscn` | All HUD panels, the Esc menu, UIAnim + UISounds nodes |
| `scenes/part.tscn` | RetroPart — the building block |
| `scenes/ladder.tscn` | RetroLadder — the classic truss |
| `scenes/maps/classic_baseplate.tscn` | The demo map (nodes) |
| `assets/sounds/*.wav` | jump, land, step, click, hover, open, close, success, deny |
| `scripts/main.gd` | Networking, login flow + Log Out, camera, shift lock, settings |
| `scripts/player.gd` | Movement + exported tuning, sounds, prediction, shift-lock heading |
| `scripts/avatar.gd` | Drives the avatar scene nodes (paint/animate/burst) |
| `scripts/avatar_platform.gd` | Account avatar dressing (site-identical rules, 1:1 UGC scale) |
| `scripts/retroblox_api.gd` | HTTP client for the platform |
| `scripts/auth_screen.gd` | Login/guest behavior (site URL baked in) |
| `scripts/hud.gd` | Chat, roster, menu behavior (the UI itself is the scene) |
| `scripts/arena.gd` | Sky + sun + auto-ladder recognition |
| `network.cfg` | Room name, ports, server address, platform api_url |

Networking model: server-authoritative simulation, clients send input,
20 Hz snapshots, client prediction with reconciliation, LAN auto-host /
auto-join, plain-text chat with server-side sanitizing.

## 4. Roadmap — one platform, every engine

The platform API is intentionally boring: HTTP + JSON + static files. That
is what makes multi-engine support straightforward. Planned order:

1. **Godot (this kit)** — done, ships first.
2. **Unity** adapter — C# `RetrobloxApi` + prefab avatar rig.
3. **Unreal** adapter — C++/Blueprints.
4. **Flax Engine** adapter — C#.
5. **Source 2** adapter — Hammer + Lua/C++.

Each adapter gets the same promise: log in inside the game, wear your
account avatar, every game sees the same you.

## 5. License

Project code is MIT. The sounds are original syntheses, not licensed
recordings. This is a fan-made classic-style client, not affiliated with
Roblox Corporation.
