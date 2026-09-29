# RetroBlox Player System (v2)

The classic six-part multiplayer sandbox client for RetroBlox — the 2006-era
Roblox remake. Open in **Godot 4.5.1 or newer**, or just download the ready
zip from the website's Player System page.

## What this is

A complete, self-contained Godot project. Sign in inside the game (or press
Guest), your **account avatar loads from the RetroBlox platform** — colors,
shirt/pants clothing, face, 3D UGC hats and gear at their creator-placed
spots — and you play in a shared LAN/Internet room where everyone sees
everyone's real avatar.

## Architecture (what lives where)

```
project.godot            Godot 4.5 GL-Compatibility project (1280x720, 60Hz physics)
main.tscn                Game root: Arena, Players, Debris, CameraRig(SpringArm)
network.cfg              Room name, ports, platform URL (an adjacent copy overrides after export)
scripts/
  main.gd                Game director: auth flow, room discovery/host/join, spawning,
                         snapshots, chat relay, chat-walk, hold-space hop, E-look camera,
                         shift lock, custom cursors, kill/respawn
  player.gd              CharacterBody3D controller — classic feel with the
                         ROBLOX HITBOX (flat 2x5x1 R6 hull that yaws with you):
                         Walk 16, 6-stud eased jump, auto-step up to 3 studs with
                         Minecraft-style pop onto stairs (no edge wedging), wall
                         glide, ladders you only grab FACING them + holding W
                         (W up / S down / hang freezes the pose / SPACE leaps
                         away / camera-away lets go / crest vaults the top),
                         fall damage + slow classic regen (1%/s after 5s),
                         overhead health billboard, jump/land/footstep 3D sounds,
                         fast 1.2s rebuild after you die
  avatar.gd              The 5-stud six-part avatar. R6IK catalog rig (assets/models/
                         R6IK.fbx) with box fallback; paints, face decal, READABLE
                         nameplate over every player (yours too), old-Roblox clips
                         (Old_Idle/Old_Walk/Old_Jump/Climb — loop modes enforced +
                         a watchdog so they never stick), big white chat bubble,
                         breakup debris (the death camera rides your head)
  avatar_platform.gd     Dresses the avatar from the platform payload: colors,
                         shirt/pants zone-UV clothing, face, 3D UGC (GLB normalized,
                         creator placement VERBATIM, site->Godot 180-degree Y mirror)
  retroblox_api.gd       The one HTTP door: login/signup, /api/platform/me,
                         /api/users/{id}/avatar, /api/assets/{id}, /api/files/{id},
                         data-URL image decoding
  sounds.gd              RetroSounds: slot loader (Hover/OOF/RetroBloxJump/Walking/...)
                         — mp3 wins when present, wav fallback. Drop real files in.
  hud.gd + auth_screen.gd Classic 2008 HUD, all light panels + dark ink for
                         readability: top-left toolbar, top-left chat (readable
                         while typing), roster, ESC menu with a LIGHT players
                         list, top-right health bar, login-only card (baked
                         platform URL, watchdog so it can never trap you),
                         hover ticks + squash on every button
  part.gd / ladder.gd / spawn_location.gd   @tool building blocks: RetroPart,
                         RetroLadder (climb zone on layer 16), SpawnLocation
  arena.gd               Friendly sky + sun + fill lights; loads scenes/maps/*
scenes/
  player.tscn avatar.tscn hud.tscn auth_screen.tscn part.tscn ladder.tscn
  spawn_location.tscn maps/classic_baseplate.tscn
assets/                  R6IK rig, cursors, UI icons, OOF + UI sounds (wav; mp3 preferred)
tests/                   Headless probe — see below
```

## Building a map

Open `scenes/maps/classic_baseplate.tscn` and add nodes: `RetroPart` (set
size + color in the inspector — everything is in studs, 1 unit = 1 stud),
`RetroLadder` (climbable truss), `SpawnLocation` (spawn pads). Parts up to
3 studs tall are walked over automatically (Minecraft-style step-up), so
staircases are just stacked parts — stair steps never grab you into climb
mode. Tall thin ledges (2.5+ studs) climb from their open sides.
`arena.gd` points players at the map's SpawnLocation pads.

## Sounds

`assets/sounds/` holds slots by name: `Hover`, `OOF`, `RetroBloxJump`,
`Walking` (+ UI ticks: click/open/close/deny/success, `jump`, `land`, `step`,
`hover`). **A real `.mp3` with the slot's name replaces the `.wav` instantly
— no code change.** Export/import picks it up automatically.

## Running

- Editor: open the folder in Godot 4.5.1, press Play.
- Multiplayer: automatic — the first player hosts on UDP 42430 and answers
  LAN discovery on 42431; anyone else who starts the game joins their room.
  Dedicated server: `godot -- --server`. Direct join: `--connect=IP`.
- Platform override: `RETROBLOX_API=https://your-site.example` or `--api=…`.

## Controls

- WASD move, SPACE jump (hold to keep hopping), SHIFT shift lock,
  E (hold) orbit the camera with the cursor visible, RMB orbit captured.
- Mouse wheel zoom: all the way IN is FIRST PERSON, all the way OUT is a
  64-stud bird's-eye view.
- ENTER or / chats — you keep walking while you type (chat-walk).
- Ladders: face the climbable face and hold W to grab; W/S ride, nothing
  hangs, SPACE leaps away, looking away lets go.
- ESC menu: Resume / Reset Character (fast ~1.2s rebuild) / Shift Lock /
  sensitivity + volume.

## Validation

```
godot --headless --import . 
godot --headless --check-only --script tests/probe_system.gd .
godot --headless --script tests/probe_system.gd .
```

The probe checks the import, every script parse, the classic constants, the
map's node-built parts, the sound slots, the avatar build and the UGC mirror.
