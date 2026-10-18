'use client'

/* ================= RetroBlox Game Templates (/templates) =================
   v7 — every template downloads as a REAL Godot 4.5 project zip: open it in
   the Godot editor, press F5, the game runs. Edit any brick (each part is a
   real node), any script, any number. The .retroplace sibling is the same
   layout for the RetroBlox studio player (STUDIO > OPEN GAME FILE).

   WHO'S WHO (the words mean different people):
   - USERS   — the people who use the web: sign in, browse, chat, trade, buy.
   - PLAYERS — people inside a game: they play. They do NOT edit UI.
   - GAME DEVS — users who published a game: they edit their game's UI and
     ship game files / Godot projects.
   - SITE OWNER (admin) — can edit any UI on the site, any game's UI. */

import Link from 'next/link'

const INK = '#1c3a52'
const DIM = '#5a6b7b'
const EDGE = '#b6c0cb'

type Tpl = {
  slug: string
  tag: string
  name: string
  desc: string
  badges: string[]
  parts: number
}

const TEMPLATES: Tpl[] = [
  {
    slug: 'top-down-arena',
    tag: 'TD',
    name: 'Brick Arena — Top-Down',
    desc: 'The board-game view: the camera parks high above you and WASD moves on the screen. Cross the grey maze, dodge the red lava, bounce over the corner shortcuts and reach the gold vault. Great base for tower-defense, dungeon and shooter ideas.',
    badges: ['TOP-DOWN CAMERA', 'MAZE', 'LAVA + GOAL'],
    parts: 32,
  },
  {
    slug: 'top-down-dungeon',
    tag: 'DG',
    name: 'Dungeon — Top-Down',
    desc: 'Four stone rooms joined by dark corridors: checkpoint braziers light the way, lava pits fill the dead ends and a GOLD treasure vault waits behind the last door. Classic dungeon-crawl base.',
    badges: ['TOP-DOWN CAMERA', 'CHECKPOINTS', 'BOSS VAULT'],
    parts: 37,
  },
  {
    slug: 'top-down-neon-grid',
    tag: 'NG',
    name: 'Neon Grid — Top-Down',
    desc: 'A black arcade board with glowing cyan grid lines, red laser walls that delete you and yellow bounce pads that fling you across the map. Reach the humming PINK CORE. Fast, loud, arcade.',
    badges: ['TOP-DOWN CAMERA', 'LASERS', 'BOUNCE CHAINS'],
    parts: 30,
  },
  {
    slug: 'paint-world',
    tag: 'PW',
    name: 'Paint World',
    desc: 'The whole world is born WHITE and your LEFT CLICK paints it. Every brick is paintable — repaint the fort, the gallery and the stage. The Godot project carries the paint counter: paint every part to win.',
    badges: ['PAINT BRUSH', 'SANDBOX'],
    parts: 33,
  },
  {
    slug: 'classic-obby',
    tag: 'OB',
    name: 'Classic Obby',
    desc: 'The classic jump course: kill bricks, gaps tuned to the classic physics (WalkSpeed 16 / JumpPower 50), checkpoints and a goal. Duplicate the pattern to make your own stages.',
    badges: ['OBBY', 'CHECKPOINTS'],
    parts: 17,
  },
  {
    slug: 'baseplate',
    tag: 'BP',
    name: 'Baseplate',
    desc: 'The classic empty baseplate — spawn pad, a few starter bricks and nothing else. The cleanest starting point for building your own game idea brick by brick in Godot or the Map Editor.',
    badges: ['BLANK SLATE', 'BUILD IT YOURSELF'],
    parts: 18,
  },
  {
    slug: 'my-place',
    tag: 'MP',
    name: 'My Place (Starter)',
    desc: 'The starter map that ships with the player — a little house, spawn, trampoline and a sign. Change everything: the bricks are real editor nodes, the scripts are plain GDScript.',
    badges: ['STARTER', 'EDITABLE'],
    parts: 12,
  },
]

const ROLES: { who: string; color: string; what: string }[] = [
  { who: 'USERS', color: '#0d69ac', what: 'the people who use the web — sign in, browse, chat, trade, buy items.' },
  { who: 'PLAYERS', color: '#4b974b', what: 'people inside a game — they play it. They do NOT edit any UI.' },
  { who: 'GAME DEVS', color: '#6b327c', what: 'users who published a game — they edit their game\'s UI and ship the game files.' },
  { who: 'SITE OWNER', color: '#c4281c', what: 'the admin — can edit any UI on the site, any game\'s UI, including every template here.' },
]

