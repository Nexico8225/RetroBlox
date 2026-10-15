# RetroBlox Player SDK (Godot 4.5+)

The official way to make a RetroBlox game: open this folder in Godot,
press **F5**, and you are playing — signed in, wearing your real account
avatar, chatting on the live platform. Edit a few friendly GDScript
files to make the game YOURS. Everything talks plain HTTP + JSON to
`https://retro-blox.vercel.app` (the same API the website uses).

---

## 1. Quick start (5 minutes)

1. Install **Godot 4.5+** (free, godotengine.org — the standard build).
2. Open Godot → **Import** → pick this folder's `project.godot`.
3. Press **F5** (Run Project). The login screen appears — sign in with
   your RetroBlox account, sign up, or play as a guest.
4. You spawn on Cloud Kingdom wearing YOUR avatar. Press **ESC** for
   the menu (People / Settings), **Enter** to chat.

You are now running a real multiplayer RetroBlox place.

## 2. Make it yours — the 3 files that matter

| File | What it is | Edit it to... |
|------|-----------|----------------|
| `scripts/world/my_place.gd` | **YOUR MAP — a working, commented template** | build your world brick by brick |
| `scripts/world/places.gd` | the built-in places list | add more maps, or remove ours |
| `scripts/game/game.gd` | the play session (world + HUD + win/lose) | change rules, add game logic |

**Start here:** open `scripts/world/my_place.gd`. It is a complete map
documented line by line — spawn pads, a parkour course, a trampoline, a
lava moat, a ladder tower, a gold goal, trees and signs. Edit it, press
F5, and pick **"My Place (template)"** in the place menu. That is the
entire workflow: edit → F5 → play.

### The map format in 20 seconds

A place is one Dictionary. Bricks live in `"parts"`, decorations in
`"props"`:

```gdscript
"parts": [
    { "p": [0, -0.5, 0], "s": [80, 1, 80], "c": "58b64c" },          # the ground
    { "p": [0, 0.5, 20], "s": [5, 1, 5], "c": "cfd4da", "g": "spawn" }, # spawn pad
    { "p": [0, -0.4, -26], "s": [80, 0.8, 8], "c": "e74c3c", "g": "kill" }, # lava!
    { "p": [-14, 8.5, -26], "s": [4, 1, 4], "c": "ffd700", "g": "goal", "m": "metal" },
],
"props": [
    { "type": "sign", "p": [4, 0, 20], "text": "Welcome!" },
    { "type": "tree", "p": [16, 0, 16] },
],
```

- `p` = center position in **studs**, `s` = size in studs, `c` = hex
  color (no `#`)
- groups `g`: `spawn` · `kill` · `ladder` · `goal` · `checkpoint` · `bounce`
- materials `m`: `plastic` · `metal` · `neon` · `wood` · `grass` · `dirt`
- shapes: `box` (default) · `cyl` · `sphere`; `no_studs: true` hides the bumps
- props: `tree` · `flower` · `fence` · `crate` · `cloud` · `cloudpad` ·
  `sign` · `pipe` · `arch` · `snow`
- jump math: a flat jump clears ~12 studs → keep gaps 6–10; 1–2 stud
  ledges step up automatically

When your map is ready, publish it: put your game in a `.zip` and upload
it on retro-blox.vercel.app → **Create** (engine "Godot"). Players
download and play. Ship the same zip as **Source Code** so anyone can
remix it (it already IS the source).

## 3. File map (the guided tour)

```
project.godot            the project (open this in Godot)
scenes/
  login.tscn             the sign-in screen
  game.tscn              the play session
scripts/
  core/
    api.gd               EVERY HTTP call to RetroBlox lives here
    session.gd           who is logged in (token + profile)
    settings.gd          persisted player settings (volume, FPS...)
    sfx.gd               sounds
    ui_config.gd         UI scale/opacity knobs
  player/
    local_player.gd      YOUR character: movement, camera, climbing
    avatar_rig.gd        the R6 blocky avatar (walk/jump/climb/fall anims)
    avatar_dresser.gd    dresses avatars from the account (shirt/pants/hat/face)
    remote_player.gd     other players you see online
    chat_bubble.gd       speech bubbles over heads
  world/
    world_builder.gd     turns a place Dictionary into a live 3D world
    places.gd            the list of built-in places
    my_place.gd          ★ YOUR editable starter map
  game/
    game.gd              the play session: builds the world, HUD, win/lose
    camera_rig.gd        the third-person camera (+ Shift lock)
    chat_box.gd          the chat window
  ui/
    login.gd             the login screen logic
    retro_theme.gd       the RetroBlox look (fonts, buttons, panels)
    menu_icons.gd        hand-drawn menu glyphs (pure code, no textures)
    avatar_viewer.gd     the drag-to-spin rig stage in the ESC menu
    emote_wheel.gd       the emote wheel UI
assets/                  sounds, faces, studs texture, fonts, icons
```

