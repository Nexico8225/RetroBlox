'use client'

/* ================= Resale Market panel (item page) =================
   The player-to-player UGC economy, one panel:

   - OWNERS  list their copy for Tix (the site suggests 1.5x what they
     paid — the classic infinite-Tix loop), lower the price while
     haggling, take it down, and accept/decline incoming Tix offers.
   - BUYERS  buy NOW at the asking price, send a Tix offer the seller
     is free to take or leave ("he takes a guess to keep and give UGC
     or not"), haggle in the open chat, or offer an item-for-item TRADE.
   - EVERYONE sees the market history graph on the item page.
------------------------------------------------------------------ */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { api, flash, timeAgo, useRetro } from '@/lib/store'
import { Avatar } from './Shell'

export interface MarketListing {
  id: string
  price: number
  createdAt: string
  seller: { id: string; username: string; avatarUrl: string | null }
  offerCount: number
  topOffer: number
}

export interface MarketData {
  listings: MarketListing[]
  history: { price: number; kind: string; at: string }[]
  myListing: string | null
  myOffer: { id: string; amount: number } | null
  mySerial: number | null
  suggestedPrice: number | null
}

interface ChatMsg {
  id: string
  text: string
  createdAt: string
  sender: { id: string; username: string; avatarUrl: string | null }
}

interface OfferRow {
  id: string
  amount: number
  status: string
  createdAt: string
  buyer: { id: string; username: string; avatarUrl: string | null }
}

const fmt = (n: number) => `T$ ${n.toLocaleString('en-US')}`

/* ---------------- the market history graph ----------------
   Real transaction prices over time — blue dots are creator sales
   (mint), green dots are player resales. This is the actual market,
   not the price ladder. */
