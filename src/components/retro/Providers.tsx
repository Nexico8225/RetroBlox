'use client'

import { useEffect } from 'react'
import { useRetro, api, type RetroUser } from '@/lib/store'
import { getStoredToken, wipeStaleToken, inIframe } from '@/lib/session'
import { installEggListeners } from '@/lib/eggs'

/**
 * App-level client bootstrap:
 * - restores the session once (/api/me, with one retry for cold servers)
 * - cleans up STALE tokens (e.g. after a database reset) so the UI never
 *   shows a half-logged-in state that later says "invalid account"
 * - keeps "online" status fresh with a heartbeat
 * - renders the global retro toast
 */
export function Providers({ children }: { children: React.ReactNode }) {
  const { booted, user, toast, setBooted, setUser, setPendingRequests, setUnreadChats, setToast } = useRetro()

  /* boot: restore session */
  useEffect(() => {
    let cancelled = false
    const finish = () => {
      if (!cancelled) setBooted(true)
    }

    async function boot(): Promise<void> {
      try {
        const res = await api<{
          user: RetroUser | null
          pendingFriendRequests?: number
          unreadChats?: number
        }>('/api/me')
        if (cancelled) return
        if (res.user) {
          setUser(res.user)
          setPendingRequests(res.pendingFriendRequests || 0)
          setUnreadChats(res.unreadChats || 0)
        } else if (getStoredToken()) {
          // a token is stored but the server does not know it — it is stale
          // (database reset, expired session). Wipe it so the user gets a
          // clean login screen instead of a mysterious logged-out state.
          wipeStaleToken()
        }
      } catch {
        // server may still be waking up — retry once before giving up
        if (!cancelled) {
          await new Promise((r) => setTimeout(r, 900))
          if (cancelled) return
          try {
            const res = await api<{
              user: RetroUser | null
              pendingFriendRequests?: number
              unreadChats?: number
            }>('/api/me')
            if (cancelled) return
            if (res.user) {
              setUser(res.user)
              setPendingRequests(res.pendingFriendRequests || 0)
              setUnreadChats(res.unreadChats || 0)
            } else if (getStoredToken()) {
              wipeStaleToken()
            }
          } catch {
            /* offline — show the site logged out */
          }
        }
      }
    }

    boot().finally(finish)
    return () => {
      cancelled = true
    }
  }, [setUser, setPendingRequests, setUnreadChats, setBooted])

  /* easter eggs: konami code, typed codes, console greeting */
  useEffect(() => {
    installEggListeners()
  }, [])

  /* heartbeat: keeps "online" status fresh (only when storage works) */
  useEffect(() => {
    if (!user) return
    if (inIframe() && !getStoredToken()) return // nothing to authenticate with
    const beat = () => {
      api('/api/heartbeat', { method: 'POST' }).catch(() => {})
    }
    beat()
    const t = setInterval(beat, 60000)
    return () => clearInterval(t)
  }, [user])

  /* global retro toast auto-dismiss */
  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => setToast(null), 3000)
    return () => clearTimeout(t)
  }, [toast, setToast])

  return (
    <>
      {children}
      {toast && (
        <div
          className="rb-box"
          role="status"
          style={{
            position: 'fixed',
            bottom: 18,
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 70,
            border: '2px solid #4c9e34',
            background: 'linear-gradient(180deg,#fff,#e8f7df)',
            color: '#2c6e31',
            fontSize: 12,
            padding: '9px 18px',
            boxShadow: '2px 2px 6px rgba(0,0,0,.3)',
            maxWidth: '90vw',
          }}
        >
          {toast}
        </div>
      )}
    </>
  )
}
