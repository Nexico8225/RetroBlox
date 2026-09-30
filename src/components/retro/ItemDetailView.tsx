'use client'

/* ================= Item detail page (/catalog/[id]) =================
   The classic "click an item and land on its page" flow, Roblox-style
   but BETTER: the item wears itself on a live blockhead you can spin,
   limiteds show Original Price + Quantity Left + a price chart of the
   DOUBLING ladder (pay 1,000 -> next buyer pays 2,000 -> 4,000...),
   and the real sales ledger lists who bought, when and for how much. */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import dynamic from 'next/dynamic'
import { useRetro, api, flash, refreshBalance, attachUpload } from '@/lib/store'
import { Avatar } from './Shell'
import { MarketPanel, MarketHistoryChart, TradeOfferModal, type MarketData } from './MarketPanel'
import {
  UGC_TYPE_LABELS,
  DEFAULT_AVATAR,
  buildPreviewParts,
  resolveDefaultAsset,
  ANIM_SLOTS,
  type AnimClipsT,
  type AnimTargetT,
  type Placement,
} from '@/lib/avatarAssets'
import type { AvatarLook3D } from '@/lib/three/rig'

const Player3DView = dynamic(() => import('./Player3DView'), { ssr: false })

interface SaleRow {
  username: string
  userId: string
  avatarUrl: string | null
  at: string
  paid: number
}

interface DetailItem {
  id: string
  assetId: string
  name: string
  description: string
  type: string
  price: number
  isLimited: boolean
  stock: number | null
  sold: number
  remaining: number | null
  ownersBoost: number
  owners: number
  buyPrice: number
  imageFileId: string
  modelFileId: string | null
  textureFileId: string | null
  baseColor: string | null
  placement: Placement | null
  animClips: AnimClipsT | null
  animTarget: AnimTargetT | null
  bundleParts: string[] | null
  hasRig: boolean
  creator: { id: string; username: string; avatarUrl: string | null }
  group: { id: string; name: string } | null
  createdAt: string
}

interface DetailData {
  item: DetailItem
  owned: boolean
  market: MarketData
  priceLadder: { soldAfter: number; price: number }[] | null
  sales: SaleRow[]
  canDelete: boolean
}

/** compact Tix formatting for chart labels (1,234 / 12.5K / 4M) */
function fmtTix(n: number): string {
  if (n >= 1_000_000) {
    const m = n / 1_000_000
    return `${m >= 10 ? Math.round(m) : Math.round(m * 10) / 10}M`
  }
  if (n >= 10_000) {
    const k = n / 1_000
    return `${k >= 10 ? Math.round(k) : Math.round(k * 10) / 10}K`
  }
  return n.toLocaleString('en-US')
}

function fmtDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
  } catch {
    return iso
  }
}

/* ---------------- the doubling price chart ----------------
   A step chart of the ladder: copies sold on X, price on Y.
   Doubling is explosive, so the axis is dropped — every step prints
   its own T$ label (the labels ARE the scale), NOW marks where the
   sales stand and NEXT marks the price the next buyer pays. */
