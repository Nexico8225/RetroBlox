'use client'

/* ================= RetroBlox SDK page (/sdk) =================
   The CLASSIC BLUE is back (the user liked the old look — v1.1's
   black & white went too far, so the site wears the 2016 blue again).
   Human words ("Bunny Hop ✅", not paragraphs), and the Unity
   version teased as the upcoming system for Unity users. */

import Link from 'next/link'

const VERSION = 'v4 "ROLES"'
const V_TAG = 'v4'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=4.0'

const INK = '#1c3a52'
const DIM = '#5a6b7b'
const EDGE = '#b6c0cb'

const NEW_STUFF: [string, string][] = [
  ['ROLES — PLAYERS PLAY, GAME DEVS EDIT', 'Three kinds of people: PLAYERS play the game, USERS use the website, GAME DEVS make and edit games. The Studio checks your account when it opens and wears a ROLE chip: GAME DEV unlocks every editor scene; PLAYERS get the editors locked — with a one-sentence tell of how in (publish any game on the site, a Web game counts, and a BECOME A GAME DEV button opens the page for you). The same gate rides the F2 UI editor in-game and the ESC Studio tab.'],
  ['DOWNLOADS FINALLY SAY WHAT THEY ARE', 'A game\'s Download button is the GAME FILE (.retroplace — open it via STUDIO > OPEN GAME FILE), and the green Source Code button on a Godot game page is THE SDK (.zip — the complete Godot project). No more “I downloaded the SDK and got a game file” mixups — every button is labeled and the game page explains both.'],
  ['THE GAME IS ORGANIZED — FOUR SCENES, ONE STUDIO', 'Every thing you can touch now lives in its own scene: PLAY GAME, UI EDITOR, MAP EDITOR, PLAYER EDITOR — all behind one STUDIO door on the login screen (and a new Studio tab in the ESC menu). Each editor saves to your device and rides with you into every game.'],
  ['THE UI EDITOR — DRAG. DROP. DONE.', 'A whole scene for rebuilding the client UI: grab a widget from the shelf (Button, Label, Panel, Text Box, Health Bar, Money), DRAG it onto the stage, drop it, then drag it anywhere. Edit position, size, text, font and one of 12 retro colors per widget. SAVE — and the real game spawns the exact same widgets: your buttons pop toasts, your health bar fills with YOUR health.'],
  ['THE MAP EDITOR — BRICK BY BRICK', 'Build worlds in a real 3D scene: LEFT CLICK places/paints/deletes bricks, RIGHT DRAG orbits, WHEEL zooms, WASD/QE pans. 12 retro colors, 5 brick sizes, 6 materials, and the classic groups (spawn, kill, ladder, goal, checkpoint, bounce). SAVE — your map becomes MY PLACE in the game. TEST PLAY jumps straight in. Bricks are built by the real world builder — the editor looks exactly like the game.'],
  ['THE PLAYER EDITOR — YOUR LOOK', 'Your avatar on a photo stage: drag to spin, three rows of the 12 retro colors for SKIN / SHIRT / PANTS, instant repaint. SAVE — you wear the look in every game (over the noob paint or on top of your site avatar).'],
  ['VIBRANT LIGHTING — GOODBYE DULL', 'The lighting got the Roblox treatment: a big bright uniform fill, blue-tinted sky bounce, a stronger near-white sun, halved fog, and a gentle saturation push on every brick. The world reads LOUD again — vivid bricks, soft blue shadows, zero milk-wash.'],
  ['GAME FILES — DOWNLOAD A GAME, OPEN IT IN STUDIO', 'Games can now ship as .retroplace files: one small JSON with the whole world inside. Download any game on the site, then STUDIO > OPEN GAME FILE and you are playing it. The Map Editor can SAVE FILE (.retroplace) too — build, share, play.'],
  ['EVERYTHING BEFORE STAYS', 'The paint brush, build mode (B), the F2 quick editor, chat, presence, settings, Color World spawn, 2-stud stairs, shift lock — all still here, still yours.'],
]

/* the user's own format: "BunnyHopping(Hold Space to keep jumping)❌ → Bunny Hop✅" */
const RENAMED: [string, string][] = [
  ['BunnyHopping(Hold Space to keep jumping)', 'Bunny Hop'],
  ['Shift lock (also SHIFT key)', 'Shift Lock'],
  ['See player names', 'Player Names'],
  ['Bunny hop — hold Space to keep bouncing', 'Bunny Hop'],
]

