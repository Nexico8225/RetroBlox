'use client'

/* ------------------------------------------------------------------
   WEB GAMES — games coded right on RetroBlox.

   A creator writes JavaScript in the Web Studio (the /create page),
   players hit Play and the code runs inside a SANDBOXED iframe:

     sandbox="allow-scripts allow-pointer-lock allow-modals"

   NO allow-same-origin — the frame gets an opaque origin, so game
   code can never touch RetroBlox cookies, accounts or API tokens.
   No allow-popups, no allow-top-navigation — it can't open ads or
   hijack the page either. What the code CAN do: canvas, keyboard,
   mouse, sound, and the window.RetroBlox helper API below.

   The wrapper also turns uncaught errors into a red banner INSIDE
   the game ("Code error: coins is not defined (line 12)") — the
   single most useful thing for a kid learning to code.
------------------------------------------------------------------ */

/** The RetroBlox API injected before the creator's code. */
const RBX_SHIM = `<script>
(function () {
  var ui = document.createElement('div')
  ui.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483000;font-family:monospace'
  function mount() { if (document.body && !ui.parentNode) document.body.appendChild(ui) }
  mount()

  var score = 0
  var chip = document.createElement('div')
  chip.style.cssText = 'position:absolute;top:10px;left:10px;background:rgba(10,25,45,.72);color:#7fd4ff;padding:5px 12px;border:1px solid #24425f;border-radius:4px;font-size:15px;display:none'
  ui.appendChild(chip)

  function show(el, ms) {
    mount()
    el.style.pointerEvents = 'auto'
    ui.appendChild(el)
    if (ms) setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el) }, ms)
  }
  function big(text, bg) {
    var w = document.createElement('div')
    w.style.cssText = 'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:' + bg
    var box = document.createElement('div')
    box.style.cssText = 'text-align:center;color:#fff;font-size:34px;font-weight:bold;text-shadow:0 2px 0 #000;padding:20px;white-space:pre-wrap'
    box.textContent = String(text)
    var b = document.createElement('button')
    b.textContent = 'Keep playing'
    b.style.cssText = 'display:block;margin:16px auto 0;font-size:16px;padding:8px 20px;cursor:pointer;font-family:monospace'
    b.onclick = function () { if (w.parentNode) w.parentNode.removeChild(w) }
    box.appendChild(b)
    w.appendChild(box)
    show(w)
  }
  window.onerror = function (msg, src, line) {
    var d = document.createElement('div')
    d.style.cssText = 'position:absolute;left:0;right:0;bottom:0;background:rgba(122,10,10,.93);color:#fff;font:12px/1.5 monospace;padding:8px 12px;white-space:pre-wrap'
    d.textContent = 'Code error: ' + msg + (line ? ' (line ' + line + ')' : '')
    show(d, 9000)
    return false
  }
  window.RetroBlox = {
    /** speech bubble at the top ("RetroBlox.say('hi!', 3)") */
    say: function (text, seconds) {
      var d = document.createElement('div')
      d.style.cssText = 'position:absolute;left:50%;top:16px;transform:translateX(-50%);background:#fff;color:#111;border:2px solid #24425f;border-radius:8px;padding:6px 14px;font-size:15px;max-width:82%;text-align:center'
      d.textContent = String(text)
      show(d, (Number(seconds) || 2.5) * 1000)
    },
    /** scoreboard chip, top-left ("RetroBlox.score(10)") */
    score: function (points) {
      score = Number(points) || 0
      chip.style.display = 'block'
      chip.textContent = 'Score: ' + score
    },
    getScore: function () { return score },
    /** full-screen overlay, game keeps running behind it */
    win: function (text) { big(text || 'YOU WIN!', 'rgba(18,72,18,.86)') },
    lose: function (text) { big(text || 'GAME OVER', 'rgba(88,10,10,.86)') },
  }
})()
</script>`

const WRAPPER_HEAD = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; background: #101820; color: #e8eef4;
    font-family: 'Courier New', monospace; overflow: hidden; }
  canvas { display: block; }
</style>
</head>
<body>`

/** Compose the sandboxed document: creators can paste either plain JS
 *  (wrapped in the default page) or a FULL HTML document (their own
 *  <style>/<canvas> markup) — the shim is injected into both. */
export function buildWebGameDoc(code: string): string {
  const trimmed = (code || '').trim()
  const isFullHtml = /^<!doctype\s+html/i.test(trimmed) || /<html[\s>]/i.test(trimmed)
  if (isFullHtml) {
    if (/<head[^>]*>/i.test(trimmed)) return trimmed.replace(/<head[^>]*>/i, (m) => m + RBX_SHIM)
    if (/<html[^>]*>/i.test(trimmed)) return trimmed.replace(/<html[^>]*>/i, (m) => m + RBX_SHIM)
    return trimmed
  }
  return `${WRAPPER_HEAD}${RBX_SHIM}
