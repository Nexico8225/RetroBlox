'use client'

/* TradesView — The /trades page:
   - Incoming & Sent offers
   - Counter trades
   - Find UGC Owners
   - Sell to Website (Instant Cashout)
   - RetroBank & IP Loans (Max 500 Tix) + Admin Free Tix
   Strictly NO emojis. Clean retro aesthetic. */

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { api, timeAgo, flash, useRetro } from '@/lib/store'
import { Avatar } from './Shell'
import { FxText } from '@/lib/textfx'

interface TradeItem {
  id: string
  assetId: string
  name: string
  type: string
  imageFileId: string
}

interface TradeRow {
  id: string
  status: 'pending' | 'accepted' | 'declined' | 'cancelled'
  tix: number
  message: string
  notes: { userId: string; text: string; at: string }[]
  createdAt: string
  respondedAt: string | null
  from: { id: string; username: string; avatarUrl: string | null }
  to: { id: string; username: string; avatarUrl: string | null }
  give: TradeItem[]
  take: TradeItem[]
  isIncoming: boolean
}

interface BankData {
  walletBalance: number
  bankBalance: number
  activeLoan: {
    id: string
    amount: number
    createdAt: string
    isUserLoan: boolean
  } | null
  canLoan: boolean
  maxLoan: number
  isAdmin: boolean
}

interface OwnedItem {
  id: string
  name: string
  type: string
  imageFileId: string
  price: number
  isLimited: boolean
  isSuperLimited?: boolean
}

const STATUS_STYLE: Record<string, { color: string; bg: string; label: string }> = {
  pending: { color: '#8a6d1a', bg: '#fff8e1', label: 'Pending' },
  accepted: { color: '#2c6e31', bg: '#eaf7ec', label: 'Accepted' },
  declined: { color: '#a81a13', bg: '#fdeeee', label: 'Declined' },
  cancelled: { color: '#5a6b7b', bg: '#eef2f6', label: 'Cancelled' },
}

function ItemChips({ items }: { items: TradeItem[] }) {
  if (items.length === 0) return <span style={{ fontSize: 11, color: '#8ba0b3' }}>nothing</span>
  return (
    <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
      {items.map((it) => (
        <Link
          key={it.id}
          href={`/catalog/${it.id}`}
          title={`${it.name} (${it.type})`}
          style={{ display: 'flex', alignItems: 'center', gap: 4, border: '1px solid #b7c6d4', background: '#fff', padding: '2px 6px 2px 2px', textDecoration: 'none' }}
        >
          <img src={`/api/files/${it.imageFileId}`} alt={it.name} style={{ width: 26, height: 26, objectFit: 'cover', background: '#fff', display: 'block' }} />
          <span style={{ fontSize: 11, color: '#1c4e7c' }}>{it.name}</span>
        </Link>
      ))}
    </div>
  )
}