const FILES = [
  ['scripts/core/api.gd', 'The one HTTP door to the platform — auth, avatars, assets, place chat + presence'],
  ['scripts/core/session.gd', 'Who is playing: account, guest state, avatar cache, saved auto-login — and the ROLE check (is this account a GAME DEV: owns >= 1 game on the platform)'],
  ['scripts/core/settings.gd', 'All 18 options, persisted + applied LIVE: sensitivity, FOV, 3 volumes, shadows, fullscreen, shift lock, show FPS/ping, Max FPS, render scale, vsync, UI opacity, invert Y, player names, chat bubbles, bunny hop — and Reset All'],
  ['scripts/core/sfx.gd', 'All sounds from one place: oof, jump, land, footsteps, climb, wind, goal fanfare + the authentic client sounds'],
  ['scripts/ui/login.gd', 'THE SIMPLE LOGIN: one flat sky, one bold RETROBLOX wordmark, one clean card — the RED Log In key. LOG IN ONLY. Specific server errors, saved session auto-login'],
  ['scripts/ui/retro_theme.gd', 'The engine: ARIAL, the RETRO NIGHT slate palette, the site gloss keys, letter avatars, pixel glyphs, cursors'],
  ['scripts/ui/menu_icons.gd', 'THE ICON SET: every menu glyph drawn in pure code (draw_polyline/draw_arc) — monochrome white ink, zero textures'],
  ['scripts/ui/avatar_viewer.gd', 'THE LIVE AVATAR STAGE: every ESC-menu card hosts the player\'s real rig in its own SubViewport — drag to spin, drag to tilt, wheel to zoom; renders only while the menu is open'],
  ['scripts/core/ui_config.gd', 'YOUR UI, saved: element moves/scales/text, your own labels, UI EDITOR widgets, global UI scale — user://ui_config.json, boots with you'],
  ['scripts/ui/ui_editor.gd', 'THE QUICK EDITOR (F2, in-game, game devs): pick, drag, X/Y/Scale steppers, text editing, add/remove labels, global zoom, Save/Reset — players pressing F2 get the role banner'],
  ['scripts/editor/ui_widgets.gd', '★ THE WIDGET FACTORY: one build() makes Button / Label / Panel / TextBox / HealthBar / Money look identical in the editor AND in the game — plus spawn_all() for the live HUD'],
  ['scripts/editor/ui_editor_scene.gd', '★ THE UI EDITOR SCENE: widget shelf → drag & drop onto the stage → select, move, resize, recolor → Save rides into every game'],
  ['scripts/editor/map_editor.gd', '★ THE MAP EDITOR SCENE: 3D orbit camera, add/paint/delete tools, colors, sizes, materials, groups — saves user://my_map.json, exports .retroplace, TEST PLAY'],
  ['scripts/editor/player_editor.gd', '★ THE PLAYER EDITOR SCENE: your live rig on a photo stage, drag to spin, skin/shirt/pants color rows — saves user://avatar_colors.json'],
  ['scripts/ui/studio.gd', '★ THE STUDIO HUB: four doors (PLAY / UI / MAP / PLAYER) + OPEN GAME FILE (.retroplace) — with the ROLE chip: game devs unlock the editors, players get told how to become one'],
  ['scripts/player/avatar_rig.gd', 'The six-part block avatar (retroblox_anims.fbx rig + box fallback)'],
  ['scripts/player/avatar_dresser.gd', 'Avatar dressing: colors, clothing zones, face decal, placed 3D UGC + finish'],
  ['scripts/player/chat_bubble.gd', 'The classic white speech bubbles — font-metric wrapping, 12s linger, stacked the Roblox way'],
  ['scripts/player/local_player.gd', 'Classic controller: the REAL R6 hitbox, WalkSpeed 16, INSTANT shift-lock snap, 2-stud STAIRS, ladders, trampolines, fall damage'],
  ['scripts/player/remote_player.gd', 'Everyone else online — presence ghosts that glide between heartbeats'],
  ['scripts/world/world_builder.gd', 'Builds places from parts + props, the AUTHENTIC Roblox stud tile, VIBRANT saturated lighting (v14), goal sparkles'],
  ['scripts/world/places.gd', 'The built-in places: COLOR WORLD (born white — paint it!), Cloud Kingdom, Happy Baseplate, My Place, Classic Obby, Skylands, Wobbly Tower'],
  ['scripts/world/my_place.gd', '★ YOUR MAP — what you build in the MAP EDITOR lands here (user://my_map.json). No save yet? You get the documented living template. Start here!'],
  ['scripts/game/game.gd', 'The play session: HUD, chat + commands, the PAINT BRUSH + BUILD MODE (B key — click places bricks!), presence loop, the ESC MENU (icon rail, live 3D avatars, settings + the UI editor button), respawn flow, vertical health bar'],
  ['scripts/game/chat_box.gd', 'The chat that HIDES until you open it: / or the chat button opens log + type box together, ESC hides everything, injection-proof'],
  ['scripts/game/camera_rig.gd', 'Orbit camera with collision spring arm, zoom, Shift Lock shoulder park — and Invert Y'],
  ['assets/*.wav|mp3', 'Wind ambience, goal fanfare + the authentic client sounds (oof, jump, land, footsteps)'],
]

