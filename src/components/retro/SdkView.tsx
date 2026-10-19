'use client'

/* ================= RetroBlox SDK page (/sdk) =================
   v7 — said like a human. Godot icon on the hero, Unity icon on
   the "coming soon" banner. No UI Studio, no templates: the SDK
   is the game, the game is the SDK. */

import Link from 'next/link'

const V_TAG = 'v7'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=9.0'

const INK = '#1c3a52'
const DIM = '#5a6b7b'
const EDGE = '#b6c0cb'

const FEATURES: [string, string][] = [
  ['Play real multiplayer places', 'Walk, jump and climb with other players online. Chat, friends, avatars — the works.'],
  ['Build', 'Press B in game and place bricks on anything. The Map Editor turns your map into your own place.'],
  ['Paint', 'Press C, pick a color, click a brick. The whole world takes paint.'],
  ['Your look', 'Your site avatar spawns with you. The Player Editor repaints it right on your device.'],
  ['Make games', 'Publish what you build to the site with one upload. Game files share as .retroplace.'],
  ['Free and open', 'The zip is a plain Godot 4.5 project. Read it, change it, ship your own version.'],
]

const FILES = [
  ['project.godot', 'The Godot project — open this'],
  ['scenes/', 'Login, game, studio, editors'],
  ['scripts/game/', 'The play session: controls, chat, HUD, build + paint'],
  ['scripts/world/', 'The built-in places and the world builder'],
  ['scripts/player/', 'The block avatar and its controller'],
  ['scripts/ui/', 'Login screen, menus, settings'],
  ['scripts/editor/', 'The UI, map and player editors'],
  ['scripts/core/', 'The API client, session, settings, sounds'],
  ['assets/', 'Sounds, icons, fonts'],
]

const ENDPOINTS = [
  ['POST /api/platform/signup', 'create an account'],
  ['POST /api/platform/login', 'get a session token'],
  ['GET /api/platform/me', 'your player + avatar'],
  ['GET /api/games', 'browse games'],
  ['GET /api/users/{id}/avatar', "any player's avatar"],
  ['GET /api/placechat/{placeId}', 'place chat + who is online'],
  ['POST /api/placechat/{placeId}', 'chat + presence heartbeat'],
  ['GET / PUT /api/gamedata/{gameId}/{key}', 'per-player save data'],
]

