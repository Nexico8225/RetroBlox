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
import { useRetro, api, flash, refreshBalance } from '@/lib/store'
import { FxText, FxToolbar } from '@/lib/textfx'
import { Avatar } from './Shell'
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
const TradeModal = dynamic(() => import('./TradeModal'), { ssr: false })

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
  roughness: number | null
  metallic: number | null
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
  const [tradeOpen, setTradeOpen] = useState(false)

  // the comment wall under the item
  const [comments, setComments] = useState<{ id: string; text: string; createdAt: string; user: { id: string; username: string; avatarUrl: string | null; seqId: number | null } }[]>([])
  const [commentText, setCommentText] = useState('')
  const [commentBusy, setCommentBusy] = useState(false)
  const commentRef = useRef<HTMLInputElement>(null)

  const loadComments = useCallback(async () => {
    try {
      const res = await api<{ comments: { id: string; text: string; createdAt: string; user: { id: string; username: string; avatarUrl: string | null; seqId: number | null } }[] }>(`/api/catalog/${id}/comments`)
      setComments(res.comments || [])
    } catch { /* the wall is optional */ }
  }, [id])

  useEffect(() => { loadComments() }, [loadComments])

  async function postComment() {
    const text = commentText.trim()
    if (!text || !item) return
    setCommentBusy(true)
    try {
      await api(`/api/catalog/${item.id}/comments`, { method: 'POST', body: JSON.stringify({ text }) })
      setCommentText('')
      await loadComments()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Comment failed.')
    } finally {
      setCommentBusy(false)
    }
  }

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
        roughness: item.roughness,
        metallic: item.metallic,
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
            <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#9aa7b4', marginTop: 8 }}>
              {item.assetId} · drag to spin
            </div>
          </div>

          {/* RIGHT: the purchase panel */}
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 24, color: '#1c2733', margin: 0, lineHeight: 1.15 }}>
              <FxText text={item.name} />
            </h1>
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
              {typeof (item.creator as { seqId?: number | null }).seqId === 'number' && (
                <span
                  style={{ fontSize: 10, fontFamily: 'monospace', color: '#0d69ac', background: '#eaf2fa', border: '1px solid #b7cfe4', padding: '1px 6px', borderRadius: 3 }}
                  title={`Player #${(item.creator as { seqId?: number | null }).seqId} — join order on the site`}
                >
                  #{(item.creator as { seqId?: number | null }).seqId}
                </span>
              )}
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
                <button className="rb-btn" style={{ fontSize: 13, padding: '8px 22px' }} disabled>
                  Sold out forever
                </button>
              ) : !user ? (
                <Link href="/login" className="rb-btn rb-btn-green" style={{ fontSize: 13, padding: '8px 22px', textDecoration: 'none' }}>
                  Log in to {item.buyPrice > 0 ? 'buy' : 'get'} this
                </Link>
              ) : (
                <button
                  className={item.buyPrice > 0 ? 'rb-btn rb-btn-green' : 'rb-btn'}
                  style={{ fontSize: 13, padding: '8px 22px', fontWeight: 'bold' }}
                  disabled={busy}
                  onClick={buyOrGet}
                >
                  {busy ? 'Working...' : item.buyPrice > 0 ? `Buy for T$ ${item.buyPrice.toLocaleString('en-US')}` : 'Get it — free'}
                </button>
              )}
              {user && !data.owned && item.creator.id !== user.id && (
                <button className="rb-btn" style={{ fontSize: 13, padding: '8px 18px' }} onClick={() => setTradeOpen(true)}>
                  ⇄ Trade for this
                </button>
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
                <div style={{ color: '#1c2733', whiteSpace: 'pre-wrap' }}>
                  <FxText text={item.description || 'No description.'} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

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

      {/* the comment wall — the classic item page comments */}
      <div className="rb-box" style={{ padding: 0 }}>
        <div className="rb-panel-head">
          <span>Comments — {comments.length}</span>
        </div>
        <div style={{ padding: 12 }}>
          {user ? (
            <div style={{ marginBottom: 12 }}>
              <div style={{ display: 'flex', gap: 8 }}>
                <input
                  ref={commentRef}
                  className="rb-input"
                  value={commentText}
                  onChange={(e) => setCommentText(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter' && commentText.trim()) postComment() }}
                  placeholder={`Say something about ${item.name}...`}
                  maxLength={500}
                  style={{ flex: 1, fontSize: 12 }}
                  aria-label="Write a comment"
                />
                <button className="rb-btn rb-btn-blue" style={{ fontSize: 11 }} disabled={commentBusy || !commentText.trim()} onClick={postComment}>
                  {commentBusy ? '...' : 'Post'}
                </button>
              </div>
              <FxToolbar taRef={commentRef} value={commentText} onChange={setCommentText} />
            </div>
          ) : (
            <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 12 }}>
              <Link href="/login" className="rb-link">Log in</Link> to comment.
            </div>
          )}
          {comments.length === 0 ? (
            <div style={{ fontSize: 12, color: '#8ba0b3' }}>No comments yet — be the first!</div>
          ) : (
            <div style={{ display: 'grid', gap: 8 }}>
              {comments.map((c) => (
                <div key={c.id} style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                  <Avatar user={c.user} size={28} rounded={4} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, flexWrap: 'wrap' }}>
                      <Link href={`/users/${c.user.id}`} className="rb-link" style={{ fontSize: 12, fontWeight: 'bold' }}>
                        {c.user.username}
                      </Link>
                      {typeof c.user.seqId === 'number' && (
                        <span style={{ fontSize: 9, fontFamily: 'monospace', color: '#0d69ac' }}>#{c.user.seqId}</span>
                      )}
                      <span style={{ fontSize: 10, color: '#9aa7b4' }}>{fmtDate(c.createdAt)}</span>
                    </div>
                    <div style={{ fontSize: 12, color: '#1c2733', overflowWrap: 'anywhere' }}>
                      <FxText text={c.text} />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {tradeOpen && user && item && (
        <TradeModal
          target={{ id: item.id, name: item.name, imageFileId: item.imageFileId }}
          targetOwnerId={item.creator.id}
          onClose={() => setTradeOpen(false)}
          onSent={() => flash(setToast, 'Offer sent — watch the bell!')}
        />
      )}
    </div>
  )
}
