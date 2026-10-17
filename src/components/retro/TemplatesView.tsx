'use client'

/* ================= RetroBlox Game Templates (/templates) =================
   Ready-made game files anyone can download and play in the desktop player:
   STUDIO > OPEN GAME FILE. Each template is the SAME .retroplace format the
   game pages download — the top-down one even carries its own camera flag. */

import Link from 'next/link'

const INK = '#1c3a52'
const DIM = '#5a6b7b'
const EDGE = '#b6c0cb'

type Tpl = {
  file: string
  icon: string
  name: string
  desc: string
  badges: string[]
  parts: number
}

const TEMPLATES: Tpl[] = [
  {
    file: 'top-down-arena.retroplace',
    icon: '🕹️',
    name: 'Brick Arena — Top-Down',
    desc: 'The board-game view: the camera parks high above you and WASD moves on the screen. Cross the grey maze, dodge the red lava, bounce over the corner shortcuts and reach the gold vault. Great base for tower-defense, dungeon and shooter ideas.',
    badges: ['TOP-DOWN CAMERA', 'MAZE', 'LAVA + GOAL'],
    parts: 32,
  },
  {
    file: 'paint-world.retroplace',
    icon: '🎨',
    name: 'Paint World',
    desc: 'The whole world is born WHITE and your LEFT CLICK paints it. Every brick is paintable — repaint the fort, the gallery and the stage. The template carries the paint counter: paint every part to win.',
    badges: ['PAINT BRUSH', 'SANDBOX'],
    parts: 33,
  },
  {
    file: 'classic-obby.retroplace',
    icon: '🏃',
    name: 'Classic Obby',
    desc: 'The classic jump course: kill bricks, gaps tuned to the classic physics (WalkSpeed 16 / JumpPower 50), checkpoints and a goal. Duplicate the pattern to make your own stages.',
    badges: ['OBBY', 'CHECKPOINTS'],
    parts: 17,
  },
  {
    file: 'baseplate.retroplace',
    icon: '🧱',
    name: 'Baseplate',
    desc: 'The classic empty baseplate — spawn pad, a few starter bricks and nothing else. The cleanest starting point for building your own game idea brick by brick in the Map Editor.',
    badges: ['BLANK SLATE', 'BUILD IT YOURSELF'],
    parts: 18,
  },
  {
    file: 'my-place.retroplace',
    icon: '🏠',
    name: 'My Place (Starter)',
    desc: 'The starter map that ships with the player — a little house, spawn, trampoline and a sign. Open it in the Map Editor, change everything, save it back as YOUR place.',
    badges: ['STARTER', 'EDITABLE'],
    parts: 12,
  },
]

export function TemplatesView() {
  return (
    <div>
      {/* hero */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Game Templates — download, open, play</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 17, color: INK }}>Ready-made game files. Download one, open it in the player, make it yours.</div>
          <div style={{ fontSize: 11, color: DIM, marginTop: 6, maxWidth: 680 }}>
            Every template is a <b style={{ fontWeight: 600 }}>.retroplace game file</b> — the same format games on the site
            download as. Grab the free player from the <Link className="rb-link" href="/sdk">SDK page</Link>, then:
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
            {['1. Download a template below', '2. Open the RetroBlox player', '3. STUDIO → OPEN GAME FILE', '4. Play — then edit it in the Map Editor (game devs)'].map((s) => (
              <span key={s} style={{ fontSize: 11, color: INK, border: `1px solid ${EDGE}`, background: '#fff', padding: '5px 10px', borderRadius: 3 }}>{s}</span>
            ))}
          </div>
        </div>
      </div>

      {/* the templates */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12 }}>
        {TEMPLATES.map((t) => (
          <div key={t.file} className="rb-box" style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ fontSize: 26 }} aria-hidden="true">{t.icon}</div>
              <div>
                <div style={{ fontSize: 13, fontWeight: 'bold', color: INK }}>{t.name}</div>
                <div style={{ fontSize: 10, color: DIM }}>{t.parts} bricks inside</div>
              </div>
            </div>
            <div style={{ fontSize: 11, color: DIM, flex: 1 }}>{t.desc}</div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {t.badges.map((b) => (
                <span key={b} style={{ fontSize: 9, fontWeight: 700, color: '#00639e', background: '#e1f2fb', border: '1px solid #b5d9ee', padding: '2px 7px', borderRadius: 3 }}>{b}</span>
              ))}
            </div>
            <a className="rb-btn rb-btn-green" href={`/templates/${t.file}`} download style={{ textDecoration: 'none', textAlign: 'center', fontSize: 12, padding: '8px 12px' }}>
              ⬇ Download {t.file}
            </a>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 12, fontSize: 11, color: DIM }}>
        Made something good from a template? <Link className="rb-link" href="/create">Publish it as a game</Link> — and the
        Map Editor can save your own version as a .retroplace file to share (STUDIO → MAP EDITOR → SAVE FILE).
      </div>
    </div>
  )
}