const CONTROLS: [string, string][] = [
  ['W A S D', 'Move'],
  ['Space', 'Jump (hold to keep bouncing)'],
  ['Mouse', 'Look — wheel zooms'],
  ['Shift', 'Shift Lock'],
  ['Enter', 'Chat'],
  ['C', 'Paint colors'],
  ['Left click', 'Paint the brick you aim at'],
  ['B', 'Build mode — click places a brick'],
  ['F2', 'Move and re-text the HUD'],
  ['Esc', 'Menu — people, settings, leave'],
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

function GodotIcon({ size = 44 }: { size?: number }) {
  return (
    <img src="/icons/godot-icon.svg" alt="Godot" width={size} height={size} style={{ display: 'block' }} draggable={false} />
  )
}

function UnityIcon({ size = 34 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" role="img" aria-label="Unity" style={{ display: 'block' }}>
      <path fill="#ffffff" d="m12.9288 4.2939 3.7997 2.1929c.1366.077.1415.2905 0 .3675l-4.515 2.6076a.4192.4192 0 0 1-.4246 0L7.274 6.8543c-.139-.0745-.1415-.293 0-.3675l3.7972-2.193V0L1.3758 5.5977V16.793l3.7177-2.1456v-4.3858c-.0025-.1565.1813-.2682.318-.1838l4.5148 2.6076a.4252.4252 0 0 1 .2136.3676v5.2127c.0025.1565-.1813.2682-.3179.1838l-3.7996-2.1929-3.7178 2.1457L12 24l9.6954-5.5977-3.7178-2.1457-3.7996 2.1929c-.1341.082-.3229-.0248-.3179-.1838V13.053c0-.1565.087-.2956.2136-.3676l4.5149-2.6076c.134-.082.3228.0224.3179.1838v4.3858l3.7177 2.1456V5.5977L12.9288 0Z" />
    </svg>
  )
}

export function SdkView() {
  return (
    <div>
      {/* hero */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>The RetroBlox Player — official SDK ({V_TAG})</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start', flexWrap: 'wrap' }}>
            <div style={{ background: '#1c3a52', border: `1px solid ${EDGE}`, borderRadius: 6, padding: 8 }}>
              <GodotIcon />
            </div>
            <div style={{ flex: 1, minWidth: 260 }}>
              <div style={{ fontSize: 16, color: INK, fontWeight: 700 }}>The whole game, free to run and edit.</div>
              <div style={{ fontSize: 12, color: DIM, marginTop: 6, maxWidth: 640, lineHeight: 1.55 }}>
                The SDK is the RetroBlox Player: a Godot project that logs into this site and plays every place
                with other people online. You spawn with your avatar, you can build and paint the world,
                and whatever you make can be published back to the site as its own game.
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14, flexWrap: 'wrap', alignItems: 'center' }}>
            <a className="rb-btn rb-btn-green" href={`/download?u=${encodeURIComponent(ZIP_URL)}&n=retroblox-godot-player.zip`} target="_blank" rel="noreferrer" style={{ textDecoration: 'none', fontSize: 14, padding: '10px 18px' }}>
              Download the player ({V_TAG}) — .zip
            </a>
            <a href="https://raw.githubusercontent.com/Nexico8225/RetroBlox/main/public/godot/retroblox-godot-player.zip" download style={{ fontSize: 11, color: DIM, textDecoration: 'underline' }}>
              direct mirror on GitHub
            </a>
            <Link className="rb-btn" href="/avatar" style={{ textDecoration: 'none' }}>Dress your avatar</Link>
            <Link className="rb-btn" href="/create" style={{ textDecoration: 'none' }}>Publish a game</Link>
          </div>
          <div style={{ fontSize: 11, color: DIM, marginTop: 10 }}>
            Made for <b style={{ fontWeight: 600 }}>Godot 4.5+</b> (free). Unzip, open the RetroBloxPlayer folder in Godot, press Play.
            Downloading a <b style={{ fontWeight: 600 }}>game</b> on the site gives you that game&apos;s file — this button gives you the player.
          </div>

          {/* the upcoming Unity version */}
          <div style={{ marginTop: 14, border: '1px solid #005f9c', background: 'linear-gradient(180deg, #0f83c9 0%, #00639e 100%)', color: '#fff', padding: '12px 14px', display: 'flex', gap: 14, alignItems: 'center', flexWrap: 'wrap' }}>
            <div style={{ background: 'rgba(0,0,0,.22)', borderRadius: 6, padding: 6 }}>
              <UnityIcon />
            </div>
            <div style={{ flex: 1, minWidth: 240 }}>
              <div style={{ fontSize: 13, fontWeight: 600 }}>A Unity version is coming</div>
              <div style={{ fontSize: 11, color: '#d7ecfa', marginTop: 2 }}>
                Same accounts, same avatars, same places — built for Unity. In development.
              </div>
            </div>
            <span style={{ fontSize: 10, border: '1px solid #7cbde0', background: 'rgba(255,255,255,.14)', color: '#fff', padding: '3px 10px', whiteSpace: 'nowrap' }}>COMING SOON</span>
          </div>
        </div>
      </div>

      {/* what it does */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>What it does</span></div>
        <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 8 }}>
          {FEATURES.map(([t, d]) => (
            <div key={t} style={{ border: `1px solid ${EDGE}`, padding: '8px 10px', background: '#ffffff' }}>
              <div style={{ fontSize: 12, color: INK, fontWeight: 600 }}>{t}</div>
              <div style={{ fontSize: 11, color: DIM, marginTop: 2 }}>{d}</div>
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
              <pre style={PRE}>{`1. Unzip retroblox-godot-player.zip
2. Open the RetroBloxPlayer folder in Godot 4.5+
3. Press Play (F5)
4. Log in on the login card — or play as a guest

Next launch signs you in automatically.`}</pre>
              <div style={{ fontSize: 11, color: DIM, marginTop: 8 }}>
                The editors live behind the STUDIO button on the login screen: build a map and it becomes
                your place, repaint your avatar, rearrange the HUD (F2 works in game too).
              </div>
            </div>
          </div>

          {/* controls */}
          <div className="rb-box" style={{ marginBottom: 12 }}>
            <div className="rb-panel-head"><span>Controls</span></div>
            <div style={{ padding: 10 }}>
              {CONTROLS.map(([k, d]) => (
                <div key={k} style={{ display: 'flex', gap: 10, padding: '5px 2px', borderBottom: '1px solid #efefef', alignItems: 'baseline' }}>
                  <span style={{ fontFamily: 'monospace', fontSize: 11, color: INK, minWidth: 110 }}>{k}</span>
                  <span style={{ fontSize: 11, color: DIM }}>{d}</span>
                </div>
              ))}
            </div>
          </div>

          {/* the API */}
          <div className="rb-box">
            <div className="rb-panel-head"><span>How it talks to the site</span></div>
            <div style={{ padding: 12 }}>
              <pre style={PRE}>{`login  ->  POST /api/platform/login  ->  session token
me     ->  GET  /api/platform/me      ->  your avatar
play   ->  GET  /api/placechat/{id}   ->  chat + who is online
save   ->  GET/PUT /api/gamedata/...  ->  per-player saves

The player never touches the database — only this API.`}</pre>
              <div style={{ fontSize: 11, color: DIM, marginTop: 8 }}>
                Every endpoint is plain HTTP + JSON, so any engine can use it. The full list lives in
                <code style={{ fontFamily: 'monospace' }}> scripts/core/api.gd</code> inside the zip.
              </div>
            </div>
          </div>
        </div>

        <div style={{ width: 300, flexShrink: 0 }}>
          {/* what's in the zip */}
          <div className="rb-box">
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
        </div>
      </div>
    </div>
  )
}
