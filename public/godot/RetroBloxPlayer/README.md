# RetroBlox Godot SDK — Player + Dev Kit

The official RetroBlox player system for **Godot 4.5+**: a classic six-part
multiplayer world that signs players into their RetroBlox account **inside
the game** and spawns them wearing their real account avatar.

It is also the **starter kit for your own games** — every piece ships as a
Godot **scene** you can drag into any project: the block avatar, the player,
the account login card, the HUD, and a small HTTP client class that talks to
the RetroBlox platform.

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
  colors, shirt, pants, face, 3D UGC) loads from the website.
- **Sign Up** — create a brand-new account WITHOUT leaving the game.
- **Play as Guest** — no account; classic noob colors, "Guest-1234" name.

The game remembers you — the next launch signs you in automatically.

| Action | Control |
|---|---|
| Move | WASD or arrow keys |
| Jump | Space |
| Orbit the camera | Hold right mouse button and drag |
| Zoom / first person | Mouse wheel |
| **Shift Lock** | Shift (or toggle it in the Esc menu) |
| Chat | **/** (already in typing mode) or Enter, then Enter to send |
| Menu / close chat focus | Esc |

Internet play: run a build with `-- --server` on a machine with a public IP,
open **UDP 42420** (+42421 for LAN discovery), and set
`server="YOUR_SERVER_IP"` in the `network.cfg` beside the players' builds.
Point the login card at any RetroBlox site with `-- --api=https://your-site`.

### The avatar uses the real catalog model (R6IK)

In-game players wear **`assets/models/R6IK.fbx`** — the exact rig the
website's catalog and avatar editor render — normalized to the game's
capsule, with limbs swinging from shoulder/hip pivots and arms-up jumps,
like the site's playground. If the FBX has not been imported yet (a
brand-new project), the kit falls back to its built-in box rig
automatically and upgrades the moment Godot imports the model.

Making your own rig? Export an FBX with the same part names —
`Head`, `Torso`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg` — and
drop it in `assets/models/`; the alias matcher (same rules as the site's
`rig.ts`) finds the parts, hides helper meshes, and everything (painting,
clothing zones, face decals, debris) keeps working.

### HUD: the classic top-left icon toolbar

The screen stays clear while you play — a **top-left toolbar** of grey
beveled icon buttons (the old-Roblox spot) toggles the menu, chat panel
and player list, and CHAT shows an unread badge while hidden.
`/` opens chat already in typing mode (the classic behavior), `Enter`
still works, `Esc` closes it. Switching to another app (alt-tab) does
**not** pause the game or open the menu — only you pause you. Lighting
matches the site's catalog look: bright white sun, sky/ground fill light,
filmic tonemapping.

### Troubleshooting sign-in

- **"Incorrect username or password"** — accounts are shared with the
  website, so the same name + password work. No account yet? Use the
  **Sign Up** tab right on the card.
- **"Could not reach …"** — the game signs in to the official site
  (`https://retro-blox.vercel.app`) and the address is locked — it cannot
  be changed on the card. Check your internet connection, then try again.
  Self-hosting? Launch with `--api=<your-url>` or the `RETROBLOX_API`
  environment variable instead.
- **Signing in works but the error comes back** — delete
  `user://profile.cfg` (Godot's *Project → Open User Data Folder*) to
  clear a stale saved token, then sign in again.
- **Still stuck on an older kit?** Re-download this zip — versions before
  October 2, 2026 had an editable Server field (and a login bug that left
  you stuck on the card). This build locks the official site and jumps
  straight into the game after signing in.

---

## 2. Build YOUR game with the kit (the scenes)

Everything reusable lives in `scenes/`. Each is a normal Godot scene — open
it in the editor, tweak sizes/colors/widgets visually, or instance it from
code:

| Scene | What it gives you |
|---|---|
| `scenes/avatar.tscn` | The six-part block avatar (head/torso/arms/legs + nameplate + face). Paintable, textureable, animatable. |
| `scenes/player.tscn` | CharacterBody3D with capsule, avatar and chat bubble — drop it in your world and call `initialize()`. |
| `scenes/auth_screen.tscn` | The account gate: log in / sign up / guest, saved-token auto sign-in. |
| `scenes/hud.tscn` | Chat, roster, status line, Esc menu with settings. |
| `main.tscn` | The demo game: arena + player spawns + camera rig + HUD + auth. Use it as a reference or a starting world. |

### Minimal example — your own game with accounts + avatars

Create a new scene, instance `scenes/auth_screen.tscn` and
`scenes/player.tscn`, then attach a small script:

```gdscript
extends Node3D

func _ready() -> void:
        var auth := $AuthScreen
        auth.completed.connect(_on_signed_in)
        auth.guest_requested.connect(_on_guest)
        auth.set_api_url("https://your-retroblox-site.example")  # or leave default

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
and 3D UGC accessories loaded from GLB with the creator's exact placement:

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

- `POST /api/platform/login` — sign in (JSON, CORS-open)
- `POST /api/platform/signup` — create an account (JSON, CORS-open)
- `GET  /api/platform/me` — your profile + account avatar (Bearer token)
- `GET  /api/users/{id}/avatar` — any player's avatar (public)
- `GET  /api/assets/{assetId}` — resolve an asset id into color/image/model
- `GET  /api/files/{fileId}` — raw asset bytes (PNG/JPG/WEBP/GLB)

### Testing your changes

A headless smoke test covers every scene and script:

```
godot --headless -s tests/smoke.gd
```

It ends with `SMOKE_OK` when all ~48 checks pass.

A second tiny guard fails if an input action ever goes missing from
`project.godot` (movement reads `move_left/right/forward/back` + `jump`):

```
godot --headless --path . --script res://tests/validate_actions.gd
```

---

## 3. Source map

| Path | Role |
|---|---|
| `main.tscn` | The demo game tree: Arena, Players, Debris, CameraRig |
| `scenes/avatar.tscn` | The block avatar rig (edit sizes visually) |
| `scenes/player.tscn` | Capsule + Avatar instance + ChatBubble |
| `scenes/auth_screen.tscn` | The login card (restyle visually) |
| `scenes/hud.tscn` | All HUD panels and the Esc menu (restyle visually) |
| `scripts/main.gd` | Networking, auth flow, camera, shift lock, settings |
| `scripts/player.gd` | Movement, prediction, shift-lock heading |
| `scripts/avatar.gd` | Drives the avatar scene nodes (paint/animate/burst) |
| `scripts/avatar_platform.gd` | Account avatar dressing (site-identical rules) |
| `scripts/retroblox_api.gd` | HTTP client for the platform |
| `scripts/auth_screen.gd` | Login/signup/guest behavior |
| `scripts/hud.gd` | Chat, roster, menu behavior |
| `scripts/arena.gd` | The procedural demo baseplate world |
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

Each adapter gets the same promise: sign in inside the game, wear your
account avatar, every game sees the same you.

## 5. License

Project code is MIT. The reset sound is an original oof-style synthesis,
not the licensed Roblox recording. This is a fan-made classic-style client,
not affiliated with Roblox Corporation.
