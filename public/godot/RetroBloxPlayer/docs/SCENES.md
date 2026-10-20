# Godot Scene Architecture & Visual Node Editing

RetroBlox Player is organized into modular Godot scenes with real nodes in the Scene Tree so you can visually edit the **Map**, **Player**, and **UI** directly in Godot Engine!

## Scene Hierarchy

| Scene file | Path | What you can edit in Godot |
|---|---|---|
| **Main Game** | `scenes/game.tscn` | The complete running game scene composed of World, Player, and HUD |
| **Map & World** | `scenes/world/map.tscn` | 3D environment, sky, directional sunlight, spawn pads, baseplate, stairs, truss ladders, trampolines, lava kill bricks, checkpoints, and wall hop obstacles |
| **Player** | `scenes/player/player.tscn` | CharacterBody3D, Hitbox, visual R6 mesh nodes (Head, Torso, Arms, Legs), Chat bubbles, physics tuning (`walk_speed`, `jump_height`, `gravity`, `coyote_time`) and classic speedrun glitches |
| **HUD / UI** | `scenes/ui/hud.tscn` | 2D UI canvas: Topbar buttons, Health bar, User pill, Stats chip, Crosshair, and Toasts |
| **Login** | `scenes/login.tscn` | Sign-in screen, guest play, and studio launcher |
| **Studio Hub** | `scenes/studio.tscn` | In-game creator studio hub |

## How to Edit in Godot

### 1. Edit the Map (`scenes/world/map.tscn`)
- Open `scenes/world/map.tscn` in Godot.
- Click on any part in the 3D viewport: move, rotate, scale with gizmos.
- Duplicate parts (`Ctrl+D`) to build new courses, islands, or structures.
- Group tags trigger classic behavior:
  - `spawn`: Player spawn points
  - `kill`: Lava / kill bricks (triggers oof & respawn)
  - `checkpoint`: Checkpoint pads that update spawn position
  - `ladder`: Climbable truss ladders
  - `bounce`: High-launch trampolines
  - `goal`: Victory pads

### 2. Edit the Player (`scenes/player/player.tscn`)
- Open `scenes/player/player.tscn` in Godot.
- Select the `Avatar` node or its child meshes (`Head`, `Torso`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`) to customize colors, textures, materials, and attachments directly in the 3D viewport!
- In the Inspector panel for the root `Player` node, tune values directly under **Player Physics & Tuning**:
  - `walk_speed`: Classic WalkSpeed (default 16 studs/s)
  - `jump_height`: Classic JumpPower (default 50 studs/s)
  - `gravity`: World gravity (default 196.2 studs/s²)
  - `coyote_time`: Ledge jump grace window
  - `max_air_jumps`: Set to 1 for double jump!
  - `momentum_enabled`: Build speed while sprinting

### 3. Classic Speedrun Glitches & Nostalgia Tech
Retrobloxians love classic obby skips and tricks! The Player comes with authentic, balanced speedrun tech built-in:
- **⚡ Wall Hop (`wall_hop_enabled`)**: Flick jump against vertical walls or obby corners in mid-air to hop up ledges.
- **✨ Ladder Flick (`ladder_flick_enabled`)**: Jump while dismounting a truss ladder to get an explosive speed boost launch.
- **🚀 Super Bounce (`super_bounce_enabled`)**: Time your Jump right as you hit a bounce pad / trampoline to launch into the stratosphere!
- **🌀 Corner Clip (`corner_clip_enabled`)**: Squeeze into 90-degree corners with shift lock to slip through thin 1-stud barriers.
- **💨 Ledge Jump**: Make daring gap skips right at the edge of platforms with coyote time grace.

### 4. Edit the UI (`scenes/ui/hud.tscn`)
- Open `scenes/ui/hud.tscn` in Godot.
- Switch to the **2D** workspace.
- Rearrange buttons, adjust health bar dimensions, change colors, or add custom HUD panels and labels!
