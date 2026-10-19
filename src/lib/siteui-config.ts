/* ------------------------------------------------------------------
   SITE UI CONFIG — pure data, safe on the server AND the client.

   This module has NO 'use client' on purpose: the /api/site-ui route
   (a server component) imports DEFAULT_SITE_UI + normalizeSiteUi
   from here. Client-side helpers (the zustand store, the live CSS
   applier) live in siteui.ts, which re-exports everything below.
------------------------------------------------------------------ */

export type SiteUiLink = { label: string; href: string; show: boolean }

export type SiteUiCta = { label: string; href: string; show: boolean }

export type SiteUiGroup = { title: string; links: SiteUiLink[] }

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
  /* ---- THE WHOLE WEB UI ---- */
  headerLogoUrl: string // '' = classic icon; any image url
  headerWordmarkUrl: string // '' = classic wordmark in the blue bar
  footerLogoUrl: string // '' = classic wordmark in the footer
  sidebar: SiteUiGroup[] // the left sidebar groups (Account + Log Out are always appended, so you can't lock yourself out)
  customCss: string // raw CSS applied to EVERY page — target one page with body[data-path^='/games']
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
  headerLogoUrl: '',
  headerWordmarkUrl: '',
  footerLogoUrl: '',
  sidebar: [
    {
      title: 'Create',
      links: [
        { label: 'My Games', href: '/my', show: true },
        { label: 'Create a Game', href: '/create', show: true },
      ],
    },
    {
      title: 'Me',
      links: [
        { label: 'My Profile', href: '/users/{me}', show: true },
        { label: 'Friends', href: '/friends', show: true },
        { label: 'Chat', href: '/chat', show: true },
        { label: 'Favorites', href: '/favorites', show: true },
        { label: 'Avatar Editor', href: '/avatar', show: true },
      ],
    },
  ],
  customCss: '',
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
    if (retiredHref(href)) continue // pages that no longer exist
    out.push({ label, href, show: r.show !== false })
  }
  return out.slice(0, 30)
}

/** Links to pages we deleted — dropped from every saved config so they never render. */
function retiredHref(href: string): boolean {
  const h = href.split('?')[0].replace(/\/$/, '')
  return h === '/templates' || h === '/ui-studio'
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

function groups(v: unknown, fallback: SiteUiGroup[]): SiteUiGroup[] {
  if (!Array.isArray(v)) return fallback
  const out: SiteUiGroup[] = []
  for (const raw of v) {
    if (!raw || typeof raw !== 'object') continue
    const r = raw as Record<string, unknown>
    const title = typeof r.title === 'string' ? r.title.slice(0, 40) : ''
    if (!title) continue
    out.push({ title, links: links(r.links, []) })
  }
  return out.slice(0, 8)
}

/** '' or a sane image path/url (https, /, data:image) */
function imgUrl(v: unknown): string {
  if (typeof v !== 'string') return ''
  const s = v.trim()
  if (!s) return ''
  return /^https:\/\//.test(s) || /^\//.test(s) || /^data:image\//.test(s) ? s.slice(0, 300) : ''
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
    headerLogoUrl: imgUrl(r.headerLogoUrl),
    headerWordmarkUrl: imgUrl(r.headerWordmarkUrl),
    footerLogoUrl: imgUrl(r.footerLogoUrl),
    sidebar: groups(r.sidebar, d.sidebar),
    customCss: typeof r.customCss === 'string' ? r.customCss.slice(0, 24000) : d.customCss,
  }
}
