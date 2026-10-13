'use client'

/* ================= RetroBlox SDK page (/sdk) =================
   The developer door into the platform — download the official
   RETROBLOX PLAYER (Godot 4.5+): load your avatar, play five
   built-in places with classic studs physics, hold Space to hop,
   use your own cursors, Shift Lock, and CHAT with everyone online
   through the platform API. */

import Link from 'next/link'

const VERSION = 'v12.2 "THE OLD FRONT DOOR"'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=12.2'

const NEW_STUFF: [string, string][] = [
  ['THE OLD LOGIN PAGE IS BACK — IT IS THE SITE\'S OWN', 'The game\'s front door is now the retro-blox.vercel.app sign-in, rebuilt 1:1: the roller-coaster key art, the chunky sprite-letter RETROBLOX wordmark bobbing over it, and the classic white card with the BLUE frame. Log in with the SAME username and password you use on the website — it is the same account, the same database, one platform.'],
  ['CREATE ACCOUNT — REMOVED', 'The Sign Up tab and the Create Account button are GONE from the player. Accounts are made on the website (retro-blox.vercel.app), once; the game just logs you in. Log in once and you never type it again — the saved session signs you in every launch.'],
  ['LOGIN ERRORS SPEAK ENGLISH NOW', 'The server answers with the website\'s exact words: "No account named X exists here yet" vs "Wrong password for X" — so a mistyped password can never again show a useless "Incorrect username or password". The error banner is the site\'s red AuthError style, inside the card.'],
  ['YOUR PROFILE IS SYNCED — THE DEFAULT PFP IS YOUR AVATAR', 'No uploaded picture? Then every face in the client (topbar chip, chat lines, People cards) wears YOUR REAL AVATAR — the site\'s payload photographed headshot-style in-engine. No more letter-N sitting where the golden helmet belongs. Upload a picture on the site and that wins automatically; the letter avatar only returns for guests/offline.'],
  ['THE OLD CHAT ICON — THE BLUE ONE — IS BACK', 'The topbar wears the site\'s blue header gloss again: the white chat bubble on the blue gloss square, the logo key beside it, and the user pill + gear + stats chip all in the same blue. Exactly the v12.0 topbar, back by demand.'],
  ['ADMIN PANEL: ACCOUNT TOOLS', 'The site\'s Admin Panel gained the master key: set any account\'s password (yours included) — the old password stops working everywhere the moment you save. Never locked out again.'],
  ['EVERYTHING FROM v12.1 STAYS', 'Dark retro menu with your full-body avatar in the identity block, PFP + name chat lines, click-to-type / click-off chat, vertical right-edge health bar, working Tiles + List views, Log Out, R6 hitbox, eased arms, 12s bubbles.'],
]

