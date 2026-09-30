# My First RetroBlox Game

The 60-second quickstart for developers building on the RetroBlox Godot kit.
A login card drops in, your account avatar spawns on a platform, and you
collect 8 coins. That's the whole platform loop — now build YOUR game.

## Run it

1. Open the RetroBlox Player project in Godot 4.2 or newer (4.5.1 recommended).
2. In the file dock open `examples/mini_game/mini_game.tscn`.
3. Press **F6** (Run Current Scene) — or set it as the main scene and press F5.
4. Log in with your RetroBlox account (created on
   `https://retro-blox.vercel.app` — the card is locked to the official
   server and signs in only).

## What it shows

| Step | What happens | Where to look |
|------|--------------|---------------|
| 1 | The login card appears (sign-in only) | `scenes/auth_screen.tscn` reused as-is |
| 2 | On login, the classic player spawns | `scenes/player.tscn` + `initialize()` |
| 3 | The account avatar is dressed (colors, shirt/pants templates, UGC) | `dress_from_payload(api, payload)` |
| 4 | Your game drives the player every physics frame | `player.drive(delta, direction, camera_yaw, jump_serial)` |
| 5 | Coins use Area3D on physics layer 4 (the player layer) | `_spawn_coins()` |

## Reuse it in your own game

Copy the whole `examples/mini_game/` folder, rename things, and build on top.
The reusable kit pieces live in:

- `scripts/retroblox_api.gd` — login / me / assets / file downloads
- `scripts/auth_screen.gd` + `scenes/auth_screen.tscn` — the login card
- `scripts/avatar.gd` + `scenes/avatar.tscn` — the six-part classic avatar
- `scripts/avatar_platform.gd` — the website-identical avatar dressing engine
- `scripts/player.gd` + `scenes/player.tscn` — capsule movement + avatar + chat bubble

Everything references these files **by path** (preload), so copying them into
another Godot project just works — no global class registration needed.

## Controls

- WASD or arrow keys — move
- Space — jump
- Close the window — quit

## Notes for devs

- The player collision layer is 4, world is layer 1 — put interactables on
  mask 4 like the coins do.
- The fixed camera passes `camera_yaw = 0.0`; with a rotating camera, pass its
  Y rotation so WASD stays screen-relative (see `scripts/main.gd` for the
  full third-person rig with Shift Lock).
- If an account has no customized avatar the kit falls back to classic noob colors.