export function TemplatesView() {
  return (
    <div>
      {/* hero */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Game Templates — real Godot projects, download and edit</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 17, color: INK }}>Not dead files. Each template is a working Godot 4.5 project — open it, press F5, it plays.</div>
          <div style={{ fontSize: 11, color: DIM, marginTop: 6, maxWidth: 760 }}>
            The <b style={{ fontWeight: 600 }}>Godot project (.zip)</b> opens in the free
            <a className="rb-link" href="https://godotengine.org/download" target="_blank" rel="noreferrer"> Godot editor</a>:
            every brick is a real node you can select and recolor, the movement is plain GDScript you can rewrite,
            and the whole game runs on your machine. The <b style={{ fontWeight: 600 }}>.retroplace file</b> is the same
            layout for the RetroBlox player (<Link className="rb-link" href="/sdk">free download</Link>): STUDIO &rarr; OPEN GAME FILE.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
            {['1. Download a Godot project zip below', '2. Godot: Import > pick project.godot', '3. F5 — the game runs', '4. Edit bricks, scripts, physics — make it YOURS'].map((s) => (
              <span key={s} style={{ fontSize: 11, color: INK, border: `1px solid ${EDGE}`, background: '#fff', padding: '5px 10px', borderRadius: 3 }}>{s}</span>
            ))}
          </div>
        </div>
      </div>

      {/* who's who */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>WHO&apos;S WHO — the words mean different people</span></div>
        <div style={{ padding: 12, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(230px, 1fr))', gap: 8 }}>
          {ROLES.map((r) => (
            <div key={r.who} style={{ border: `1px solid ${EDGE}`, borderRadius: 4, padding: '8px 10px', background: '#fff' }}>
              <span style={{ fontSize: 11, fontWeight: 800, color: '#fff', background: r.color, padding: '2px 8px', borderRadius: 3 }}>{r.who}</span>
              <div style={{ fontSize: 10.5, color: DIM, marginTop: 6 }}>{r.what}</div>
            </div>
          ))}
        </div>
      </div>

      {/* the templates */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12 }}>
        {TEMPLATES.map((t) => (
          <div key={t.slug} className="rb-box" style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ width: 38, height: 38, borderRadius: 4, background: '#1b2a34', color: '#f5cd30', fontWeight: 800, fontSize: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', letterSpacing: 1 }} aria-hidden="true">{t.tag}</div>
              <div>
                <div style={{ fontSize: 13, fontWeight: 'bold', color: INK }}>{t.name}</div>
                <div style={{ fontSize: 10, color: DIM }}>{t.parts} bricks inside — Godot 4.5 project</div>
              </div>
            </div>
            <div style={{ fontSize: 11, color: DIM, flex: 1 }}>{t.desc}</div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {t.badges.map((b) => (
                <span key={b} style={{ fontSize: 9, fontWeight: 700, color: '#00639e', background: '#e1f2fb', border: '1px solid #b5d9ee', padding: '2px 7px', borderRadius: 3 }}>{b}</span>
              ))}
            </div>
            <a className="rb-btn rb-btn-green" href={`/download?u=${encodeURIComponent(`/api/template/${t.slug}-godot-project.zip`)}&n=${encodeURIComponent(`${t.slug}-godot-project.zip`)}`} target="_blank" rel="noreferrer" style={{ textDecoration: 'none', textAlign: 'center', fontSize: 12, padding: '8px 12px' }}>
              Download Godot project (.zip)
            </a>
            <a className="rb-btn" href={`/download?u=${encodeURIComponent(`/api/template/${t.slug}.retroplace`)}&n=${encodeURIComponent(`${t.slug}.retroplace`)}`} target="_blank" rel="noreferrer" style={{ textDecoration: 'none', textAlign: 'center', fontSize: 10.5, padding: '6px 12px' }}>
              Game file for the RetroBlox studio (.retroplace)
            </a>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 12, fontSize: 11, color: DIM }}>
        Made something good from a template? <Link className="rb-link" href="/create">Publish it as a game</Link> — attach the
        Godot zip (game devs own their games) or save your studio version as a .retroplace file (STUDIO &rarr; MAP EDITOR &rarr; SAVE FILE).
      </div>
    </div>
  )
}