function TradeCard({ trade, onChanged }: { trade: TradeRow; onChanged: () => void }) {
  const { setToast } = useRetro()
  const [busy, setBusy] = useState(false)
  const [reply, setReply] = useState('')
  const st = STATUS_STYLE[trade.status] || STATUS_STYLE.pending

  async function act(action: 'accept' | 'decline' | 'cancel', confirmMsg?: string) {
    if (confirmMsg && !window.confirm(confirmMsg)) return
    setBusy(true)
    try {
      const res = await api<{ message?: string }>(`/api/trades/${trade.id}`, {
        method: 'POST',
        body: JSON.stringify({ action }),
      })
      flash(setToast, res.message || 'Done!')
      onChanged()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.')
    } finally {
      setBusy(false)
    }
  }

  async function sendReply() {
    const text = reply.trim()
    if (!text) return
    setBusy(true)
    try {
      await api(`/api/trades/${trade.id}`, { method: 'POST', body: JSON.stringify({ action: 'message', text }) })
      setReply('')
      onChanged()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Message failed.')
    } finally {
      setBusy(false)
    }
  }

  const other = trade.isIncoming ? trade.from : trade.to

  return (
    <div className="rb-box" style={{ padding: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
        <Avatar user={other} size={24} rounded={4} />
        <Link href={`/users/${other.id}`} className="rb-link" style={{ fontSize: 12, fontWeight: 'bold' }}>
          {other.username}
        </Link>
        <span style={{ fontSize: 11, color: '#5a6b7b' }}>
          {trade.isIncoming ? 'offered you' : 'you offered'} · {timeAgo(trade.createdAt)}
        </span>
        <span style={{ fontSize: 10, padding: '2px 8px', borderRadius: 3, color: st.color, background: st.bg, border: '1px solid currentColor', marginLeft: 'auto' }}>
          {st.label}
        </span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', gap: 8, alignItems: 'start' }}>
        <div>
          <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: 0.5, color: '#5a6b7b', marginBottom: 4 }}>
            {trade.isIncoming ? 'They give' : 'You give'}
          </div>
          <ItemChips items={trade.isIncoming ? trade.give : trade.give} />
          {trade.tix > 0 && (
            <div style={{ fontSize: 11, fontFamily: 'monospace', color: '#8a6d1a', marginTop: 4 }}>
              + T$ {trade.tix.toLocaleString('en-US')}
            </div>
          )}
        </div>
        <div style={{ fontSize: 16, color: '#71869a', padding: '14px 2px' }}>⇄</div>
        <div>
          <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: 0.5, color: '#5a6b7b', marginBottom: 4 }}>
            {trade.isIncoming ? 'They want' : 'You want'}
          </div>
          <ItemChips items={trade.take} />
        </div>
      </div>

      {trade.message && (
        <div style={{ fontSize: 12, color: '#1c2733', background: '#f6f9fc', border: '1px solid #e8eef4', padding: '6px 9px', marginTop: 8 }}>
          <FxText text={trade.message} />
        </div>
      )}

      {trade.notes.length > 0 && (
        <div style={{ marginTop: 8, display: 'grid', gap: 4 }}>
          {trade.notes.map((n, i) => (
            <div key={i} style={{ fontSize: 11, color: '#1c2733' }}>
              <span style={{ color: '#0d69ac', fontWeight: 'bold' }}>
                {n.userId === trade.from.id ? trade.from.username : trade.to.username}:
              </span>{' '}
              <FxText text={n.text} />{' '}
              <span style={{ color: '#9aa7b4', fontSize: 10 }}>{timeAgo(n.at)}</span>
            </div>
          ))}
        </div>
      )}

      {trade.status === 'pending' && (
        <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap', alignItems: 'center' }}>
          {trade.isIncoming ? (
            <>
              <button className="rb-btn rb-btn-green" style={{ fontSize: 11 }} disabled={busy} onClick={() => act('accept')}>
                Accept Trade
              </button>
              <Link
                href={`/trades/new?with=${trade.from.id}&counter=${trade.id}`}
                className="rb-btn rb-btn-blue"
                style={{ fontSize: 11, textDecoration: 'none', display: 'inline-flex', alignItems: 'center' }}
              >
                Counter Trade
              </Link>
              <button className="rb-btn rb-btn-red" style={{ fontSize: 11 }} disabled={busy} onClick={() => act('decline', 'Decline this offer?')}>
                Decline
              </button>
            </>
          ) : (
            <button className="rb-btn" style={{ fontSize: 11 }} disabled={busy} onClick={() => act('cancel', 'Cancel your offer?')}>
              Cancel Offer
            </button>
          )}

          <div style={{ display: 'flex', gap: 4, marginLeft: 'auto', flex: '1 1 240px', maxWidth: 360 }}>
            <input
              className="rb-input"
              value={reply}
              onChange={(e) => setReply(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && sendReply()}
              placeholder="Leave a note or counter idea..."
              style={{ fontSize: 11, flex: 1 }}
              maxLength={200}
            />
            <button className="rb-btn" style={{ fontSize: 11 }} disabled={busy || !reply.trim()} onClick={sendReply}>
              Reply
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

export function TradesView() {
  const { user, setToast } = useRetro()
  const [trades, setTrades] = useState<TradeRow[]>([])
  const [tab, setTab] = useState<'incoming' | 'outgoing' | 'owners' | 'cashout' | 'bank' | 'done'>('incoming')
  const [loading, setLoading] = useState(true)

  // UGC Owners tab state
  const [ownerSearch, setOwnerSearch] = useState('')
  const [searchingOwners, setSearchingOwners] = useState(false)
  const [ownerItems, setOwnerItems] = useState<any[]>([])

  // Bank & Cashout state
  const [bankData, setBankData] = useState<BankData | null>(null)
  const [bankAmount, setBankAmount] = useState('')
  const [bankBusy, setBankBusy] = useState(false)
  const [myInventory, setMyInventory] = useState<OwnedItem[]>([])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = await api<{ trades: TradeRow[] }>('/api/trades')
      setTrades(res.trades || [])
    } catch {
      /* not logged in */
    } finally {
      setLoading(false)
    }
  }, [])

  const loadBank = useCallback(async () => {
    try {
      const data = await api<BankData>('/api/bank')
      setBankData(data)
    } catch {}
  }, [])

  const loadInventory = useCallback(async () => {
    if (!user?.id) return
    try {
      const res = await api<{ inventory: OwnedItem[] }>(`/api/users/${user.id}`)
      setMyInventory(res.inventory || [])
    } catch {}
  }, [user?.id])

  useEffect(() => {
    load()
    loadBank()
    loadInventory()
  }, [load, loadBank, loadInventory])

  async function searchOwners(q: string) {
    setSearchingOwners(true)
    try {
      const res = await api<{ items: any[] }>(`/api/trades/owners?q=${encodeURIComponent(q.trim())}`)
      setOwnerItems(res.items || [])
    } catch {
      setOwnerItems([])
    } finally {
      setSearchingOwners(false)
    }
  }

  async function handleBankAction(action: 'deposit' | 'withdraw' | 'loan' | 'repay_loan' | 'admin_mint', amount?: number) {
    setBankBusy(true)
    try {
      const res = await api<{ ok: boolean; message: string }>('/api/bank', {
        method: 'POST',
        body: JSON.stringify({ action, amount }),
      })
      flash(setToast, res.message)
      setBankAmount('')
      await loadBank()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Action failed.')
    } finally {
      setBankBusy(false)
    }
  }

  async function sellToWebsite(itemId: string) {
    if (!window.confirm('Sell this UGC to the website for instant Tix? It will be removed from your inventory.')) return
    try {
      const res = await api<{ ok: boolean; message: string; payout: number }>('/api/bank', {
        method: 'POST',
        body: JSON.stringify({ action: 'sell_to_website', itemId }),
      })
      flash(setToast, res.message)
      await Promise.all([loadBank(), loadInventory()])
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to sell item.')
    }
  }

  if (!user) {
    return (
      <div className="rb-box" style={{ padding: 30, textAlign: 'center', color: '#5a6b7b', fontSize: 13 }}>
        Log in to see your trades and access RetroBank.{' '}
        <Link href="/login" className="rb-link">Log in</Link>
      </div>
    )
  }

  const incoming = trades.filter((t) => t.isIncoming && t.status === 'pending')
  const outgoing = trades.filter((t) => !t.isIncoming && t.status === 'pending')
  const done = trades.filter((t) => t.status !== 'pending')
  const list = tab === 'incoming' ? incoming : tab === 'outgoing' ? outgoing : done

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div className="rb-box" style={{ padding: 0 }}>
        <div className="rb-panel-head">
          <span>Trades &amp; Market</span>
          <span style={{ fontSize: 10, color: '#71869a' }}>swap UGC, cashout to website, or manage RetroBank</span>
        </div>
        <div style={{ display: 'flex', gap: 4, padding: '8px 10px 0', flexWrap: 'wrap' }}>
          {([
            ['incoming', `Incoming (${incoming.length})`],
            ['outgoing', `Sent (${outgoing.length})`],
            ['owners', 'Find UGC Owners'],
            ['cashout', 'Sell to Website'],
            ['bank', 'RetroBank & Loans'],
            ['done', `History (${done.length})`],
          ] as const).map(([k, label]) => (
            <button
              key={k}
              type="button"
              onClick={() => {
                setTab(k)
                if (k === 'bank') loadBank()
                if (k === 'cashout') loadInventory()
              }}
              aria-pressed={tab === k}
              className="rb-btn"
              style={{
                fontSize: 11,
                ...(tab === k
                  ? { background: 'linear-gradient(180deg,#dceaf5,#c8e0f0)', borderColor: '#7fb3d3', color: '#084672' }
                  : {}),
              }}
            >
              {label}
            </button>
          ))}
        </div>

        <div style={{ padding: 10 }}>
          {tab === 'bank' ? (
            /* ========================================================
               RETROBANK & IP LOANS SECTION
               ======================================================== */
            <div style={{ display: 'grid', gap: 12 }}>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 10 }}>
                <div className="rb-box" style={{ padding: 12, background: '#f8fafc' }}>
                  <div style={{ fontSize: 11, color: '#5a6b7b' }}>Wallet Balance</div>
                  <div style={{ fontSize: 20, fontWeight: 'bold', color: '#029a4a', fontFamily: 'monospace' }}>
                    T$ {(bankData?.walletBalance ?? 10).toLocaleString('en-US')}
                  </div>
                </div>
                <div className="rb-box" style={{ padding: 12, background: '#f0f7fc' }}>
                  <div style={{ fontSize: 11, color: '#5a6b7b' }}>RetroBank Vault (Stored)</div>
                  <div style={{ fontSize: 20, fontWeight: 'bold', color: '#0070b6', fontFamily: 'monospace' }}>
                    T$ {(bankData?.bankBalance ?? 0).toLocaleString('en-US')}
                  </div>
                </div>
              </div>

              {/* Deposit / Withdraw Controls */}
              <div className="rb-box" style={{ padding: 12 }}>
                <div style={{ fontSize: 12, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 6 }}>
                  Deposit / Withdraw Tix
                </div>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                  <input
                    className="rb-input"
                    type="number"
                    min={1}
                    placeholder="Amount of Tix..."
                    value={bankAmount}
                    onChange={(e) => setBankAmount(e.target.value)}
                    style={{ width: 140, fontSize: 12 }}
                  />
                  <button
                    type="button"
                    className="rb-btn rb-btn-green"
                    disabled={bankBusy || !bankAmount}
                    onClick={() => handleBankAction('deposit', Number(bankAmount))}
                  >
                    Deposit to Vault
                  </button>
                  <button
                    type="button"
                    className="rb-btn"
                    disabled={bankBusy || !bankAmount}
                    onClick={() => handleBankAction('withdraw', Number(bankAmount))}
                  >
                    Withdraw to Wallet
                  </button>
                </div>
              </div>

              {/* Loans Section: 1 active loan per IP address, max 500 Tix */}
              <div className="rb-box" style={{ padding: 12, border: '1px solid #dbe4ec' }}>
                <div style={{ fontSize: 12, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 4 }}>
                  RetroBank Loans (Max 500 Tix)
                </div>
                <div style={{ fontSize: 11, color: '#64748b', marginBottom: 8, lineHeight: 1.4 }}>
                  Each player or IP address can borrow up to 500 Tix. Only one active loan is allowed per IP address at a time until fully repaid.
                </div>

                {bankData?.activeLoan ? (
                  <div style={{ padding: 10, background: '#fffdf4', border: '1px solid #e0c98a', borderRadius: 4 }}>
                    <div style={{ fontSize: 12, fontWeight: 'bold', color: '#8a6d1a' }}>
                      Active Loan: T$ {bankData.activeLoan.amount.toLocaleString('en-US')}
                    </div>
                    <div style={{ fontSize: 10.5, color: '#5a6b7b', margin: '4px 0 8px' }}>
                      Borrowed {timeAgo(bankData.activeLoan.createdAt)}. You must repay this loan before borrowing again.
                    </div>
                    <button
                      type="button"
                      className="rb-btn rb-btn-green"
                      disabled={bankBusy}
                      onClick={() => handleBankAction('repay_loan')}
                    >
                      Repay Loan (T$ {bankData.activeLoan.amount.toLocaleString('en-US')})
                    </button>
                  </div>
                ) : (
                  <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                    {[100, 250, 500].map((amt) => (
                      <button
                        key={amt}
                        type="button"
                        className="rb-btn rb-btn-blue"
                        disabled={bankBusy}
                        onClick={() => handleBankAction('loan', amt)}
                      >
                        Borrow T$ {amt}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Admin Mint (Only for Nexico8225 / admin) */}
              {bankData?.isAdmin && (
                <div className="rb-box" style={{ padding: 12, background: '#fdf6e4', border: '1px solid #e0d3a6' }}>
                  <div style={{ fontSize: 12, fontWeight: 'bold', color: '#8a6d1a', marginBottom: 4 }}>
                    Admin Controls (Nexico8225 Only)
                  </div>
                  <div style={{ fontSize: 11, color: '#64748b', marginBottom: 8 }}>
                    Free Tix minting for the administrator.
                  </div>
                  <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                    <button
                      type="button"
                      className="rb-btn rb-btn-green"
                      disabled={bankBusy}
                      onClick={() => handleBankAction('admin_mint', 500)}
                    >
                      Mint +500 Tix Free
                    </button>
                    <button
                      type="button"
                      className="rb-btn rb-btn-green"
                      disabled={bankBusy}
                      onClick={() => handleBankAction('admin_mint', 5000)}
                    >
                      Mint +5,000 Tix Free
                    </button>
                  </div>
                </div>
              )}
            </div>
          ) : tab === 'cashout' ? (
            /* ========================================================
               SELL TO WEBSITE (INSTANT CASHOUT)
               ======================================================== */
            <div style={{ display: 'grid', gap: 12 }}>
              <div style={{ fontSize: 12, color: '#5a6b7b' }}>
                Sell any of your owned UGC items directly to the website for instant Tix payout (80% of value).
              </div>
              {myInventory.length === 0 ? (
                <div style={{ padding: 24, textAlign: 'center', color: '#7b8896', fontStyle: 'italic' }}>
                  You have no UGC items in your inventory to sell.
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: 10 }}>
                  {myInventory.map((item) => {
                    const payout = Math.max(1, Math.round((item.price || 5) * 0.8))
                    return (
                      <div key={item.id} className="rb-box" style={{ padding: 8, textAlign: 'center', display: 'flex', flexDirection: 'column' }}>
                        <div style={{ width: '100%', aspectRatio: '1', background: '#fff', border: '1px solid #eef2f6', marginBottom: 6 }}>
                          <img
                            src={`/api/files/${item.imageFileId}`}
                            alt={item.name}
                            style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                          />
                        </div>
                        <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c2733', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginBottom: 2 }}>
                          {item.name}
                        </div>
                        <div style={{ fontSize: 10, color: '#029a4a', fontWeight: 'bold', fontFamily: 'monospace', marginBottom: 6 }}>
                          Instant: T$ {payout.toLocaleString('en-US')}
                        </div>
                        <button
                          type="button"
                          className="rb-btn rb-btn-green"
                          style={{ fontSize: 10, padding: '3px 6px', marginTop: 'auto' }}
                          onClick={() => sellToWebsite(item.id)}
                        >
                          Sell to Website
                        </button>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          ) : tab === 'owners' ? (
            /* ========================================================
               FIND UGC OWNERS
               ======================================================== */
            <div style={{ display: 'grid', gap: 12 }}>
              <div style={{ display: 'flex', gap: 6 }}>
                <input
                  className="rb-input"
                  placeholder="Search item name (e.g. Traffic Cone, Dominus, Mr Tentacles)..."
                  value={ownerSearch}
                  onChange={(e) => setOwnerSearch(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') searchOwners(ownerSearch) }}
                  style={{ flex: 1, fontSize: 12, padding: '5px 8px' }}
                />
                <button
                  type="button"
                  className="rb-btn rb-btn-blue"
                  disabled={searchingOwners}
                  onClick={() => searchOwners(ownerSearch)}
                  style={{ fontSize: 11, padding: '4px 12px' }}
                >
                  {searchingOwners ? 'Searching...' : 'Find Owners'}
                </button>
              </div>

              {searchingOwners ? (
                <div style={{ fontSize: 11, color: '#5a6b7b' }}>Looking up item owners...</div>
              ) : ownerItems.length === 0 ? (
                <div style={{ fontSize: 11, color: '#5a6b7b', fontStyle: 'italic' }}>
                  No items found matching &quot;{ownerSearch}&quot;. Try searching for another UGC item!
                </div>
              ) : (
                <div style={{ display: 'grid', gap: 10 }}>
                  {ownerItems.map((it) => (
                    <div key={it.id} className="rb-box" style={{ padding: 10, display: 'grid', gap: 8 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <img
                          src={`/api/files/${it.imageFileId}`}
                          alt={it.name}
                          style={{ width: 44, height: 44, objectFit: 'contain', border: '1px solid #b7c6d4', background: '#fff' }}
                        />
                        <div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <Link href={`/catalog/${it.id}`} className="rb-link" style={{ fontSize: 13, fontWeight: 'bold' }}>
                              {it.name}
                            </Link>
                            {it.isSuperLimited ? (
                              <span style={{ fontSize: 9, fontWeight: 'bold', padding: '1px 6px', background: '#9b51e0', color: '#fff', borderRadius: 3 }}>
                                SUPER LIMITED
                              </span>
                            ) : it.isLimited ? (
                              <span style={{ fontSize: 9, fontWeight: 'bold', padding: '1px 6px', background: '#2c6e31', color: '#fff', borderRadius: 3 }}>
                                LIMITED
                              </span>
                            ) : null}
                          </div>
                          <div style={{ fontSize: 11, color: '#5a6b7b' }}>
                            {it.type} • T$ {it.price.toLocaleString('en-US')} • {it.owners.length} current owner(s)
                          </div>
                        </div>
                      </div>

                      <div style={{ borderTop: '1px solid #e8eef4', paddingTop: 6 }}>
                        <div style={{ fontSize: 10, textTransform: 'uppercase', color: '#71869a', marginBottom: 4, fontWeight: 'bold' }}>
                          Players who own this UGC:
                        </div>
                        {it.owners.length === 0 ? (
                          <div style={{ fontSize: 11, color: '#8ba0b3', fontStyle: 'italic' }}>No registered owners yet.</div>
                        ) : (
                          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 6 }}>
                            {it.owners.map((ow: any) => (
                              <div
                                key={ow.id}
                                style={{
                                  display: 'flex',
                                  alignItems: 'center',
                                  gap: 6,
                                  border: '1px solid #cfe0ef',
                                  background: '#f9fcfe',
                                  padding: 4,
                                  borderRadius: 3,
                                }}
                              >
                                <Avatar user={ow} size={22} rounded={3} />
                                <div style={{ flex: 1, minWidth: 0, fontSize: 11 }}>
                                  <Link href={`/users/${ow.id}`} className="rb-link" style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                    {ow.username}
                                  </Link>
                                </div>
                                {ow.id !== user.id && (
                                  <Link
                                    href={`/trades/new?with=${ow.id}&item=${it.id}`}
                                    className="rb-btn rb-btn-green"
                                    style={{ fontSize: 10, padding: '2px 8px', textDecoration: 'none', whiteSpace: 'nowrap' }}
                                  >
                                    Trade
                                  </Link>
                                )}
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          ) : loading ? (
            <div style={{ fontSize: 12, color: '#5a6b7b' }}>Loading trades...</div>
          ) : list.length === 0 ? (
            <div style={{ fontSize: 12, color: '#5a6b7b' }}>
              {tab === 'incoming' && 'No incoming offers. When someone offers a trade for one of your items, it lands here.'}
              {tab === 'outgoing' && 'No pending offers from you. Open any catalog item and press "Trade" to make one.'}
              {tab === 'done' && 'No finished trades yet.'}
            </div>
          ) : (
            <div style={{ display: 'grid', gap: 8 }}>
              {list.map((t) => (
                <TradeCard key={t.id} trade={t} onChanged={load} />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
