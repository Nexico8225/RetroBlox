'use client'

/* TradeComposer — The Authentic Classic Roblox Trade Window.
   Two-sided item exchange:
   [ Your Offer (Giving) ]  <== [ PROFIT / WIN-LOSS ] ==>  [ Their Offer (Receiving) ]
   Below: full inventory cards with clean catalog styling to pick from.
   Strictly NO emojis. Clean retro aesthetic. */

import { Suspense, useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import dynamic from 'next/dynamic'
import { useRouter, useSearchParams } from 'next/navigation'
import { api, useRetro } from '@/lib/store'
import { Avatar } from './Shell'
import { FxText } from '@/lib/textfx'
import { UGC_TYPE_LABELS } from '@/lib/avatarAssets'

const ItemThumb3D = dynamic(() => import('./ItemThumb3D'), { ssr: false })

export interface ShelfEntry {
  id: string
  name: string
  type: string
  imageFileId: string
  modelFileId?: string | null
  isLimited: boolean
  isSuperLimited?: boolean
  price: number
  stock: number | null
  serial: number | null
}

const tixShort = (n: number) => n.toLocaleString('en-US')

function TypeFilter({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <select
      className="rb-input"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      style={{ fontSize: 11, height: 26, width: 'auto', minWidth: 130 }}
      aria-label="Filter by type"
    >
      <option value="">All types</option>
      {Object.entries(UGC_TYPE_LABELS).map(([k, v]) => (
        <option key={k} value={k}>{v}</option>
      ))}
    </select>
  )
}

export function TradeComposer() {
  return (
    <Suspense fallback={<div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Opening trade window...</div>}>
      <TradeComposerInner />
    </Suspense>
  )
}

function TradeComposerInner() {
  const { user } = useRetro()
  const router = useRouter()
  const params = useSearchParams()
  const withParam = params.get('with') || ''
  const itemParam = params.get('item') || ''
  const giveParam = params.get('give') || ''
  const counterParam = params.get('counter') || ''

  const [target, setTarget] = useState<{ id: string; username: string } | null>(null)
  const [theirShelf, setTheirShelf] = useState<ShelfEntry[]>([])
  const [myShelf, setMyShelf] = useState<ShelfEntry[]>([])
  const [want, setWant] = useState<Set<string>>(new Set())
  const [give, setGive] = useState<Set<string>>(new Set())
  const [tix, setTix] = useState('')
  const [msg, setMsg] = useState('')
  const [showNote, setShowNote] = useState(false)
  const [fullWidth, setFullWidth] = useState(false)
  const [invTab, setInvTab] = useState<'mine' | 'theirs'>('theirs')
  const [typeFilter, setTypeFilter] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [itemData, setItemData] = useState<{ id: string; name: string; buyPrice: number; isLimited: boolean; remaining: number | null; owned: boolean } | null>(null)
  const [pickerQ, setPickerQ] = useState('')
  const [pickerResults, setPickerResults] = useState<{ id: string; username: string; playerNo: number }[]>([])
  const [pickerBusy, setPickerBusy] = useState(false)

  // Toggle global sidebar visibility via body class
  useEffect(() => {
    if (fullWidth) {
      document.body.classList.add('hide-sidebar')
    } else {
      document.body.classList.remove('hide-sidebar')
    }
    return () => {
      document.body.classList.remove('hide-sidebar')
    }
  }, [fullWidth])

  useEffect(() => {
    let dead = false
    async function resolve() {
      setLoading(true)
      setError('')
      try {
        let t: { id: string; username: string } | null = null
        let it: { id: string; name: string; buyPrice: number; isLimited: boolean; remaining: number | null; owned: boolean } | null = null
        if (counterParam) {
          const res = await api<{ trade: any }>(`/api/trades/${counterParam}`)
          const tr = res.trade
          if (tr) {
            t = { id: tr.from.id, username: tr.from.username }
            const shelf = await api<{ inventory: ShelfEntry[] }>(`/api/users/${t.id}`)
            if (!dead) {
              setTheirShelf(shelf.inventory || [])
              setWant(new Set(tr.give || []))
              setGive(new Set(tr.take || []))
              setMsg(`Counter offer for trade #${counterParam.slice(-6)}`)
            }
          }
        } else if (withParam) {
          const res = await api<{ user: { id: string; username: string } }>(`/api/users/${withParam}`)
          t = { id: res.user.id, username: res.user.username }
        } else if (itemParam || giveParam) {
          const res = await api<{ item: { id: string; name: string; buyPrice: number; isLimited: boolean; remaining: number | null }; owned: boolean; tradeTarget: { id: string; username: string } | null }>(`/api/catalog/${itemParam || giveParam}`)
          it = {
            id: res.item.id,
            name: res.item.name,
            buyPrice: res.item.buyPrice,
            isLimited: res.item.isLimited,
            remaining: res.item.remaining,
            owned: res.owned,
          }
          if (itemParam) t = res.tradeTarget
        }
        if (dead) return
        setTarget(t)
        setItemData(it)
        if (t && !giveParam) {
          const shelf = await api<{ inventory: ShelfEntry[] }>(`/api/users/${t.id}`)
          if (dead) return
          setTheirShelf(shelf.inventory || [])
          if (itemParam && shelf.inventory.some((e) => e.id === itemParam)) {
            setWant(new Set([itemParam]))
          }
        }
      } catch (e) {
        if (!dead) setError(e instanceof Error ? e.message : 'Could not open that trade.')
      } finally {
        if (!dead) setLoading(false)
      }
    }
    resolve()
    return () => { dead = true }
  }, [withParam, itemParam, giveParam, counterParam])

  useEffect(() => {
    if (!user?.id) return
    let dead = false
    api<{ inventory: ShelfEntry[] }>(`/api/users/${user.id}`)
      .then((res) => {
        if (dead) return
        const inv = res.inventory || []
        setMyShelf(inv)
        if (giveParam && inv.some((e) => e.id === giveParam)) {
          setGive((g) => (g.size > 0 ? g : new Set([giveParam])))
        }
      })
      .catch(() => {})
    return () => { dead = true }
  }, [user?.id, giveParam])

  // give-mode recipient search
  useEffect(() => {
    if (!giveParam) return
    const q = pickerQ.trim()
    if (!q) {
      setPickerResults([])
      return
    }
    const t = setTimeout(async () => {
      setPickerBusy(true)
      try {
        const res = await api<{ results: { id: string; username: string; playerNo: number }[] }>(`/api/users/similar?q=${encodeURIComponent(q)}`)
        setPickerResults(res.results || [])
      } catch {
        setPickerResults([])
      } finally {
        setPickerBusy(false)
      }
    }, 200)
    return () => clearTimeout(t)
  }, [pickerQ, giveParam])

  const tixNum = Math.max(0, Math.floor(Number(tix) || 0))
  const giveValue = useMemo(() => {
    return [...give].reduce((sum, id) => {
      const e = myShelf.find((x) => x.id === id)
      return sum + (e?.price || 0)
    }, 0)
  }, [give, myShelf])

  const wantValue = useMemo(() => {
    return [...want].reduce((sum, id) => {
      const e = theirShelf.find((x) => x.id === id)
      return sum + (e?.price || 0)
    }, 0)
  }, [want, theirShelf])

  const totalMyValue = giveValue + tixNum
  const totalTheirValue = wantValue
  const profitLoss = totalTheirValue - totalMyValue

  const canSend = (give.size > 0 || want.size > 0 || tixNum > 0) && !!target

  const toggle = (set: Set<string>, setFn: React.Dispatch<React.SetStateAction<Set<string>>>, max = 8) => (id: string) => {
    setFn((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else if (next.size < max) next.add(id)
      return next
    })
  }

  async function makeOffer() {
    if (!target || !canSend) return
    setError('')
    setBusy(true)
    try {
      if (counterParam) {
        const res = await api<{ ok: boolean; newTradeId?: string; tradeId?: string }>(`/api/trades/${counterParam}`, {
          method: 'POST',
          body: JSON.stringify({
            action: 'counter',
            giveItemIds: [...give],
            takeItemIds: [...want],
            tix: tixNum,
            message: msg.trim() || undefined,
          }),
        })
        router.push(`/trades/${res.newTradeId || res.tradeId || counterParam}`)
        return
      }

      const res = await api<{ ok?: boolean; tradeId?: string; trade?: { id: string } }>('/api/trades', {
        method: 'POST',
        body: JSON.stringify({
          toUserId: target.id,
          giveItemIds: [...give],
          takeItemIds: [...want],
          tix: tixNum,
          message: msg.trim() || undefined,
        }),
      })

      const finalId = res.tradeId || res.trade?.id
      if (finalId) {
        router.push(`/trades/${finalId}`)
      } else {
        router.push('/trades')
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The trade could not be sent.')
      setBusy(false)
    }
  }

  if (loading) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Opening trade window...</div>
  }

  if (!user) {
    return (
      <div className="rb-box" style={{ padding: 30, textAlign: 'center', display: 'grid', gap: 10, justifyItems: 'center' }}>
        <div style={{ fontSize: 13, fontWeight: 'bold' }}>Log in to trade with other players.</div>
        <Link href="/login" className="rb-btn rb-btn-green" style={{ textDecoration: 'none', fontSize: 12, padding: '7px 18px' }}>Log in</Link>
      </div>
    )
  }

  if (error && !target) {
    return (
      <div className="rb-box" style={{ padding: 30, textAlign: 'center', display: 'grid', gap: 10, justifyItems: 'center' }}>
        <div style={{ fontSize: 13, fontWeight: 'bold', color: '#a81a13' }}>{error}</div>
        <Link href="/catalog" className="rb-btn" style={{ textDecoration: 'none', fontSize: 12 }}>Back to Catalog</Link>
      </div>
    )
  }

  if (!target && !giveParam) {
    return (
      <div className="rb-box" style={{ padding: 30, textAlign: 'center', fontSize: 13, color: '#5a6b7b' }}>
        Select a player or a catalog item to initiate a trade.
      </div>
    )
  }

  const activeShelf = invTab === 'theirs' ? theirShelf : myShelf
  const filteredActiveShelf = typeFilter ? activeShelf.filter((e) => e.type === typeFilter) : activeShelf

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      <style>{`
        body.hide-sidebar .rb-sidebar { display: none !important; }
        body.hide-sidebar .rb-main { max-width: 100% !important; width: 100% !important; }
      `}</style>

      {/* Top Bar */}
      <div className="rb-box" style={{ padding: '8px 12px', display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <Link href="/trades" className="rb-link" style={{ fontSize: 11.5 }}>
          [Back to Trades]
        </Link>
        <div style={{ fontSize: 14, fontWeight: 'bold', color: '#1c2733' }}>
          {giveParam ? (
            <>Give Item to Player</>
          ) : (
            <>Trading with {target?.username || 'Player'}</>
          )}
        </div>
        {target && (
          <Link href={`/users/${target.id}`} className="rb-link" style={{ fontSize: 11 }}>
            [View Profile]
          </Link>
        )}
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 8 }}>
          <button
            type="button"
            className="rb-btn"
            style={{ fontSize: 10 }}
            onClick={() => setFullWidth((w) => !w)}
            title="Toggle the left sidebar to expand trade window"
          >
            {fullWidth ? '[Show Sidebar]' : '[Hide Sidebar / Expand]'}
          </button>
          <button
            type="button"
            className="rb-btn"
            style={{ fontSize: 10 }}
            onClick={() => setShowNote((n) => !n)}
          >
            {showNote ? '[Hide Note]' : '[Add Note / Chat]'}
          </button>
        </div>
      </div>

      {error && (
        <div className="rb-box" style={{ padding: 10, color: '#a81a13', fontSize: 12, background: '#fdf3f2', border: '1px solid #eecbc9' }}>
          {error}
        </div>
      )}

      {/* Optional Note / Message input */}
      {showNote && (
        <div className="rb-box" style={{ padding: 10, background: '#f8fafc' }}>
          <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 4 }}>Trade Note:</div>
          <textarea
            className="rb-input"
            value={msg}
            onChange={(e) => setMsg(e.target.value)}
            rows={2}
            maxLength={300}
            placeholder="Type a message or note for this trade offer..."
            style={{ width: '100%', fontSize: 12 }}
          />
        </div>
      )}

      {/* ========================================================
          THE CLASSIC ROBLOX TRADE EXCHANGE (2 SIDES + MIDDLE VALUE)
         ======================================================== */}
      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(280px, 1fr) auto minmax(280px, 1fr)', gap: 10, alignItems: 'stretch' }}>

        {/* LEFT: YOUR OFFER (GIVING) */}
        <div className="rb-box" style={{ padding: 10, display: 'flex', flexDirection: 'column' }}>
          <div className="rb-panel-head" style={{ margin: '-10px -10px 10px -10px' }}>
            <span>Your Offer (You Give)</span>
            <span style={{ fontSize: 10, color: '#2c6e31' }}>{give.size}/8 items</span>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6, minHeight: 140, marginBottom: 8 }}>
            {[0, 1, 2, 3, 4, 5, 6, 7].map((idx) => {
              const id = [...give][idx]
              const it = id ? myShelf.find((x) => x.id === id) : null
              return (
                <div
                  key={idx}
                  style={{
                    border: it ? '1px solid #029a4a' : '1px dashed #c9d6e2',
                    background: it ? '#f4faf5' : '#fafbfc',
                    aspectRatio: '1',
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    padding: 4,
                    position: 'relative',
                    overflow: 'hidden',
                  }}
                >
                  {it ? (
                    <>
                      <button
                        type="button"
                        onClick={() => toggle(give, setGive)(it.id)}
                        title="Remove from trade"
                        style={{
                          position: 'absolute', top: 2, right: 2, zIndex: 5,
                          background: '#c81c14', color: '#fff', border: 'none',
                          borderRadius: 2, width: 16, height: 16, fontSize: 10,
                          cursor: 'pointer', lineHeight: '16px', textAlign: 'center', padding: 0,
                        }}
                      >
                        X
                      </button>
                      <div style={{ width: '100%', flex: 1, position: 'relative' }}>
                        {it.modelFileId ? (
                          <ItemThumb3D
                            modelUrl={`/api/files/${it.modelFileId}`}
                            alt={it.name}
                            fallbackSrc={`/api/files/${it.imageFileId}`}
                            style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                          />
                        ) : (
                          <img
                            src={`/api/files/${it.imageFileId}`}
                            alt={it.name}
                            style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                          />
                        )}
                      </div>
                      <div style={{ fontSize: 9, fontWeight: 'bold', color: '#1c2733', width: '100%', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textAlign: 'center' }}>
                        {it.name}
                      </div>
                      <div style={{ fontSize: 8.5, color: '#5a6b7b', fontFamily: 'monospace' }}>
                        T$ {tixShort(it.price)}
                      </div>
                    </>
                  ) : (
                    <span style={{ fontSize: 10, color: '#cbd5e1' }}>Empty</span>
                  )}
                </div>
              )
            })}
          </div>

          <div style={{ marginTop: 'auto', borderTop: '1px solid #e2e8f0', paddingTop: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
              <span style={{ fontSize: 11, color: '#5a6b7b' }}>Add Tix to offer:</span>
              <input
                className="rb-input"
                type="number"
                min={0}
                placeholder="0"
                value={tix}
                onChange={(e) => setTix(e.target.value.replace(/[^0-9]/g, ''))}
                style={{ width: 80, fontSize: 11, padding: '2px 6px' }}
              />
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, fontWeight: 'bold', color: '#1c2733' }}>
              <span>Total Your Value:</span>
              <span style={{ fontFamily: 'monospace', color: '#2c6e31' }}>T$ {tixShort(totalMyValue)}</span>
            </div>
          </div>
        </div>

        {/* MIDDLE: THE DEAL & PROFIT / LOSS CALCULATION */}
        <div
          className="rb-box"
          style={{
            width: 170,
            padding: 10,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'linear-gradient(180deg, #f8fafc, #edf2f7)',
            textAlign: 'center',
          }}
        >
          <div style={{ fontSize: 10, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 6 }}>
            Trade Difference
          </div>

          {/* Win / Loss Display */}
          <div
            style={{
              padding: '6px 10px',
              borderRadius: 4,
              border: `1px solid ${profitLoss > 0 ? '#029a4a' : profitLoss < 0 ? '#c81c14' : '#084672'}`,
              background: profitLoss > 0 ? '#edfbf1' : profitLoss < 0 ? '#fdf2f2' : '#f0f7fc',
              width: '100%',
              marginBottom: 10,
            }}
          >
            {profitLoss > 0 ? (
              <>
                <div style={{ fontSize: 10, fontWeight: 'bold', color: '#029a4a' }}>PROFIT (WIN)</div>
                <div style={{ fontSize: 15, fontWeight: 'bold', color: '#029a4a', fontFamily: 'monospace' }}>
                  +T$ {tixShort(profitLoss)}
                </div>
              </>
            ) : profitLoss < 0 ? (
              <>
                <div style={{ fontSize: 10, fontWeight: 'bold', color: '#c81c14' }}>LOSS</div>
                <div style={{ fontSize: 15, fontWeight: 'bold', color: '#c81c14', fontFamily: 'monospace' }}>
                  -T$ {tixShort(Math.abs(profitLoss))}
                </div>
              </>
            ) : (
              <>
                <div style={{ fontSize: 10, fontWeight: 'bold', color: '#084672' }}>EQUAL DEAL</div>
                <div style={{ fontSize: 15, fontWeight: 'bold', color: '#084672', fontFamily: 'monospace' }}>
                  T$ 0
                </div>
              </>
            )}
          </div>

          <div style={{ fontSize: 10, color: '#7b8896', marginBottom: 12 }}>
            <div>Give: T$ {tixShort(totalMyValue)}</div>
            <div>Get: T$ {tixShort(totalTheirValue)}</div>
          </div>

          <button
            type="button"
            className="rb-btn rb-btn-green"
            disabled={busy || !canSend}
            onClick={makeOffer}
            style={{ width: '100%', fontSize: 12, padding: '8px 0', fontWeight: 'bold' }}
          >
            {busy ? 'Sending...' : counterParam ? 'Send Counter' : 'Make Offer'}
          </button>
        </div>

        {/* RIGHT: THEIR OFFER (REQUESTING) */}
        <div className="rb-box" style={{ padding: 10, display: 'flex', flexDirection: 'column' }}>
          <div className="rb-panel-head" style={{ margin: '-10px -10px 10px -10px' }}>
            <span>Their Offer (You Receive)</span>
            <span style={{ fontSize: 10, color: '#1c4e7c' }}>{want.size}/8 items</span>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6, minHeight: 140, marginBottom: 8 }}>
            {[0, 1, 2, 3, 4, 5, 6, 7].map((idx) => {
              const id = [...want][idx]
              const it = id ? theirShelf.find((x) => x.id === id) : null
              return (
                <div
                  key={idx}
                  style={{
                    border: it ? '1px solid #0070b6' : '1px dashed #c9d6e2',
                    background: it ? '#f0f7fc' : '#fafbfc',
                    aspectRatio: '1',
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    padding: 4,
                    position: 'relative',
                    overflow: 'hidden',
                  }}
                >
                  {it ? (
                    <>
                      <button
                        type="button"
                        onClick={() => toggle(want, setWant)(it.id)}
                        title="Remove from trade"
                        style={{
                          position: 'absolute', top: 2, right: 2, zIndex: 5,
                          background: '#c81c14', color: '#fff', border: 'none',
                          borderRadius: 2, width: 16, height: 16, fontSize: 10,
                          cursor: 'pointer', lineHeight: '16px', textAlign: 'center', padding: 0,
                        }}
                      >
                        X
                      </button>
                      <div style={{ width: '100%', flex: 1, position: 'relative' }}>
                        {it.modelFileId ? (
                          <ItemThumb3D
                            modelUrl={`/api/files/${it.modelFileId}`}
                            alt={it.name}
                            fallbackSrc={`/api/files/${it.imageFileId}`}
                            style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                          />
                        ) : (
                          <img
                            src={`/api/files/${it.imageFileId}`}
                            alt={it.name}
                            style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                          />
                        )}
                      </div>
                      <div style={{ fontSize: 9, fontWeight: 'bold', color: '#1c2733', width: '100%', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textAlign: 'center' }}>
                        {it.name}
                      </div>
                      <div style={{ fontSize: 8.5, color: '#5a6b7b', fontFamily: 'monospace' }}>
                        T$ {tixShort(it.price)}
                      </div>
                    </>
                  ) : (
                    <span style={{ fontSize: 10, color: '#cbd5e1' }}>Empty</span>
                  )}
                </div>
              )
            })}
          </div>

          <div style={{ marginTop: 'auto', borderTop: '1px solid #e2e8f0', paddingTop: 8 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, fontWeight: 'bold', color: '#1c2733' }}>
              <span>Total Request Value:</span>
              <span style={{ fontFamily: 'monospace', color: '#0070b6' }}>T$ {tixShort(totalTheirValue)}</span>
            </div>
          </div>
        </div>
      </div>

      {/* ========================================================
          INVENTORY PICKER — CLEAN CATALOG CARDS (NO TINY BROKEN ICONS)
         ======================================================== */}
      <div className="rb-box" style={{ padding: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', borderBottom: '1px solid #dbe4ec', paddingBottom: 8, marginBottom: 10 }}>
          <div style={{ display: 'flex', gap: 6 }}>
            <button
              type="button"
              className="rb-btn"
              onClick={() => setInvTab('theirs')}
              style={{
                fontSize: 11,
                fontWeight: 'bold',
                ...(invTab === 'theirs' ? { background: '#0070b6', color: '#fff', borderColor: '#005f9c' } : {}),
              }}
            >
              {target?.username || 'Their'}&apos;s Inventory ({theirShelf.length})
            </button>
            <button
              type="button"
              className="rb-btn"
              onClick={() => setInvTab('mine')}
              style={{
                fontSize: 11,
                fontWeight: 'bold',
                ...(invTab === 'mine' ? { background: '#029a4a', color: '#fff', borderColor: '#028540' } : {}),
              }}
            >
              Your Inventory ({myShelf.length})
            </button>
          </div>

          <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: 11, color: '#5a6b7b' }}>Filter:</span>
            <TypeFilter value={typeFilter} onChange={setTypeFilter} />
          </div>
        </div>

        {filteredActiveShelf.length === 0 ? (
          <div style={{ padding: 30, textAlign: 'center', color: '#7b8896', fontStyle: 'italic', fontSize: 12 }}>
            No items in this inventory view.
          </div>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(130px, 1fr))', gap: 10 }}>
            {filteredActiveShelf.map((item) => {
              const isSelected = invTab === 'theirs' ? want.has(item.id) : give.has(item.id)
              const toggleFn = invTab === 'theirs' ? toggle(want, setWant) : toggle(give, setGive)
              return (
                <div
                  key={item.id}
                  className="rb-box"
                  style={{
                    padding: 8,
                    textAlign: 'center',
                    border: isSelected ? `2px solid ${invTab === 'theirs' ? '#0070b6' : '#029a4a'}` : '1px solid #dbe4ec',
                    background: isSelected ? (invTab === 'theirs' ? '#f0f7fc' : '#f0fbf4') : '#fff',
                    display: 'flex',
                    flexDirection: 'column',
                    position: 'relative',
                  }}
                >
                  <div style={{ width: '100%', aspectRatio: '1', position: 'relative', background: '#fff', border: '1px solid #eef2f6', marginBottom: 6 }}>
                    {item.modelFileId ? (
                      <ItemThumb3D
                        modelUrl={`/api/files/${item.modelFileId}`}
                        alt={item.name}
                        fallbackSrc={`/api/files/${item.imageFileId}`}
                        style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                      />
                    ) : (
                      <img
                        src={`/api/files/${item.imageFileId}`}
                        alt={item.name}
                        style={{ width: '100%', height: '100%', objectFit: 'contain' }}
                      />
                    )}

                    {item.isSuperLimited ? (
                      <span style={{ position: 'absolute', bottom: 2, left: 2, fontSize: 8, padding: '1px 4px', background: '#9b51e0', color: '#fff', fontWeight: 'bold', borderRadius: 2 }}>
                        SUPER
                      </span>
                    ) : item.isLimited ? (
                      <span style={{ position: 'absolute', bottom: 2, left: 2, fontSize: 8, padding: '1px 4px', background: '#2c6e31', color: '#fff', fontWeight: 'bold', borderRadius: 2 }}>
                        LIMITED
                      </span>
                    ) : null}
                  </div>

                  <div style={{ fontSize: 11, fontWeight: 'bold', color: '#1c2733', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginBottom: 2 }}>
                    <FxText text={item.name} />
                  </div>

                  <div style={{ fontSize: 10, color: '#5a6b7b', fontFamily: 'monospace', marginBottom: 6 }}>
                    {item.price > 0 ? `T$ ${tixShort(item.price)}` : 'free'}
                  </div>

                  <button
                    type="button"
                    onClick={() => toggleFn(item.id)}
                    className={`rb-btn ${isSelected ? '' : 'rb-btn-green'}`}
                    style={{ fontSize: 10, padding: '3px 6px', marginTop: 'auto' }}
                  >
                    {isSelected ? '[Remove]' : '[+ Add to Offer]'}
                  </button>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
