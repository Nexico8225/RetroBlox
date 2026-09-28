'use client'

/* ================= RetroBlox Game Kit page (/sdk) =================
   The developer door into the platform — the RETROBLOX PLAYER
   SYSTEM: a downloadable classic multiplayer player (Godot 4.5+)
   that logs you in, pulls the account avatar from the API and plays
   on a shared baseplate. Everything in it is nodes + exports devs edit. */

import Link from 'next/link'

const FILES = [
  ['scenes/', 'EVERYTHING is editable nodes: hud.tscn (toolbar, health bar, chat, menu, UI animations + sounds), auth_screen.tscn, player.tscn, avatar.tscn, maps/classic_baseplate.tscn'],
  ['scripts/player.gd', 'Classic character controller — Inspector exports: walk speed, jump height, gravity, can_climb, sounds'],
  ['scripts/main.gd', 'Multiplayer, login flow (auto sign-in + Log Out), camera, Shift Lock'],
  ['scripts/auth_screen.gd', 'The login card (login-only — accounts are made on the website)'],
  ['scripts/avatar.gd', 'The six-part block avatar — painted by your account'],
  ['scripts/avatar_platform.gd', 'Avatar dressing: colors, clothing zones, face decal, verbatim 3D UGC'],
  ['scripts/arena.gd', 'Sky + sun + auto-ladders: thin platforms & classic rungs climb by themselves'],
  ['scripts/retroblox_api.gd', 'The one HTTP door to the platform (login / me / avatars / assets / files)'],
  ['assets/sounds/', 'Built-in retro SFX: jump, land, footsteps, UI click / hover / open / close, success, deny'],
]

const ENDPOINTS = [
  ['POST /api/platform/login', 'username + password → session token'],
  ['GET /api/platform/me', 'current player + avatar (Bearer token)'],
  ['GET /api/users/{userId}/avatar', "any player's avatar config (public)"],
  ['GET /api/assets/{assetId}', 'asset service: color / image / 3D model for an id'],
  ['GET /api/files/{fileId}', 'the actual bytes (images, GLB, audio)'],
  ['GET / PUT /api/gamedata/{gameId}/{key}', 'per-player save data'],
]

const CONTROLS: [string, string][] = [
  ['W A S D / arrows', 'Move (camera-relative, classic)'],
  ['Space', 'Jump'],
  ['Right-mouse drag', 'Orbit the camera'],
  ['Mouse wheel', 'Zoom all the way to first person'],
  ['Shift', 'SHIFT LOCK — mouse locks, camera sits on your right shoulder'],
  ['Enter', 'Chat · Esc opens the game menu'],
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
        <div className="rb-panel-head"><span>RetroBlox Game Kit — the RetroBlox Player System</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 17, color: '#1c2733' }}>Download the player. Log in once. You&apos;re in.</div>
          <div style={{ fontSize: 11, color: '#41586c', marginTop: 4, maxWidth: 660 }}>
            The RetroBlox Game Kit is the official <b style={{ fontWeight: 400 }}>RetroBlox Player system</b> — a
            classic multiplayer world you download and run on your machine. Log in with your site
            account and your avatar loads from the platform API: body colors, shirts, pants, face
            and 3D UGC placed exactly where their creators left them, at true stud scale
            (1 stud = 0.28 m). Everyone in the room sees your real look. Shift Lock, the Esc game
            menu, chat with speech bubbles, LAN auto-join, built-in sounds — and it all ships as
            editable Godot scenes and Inspector exports so you can build your own game on it.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
            <a className="rb-btn rb-btn-green" href="/godot/retroblox-godot-player.zip" download style={{ textDecoration: 'none' }}>
              ⬇ Download the RetroBlox Player (.zip)
            </a>
            <Link className="rb-btn" href="/avatar" style={{ textDecoration: 'none' }}>Dress your avatar first</Link>
            <Link className="rb-btn" href="/create" style={{ textDecoration: 'none' }}>Publish a game</Link>
          </div>
          <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 8 }}>
            Requires <b style={{ fontWeight: 400 }}>Godot 4.5+</b> (free). Unzip, open the folder in Godot, press Play —
            a second copy on the same network joins your game automatically.
          </div>
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
4. Log in with your RetroBlox account
   (or play as a guest, classic noob style)

The game remembers you — next launch signs you in
automatically. Log Out lives in the ESC menu.
LAN: a second copy of the game on your network joins
you by itself.`}</pre>
              <div style={{ fontSize: 11, color: '#41586c', marginTop: 8 }}>
                You spawn wearing your account avatar — change it on the website and every login after
                that wears the new look. Press SHIFT for Shift Lock: the camera locks on your right
                shoulder and your character turns with it.
              </div>
            </div>
          </div>

          {/* controls */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>Controls</span></div>
            <div style={{ padding: 10 }}>
              {CONTROLS.map(([k, d]) => (
                <div key={k} style={{ display: 'flex', gap: 10, padding: '5px 2px', borderBottom: '1px solid #edf2f6', alignItems: 'baseline' }}>
                  <span style={{ fontFamily: 'monospace', fontSize: 11, color: '#0a4f82', minWidth: 140 }}>{k}</span>
                  <span style={{ fontSize: 11, color: '#41586c' }}>{d}</span>
                </div>
              ))}
            </div>
          </div>

          {/* how the avatar flows */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>How the Avatar Flows</span></div>
            <div style={{ padding: 12 }}>
              <pre style={PRE}>{`   RetroBlox website (make your account there)
              |
   POST /api/platform/login     username + password -> session token
   GET  /api/platform/me        token -> your account-wide avatar
   GET  /api/users/{id}/avatar  every player fetches EVERYONE's look
   GET  /api/assets/{assetId}   asset ids -> color / image / 3D model
   GET  /api/files/{fileId}     the actual bytes (images, GLB, audio)
              |
   The player paints every avatar in the room with the website render.`}</pre>
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
