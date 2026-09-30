'use client'

/* ================= Trades & Market hub (/trades) =================
   Two tabs:

   TRADES — item-for-item (+ Tix) offers between players. Each side
   sees exactly what is on the table, chats ("throw in the Dominus
   and it's a deal"), counters the terms, then ACCEPTS — the swap is
   atomic: items and Tix move together or not at all.

   MARKET — your resale listings (with the Tix offers rolling in) and
   the offers you have sent, waiting on other sellers.
------------------------------------------------------------------ */

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { api, flash, timeAgo, useRetro } from '@/lib/store'
import { Avatar } from './Shell'
import { tixFull } from '@/lib/tix'
import { OfferItemChips, OfferItemPreview, parseIds as parseIdsJson } from './MarketPanel'

interface ItemPreview {
  id: string
  name: string
  type: string
  imageFileId: string
  isLimited: boolean
}

interface TradeRow {
  id: string
  status: string
  fromUserId: string
  toUserId: string
  fromUser: { id: string; username: string; avatarUrl: string | null }
  toUser: { id: string; username: string; avatarUrl: string | null }
  giveItemIds: string[]
  takeItemIds: string[]
  tixFrom: number
  tixTo: number
  createdAt: string
  updatedAt: string
  messages?: { id: string; text: string; sender: { id: string; username: string } }[]
}

interface TradeMsg {
  id: string
  text: string
  createdAt: string
  sender: { id: string; username: string; avatarUrl: string | null }
}

const fmt = (n: number) => `T$ ${tixFull(n)}`

function ItemChip({ item, note }: { item?: ItemPreview; note?: string }) {
  if (!item) return <span style={{ fontSize: 10.5, color: '#a81a13' }}>{note || 'item gone'}</span>
  return (
    <span
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 4, padding: '2px 6px 2px 2px',
        border: '1px solid #dbe4ec', background: '#fff', fontSize: 10.5, color: '#1c2733', maxWidth: 170,
      }}
      title={item.name}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`/api/files/${item.imageFileId}`} alt="" width={22} height={22} style={{ border: '1px solid #dbe4ec', objectFit: 'cover' }} />
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.name}</span>
      {item.isLimited && <span style={{ color: '#2c8e31', fontWeight: 'bold' }}>★</span>}
    </span>
  )
}

function TradeSide({ title, ids, itemMap, tix, tone }: { title: string; ids: string[]; itemMap: Record<string, ItemPreview>; tix: number; tone: 'give' | 'take' }) {
  const color = tone === 'give' ? '#2c6e31' : '#1c4e7c'
  return (
    <div style={{ flex: 1, minWidth: 180 }}>
      <div style={{ fontSize: 10, fontWeight: 'bold', color, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 4 }}>{title}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, alignItems: 'center' }}>
        {ids.length === 0 && tix <= 0 && <span style={{ fontSize: 10.5, color: '#8ba0b3' }}>nothing</span>}
        {ids.map((id) => <ItemChip key={id} item={itemMap[id]} />)}
        {tix > 0 && (
          <span style={{ fontSize: 11.5, fontFamily: 'monospace', fontWeight: 'bold', color: '#8a6d1a', background: '#fffdf4', border: '1px solid #e0c98a', padding: '2px 7px' }}>
            {fmt(tix)}
          </span>
        )}
      </div>
    </div>
  )
}