function PriceChart({ ladder, sold }: { ladder: { soldAfter: number; price: number }[]; sold: number }) {
  const W = 620
  const H = 230
  const L = 40
  const R = 40
  const T = 46
  const B = 52
  const n = ladder.length
  const x = (k: number) => L + (k * (W - L - R)) / Math.max(1, n - 1)
  // sqrt scale keeps every step visible even at 1000x; labels carry exact values
  const maxP = Math.max(...ladder.map((p) => p.price), 1)
  const y = (p: number) => B - (Math.sqrt(p / maxP) * (B - T))

  const pts = ladder.map((p) => ({ k: p.soldAfter, price: p.price }))
  let d = ''
  pts.forEach((p, i) => {
    d += `${i === 0 ? 'M' : 'L'} ${x(p.k).toFixed(1)} ${y(p.price).toFixed(1)} `
    if (i < pts.length - 1) d += `L ${x(pts[i + 1].k).toFixed(1)} ${y(p.price).toFixed(1)} `
  })

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto', display: 'block' }} role="img" aria-label="Price chart — the price doubles with every copy sold">
      {/* baseline */}
      <line x1={L} y1={B} x2={W - R} y2={B} stroke="#d4dce4" strokeWidth={1.5} />
      {/* the ladder itself */}
      <path d={d} fill="none" stroke="#0d69ac" strokeWidth={2.5} strokeLinejoin="round" />
      {pts.map((p) => {
        const isNow = p.k === sold
        const isNext = p.k === sold + 1
        const labelY = y(p.price) - 12
        return (
          <g key={p.k}>
            {/* drop line from the dot to the baseline */}
            <line x1={x(p.k)} y1={y(p.price)} x2={x(p.k)} y2={B} stroke="#e2e9f0" strokeWidth={1} strokeDasharray="3 3" />
            <circle cx={x(p.k)} cy={y(p.price)} r={isNow ? 5.5 : 3.5} fill={isNow ? '#2c8e31' : isNext ? '#8a6d1a' : '#0d69ac'} stroke={isNow ? '#b7e6bb' : '#fff'} strokeWidth={isNow ? 2.5 : 1.5} />
            <text x={x(p.k)} y={labelY} textAnchor="middle" fontSize={11} fontWeight={isNow || isNext ? 'bold' : 'normal'} fill={isNow ? '#2c8e31' : isNext ? '#8a6d1a' : '#1c4e7c'} fontFamily="monospace">
              {fmtTix(p.price)}
            </text>
            {isNow && (
              <text x={x(p.k)} y={B + 14} textAnchor="middle" fontSize={9} fontWeight="bold" fill="#2c8e31">
                NOW
              </text>
            )}
            {isNext && (
              <text x={x(p.k)} y={B + 14} textAnchor="middle" fontSize={9} fontWeight="bold" fill="#8a6d1a">
                NEXT
              </text>
            )}
            {!isNow && !isNext && p.k % 2 === 0 && (
              <text x={x(p.k)} y={B + 14} textAnchor="middle" fontSize={9} fill="#7b8896">
                {p.k} sold
              </text>
            )}
            {!isNow && !isNext && p.k % 2 === 1 && (
              <text x={x(p.k)} y={B + 26} textAnchor="middle" fontSize={9} fill="#7b8896">
                {p.k} sold
              </text>
            )}
          </g>
        )
      })}
      <text x={W - R} y={B + 40} textAnchor="end" fontSize={10} fill="#7b8896">
        copies sold →
      </text>
    </svg>
  )
}

