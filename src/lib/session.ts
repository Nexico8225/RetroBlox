'use client'

/* ------------------------------------------------------------------
   BULLETPROOF SESSION STORAGE
   The preview panel embeds the site in a cross-site iframe. Some
   browsers (Safari ITP, Chrome with third-party cookies blocked)
   throw away those cookies AND partition localStorage, which made
   people "unable to sign in" even though the account exists.

   Strategy — the session token survives if ANY layer survives:
     1. localStorage (rb_token)
     2. a JS-readable cookie (rb_token_js) set from the client
     3. the httpOnly session cookie (rb_session) set by the server

   On boot we try every layer, clean up stale tokens (sessions that
   no longer exist server-side, e.g. after a database reset), and if
   we are inside an iframe without storage access we ask for it.
------------------------------------------------------------------ */

const LS_KEY = 'rb_token'
const JS_COOKIE = 'rb_token_js'

function setJsCookie(token: string) {
  try {
    // 180 days, matches the server session cookie lifetime
    document.cookie = `${JS_COOKIE}=${encodeURIComponent(token)}; path=/; max-age=${60 * 60 * 24 * 180}; samesite=none; secure`
  } catch {
    /* ignore */
  }
}

function getJsCookie(): string {
  try {
    const row = document.cookie.split('; ').find((c) => c.startsWith(`${JS_COOKIE}=`))
    return row ? decodeURIComponent(row.split('=')[1] || '') : ''
  } catch {
    return ''
  }
}

function clearJsCookie() {
  try {
    document.cookie = `${JS_COOKIE}=; path=/; max-age=0; samesite=none; secure`
  } catch {
    /* ignore */
  }
}

export function saveSessionToken(token?: string | null) {
  if (!token) return
  try {
    window.localStorage.setItem(LS_KEY, token)
  } catch {
    /* localStorage blocked — cookie layer still works */
  }
  setJsCookie(token)
}

export function clearSessionToken() {
  try {
    window.localStorage.removeItem(LS_KEY)
  } catch {
    /* ignore */
  }
  clearJsCookie()
}

/** First stored token we can find, in reliability order. */
export function getStoredToken(): string {
  try {
    const ls = window.localStorage.getItem(LS_KEY)
    if (ls) return ls
  } catch {
    /* ignore */
  }
  return getJsCookie()
}

export function inIframe(): boolean {
  try {
    return window.self !== window.top
  } catch {
    return true // cross-origin access error == we are framed
  }
}

/**
 * Ask the browser for first-party storage access (Safari ITP / Chrome
 * embedded contexts). MUST be called from a user gesture (a click /
 * submit handler) to have any chance of being granted.
 * Resolves true if access is (already) available.
 */
export async function requestStorageAccessIfNeeded(): Promise<boolean> {
  if (!inIframe()) return true
  try {
    const doc = document as Document & {
      requestStorageAccess?: () => Promise<void>
      hasStorageAccess?: () => Promise<boolean>
    }
    if (doc.hasStorageAccess) {
      const has = await doc.hasStorageAccess()
      if (has) return true
    }
    if (doc.requestStorageAccess) {
      await doc.requestStorageAccess()
      return true
    }
    return false
  } catch {
    return false
  }
}

/** Wipe tokens that are not valid anymore (e.g. DB was reset). */
export function wipeStaleToken() {
  clearSessionToken()
}