/* ---------------- one trade card + its chat ---------------- */
function TradeCard({
  trade,
  itemMap,
  meId,
  onChanged,
}: {
  trade: TradeRow
  itemMap: Record<string, ItemPreview>
  meId: string
  onChanged: () => void
}) {
  const { setToast } = useRetro()
  const [open, setOpen] = useState(false)
  const [msgs, setMsgs] = useState<TradeMsg[]>([])
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [counterTixFrom, setCounterTixFrom] = useState(String(trade.tixFrom))
  const [counterTixTo, setCounterTixTo] = useState(String(trade.tixTo))
  const [counterOpen, setCounterOpen] = useState(false)

  const isSender = trade.fromUserId === meId
  const other = isSender ? trade.toUser : trade.fromUser
  const lastMsg = trade.messages?.[0]

  const loadChat = useCallback(async () => {
    try {
      const res = await api<{ messages: TradeMsg[] }>(`/api/trades/${trade.id}`)
      setMsgs(res.messages || [])
    } catch { /* ignore */ }
  }, [trade.id])

  useEffect(() => {
    if (open) loadChat()
  }, [open, loadChat])

  async function act(payload: Record<string, unknown>, ok: string) {
    setBusy(true)
    try {
      const res = await api<{ message?: string }>(`/api/trades/${trade.id}`, { method: 'POST', body: JSON.stringify(payload) })
      flash(setToast, res.message || ok, 3400)
      onChanged()
      return true
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
      return false
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{ border: '1px solid #dbe4ec', background: '#fff' }}>
      <div style={{ padding: '8px 10px', display: 'flex', flexDirection: 'column', gap: 7 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <Avatar user={other} size={26} rounded={4} />
          <Link href={`/users/${other.id}`} className="rb-link" style={{ fontSize: 12, fontWeight: 'bold' }}>{other.username}</Link>
          <span style={{ fontSize: 10, color: '#8ba0b3' }}>{isSender ? 'you offered' : 'wants to trade'} · {timeAgo(trade.updatedAt)}</span>
          {lastMsg && !open && (
            <span style={{ fontSize: 10.5, color: '#5a6b7b', fontStyle: 'italic', maxWidth: 240, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              “{lastMsg.text}”
            </span>
          )}
          <span style={{ marginLeft: 'auto', display: 'flex', gap: 5 }}>
            {!open && (
              <button type="button" className="rb-btn" style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => setOpen(true)}>
                Open
              </button>
            )}
            {!isSender ? (
              <>
                <button type="button" className="rb-btn rb-btn-green" disabled={busy} style={{ fontSize: 10.5, padding: '2px 10px', fontWeight: 'bold' }} onClick={() => act({ action: 'accept' }, 'Trade complete!')}>
                  Accept
                </button>
                <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => act({ action: 'decline' }, 'Trade declined.')}>
                  Decline
                </button>
              </>
            ) : (
              <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => act({ action: 'cancel' }, 'Trade cancelled.')}>
                Cancel
              </button>
            )}
          </span>
        </div>

        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <TradeSide title={`${trade.fromUser.username} gives`} ids={trade.giveItemIds} itemMap={itemMap} tix={trade.tixFrom} tone="give" />
          <div style={{ alignSelf: 'center', fontSize: 16, color: '#8ba0b3' }}>⇄</div>
          <TradeSide title={`${trade.toUser.username} gives`} ids={trade.takeItemIds} itemMap={itemMap} tix={trade.tixTo} tone="take" />
        </div>

        {open && (
          <div style={{ borderTop: '1px solid #e8eef4', paddingTop: 7 }}>
            {/* chat */}
            <div style={{ maxHeight: 190, overflowY: 'auto', display: 'grid', gap: 4, marginBottom: 7 }}>
              {msgs.length === 0 ? (
                <div style={{ fontSize: 11, color: '#5a6b7b' }}>No messages yet — talk it out, then someone counters or accepts.</div>
              ) : (
                msgs.map((m) => (
                  <div key={m.id} style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
                    <Avatar user={m.sender} size={18} rounded={3} />
                    <div style={{ fontSize: 11.5, lineHeight: 1.45 }}>
                      <span style={{ fontWeight: 'bold', fontSize: 11 }}>{m.sender.username}</span>{' '}
                      <span style={{ color: '#1c2733' }}>{m.text}</span>{' '}
                      <span style={{ fontSize: 9, color: '#8ba0b3' }}>{timeAgo(m.createdAt)}</span>
                    </div>
                  </div>
                ))
              )}
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 8 }}>
              <input
                className="rb-input"
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && text.trim()) {
                    act({ action: 'message', text }, 'Message sent').then((ok) => { if (ok) { setText(''); loadChat() } })
                  }
                }}
                placeholder="Negotiate: “add the bucket hat and we're even”"
                style={{ flex: 1, fontSize: 11.5, height: 28 }}
                aria-label="Trade chat"
              />
              <button
                type="button"
                className="rb-btn"
                disabled={busy || !text.trim()}
                style={{ fontSize: 11, padding: '3px 12px' }}
                onClick={() => act({ action: 'message', text }, 'Message sent').then((ok) => { if (ok) { setText(''); loadChat() } })}
              >
                Send
              </button>
            </div>

            {/* counter — reshape the terms */}
            {counterOpen ? (
              <div style={{ border: '1px solid #cfe0ef', background: '#f3f9fe', padding: 8, display: 'grid', gap: 6 }}>
                <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c' }}>Counter — keep the items, move the Tix:</div>
                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
                  <label style={{ fontSize: 10.5, color: '#5a6b7b' }}>From {trade.fromUser.username}:</label>
                  <input className="rb-input" type="number" min={0} value={counterTixFrom} onChange={(e) => setCounterTixFrom(e.target.value)} style={{ width: 96, fontSize: 11.5, height: 26 }} />
                  <label style={{ fontSize: 10.5, color: '#5a6b7b' }}>From {trade.toUser.username}:</label>
                  <input className="rb-input" type="number" min={0} value={counterTixTo} onChange={(e) => setCounterTixTo(e.target.value)} style={{ width: 96, fontSize: 11.5, height: 26 }} />
                </div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <button
                    type="button"
                    className="rb-btn rb-btn-blue"
                    disabled={busy}
                    style={{ fontSize: 11, padding: '3px 12px' }}
                    onClick={() =>
                      act(
                        {
                          action: 'counter',
                          giveItemIds: trade.giveItemIds,
                          takeItemIds: trade.takeItemIds,
                          tixFrom: Math.max(0, Math.floor(Number(counterTixFrom) || 0)),
                          tixTo: Math.max(0, Math.floor(Number(counterTixTo) || 0)),
                        },
                        'Counter sent.'
                      ).then((ok) => { if (ok) { setCounterOpen(false); onChanged() } })
                    }
                  >
                    Send counter
                  </button>
                  <button type="button" className="rb-btn" style={{ fontSize: 11, padding: '3px 12px' }} onClick={() => setCounterOpen(false)}>
                    Never mind
                  </button>
                </div>
              </div>
            ) : (
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                <button type="button" className="rb-btn" style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => setCounterOpen(true)}>
                  Counter the terms
                </button>
                {isSender && (
                  <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => act({ action: 'cancel' }, 'Trade cancelled.')}>
                    Withdraw
                  </button>
                )}
                <button type="button" className="rb-btn" style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => setOpen(false)}>
                  Close
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