/* ---------------- the page ---------------- */
export function ItemDetailView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const [data, setData] = useState<DetailData | null>(null)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  // emotes: which clip the preview performs
  const [clip, setClip] = useState('')
  const [reload, setReload] = useState(0)
  const [tradeOpen, setTradeOpen] = useState(false)
  // owner thumbnail editor (the picture everyone sees on catalog cards)
  const [thumbOpen, setThumbOpen] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api<DetailData>(`/api/catalog/${id}`)
      setData(res)
      setErr('')
      setClip((c) => c || (res.item.animClips?.clips?.[0] ?? ''))
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'This item could not be loaded.')
    }
  }, [id])

  useEffect(() => { load() }, [load, reload])

  const item = data?.item

  /** creator / admin can retouch this item's listing picture */
  const isOwner = !!user && !!item && (user.id === item.creator.id || user.role === 'admin')

  /** the default blockhead wearing THIS item — the try-on lives on the page now */
  const look: AvatarLook3D | null = useMemo(() => {
    if (!item) return null
    const base = buildPreviewParts(DEFAULT_AVATAR, (aid) => resolveDefaultAsset(aid))
    const l: AvatarLook3D = {
      skin: base.skin,
      shirtColor: base.shirtColor,
      shirtImage: base.shirtImage || null,
      pantsColor: base.pantsColor,
      pantsImage: base.pantsImage || null,
      faceUrl: base.faceUrl,
      tshirtUrls: [],
      models: [],
    }
    const f = (fid: string) => `/api/files/${fid}`
    if (item.type === 'tshirt') l.tshirtUrls = [f(item.imageFileId)]
    else if (item.type === 'shirt') l.shirtImage = f(item.imageFileId)
    else if (item.type === 'pants') l.pantsImage = f(item.imageFileId)
    else if (item.type === 'face') l.faceUrl = f(item.imageFileId)
    else if (item.type === 'bundle' && item.modelFileId) l.bundle = { url: f(item.modelFileId) }
    else if (item.modelFileId)
      l.models = [{
        url: f(item.modelFileId),
        imageUrl: f(item.imageFileId),
        placement: item.placement,
        textureUrl: item.textureFileId ? f(item.textureFileId) : undefined,
        color: item.baseColor || undefined,
      }]
    else l.models = [{ url: '', imageUrl: f(item.imageFileId), placement: null }]
    return l
  }, [item])

  /** emote: loop the chosen clip; anim pack: run its mapped move sequence */
  const anim = useMemo(() => {
    if (!item || !item.modelFileId) return null
    const clips = item.animClips?.clips || []
    if (clips.length === 0) return null
    if (item.type === 'anim' && item.animClips?.map) {
      const seq = ANIM_SLOTS.map((s) => item.animClips!.map![s]).filter(Boolean) as string[]
      if (seq.length > 0) return { url: `/api/files/${item.modelFileId}`, clips: seq, single: false }
    }
    const pick = clip && clips.includes(clip) ? clip : clips[0]
    return { url: `/api/files/${item.modelFileId}`, clips: [pick], single: true }
  }, [item, clip])

  async function buyOrGet() {
    if (!item || !user) return
    setBusy(true)
    try {
      const res = await api<{ message?: string }>(`/api/catalog/${item.id}`, {
        method: 'POST',
        body: JSON.stringify({ action: item.buyPrice > 0 ? 'buy' : 'get' }),
      })
      flash(setToast, res.message || 'Done!', 3400)
      await refreshBalance()
      setReload((r) => r + 1)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'That did not work.', 3600)
    } finally {
      setBusy(false)
    }
  }

  if (err) {
    return (
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>
        <div style={{ fontSize: 13, fontWeight: 'bold', color: '#a81a13', marginBottom: 8 }}>{err}</div>
        <Link href="/catalog" className="rb-link" style={{ fontSize: 12 }}>Back to the catalog</Link>
      </div>
    )
  }

  if (!data || !item) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading the item...</div>
  }

  const soldOut = item.isLimited && item.remaining === 0
  const clips = item.animClips?.clips || []
  const typeLabel = UGC_TYPE_LABELS[item.type] || item.type
  const createdBy = item.group ? `${item.group.name} (group)` : item.creator.username

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* breadcrumb */}
      <div style={{ fontSize: 11, color: '#5a6b7b', display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
        <Link href="/catalog" className="rb-link">Catalog</Link>
        <span>/</span>
        <Link href={`/catalog?type=${encodeURIComponent(item.type)}`} className="rb-link">{typeLabel}</Link>
        <span>/</span>
        <span style={{ color: '#1c2733', fontWeight: 'bold' }}>{item.name}</span>
      </div>

      {/* main card — preview left, purchase panel right (the classic layout) */}
      <div className="rb-box" style={{ padding: 14 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(280px, 460px) 1fr', gap: 18, alignItems: 'start' }}>
          {/* LEFT: the live try-on */}
          <div>
            <div style={{ background: '#fff', border: '1px solid #dbe4ec', position: 'relative' }}>
              {look && <Player3DView look={look} height={400} anim={anim} />}
            </div>
            {clips.length > 1 && item.type !== 'anim' && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
                <span style={{ fontSize: 11, color: '#1c4e7c', fontWeight: 'bold' }}>Animation:</span>
                {clips.map((c) => (
                  <button
                    key={c}
                    type="button"
                    onClick={() => setClip(c)}
                    aria-pressed={clip === c}
                    style={{
                      fontSize: 10, padding: '3px 10px', cursor: 'pointer',
                      border: clip === c ? '1px solid #0069a8' : '1px solid #b7c6d4',
                      background: clip === c ? '#0085cf' : '#fff', color: clip === c ? '#fff' : '#1c4e7c',
                    }}
                  >
                    {c}
                  </button>
                ))}
              </div>
            )}
            {item.type === 'anim' && (
              <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 8 }}>
                This pack takes over the REAL moves in realtime
                {item.animClips?.map && <> — mapped: {ANIM_SLOTS.map((s) => item.animClips!.map![s]).filter(Boolean).join(' → ')}</>}.

              </div>
            )}
            {item.type === 'bundle' && item.bundleParts && item.bundleParts.length > 0 && (
              <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 8 }}>
                Replaces your: {item.bundleParts.join(', ')} — the classic body steps aside.
              </div>
            )}
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 8, flexWrap: 'wrap' }}>
              <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#9aa7b4' }}>
                {item.assetId} · drag to spin
              </div>
              {isOwner && (
                <button type="button" className="rb-btn" style={{ fontSize: 10, padding: '3px 9px' }} onClick={() => setThumbOpen(true)} title="Swap the picture players see in the catalog">
                  ✎ Change Thumbnail
                </button>
              )}
            </div>
          </div>

          {/* RIGHT: the purchase panel */}
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 24, color: '#1c2733', margin: 0, lineHeight: 1.15 }}>{item.name}</h1>
              {item.isLimited && (
                <span
                  style={{
                    fontSize: 10, fontWeight: 'bold', padding: '3px 9px',
                    background: 'linear-gradient(180deg,#3ec94e,#1f9e33)', color: '#fff',
                    textTransform: 'uppercase', letterSpacing: '0.5px', border: '1px solid #fff',
                    borderRadius: 3, boxShadow: '1px 1px 3px rgba(0,0,0,.25)',
                  }}
                >
                  ★ Limited
                </span>
              )}
              {soldOut && (
                <span style={{ fontSize: 10, fontWeight: 'bold', padding: '3px 9px', background: '#a81a13', color: '#fff', borderRadius: 3 }}>
                  SOLD OUT
                </span>
              )}
            </div>

            {/* creator — users have IDs, the profile carries the full card */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 7, margin: '8px 0 12px' }}>
              <Avatar user={item.creator} size={22} rounded={4} />
              <span style={{ fontSize: 12, color: '#5a6b7b' }}>By</span>
              <Link href={`/users/${item.creator.id}`} className="rb-link" style={{ fontSize: 12, fontWeight: 'bold' }}>
                {createdBy}
              </Link>
              <span style={{ fontSize: 10, fontFamily: 'monospace', color: '#9aa7b4' }} title="Every member has an ID">
                ID: {item.creator.id}
              </span>
            </div>

            {/* PRICE BLOCK */}
            {item.isLimited ? (
              <div style={{ border: '1px solid #e0c98a', background: '#fffdf4', padding: '10px 12px', marginBottom: 12 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
                  <div>
                    <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.5px', color: '#8a6d1a', fontWeight: 'bold' }}>Original Price</div>
                    <div style={{ fontSize: 16, fontFamily: 'monospace', color: '#8a6d1a' }}>T$ {item.price.toLocaleString('en-US')}</div>
                    {item.stock != null && (
                      <div style={{ fontSize: 10, color: '#5d4a0a', marginTop: 2 }}>
                        Quantity Left: <b>{item.remaining}/{item.stock}</b>
                      </div>
                    )}
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.5px', color: '#5a6b7b', fontWeight: 'bold' }}>
                      {soldOut ? 'Final Price' : 'Price to Buy Now'}
                    </div>
                    <div style={{ fontSize: 26, fontFamily: 'monospace', fontWeight: 'bold', color: soldOut ? '#a81a13' : '#1c4e7c', lineHeight: 1.1 }}>
                      T$ {item.buyPrice.toLocaleString('en-US')}
                    </div>
                    {!soldOut && item.sold > 0 && (
                      <div style={{ fontSize: 10, color: '#8a6d1a' }}>
                        Doubles every sale — next buyer pays <b>T$ {(item.buyPrice * 2).toLocaleString('en-US')}</b>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ) : (
              <div style={{ marginBottom: 12 }}>
                <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.5px', color: '#5a6b7b', fontWeight: 'bold' }}>Price</div>
                <div style={{ fontSize: 26, fontFamily: 'monospace', fontWeight: 'bold', color: '#1c4e7c' }}>
                  {item.buyPrice > 0 ? <>T$ {item.buyPrice.toLocaleString('en-US')}</> : <span style={{ color: '#2c6e31' }}>FREE</span>}
                </div>
              </div>
            )}

            {/* owners — buyers are visible, rarity is public */}
            <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 12 }}>
              {item.owners.toLocaleString('en-US')} {item.owners === 1 ? 'member owns' : 'members own'} this
              {item.isLimited && item.stock != null && <> · {item.sold.toLocaleString('en-US')}/{item.stock.toLocaleString('en-US')} copies sold</>}
              {data.market?.mySerial != null && item.isLimited && item.stock != null && (
                <span
                  title="Limited copies carry a permanent serial number — it travels with every trade and resale"
                  style={{ marginLeft: 6, fontSize: 10, fontWeight: 'bold', color: '#8a6d1a', background: '#fffdf4', border: '1px solid #e0c98a', padding: '1px 7px', borderRadius: 3 }}
                >
                  ★ You own copy #{data.market.mySerial}/{item.stock}
                </span>
              )}
            </div>

            {/* ACTIONS */}
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center', marginBottom: 14 }}>
              {data.owned ? (
                <>
                  <Link href="/avatar" className="rb-btn rb-btn-green" style={{ fontSize: 13, padding: '8px 22px', textDecoration: 'none' }}>
                    Wear it now
                  </Link>
                  <span style={{ fontSize: 12, color: '#2c6e31', fontWeight: 'bold' }}>✓ In your inventory</span>
                </>
              ) : soldOut ? (
                <>
                  <button className="rb-btn" style={{ fontSize: 13, padding: '8px 22px' }} disabled>
                    Sold out forever
                  </button>
                  {user && (
                    <button type="button" className="rb-btn" style={{ fontSize: 12, padding: '7px 14px' }} onClick={() => setTradeOpen(true)} title="It sold out — but another player may trade or resell theirs">
                      🔁 Offer a Trade
                    </button>
                  )}
                </>
              ) : !user ? (
                <Link href="/login" className="rb-btn rb-btn-green" style={{ fontSize: 13, padding: '8px 22px', textDecoration: 'none' }}>
                  Log in to {item.buyPrice > 0 ? 'buy' : 'get'} this
                </Link>
              ) : (
                <>
                  <button
                    className={item.buyPrice > 0 ? 'rb-btn rb-btn-green' : 'rb-btn'}
                    style={{ fontSize: 13, padding: '8px 22px', fontWeight: 'bold' }}
                    disabled={busy}
                    onClick={buyOrGet}
                  >
                    {busy ? 'Working...' : item.buyPrice > 0 ? `Buy for T$ ${item.buyPrice.toLocaleString('en-US')}` : 'Get it — free'}
                  </button>
                  {!data.owned && (
                    <button type="button" className="rb-btn" style={{ fontSize: 12, padding: '7px 14px' }} onClick={() => setTradeOpen(true)} title="Offer items from your inventory instead of Tix">
                      🔁 Offer a Trade
                    </button>
                  )}
                </>
              )}
              {user?.role === 'admin' && (
                <span style={{ fontSize: 10, color: '#8ba0b3' }} title="Manage stock, owners boost and the locked price from the catalog card's Edit panel">
                  Admin tools live on the catalog cards
                </span>
              )}
            </div>

            {/* DETAILS table — the classic rows */}
            <div style={{ borderTop: '1px solid #dbe4ec' }}>
              {[
                ['Type', typeLabel],
                ['Category', item.type === 'accessory' ? 'Accessories · Back' : UGC_TYPE_LABELS[item.type] || item.type],
                ['Created', fmtDate(item.createdAt)],
                ['Asset ID', item.assetId],
                ...(item.modelFileId && item.placement ? [['Placement', 'Exactly where its creator left it']] : []),
                ...(item.hasRig ? [['Rig', 'Has a skeleton — usable as a rig for new animations']] : []),
              ].map(([k, v]) => (
                <div key={k} style={{ display: 'grid', gridTemplateColumns: '130px 1fr', gap: 8, padding: '7px 0', borderBottom: '1px solid #e8eef4', fontSize: 12 }}>
                  <div style={{ color: '#5a6b7b' }}>{k}</div>
                  <div style={{ color: '#1c2733', overflowWrap: 'anywhere' }}>{v}</div>
                </div>
              ))}
              <div style={{ padding: '9px 0', fontSize: 12 }}>
                <div style={{ color: '#5a6b7b', marginBottom: 3 }}>Description</div>
                <div style={{ color: '#1c2733', whiteSpace: 'pre-wrap' }}>{item.description || 'No description.'}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* RESALE MARKET — listings, offers, haggle chat, trade offers */}
      {data.market && (
        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head">
            <span>Resale Market — trade it, sell it, haggle for it</span>
          </div>
          <div style={{ padding: 12 }}>
            <MarketPanel
              itemId={item.id}
              itemName={item.name}
              owned={data.owned}
              market={data.market}
              onChanged={() => setReload((r) => r + 1)}
            />
          </div>
        </div>
      )}

      {/* LIMITED: the doubling price chart */}
      {item.isLimited && data.priceLadder && data.priceLadder.length > 1 && (
        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head">
            <span>Price Chart — every sale DOUBLES the next price</span>
          </div>
          <div style={{ padding: 12 }}>
            <PriceChart ladder={data.priceLadder} sold={item.sold} />
            <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 6 }}>
              Copies sold on the X axis, the buyer&apos;s price on the Y. {soldOut
                ? 'Every copy is gone — the chart is history now.'
                : <>The next buyer pays <b>T$ {item.buyPrice.toLocaleString('en-US')}</b>; after that sale the price jumps to <b>T$ {(item.buyPrice * 2).toLocaleString('en-US')}</b>.</>}
            </div>
          </div>
        </div>
      )}

      {/* the REAL market history — actual sale prices over time */}
      {data.market && data.market.history.length >= 2 && (
        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head">
            <span>Market History — what buyers ACTUALLY paid</span>
          </div>
          <div style={{ padding: 12 }}>
            <MarketHistoryChart history={data.market.history} />
            <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 6 }}>
              Every real transaction on this item: creator sales, player resales and trades. The resale market runs at 1.5x — buy low, sell at 1.5x, and the value climbs with every hand-off.
            </div>
          </div>
        </div>
      )}

      {/* the sales ledger — who bought, when, for how much */}
      <div className="rb-box" style={{ padding: 0 }}>
        <div className="rb-panel-head">
          <span>Sales History — {item.owners.toLocaleString('en-US')} {item.owners === 1 ? 'owner' : 'owners'}</span>
        </div>
        <div style={{ padding: 12 }}>
          {data.sales.length === 0 ? (
            <div style={{ fontSize: 12, color: '#5a6b7b' }}>
              No sales yet{item.isLimited ? ' — copy #1 pays the original price. ' : ' — be the first owner! '}
              {user && !data.owned && !soldOut && (
                <button className="rb-link" style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', fontSize: 12 }} onClick={buyOrGet}>
                  {item.buyPrice > 0 ? `Buy it for T$ ${item.buyPrice.toLocaleString('en-US')}.` : 'Grab it for free.'}
                </button>
              )}
            </div>
          ) : (
            <div style={{ display: 'grid', gap: 6 }}>
              {data.sales.map((s, i) => (
                <div key={`${s.userId}-${s.at}`} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 8px', background: '#f6f9fc', border: '1px solid #e8eef4' }}>
                  <span style={{ fontSize: 10, fontFamily: 'monospace', color: '#9aa7b4', width: 44 }}>
                    #{item.sold - i}
                  </span>
                  <Avatar user={s} size={20} rounded={3} />
                  <Link href={`/users/${s.userId}`} className="rb-link" style={{ fontSize: 12, fontWeight: 'bold' }}>
                    {s.username}
                  </Link>
                  {item.isLimited && (
                    <span style={{ fontSize: 11, fontFamily: 'monospace', color: '#8a6d1a' }}>paid T$ {s.paid.toLocaleString('en-US')}</span>
                  )}
                  <span style={{ fontSize: 10, color: '#8ba0b3', marginLeft: 'auto' }}>{fmtDate(s.at)}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* trade-with-creator modal (the "Offer a Trade" button) */}
      {tradeOpen && item && (
        <TradeOfferModal
          itemId={item.id}
          itemName={item.name}
          toUserId={item.creator.id}
          toLabel={item.creator.username}
          onClose={() => setTradeOpen(false)}
          onSent={() => setReload((r) => r + 1)}
        />
      )}
      {/* 3D try-on — the same scene every game renders through the SDK */}
      {thumbOpen && item && (
        <ChangeThumbModal
          item={item}
          onClose={() => setThumbOpen(false)}
          onSaved={() => {
            setThumbOpen(false)
            setReload((r) => r + 1)
          }}
        />
      )}
    </div>
  )
}

/* ---------------- owner: swap the catalog thumbnail ----------------
   The picture on catalog cards / search rows is a separate file from the
   3D model — creators often want a nicer shot than the auto one, so this
   little editor swaps JUST that image without touching the item itself. */
function ChangeThumbModal({
  item,
  onClose,
  onSaved,
}: {
  item: DetailItem
  onClose: () => void
  onSaved: () => void
}) {
  const { setToast } = useRetro()
  const [file, setFile] = useState<File | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  function pick(f: File | null) {
    setFile(f)
    setError('')
    if (!f) {
      setPreview(null)
      return
    }
    const r = new FileReader()
    r.onload = () => setPreview(String(r.result))
    r.readAsDataURL(f)
  }

  async function save() {
    if (!file) {
      setError('Pick a picture first — or just close this if you changed your mind.')
      return
    }
    setBusy(true)
    setError('')
    try {
      const fd = new FormData()
      await attachUpload(fd, 'image', file, file.name || 'thumbnail.png', file.type || 'image/png')
      await api(`/api/catalog/${item.id}`, { method: 'PATCH', body: fd })
      flash(setToast, 'Thumbnail updated — the catalog shows the new look right away!', 3400)
      onSaved()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the new thumbnail.')
      setBusy(false)
    }
  }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 90, background: 'rgba(20,32,44,0.72)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 14,
      }}
      role="dialog"
      aria-modal="true"
      aria-label={`Change the thumbnail of ${item.name}`}
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <div className="rb-box" style={{ width: 'min(440px, 100%)', background: '#fff' }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Change Thumbnail — {item.name}</span>
          <button className="rb-btn" style={{ fontSize: 10, padding: '2px 8px' }} onClick={onClose}>✕</button>
        </div>
        <div style={{ padding: 12 }}>
          <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 3 }}>The picture players see</div>
          <div style={{ fontSize: 10, color: '#5a6b7b', lineHeight: 1.45, marginBottom: 10 }}>
            This is the shot on catalog cards, search rows and your profile shelf.
            {item.modelFileId
              ? ' Your 3D model stays exactly the same — this only swaps the flat picture.'
              : ' Your item itself stays exactly the same — this only swaps the artwork.'}
          </div>

          {/* before / after */}
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', marginBottom: 12 }}>
            <div style={{ textAlign: 'center' }}>
              <div
                style={{
                  width: 84, height: 84, border: '1px solid #b7c6d4', background: '#fff', overflow: 'hidden',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}
              >
                <img src={`/api/files/${item.imageFileId}`} alt="Current thumbnail" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', display: 'block' }} />
              </div>
              <div style={{ fontSize: 9, color: '#7b8896', marginTop: 3 }}>now</div>
            </div>
            <div style={{ fontSize: 16, color: '#9aa7b4' }}>→</div>
            <div style={{ textAlign: 'center' }}>
              <div
                style={{
                  width: 84, height: 84, border: preview ? '1px solid #2c8e31' : '1px dashed #b7c6d4', background: '#fff', overflow: 'hidden',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 9, color: '#8ba0b3', textAlign: 'center', padding: 4,
                }}
              >
                {preview ? (
                  <img src={preview} alt="New thumbnail preview" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', display: 'block' }} />
                ) : (
                  'pick a picture'
                )}
              </div>
              <div style={{ fontSize: 9, color: preview ? '#2c8e31' : '#7b8896', marginTop: 3 }}>new</div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', marginBottom: 8 }}>
            <button type="button" className="rb-btn" style={{ fontSize: 11, padding: '5px 12px' }} disabled={busy} onClick={() => fileRef.current?.click()}>
              {file ? '↺ Choose a different picture' : '📁 Pick a picture (PNG / JPG)'}
            </button>
            {file && !busy && (
              <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }} onClick={() => pick(null)}>
                undo
              </button>
            )}
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              style={{ display: 'none' }}
              onChange={(e) => {
                pick(e.target.files?.[0] || null)
                e.target.value = ''
              }}
            />
          </div>

          {error && (
            <div style={{ fontSize: 10, color: '#a81a13', background: '#fdf3f2', border: '1px solid #eecac7', padding: '6px 9px', marginBottom: 8 }}>
              {error}
            </div>
          )}

          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button type="button" className="rb-btn" style={{ fontSize: 11, padding: '5px 12px' }} disabled={busy} onClick={onClose}>
              {file ? 'Cancel' : 'Close'}
            </button>
            <button type="button" className="rb-btn rb-btn-green" style={{ fontSize: 11, padding: '5px 14px', fontWeight: 'bold' }} disabled={busy || !file} onClick={save}>
              {busy ? 'Saving...' : 'Save New Thumbnail'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
