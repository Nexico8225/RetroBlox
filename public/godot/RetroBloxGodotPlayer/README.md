# RetroBlox Player for Godot

The official RetroBlox player system, 1:1 classic:

- **The R6IK character** — the real rigged model, walking with the original
  classic clips: `old_walk`, `old_jump`, `old_idle`
- **Classic physics** — 16 walk speed, 50 jump power, 196.2 gravity,
  camera-relative WASD, right-drag orbit camera, scroll zoom (0.5–40 studs)
- **Your real avatar** — sign in with your RetroBlox account and the character
  spawns wearing exactly what you dressed on the website: body colors, per-part
  Body Colors, shirt + pants (300x190 / 220x190 template zone-crops), the face
  decal (with the Face size slider), and your 3D UGC (GLB models placed EXACTLY
  where their creators left them — the sacred placement rule)
- **Classic chat** — press `/` to chat, Enter to send, Esc to cancel. Messages
  land in the feed and pop as a bubble above your head.

## Requirements

- **Godot 4.3 or newer** (the built-in FBX importer reads the R6IK rig —
  no FBX2glTF needed)
- A RetroBlox server to connect to (the website itself!)

## Run it

1. Open this folder in Godot 4.3+ (it imports the FBX on first open).
2. Press **Play** (F5).
3. In the login screen:
   - **Server URL** — your RetroBlox site, e.g. `http://localhost:3000`
     (or the public URL of a deployed RetroBlox)
   - **Username / Password** — your RetroBlox account
4. You spawn on the baseplate wearing your avatar.

## Controls

| Input            | Action                                   |
| ---------------- | ---------------------------------------- |
| W A S D / arrows | Move (relative to the camera, classic)   |
| Space            | Jump (old_jump plays)                    |
| Right-mouse drag | Orbit the camera                         |
| Mouse wheel      | Zoom 0.5 – 40 studs                      |
| `/`              | Open chat                                |
| Enter            | Send chat                                |
| Esc              | Close chat                               |

## How the avatar flows (the platform contract)

```
   RetroBlox website (dress your avatar once)
              |
   POST /api/platform/login     username + password -> session token
   GET  /api/platform/me        token -> your account-wide avatar
   GET  /api/assets/{assetId}   asset ids -> color / image / 3D model
   GET  /api/files/{fileId}     the actual bytes (images, GLB, audio)
              |
   This player loads it all and dresses R6IK 1:1 with the website render.
```

- The avatar belongs to your **account**, not to a game. Change it on the
  website and every game (this player, Unity SDK games, anything) sees it.
- Games never touch the database — only the platform API.
- `GET /api/users/{userId}/avatar` also returns any player's avatar publicly,
  so multiplayer games can spawn OTHER players wearing their real looks.

## Files

| File                     | What it is                                       |
| ------------------------ | ------------------------------------------------ |
| `models/R6IK.fbx`        | The official rigged R6 player model (old_walk / old_jump / old_idle clips) |
| `models/default_face.png`| The classic Smile, used when the account wears head_01 |
| `scripts/game.gd`        | Entry point: world, login screen, spawn flow     |
| `scripts/retroblox_api.gd` | The one HTTP door to the platform (login / me / assets / files) |
| `scripts/avatar_builder.gd` | Dresses the rig: colors, clothing zones, face decal, placed UGC |
| `scripts/player.gd`      | Classic character controller + camera + animations |
| `scripts/chat.gd`        | The classic chat feed + `/` input + bubble       |
| `scenes/main.tscn`       | The main scene                                   |

## Notes & troubleshooting

- **Model is invisible / no animations?** Make sure you opened the project in
  the Godot **editor** at least once so the FBX imports (check the Import tab;
  animation names must contain old_walk / old_jump / old_idle).
- **HTTPS servers**: Godot only trusts certificates signed by the system CA.
  Use a public HTTPS URL (like the deployed site) or plain `http://` locally.
- **Chat is local** in this build (sandbox). The feed is exactly where
  multiplayer chat lands once the platform's realtime relay ships.
- **UGC placement is sacred**: models render exactly where their creators
  placed them on the website. If a hat looks off in-game, it looks off on
  the site too — fix it in the placement editor, not in the player.
