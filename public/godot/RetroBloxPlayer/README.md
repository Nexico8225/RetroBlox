# RetroBlox Player (v2)

The completely new classic player: **load your avatar, play, and chat** —
all through the official RetroBlox platform, with the server locked to
`retro-blox.vercel.app`.

## What is new

- **Your avatar, in every place** — body colors, shirt/pants, face and every
  3D UGC accessory you wear on the website (placed EXACTLY where the creator
  left it, with the creator's texture, tint and metallic/roughness finish).
- **Play** — classic studs movement (WalkSpeed 16 / JumpPower 50 / gravity
  196.2), 2.5-stud steps, truss ladders, trampolines, kill bricks,
  checkpoints, fall damage with the original *oof*.
- **Chat, across the internet** — the place chat runs through the platform
  API (no LAN needed): talk to anyone in the same place anywhere in the
  world, see them walk around via live presence, player list with #seqId
  chips, speech bubbles.
- **Three built-in places** — Happy Baseplate, Classic Obby (with checkpoints
  and a gold goal), Skylands (the void is real).
- **New retro UI** — the same 2006 Steel look the website wears: grey bevels,
  steel-blue headers, chunky buttons.
- **Guests work** — play everything instantly, watch chat read-only.
  Sign up (inside the player or on the site) to talk, show online and save
  your look.

## Quick start

1. Unzip `retroblox-godot-player.zip`
2. Open the `RetroBloxPlayer` folder in **Godot 4.5+** (free)
3. First open: Godot imports for a moment, then press **Play (F5)**
4. Log in with your RetroBlox account — or **Sign Up** right here — or hit
   **Play as Guest**

The player remembers you: next launch signs you in automatically.

## Controls

| Input | Action |
| --- | --- |
| W A S D / arrows | Move |
| Space | Jump (hold to bunny-hop) |
| Mouse | Look (captured while playing) |
| Mouse wheel | Zoom |
| Shift | Shift Lock — camera parks on your shoulder, you turn with it |
| Enter | Open chat · Enter again sends · Esc closes |
| P | Player list (who is in the place right now) |
| Esc | Game menu (Resume / Respawn / Leave Place) |

## Places

- **Happy Baseplate** — the sandbox: brick pile, stairs fort, truss tower,
  trampoline and a very shiny metal shed.
- **Classic Obby** — hops, kill bricks, a narrow plank, a truss climb and a
  trampoline launch to the gold goal. Checkpoints save your progress.
- **Skylands** — floating islands over the void; bounce between them, walk
  the kill plank, claim the gold.

## Notes

- Only signed-in members appear online and chat — guests never create
  hidden accounts or spam the platform.
- The first open of the project uses the classic box avatar until Godot has
  imported `assets/models/R6IK.fbx`; press Play again after the import for
  the full animated catalog rig.
- Chat rate limit: one line per ~0.8 s, 240 characters — the classic pace.
