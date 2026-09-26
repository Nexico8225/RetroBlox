'use client'

/* RetroBlox easter eggs — hidden fun for curious blockheads.
   1. Konami code (up up down down left right left right B A) = KONAMI MODE
   2. Click the logo 7 times fast = a very familiar sound + confetti
   3. Type "2006" anywhere = CRT flashback
   4. Type "tix" anywhere = T$ RAIN (fake coins, real joy)
   5. Type "admin" anywhere = the mint says no
   6. Type "oof" anywhere = you know the sound
   7. Open the dev console = a greeting from the server room
   The typed-code listener is installed once from Providers. */

import { useRetro } from './store'

const KONAMI = [
  'arrowup', 'arrowup', 'arrowdown', 'arrowdown',
  'arrowleft', 'arrowright', 'arrowleft', 'arrowright', 'b', 'a',
]

let buffer: string[] = []
let logoClicks = 0
let logoTimer: ReturnType<typeof setTimeout> | null = null

export function flashToast(msg: string, ms = 2600) {
  useRetro.getState().setToast(msg)
  setTimeout(() => {
    useRetro.getState().setToast(null)
  }, ms)
}

/* tiny WebAudio synth — no audio files, pure 2006 dial-up spirit */
function tone(freqStart: number, freqEnd: number, dur: number, type: OscillatorType = 'square', vol = 0.05) {
  try {
    const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    const ctx = new Ctx()
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.type = type
    osc.frequency.setValueAtTime(freqStart, ctx.currentTime)
    osc.frequency.exponentialRampToValueAtTime(Math.max(40, freqEnd), ctx.currentTime + dur)
    gain.gain.setValueAtTime(vol, ctx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + dur)
    osc.connect(gain).connect(ctx.destination)
    osc.start()
    osc.stop(ctx.currentTime + dur)
    setTimeout(() => ctx.close(), (dur + 0.1) * 1000)
  } catch {
    /* no audio, no problem */
  }
}

export function oofSound() {
  // the forbidden syllable, synthesized: a quick descending "uuh"
  tone(480, 150, 0.32, 'square', 0.06)
  setTimeout(() => tone(300, 110, 0.22, 'triangle', 0.05), 90)
}

export function konamiFanfare() {
  tone(523, 523, 0.09, 'square', 0.04)
  setTimeout(() => tone(659, 659, 0.09, 'square', 0.04), 100)
  setTimeout(() => tone(784, 784, 0.09, 'square', 0.04), 200)
  setTimeout(() => tone(1047, 1047, 0.16, 'square', 0.04), 300)
}

export function confetti(count = 70) {
  const colors = ['#e1231a', '#0d69ac', '#4c9e34', '#ffd34e', '#8e44ad', '#ff9ec6']
  for (let i = 0; i < count; i++) {
    const d = document.createElement('span')
    d.className = 'rb-confetti'
    d.style.left = `${Math.random() * 100}vw`
    d.style.background = colors[i % colors.length]
    d.style.animationDelay = `${Math.random() * 0.5}s`
    d.style.transform = `rotate(${Math.random() * 360}deg)`
    if (i % 3 === 0) d.style.borderRadius = '50%'
    document.body.appendChild(d)
    setTimeout(() => d.remove(), 3200)
  }
}

function crtFlash() {
  const overlay = document.createElement('div')
  overlay.className = 'rb-crt-flash'
  document.body.appendChild(overlay)
  tone(15734, 15734, 0.4, 'sawtooth', 0.012) // the classic 15.7kHz CRT whine
  setTimeout(() => overlay.remove(), 2600)
}

function konami() {
  document.body.classList.add('rb-konami')
  konamiFanfare()
  confetti(80)
  flashToast('KONAMI MODE UNLOCKED — you actually did the code!', 3200)
  setTimeout(() => {
    document.body.classList.remove('rb-konami')
  }, 12000)
}

/* TIX RAIN — the mint has a leak. Golden T$ coins pour from the sky
   with a fat cha-ching. Triggered by typing "tix" anywhere. */