export function MarketHistoryChart({ history }: { history: MarketData['history'] }) {
  if (history.length < 2) return null
  const W = 620
  const H = 200
  const L = 46
  const R = 14
  const T = 16
  const B = 34
  const maxP = Math.max(...history.map((h) => h.price), 1)
  const minP = Math.min(...history.map((h) => h.price), 0)
  const x = (i: number) => L + (i * (W - L - R)) / Math.max(1, history.length - 1)
  const y = (p: number) => B - ((p - minP) / Math.max(1, maxP - minP)) * (B - T)

  const line = history.map((h, i) => `${i === 0 ? 'M' : 'L'} ${x(i).toFixed(1)} ${y(h.price).toFixed(1)}`).join(' ')

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto', display: 'block' }} role="img" aria-label="Market history — real sale prices over time">
      {/* gridlines */}
      {[0.25, 0.5, 0.75].map((g) => {
        const gy = B - g * (B - T)
        const val = minP + g * (maxP - minP)
        return (
          <g key={g}>
            <line x1={L} y1={gy} x2={W - R} y2={gy} stroke="#eef2f6" strokeWidth={1} />
            <text x={L - 5} y={gy + 3} textAnchor="end" fontSize={9} fill="#9aa7b4" fontFamily="monospace">
              {val >= 10000 ? `${Math.round(val / 1000)}K` : Math.round(val).toLocaleString('en-US')}
            </text>
          </g>
        )
      })}
      <line x1={L} y1={B} x2={W - R} y2={B} stroke="#d4dce4" strokeWidth={1.5} />
      <path d={line} fill="none" stroke="#0d69ac" strokeWidth={2} strokeLinejoin="round" opacity={0.85} />
      {history.map((h, i) => (
        <g key={i}>
          <circle
            cx={x(i)}
            cy={y(h.price)}
            r={h.kind === 'resale' ? 4.5 : 3}
            fill={h.kind === 'resale' ? '#2c8e31' : h.kind === 'trade' ? '#d35400' : '#0d69ac'}
            stroke="#fff"
            strokeWidth={1.2}
          />
          <title>{`${fmt(h.price)} — ${h.kind === 'resale' ? 'player resale' : h.kind === 'trade' ? 'trade' : 'creator sale'} · ${timeAgo(h.at)}`}</title>
        </g>
      ))}
      <text x={L} y={B + 16} fontSize={9} fill="#7b8896">
        {new Date(history[0].at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
      </text>
      <text x={W - R} y={B + 16} textAnchor="end" fontSize={9} fill="#7b8896">
        {new Date(history[history.length - 1].at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} · latest {fmt(history[history.length - 1].price)}
      </text>
      {/* legend */}
      <g fontSize={9.5} fill="#5a6b7b">
        <circle cx={L + 8} cy={T - 4} r={3} fill="#0d69ac" />
        <text x={L + 15} y={T - 1}>creator sale</text>
        <circle cx={L + 90} cy={T - 4} r={3.6} fill="#2c8e31" />
        <text x={L + 98} y={T - 1}>player resale</text>
        <circle cx={L + 176} cy={T - 4} r={3.2} fill="#d35400" />
        <text x={L + 184} y={T - 1}>trade</text>
      </g>
    </svg>
  )
}

/* ---------------- the trade offer modal ----------------
   Pick items from your inventory (+ optional Tix) and offer them for
   THIS item. The other player gets a notification and can chat,
   counter, accept or decline. */
export function TradeOfferModal({
  itemId,
  itemName,
  toUserId,
  toLabel,
  onClose,
  onSent,
}: {
  itemId: string
  itemName: string
  toUserId: string
  toLabel: string
  onClose: () => void
  onSent: () => void
}) {
  const { setToast } = useRetro()
  const [inv, setInv] = useState<{ id: string; name: string; imageFileId: string; type: string }[]>([])
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [tix, setTix] = useState('')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    api<{ items: { id: string; name: string; imageFileId: string; type: string }[]; ownedItemIds: string[] }>('/api/catalog')
      .then((res) => {
        const ownedSet = new Set(res.ownedItemIds)
        setInv(res.items.filter((i) => ownedSet.has(i.id) && i.id !== itemId))
      })
      .catch(() => {})
  }, [itemId])

  function toggle(id: string) {
    setPicked((p) => {
      const n = new Set(p)
      if (n.has(id)) n.delete(id)
      else if (n.size < 8) n.add(id)
      return n
    })
  }

  async function send() {
    setBusy(true)
    try {
      const res = await api<{ message?: string }>('/api/trades', {
        method: 'POST',
        body: JSON.stringify({
          toUserId,
          giveItemIds: [...picked],
          takeItemIds: [itemId],
          tix: Math.max(0, Math.floor(Number(tix) || 0)),
          message: msg,
        }),
      })
      flash(setToast, res.message || 'Trade offer sent!', 3400)
      onSent()
      onClose()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 200, background: 'rgba(9,30,50,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16 }} onClick={onClose}>
      <div
        className="rb-box"
        style={{ width: '100%', maxWidth: 560, maxHeight: '86vh', overflowY: 'auto', padding: 14, background: '#fff' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: 16, color: '#1c2733' }}>Offer a trade to {toLabel}</h3>
          <button type="button" className="rb-btn" style={{ padding: '2px 9px' }} onClick={onClose} aria-label="Close">✕</button>
        </div>
        <div style={{ fontSize: 11.5, color: '#5a6b7b', marginBottom: 10 }}>
          They get <b>{itemName}</b> from you{tix && Number(tix) > 0 ? ` + ${fmt(Number(tix))}` : ''} — if they accept. They can chat and counter first.
        </div>

        <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c', margin: '8px 0 5px' }}>YOU GIVE — pick from your inventory ({picked.size}/8):</div>
        {inv.length === 0 ? (
          <div style={{ fontSize: 11.5, color: '#5a6b7b', padding: '8px 10px', background: '#f6f9fc', border: '1px solid #e8eef4' }}>
            Nothing tradeable in your inventory yet — grab something from the catalog first (or just offer Tix).
          </div>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(86px,1fr))', gap: 6, marginBottom: 8 }}>
            {inv.map((i) => {
              const on = picked.has(i.id)
              return (
                <button
                  key={i.id}
                  type="button"
                  onClick={() => toggle(i.id)}
                  aria-pressed={on}
                  style={{
                    padding: 5, cursor: 'pointer', textAlign: 'center',
                    border: on ? '2px solid #2c8e31' : '1px solid #b7c6d4',
                    background: on ? '#eaf7eb' : '#fff',
                  }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={`/api/files/${i.imageFileId}`} alt={i.name} width={56} height={56} style={{ objectFit: 'cover', display: 'block', margin: '0 auto 3px', border: '1px solid #dbe4ec' }} />
                  <span style={{ fontSize: 9, color: '#1c2733', display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{i.name}</span>
                </button>
              )
            })}
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '130px 1fr', gap: 8, alignItems: 'center', margin: '8px 0' }}>
          <label style={{ fontSize: 11, color: '#5a6b7b' }}>Tix you add:</label>
          <input className="rb-input" type="number" min={0} max={1000000} value={tix} onChange={(e) => setTix(e.target.value)} placeholder="0" style={{ fontSize: 12, height: 28 }} />
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '130px 1fr', gap: 8, alignItems: 'start', marginBottom: 12 }}>
          <label style={{ fontSize: 11, color: '#5a6b7b', paddingTop: 4 }}>Say something:</label>
          <textarea
            className="rb-input"
            value={msg}
            onChange={(e) => setMsg(e.target.value)}
            placeholder="Trade you my Golden Dominus for this — plus a little Tix on top?"
            rows={2}
            style={{ fontSize: 12, resize: 'vertical' }}
          />
        </div>
        <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
          <button type="button" className="rb-btn" onClick={onClose}>Cancel</button>
          <button type="button" className="rb-btn rb-btn-green" disabled={busy || (picked.size === 0 && !(Number(tix) > 0))} onClick={send} style={{ fontWeight: 'bold' }}>
            {busy ? 'Sending...' : 'Send trade offer'}
          </button>
        </div>
      </div>
    </div>
  )
}

/* ---------------- the panel ---------------- */
export function MarketPanel({
  itemId,
  itemName,
  owned,
  market,
  onChanged,
}: {
  itemId: string
  itemName: string
  owned: boolean
  market: MarketData
  onChanged: () => void
}) {
  const { user, setToast } = useRetro()
  const [sellOpen, setSellOpen] = useState(false)
  const [sellPrice, setSellPrice] = useState('')
  const [lowerPrice, setLowerPrice] = useState('')
  const [offerAmount, setOfferAmount] = useState('')
  const [busy, setBusy] = useState(false)
  const [chatFor, setChatFor] = useState<string | null>(null)
  const [tradeFor, setTradeFor] = useState<{ userId: string; label: string } | null>(null)

  const myListings = market.listings.filter((l) => l.seller.id === user?.id)
  const otherListings = market.listings.filter((l) => l.seller.id !== user?.id)
  const myListing = myListings[0]

  useEffect(() => {
    if (myListing) setLowerPrice(String(myListing.price))
  }, [myListing?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (sellOpen && !sellPrice && market.suggestedPrice) setSellPrice(String(market.suggestedPrice))
  }, [sellOpen]) // eslint-disable-line react-hooks/exhaustive-deps

  const act = useCallback(
    async (payload: Record<string, unknown>, ok: string) => {
      setBusy(true)
      try {
        const res = await api<{ message?: string }>('/api/market', { method: 'POST', body: JSON.stringify(payload) })
        flash(setToast, res.message || ok, 3400)
        onChanged()
        return true
      } catch (e) {
        flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
        return false
      } finally {
        setBusy(false)
      }
    },
    [onChanged, setToast]
  )

  const canSell = owned && !myListing

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {/* ---------- SELLER STRIP (owners) ---------- */}
      {user && owned && (
        <div style={{ border: '1px solid #cfe0ef', background: '#f3f9fe', padding: '9px 11px' }}>
          {myListing ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <span style={{ fontSize: 12, fontWeight: 'bold', color: '#1c4e7c' }}>Your listing: {fmt(myListing.price)}</span>
                {myListing.offerCount > 0 && (
                  <span style={{ fontSize: 10.5, background: '#fff3cd', border: '1px solid #e0c98a', padding: '1px 7px', color: '#8a6d1a', fontWeight: 'bold' }}>
                    {myListing.offerCount} offer{myListing.offerCount > 1 ? 's' : ''} — top {fmt(myListing.topOffer)}
                  </span>
                )}
                <button type="button" className="rb-link" style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 11 }} onClick={() => setChatFor(chatFor === myListing.id ? null : myListing.id)}>
                  {chatFor === myListing.id ? 'Hide offers & chat' : 'Offers & chat'}
                </button>
              </div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  value={lowerPrice}
                  onChange={(e) => setLowerPrice(e.target.value)}
                  style={{ width: 110, fontSize: 12, height: 28 }}
                  aria-label="New asking price"
                />
                <button type="button" className="rb-btn" disabled={busy} onClick={() => act({ action: 'set_price', listingId: myListing.id, price: Number(lowerPrice) }, 'Price updated')}>
                  Lower price
                </button>
                <button type="button" className="rb-btn" disabled={busy} onClick={() => act({ action: 'cancel', listingId: myListing.id }, 'Listing taken down')}>
                  Take down
                </button>
                {market.suggestedPrice && (
                  <span style={{ fontSize: 10.5, color: '#8a6d1a' }}>
                    Market value: <b>{fmt(market.suggestedPrice)}</b> (1.5x what you paid)
                  </span>
                )}
              </div>
            </div>
          ) : sellOpen ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ fontSize: 12, fontWeight: 'bold', color: '#1c4e7c' }}>Sell your copy of {itemName}</div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                <span style={{ fontSize: 11, color: '#5a6b7b' }}>Asking price:</span>
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  value={sellPrice}
                  onChange={(e) => setSellPrice(e.target.value)}
                  style={{ width: 120, fontSize: 12, height: 28 }}
                  aria-label="Asking price"
                />
                <button type="button" className="rb-btn rb-btn-green" disabled={busy} onClick={async () => { if (await act({ action: 'list', itemId, price: Number(sellPrice) }, 'Listed!')) setSellOpen(false) }} style={{ fontWeight: 'bold' }}>
                  List it
                </button>
                <button type="button" className="rb-btn" onClick={() => setSellOpen(false)}>Cancel</button>
              </div>
              {market.suggestedPrice && (
                <div style={{ fontSize: 10.5, color: '#8a6d1a' }}>
                  Suggested: <b>{fmt(market.suggestedPrice)}</b> — 1.5x what you paid. Sell at 1.5x and every hand-off profits!
                </div>
              )}
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <button type="button" className="rb-btn rb-btn-blue" onClick={() => setSellOpen(true)} style={{ fontSize: 12, padding: '5px 14px', fontWeight: 'bold' }}>
                Sell this
              </button>
              <span style={{ fontSize: 10.5, color: '#5a6b7b' }}>
                {market.suggestedPrice ? <>Market value: <b>{fmt(market.suggestedPrice)}</b> (1.5x what you paid). </> : ''}
                Put it on the market and haggle in the comments.
              </span>
            </div>
          )}
        </div>
      )}

      {/* ---------- MY PENDING OFFER ---------- */}
      {user && market.myOffer && !owned && (
        <div style={{ border: '1px solid #e0c98a', background: '#fffdf4', padding: '7px 11px', fontSize: 11.5, color: '#8a6d1a' }}>
          Your offer of <b>{fmt(market.myOffer.amount)}</b> is waiting for the seller&apos;s answer.
        </div>
      )}

      {/* ---------- ACTIVE LISTINGS ---------- */}
      <div>
        <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 5 }}>
          Resale market — {market.listings.length === 0 ? 'no copies listed right now' : `${market.listings.length} listing${market.listings.length > 1 ? 's' : ''}, cheapest first`}
        </div>
        {market.listings.length === 0 ? (
          <div style={{ fontSize: 11.5, color: '#5a6b7b', padding: '8px 10px', background: '#f6f9fc', border: '1px solid #e8eef4' }}>
            Nobody is reselling this yet{owned ? ' — be the first seller!' : '. Owners can list theirs with one click.'}
          </div>
        ) : (
          <div style={{ display: 'grid', gap: 6 }}>
            {market.listings.map((l) => (
              <div key={l.id} style={{ border: '1px solid #dbe4ec', background: '#fff' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 9px', flexWrap: 'wrap' }}>
                  <Avatar user={l.seller} size={26} rounded={4} />
                  <Link href={`/users/${l.seller.id}`} className="rb-link" style={{ fontSize: 12, fontWeight: 'bold' }}>
                    {l.seller.username}
                  </Link>
                  <span style={{ fontSize: 15, fontFamily: 'monospace', fontWeight: 'bold', color: '#1c4e7c', marginLeft: 'auto' }}>{fmt(l.price)}</span>
                  {l.offerCount > 0 && (
                    <span style={{ fontSize: 9.5, color: '#8a6d1a' }} title="Highest pending offer">
                      top offer {fmt(l.topOffer)}
                    </span>
                  )}
                </div>
                {user && user.id !== l.seller.id && (
                  <div style={{ display: 'flex', gap: 6, padding: '0 9px 8px', flexWrap: 'wrap', alignItems: 'center' }}>
                    <button type="button" className="rb-btn rb-btn-green" disabled={busy} onClick={() => act({ action: 'buy', listingId: l.id }, 'Bought!')} style={{ fontSize: 11.5, padding: '4px 12px', fontWeight: 'bold' }}>
                      Buy now — {fmt(l.price)}
                    </button>
                    <input
                      className="rb-input"
                      type="number"
                      min={1}
                      placeholder="Your offer"
                      value={offerAmount}
                      onChange={(e) => setOfferAmount(e.target.value)}
                      style={{ width: 96, fontSize: 11.5, height: 26 }}
                      aria-label="Your Tix offer"
                    />
                    <button
                      type="button"
                      className="rb-btn"
                      disabled={busy || !(Number(offerAmount) > 0)}
                      onClick={async () => {
                        if (await act({ action: 'offer', listingId: l.id, amount: Number(offerAmount) }, 'Offer sent!')) setOfferAmount('')
                      }}
                      style={{ fontSize: 11.5, padding: '4px 10px' }}
                      title="Send some Tix — the seller decides whether to hand the item over"
                    >
                      Send offer
                    </button>
                    <button type="button" className="rb-btn" onClick={() => setTradeFor({ userId: l.seller.id, label: l.seller.username })} style={{ fontSize: 11.5, padding: '4px 10px' }} title="Offer items from your inventory instead">
                      🔁 Trade
                    </button>
                    <button type="button" className="rb-link" style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 11 }} onClick={() => setChatFor(chatFor === l.id ? null : l.id)}>
                      {chatFor === l.id ? 'hide chat' : 'chat'}
                    </button>
                  </div>
                )}
                {chatFor === l.id && (
                  <ListingChat listingId={l.id} isSeller={user?.id === l.seller.id} onChanged={onChanged} />
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* trade modal */}
      {tradeFor && (
        <TradeOfferModal
          itemId={itemId}
          itemName={itemName}
          toUserId={tradeFor.userId}
          toLabel={tradeFor.label}
          onClose={() => setTradeFor(null)}
          onSent={onChanged}
        />
      )}
    </div>
  )
}

/* ---------------- haggle chat on one listing ---------------- */
function ListingChat({ listingId, isSeller, onChanged }: { listingId: string; isSeller: boolean; onChanged: () => void }) {
  const { setToast } = useRetro()
  const [msgs, setMsgs] = useState<ChatMsg[]>([])
  const [offers, setOffers] = useState<OfferRow[]>([])
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const bottom = useRef<HTMLDivElement | null>(null)

  const load = useCallback(async () => {
    try {
      const res = await api<{ messages: ChatMsg[]; offers: OfferRow[] }>(`/api/market/${listingId}`)
      setMsgs(res.messages || [])
      setOffers(res.offers || [])
    } catch { /* ignore */ }
  }, [listingId])

  useEffect(() => {
    load()
  }, [load])

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: 'nearest' })
  }, [msgs.length])

  async function send() {
    if (!text.trim()) return
    setBusy(true)
    try {
      await api(`/api/market/${listingId}`, { method: 'POST', body: JSON.stringify({ text }) })
      setText('')
      await load()
      onChanged()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3200)
    } finally {
      setBusy(false)
    }
  }

  async function answer(offerId: string, accept: boolean) {
    setBusy(true)
    try {
      await api('/api/market', { method: 'POST', body: JSON.stringify({ action: accept ? 'accept_offer' : 'decline_offer', offerId }) })
      flash(setToast, accept ? 'Sold! The Tix are in your wallet.' : 'Offer declined.', 3200)
      await load()
      onChanged()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{ borderTop: '1px solid #dbe4ec', background: '#f9fbfd', padding: 9 }}>
      {isSeller && offers.length > 0 && (
        <div style={{ marginBottom: 8 }}>
          <div style={{ fontSize: 10.5, fontWeight: 'bold', color: '#8a6d1a', marginBottom: 4 }}>OFFERS — take the Tix and hand over the item, or hold out:</div>
          <div style={{ display: 'grid', gap: 4 }}>
            {offers.map((o) => (
              <div key={o.id} style={{ display: 'flex', alignItems: 'center', gap: 8, background: '#fff', border: '1px solid #e8eef4', padding: '4px 8px' }}>
                <Avatar user={o.buyer} size={20} rounded={3} />
                <span style={{ fontSize: 11.5, fontWeight: 'bold' }}>{o.buyer.username}</span>
                <span style={{ fontSize: 12, fontFamily: 'monospace', color: '#1c4e7c', fontWeight: 'bold' }}>{fmt(o.amount)}</span>
                <span style={{ fontSize: 9.5, color: '#8ba0b3' }}>{timeAgo(o.createdAt)}</span>
                <span style={{ marginLeft: 'auto', display: 'flex', gap: 5 }}>
                  <button type="button" className="rb-btn rb-btn-green" disabled={busy} onClick={() => answer(o.id, true)} style={{ fontSize: 10.5, padding: '2px 10px' }}>
                    Accept
                  </button>
                  <button type="button" className="rb-btn" disabled={busy} onClick={() => answer(o.id, false)} style={{ fontSize: 10.5, padding: '2px 10px' }}>
                    Decline
                  </button>
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
      <div style={{ maxHeight: 200, overflowY: 'auto', display: 'grid', gap: 4, marginBottom: 7 }}>
        {msgs.length === 0 ? (
          <div style={{ fontSize: 11, color: '#5a6b7b' }}>No messages yet — this is where the price gets talked down.</div>
        ) : (
          msgs.map((m) => (
            <div key={m.id} style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
              <Avatar user={m.sender} size={18} rounded={3} />
              <div style={{ fontSize: 11.5, lineHeight: 1.45 }}>
                <Link href={`/users/${m.sender.id}`} className="rb-link" style={{ fontWeight: 'bold', fontSize: 11 }}>{m.sender.username}</Link>{' '}
                <span style={{ color: '#1c2733' }}>{m.text}</span>{' '}
                <span style={{ fontSize: 9, color: '#8ba0b3' }}>{timeAgo(m.createdAt)}</span>
              </div>
            </div>
          ))
        )}
        <div ref={bottom} />
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        <input
          className="rb-input"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }}
          placeholder={isSeller ? 'Reply — or just lower the price above' : 'Haggle: "take 400 and it\u2019s a deal"'}
          style={{ flex: 1, fontSize: 11.5, height: 28 }}
          aria-label="Chat message"
        />
        <button type="button" className="rb-btn" disabled={busy || !text.trim()} onClick={send} style={{ fontSize: 11, padding: '3px 12px' }}>
          Send
        </button>
      </div>
    </div>
  )
}