## 4. Change the rules — game.gd hooks

`game.gd` is where gameplay lives. The useful bits:

- `place` — the active place Dictionary (what `WorldBuilder.build` got)
- goal pads fire the win sequence; `kill` parts gibs + respawns you
- the void: falling below `void_y` respawns you
- chat: `chat.add_system("...")` prints a line to everyone's feed
- the API door: `Api` (core/api.gd) is an autoload — call it anywhere

Simple examples you can paste into `game.gd`:

```gdscript
# greet the player by name when the world is built
chat.add_system("Have fun, %s!" % Session.username)

# a coin that counts: put this in _process and move a part first
if player.global_position.distance_to(coin_pos) < 2.0:
        coins += 1
        chat.add_system("Coins: %d" % coins)
```

## 5. The platform API (core/api.gd)

Everything is plain HTTP + JSON — the same endpoints power the website
and the Unity SDK. From any script: `Api.get_json(...)`, `Api.post_json(...)`.

| Call | What it does |
|------|--------------|
| `POST /api/platform/login` | `{username,password}` → `{token, userId, seqId, username}` |
| `POST /api/platform/signup` | create an account in-game (gets its own Player ID) |
| `GET /api/platform/me` | your profile + full avatar payload |
| `GET /api/users/{id}/avatar` | any player's public avatar |
| `GET /api/files/{fileId}` | raw bytes: images, GLB models, audio |
| `GET /api/games?engine=Web` | browse games (Webs are engine "Web") |
| `POST /api/games/{id}/play` | tell the platform you are playing a game |

**Player ID & Game ID:** every account has a short human **Player ID**
(`#1`, `#2`, ... join order) — it comes back from login as `seqId`, and
it is the same number shown on the website profile. Every published game
has a **Game ID** the same way (shown on its game page). Show them off
in your game's HUD: `"%s #%d" % [Session.username, Session.player_seq]`.

## 6. Editing with ChatGPT (yes, really)

These files are written to be READ — by humans and by AIs. The recipe:

1. Attach the file you want to change (for maps: `my_place.gd` — it is
   fully self-contained documentation).
2. Say what you want: *"add a volcano with a kill-brick lava lake and a
   bounce pad to the top"*.
3. Paste the answer back over the file, press F5, play.

Tips: keep one place per Dictionary, keep ids unique, and if Godot
prints a script error it names the file + line — fix and re-run.

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| "Could not reach RetroBlox" | check your internet; the Server field in Settings → Network |
| Spawned as a plain noob | log in on the login screen — avatars come from your account |
| Godot says "Parse Error" | the file+line is in the error; usually a missing comma/quote in a parts list |
| My map didn't change | edit `my_place.gd`, save, F5, and pick "My Place (template)" again in the menu |
| Login works on the site but not in-game | the game talks to `https://retro-blox.vercel.app` — check Settings → Network server URL |

## 8. Publish your game

1. Zip this folder's CONTENTS (project.godot at the zip root).
2. retro-blox.vercel.app → **Create** → engine **Godot** → upload the zip.
3. Upload the same zip as **Source Code** — remixing is the point.
4. Your game gets a Game ID and a page with comments, ratings and plays.

---

### Icon + image credits (downloaded from the internet)

- `assets/icons/menu.png` — hamburger glyph, Pixabay (recolored white)
- `assets/icons/settings.png`, `people.png`, `chat.png`, `respawn.png` — Icons8 (iOS Glyph style, white)
- `assets/icons/close.png` — close badge, Pixabay
- `assets/ui/login_backdrop.jpg` — classic baseplate photograph (Reddit)

> One platform, every engine. Everything here is plain HTTP + JSON against
> `https://retro-blox.vercel.app` — the same API the website and the Unity
> SDK use, so a game made with this kit and a game made in Unity play on
> the same servers, with the same avatars, in the same world.
