// Retro blockhead avatar generator - classic 2006 Roblox noob style, as SVG data URLs.
// Deterministic per seed: body colors vary, face always the classic smile.

function hashSeed(seed: string): number {
  let h = 0
  for (let i = 0; i < seed.length; i++) {
    h = ((h << 5) - h + seed.charCodeAt(i)) | 0
  }
  return Math.abs(h)
}

const SKIN_TONES = ['#F6C89F', '#FFD34E', '#F0B27A', '#EAB98B', '#FFCC66', '#F5CBA7']
const SHIRT_COLORS = ['#1F7AB8', '#2ECC71', '#C0392B', '#8E44AD', '#16A085', '#D35400', '#2C3E50', '#C2185B']
const PANT_COLORS = ['#2C6E31', '#34495E', '#5D4037', '#4A4A4A', '#1A5276', '#6E2C00']

function pick<T>(arr: T[], h: number, salt: number): T {
  return arr[(h + salt * 7919) % arr.length]
}

export function blockheadAvatar(seed: string, size = 200): string {
  const h = hashSeed(seed)
  const skin = pick(SKIN_TONES, h, 1)
  const shirt = pick(SHIRT_COLORS, h, 2)
  const pants = pick(PANT_COLORS, h, 3)
  const bgA = pick(['#BFE8FF', '#D8F0D8', '#FDEBD0', '#E8DAEF', '#D6EAF8'], h, 4)
  const bgB = pick(['#7FC4E8', '#A9DFBF', '#F5CBA7', '#D2B4DE', '#85C1E9'], h, 5)

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 100 100">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${bgA}"/>
      <stop offset="1" stop-color="${bgB}"/>
    </linearGradient>
  </defs>
  <rect width="100" height="100" fill="url(#bg)"/>
  <rect x="0" y="82" width="100" height="18" fill="#4E9A4E"/>
  <rect x="0" y="82" width="100" height="3" fill="#5FB35F"/>
  <!-- legs -->
  <rect x="38" y="62" width="10" height="24" fill="${pants}" stroke="#00000033" stroke-width="1"/>
  <rect x="52" y="62" width="10" height="24" fill="${pants}" stroke="#00000033" stroke-width="1"/>
  <!-- torso -->
  <rect x="34" y="40" width="32" height="24" fill="${shirt}" stroke="#00000033" stroke-width="1"/>
  <!-- arms -->
  <rect x="24" y="40" width="9" height="24" fill="${skin}" stroke="#00000033" stroke-width="1"/>
  <rect x="67" y="40" width="9" height="24" fill="${skin}" stroke="#00000033" stroke-width="1"/>
  <!-- head -->
  <rect x="35" y="12" width="30" height="28" fill="${skin}" stroke="#00000044" stroke-width="1"/>
  <!-- classic face -->
  <circle cx="44" cy="25" r="2.6" fill="#1a1a1a"/>
  <circle cx="56" cy="25" r="2.6" fill="#1a1a1a"/>
  <path d="M 42 31 Q 50 38 58 31" stroke="#1a1a1a" stroke-width="2.2" fill="none" stroke-linecap="round"/>
</svg>`
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`
}

// Retro game thumbnail generator (used only for seed content) - old-school blocky scene.
export function retroThumb(seed: string, title: string, w = 420, h = 230): string {
  const n = hashSeed(seed)
  const sky = pick(['#5DA9E9', '#77C3F0', '#8ECAE6', '#64B5F6'], n, 6)
  const grass = pick(['#4E9A4E', '#57A05A', '#3E8E41'], n, 7)
  const brick = pick(['#B5651D', '#A0522D', '#C0392B', '#8D6E63'], n, 8)
  const accent = pick(['#F4D03F', '#E74C3C', '#9B59B6', '#1ABC9C'], n, 9)

  // deterministic little buildings / ramps
  let shapes = ''
  const count = 3 + (n % 3)
  for (let i = 0; i < count; i++) {
    const bw = 34 + ((n >> i) % 40)
    const bh = 30 + ((n >> (i + 2)) % 60)
    const bx = 12 + i * (340 / count) + ((n >> i) % 14)
    const by = 196 - bh
    shapes += `<rect x="${bx}" y="${by}" width="${bw}" height="${bh}" fill="${brick}" stroke="#00000055"/>
      <rect x="${bx + 5}" y="${by + 6}" width="9" height="9" fill="#FFF3C4"/>
      <rect x="${bx + 20}" y="${by + 6}" width="9" height="9" fill="#FFF3C4"/>`
  }
  // a ramp
  shapes += `<polygon points="300,196 380,120 380,196" fill="${accent}" stroke="#00000055"/>`
  // blocky "player"
  shapes += `<g transform="translate(120,128)">
      <rect x="0" y="0" width="22" height="20" fill="#F6C89F" stroke="#00000044"/>
      <circle cx="7" cy="8" r="1.8" fill="#111"/>
      <circle cx="15" cy="8" r="1.8" fill="#111"/>
      <path d="M 6 13 Q 11 17 16 13" stroke="#111" stroke-width="1.6" fill="none"/>
      <rect x="3" y="20" width="16" height="16" fill="${shirtOrSeed(n)}" stroke="#00000044"/>
      <rect x="4" y="36" width="6" height="16" fill="#2C6E31"/>
      <rect x="12" y="36" width="6" height="16" fill="#2C6E31"/>
    </g>`
  // clouds
  shapes += `<ellipse cx="70" cy="34" rx="26" ry="10" fill="#ffffffcc"/><ellipse cx="92" cy="30" rx="18" ry="8" fill="#ffffffcc"/>`
  const t = title.toUpperCase().slice(0, 22)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 420 230">
    <rect width="420" height="230" fill="${sky}"/>
    ${shapes}
    <rect x="0" y="196" width="420" height="34" fill="${grass}"/>
    <rect x="0" y="196" width="420" height="4" fill="#5FB35F"/>
    <rect x="6" y="6" width="${28 + t.length * 13}" height="30" fill="#00000088" rx="4"/>
    <text x="14" y="28" font-family="Verdana,Arial" font-size="17" font-weight="bold" fill="#fff">${escapeXml(t)}</text>
  </svg>`
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`
}

function shirtOrSeed(n: number): string {
  const colors = ['#1F7AB8', '#2ECC71', '#C0392B', '#8E44AD', '#D35400']
  return colors[n % colors.length]
}

function escapeXml(s: string): string {
  return s.replace(/[<>&'"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' }[c] as string))
}
