'use client'

/* ================= Tix Admin (/admin) =================
   Admins only: manage Tix packages (server-side price authority),
   watch payments + Stripe ids, inspect the ledger, see balances,
   and issue controlled Tix grants. */

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, flash, refreshBalance, timeAgo } from '@/lib/store'

interface Pkg {
  id: string
  code: string
  name: string
  rbxAmount: number
  priceCents: number
  active: boolean
  sortOrder: number
}
interface Payment {
  id: string
  username: string
  packageName: string
  amountPaid: number
  status: string
  refundedCents: number
  rbxCredited: number
  rbxReversed: number
  sessionId: string
  paymentIntentId: string | null
  createdAt: string
}
interface Txn {
  id: string
  username: string
  amount: number
  type: string
  balanceBefore: number
  balanceAfter: number
  note: string
  stripeEventId: string | null
  stripePaymentIntentId: string | null
  createdAt: string
}
interface Holder { id: string; username: string; rbxBalance: number; role: string }
interface Overview {
  mode: string
  packages: Pkg[]
  payments: Payment[]
  transactions: Txn[]
  holders: Holder[]
  stats: { paymentsCount: number; totalPaidCents: number; totalRefundedCents: number; totalRbxGranted: number; totalRbxReversed: number }
}

const usd = (c: number) => `$${(c / 100).toFixed(2)}`
const short = (s: string | null) => (s ? `${s.slice(0, 18)}…` : '—')

const STATUS_COLOR: Record<string, string> = {
  succeeded: '#2c6e31',
  pending: '#8a6d1a',
  failed: '#a81a13',
  expired: '#7b8896',
  refunded: '#0d69ac',
  partially_refunded: '#0d69ac',
}

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

