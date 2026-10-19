# Happy Baseplate

The classic sandbox. Climb the fort, ride the trampoline, hang out.

A RetroBlox game template exported as a **real Godot 4.5 project** — open it in
the Godot editor, press F5, and it runs. Everything is standard Godot: no
plugins, no custom formats.

## Open it

1. Install Godot 4.5+ (free, open source): https://godotengine.org/download
2. Open Godot -> Import -> pick this folder's `project.godot` -> Import & Edit.
3. Press **F5** (or the play button). That is the whole game running.

## What is inside

| Path | What it is |
|------|------------|
| `scenes/main.tscn` | The whole level. Every brick is a real node under `Parts` — select, move, scale, recolor in the editor. |
| `scripts/player.gd` | Movement (WASD + Space), camera, death/respawn, bounce pads, ladders, checkpoints, goal. Classic feel: WalkSpeed 16, JumpPower 50. |
| `scripts/game.gd` | Spawn placement, win banner, toasts, and the paint-to-win mode on paint templates. |
| `project.godot` | Engine settings + the WASD/Space input map. |

## How bricks work

Each part is a `StaticBody3D` with a `MeshInstance3D` (BoxMesh) and a
`CollisionShape3D`. The part's **group** is its gameplay role:

| Group | Meaning |
|-------|---------|
| `spawn` | where players start |
| `kill` | touch it and you die |
| `goal` | touch it to win |
| `checkpoint` | touch it to save your respawn |
| `bounce` | launch pad |
| `ladder` | hold W against it to climb |

To build: duplicate any `Part_*` node (Ctrl+D), move it, resize the BoxMesh +
BoxShape3D together, recolor the material. To change how the player feels,
tune the constants at the top of `scripts/player.gd`.

Top-down templates: the camera parks high above the board (`topdown = true`
in `scripts/player.gd`). Set it to `false` for a third-person chase camera.

## Publish it back

1. Zip this folder (with `project.godot` at the top of the zip).
2. On retro-blox.vercel.app -> Create / your game -> attach it as the game file
   or source. The sibling `baseplate.retroplace` file is the same layout for the
   RetroBlox studio player (STUDIO > OPEN GAME FILE).
