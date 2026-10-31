'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, flash, isClientAdmin, type RetroUser } from '@/lib/store'

interface BotRow {
  id: string
  username: string
  playerNo: number
  createdAt: string
  lastSeen: string
  role: string
  likelyBot: boolean
  _count: { inventory: number; ugcItems: number; tradesSent: number; tradesRecv: number }
}

export function BotCleanupView() {
  const { user, setToast } = useRetro()
  const [bots, setBots] = useState<BotRow[]>([])
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [query, setQuery] = useState('')
  const [activeFilter, setActiveFilter] = useState<'all' | 'bots' | 'non-admin'>('bots')

  const loadBots = useCallback(async (searchQuery = '') => {
    setLoading(true)
    try {
      const q = searchQuery.trim()
      const url = q ? `/api/admin/bots?q=${encodeURIComponent(q)}&limit=500` : '/api/admin/bots?limit=500'
      const res = await api<{ users: BotRow[] }>(url)
      const list = res.users || []
      setBots(list)
      // Default selection to bots
      setPicked(new Set(list.filter((u) => u.likelyBot && u.role !== 'admin').map((u) => u.id)))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to load accounts list', 3500)
    } finally {
      setLoading(false)
    }
  }, [setToast])

  useEffect(() => {
    if (isClientAdmin(user)) {
      loadBots()
    }
  }, [user, loadBots])

  if (!user) {
    return (
      <div className="rb-box" style={{ padding: 24, textAlign: 'center', fontSize: 13, color: '#5a6b7b' }}>
        Please <Link href="/login" className="rb-link">log in</Link> to access the Bot Cleanup panel.
      </div>
    )
  }

  if (!isClientAdmin(user)) {
    return (
      <div className="rb-box" style={{ padding: 24, textAlign: 'center', fontSize: 13, color: '#a81a13' }}>
        Admins only — your account does not have permission to delete users.
      </div>
    )
  }

  const detectedBotsCount = bots.filter((b) => b.likelyBot && b.role !== 'admin').length

  const filteredBots = bots.filter((u) => {
    if (activeFilter === 'bots') return u.likelyBot
    if (activeFilter === 'non-admin') return u.role !== 'admin'
    return true
  })

  // Purge ALL detected bots in one shot
  async function purgeAllBots() {
    if (!window.confirm('WARNING: Are you sure you want to PURGE ALL detected bot accounts and everything they own (items, trades, listings, messages)? This is permanent and cannot be undone!')) {
      return
    }
    setBusy(true)
    try {
      const res = await api<{ removed: string[]; count: number; message: string }>('/api/admin/bots', {
        method: 'POST',
        body: JSON.stringify({ purgeAllBots: true }),
      })
      flash(setToast, res.message || `Successfully purged ${res.count} bot accounts!`, 4500)
      await loadBots(query)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Purge failed', 4000)
    } finally {
      setBusy(false)
    }
  }

  // Remove picked accounts
  async function removePicked() {
    const ids = [...picked]
    if (ids.length === 0) return
    if (!window.confirm(`Permanently remove ${ids.length} selected account(s) and all their data? This cannot be undone.`)) {
      return
    }
    setBusy(true)
    try {
      const res = await api<{ removed: string[]; count: number; errors?: string[] }>('/api/admin/bots', {
        method: 'POST',
        body: JSON.stringify({ userIds: ids }),
      })
      if (res.errors && res.errors.length > 0) {
        flash(setToast, `Removed ${res.removed.length} accounts. Warning: ${res.errors[0]}`, 4500)
      } else {
        flash(setToast, `Successfully removed ${res.removed.length} account(s)!`, 3500)
      }
      await loadBots(query)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Removal failed', 4000)
    } finally {
      setBusy(false)
    }
  }

  // Remove a single account
  async function removeSingle(account: BotRow) {
    if (account.role === 'admin') return
    if (!window.confirm(`Delete "${account.username}" and all their data permanently?`)) return
    setBusy(true)
    try {
      await api('/api/admin/bots', {
        method: 'POST',
        body: JSON.stringify({ userIds: [account.id] }),
      })
      flash(setToast, `Removed "${account.username}".`, 3000)
      await loadBots(query)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to delete account', 4000)
    } finally {
      setBusy(false)
    }
  }

  function handleSearch(e: React.FormEvent) {
    e.preventDefault()
    loadBots(query)
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Top Breadcrumb & Quick Link */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ fontSize: 12, color: '#5a6b7b' }}>
          <Link href="/admin" className="rb-link">← Back to Admin Panel</Link>
        </div>
        <div style={{ fontSize: 11, color: '#7b8896' }}>
          Target: <b style={{ color: '#00639e' }}>retro-blox.vercel.app</b>
        </div>
      </div>

      {/* Main Action Box */}
      <div className="rb-box" style={{ border: '2px solid #d91e18', background: '#fffcfb' }}>
        <div className="rb-panel-head" style={{ background: 'linear-gradient(180deg, #c0392b, #962d22)', color: '#fff' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            🧹 Bot Removal & Junk Cleanup
          </span>
          <span style={{ fontSize: 11, fontWeight: 'normal', opacity: 0.9 }}>
            Fast bulk deletion engine
          </span>
        </div>

        <div style={{ padding: 14 }}>
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 12 }}>
            <div>
              <h2 style={{ margin: '0 0 4px', fontSize: 15, color: '#1c2733' }}>
                Purge Bots & Junk Accounts
              </h2>
              <div style={{ fontSize: 11.5, color: '#5a6b7b', maxWidth: 640 }}>
                This tool sweeps out automated probe accounts, spam accounts, and junk users. 
                Deleting an account safely cascades through and removes their UGC items, inventory, trades, chats, comments, and sessions in seconds.
                <b> Admin accounts are automatically protected.</b>
              </div>
            </div>

            {/* 1-CLICK PURGE BUTTON */}
            <button
              type="button"
              className="rb-btn rb-btn-red"
              disabled={busy}
              onClick={purgeAllBots}
              style={{
                fontSize: 13,
                fontWeight: 'bold',
                padding: '8px 18px',
                boxShadow: '0 2px 4px rgba(217, 30, 24, 0.3)',
                background: 'linear-gradient(180deg, #e74c3c, #c0392b)',
                borderColor: '#962d22',
                cursor: busy ? 'not-allowed' : 'pointer',
              }}
            >
              {busy ? 'Processing Purge…' : `⚡ Purge All Bots Now (${detectedBotsCount} Detected)`}
            </button>
          </div>

          {/* Stats Bar */}
          <div style={{
            display: 'flex',
            flexWrap: 'wrap',
            gap: 16,
            background: '#f2f6fa',
            border: '1px solid #c9d8e5',
            borderRadius: 4,
            padding: '8px 12px',
            fontSize: 11.5,
            color: '#34495e',
          }}>
            <span>Total Loaded: <b>{bots.length}</b></span>
            <span>Detected Bots: <b style={{ color: '#c0392b' }}>{detectedBotsCount}</b></span>
            <span>Selected for Removal: <b style={{ color: '#00639e' }}>{picked.size}</b></span>
          </div>
        </div>
      </div>

      {/* Account Browser & Search Box */}
      <div className="rb-box">
        <div className="rb-panel-head">
          <span>Account Inspector & Picker</span>
        </div>

        <div style={{ padding: 12 }}>
          {/* Search & Filter Bar */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
            <form onSubmit={handleSearch} style={{ display: 'flex', gap: 4, flex: 1, maxWidth: 360 }}>
              <input
                className="rb-input"
                type="search"
                placeholder="Search username..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                style={{ fontSize: 11.5, height: 28, flex: 1 }}
              />
              <button className="rb-btn" type="submit" disabled={busy} style={{ height: 28, fontSize: 11 }}>
                Search
              </button>
              {query && (
                <button
                  type="button"
                  className="rb-btn"
                  onClick={() => { setQuery(''); loadBots('') }}
                  style={{ height: 28, fontSize: 11 }}
                >
                  Clear
                </button>
              )}
            </form>

            {/* Filter Tabs */}
            <div style={{ display: 'flex', gap: 4 }}>
              <button
                type="button"
                className={`rb-btn ${activeFilter === 'bots' ? 'rb-btn-blue' : ''}`}
                onClick={() => setActiveFilter('bots')}
                style={{ fontSize: 11, padding: '4px 10px' }}
              >
                Bots Only ({detectedBotsCount})
              </button>
              <button
                type="button"
                className={`rb-btn ${activeFilter === 'non-admin' ? 'rb-btn-blue' : ''}`}
                onClick={() => setActiveFilter('non-admin')}
                style={{ fontSize: 11, padding: '4px 10px' }}
              >
                Non-Admins ({bots.filter((b) => b.role !== 'admin').length})
              </button>
              <button
                type="button"
                className={`rb-btn ${activeFilter === 'all' ? 'rb-btn-blue' : ''}`}
                onClick={() => setActiveFilter('all')}
                style={{ fontSize: 11, padding: '4px 10px' }}
              >
                All ({bots.length})
              </button>
            </div>
          </div>

          {/* Quick Selection Buttons */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', marginBottom: 12 }}>
            <button
              type="button"
              className="rb-btn rb-btn-red"
              disabled={busy || picked.size === 0}
              onClick={removePicked}
              style={{ fontSize: 11.5, fontWeight: 'bold', padding: '4px 14px' }}
            >
              {busy ? 'Removing…' : `Delete Selected (${picked.size})`}
            </button>
            <button
              type="button"
              className="rb-btn"
              onClick={() => setPicked(new Set(filteredBots.filter((u) => u.likelyBot && u.role !== 'admin').map((u) => u.id)))}
              style={{ fontSize: 10.5, padding: '4px 8px' }}
            >
              Select Filtered Bots
            </button>
            <button
              type="button"
              className="rb-btn"
              onClick={() => setPicked(new Set(filteredBots.filter((u) => u.role !== 'admin').map((u) => u.id)))}
              style={{ fontSize: 10.5, padding: '4px 8px' }}
            >
              Select All in View
            </button>
            <button
              type="button"
              className="rb-link"
              onClick={() => setPicked(new Set())}
              style={{ fontSize: 10.5, marginLeft: 4 }}
            >
              Deselect All
            </button>
          </div>

          {/* Accounts Table */}
          {loading ? (
            <div style={{ padding: 30, textAlign: 'center', color: '#5a6b7b', fontSize: 12 }}>
              Loading accounts list…
            </div>
          ) : (
            <div style={{ border: '1px solid #dbe5ec', borderRadius: 3, maxHeight: 480, overflowY: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11, textAlign: 'left' }}>
                <thead style={{ background: '#eef4fa', borderBottom: '1px solid #dbe5ec', position: 'sticky', top: 0, zIndex: 1 }}>
                  <tr>
                    <th style={{ width: 32, padding: '6px 8px' }}>
                      <input
                        type="checkbox"
                        checked={filteredBots.length > 0 && filteredBots.filter((u) => u.role !== 'admin').every((u) => picked.has(u.id))}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setPicked(new Set(filteredBots.filter((u) => u.role !== 'admin').map((u) => u.id)))
                          } else {
                            setPicked(new Set())
                          }
                        }}
                      />
                    </th>
                    <th style={{ padding: '6px 8px' }}>Username</th>
                    <th style={{ padding: '6px 8px' }}>Player #</th>
                    <th style={{ padding: '6px 8px' }}>Role / Status</th>
                    <th style={{ padding: '6px 8px' }}>Items & Trades</th>
                    <th style={{ padding: '6px 8px' }}>Created</th>
                    <th style={{ width: 80, padding: '6px 8px', textAlign: 'right' }}>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredBots.map((u) => {
                    const isPicked = picked.has(u.id)
                    const isAdmin = u.role === 'admin'
                    return (
                      <tr
                        key={u.id}
                        style={{
                          background: isPicked ? '#fef3f2' : u.likelyBot ? '#fdf9ee' : '#fff',
                          borderBottom: '1px solid #f0f4f8',
                        }}
                      >
                        <td style={{ padding: '6px 8px' }}>
                          <input
                            type="checkbox"
                            checked={isPicked}
                            disabled={isAdmin}
                            onChange={(e) => {
                              setPicked((prev) => {
                                const next = new Set(prev)
                                if (e.target.checked) next.add(u.id)
                                else next.delete(u.id)
                                return next
                              })
                            }}
                          />
                        </td>
                        <td style={{ padding: '6px 8px' }}>
                          <Link href={`/users/${u.id}`} className="rb-link" style={{ fontWeight: 'bold' }}>
                            {u.username}
                          </Link>
                        </td>
                        <td style={{ padding: '6px 8px', fontFamily: 'monospace', color: '#7b8896' }}>
                          #{u.playerNo}
                        </td>
                        <td style={{ padding: '6px 8px' }}>
                          {isAdmin ? (
                            <span className="rb-admin-badge" style={{ fontSize: 9 }}>ADMIN (PROTECTED)</span>
                          ) : u.likelyBot ? (
                            <span style={{
                              fontSize: 9.5,
                              fontWeight: 'bold',
                              color: '#945800',
                              background: '#fff7d6',
                              border: '1px solid #e2c070',
                              borderRadius: 2,
                              padding: '1px 5px',
                            }}>
                              🤖 bot detected
                            </span>
                          ) : (
                            <span style={{ fontSize: 10, color: '#5a6b7b' }}>Normal</span>
                          )}
                        </td>
                        <td style={{ padding: '6px 8px', color: '#5a6b7b', fontSize: 10.5 }}>
                          {u._count.inventory} inv · {u._count.ugcItems} UGC · {u._count.tradesSent + u._count.tradesRecv} trades
                        </td>
                        <td style={{ padding: '6px 8px', color: '#7b8896', fontSize: 10.5 }}>
                          {new Date(u.createdAt).toLocaleDateString('en-US')}
                        </td>
                        <td style={{ padding: '6px 8px', textAlign: 'right' }}>
                          {!isAdmin && (
                            <button
                              type="button"
                              className="rb-btn rb-btn-red"
                              disabled={busy}
                              onClick={() => removeSingle(u)}
                              style={{ fontSize: 10, padding: '2px 8px' }}
                            >
                              Delete
                            </button>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                  {filteredBots.length === 0 && (
                    <tr>
                      <td colSpan={7} style={{ padding: 24, textAlign: 'center', color: '#8ba0b3' }}>
                        No accounts match this filter or search query.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