export function RbxAdminView() {
  const { user, setToast } = useRetro()
  const [data, setData] = useState<Overview | null>(null)
  const [error, setError] = useState('')
  const [grantUser, setGrantUser] = useState('')
  const [grantAmount, setGrantAmount] = useState('')
  const [grantNote, setGrantNote] = useState('')
  const [busy, setBusy] = useState(false)
  // draft edits per package row (only touched fields get sent)
  const [draft, setDraft] = useState<Record<string, Partial<Pkg>>>({})
  // bot cleanup state — recent accounts, bot-shaped names flagged
  const [bots, setBots] = useState<BotRow[]>([])
  const [botPicked, setBotPicked] = useState<Set<string>>(new Set())
  const [botBusy, setBotBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      setData(await api<Overview>('/api/admin/rbx'))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load.')
    }
  }, [])

  const loadBots = useCallback(async () => {
    try {
      const res = await api<{ users: BotRow[] }>('/api/admin/bots')
      setBots(res.users || [])
      setBotPicked(new Set((res.users || []).filter((u) => u.likelyBot).map((u) => u.id)))
    } catch { /* the panel just stays empty */ }
  }, [])

  useEffect(() => { if (user?.role === 'admin') { load(); loadBots() } }, [user, load, loadBots])

  async function removeBots() {
    const ids = [...botPicked]
    if (ids.length === 0) return
    if (!window.confirm(`Permanently remove ${ids.length} account${ids.length === 1 ? '' : 's'} and everything they own? This cannot be undone.`)) return
    setBotBusy(true)
    try {
      const res = await api<{ removed: string[] }>('/api/admin/bots', { method: 'POST', body: JSON.stringify({ userIds: ids }) })
      flash(setToast, `Removed ${res.removed.length} account${res.removed.length === 1 ? '' : 's'}.`, 3200)
      await loadBots()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Cleanup failed.', 3600)
    } finally {
      setBotBusy(false)
    }
  }

  if (!user) return null
  if (user.role !== 'admin') {
    return (
      <div className="rb-box" style={{ padding: 24, textAlign: 'center', fontSize: 12, color: '#5a6b7b' }}>
        Admins only — this page runs the Tix economy.
      </div>
    )
  }

  async function savePackage(p: Pkg) {
    const d = draft[p.id] || {}
    setBusy(true)
    try {
      await api('/api/admin/rbx', {
        method: 'POST',
        body: JSON.stringify({ action: 'package.update', id: p.id, ...d }),
      })
      flash(setToast, `Package "${d.name || p.name}" saved.`)
      setDraft((x) => { const n = { ...x }; delete n[p.id]; return n })
      await load()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Save failed', 3000)
    } finally {
      setBusy(false)
    }
  }

  async function createPackage(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const fd = new FormData(e.currentTarget)
    setBusy(true)
    try {
      await api('/api/admin/rbx', {
        method: 'POST',
        body: JSON.stringify({
          action: 'package.create',
          name: String(fd.get('name') || ''),
          rbxAmount: Number(fd.get('rbxAmount')),
          priceCents: Math.round(Number(fd.get('price')) * 100),
        }),
      })
      flash(setToast, 'Package created — it is on sale now.')
      ;(e.target as HTMLFormElement).reset()
      await load()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Create failed', 3000)
    } finally {
      setBusy(false)
    }
  }

  async function grant(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setBusy(true)
    try {
      const res = await api<{ target: string; balanceAfter: number }>('/api/admin/rbx', {
        method: 'POST',
        body: JSON.stringify({
          action: 'grant',
          username: grantUser.trim(),
          amount: Number(grantAmount),
          note: grantNote.trim(),
        }),
      })
      flash(setToast, `${res.target} now holds T$ ${res.balanceAfter.toLocaleString('en-US')}.`)
      setGrantUser(''); setGrantAmount(''); setGrantNote('')
      refreshBalance()
      await load()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Grant failed', 3000)
    } finally {
      setBusy(false)
    }
  }

  if (error) return <div className="rb-box" style={{ padding: 20, color: '#a81a13', fontSize: 12 }}>{error}</div>
  if (!data) return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading the Tix desk...</div>

  const d = (id: string, field: keyof Pkg) => draft[id]?.[field]

  return (
    <div>
      {/* hero + stats */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Tix Admin</span></div>
        <div style={{ padding: 12, display: 'flex', flexWrap: 'wrap', gap: 14, fontSize: 11, color: '#41586c' }}>
          <span>Mode: <b style={{ color: data.mode === 'live' ? '#2c6e31' : '#8a6d1a' }}>{data.mode.toUpperCase()}</b></span>
          <span>Paid checkouts: <b>{data.stats.paymentsCount}</b></span>
          <span>Money in: <b>{usd(data.stats.totalPaidCents)}</b></span>
          <span>Refunded: <b>{usd(data.stats.totalRefundedCents)}</b></span>
          <span>Tix granted: <b>{data.stats.totalRbxGranted.toLocaleString('en-US')}</b></span>
          <span>Tix reversed: <b>{data.stats.totalRbxReversed.toLocaleString('en-US')}</b></span>
        </div>
      </div>

      {/* packages */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Tix Packages <span style={{ fontSize: 10, fontWeight: 'normal' }}>(the server price wins — the browser never sets prices)</span></span></div>
        <div style={{ padding: 10, display: 'flex', flexDirection: 'column', gap: 6 }}>
          {data.packages.map((p) => (
            <div key={p.id} style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', borderBottom: '1px solid #eef2f6', paddingBottom: 6 }}>
              <span style={{ fontSize: 9, fontFamily: 'monospace', color: '#7b8896', width: 130, overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.code}</span>
              <input
                className="rb-input"
                value={d(p.id, 'name') ?? p.name}
                onChange={(e) => setDraft((x) => ({ ...x, [p.id]: { ...x[p.id], name: e.target.value } }))}
                style={{ width: 120, fontSize: 11 }}
                aria-label="Package name"
              />
              <label style={{ fontSize: 10, color: '#1c4e7c' }}>
                Tix
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  value={d(p.id, 'rbxAmount') ?? p.rbxAmount}
                  onChange={(e) => setDraft((x) => ({ ...x, [p.id]: { ...x[p.id], rbxAmount: Number(e.target.value) } }))}
                  style={{ width: 84, fontSize: 11, marginLeft: 4 }}
                />
              </label>
              <label style={{ fontSize: 10, color: '#1c4e7c' }}>
                Price $
                <input
                  className="rb-input"
                  type="number"
                  min={0.01}
                  step={0.01}
                  value={((d(p.id, 'priceCents') ?? p.priceCents) / 100).toFixed(2)}
                  onChange={(e) => setDraft((x) => ({ ...x, [p.id]: { ...x[p.id], priceCents: Math.round(Number(e.target.value) * 100) } }))}
                  style={{ width: 74, fontSize: 11, marginLeft: 4 }}
                />
              </label>
              <label style={{ fontSize: 10, color: '#1c4e7c', display: 'flex', alignItems: 'center', gap: 3 }}>
                <input
                  type="checkbox"
                  checked={d(p.id, 'active') ?? p.active}
                  onChange={(e) => setDraft((x) => ({ ...x, [p.id]: { ...x[p.id], active: e.target.checked } }))}
                />
                on sale
              </label>
              <button className="rb-btn rb-btn-green" style={{ fontSize: 10, padding: '3px 10px' }} disabled={busy || Object.keys(draft[p.id] || {}).length === 0} onClick={() => savePackage(p)}>
                Save
              </button>
              {p.active ? null : <span style={{ fontSize: 10, color: '#a81a13' }}>hidden from the store</span>}
            </div>
          ))}

          <form onSubmit={createPackage} style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', marginTop: 4 }}>
            <input className="rb-input" name="name" placeholder="Name (e.g. 50 Tix)" style={{ width: 130, fontSize: 11 }} required minLength={2} maxLength={40} />
            <input className="rb-input" name="rbxAmount" type="number" min={1} placeholder="Tix" style={{ width: 84, fontSize: 11 }} required />
            <input className="rb-input" name="price" type="number" min={0.01} step={0.01} placeholder="Price $" style={{ width: 84, fontSize: 11 }} required />
            <button className="rb-btn" style={{ fontSize: 10, padding: '3px 10px' }} disabled={busy}>+ New package</button>
          </form>
        </div>
      </div>

      {/* grant */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Issue Tix <span style={{ fontSize: 10, fontWeight: 'normal' }}>(goes through the ledger like every other balance change)</span></span></div>
        <form onSubmit={grant} style={{ padding: 10, display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' }}>
          <input className="rb-input" placeholder="Username" value={grantUser} onChange={(e) => setGrantUser(e.target.value)} style={{ width: 140, fontSize: 11 }} required />
          <input className="rb-input" placeholder="± Tix (negative takes back)" type="number" value={grantAmount} onChange={(e) => setGrantAmount(e.target.value)} style={{ width: 170, fontSize: 11 }} required />
          <input className="rb-input" placeholder="Note (why)" value={grantNote} onChange={(e) => setGrantNote(e.target.value)} style={{ flex: 1, minWidth: 140, fontSize: 11 }} maxLength={200} />
          <button className="rb-btn rb-btn-green" style={{ fontSize: 11 }} disabled={busy}>Grant</button>
        </form>
      </div>

      {/* payments */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Payments <span style={{ fontSize: 10, fontWeight: 'normal' }}>(Stripe is the money truth — refunds happen in Stripe and flow back here)</span></span></div>
        <div style={{ padding: 8, overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 10, minWidth: 720 }}>
            <thead>
              <tr style={{ color: '#5a6b7b', textAlign: 'left' }}>
                <th style={{ padding: '4px 6px' }}>When</th>
                <th style={{ padding: '4px 6px' }}>Player</th>
                <th style={{ padding: '4px 6px' }}>Package</th>
                <th style={{ padding: '4px 6px' }}>Money</th>
                <th style={{ padding: '4px 6px' }}>Status</th>
                <th style={{ padding: '4px 6px' }}>Tix</th>
                <th style={{ padding: '4px 6px' }}>Checkout session</th>
                <th style={{ padding: '4px 6px' }}>Payment intent</th>
              </tr>
            </thead>
            <tbody>
              {data.payments.map((p) => (
                <tr key={p.id} style={{ borderTop: '1px solid #eef2f6' }}>
                  <td style={{ padding: '4px 6px', whiteSpace: 'nowrap' }}>{timeAgo(p.createdAt)}</td>
                  <td style={{ padding: '4px 6px' }}>{p.username}</td>
                  <td style={{ padding: '4px 6px' }}>{p.packageName}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace' }}>{usd(p.amountPaid)}{p.refundedCents > 0 ? ` (-${usd(p.refundedCents)})` : ''}</td>
                  <td style={{ padding: '4px 6px', color: STATUS_COLOR[p.status] || '#333', whiteSpace: 'nowrap' }}>{p.status}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace' }}>{p.rbxCredited > 0 ? `+${p.rbxCredited}` : '0'}{p.rbxReversed > 0 ? ` / -${p.rbxReversed}` : ''}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace', color: '#7b8896' }} title={p.sessionId}>{short(p.sessionId)}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace', color: '#7b8896' }} title={p.paymentIntentId || ''}>{short(p.paymentIntentId)}</td>
                </tr>
              ))}
              {data.payments.length === 0 && (
                <tr><td colSpan={8} style={{ padding: 10, color: '#7b8896' }}>No checkouts yet — real payments and failed attempts both land here.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* ledger */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Tix Ledger <span style={{ fontSize: 10, fontWeight: 'normal' }}>(append-only — history is never rewritten, refunds add reversal rows)</span></span></div>
        <div style={{ padding: 8, overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 10, minWidth: 680 }}>
            <thead>
              <tr style={{ color: '#5a6b7b', textAlign: 'left' }}>
                <th style={{ padding: '4px 6px' }}>When</th>
                <th style={{ padding: '4px 6px' }}>Player</th>
                <th style={{ padding: '4px 6px' }}>Type</th>
                <th style={{ padding: '4px 6px' }}>Change</th>
                <th style={{ padding: '4px 6px' }}>Before → after</th>
                <th style={{ padding: '4px 6px' }}>Note</th>
                <th style={{ padding: '4px 6px' }}>Stripe event</th>
              </tr>
            </thead>
            <tbody>
              {data.transactions.map((t) => (
                <tr key={t.id} style={{ borderTop: '1px solid #eef2f6' }}>
                  <td style={{ padding: '4px 6px', whiteSpace: 'nowrap' }}>{timeAgo(t.createdAt)}</td>
                  <td style={{ padding: '4px 6px' }}>{t.username}</td>
                  <td style={{ padding: '4px 6px' }}>{t.type}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace', color: t.amount >= 0 ? '#2c6e31' : '#a81a13' }}>{t.amount >= 0 ? '+' : ''}{t.amount}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace' }}>{t.balanceBefore} → {t.balanceAfter}</td>
                  <td style={{ padding: '4px 6px', color: '#41586c', maxWidth: 240, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={t.note}>{t.note}</td>
                  <td style={{ padding: '4px 6px', fontFamily: 'monospace', color: '#7b8896' }} title={t.stripeEventId || ''}>{short(t.stripeEventId)}</td>
                </tr>
              ))}
              {data.transactions.length === 0 && (
                <tr><td colSpan={7} style={{ padding: 10, color: '#7b8896' }}>The ledger is empty.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* balances */}
      <div className="rb-box">
        <div className="rb-panel-head"><span>Top Wallets</span></div>
        {/* bot cleanup — sweep junk accounts the tests/probes left behind */}
        <div className="rb-box" style={{ marginBottom: 12 }}>
          <div className="rb-panel-head"><span>Bot Cleanup — remove junk accounts</span></div>
          <div style={{ padding: 12 }}>
            <div style={{ fontSize: 11, color: '#41586c', marginBottom: 8 }}>
              Recent accounts (newest first). Probe/bot-shaped names are pre-checked. Removing an account deletes its items, trades, chats and comments too. Admins can never be removed.
            </div>
            <div style={{ display: 'grid', gap: 4, maxHeight: 300, overflowY: 'auto' }}>
              {bots.map((u) => (
                <label key={u.id} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 11, background: u.likelyBot ? '#fdf6e4' : '#fbfdfe', border: '1px solid #e8eef4', padding: '5px 8px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={botPicked.has(u.id)}
                    disabled={u.role === 'admin'}
                    onChange={(e) => setBotPicked((prev) => {
                      const n = new Set(prev)
                      if (e.target.checked) n.add(u.id)
                      else n.delete(u.id)
                      return n
                    })}
                  />
                  <span style={{ fontWeight: 'bold', color: '#1c2733' }}>{u.username}</span>
                  <span style={{ fontFamily: 'monospace', color: '#9aa7b4' }}>#{u.playerNo}</span>
                  {u.likelyBot && <span style={{ fontSize: 9, fontWeight: 'bold', color: '#8a6d1a', background: '#fffdf4', border: '1px solid #e0c98a', padding: '0 5px', borderRadius: 2 }}>bot?</span>}
                  {u.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                  <span style={{ marginLeft: 'auto', fontSize: 9.5, color: '#7b8896' }}>
                    joined {new Date(u.createdAt).toLocaleDateString('en-US')} · {u._count.inventory} items · {u._count.tradesSent + u._count.tradesRecv} trades
                  </span>
                </label>
              ))}
              {bots.length === 0 && <div style={{ fontSize: 11, color: '#8ba0b3' }}>No accounts to review.</div>}
            </div>
            <div style={{ marginTop: 9, display: 'flex', gap: 8, alignItems: 'center' }}>
              <button type="button" className="rb-btn rb-btn-red" disabled={botBusy || botPicked.size === 0} onClick={removeBots} style={{ fontSize: 11.5, padding: '5px 14px' }}>
                {botBusy ? 'Removing…' : `Remove ${botPicked.size || ''} picked`}
              </button>
              <span style={{ fontSize: 10, color: '#8ba0b3' }}>This cannot be undone.</span>
            </div>
          </div>
        </div>

        <div style={{ padding: 8, display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {data.holders.map((h) => (
            <Link
              key={h.id}
              href={`/users/${h.id}`}
              className="rb-link"
              style={{
                fontSize: 10, padding: '3px 8px', border: '1px solid #b7c6d4', borderRadius: 3,
                display: 'inline-flex', gap: 6, textDecoration: 'none',
              }}
            >
              <span>{h.username}{h.role === 'admin' ? ' ★' : ''}</span>
              <span style={{ fontFamily: 'monospace', color: '#1c4e7c' }}>T$ {h.rbxBalance.toLocaleString('en-US')}</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  )
}
