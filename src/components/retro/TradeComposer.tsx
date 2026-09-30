'use client'

/* ================= Trade composer (/trades/new) =================
   The classic Roblox trade window, rebuilt for RetroBlox:

     ┌──────────────────────────────┬───────────────────┐
     │  THEIR inventory (pick what  │  YOU ARE ASKING FOR│
     │  you want, checkboxes)       │  ...their items    │
     │                              │                    │
     │  YOUR inventory (pick what   │  YOU ARE GIVING    │
     │  you'll hand over)           │  ...your items + Tix│
     └──────────────────────────────┴───────────────────┘
                     [ Make Offer ]

   Opened by the "Trade" button beside any UGC item, or from a
   profile. Works for every item — even FREE ones (a trade never
   looks at the price tag). Sending drops you straight into the
   trade room, where the other player can chat, counter, accept
   or decline. ------------------------------------------------ */

import { Suspense, useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { api, useRetro } from '@/lib/store'
import { Avatar } from './Shell'
import { FxText } from '@/lib/textfx'
import { UGC_TYPE_LABELS } from '@/lib/avatarAssets'

interface ShelfEntry {
  id: string
  name: string
  type: string
  imageFileId: string
  isLimited: boolean
  price: number
  stock: number | null
  serial: number | null
}

const tixShort = (n: number) => n.toLocaleString('en-US')

function ShelfGrid({
  entries,
  picked,
  onToggle,
  accent,
}: {
  entries: ShelfEntry[]
  picked: Set<string>
  onToggle: (id: string) => void
  accent: string
}) {
  if (entries.length === 0) {
    return (
      <div style={{ fontSize: 11, color: '#8ba0b3', padding: '12px 10px', border: '1px dashed #c9d6e2', textAlign: 'center', fontStyle: 'italic' }}>
        nothing here
      </div>
    )
  }
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(92px, 1fr))', gap: 7 }}>
      {entries.map((e) => {
        const on = picked.has(e.id)
        return (
          <button
            key={e.id}
            type="button"
            onClick={() => onToggle(e.id)}
            aria-pressed={on}
            title={`${e.name}${e.serial ? ` · copy #${e.serial}` : ''} — ${on ? 'click to remove' : 'click to pick'}`}
            style={{
              padding: 5, cursor: 'pointer', textAlign: 'center', position: 'relative',
              border: on ? `2px solid ${accent}` : '1px solid #b7c6d4',
              background: on ? '#f2fbf3' : '#fff',
            }}
          >
            {on && (
              <span
                style={{
                  position: 'absolute', top: 2, right: 2, width: 15, height: 15, fontSize: 10, lineHeight: '15px',
                  background: accent, color: '#fff', borderRadius: 2, fontWeight: 'bold',
                }}
                aria-hidden
              >
                ✓
              </span>
            )}
            {e.serial != null && (
              <span
                style={{
                  position: 'absolute', top: 2, left: 2, fontSize: 8, fontWeight: 'bold', color: '#8a6d1a',
                  background: '#fffdf4', border: '1px solid #e0c98a', padding: '0 3px', borderRadius: 2,
                }}
                title={`Limited copy #${e.serial}`}
              >
                ✦#{e.serial}
              </span>
            )}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`/api/files/${e.imageFileId}`} alt={e.name} width={64} height={64} style={{ objectFit: 'cover', display: 'block', margin: '0 auto 3px', border: '1px solid #dbe4ec' }} />
            <span style={{ fontSize: 9, color: '#1c2733', display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              <FxText text={e.name} />
            </span>
            <span style={{ fontSize: 9, color: '#5a6b7b', fontFamily: 'monospace' }}>
              {e.price > 0 ? `T$ ${tixShort(e.price)}` : 'free'}
            </span>
          </button>
        )
      })}
    </div>
  )
}

function TypeFilter({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <select className="rb-input" value={value} onChange={(e) => onChange(e.target.value)} style={{ fontSize: 11, height: 28, width: 'auto', minWidth: 150 }} aria-label="Filter by type">
      <option value="">All types</option>
      {Object.entries(UGC_TYPE_LABELS).map(([k, v]) => (
        <option key={k} value={k}>{v}</option>
      ))}
    </select>
  )
}

export function TradeComposer() {
  return (
    <Suspense fallback={<div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Opening the trade window…</div>}>
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

  const [target, setTarget] = useState<{ id: string; username: string } | null>(null)
  const [theirShelf, setTheirShelf] = useState<ShelfEntry[]>([])
  const [myShelf, setMyShelf] = useState<ShelfEntry[]>([])
  const [want, setWant] = useState<Set<string>>(new Set())
  const [give, setGive] = useState<Set<string>>(new Set())
  const [tix, setTix] = useState('')
  const [msg, setMsg] = useState('')
  const [typeFilterTheirs, setTypeFilterTheirs] = useState('')
  const [typeFilterMine, setTypeFilterMine] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  // resolve WHO we're trading with: ?with=<userId> wins; ?item=<itemId>
  // looks the current owner up on the item's page data
  useEffect(() => {
    let dead = false
    async function resolve() {
      setLoading(true)
      setError('')
      try {
        let t: { id: string; username: string } | null = null
        if (withParam) {
          const res = await api<{ user: { id: string; username: string } }>(`/api/users/${withParam}`)
          t = { id: res.user.id, username: res.user.username }
        } else if (itemParam) {
          const res = await api<{ tradeTarget: { id: string; username: string } | null }>(`/api/catalog/${itemParam}`)
          t = res.tradeTarget
        }
        if (dead) return
        setTarget(t)
        if (t) {
          const shelf = await api<{ inventory: ShelfEntry[] }>(`/api/users/${t.id}`)
          if (dead) return
          setTheirShelf(shelf.inventory || [])
        }
      } catch (e) {
        if (!dead) setError(e instanceof Error ? e.message : 'Could not open that trade.')
      } finally {
        if (!dead) setLoading(false)
      }
    }
    resolve()
    return () => { dead = true }
  }, [withParam, itemParam])

  // my own shelf
  useEffect(() => {
    if (!user?.id) return
    let dead = false
    api<{ inventory: ShelfEntry[] }>(`/api/users/${user.id}`)
      .then((res) => { if (!dead) setMyShelf(res.inventory || []) })
      .catch(() => {})
    return () => { dead = true }
  }, [user?.id])

  const toggle = (set: Set<string>, apply: (n: Set<string>) => void, max: number) => (id: string) => {
    const n = new Set(set)
    if (n.has(id)) n.delete(id)
    else if (n.size < max) n.add(id)
    apply(n)
  }

  const filterShelf = useCallback((shelf: ShelfEntry[], f: string) => (f ? shelf.filter((e) => e.type === f) : shelf), [])

  const wantValue = useMemo(() => {
    let v = 0
    for (const id of want) v += theirShelf.find((e) => e.id === id)?.price ?? 0
    return v
  }, [want, theirShelf])
  const giveValue = useMemo(() => {
    let v = 0
    for (const id of give) v += myShelf.find((e) => e.id === id)?.price ?? 0
    return v
  }, [give, myShelf])

  const tixNum = Math.max(0, Math.floor(Number(tix) || 0))
  const canSend = !!target && !!user && target.id !== user.id && (want.size > 0 || give.size > 0 || tixNum > 0)

  async function makeOffer() {
    if (!target || !canSend) return
    setBusy(true)
    setError('')
    try {
      const res = await api<{ tradeId: string; message?: string }>('/api/trades', {
        method: 'POST',
        body: JSON.stringify({
          toUserId: target.id,
          giveItemIds: [...give],
          takeItemIds: [...want],
          tix: tixNum,
          message: msg.trim() || undefined,
        }),
      })
      router.push(`/trades/${res.tradeId}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The trade could not be sent.')
      setBusy(false)
    }
  }

  if (loading) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Opening the trade window…</div>
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
        <Link href="/catalog" className="rb-btn" style={{ textDecoration: 'none', fontSize: 12 }}>Back to the catalog</Link>
      </div>
    )
  }

  if (!target) {
    return (
      <div className="rb-box" style={{ padding: 30, textAlign: 'center', fontSize: 13, color: '#5a6b7b' }}>
        Nothing to trade yet — open someone&apos;s profile or an item page and press <b>Trade</b>.
      </div>
    )
  }

  if (target.id === user.id) {
    return (
      <div className="rb-box" style={{ padding: 30, textAlign: 'center', fontSize: 13, color: '#5a6b7b', display: 'grid', gap: 10, justifyItems: 'center' }}>
        <div>That&apos;s your own item — you already have it! Check the <b>Trades</b> page for incoming offers instead.</div>
        <Link href="/trades" className="rb-btn" style={{ textDecoration: 'none', fontSize: 12 }}>Open Trades</Link>
      </div>
    )
  }

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      {/* header */}
      <div className="rb-box" style={{ padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <Link href="/trades" className="rb-link" style={{ fontSize: 11.5 }}>← Trades</Link>
        <h1 style={{ fontSize: 20, color: '#1c2733', margin: 0 }}>
          Trade with <FxText text={target.username} />
        </h1>
        <Link href={`/users/${target.id}`} className="rb-link" style={{ fontSize: 11 }}>view profile</Link>
        <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 7 }}>
          <Avatar user={{ username: target.username, avatarUrl: null }} size={30} rounded={5} />
        </span>
      </div>

      {error && (
        <div className="rb-box" style={{ padding: 10, color: '#a81a13', fontSize: 12 }}>{error}</div>
      )}

      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
        {/* ---------- LEFT: the two inventories ---------- */}
        <div style={{ flex: '1 1 420px', display: 'grid', gap: 12, minWidth: 0 }}>
          <div className="rb-box" style={{ padding: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
              <span style={{ fontSize: 12.5, fontWeight: 'bold', color: '#1c4e7c' }}>{target.username}&apos;s Inventory</span>
              <span style={{ fontSize: 10, color: '#8ba0b3' }}>check what you want</span>
              <span style={{ marginLeft: 'auto' }}><TypeFilter value={typeFilterTheirs} onChange={setTypeFilterTheirs} /></span>
            </div>
            <ShelfGrid
              entries={filterShelf(theirShelf, typeFilterTheirs)}
              picked={want}
              onToggle={toggle(want, setWant, 8)}
              accent="#1c4e7c"
            />
          </div>

          <div className="rb-box" style={{ padding: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
              <span style={{ fontSize: 12.5, fontWeight: 'bold', color: '#2c6e31' }}>Your Inventory</span>
              <span style={{ fontSize: 10, color: '#8ba0b3' }}>check what you&apos;ll give</span>
              <span style={{ marginLeft: 'auto' }}><TypeFilter value={typeFilterMine} onChange={setTypeFilterMine} /></span>
            </div>
            <ShelfGrid
              entries={filterShelf(myShelf, typeFilterMine)}
              picked={give}
              onToggle={toggle(give, setGive, 8)}
              accent="#2c8e31"
            />
          </div>
        </div>

        {/* ---------- RIGHT: request / offer panels ---------- */}
        <div style={{ flex: '0 1 300px', display: 'grid', gap: 12, minWidth: 260 }}>
          <div className="rb-box" style={{ padding: 12 }}>
            <div style={{ fontSize: 12.5, fontWeight: 'bold', color: '#1c4e7c', marginBottom: 7 }}>You are asking for</div>
            <PickList ids={[...want]} shelf={theirShelf} emptyText="Nothing yet — check items on the left." />
            <div style={{ borderTop: '1px solid #e8eef4', marginTop: 8, paddingTop: 6, fontSize: 10.5, color: '#5a6b7b', display: 'flex', justifyContent: 'space-between' }}>
              <span>value</span>
              <span style={{ fontFamily: 'monospace' }}>T$ {tixShort(wantValue)}</span>
            </div>
          </div>

          <div className="rb-box" style={{ padding: 12 }}>
            <div style={{ fontSize: 12.5, fontWeight: 'bold', color: '#2c6e31', marginBottom: 7 }}>You are giving</div>
            <PickList ids={[...give]} shelf={myShelf} emptyText="Nothing yet — check items on the left." />
            <label style={{ display: 'block', fontSize: 10.5, color: '#5a6b7b', marginTop: 9, marginBottom: 3 }}>
              Tix you add on top:
            </label>
            <input
              className="rb-input"
              type="number"
              min={0}
              max={1000000}
              placeholder="0 — any amount, e.g. 6000"
              value={tix}
              onChange={(e) => setTix(e.target.value.replace(/[^0-9]/g, ''))}
              style={{ width: '100%', fontSize: 12, height: 28 }}
            />
            <div style={{ borderTop: '1px solid #e8eef4', marginTop: 8, paddingTop: 6, fontSize: 10.5, color: '#5a6b7b', display: 'flex', justifyContent: 'space-between' }}>
              <span>value + Tix</span>
              <span style={{ fontFamily: 'monospace' }}>T$ {tixShort(giveValue + tixNum)}</span>
            </div>
          </div>

          <div className="rb-box" style={{ padding: 12 }}>
            <label style={{ display: 'block', fontSize: 10.5, color: '#5a6b7b', marginBottom: 3 }}>
              Say something with the offer:
            </label>
            <textarea
              className="rb-input"
              value={msg}
              onChange={(e) => setMsg(e.target.value)}
              rows={2}
              maxLength={300}
              placeholder="throw in the Dominus and it's a deal [wiggle]deal?[/wiggle]"
              style={{ fontSize: 12, resize: 'vertical', width: '100%' }}
            />
            <button
              type="button"
              className="rb-btn rb-btn-green"
              disabled={busy || !canSend}
              onClick={makeOffer}
              style={{ width: '100%', marginTop: 9, fontSize: 13, padding: '8px 0', fontWeight: 'bold' }}
              title={canSend ? 'Send it — they can chat, counter, accept or decline' : 'Pick at least one item or some Tix'}
            >
              {busy ? 'Sending…' : 'Make Offer'}
            </button>
            <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 6, lineHeight: 1.5 }}>
              They get a notification instantly. You land in the trade room where you can chat and counter while you wait.
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function PickList({ ids, shelf, emptyText }: { ids: string[]; shelf: ShelfEntry[]; emptyText: string }) {
  if (ids.length === 0) {
    return <div style={{ fontSize: 10.5, color: '#8ba0b3', fontStyle: 'italic' }}>{emptyText}</div>
  }
  return (
    <div style={{ display: 'grid', gap: 4 }}>
      {ids.map((id) => {
        const e = shelf.find((x) => x.id === id)
        return (
          <div key={id} style={{ display: 'flex', alignItems: 'center', gap: 6, background: '#fff', border: '1px solid #dbe4ec', padding: '3px 6px' }}>
            {e ? (
              <>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/api/files/${e.imageFileId}`} alt="" width={26} height={26} style={{ border: '1px solid #dbe4ec', objectFit: 'cover' }} />
                <span style={{ fontSize: 11, fontWeight: 'bold', color: '#1c2733', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  <FxText text={e.name} />
                </span>
                {e.isLimited && <span title="Limited" style={{ color: '#2c8e31', fontWeight: 'bold', fontSize: 10.5 }}>★</span>}
                <span style={{ marginLeft: 'auto', fontSize: 9.5, fontFamily: 'monospace', color: '#5a6b7b' }}>
                  {e.price > 0 ? `T$ ${tixShort(e.price)}` : 'free'}
                </span>
              </>
            ) : (
              <span style={{ fontSize: 10.5, color: '#a81a13' }}>item gone</span>
            )}
          </div>
        )
      })}
    </div>
  )
}
