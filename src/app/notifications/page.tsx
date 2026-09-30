'use client'

/* ================= Notifications page (/notifications) =================
   The full history behind the header bell — trade offers, listing
   offers, sales, and friend requests. Click one to jump to it. */

import { useCallback, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Page, Title } from '@/components/retro/Shell'
import { api, timeAgo, useRetro } from '@/lib/store'

interface NotificationRow {
  id: string
  type: string
  title: string
  body: string
  link: string
  readAt: string | null
  createdAt: string
}

const ICONS: Record<string, string> = {
  trade_offer: '🔁',
  trade_message: '💬',
  trade_accepted: '✅',
  trade_declined: '🚫',
  trade_cancelled: '↩️',
  friend_request: '👋',
  friend_accepted: '🤝',
  listing_offer: '💰',
  listing_sold: '🎉',
  offer_accepted: '📦',
  offer_declined: '🚫',
}

export default function NotificationsPage() {
  const router = useRouter()
  const { setUnreadNotifications } = useRetro()
  const [items, setItems] = useState<NotificationRow[]>([])
  const [loaded, setLoaded] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api<{ items: NotificationRow[]; unread: number }>('/api/notifications')
      setItems(res.items || [])
      setUnreadNotifications(res.unread || 0)
    } catch { /* ignore */ } finally {
      setLoaded(true)
    }
  }, [setUnreadNotifications])

  useEffect(() => { load() }, [load])

  async function open(n: NotificationRow) {
    if (!n.readAt) {
      try {
        await api('/api/notifications', { method: 'POST', body: JSON.stringify({ action: 'read', id: n.id }) })
        setUnreadNotifications(Math.max(0, useRetro.getState().unreadNotifications - 1))
      } catch { /* ignore */ }
    }
    if (n.link) router.push(n.link)
    else load()
  }

  return (
    <Page>
      <Title t="Notifications" />
      <div className="rb-box" style={{ padding: 0 }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Notifications — trades, offers, sales & friends</span>
          <button
            type="button"
            className="rb-link"
            style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 10.5, color: '#cfe8f8' }}
            onClick={async () => {
              try {
                await api('/api/notifications', { method: 'POST', body: JSON.stringify({ action: 'read_all' }) })
                setUnreadNotifications(0)
                setItems((rows) => rows.map((r) => ({ ...r, readAt: r.readAt || new Date().toISOString() })))
              } catch { /* ignore */ }
            }}
          >
            Mark all read
          </button>
        </div>
        <div style={{ padding: 10, display: 'grid', gap: 5 }}>
          {!loaded ? (
            <div style={{ fontSize: 12, color: '#5a6b7b', padding: 14 }}>Loading…</div>
          ) : items.length === 0 ? (
            <div style={{ fontSize: 12, color: '#5a6b7b', padding: 14 }}>
              Nothing yet. When someone offers a trade, bids on your listing, buys your UGC or sends a friend request — it shows up here and on the bell.
            </div>
          ) : (
            items.map((n) => (
              <button
                key={n.id}
                type="button"
                onClick={() => open(n)}
                style={{
                  display: 'flex', gap: 9, alignItems: 'flex-start', textAlign: 'left', padding: '9px 11px', cursor: 'pointer',
                  background: n.readAt ? '#fff' : '#eaf4fc', border: '1px solid #e8eef4',
                }}
              >
                <span style={{ fontSize: 16 }}>{ICONS[n.type] || '🔔'}</span>
                <span style={{ flex: 1 }}>
                  <span style={{ display: 'block', fontSize: 12, fontWeight: n.readAt ? 'normal' : 'bold', color: '#1c2733' }}>{n.title}</span>
                  {n.body && <span style={{ display: 'block', fontSize: 11, color: '#5a6b7b', marginTop: 1 }}>{n.body}</span>}
                  <span style={{ display: 'block', fontSize: 9.5, color: '#8ba0b3', marginTop: 3 }}>{timeAgo(n.createdAt)}{n.readAt ? '' : ' · new'}</span>
                </span>
              </button>
            ))
          )}
        </div>
      </div>
    </Page>
  )
}
