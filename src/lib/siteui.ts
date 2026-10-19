'use client'

/* ------------------------------------------------------------------
   SITE UI — client side of the web UI editor.

   The OWNER (role admin) edits the actual website from /site-ui:
   colors, site name, navbar links, the welcome banner and the footer.
   Config lives in one database row and is applied LIVE by overriding
   the CSS custom properties in globals.css — every page picks it up
   instantly, no rebuild, no deploy.

   users (web people) configure it; players just see the result.
   Pure data + normalize lives in siteui-config.ts (server-safe).
------------------------------------------------------------------ */

import { create } from 'zustand'
import { DEFAULT_SITE_UI, normalizeSiteUi, type SiteUiConfig, type SiteUiCta, type SiteUiGroup, type SiteUiLink } from './siteui-config'

export type { SiteUiConfig, SiteUiCta, SiteUiGroup, SiteUiLink }
export { DEFAULT_SITE_UI, normalizeSiteUi }

/** Push a config into the live CSS variables — instant, site-wide. */
export function applySiteUi(cfg: SiteUiConfig) {
  if (typeof document === 'undefined') return
  const root = document.documentElement.style
  // header blues
  root.setProperty('--rb-nav', cfg.colors.nav)
  root.setProperty('--rb-nav-hover', cfg.colors.navLight)
  root.setProperty('--rb-nav-light', cfg.colors.navLight)
  root.setProperty('--rb-nav-dark', cfg.colors.navDark)
  // accent pair: links (--rb-blue) + blue buttons/search (--rb-accent)
  root.setProperty('--rb-blue', cfg.colors.accent)
  root.setProperty('--rb-blue-dark', cfg.colors.accentDark)
  root.setProperty('--rb-accent', cfg.colors.accent)
  root.setProperty('--rb-accent-dark', cfg.colors.accentDark)
  // action green
  root.setProperty('--rb-green', cfg.colors.green)
  root.setProperty('--rb-green-dark', cfg.colors.greenDark)
  // page background
  root.setProperty('--rbx-page-bg', cfg.colors.pageBg)
  // THE WHOLE WEB UI: the owner's raw CSS, live on every page
  applyCustomCss(cfg.customCss)
}

/** Inject / update the owner's custom CSS as one style tag. */
export function applyCustomCss(css: string) {
  if (typeof document === 'undefined') return
  const id = 'rb-site-custom-css'
  let tag = document.getElementById(id) as HTMLStyleElement | null
  if (!tag) {
    tag = document.createElement('style')
    tag.id = id
    document.head.appendChild(tag)
  }
  tag.textContent = css || ''
}

interface SiteUiState {
  config: SiteUiConfig
  loaded: boolean
  setConfig: (c: SiteUiConfig) => void
}

export const useSiteUi = create<SiteUiState>((set) => ({
  config: DEFAULT_SITE_UI,
  loaded: false,
  setConfig: (c) => set({ config: c, loaded: true }),
}))