const FILES = [
  ['scripts/core/api.gd', 'The one HTTP door to the platform — auth, avatars, assets, place chat + presence'],
  ['scripts/core/session.gd', 'Who is playing: account, guest state, avatar cache — and the saved login that signs you in automatically next launch'],
  ['scripts/core/settings.gd', 'Every option, persisted + applied live (FOV, volumes, shadows, fullscreen, shift lock, show FPS/ping, max FPS, player names, bunny hop, reset all)'],
  ['scripts/core/sfx.gd', 'All sounds from one place: oof, jump, land, footsteps, climb, wind, goal fanfare + the authentic client sounds'],
  ['scripts/ui/login.gd', 'THE OLD LOGIN, the site\'s own: the roller-coaster key art + the sprite-letter RETROBLOX wordmark (bobbing, hard shadow) + the white card with the blue frame + uppercase labels + white wells + the RED Log In key. LOG IN ONLY — no Create Account. Specific server errors in the site\'s red banner'],
  ['scripts/ui/retro_theme.gd', 'The engine: ARIAL, the RETRO NIGHT slate palette + the site gloss keys, the site letter-avatar palette + pixel glyphs, the circle-badge cropper, icon_png() internet PNGs with a code-drawn fallback, bevels, wells, glass, cursors'],
  ['scripts/ui/pfp_service.gd', 'The PFP engine, SYNCED: custom URL → uploaded avatarUrl (yours via /me, everyone else via GET /api/users/{id}/pfp) → THE DEFAULT = YOUR AVATAR RENDERED headshot-style → letter avatar last resort; peek() for instant chat lines, 6h disk cache v14, rounded corners. NO bundled bacon, NO Roblox thumbnails'],
  ['scripts/core/ui_config.gd', 'YOUR UI, saved: element moves/scales/text, your own labels, global UI scale, your PFP URL — user://ui_config.json, boots with you'],
  ['scripts/ui/ui_editor.gd', 'THE UI EDITOR (F2): pick layer hit-testing, drag to move, X/Y/Scale steppers, text editing, add/remove labels, global zoom, PFP URL, Save/Reset'],
  ['scripts/player/avatar_rig.gd', 'The six-part block avatar (retroblox_anims.fbx rig + box fallback)'],
  ['scripts/player/avatar_dresser.gd', 'Avatar dressing: colors, clothing zones, face decal, placed 3D UGC + finish'],
  ['scripts/player/chat_bubble.gd', 'The classic white speech bubbles — font-metric wrapping (text NEVER spills off the plate), 12s linger, slow fade, stacked the Roblox way'],
  ['scripts/player/local_player.gd', 'Classic controller at the classic size: the REAL R6 hitbox (2x5x1 stud box), WalkSpeed 16, 2-stud gliding STAIRS, ladders + stud-edge grabs, trampolines, fall damage, dust'],
  ['scripts/player/remote_player.gd', 'Everyone else online — presence ghosts that glide between heartbeats'],
  ['scripts/world/world_builder.gd', 'Builds places from parts + props, the AUTHENTIC Roblox stud tile, LINEAR true-color lighting, goal sparkles'],
  ['scripts/world/places.gd', 'The built-in sample places: Cloud Kingdom, Happy Baseplate, Classic Obby, Skylands, Wobbly Tower'],
  ['scripts/game/game.gd', 'The play session: HUD, chat + commands, presence loop, the RETRO NIGHT ESC menu (identity block with your avatar render + PFP badge, tiles/list views, People + Settings tabs, [L]/[R]/[ESC] footer, Log Out), respawn flow, the vertical right-edge health bar'],
  ['scripts/game/chat_box.gd', 'The classic chat: always-visible type box (click to type, click off to release), dark glass log with PFP + name lines, injection-proof'],
  ['scripts/game/camera_rig.gd', 'Orbit camera with collision spring arm, zoom, and Shift Lock shoulder park'],
  ['assets/*.wav|mp3', 'Wind ambience, goal fanfare + the authentic client sounds (oof, jump, land, footsteps)'],
]

const ENDPOINTS = [
  ['POST /api/platform/signup', 'create an account from inside the game (with a #seqId)'],
  ['POST /api/platform/login', 'username + password → session token'],
  ['GET /api/platform/me', 'current player + avatar + your account avatarUrl (Bearer token)'],
  ['GET /api/users/{userId}/avatar', "any player's avatar config (public)"],
  ['GET /api/users/{userId}/pfp', "any player's site profile picture — username + avatarUrl (public, v9.0+)"],
  ['GET /api/assets/{assetId}', 'asset service: color / image / 3D model + finish for an id'],
  ['GET /api/files/{fileId}', 'the actual bytes (images, GLB, audio)'],
  ['GET /api/placechat/{placeId}', 'latest chat lines + who is online (with their live ping/fps)'],
  ['POST /api/placechat/{placeId}', 'send a chat line / presence heartbeat with your ping + fps (Bearer token)'],
  ['GET / PUT /api/gamedata/{gameId}/{key}', 'per-player save data'],
]

