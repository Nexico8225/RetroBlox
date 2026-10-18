/* ------------------------------------------------------------------
   SITE UI CONFIG — pure data, safe on the server AND the client.

   This module has NO 'use client' on purpose: the /api/site-ui route
   (a server component) imports DEFAULT_SITE_UI + normalizeSiteUi
   from here. Client-side helpers (the zustand store, the live CSS
   applier) live in siteui.ts, which re-exports everything below.
------------------------------------------------------------------ */

export type SiteUiLink = { label: string; href: string; show: boolean }

export type SiteUiCta = { label: string; href: string; show: boolean }

export type SiteUiConfig = {
  siteName: string
  colors: {
    navLight: string // top of the header gradient
    nav: string // middle of the header gradient (the classic blue bar)
    navDark: string // bottom of the header gradient
    accent: string // links + highlights
    accentDark: string // blue button bottom
    green: string // action green
    greenDark: string // green button bottom
    pageBg: string // page background
  }
  links: SiteUiLink[]
  hero: {
    show: boolean
    guestTitle: string // shown to logged-out visitors
    memberTitle: string // the "Hello, NAME!" line — {name} is replaced
    subtitle: string
    ctas: SiteUiCta[]
  }
  footer: {
    tagline: string
    bottom: string
  }
}

/** The current look — every editor field falls back to these. */
export const DEFAULT_SITE_UI: SiteUiConfig = {
  siteName: 'RetroBlox',
  colors: {
    navLight: '#0f83c9',
    nav: '#0070b6',
    navDark: '#005f9c',
    accent: '#00a2ff',
    accentDark: '#0d69ac',
    green: '#02b757',
    greenDark: '#029a4a',
    pageBg: '#e6eaf0',
  },
  links: [
    { label: 'Home', href: '/', show: true },
    { label: 'Games', href: '/games', show: true },
    { label: 'ColorWorld', href: '/colorworld', show: true },
    { label: 'Webs', href: '/webs', show: true },
    { label: 'Catalog', href: '/catalog', show: true },
    { label: 'Avatar', href: '/avatar', show: true },
    { label: 'Create', href: '/create', show: true },
    { label: 'SDK', href: '/sdk', show: true },
    { label: 'Templates', href: '/templates', show: true },
    { label: 'Videos', href: '/videos', show: true },
    { label: 'Groups', href: '/groups', show: true },
    { label: 'Communities', href: '/community', show: true },
  ],
  hero: {
    show: true,
    guestTitle: 'Welcome to RetroBlox',
    memberTitle: 'Hello, {name}!',
    subtitle: 'Publish a game, upload a video, dress your blockhead, or hang out in the lounge.',
    ctas: [
      { label: '+ Publish a Game', href: '/create', show: true },
      { label: 'Post a Video', href: '/community/new?video=1', show: true },
      { label: 'Community', href: '/community', show: true },
    ],
  },
  footer: {
    tagline: '— you can see the ROBLOX inside ReTROBLOX. A fan-made tribute to classic blocky gaming.',
    bottom: 'Best viewed at 1024x768 with a 56k modem',
  },
}

const HEX = /^#[0-9a-fA-F]{6}$/

function str(v: unknown, fallback: string, max = 200): string {
  return typeof v === 'string' && v.trim() ? v.slice(0, max) : fallback
}

function hex(v: unknown, fallback: string): string {
  return typeof v === 'string' && HEX.test(v.trim()) ? v.trim().toLowerCase() : fallback
}

function links(v: unknown, fallback: SiteUiLink[]): SiteUiLink[] {
  if (!Array.isArray(v)) return fallback
  const out: SiteUiLink[] = []
  for (const raw of v) {
    if (!raw || typeof raw !== 'object') continue
    const r = raw as Record<string, unknown>
    const label = typeof r.label === 'string' ? r.label.slice(0, 40) : ''
    const href = typeof r.href === 'string' ? r.href.slice(0, 200) : ''
    if (!label || !href) continue
    out.push({ label, href, show: r.show !== false })
  }
  return out.slice(0, 30)
}

function ctas(v: unknown, fallback: SiteUiCta[]): SiteUiCta[] {
  if (!Array.isArray(v)) return fallback
  const out: SiteUiCta[] = []
  for (const raw of v) {
    if (!raw || typeof raw !== 'object') continue
    const r = raw as Record<string, unknown>
    out.push({
      label: str(r.label, '', 60),
      href: typeof r.href === 'string' ? r.href.slice(0, 200) : '/games',
      show: r.show !== false,
    })
  }
  return out.slice(0, 6)
}

/** Merge any junk (old rows, partial saves, hand-edited JSON) into a valid config. */
export function normalizeSiteUi(raw: unknown): SiteUiConfig {
  const d = DEFAULT_SITE_UI
  if (!raw || typeof raw !== 'object') return d
  const r = raw as Record<string, unknown>
  const c = (r.colors && typeof r.colors === 'object' ? r.colors : {}) as Record<string, unknown>
  const h = (r.hero && typeof r.hero === 'object' ? r.hero : {}) as Record<string, unknown>
  const f = (r.footer && typeof r.footer === 'object' ? r.footer : {}) as Record<string, unknown>
  return {
    siteName: str(r.siteName, d.siteName, 40),
    colors: {
      navLight: hex(c.navLight, d.colors.navLight),
      nav: hex(c.nav, d.colors.nav),
      navDark: hex(c.navDark, d.colors.navDark),
      accent: hex(c.accent, d.colors.accent),
      accentDark: hex(c.accentDark, d.colors.accentDark),
      green: hex(c.green, d.colors.green),
      greenDark: hex(c.greenDark, d.colors.greenDark),
      pageBg: hex(c.pageBg, d.colors.pageBg),
    },
    links: links(r.links, d.links),
    hero: {
      show: h.show !== false,
      guestTitle: str(h.guestTitle, d.hero.guestTitle, 80),
      memberTitle: str(h.memberTitle, d.hero.memberTitle, 80),
      subtitle: typeof h.subtitle === 'string' ? h.subtitle.slice(0, 200) : d.hero.subtitle,
      ctas: ctas(h.ctas, d.hero.ctas),
    },
    footer: {
      tagline: typeof f.tagline === 'string' ? f.tagline.slice(0, 200) : d.footer.tagline,
      bottom: typeof f.bottom === 'string' ? f.bottom.slice(0, 120) : d.footer.bottom,
    },
  }
}