const ENDPOINTS = [
  ['POST /api/platform/signup', 'create an account from inside the game (with a #seqId)'],
  ['POST /api/platform/login', 'username + password → session token + your PLAYER ID (seqId)'],
  ['GET /api/platform/me', 'current player + avatar + PLAYER ID (seqId) (Bearer token)'],
  ['GET /api/games', 'browse games — ?engine=Web lists the Webs tab, game rows carry their Game ID (seqId)'],
  ['POST /api/games/{id}/play', '“I am playing this game” play counter (Bearer token)'],
  ['GET /api/users/{userId}/avatar', "any player's avatar config (public)"],
  ['GET /api/assets/{assetId}', 'asset service: color / image / 3D model + finish for an id'],
  ['GET /api/files/{fileId}', 'the actual bytes (images, GLB, audio)'],
  ['GET /api/placechat/{placeId}', 'latest chat lines + who is online (with their live ping/fps)'],
  ['POST /api/placechat/{placeId}', 'send a chat line / presence heartbeat (Bearer token)'],
  ['GET / PUT /api/gamedata/{gameId}/{key}', 'per-player save data'],
]

const CONTROLS: [string, string][] = [
  ['W A S D / arrows', 'Move (camera-relative, classic)'],
  ['Space', 'Jump — hold to Bunny Hop · while on a ladder: JUMP OFF'],
  ['Mouse', 'Look (captured while playing) · wheel zooms'],
  ['Shift', 'SHIFT LOCK — camera parks on your right shoulder, you turn with it'],
  ['Enter', 'Open chat · Enter again sends · Esc closes'],
  ['/e sit · /e stop', 'Chat commands — pose your character'],
  ['/help', 'Lists every command + control in chat'],
  ['P', 'Player list — opens the menu on People'],
  ['F2', 'THE UI EDITOR — move, scale, re-text anything'],
  ['Esc', 'Game menu — People / Settings on the icon rail, Leave / Respawn / Resume'],
]

const PRE: React.CSSProperties = {
  background: '#122b41',
  color: '#cfe6f7',
  padding: 12,
  fontSize: 11,
  fontFamily: 'Courier New, monospace',
  overflowX: 'auto',
  lineHeight: 1.5,
  border: '1px solid #0d3054',
  whiteSpace: 'pre',
}

