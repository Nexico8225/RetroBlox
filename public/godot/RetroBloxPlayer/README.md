# RetroBlox Player

The official RetroBlox player system: a classic six-part multiplayer world
that signs you into your RetroBlox account — **inside the game** — and
spawns you wearing your real account avatar.

Built on server-authoritative multiplayer (clients send input, the server
simulates), client prediction, 20 Hz snapshots, chat with speech bubbles
and a LAN auto-host/auto-join flow.

## Play

**Godot source:** install [Godot 4.5.1](https://godotengine.org/download/archive/4.5.1-stable/)
or a compatible newer Godot 4 release. Import `project.godot`, let imports
finish, then press **F5**. No plugins or external assets required.

## Sign in, sign up, or play as a guest

The game opens on a login card:

- **Log In** — your existing RetroBlox account. Your account avatar
  (body colors, shirt, pants, face, 3D UGC) loads from the website.
- **Sign Up** — create a brand-new account WITHOUT leaving the game.
  Pick a username + password and you are in, avatar ready.
- **Play as Guest** — no account; you spawn as a classic noob with a
  Guest-1234 name.

The game remembers you: the next launch signs you in automatically.

### Pointing at a different RetroBlox website

The login card's "RetroBlox website" field defaults to `http://localhost:3000`.
Change it there, or set `api_url` in `network.cfg`, or launch with
`-- --api=http://your-site:3000`.

## Controls

| Action | Control |
|---|---|
| Move | WASD or arrow keys |
| Jump | Space |
| Orbit the camera | Hold right mouse button and drag |
| Zoom / first person | Mouse wheel |
| **Shift Lock** | Shift (or toggle it in the Esc menu) |
| Chat | Enter, type, Enter to send |
| Menu / close chat focus | Esc |

### Shift Lock

Press **Shift**: the mouse locks to the screen center, the camera rests on
your right shoulder, and your character always squares up with the camera —
the classic way to build and strafe. Everyone else sees your character turn
too (it is simulated on the server, not faked on your screen).

## The Esc menu

Esc opens a proper game menu: the player roster, **Resume Game**,
**Reset Character** (six falling pieces + the oof-style sound),
the **Shift Lock** toggle, camera sensitivity and volume sliders, and
**Leave Game**. The multiplayer session keeps running while the menu is open.

## Internet multiplayer (creator setup)

The room auto-hosts on your LAN with zero setup. For internet play, run a
dedicated headless server and point players at it:

1. Put a build of this project on a machine with a public IP.
2. Run `godot --headless -- --server` (or export a build and run it with
   `-- --server`). Dedicated servers skip the login card.
3. Open inbound **UDP 42420** (and 42421 for LAN discovery replies).
4. Set `server="YOUR_SERVER_IP"` in the `network.cfg` distributed beside
   every player's executable.

## Source map

- `scripts/main.gd` — networking, auth flow, camera, shift lock, settings
- `scripts/auth_screen.gd` — the in-game login / sign up card
- `scripts/player.gd` — movement, prediction, shift-lock heading
- `scripts/avatar.gd` — the six-part block avatar (paintable)
- `scripts/avatar_platform.gd` — account avatar dressing: colors, clothing
  textures (300x190 / 220x190 template zones), face decal, UGC GLB models
- `scripts/retroblox_api.gd` — the HTTP client for the RetroBlox platform
  (login, signup, /me, avatars, assets, files)
- `scripts/hud.gd` — chat, roster, status, the Esc menu
- `scripts/arena.gd` — the classic baseplate world

## Platform API the player uses

- `POST /api/platform/login` — sign in (JSON, CORS-open)
- `POST /api/platform/signup` — create an account (JSON, CORS-open)
- `GET /api/platform/me` — your profile + account avatar (Bearer token)
- `GET /api/users/{id}/avatar` — any player's avatar (public)
- `GET /api/assets/{assetId}` — resolve an asset id into color/image/model
- `GET /api/files/{fileId}` — raw asset bytes

Project code is MIT. The reset sound is an original oof-style synthesis,
not the licensed Roblox recording. This is a fan-made classic-style client,
not affiliated with Roblox Corporation.