<script>
${trimmed}
</script>
</body>
</html>`
}

/* ---------------- starter templates ---------------- */

export interface WebTemplate {
  id: string
  label: string
  blurb: string
  code: string
}

export const WEB_TEMPLATES: WebTemplate[] = [
  {
    id: 'blank',
    label: 'Blank',
    blurb: 'A clean page + the RetroBlox helpers.',
    code: `// Welcome to the RetroBlox Web Studio!
// Anything you write here runs when players press Play.

RetroBlox.say('Welcome to my game!', 3)
RetroBlox.score(0)

// Try: RetroBlox.win('You did it!') or RetroBlox.lose('Try again!')
`,
  },
  {
    id: 'clicker',
    label: 'Coin Clicker',
    blurb: 'Click the coin 25 times to win.',
    code: `// COIN CLICKER - click the coin 25 times to win!
let coins = 0
RetroBlox.score(coins)

const coin = document.createElement('div')
coin.textContent = 'O'
coin.style.cssText = [
  'width:120px', 'height:120px', 'line-height:114px', 'text-align:center',
  'font-size:64px', 'font-weight:bold', 'color:#7a5b12',
  'background:radial-gradient(circle at 35% 30%, #ffe98a, #d9a821)',
  'border:4px solid #8a6d1a', 'border-radius:50%', 'margin:60px auto',
  'cursor:pointer', 'user-select:none',
].join(';')
document.body.appendChild(coin)

const hint = document.createElement('div')
hint.style.cssText = 'text-align:center;font-size:16px'
hint.textContent = 'Click the coin!'
document.body.appendChild(hint)

coin.addEventListener('click', function () {
  coins = coins + 1
  RetroBlox.score(coins)
  hint.textContent = coins + ' / 25 coins'
  if (coins >= 25) RetroBlox.win('You collected 25 coins!')
})
`,
  },
  {
    id: 'dodger',
    label: 'Block Dodger',
    blurb: 'Arrow keys dodge falling blocks.',
    code: `// BLOCK DODGER - arrow keys (or A/D) to move, survive as long as you can!
const canvas = document.createElement('canvas')
document.body.appendChild(canvas)
const ctx = canvas.getContext('2d')

function resize() {
  canvas.width = window.innerWidth
  canvas.height = window.innerHeight
}
resize()
window.addEventListener('resize', resize)

const player = { x: 200, w: 46, h: 46, speed: 340 }
const keys = {}
window.addEventListener('keydown', function (e) { keys[e.key] = true })
window.addEventListener('keyup', function (e) { keys[e.key] = false })

let blocks = []      // { x, y, s, v }
let spawnIn = 0      // seconds until the next block
let time = 0
let last = performance.now()
let over = false

function loop(now) {
  if (over) return
  const dt = Math.min(0.05, (now - last) / 1000)
  last = now
  time = time + dt

  // move
  if (keys.ArrowLeft || keys.a) player.x = player.x - player.speed * dt
  if (keys.ArrowRight || keys.d) player.x = player.x + player.speed * dt
  if (player.x < 0) player.x = 0
  if (player.x > canvas.width - player.w) player.x = canvas.width - player.w

  // spawn blocks faster over time
  spawnIn = spawnIn - dt
  if (spawnIn <= 0) {
    spawnIn = Math.max(0.28, 0.9 - time * 0.02)
    const s = 26 + Math.random() * 30
    blocks.push({
      x: Math.random() * (canvas.width - s),
      y: -s,
      s: s,
      v: 160 + Math.random() * 140 + time * 6,
    })
  }

  // update + collide
  const py = canvas.height - player.h - 30
  for (const b of blocks) {
    b.y = b.y + b.v * dt
    const hit = b.x < player.x + player.w && b.x + b.s > player.x && b.y < py + player.h && b.y + b.s > py
    if (hit) {
      over = true
      RetroBlox.lose('Wasted! You survived ' + Math.floor(time) + ' seconds')
    }
  }
  blocks = blocks.filter(function (b) { return b.y < canvas.height + 60 })

  // draw
  ctx.fillStyle = '#101820'
  ctx.fillRect(0, 0, canvas.width, canvas.height)
  ctx.fillStyle = '#8fd464'
  ctx.fillRect(player.x, py, player.w, player.h)
  ctx.fillStyle = '#e1231a'
  for (const b of blocks) ctx.fillRect(b.x, b.y, b.s, b.s)
  ctx.fillStyle = '#7fd4ff'
  ctx.font = '16px monospace'
  ctx.fillText('Score: ' + Math.floor(time * 10), 12, 24)

  RetroBlox.score(Math.floor(time * 10))
  requestAnimationFrame(loop)
}
RetroBlox.say('Dodge the red blocks!', 3)
requestAnimationFrame(loop)
`,
  },
]