function tixRain() {
  confetti(0) // no plain confetti — we make custom coins below
  const coins = 44
  for (let i = 0; i < coins; i++) {
    const c = document.createElement('span')
    c.className = 'rb-confetti'
    c.style.left = `${Math.random() * 100}vw`
    c.style.width = c.style.height = `${10 + Math.random() * 10}px`
    c.style.borderRadius = '50%'
    c.style.background = 'radial-gradient(circle at 35% 30%, #ffe08a, #f0b429 55%, #8a6d1a)'
    c.style.border = '1px solid #6d5510'
    c.style.color = '#6d5510'
    c.style.fontSize = '8px'
    c.style.fontWeight = 'bold'
    c.style.display = 'flex'
    c.style.alignItems = 'center'
    c.style.justifyContent = 'center'
    c.style.fontFamily = 'Verdana, sans-serif'
    c.textContent = 'T$'
    c.style.animationDelay = `${Math.random() * 0.9}s`
    c.style.animationDuration = `${2.2 + Math.random() * 1.6}s`
    document.body.appendChild(c)
    setTimeout(() => c.remove(), 4200)
  }
  // cha-ching: two bright bells
  tone(880, 880, 0.09, 'square', 0.05)
  setTimeout(() => tone(1318, 1318, 0.22, 'square', 0.05), 110)
  flashToast('T$ RAIN! ...sadly those ones are fake. Keep clicking.', 3000)
}

/* typing "admin" — nice try. */
function adminEgg() {
  tone(200, 120, 0.18, 'sawtooth', 0.04)
  flashToast('Nice try. The Tix mint belongs to Nexico8225.', 3200)
}

export function eggLogoClick() {
  logoClicks++
  if (logoTimer) clearTimeout(logoTimer)
  logoTimer = setTimeout(() => {
    logoClicks = 0
  }, 1800)
  if (logoClicks === 3) flashToast('Keep clicking... something feels weird.', 1800)
  if (logoClicks >= 7) {
    logoClicks = 0
    oofSound()
    confetti(60)
    flashToast('OOF! You found nothing. But here is confetti.', 3000)
  }
}

export function installEggListeners() {
  if (typeof window === 'undefined') return
  if ((window as unknown as { __rbEggs?: boolean }).__rbEggs) return
  ;(window as unknown as { __rbEggs?: boolean }).__rbEggs = true

  document.addEventListener('keydown', (e) => {
    // Mobile keyboards and IMEs fire keydown with key === undefined — guard so
    // the whole page never crashes on them (TypeError: reading 'toLowerCase').
    const raw = typeof e.key === 'string' ? e.key : ''
    if (!raw) return
    const key = raw.toLowerCase()
    buffer.push(key)
    buffer = buffer.slice(-16)

    // Konami
    if (buffer.length >= KONAMI.length) {
      const tail = buffer.slice(-KONAMI.length)
      if (tail.every((k, i) => k === KONAMI[i])) {
        buffer = []
        konami()
        return
      }
    }

    // "2006" CRT flashback
    const typed = buffer.join('')
    if (typed.endsWith('2006')) {
      buffer = []
      crtFlash()
      return
    }

    // "oof" — because obviously
    if (typed.endsWith('oof') && !typed.endsWith('ooof')) {
      buffer = []
      oofSound()
      return
    }

    // "tix" — make it rain (fake) money
    if (typed.endsWith('tix')) {
      buffer = []
      tixRain()
      return
    }

    // "admin" — the guard says no
    if (typed.endsWith('admin')) {
      buffer = []
      adminEgg()
      return
    }
  })

  // console greeting from the server room
  try {
    console.log(
      '%c RETROBLOX %c \u2588\u2588\u2588',
      'background:#e1231a;color:#fff;padding:3px 7px;border-radius:3px 0 0 3px;font-family:monospace',
      'background:#0d69ac;color:#fff;padding:3px 7px;border-radius:0 3px 3px 0;font-family:monospace'
    )
    console.log('%cpsst... try the Konami code, click the logo 7 times fast, or type "2006", "oof", "tix" or "admin" anywhere.', 'color:#0d69ac')
  } catch {
    /* console blocked, whatever */
  }
}
