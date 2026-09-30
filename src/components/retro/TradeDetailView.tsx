'use client'

/* ================= Trade room (/trades/[id]) =================
   The page a notification drops you on. Everything one trade
   needs lives here, laid out like the classic trade window:

     ┌───────────────────────────┬──────────────────┐
     │  THEIR offer  ⇄  YOUR offer │  the negotiation │
     │  (items + Tix + Robux)      │  chat, FX included│
     └───────────────────────────┴──────────────────┘

   Chat refreshes every few seconds so both sides watch the
   deal come together live. Accepting swaps items + both
   currencies atomically — nobody can ever be left holding
   half a trade.
------------------------------------------------------------------ */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { api, flash, timeAgo, useRetro, refreshBalance } from '@/lib/store'
import { Avatar } from './Shell'
import { tixFull } from '@/lib/tix'
import { FxText, FxToolbar } from '@/lib/textfx'
interface ItemInfo {
  id: string
  name: string
  type: string
  imageFileId: string
  isLimited: boolean
  price: number
  stock: number | null
}

interface TradeMsg {
  id: string
  text: string
  createdAt: string
  sender: { id: string; username: string; avatarUrl: string | null }
}

interface TradeInfo {
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
  robuxFrom: number
  robuxTo: number
  createdAt: string
  updatedAt: string
}

const robux = (n: number) => `R$ ${tixFull(n)}`

function StatusChip({ status }: { status: string }) {
  const map: Record<string, { bg: string; fg: string; label: string }> = {
    pending: { bg: '#fff3cd', fg: '#8a6d1a', label: 'PENDING' },
    accepted: { bg: '#eaf7eb', fg: '#2c6e31', label: 'ACCEPTED' },
    declined: { bg: '#fdeaea', fg: '#a81a13', label: 'DECLINED' },
    cancelled: { bg: '#f1f4f7', fg: '#5a6b7b', label: 'CANCELLED' },
  }
  const s = map[status] || map.pending
  return (
    <span style={{ fontSize: 10, fontWeight: 'bold', letterSpacing: '0.6px', padding: '2px 10px', background: s.bg, color: s.fg, border: '1px solid currentColor' }}>
      {s.label}
    </span>
  )
}

