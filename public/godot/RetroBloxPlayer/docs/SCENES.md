# Where is everything? (the scenes look "empty" — on purpose)

Open `scenes/game.tscn` in the Godot editor and you see almost no nodes.
That is NOT an oversight: **every scene builds its content in code, at
runtime.** The .tscn files are one root node with a script attached — the
script IS the scene. That is what makes everything here editable as plain
GDScript instead of hunting through a node tree.

## What you WILL find, and where it really lives

| Scene file | Root script | The actual content |
|---|---|---|
| `scenes/game.tscn` | `scripts/game/game.gd` | The whole world: WorldBuilder builds every brick, the HUD, chat, ESC menu, paint bar, your widgets — all constructed in `_build_hud()` + friends |
| `scenes/studio.tscn` | `scripts/ui/studio.gd` | The four STUDIO doors + role gate, built in `_ready()` |
| `scenes/ui_editor.tscn` | `scripts/editor/ui_editor_scene.gd` | The widget shelf + drag & drop stage |
| `scenes/map_editor.tscn` | `scripts/editor/map_editor.gd` | The 3D brick stage, toolbars, color rows |
| `scenes/player_editor.tscn` | `scripts/editor/player_editor.gd` | The avatar photo stage + color rows |
| `scenes/login.tscn` | `scripts/ui/login.gd` | The wordmark, the card, the STUDIO door |

## How to actually edit things

**Nodes + scripts, for real:**
- Everything is plain GDScript — open `scripts/game/game.gd`, find
  `_build_hud()`, and change anything: colors, sizes, new panels, new keys.
- Section 6 of the README lists the exact hooks (respawn seconds, paint
  colors, WalkSpeed…).
- New behavior = new func + one call site. Press F5, see it live.

**Map:** STUDIO → MAP EDITOR (brick by brick, groups: spawn/kill/goal…),
or edit `scripts/world/my_place.gd` directly — it is a parts list.

**UI:** STUDIO → UI EDITOR in-game (drag & drop widgets), or the site's
**UI Studio** page (retro-blox.vercel.app/ui-studio) to publish a UI that
every player of your game sees — text, icons, images, link buttons and
click/hover FX. Widget JSON is plain dictionaries in `ui_config.gd`.

**Player:** STUDIO → PLAYER EDITOR (colors on your live rig), or
`scripts/player/avatar_rig.gd` for the rig itself.

## Why not "real" node trees?

A node tree saved in a .tscn is frozen data. A parts list / widget list in
code is live data you can loop, remix and generate — the same dictionary
format flows from the Map Editor, the UI Editor, the site's UI Studio and
the .retroplace game files into one WorldBuilder / UiWidgets factory.
Edit the factory, and the editors, the game AND the website all change
together.