/* ---------------- market tab ---------------- */
interface ListingRow {
  id: string
  price: number
  status: string
  soldPrice?: number | null
  item: ItemPreview & { price: number; stock: number | null }
  offers: { id: string; amount: number; offerItemIdsJson?: string; status: string; createdAt: string; buyer: { id: string; username: string; avatarUrl: string | null } }[]
}

function MarketTab({ onChanged }: { onChanged: () => void }) {
  const { setToast } = useRetro()
  const [listings, setListings] = useState<ListingRow[]>([])
  const [offersSent, setOffersSent] = useState<{ id: string; amount: number; offerItemIdsJson?: string; status: string; createdAt: string; listing: { id: string; price: number; item: ItemPreview; seller: { id: string; username: string; avatarUrl: string | null } } }[]>([])
  const [offerItemMap, setOfferItemMap] = useState<Record<string, OfferItemPreview>>({})
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api<{ listings: ListingRow[]; offersSent: typeof offersSent; offerItemMap?: Record<string, OfferItemPreview> }>('/api/market?mine=1')
      setListings(res.listings || [])
      setOffersSent(res.offersSent || [])
      setOfferItemMap(res.offerItemMap || {})
    } catch { /* ignore */ }
  }, [])

  useEffect(() => { load() }, [load])

  async function act(payload: Record<string, unknown>, ok: string) {
    setBusy(true)
    try {
      const res = await api<{ message?: string }>('/api/market', { method: 'POST', body: JSON.stringify(payload) })
      flash(setToast, res.message || ok, 3400)
      await load()
      onChanged()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
    } finally {
      setBusy(false)
    }
  }

  const active = listings.filter((l) => l.status === 'active')
  const past = listings.filter((l) => l.status !== 'active')

  return (
    <div style={{ display: 'grid', gap: 10 }}>
      <div>
        <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 6 }}>YOUR LISTINGS — the Tix offers people sent:</div>
        {active.length === 0 ? (
          <div style={{ fontSize: 11.5, color: '#5a6b7b', padding: '9px 11px', background: '#f6f9fc', border: '1px solid #e8eef4' }}>
            Nothing on the market. Open any item you own and press <b>Sell this</b> — the site suggests 1.5x what you paid.
          </div>
        ) : (
          <div style={{ display: 'grid', gap: 8 }}>
            {active.map((l) => (
              <div key={l.id} style={{ border: '1px solid #dbe4ec', background: '#fff' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '8px 10px' }}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={`/api/files/${l.item.imageFileId}`} alt="" width={38} height={38} style={{ border: '1px solid #dbe4ec', objectFit: 'cover' }} />
                  <div>
                    <Link href={`/catalog/${l.item.id}`} className="rb-link" style={{ fontSize: 12.5, fontWeight: 'bold' }}>{l.item.name}</Link>
                    <div style={{ fontSize: 10.5, color: '#5a6b7b' }}>Asking {fmt(l.price)}</div>
                  </div>
                  <span style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
                    <LowerPrice listingId={l.id} price={l.price} busy={busy} onSave={(p) => act({ action: 'set_price', listingId: l.id, price: p }, 'Price updated')} />
                    <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 10.5, padding: '3px 10px' }} onClick={() => act({ action: 'cancel', listingId: l.id }, 'Listing taken down.')}>
                      Take down
                    </button>
                  </span>
                </div>
                {l.offers.length > 0 && (
                  <div style={{ borderTop: '1px solid #e8eef4', padding: '7px 10px', display: 'grid', gap: 5, background: '#fffdf4' }}>
                    <div style={{ fontSize: 10, fontWeight: 'bold', color: '#8a6d1a' }}>
                      {l.offers.length} PENDING OFFER{l.offers.length > 1 ? 'S' : ''} — accept to trade the item for their Tix + UGC:
                    </div>
                    {l.offers.map((o) => (
                      <div key={o.id} style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                        <Avatar user={o.buyer} size={20} rounded={3} />
                        <Link href={`/users/${o.buyer.id}`} className="rb-link" style={{ fontSize: 11.5, fontWeight: 'bold' }}>{o.buyer.username}</Link>
                        {o.amount > 0 && <span style={{ fontSize: 12, fontFamily: 'monospace', fontWeight: 'bold', color: '#1c4e7c' }}>{fmt(o.amount)}</span>}
                        <OfferItemChips ids={parseIdsJson(o.offerItemIdsJson)} itemMap={offerItemMap} />
                        <span style={{ fontSize: 9.5, color: '#8ba0b3' }}>{timeAgo(o.createdAt)}</span>
                        <span style={{ marginLeft: 'auto', display: 'flex', gap: 5 }}>
                          <button type="button" className="rb-btn rb-btn-green" disabled={busy} style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => act({ action: 'accept_offer', offerId: o.id }, 'Sold!')}>
                            Accept
                          </button>
                          <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 10.5, padding: '2px 10px' }} onClick={() => act({ action: 'decline_offer', offerId: o.id }, 'Offer declined.')}>
                            Decline
                          </button>
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {offersSent.length > 0 && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 6 }}>OFFERS YOU SENT — waiting on the sellers:</div>
          <div style={{ display: 'grid', gap: 5 }}>
            {offersSent.map((o) => (
              <div key={o.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 9px', border: '1px solid #e8eef4', background: '#fff', flexWrap: 'wrap' }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/api/files/${o.listing.item.imageFileId}`} alt="" width={26} height={26} style={{ border: '1px solid #dbe4ec', objectFit: 'cover' }} />
                <Link href={`/catalog/${o.listing.item.id}`} className="rb-link" style={{ fontSize: 11.5, fontWeight: 'bold' }}>{o.listing.item.name}</Link>
                <span style={{ fontSize: 10.5, color: '#5a6b7b' }}>asking {fmt(o.listing.price)}</span>
                {o.amount > 0 && <span style={{ fontSize: 11.5, fontFamily: 'monospace', fontWeight: 'bold', color: '#1c4e7c' }}>your offer {fmt(o.amount)}</span>}
                <OfferItemChips ids={parseIdsJson(o.offerItemIdsJson)} itemMap={offerItemMap} />
                <span
                  style={{
                    marginLeft: 'auto', fontSize: 10, fontWeight: 'bold', padding: '1px 8px',
                    background: o.status === 'pending' ? '#fff3cd' : o.status === 'accepted' ? '#eaf7eb' : '#fdeaea',
                    color: o.status === 'pending' ? '#8a6d1a' : o.status === 'accepted' ? '#2c6e31' : '#a81a13',
                    border: '1px solid #e0c98a',
                  }}
                >
                  {o.status}
                </span>
                {o.status === 'pending' && (
                  <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 10, padding: '2px 9px' }} onClick={() => act({ action: 'decline_offer', offerId: o.id }, 'Offer withdrawn.')} title="Take your offer back">
                    Withdraw
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {past.length > 0 && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 'bold', color: '#5a6b7b', marginBottom: 6 }}>SOLD / TAKEN DOWN:</div>
          <div style={{ display: 'grid', gap: 4 }}>
            {past.slice(0, 10).map((l) => (
              <div key={l.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 9px', border: '1px solid #e8eef4', background: '#fbfdfe', opacity: 0.85 }}>
                <ItemChip item={l.item} />
                <span style={{ fontSize: 10.5, color: '#5a6b7b' }}>
                  {l.status === 'sold' ? `SOLD for ${fmt(l.soldPrice || 0)}` : 'taken down'}
                </span>
                <span style={{ marginLeft: 'auto' }}>
                  <Link href={`/catalog/${l.item.id}`} className="rb-link" style={{ fontSize: 10.5 }}>view item</Link>
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function LowerPrice({ listingId, price, busy, onSave }: { listingId: string; price: number; busy: boolean; onSave: (p: number) => void }) {
  const [val, setVal] = useState(String(price))
  useEffect(() => setVal(String(price)), [price])
  return (
    <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
      <input
        className="rb-input"
        type="number"
        min={1}
        value={val}
        onChange={(e) => setVal(e.target.value)}
        style={{ width: 88, fontSize: 11, height: 26 }}
        aria-label={`New price for listing ${listingId}`}
      />
      <button type="button" className="rb-btn rb-btn-blue" disabled={busy || !val || Number(val) === price} style={{ fontSize: 10.5, padding: '3px 10px' }} onClick={() => onSave(Number(val))}>
        Set price
      </button>
    </span>
  )
}

/* ---------------- the hub ---------------- */
export function TradesView() {
  const { user } = useRetro()
  const [tab, setTab] = useState<'trades' | 'market'>('trades')
  const [incoming, setIncoming] = useState<TradeRow[]>([])
  const [outgoing, setOutgoing] = useState<TradeRow[]>([])
  const [itemMap, setItemMap] = useState<Record<string, ItemPreview>>({})
  const [reload, setReload] = useState(0)

  const load = useCallback(async () => {
    try {
      const res = await api<{ incoming: TradeRow[]; outgoing: TradeRow[]; itemMap: Record<string, ItemPreview> }>('/api/trades')
      setIncoming(res.incoming || [])
      setOutgoing(res.outgoing || [])
      setItemMap(res.itemMap || {})
    } catch { /* ignore */ }
  }, [])

  useEffect(() => { load() }, [load, reload])

  const tabBtn = (id: 'trades' | 'market', label: string, badge: number) => (
    <button
      type="button"
      onClick={() => setTab(id)}
      aria-pressed={tab === id}
      style={{
        fontSize: 12, padding: '6px 18px', cursor: 'pointer', fontWeight: 'bold',
        border: tab === id ? '1px solid #0069a8' : '1px solid #b7c6d4', borderBottom: tab === id ? '1px solid #fff' : '1px solid #b7c6d4',
        background: tab === id ? '#fff' : '#eef4fa', color: tab === id ? '#00639e' : '#1c4e7c', borderRadius: '3px 3px 0 0',
      }}
    >
      {label}
      {badge > 0 && <span className="rb-badge" style={{ marginLeft: 6 }}>{badge}</span>}
    </button>
  )

  return (
    <div>
      <div style={{ display: 'flex', gap: 4, marginBottom: -1 }}>
        {tabBtn('trades', 'Trades', incoming.length)}
        {tabBtn('market', 'Market', 0)}
      </div>
      <div className="rb-box" style={{ borderTopLeftRadius: 0, padding: 12 }}>
        {tab === 'trades' ? (
          <div style={{ display: 'grid', gap: 12 }}>
            <div>
              <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 6 }}>INCOMING — they want to trade with you:</div>
              {incoming.length === 0 ? (
                <div style={{ fontSize: 11.5, color: '#5a6b7b', padding: '9px 11px', background: '#f6f9fc', border: '1px solid #e8eef4' }}>
                  No trade offers right now. Offer one from any item page — or send a friend request and talk it out.
                </div>
              ) : (
                <div style={{ display: 'grid', gap: 8 }}>
                  {incoming.map((t) => <TradeCard key={t.id} trade={t} itemMap={itemMap} meId={user!.id} onChanged={() => setReload((r) => r + 1)} />)}
                </div>
              )}
            </div>
            {outgoing.length > 0 && (
              <div>
                <div style={{ fontSize: 11, fontWeight: 'bold', color: '#5a6b7b', marginBottom: 6 }}>OUTGOING — your offers on the table:</div>
                <div style={{ display: 'grid', gap: 8 }}>
                  {outgoing.map((t) => <TradeCard key={t.id} trade={t} itemMap={itemMap} meId={user!.id} onChanged={() => setReload((r) => r + 1)} />)}
                </div>
              </div>
            )}
          </div>
        ) : (
          <MarketTab onChanged={() => setReload((r) => r + 1)} />
        )}
      </div>
    </div>
  )
}