export function SdkView() {
  return (
    <div>
      {/* hero */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>The RetroBlox Player — official SDK ({V_TAG})</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 17, color: INK }}>FOUR SCENES: PLAY the world, DRAG & DROP your UI, BUILD maps brick by brick, PAINT your player. Players play — GAME DEVS edit. Lighting: vibrant.</div>
          <div style={{ marginTop: 6 }}>
            <span style={{ fontSize: 10, fontWeight: 700, color: '#00639e', background: '#e1f2fb', border: '1px solid #b5d9ee', padding: '2px 8px', borderRadius: 3 }}>{VERSION}</span>
          </div>
          <div style={{ fontSize: 11, color: DIM, marginTop: 4, maxWidth: 660 }}>
            The RetroBlox SDK is the official <b style={{ fontWeight: 600 }}>RetroBlox Player</b> —
            log in once and the game <b style={{ fontWeight: 600 }}>remembers you forever</b>: your account avatar loads from the platform —
            body colors, shirts, pants, face and every 3D UGC accessory placed exactly where its creator left it. You spawn in
            COLOR WORLD — every brick is born WHITE and your LEFT CLICK paints it with the palette; then explore more
            built-in places at the classic size (1 stud = 1 unit, 5-stud avatar) with classic climbing,
            Shift Lock, Tix collectibles, the authentic classic sounds — and chat with
            anyone in the same place <b style={{ fontWeight: 600 }}>across the internet</b>. No LAN needed, ever.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap', alignItems: 'center' }}>
            <a className="rb-btn rb-btn-green" href={ZIP_URL} download style={{ textDecoration: 'none', fontSize: 14, padding: '10px 18px' }}>
              ⬇ Download the RetroBlox Player ({V_TAG}) (.zip)
            </a>
            <a href="https://raw.githubusercontent.com/Nexico8225/RetroBlox/main/public/godot/retroblox-godot-player.zip" download style={{ fontSize: 11, color: DIM, textDecoration: 'underline', marginLeft: 12 }}>
              mirror: direct from GitHub (always the latest build)
            </a>
            <Link className="rb-btn" href="/avatar" style={{ textDecoration: 'none' }}>Dress your avatar first</Link>
            <Link className="rb-btn" href="/create" style={{ textDecoration: 'none' }}>Publish a game</Link>
          </div>
          <div style={{ fontSize: 10, color: DIM, marginTop: 8 }}>
            Requires <b style={{ fontWeight: 600 }}>Godot 4.5+</b> (free). Unzip, open the RetroBloxPlayer folder in Godot, press Play.
            The zip is the same folder this page ships from — always the latest build. <b style={{ fontWeight: 600 }}>Heads up:</b> downloading a <b style={{ fontWeight: 600 }}>game</b> on the site gives you that game's file — THIS button is the one that gives the SDK.
          </div>
          {/* the upcoming Unity system */}
          <div style={{ marginTop: 14, border: '1px solid #005f9c', background: 'linear-gradient(180deg, #0f83c9 0%, #00639e 100%)', color: '#fff', padding: '12px 14px', display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: 0.4, textShadow: '0 1px 1px rgba(0,0,0,.3)' }}>UNITY VERSION — IN THE WORKS</div>
            <div style={{ fontSize: 11, color: '#d7ecfa', flex: 1, minWidth: 260 }}>
              The same RetroBlox — accounts, avatars, chat, presence — as an upcoming system built for Unity users. It is being worked on right now. Watch this space.
            </div>
            <span style={{ fontSize: 10, border: '1px solid #7cbde0', background: 'rgba(255,255,255,.14)', color: '#fff', padding: '3px 10px', whiteSpace: 'nowrap' }}>COMING SOON</span>
          </div>
        </div>
      </div>

      {/* what's new */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>What&apos;s new in {V_TAG}</span></div>
        <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 8 }}>
          {NEW_STUFF.map(([t, d]) => (
            <div key={t} style={{ border: '1px solid ' + EDGE, padding: '8px 10px', background: '#ffffff' }}>
              <div style={{ fontSize: 12, color: INK, fontWeight: 600 }}>{t}</div>
              <div style={{ fontSize: 11, color: DIM, marginTop: 2 }}>{d}</div>
              {t.startsWith('HUMAN NAMES') && (
                <div style={{ marginTop: 8, display: 'grid', gap: 4 }}>
                  {RENAMED.map(([bad, good]) => (
                    <div key={bad} style={{ fontSize: 11, fontFamily: 'monospace' }}>
                      <span style={{ color: DIM, textDecoration: 'line-through' }}>{bad}</span>
                      <span style={{ color: DIM }}> ❌</span>
                      <span style={{ color: INK, fontWeight: 600 }}>   {good} ✅</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'flex-start' }}>
        <div style={{ flex: 1, minWidth: 300 }}>
          {/* quick start */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>Quick Start</span></div>
            <div style={{ padding: 12 }}>
              <div style={{ fontSize: 11, color: DIM, marginBottom: 8 }}>
                Four steps from zip to baseplate:
              </div>
              <pre style={PRE}>{`1. Unzip retroblox-godot-player.zip
2. Open the RetroBloxPlayer folder in Godot 4.5+
3. Press Play (F5) — you spawn into the world
4. On the login card:
     Log In  — your RetroBlox account
     STUDIO  — the editors (UI / Map / Player)
               (game devs: publish any game on the
                site and every editor unlocks)
     (or play as a guest, classic noob style)

The game remembers you — next launch signs you in automatically.
STUDIO is the organized way in: four scenes, one hub. Build a map in
the MAP EDITOR and it becomes MY PLACE. Drag widgets in the UI EDITOR
and they ride into every game. Paint your look in the PLAYER EDITOR.
Chat with ENTER — everyone sees it, anywhere on the internet.`}</pre>
              <div style={{ fontSize: 11, color: DIM, marginTop: 8 }}>
                You spawn wearing your account avatar — change it on the website and every place wears the
                new look. Kill bricks, checkpoints, trampolines, the original oof and a music box included.
              </div>
            </div>
          </div>

          {/* controls */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>Controls</span></div>
            <div style={{ padding: 10 }}>
              {CONTROLS.map(([k, d]) => (
                <div key={k} style={{ display: 'flex', gap: 10, padding: '5px 2px', borderBottom: '1px solid #efefef', alignItems: 'baseline' }}>
                  <span style={{ fontFamily: 'monospace', fontSize: 11, color: INK, minWidth: 150 }}>{k}</span>
                  <span style={{ fontSize: 11, color: DIM }}>{d}</span>
                </div>
              ))}
            </div>
          </div>

          {/* how the avatar flows */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>How the Avatar Flows</span></div>
            <div style={{ padding: 12 }}>
              <pre style={PRE}>{`   RetroBlox website or the in-game Sign Up card
              |
   POST /api/platform/signup    create an account inside the game
   POST /api/platform/login     username + password -> session token
   GET  /api/platform/me        token -> your account-wide avatar
   GET  /api/users/{id}/avatar  every player fetches EVERYONE's look
   GET  /api/assets/{assetId}   asset ids -> color / image / 3D model + finish
   GET  /api/files/{fileId}     the actual bytes (images, GLB, audio)
              |
   GET  /api/placechat/{placeId}   chat lines + who is online right now
   POST /api/placechat/{placeId}   send a line / "I am here at x,y,z" heartbeat
              |
   The player paints every avatar in the place with the website render,
   and the platform relays chat + presence so places feel multiplayer.`}</pre>
              <div style={{ fontSize: 11, color: DIM, marginTop: 8 }}>
                <b style={{ fontWeight: 600 }}>Security rule:</b> the player never talks to the database —
                only to the RetroBlox API, which validates the session before returning anything.
                The avatar belongs to the ACCOUNT: change it on the website and every game sees the new
                look. <code style={{ fontFamily: 'monospace' }}>GET /api/users/&#123;userId&#125;/avatar</code> also
                returns any player&apos;s avatar publicly, so multiplayer games can spawn OTHER players
                wearing their real looks.
              </div>
            </div>
          </div>
        </div>

        <div style={{ width: 300, flexShrink: 0 }}>
          {/* what's in the box */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>What&apos;s in the zip</span></div>
            <div style={{ padding: 10 }}>
              {FILES.map(([f, d]) => (
                <div key={f} style={{ padding: '5px 0', borderBottom: '1px solid #efefef' }}>
                  <div style={{ fontSize: 11, fontFamily: 'monospace', color: INK, wordBreak: 'break-all' }}>{f}</div>
                  <div style={{ fontSize: 10, color: DIM }}>{d}</div>
                </div>
              ))}
            </div>
          </div>

          {/* endpoints */}
          <div className="rb-box">
            <div className="rb-panel-head"><span>Platform API</span></div>
            <div style={{ padding: 10 }}>
              {ENDPOINTS.map(([e, d]) => (
                <div key={e} style={{ padding: '5px 0', borderBottom: '1px solid #efefef' }}>
                  <div style={{ fontSize: 10, fontFamily: 'monospace', color: INK, wordBreak: 'break-all' }}>{e}</div>
                  <div style={{ fontSize: 10, color: DIM }}>{d}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