/** One side of the trade table — items stacked like the classic window. */
function TradeSidePanel({
  title, person, ids, itemMap, tix, robuxAmt, tone, missingIds,
}: {
  title: string
  person: { id: string; username: string; avatarUrl: string | null }
  ids: string[]
  itemMap: Record<string, ItemInfo>
  tix: number
  robuxAmt: number
  tone: 'give' | 'take'
  missingIds: string[]
}) {
  const color = tone === 'give' ? '#2c6e31' : '#1c4e7c'
  const empty = ids.length === 0 && tix <= 0 && robuxAmt <= 0
  return (
    <div style={{ flex: 1, minWidth: 210, border: '1px solid #dbe4ec', background: '#fbfdfe' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '7px 9px', borderBottom: '1px solid #e8eef4', background: '#fff' }}>
        <Avatar user={person} size={26} rounded={4} />
        <div>
          <div style={{ fontSize: 10, fontWeight: 'bold', color, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{title}</div>
          <Link href={`/users/${person.id}`} className="rb-link" style={{ fontSize: 11.5, fontWeight: 'bold' }}>{person.username}</Link>
        </div>
        <span style={{ marginLeft: 'auto', fontSize: 10, color: '#8ba0b3' }}>{ids.length} item{ids.length === 1 ? '' : 's'}</span>
      </div>
      <div style={{ padding: 8, display: 'grid', gap: 5, minHeight: 92 }}>
        {empty && <span style={{ fontSize: 11, color: '#8ba0b3', fontStyle: 'italic' }}>nothing on this side yet</span>}
        {ids.map((id) => {
          const it = itemMap[id]
          const gone = !it || missingIds.includes(id)
          return (
            <div key={id} style={{ display: 'flex', alignItems: 'center', gap: 6, background: '#fff', border: `1px solid ${gone ? '#eec4c1' : '#dbe4ec'}`, padding: '3px 6px 3px 3px', opacity: gone ? 0.6 : 1 }}>
              {it ? (
                <>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={`/api/files/${it.imageFileId}`} alt="" width={30} height={30} style={{ border: '1px solid #dbe4ec', objectFit: 'cover' }} />
                  <span style={{ fontSize: 11.5, fontWeight: 'bold', color: '#1c2733', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{it.name}</span>
                  {it.isLimited && <span title="Limited item" style={{ color: '#2c8e31', fontWeight: 'bold', fontSize: 11 }}>★</span>}
                  {gone && <span style={{ marginLeft: 'auto', fontSize: 9.5, color: '#a81a13' }}>no longer owned</span>}
                </>
              ) : (
                <span style={{ fontSize: 10.5, color: '#a81a13' }}>item removed from the catalog</span>
              )}
            </div>
          )
        })}
        {(tix > 0 || robuxAmt > 0) && (
          <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
            {tix > 0 && (
              <span style={{ fontSize: 12.5, fontFamily: 'monospace', fontWeight: 'bold', color: '#8a6d1a', background: '#fffdf4', border: '1px solid #e0c98a', padding: '2px 8px' }}>
                T$ {tixFull(tix)}
              </span>
            )}
            {robuxAmt > 0 && (
              <span style={{ fontSize: 12.5, fontFamily: 'monospace', fontWeight: 'bold', color: '#1c4e7c', background: '#f2f8fd', border: '1px solid #b9d4e8', padding: '2px 8px' }}>
                {robux(robuxAmt)}
              </span>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

export function TradeDetailView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const [trade, setTrade] = useState<TradeInfo | null>(null)
  const [itemMap, setItemMap] = useState<Record<string, ItemInfo>>({})
  const [iStillOwn, setIStillOwn] = useState<string[]>([])
  const [msgs, setMsgs] = useState<TradeMsg[]>([])
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [notFound, setNotFound] = useState(false)
  const [counterOpen, setCounterOpen] = useState(false)
  const [cTixFrom, setCTixFrom] = useState('0')
  const [cTixTo, setCTixTo] = useState('0')
  const [cRobuxFrom, setCRobuxFrom] = useState('0')
  const [cRobuxTo, setCRobuxTo] = useState('0')
  const chatEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const isSender = trade ? trade.fromUserId === user?.id : false
  const other = trade ? (trade.fromUserId === user?.id ? trade.toUser : trade.fromUser) : null
  const settled = trade ? trade.status !== 'pending' : false

  const loadChat = useCallback(async () => {
    try {
      const res = await api<{ messages: TradeMsg[] }>(`/api/trades/${id}`)
      setMsgs(res.messages || [])
    } catch { /* ignore */ }
  }, [id])

  const lastSeenUpdate = useRef<string>('')

  const loadTrade = useCallback(async () => {
    try {
      const res = await api<{ trade: TradeInfo; itemMap: Record<string, ItemInfo>; iStillOwn: string[]; messages: TradeMsg[] }>(`/api/trades/${id}`)
      setTrade(res.trade)
      setItemMap(res.itemMap || {})
      setIStillOwn(res.iStillOwn || [])
      setMsgs(res.messages || [])
      // sync the counter inputs only when the TERMS actually changed —
      // otherwise the poll would stomp on whatever the user is typing
      if (res.trade.updatedAt !== lastSeenUpdate.current) {
        lastSeenUpdate.current = res.trade.updatedAt
        setCTixFrom(String(res.trade.tixFrom))
        setCTixTo(String(res.trade.tixTo))
        setCRobuxFrom(String(res.trade.robuxFrom))
        setCRobuxTo(String(res.trade.robuxTo))
      }
    } catch {
      setNotFound(true)
    }
  }, [id])

  useEffect(() => { loadTrade() }, [loadTrade])

  // the chat keeps itself fresh while the tab is open — negotiation
  // is a conversation, not a refresh-button exercise
  useEffect(() => {
    const chatTick = setInterval(loadChat, 4000)
    return () => clearInterval(chatTick)
  }, [loadChat])

  // the trade state refreshes a little slower (terms + status)
  useEffect(() => {
    if (settled) return
    const t = setInterval(loadTrade, 8000)
    return () => clearInterval(t)
  }, [loadTrade, settled])

  // keep the chat scrolled to the newest message
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ block: 'nearest' })
  }, [msgs.length])

  async function act(payload: Record<string, unknown>, ok: string) {
    setBusy(true)
    try {
      const res = await api<{ message?: string }>(`/api/trades/${id}`, { method: 'POST', body: JSON.stringify(payload) })
      flash(setToast, res.message || ok, 3400)
      await loadTrade()
      refreshBalance()
      return true
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
      return false
    } finally {
      setBusy(false)
    }
  }

  async function send() {
    const t = text.trim()
    if (!t) return
    setText('')
    if (await act({ action: 'message', text: t }, 'Message sent')) loadChat()
  }

  if (notFound) {
    return (
      <div className="rb-box" style={{ padding: 22, textAlign: 'center', display: 'grid', gap: 10, justifyItems: 'center' }}>
        <div style={{ fontSize: 13, fontWeight: 'bold' }}>That trade does not exist (or is not yours to see).</div>
        <Link href="/trades" className="rb-btn">Back to Trades</Link>
      </div>
    )
  }

  if (!trade || !other || !user) {
    return <div className="rb-box" style={{ padding: 22, fontSize: 12, color: '#5a6b7b' }}>Opening the trade room…</div>
  }

  // when I'm the sender: I give "give", they give "take" — flip it when I'm the recipient
  const myGive = isSender ? { ids: trade.giveItemIds, tix: trade.tixFrom, robuxAmt: trade.robuxFrom } : { ids: trade.takeItemIds, tix: trade.tixTo, robuxAmt: trade.robuxTo }
  const theirGive = isSender ? { ids: trade.takeItemIds, tix: trade.tixTo, robuxAmt: trade.robuxTo } : { ids: trade.giveItemIds, tix: trade.tixFrom, robuxAmt: trade.robuxFrom }

  return (
    <div style={{ display: 'grid', gap: 10 }}>
      {/* header */}
      <div className="rb-box" style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 9, flexWrap: 'wrap' }}>
        <Link href="/trades" className="rb-link" style={{ fontSize: 11.5 }}>← Trades</Link>
        <span style={{ fontSize: 13.5, fontWeight: 'bold' }}>
          Trade with {other.username}
        </span>
        <StatusChip status={trade.status} />
        <span style={{ marginLeft: 'auto', fontSize: 10, color: '#8ba0b3' }}>opened {timeAgo(trade.createdAt)}</span>
      </div>

      <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start', flexWrap: 'wrap' }}>
        {/* ---- left: the two-sided table ---- */}
        <div style={{ flex: '1 1 380px', display: 'grid', gap: 10, minWidth: 0 }}>
          <div className="rb-box" style={{ padding: 12 }}>
            <div style={{ display: 'flex', gap: 10, alignItems: 'stretch', flexWrap: 'wrap' }}>
              <TradeSidePanel
                title="They give"
                person={other}
                ids={theirGive.ids}
                itemMap={itemMap}
                tix={theirGive.tix}
                robuxAmt={theirGive.robuxAmt}
                tone="take"
                missingIds={[]}
              />
              <div style={{ alignSelf: 'center', fontSize: 22, color: '#8ba0b3' }} title="for">⇄</div>
              <TradeSidePanel
                title="You give"
                person={{ id: user.id, username: user.username, avatarUrl: user.avatarUrl }}
                ids={myGive.ids}
                itemMap={itemMap}
                tix={myGive.tix}
                robuxAmt={myGive.robuxAmt}
                tone="give"
                missingIds={myGive.ids.filter((x) => !iStillOwn.includes(x))}
              />
            </div>

            {/* actions */}
            <div style={{ borderTop: '1px solid #e8eef4', marginTop: 10, paddingTop: 9, display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
              {!settled && !isSender && (
                <>
                  <button type="button" className="rb-btn rb-btn-green" disabled={busy} style={{ fontWeight: 'bold', fontSize: 12, padding: '4px 16px' }} onClick={() => act({ action: 'accept' }, 'Trade complete!')}>
                    Accept trade
                  </button>
                  <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 11.5 }} onClick={() => act({ action: 'decline' }, 'Trade declined.')}>
                    Decline
                  </button>
                </>
              )}
              {!settled && isSender && (
                <button type="button" className="rb-btn" disabled={busy} style={{ fontSize: 11.5 }} onClick={() => act({ action: 'cancel' }, 'Trade cancelled.')}>
                  Withdraw offer
                </button>
              )}
              {!settled && (
                <button type="button" className="rb-btn rb-btn-blue" style={{ fontSize: 11.5 }} onClick={() => setCounterOpen((v) => !v)}>
                  {counterOpen ? 'Close counter' : 'Counter the terms'}
                </button>
              )}
              {settled && <span style={{ fontSize: 11, color: '#5a6b7b', fontStyle: 'italic' }}>This trade is settled — nothing more can change.</span>}
            </div>

            {/* counter editor */}
            {!settled && counterOpen && (
              <div style={{ border: '1px solid #cfe0ef', background: '#f3f9fe', padding: 9, marginTop: 9, display: 'grid', gap: 7 }}>
                <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c' }}>
                  Counter — keep the items where they are, set the money both ways:
                </div>
                {[
                  { label: `Tix from ${trade.fromUser.username}`, val: cTixFrom, set: setCTixFrom },
                  { label: `Tix from ${trade.toUser.username}`, val: cTixTo, set: setCTixTo },
                  { label: `Robux from ${trade.fromUser.username}`, val: cRobuxFrom, set: setCRobuxFrom },
                  { label: `Robux from ${trade.toUser.username}`, val: cRobuxTo, set: setCRobuxTo },
                ].map((row) => (
                  <label key={row.label} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 11, color: '#3c4c5c' }}>
                    <span style={{ width: 210 }}>{row.label}:</span>
                    <input className="rb-input" type="number" min={0} value={row.val} onChange={(e) => row.set(e.target.value)} style={{ width: 110, fontSize: 11.5, height: 26 }} />
                  </label>
                ))}
                <div style={{ display: 'flex', gap: 6 }}>
                  <button
                    type="button"
                    className="rb-btn rb-btn-blue"
                    disabled={busy}
                    style={{ fontSize: 11, padding: '3px 14px' }}
                    onClick={() =>
                      act(
                        {
                          action: 'counter',
                          giveItemIds: trade.giveItemIds,
                          takeItemIds: trade.takeItemIds,
                          tixFrom: Math.max(0, Math.floor(Number(cTixFrom) || 0)),
                          tixTo: Math.max(0, Math.floor(Number(cTixTo) || 0)),
                          robuxFrom: Math.max(0, Math.floor(Number(cRobuxFrom) || 0)),
                          robuxTo: Math.max(0, Math.floor(Number(cRobuxTo) || 0)),
                        },
                        'Counter sent.'
                      ).then((ok) => { if (ok) setCounterOpen(false) })
                    }
                  >
                    Send counter
                  </button>
                  <button type="button" className="rb-btn" style={{ fontSize: 11, padding: '3px 12px' }} onClick={() => setCounterOpen(false)}>
                    Never mind
                  </button>
                </div>
              </div>
            )}
          </div>

          <div style={{ fontSize: 10.5, color: '#8ba0b3', padding: '0 4px' }}>
            Accepting swaps every item and every coin in one motion — half-trades are impossible. Currency: <b>T$</b> Tix · <b>R$</b> Robux.
          </div>
        </div>

        {/* ---- right: the negotiation chat ---- */}
        <div className="rb-box" style={{ width: 320, flex: '0 1 320px', display: 'flex', flexDirection: 'column', maxHeight: 520, minWidth: 280 }}>
          <div style={{ background: '#0d69ac', color: '#fff', margin: '-1px', padding: '6px 10px', fontSize: 12, fontWeight: 'bold', display: 'flex', alignItems: 'center', gap: 6 }}>
            Trade chat
            <span style={{ marginLeft: 'auto', fontSize: 9.5, fontWeight: 'normal', opacity: 0.85 }}>live</span>
          </div>
          <div style={{ flex: 1, overflowY: 'auto', padding: 9, display: 'grid', gap: 7, alignContent: 'start', minHeight: 220 }}>
            {msgs.length === 0 ? (
              <div style={{ fontSize: 11, color: '#5a6b7b', fontStyle: 'italic' }}>
                No messages yet. Ask for more Tix, offer a throw-in, or just say hi — then someone accepts.
              </div>
            ) : (
              msgs.map((m) => {
                const mine = m.sender.id === user.id
                return (
                  <div key={m.id} style={{ display: 'flex', flexDirection: 'column', alignItems: mine ? 'flex-end' : 'flex-start' }}>
                    <div style={{ display: 'flex', gap: 5, alignItems: 'center', marginBottom: 1 }}>
                      {!mine && <Avatar user={m.sender} size={16} rounded={3} />}
                      <span style={{ fontSize: 10, fontWeight: 'bold', color: mine ? '#2c6e31' : '#1c4e7c' }}>{mine ? 'you' : m.sender.username}</span>
                      <span style={{ fontSize: 8.5, color: '#a8b8c6' }}>{timeAgo(m.createdAt)}</span>
                    </div>
                    <div style={{ fontSize: 11.5, lineHeight: 1.45, background: mine ? '#eaf7eb' : '#f3f9fe', border: '1px solid #e1eaf2', padding: '4px 8px', maxWidth: '92%', wordBreak: 'break-word' }}>
                      <FxText text={m.text} />
                    </div>
                  </div>
                )
              })
            )}
            <div ref={chatEndRef} />
          </div>
          <div style={{ borderTop: '1px solid #e8eef4', padding: 8, display: 'grid', gap: 6 }}>
            <FxToolbar taRef={inputRef} value={text} onChange={setText} />
            <div style={{ display: 'flex', gap: 6 }}>
              <input
                ref={inputRef}
                className="rb-input"
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') send() }}
                placeholder="Talk it out — [shake]shake[/shake] your words"
                style={{ flex: 1, fontSize: 11.5, height: 28 }}
                aria-label="Trade chat message"
                maxLength={300}
              />
              <button type="button" className="rb-btn" disabled={busy || !text.trim()} style={{ fontSize: 11, padding: '3px 12px' }} onClick={send}>
                Send
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
