'use client'

/* ================= RetroBlox SDK page (/sdk) =================
   The developer door into the platform — download the official
   RETROBLOX PLAYER (Godot 4.5+): load your avatar, play five
   built-in places with classic studs physics, hold Space to hop,
   use your own cursors, Shift Lock, and CHAT with everyone online
   through the platform API. */

import Link from 'next/link'

const VERSION = 'v7.0 "CLASSIC"'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=7.0'

const NEW_STUFF: [string, string][] = [
  ['A COMPLETELY NEW UI — the CLASSIC 2008-2013 CLIENT look', 'Every pixel of the client chrome is rebuilt in the retro gray you remember: chunky BEVELED panels (a light top-left rim, a dark bottom-right rim, generated 9-patch textures tinted per face), Arial on every title, button and name (Liberation Sans — the metric-perfect Arial), small tight corner radii, hard dark drop shadows. Nothing glassy, nothing borderless-modern — it reads like the client you grew up on.'],
  ['The CLASSIC GREEN action key + ROBLOX red', 'Resume and LOG IN are the old-site GREEN keys that sink when pressed; Leave speaks in the ROBLOX red; the one Roblox blue stays as the selection accent (your People card, the lit nav icon). The health bar is the classic SUNKEN track with the pure-green fill and the number inside.'],
  ['The classic beveled LOGIN window', 'A gray beveled window on a deep backdrop with a faint STUD GRID: the tilted red logo tile + RETROBLOX wordmark in bold Arial with a drop shadow, chunky beveled LOG IN / SIGN UP tabs, sunken input wells, the green LOG IN key — the old front door, rebuilt.'],
  ['The ESC menu — the classic gray window', 'Title bar with a dark rule under it, the icon rail, People cards that SINK like list slots (yours wears the blue selection frame), beveled keys in the footer: green Resume, dark Reset / Log Out, red Leave. Chat panels keep the thin light frame, Arial everywhere.'],
  ['Everything sharp stays sharp', 'The portrait pipeline (320x448 + 4x MSAA), 4x world MSAA, anisotropic stud tiles and LINEAR true-color lighting all carry over — the classic look is chrome-only, the world stays crisp.'],
]

const FILES = [
  ['scripts/core/api.gd', 'The one HTTP door to the platform — auth, avatars, assets, place chat + presence'],
  ['scripts/core/session.gd', 'Who is playing: account, guest state, avatar cache — and the saved login that signs you in automatically next launch'],
  ['scripts/core/settings.gd', 'Every option, persisted + applied live (FOV, volumes, shadows, fullscreen, shift lock)'],
  ['scripts/core/sfx.gd', 'All sounds from one place: oof, jump, land, footsteps, climb, wind, goal fanfare + the authentic client sounds'],
  ['scripts/ui/login.gd', 'The in-game login / SIGN UP window — the classic beveled look, server URL locked, guests welcome'],
  ['scripts/ui/retro_theme.gd', 'The v7.0 CLASSIC UI: generated 9-patch bevel textures (raised keys + sunken wells tinted per face), Arial (Liberation Sans) voice, the classic GREEN primary key + ROBLOX red, code-drawn icons, your cursors'],
  ['scripts/ui/avatar_portrait.gd', 'Renders each player\'s REAL avatar at 320x448 with 4x MSAA for the ESC menu People cards (offscreen viewport, cached)'],
  ['scripts/player/avatar_rig.gd', 'The six-part block avatar (retroblox_anims.fbx rig + box fallback)'],
  ['scripts/player/avatar_dresser.gd', 'Avatar dressing: colors, clothing zones, face decal, placed 3D UGC + finish'],
  ['scripts/player/chat_bubble.gd', 'The classic white speech bubbles — they STACK the Roblox way, up to three live'],
  ['scripts/player/local_player.gd', 'Classic controller at the classic size: WalkSpeed 16, 2-stud gliding STAIRS, ladders + stud-edge grabs (face-to-climb, look-away = fall), trampolines, fall damage, dust'],
  ['scripts/player/remote_player.gd', 'Everyone else online — presence ghosts that glide between heartbeats'],
  ['scripts/world/world_builder.gd', 'Builds places from parts + props, the AUTHENTIC Roblox stud tile, LINEAR true-color lighting, goal sparkles'],
  ['scripts/world/places.gd', 'The built-in sample places: Cloud Kingdom, Happy Baseplate, Classic Obby, Skylands, Wobbly Tower'],
  ['scripts/game/game.gd', 'The play session: HUD, chat + commands, presence loop, the classic-client ESC menu (player cards + live stats), respawn flow'],
  ['scripts/game/chat_box.gd', 'The classic chat log + type box that open and close as ONE widget, injection-proof'],
  ['scripts/game/camera_rig.gd', 'Orbit camera with collision spring arm, zoom, and Shift Lock shoulder park'],
  ['assets/*.wav|mp3', 'Wind ambience, goal fanfare + the authentic client sounds (oof, jump, land, footsteps)'],
]

const ENDPOINTS = [
  ['POST /api/platform/signup', 'create an account from inside the game (with a #seqId)'],
  ['POST /api/platform/login', 'username + password → session token'],
  ['GET /api/platform/me', 'current player + avatar (Bearer token)'],
  ['GET /api/users/{userId}/avatar', "any player's avatar config (public)"],
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
  ['P', 'Player list — who is in the place right now'],
  ['Esc', 'Game menu — resume / respawn / leave place'],
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