const CONTROLS: [string, string][] = [
  ['W A S D / arrows', 'Move (camera-relative, classic)'],
  ['Space', 'Jump — hold to bunny-hop · while on a ladder: JUMP OFF'],
  ['Mouse', 'Look (captured while playing) · wheel zooms'],
  ['Shift', 'SHIFT LOCK — camera parks on your right shoulder, you turn with it, ladders off'],
  ['Enter', 'Open chat · Enter again sends · Esc closes'],
  ['/e sit · /e stop', 'Chat commands — pose your character (move to stand up)'],
  ['/help', 'Lists every command + control in chat'],
  ['P', 'Player list — opens the menu on the People tab'],
  ['F2', 'THE UI EDITOR — move, scale, re-text anything, add labels, save your layout'],
  ['Esc', 'Game menu — People / Settings, [L] Leave / [R] Respawn / [ESC] Resume'],
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
        <div className="rb-panel-head"><span>RetroBlox SDK — the RetroBlox Player {VERSION}</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 17, color: '#1c2733' }}>Load your avatar. Play five places. Collect Tix. Chat with everyone online.</div>
          <div style={{ fontSize: 11, color: '#41586c', marginTop: 4, maxWidth: 660 }}>
            The RetroBlox SDK is the official <b style={{ fontWeight: 400 }}>RetroBlox Player (v3.4)</b> —
            log in once and the game <b style={{ fontWeight: 400 }}>remembers you forever</b>: your account avatar loads from the platform —
            body colors, shirts, pants, face and every 3D UGC accessory placed exactly where its creator left it. Play five
            built-in places at the classic size (1 stud = 1 unit, 5-stud avatar) with classic climbing —
            ladders AND platform edges, Shift Lock, Tix collectibles and the authentic classic sounds — and chat with
            anyone in the same place <b style={{ fontWeight: 400 }}>across the internet</b>, with live
            presence so you see other players walking around. No LAN needed, ever.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap', alignItems: 'center' }}>
            <a className="rb-btn rb-btn-green" href={ZIP_URL} download style={{ textDecoration: 'none', fontSize: 14, padding: '10px 18px' }}>
              ⬇ Download the RetroBlox Player {VERSION} (.zip)
            </a>
            <a href="https://raw.githubusercontent.com/Nexico8225/RetroBlox/main/public/godot/retroblox-godot-player.zip" download style={{ fontSize: 11, color: '#41586c', textDecoration: 'underline', marginLeft: 12 }}>
              mirror: direct from GitHub (always the latest build)
            </a>
            <Link className="rb-btn" href="/avatar" style={{ textDecoration: 'none' }}>Dress your avatar first</Link>
            <Link className="rb-btn" href="/create" style={{ textDecoration: 'none' }}>Publish a game</Link>
          </div>
          <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 8 }}>
            Requires <b style={{ fontWeight: 400 }}>Godot 4.5+</b> (free). Unzip, open the RetroBloxPlayer folder in Godot, press Play.
            The zip is the same folder this page ships from — always the latest build.
          </div>
        </div>
      </div>

      {/* what's new */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>What&apos;s new in {VERSION}</span></div>
        <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 8 }}>
          {NEW_STUFF.map(([t, d]) => (
            <div key={t} style={{ border: '1px solid #e3ecf3', borderRadius: 8, padding: '8px 10px', background: '#f7fbfe' }}>
              <div style={{ fontSize: 12, color: '#0a4f82', fontWeight: 700 }}>{t}</div>
              <div style={{ fontSize: 11, color: '#41586c', marginTop: 2 }}>{d}</div>
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
              <div style={{ fontSize: 11, color: '#41586c', marginBottom: 8 }}>
                Four steps from zip to baseplate:
              </div>
              <pre style={PRE}>{`1. Unzip retroblox-godot-player.zip
2. Open the RetroBloxPlayer folder in Godot 4.5+
3. Press Play (F5)
4. On the login card:
     Log In  — your RetroBlox account
     Sign Up — create an account RIGHT HERE (you get #seqId too)
     (or play as a guest, classic noob style)

The game remembers you — next launch signs you in automatically.
Then pick a place in the hub: Cloud Kingdom, Happy Baseplate,
Classic Obby, Skylands or Wobbly Tower. Chat with ENTER — everyone
in that place sees it, anywhere on the internet. Collect the Tix,
flip on Shift Lock with SHIFT, and jump off ladders with SPACE.`}</pre>
              <div style={{ fontSize: 11, color: '#41586c', marginTop: 8 }}>
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
                <div key={k} style={{ display: 'flex', gap: 10, padding: '5px 2px', borderBottom: '1px solid #edf2f6', alignItems: 'baseline' }}>
                  <span style={{ fontFamily: 'monospace', fontSize: 11, color: '#0a4f82', minWidth: 150 }}>{k}</span>
                  <span style={{ fontSize: 11, color: '#41586c' }}>{d}</span>
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
              <div style={{ fontSize: 11, color: '#41586c', marginTop: 8 }}>
                <b style={{ fontWeight: 400 }}>Security rule:</b> the player never talks to the database —
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
                <div key={f} style={{ padding: '5px 0', borderBottom: '1px solid #edf2f6' }}>
                  <div style={{ fontSize: 11, fontFamily: 'monospace', color: '#0a4f82', wordBreak: 'break-all' }}>{f}</div>
                  <div style={{ fontSize: 10, color: '#5a6b7b' }}>{d}</div>
                </div>
              ))}
            </div>
          </div>

          {/* endpoints */}
          <div className="rb-box">
            <div className="rb-panel-head"><span>Platform API</span></div>
            <div style={{ padding: 10 }}>
              {ENDPOINTS.map(([e, d]) => (
                <div key={e} style={{ padding: '5px 0', borderBottom: '1px solid #edf2f6' }}>
                  <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#0a4f82', wordBreak: 'break-all' }}>{e}</div>
                  <div style={{ fontSize: 10, color: '#5a6b7b' }}>{d}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
