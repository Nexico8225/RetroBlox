'use client'

/* ================= Catalog (/catalog) =================
   Avatar UGC made by the community: hats, faces, back accessories,
   shirts, pants and gear. Items are free or paid in Tix — paid items
   are bought from your server-side wallet (the price the creator set
   is the price you pay, limiteds included), "Get" grabs free items.
   Everything lands in your inventory, the Avatar Editor wears it,
   and games download it by asset id. Owners can edit their own items
   right on the card. */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import dynamic from 'next/dynamic'
import { useRetro, api, flash, refreshBalance, attachUpload } from '@/lib/store'
import { Avatar } from './Shell'
import {
  UGC_TYPES,
  UGC_TYPE_LABELS,
  DEFAULT_AVATAR,
  buildPreviewParts,
  resolveDefaultAsset,
  is3DType,
  isRiggedType,
  ANIM_SLOTS,
  ANIM_SLOT_LABELS,
  type AnimSlot,
  type AnimClipsT,
  type AnimTargetT,
  placementJson,
  type Placement,
} from '@/lib/avatarAssets'
import { MODEL_ACCEPT, fileToGlb, fileToGlbWithCheck, modelTooBig } from '@/lib/three/convert'
import { captureRiggedThumb } from '@/lib/three/animCapture'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import type { AvatarLook3D } from '@/lib/three/rig'

/* 3D pieces load on demand (three.js is heavy and browser-only) */
const PlacementEditor = dynamic(() => import('./PlacementEditor'), { ssr: false })
const Player3DView = dynamic(() => import('./Player3DView'), { ssr: false })
/** live item-only white thumbnail — replaces stale baked shots (blue sky /
 *  player model / gizmo arrows) for every 3D item, no re-upload needed */
const ItemThumb3D = dynamic(() => import('./ItemThumb3D'), { ssr: false })

/* singular label per type for the template link ("Hat template", not "Hats template") */
const TYPE_SINGULAR: Record<string, string> = {
  hat: 'Hat', hair: 'Hair', face: 'Face', tshirt: 'T-Shirt', shirt: 'Shirt', pants: 'Pants',
  gear: 'Gear', accessory: 'Back Accessory', neck: 'Neck Accessory',
  shoulder: 'Shoulder Accessory', front: 'Front Accessory', waist: 'Waist Accessory',
  emote: 'Emote', bundle: 'Bundle', anim: 'Animation Pack',
}

/* A never-blank placeholder for a thumbnail whose image failed to load
   (the "wheres the icon of the ugc" bug): the item type drawn on a soft
   card so the slot ALWAYS shows something meaningful. */
function thumbPlaceholder(type: string): string {
  const label = (type === 'accessory' ? 'BACK' : type || 'UGC').toUpperCase()
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'>`
    + `<rect width='220' height='220' fill='#f2f6fa'/>`
    + `<rect x='10' y='10' width='200' height='200' fill='none' stroke='#d4dce4' stroke-width='3' stroke-dasharray='8 6' rx='12'/>`
    + `<circle cx='110' cy='88' r='34' fill='none' stroke='#b8c6d2' stroke-width='5'/>`
    + `<path d='M60 168 L92 118 L114 142 L134 112 L162 168 Z' fill='#dbe4ec'/>`
    + `<text x='110' y='196' font-family='Verdana,sans-serif' font-size='17' font-weight='bold' fill='#9aa7b4' text-anchor='middle'>${label}</text>`
    + `</svg>`
  return `data:image/svg+xml,${encodeURIComponent(svg)}`
}

/* short placement hint per type — placement is the creator's call, we never move it */
const TYPE_HINTS: Record<string, string> = {
  hat: 'Upload a 3D model (FBX / GLB / OBJ), then place it on the player model in 3D. It renders exactly where you leave it.',
  hair: 'Upload a 3D hairstyle (FBX / GLB / OBJ) and place it on the head in 3D where it belongs.',
  accessory: 'Upload a 3D model — wings, capes, backpacks — and place it on the back in 3D where it belongs.',
  neck: 'Upload a 3D model — scarves, necklaces, collars — and place it around the neck in 3D.',
  shoulder: 'Upload a 3D model — pauldrons, shoulder buddies — and place it on a shoulder in 3D.',
  front: 'Upload a 3D model — badges, chest plates — and place it on the chest in 3D.',
  waist: 'Upload a 3D model — belts, capes ties, pouches — and place it around the waist in 3D.',
  gear: 'Upload a 3D model (FBX / GLB / OBJ) — a tool or prop — and place it in 3D.',
  face: 'The whole box is the face on the front of the head. The default face is the classic Smile.',
  tshirt: 'Just an image — it goes on the FRONT of the torso, exactly where you draw it.',
  shirt: 'A texture that wraps the torso and arms. Paint inside the RIGHT ARM / TORSO / LEFT ARM zones.',
  pants: 'A texture that wraps the legs. Paint inside the RIGHT LEG / LEFT LEG zones.',
  emote: 'A rigged GLB from Blender with an animation inside — the character performs it. Preview it right here before publishing.',
  bundle: 'A rigged body model that REPLACES body parts — import a model with a rig, or animate it too. The parts are detected from their names.',
  anim: 'A rigged GLB whose clips replace the REAL idle / walk / jump / climb / fall — they play in realtime. Map each move to a clip below.',
}

/* the classic BrickColor palette — the same swatches the old color pickers
   gave you (Body Colors, Studio parts). Flat-painting a UGC model should
   feel exactly like painting a part in 2016. */
const BRICK_COLORS: [string, string][] = [
  ['White', '#F2F3F3'],
  ['Medium stone grey', '#A3A2A5'],
  ['Dark stone grey', '#635F62'],
  ['Black', '#1B2A35'],
  ['Bright red', '#C4281C'],
  ['Bright orange', '#DA8541'],
  ['Bright yellow', '#F5CD30'],
  ['Brick yellow', '#D7C59A'],
  ['Nougat', '#CC8E69'],
  ['Reddish brown', '#694028'],
  ['Bright green', '#4B974B'],
  ['Pastel blue', '#80BBDB'],
  ['Bright blue', '#0D69AC'],
  ['Bright violet', '#6B327C'],
  ['Pink', '#FF66CC'],
  ['Cyan', '#04AFEC'],
]

/** the shared swatch row used by publish + edit — one classic palette */
function BrickSwatches({
  value,
  onPick,
  disabled,
}: {
  value?: string
  onPick: (hex: string) => void
  disabled?: boolean
}) {
  return (
    <div
      className="rb-brick-swatches"
      role="group"
      aria-label="Classic BrickColors"
      title={disabled ? 'Remove the texture to paint flat colors' : undefined}
    >
      {BRICK_COLORS.map(([name, hex]) => (
        <button
          key={hex}
          type="button"
          className="rb-brick-swatch"
          title={name}
          aria-label={`Flat color ${name}`}
          disabled={disabled}
          data-on={value && value.toLowerCase() === hex.toLowerCase() ? '1' : '0'}
          style={{ background: hex }}
          onClick={() => onPick(hex)}
        />
      ))}
    </div>
  )
}

/**
 * The upload preview shows ONLY the item — no player model behind it, no
 * template clutter — on white so the art reads exactly like the catalog.
 * (The "how it sits on you" check happens in the Avatar Editor and the 3D
 * try-on; the publish preview is about the art itself.)
 */
const PREVIEW_BG = '#ffffff'

interface CatalogItem {
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
  buyPrice: number // what a buyer pays — limiteds: the RISING price
  imageFileId: string
  modelFileId: string | null
  textureFileId: string | null
  baseColor: string | null
  // PBR material sliders (null = render exactly what the GLB carries)
  metallic: number | null
  roughness: number | null
  placement: Placement | null
  animClips?: AnimClipsT | null
  animTarget?: AnimTargetT | null
  bundleParts?: string[] | null
  hasRig?: boolean
  creator: { id: string; username: string; avatarUrl: string | null }
  group: { id: string; name: string } | null
  createdAt: string
  deletedAt?: string | null
}

interface GroupOpt { id: string; name: string }

export function CatalogView({ initialType = '', initialQ = '' }: { initialType?: string; initialQ?: string }) {
  const { user, setToast } = useRetro()
  const [items, setItems] = useState<CatalogItem[]>([])
  const [ownedIds, setOwnedIds] = useState<string[]>([])
  const [type, setType] = useState(initialType)
  const [q, setQ] = useState(initialQ)
  const [onlyLimited, setOnlyLimited] = useState(false)
  const [loading, setLoading] = useState(true)
  const [showPublish, setShowPublish] = useState(false)
  const [myGroups, setMyGroups] = useState<GroupOpt[]>([])
  const [tryOn, setTryOn] = useState<CatalogItem | null>(null)
  const [editing, setEditing] = useState<CatalogItem | null>(null)
  // admin-only: soft-deleted UGC — deletes are reversible, nothing is ever really gone
  const [deletedItems, setDeletedItems] = useState<CatalogItem[]>([])
  const isAdmin = user?.role === 'admin'

  const loadDeleted = useCallback(async () => {
    if (!isAdmin) { setDeletedItems([]); return }
    try {
      const res = await api<{ items: CatalogItem[] }>('/api/catalog?deleted=1')
      setDeletedItems(res.items)
    } catch { /* ignore */ }
  }, [isAdmin])

  useEffect(() => { loadDeleted() }, [loadDeleted])

  async function restoreItem(item: CatalogItem) {
    try {
      const res = await api<{ message?: string }>(`/api/catalog/${item.id}`, { method: 'POST', body: JSON.stringify({ action: 'restore' }) })
      flash(setToast, res.message || 'Restored!')
      await Promise.all([loadDeleted(), load()])
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Restore failed', 3000)
    }
  }

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params = new URLSearchParams()
      if (type) params.set('type', type)
      if (q.trim()) params.set('q', q.trim())
      if (onlyLimited) params.set('limited', '1')
      const res = await api<{ items: CatalogItem[]; ownedItemIds: string[] }>(`/api/catalog?${params}`)
      setItems(res.items)
      setOwnedIds(res.ownedItemIds)
    } catch { /* ignore */ } finally {
      setLoading(false)
    }
  }, [type, q, onlyLimited])

  useEffect(() => { load() }, [load])

  // group memberships drive both the publish-as-group dropdown and group-owner delete rights
  useEffect(() => {
    if (!user) return
    api<{ groups: GroupOpt[] }>('/api/groups').then((res) => setMyGroups(res.groups)).catch(() => {})
  }, [user])

  async function getItem(item: CatalogItem) {
    const isBuy = item.buyPrice > 0
    try {
      const res = await api<{ message: string; balanceAfter?: number }>(`/api/catalog/${item.id}`, {
        method: 'POST',
        body: JSON.stringify({ action: isBuy ? 'buy' : 'get' }),
      })
      flash(setToast, res.message || (isBuy ? 'Purchased!' : 'Added to your inventory!'))
      setOwnedIds((ids) => [...ids, item.id])
      if (isBuy) refreshBalance()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 3000)
    }
  }

  async function removeItem(item: CatalogItem) {
    if (!window.confirm(`Delete "${item.name}"? It hides from the catalog — an admin can restore it any time.`)) return
    try {
      await api(`/api/catalog/${item.id}`, { method: 'DELETE' })
      flash(setToast, 'UGC deleted — restorable by an admin.')
      load()
      loadDeleted()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

  const canDelete = (item: CatalogItem) =>
    !!user && (user.role === 'admin' || user.id === item.creator.id || (!!item.group && item.group.id && myGroups.some((g) => g.id === item.group!.id)))

  const canManage = (item: CatalogItem) =>
    canDelete(item) // same rule as delete: creator, group owner, or site admin

  return (
    <div>
      {/* hero — human words, not robot words */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Catalog</span></div>
        <div style={{ padding: 14, display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'center' }}>
          <div style={{ flex: 1, minWidth: 220 }}>
            <div style={{ fontSize: 17, color: '#1c2733' }}>Hats, faces and gear made by players</div>
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 4 }}>
              Grab the official template, paint your item, publish it — it lands here with its own asset id.
              Get it, wear it in the <Link href="/avatar" className="rb-link">Avatar Editor</Link>,
              and it follows you into every RetroBlox game.
            </div>
          </div>
          {user && (
            <button className="rb-btn rb-btn-green" onClick={() => setShowPublish(!showPublish)}>
              {showPublish ? 'Close' : '+ Publish UGC'}
            </button>
          )}
        </div>
      </div>

      {showPublish && user && <PublishForm onDone={() => { setShowPublish(false); load() }} groups={myGroups} />}

      {/* search + type tabs */}
      <div className="rb-box" style={{ padding: 10, marginBottom: 12 }}>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
          <input
            className="rb-input"
            placeholder="Search the catalog..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            style={{ flex: 1, minWidth: 160, fontSize: 11 }}
            aria-label="Search catalog"
          />
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 8 }}>
          <button
            key="limiteds"
            type="button"
            onClick={() => setOnlyLimited(!onlyLimited)}
            aria-pressed={onlyLimited}
            style={{
              fontSize: 11,
              padding: '4px 10px',
              cursor: 'pointer',
              fontWeight: 'bold',
              border: onlyLimited ? '1px solid #1f9e33' : '1px solid #b7c6d4',
              background: onlyLimited ? 'linear-gradient(180deg,#3ec94e,#1f9e33)' : '#fff',
              color: onlyLimited ? '#fff' : '#1f9e33',
            }}
          >
            ★ Limiteds
          </button>
          {['', ...UGC_TYPES].map((t) => (
            <button
              key={t || 'all'}
              type="button"
              onClick={() => setType(t)}
              aria-pressed={type === t}
              style={{
                fontSize: 11,
                padding: '4px 10px',
                cursor: 'pointer',
                border: type === t ? '1px solid #0069a8' : '1px solid #b7c6d4',
                background: type === t ? '#0085cf' : '#fff',
                color: type === t ? '#fff' : '#1c4e7c',
              }}
            >
              {t ? UGC_TYPE_LABELS[t] : 'Everything'}
            </button>
          ))}
        </div>
      </div>

      {/* admin-only recycle bin — deleted UGC is restorable, nothing is ever gone for good */}
      {isAdmin && deletedItems.length > 0 && (
        <div className="rb-box" style={{ padding: 10, marginBottom: 12, background: '#fff8e8', borderColor: '#e0c98a' }}>
          <div style={{ fontSize: 11, fontWeight: 'bold', color: '#8a6d1a', marginBottom: 6 }}>
            Deleted UGC ({deletedItems.length}) — restorable, nothing is ever gone for good
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {deletedItems.map((item) => (
              <div key={item.id} style={{ display: 'flex', alignItems: 'center', gap: 6, background: '#fff', border: '1px solid #e0c98a', padding: '3px 8px', borderRadius: 3 }}>
                <span style={{ fontSize: 10, color: '#5d4a0a' }}>
                  {item.name} <span style={{ fontFamily: 'monospace', color: '#9aa7b4' }}>({item.assetId})</span>
                </span>
                <button
                  type="button"
                  className="rb-btn rb-btn-green"
                  style={{ fontSize: 9, padding: '2px 8px' }}
                  onClick={() => restoreItem(item)}
                >
                  ↺ Restore
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* item grid */}
      {loading ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading the catalog...</div>
      ) : items.length === 0 ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b', fontSize: 12 }}>
          Nothing here yet — the catalog is a blank canvas.
          {user && <> Be the first: hit + Publish UGC and give RetroBlox its first hat.</>}
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(205px, 1fr))', gap: 10 }}>
          {items.map((item) => {
            const owned = ownedIds.includes(item.id)
            return (
              <div key={item.id} className="rb-box rb-card" style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{ background: '#ffffff', borderBottom: '1px solid #dbe4ec', position: 'relative' }}>
                  {/* the SAVED thumbnail always paints first — the live 3D render (if any)
                      covers it, and if that render ever fails the saved shot still shows:
                      this slot can never end up blank */}
                  <img
                    src={`/api/files/${item.imageFileId}`}
                    alt={item.name}
                    loading="lazy"
                    onError={(e) => {
                      // dead file id / truncated upload -> draw the type placeholder instead of a white hole
                      const ph = thumbPlaceholder(item.type)
                      if (!e.currentTarget.src.startsWith('data:')) e.currentTarget.src = ph
                    }}
                    style={{ width: '100%', aspectRatio: '1', objectFit: 'cover', display: 'block' }}
                  />
                  {item.modelFileId && (
                    <ItemThumb3D
                      modelUrl={`/api/files/${item.modelFileId}`}
                      placement={item.placement}
                      alt={item.name}
                      fallbackSrc={`/api/files/${item.imageFileId}`}
                      textureUrl={item.textureFileId ? `/api/files/${item.textureFileId}` : undefined}
                      color={item.baseColor || undefined}
                      metallic={item.metallic}
                      roughness={item.roughness}
                      style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', display: 'block', background: '#fff' }}
                    />
                  )}
                  <span
                    style={{
                      position: 'absolute', top: 6, left: 6, fontSize: 9, padding: '2px 6px',
                      background: '#0d69ac', color: '#fff', textTransform: 'uppercase', letterSpacing: '0.5px',
                    }}
                  >
                    {item.type === 'accessory' ? 'back' : item.type}
                  </span>
                  {item.isLimited && (
                    <span
                      title={item.stock != null ? `Limited — only ${item.stock} copies will ever exist` : "Limited — a collectible. When it's gone, it's gone."}
                      style={{
                        position: 'absolute', bottom: 6, left: 6, fontSize: 9, fontWeight: 'bold', padding: '2px 7px',
                        background: 'linear-gradient(180deg,#3ec94e,#1f9e33)', color: '#fff',
                        textTransform: 'uppercase', letterSpacing: '0.5px', border: '1px solid #fff',
                        borderRadius: 3, boxShadow: '1px 1px 3px rgba(0,0,0,.35)',
                      }}
                    >
                      ★ Limited
                    </span>
                  )}
                  {item.isLimited && item.remaining != null && (
                    <span
                      title={`${item.remaining} of ${item.stock} copies left`}
                      style={{
                        position: 'absolute', top: 6, right: 6, fontSize: 9, fontWeight: 'bold', padding: '2px 6px',
                        background: item.remaining === 0 ? '#a81a13' : 'rgba(20,32,44,0.78)', color: '#fff',
                        border: '1px solid #fff', borderRadius: 3,
                      }}
                    >
                      {item.remaining === 0 ? 'SOLD OUT' : `${item.remaining} left`}
                    </span>
                  )}
                  {item.modelFileId && (
                    <button
                      type="button"
                      onClick={() => setTryOn(item)}
                      title="See it on the player model in 3D"
                      style={{
                        position: 'absolute', bottom: 6, right: 6, zIndex: 2, fontSize: 9, padding: '3px 8px',
                        background: '#0d69ac', color: '#fff', border: '1px solid #fff', cursor: 'pointer',
                      }}
                    >
                      Try on in 3D
                    </button>
                  )}
                  {/* the whole artwork clicks through to the item's own page —
                      the try-on button sits above this overlay */}
                  <Link
                    href={`/catalog/${item.id}`}
                    aria-label={`View ${item.name}`}
                    style={{ position: 'absolute', inset: 0, zIndex: 1 }}
                  />
                </div>
                <div style={{ padding: 8 }}>
                  <Link href={`/catalog/${item.id}`} className="rb-link" style={{ display: 'block', fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {item.name}
                  </Link>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 5, margin: '3px 0 6px', fontSize: 10, color: '#5a6b7b' }}>
                    <Avatar user={item.creator} size={14} rounded={3} />
                    <Link href={`/users/${item.creator.id}`} className="rb-link" style={{ fontSize: 10 }}>
                      By {item.group ? item.group.name : item.creator.username}
                    </Link>
                  </div>
                  <div style={{ fontSize: 13, marginBottom: 4, display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'wrap', marginTop: 3 }}>
                    {item.buyPrice > 0 ? (
                      <>
                        {/* the little Tix coin */}
                        <span
                          aria-hidden="true"
                          style={{
                            width: 15, height: 15, borderRadius: '50%', flexShrink: 0,
                            background: 'radial-gradient(circle at 35% 30%, #ffe08a, #f0b429 55%, #8a6d1a)',
                            border: '1px solid #6d5510',
                            color: '#5d4a0a', fontSize: 7, fontWeight: 'bold',
                            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                            fontFamily: 'Verdana, sans-serif',
                          }}
                        >
                          T$
                        </span>
                        <span
                          style={{
                            fontFamily: 'monospace', fontWeight: 'bold',
                            color: item.isLimited ? '#8a6d1a' : '#1c4e7c',
                          }}
                        >
                          {item.buyPrice.toLocaleString('en-US')}
                        </span>
                        {item.isLimited && item.sold > 0 && (
                          <span
                            title="The original price — it rises as copies sell"
                            style={{ fontSize: 9, color: '#9aa7b4', fontFamily: 'monospace' }}
                          >
                            <span style={{ textDecoration: 'line-through' }}>was {item.price.toLocaleString('en-US')}</span>
                          </span>
                        )}
                      </>
                    ) : (
                      <span style={{ color: '#2c6e31', fontWeight: 'bold', fontSize: 10 }}>FREE</span>
                    )}
                  </div>
                  {/* buyers + stock — scarcity is visible at a glance */}
                  {(item.isLimited || item.owners > 0) && (
                    <div style={{ fontSize: 9, color: '#5a6b7b', marginBottom: 4 }}>
                      {item.owners.toLocaleString('en-US')} owned
                      {item.isLimited && item.stock != null && ` · ${item.sold.toLocaleString('en-US')}/${item.stock} sold`}
                    </div>
                  )}
                  <div style={{ fontSize: 9, fontFamily: 'monospace', color: '#9aa7b4', marginBottom: 6 }}>{item.assetId}</div>
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {owned ? (
                      <>
                        <Link href={`/catalog/${item.id}`} className="rb-btn" style={{ fontSize: 10, textDecoration: 'none', padding: '3px 8px' }}>View</Link>
                        <Link href="/avatar" className="rb-btn" style={{ fontSize: 10, textDecoration: 'none', padding: '3px 8px' }}>Wear</Link>
                        <span style={{ fontSize: 10, color: '#3e8e41', alignSelf: 'center' }}>✓ In inventory</span>
                      </>
                    ) : (
                      <button
                        className={item.buyPrice > 0 ? 'rb-btn rb-btn-green' : 'rb-btn'}
                        style={{ fontSize: 10, padding: '3px 8px' }}
                        disabled={item.isLimited && item.remaining === 0}
                        title={item.isLimited && item.remaining === 0 ? 'Every copy of this limited is gone forever' : undefined}
                        onClick={() => getItem(item)}
                      >
                        {item.isLimited && item.remaining === 0
                          ? 'Sold out'
                          : item.buyPrice > 0
                            ? `Buy T$ ${item.buyPrice.toLocaleString('en-US')}`
                            : 'Get'}
                      </button>
                    )}
                    {canManage(item) && (
                      <button className="rb-btn" style={{ fontSize: 10, padding: '3px 8px' }} onClick={() => setEditing(item)}>
                        Edit
                      </button>
                    )}
                    {canDelete(item) && (
                      <button className="rb-btn rb-btn-red" style={{ fontSize: 10, padding: '3px 8px' }} onClick={() => removeItem(item)}>
                        Delete
                      </button>
                    )}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* 3D try-on — the same scene every game renders through the SDK */}
      {tryOn && <TryOnModal item={tryOn} onClose={() => setTryOn(null)} />}

      {/* owner edit — change name / description / price on your own items */}
      {editing && (
        <EditItemModal
          item={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null)
            load()
          }}
        />
      )}
    </div>
  )
}

/* ---------------- 3D try-on modal ---------------- */

function itemLook(item: CatalogItem): AvatarLook3D {
  // the default blockhead wearing just this item — "try it on" like Roblox
  const base = buildPreviewParts(DEFAULT_AVATAR, (id) => resolveDefaultAsset(id))
  const look: AvatarLook3D = {
    skin: base.skin,
    shirtColor: base.shirtColor,
    shirtImage: base.shirtImage || null,
    pantsColor: base.pantsColor,
    pantsImage: base.pantsImage || null,
    faceUrl: base.faceUrl,
    tshirtUrls: [],
    models: [],
  }
  const fileUrl = (id: string) => `/api/files/${id}`
  if (item.type === 'tshirt') look.tshirtUrls = [fileUrl(item.imageFileId)]
  else if (item.type === 'shirt') look.shirtImage = fileUrl(item.imageFileId)
  else if (item.type === 'pants') look.pantsImage = fileUrl(item.imageFileId)
  else if (item.type === 'face') look.faceUrl = fileUrl(item.imageFileId)
  else if (item.type === 'bundle' && item.modelFileId) look.bundle = { url: fileUrl(item.modelFileId) }
  else if (item.modelFileId)
    look.models = [{
      url: fileUrl(item.modelFileId),
      imageUrl: fileUrl(item.imageFileId),
      placement: item.placement,
      textureUrl: item.textureFileId ? fileUrl(item.textureFileId) : undefined,
      color: item.baseColor || undefined,
      animClips: item.type === 'emote' || item.hasRig ? item.animClips?.clips : undefined,
    }]
  else look.models = [{ url: '', imageUrl: fileUrl(item.imageFileId), placement: null }] // legacy image-only accessory
  return look
}

function TryOnModal({ item, onClose }: { item: CatalogItem; onClose: () => void }) {
  const look = useMemo(() => itemLook(item), [item])
  // emotes / anim packs: pick which clip plays on the body
  const clips = item.animClips?.clips || []
  const isAnimPack = item.type === 'anim'
  const [clip, setClip] = useState(clips[0] || '')
  const slotOrder = isAnimPack && item.animClips?.map
    ? ANIM_SLOTS.map((s) => item.animClips!.map![s]).filter(Boolean) as string[]
    : []
  const anim = clips.length > 0 && item.modelFileId
    ? { url: `/api/files/${item.modelFileId}`, clips: isAnimPack ? (slotOrder.length ? slotOrder : clips) : [clip], single: !isAnimPack }
    : null
  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 90, background: 'rgba(20,32,44,0.72)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 14,
      }}
      role="dialog"
      aria-modal="true"
      aria-label={`Try on ${item.name} in 3D`}
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <div className="rb-box" style={{ width: 'min(640px, 100%)', background: '#fff' }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Trying on: {item.name}</span>
          <button className="rb-btn" style={{ fontSize: 10, padding: '2px 8px' }} onClick={onClose}>✕</button>
        </div>
        <div style={{ padding: 12 }}>
          <Player3DView look={look} height={380} anim={anim} />
          {clips.length > 1 && !isAnimPack && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10 }}>
              <span style={{ fontSize: 11, color: '#1c4e7c' }}>Clip:</span>
              <select className="rb-input" value={clip} onChange={(e) => setClip(e.target.value)} style={{ fontSize: 11, flex: 1 }} aria-label="Animation clip">
                {clips.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>
          )}
          {isAnimPack && slotOrder.length > 0 && (
            <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 10 }}>
              Playing the mapped moves in sequence: {slotOrder.join(' → ')} — the pack takes over the classic moves in realtime.
            </div>
          )}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'center', marginTop: 10 }}>
            <div style={{ flex: 1, minWidth: 200 }}>
              <div style={{ fontSize: 12, color: '#1c2733' }}>{item.description || 'No description.'}</div>
              <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#7b8896', marginTop: 2 }}>
                {item.assetId} · drag to spin the camera
              </div>
            </div>
            <Link href="/avatar" className="rb-btn rb-btn-green" style={{ fontSize: 11, textDecoration: 'none' }}>
              Wear it in the Avatar Editor
            </Link>
          </div>
          <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 8 }}>
            {item.type === 'bundle'
              ? 'This bundle replaces the body parts its creator modeled — the classic blocky body steps aside.'
              : item.type === 'emote' || item.type === 'anim'
                ? 'Clips retarget onto the body by part name — animate against the R6 template and it plays right on your character.'
                : 'This is the exact spot its creator left it in — RetroBlox never moves UGC on its own.'}
          </div>
        </div>
      </div>
    </div>
  )
}

/* ---------------- owner edit modal ---------------- */

function EditItemModal({
  item,
  onClose,
  onSaved,
}: {
  item: CatalogItem
  onClose: () => void
  onSaved: () => void
}) {
  const { user, setToast } = useRetro()
  const isAdmin = user?.role === 'admin'
  const [name, setName] = useState(item.name)
  const [description, setDescription] = useState(item.description || '')
  const [priceMode, setPriceMode] = useState<'free' | 'paid'>(item.price > 0 ? 'paid' : 'free')
  const [price, setPrice] = useState(item.price > 0 ? String(item.price) : '')
  const [limited, setLimited] = useState(item.isLimited)
  // limited economy: the print run + the displayed-buyers boost (admin only)
  const [stock, setStock] = useState(item.stock != null ? String(item.stock) : '')
  const [ownersBoost, setOwnersBoost] = useState(item.ownersBoost ? String(item.ownersBoost) : '0')
  const [newImage, setNewImage] = useState<File | null>(null)
  const [newImagePreview, setNewImagePreview] = useState<string | null>(null)
  // 3D items: owner can also swap the texture or repaint the tint color
  const [newTexture, setNewTexture] = useState<File | null>(null)
  const [newTexturePreview, setNewTexturePreview] = useState<string | null>(null)
  const [clearTexture, setClearTexture] = useState(false)
  const [tintOn, setTintOn] = useState(!!item.baseColor)
  const [tint, setTint] = useState(item.baseColor || '#b8663a')
  // PBR material sliders — 'file' = use whatever the GLB carries, 'custom' =
  // the creator's values (applied by the site renderer AND the Godot player)
  const hasPbr = item.metallic != null || item.roughness != null
  const [metMode, setMetMode] = useState<'file' | 'custom'>(hasPbr ? 'custom' : 'file')
  const [rghMode, setRghMode] = useState<'file' | 'custom'>(hasPbr ? 'custom' : 'file')
  const [metVal, setMetVal] = useState(item.metallic ?? 0)
  const [rghVal, setRghVal] = useState(item.roughness ?? 0.85)
  // what the live 3D thumbnail in THIS modal should show right now
  const metPreview = metMode === 'custom' ? metVal : null
  const rghPreview = rghMode === 'custom' ? rghVal : null
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const imageRef = useRef<HTMLInputElement>(null)
  const textureRef = useRef<HTMLInputElement>(null)
  const priceNum = Math.floor(Number(price) || 0)

  function pickImage(f: File | null) {
    setNewImage(f)
    if (!f) {
      setNewImagePreview(null)
      return
    }
    const r = new FileReader()
    r.onload = () => setNewImagePreview(String(r.result))
    r.readAsDataURL(f)
  }

  function pickTexture(f: File | null) {
    setNewTexture(f)
    setClearTexture(false)
    if (!f) {
      setNewTexturePreview(null)
      return
    }
    const r = new FileReader()
    r.onload = () => setNewTexturePreview(String(r.result))
    r.readAsDataURL(f)
  }

  async function save() {
    setError('')
    if (name.trim().length < 3) {
      setError('Give it a name (3+ characters).')
      return
    }
    const finalPrice = priceMode === 'paid' ? priceNum : 0
    if (priceMode === 'paid' && finalPrice < 1) {
      setError('Paid items need a price of at least T$ 1 (or mark it Free).')
      return
    }
    if (limited && finalPrice < 1) {
      setError('Limited items need a price of at least T$ 1.')
      return
    }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('name', name.trim())
      fd.append('description', description.trim())
      fd.append('price', String(finalPrice))
      fd.append('limited', limited ? '1' : '0')
      if (limited) fd.append('stock', stock.trim())
      if (isAdmin) fd.append('ownersBoost', ownersBoost.trim() === '' ? '0' : ownersBoost.trim())
      if (newImage) await attachUpload(fd, 'image', newImage, newImage.name || 'image.png', newImage.type || 'image/png')
      if (item.modelFileId) {
        // texture / tint — only sent for 3D items; the API ignores them otherwise
        if (newTexture) await attachUpload(fd, 'texture', newTexture, newTexture.name || 'texture.png', newTexture.type || 'image/png')
        if (clearTexture) fd.append('clearTexture', '1')
        if (tintOn) fd.append('color', tint)
        else if (item.baseColor) fd.append('clearColor', '1')
        // PBR material sliders — 'file' resets to whatever the GLB carries
        fd.append('metallic', metMode === 'custom' ? String(metVal) : 'file')
        fd.append('roughness', rghMode === 'custom' ? String(rghVal) : 'file')
      }
      await api(`/api/catalog/${item.id}`, {
        method: 'PATCH',
        body: fd,
      })
      flash(setToast, 'Item updated!')
      onSaved()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Update failed')
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
      aria-label={`Edit ${item.name}`}
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <div className="rb-box" style={{ width: 'min(460px, 100%)', background: '#fff' }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Edit: {item.name}</span>
          <button className="rb-btn" style={{ fontSize: 10, padding: '2px 8px' }} onClick={onClose}>✕</button>
        </div>
        <div style={{ padding: 12 }}>
          <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#7b8896', marginBottom: 10 }}>
            {item.assetId} · you own this, so you can change its listing
          </div>
          {/* thumbnail / artwork — current one shown, owner can swap it */}
          <div style={{ display: 'flex', gap: 10, marginBottom: 10, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 72, height: 72, flexShrink: 0, border: '1px solid #b7c6d4', overflow: 'hidden',
                background: PREVIEW_BG,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}
            >
              {item.modelFileId && !newImage ? (
                <ItemThumb3D
                  modelUrl={`/api/files/${item.modelFileId}`}
                  placement={item.placement}
                  alt={item.name}
                  fallbackSrc={`/api/files/${item.imageFileId}`}
                  metallic={metPreview}
                  roughness={rghPreview}
                  style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', display: 'block' }}
                />
              ) : (
                <img
                  src={newImagePreview || `/api/files/${item.imageFileId}`}
                  alt={item.name}
                  style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', display: 'block' }}
                />
              )}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 3 }}>Thumbnail / artwork</div>
              <div style={{ fontSize: 10, color: '#5a6b7b', lineHeight: 1.45, marginBottom: 4 }}>
                {item.modelFileId
                  ? 'This is the catalog shot. Upload a new image, or re-frame it in the placement editor when you wear it.'
                  : 'Upload a new image if you want a different look.'}
              </div>
              <button type="button" className="rb-btn" style={{ fontSize: 10, padding: '3px 9px' }} onClick={() => imageRef.current?.click()}>
                {newImage ? '↺ Choose a different image' : '✎ Replace image'}
              </button>
              {newImage && (
                <button
                  type="button"
                  className="rb-link"
                  style={{ background: 'none', border: 'none', padding: 0, fontSize: 10, marginLeft: 8 }}
                  onClick={() => pickImage(null)}
                >
                  undo
                </button>
              )}
              <input
                ref={imageRef}
                type="file"
                accept="image/*"
                style={{ display: 'none' }}
                onChange={(e) => {
                  pickImage(e.target.files?.[0] || null)
                  e.target.value = ''
                }}
              />
            </div>
          </div>
          {item.modelFileId && (
            /* texture & tint — the model's surface, editable by the owner */
            <div style={{ border: '1px solid #dbe4ec', background: '#f8fbfe', padding: '8px 10px', marginBottom: 10 }}>
              <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>Texture &amp; color (3D model surface)</div>
              <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center', fontSize: 11 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ color: '#5a6b7b' }}>Texture:</span>
                  <span
                    style={{
                      width: 30, height: 30, border: '1px solid #b7c6d4', display: 'inline-flex',
                      alignItems: 'center', justifyContent: 'center', background: '#fff', overflow: 'hidden', fontSize: 8, color: '#8ba0b3',
                    }}
                  >
                    {newTexturePreview ? (
                      <img src={newTexturePreview} alt="New texture" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                    ) : clearTexture ? (
                      'none'
                    ) : item.textureFileId ? (
                      <img src={`/api/files/${item.textureFileId}`} alt="Current texture" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                    ) : (
                      'none'
                    )}
                  </span>
                  <button type="button" className="rb-btn" style={{ fontSize: 10, padding: '3px 9px' }} onClick={() => textureRef.current?.click()}>
                    {newTexture ? '↺ Different image' : item.textureFileId ? 'Replace texture' : 'Add texture'}
                  </button>
                  {(item.textureFileId || newTexture) && !clearTexture && (
                    <button
                      type="button"
                      className="rb-link"
                      style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }}
                      onClick={() => { setNewTexture(null); setNewTexturePreview(null); setClearTexture(true) }}
                    >
                      remove
                    </button>
                  )}
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 5, cursor: 'pointer' }}>
                  <input type="checkbox" checked={tintOn} onChange={(e) => setTintOn(e.target.checked)} />
                  Tint color
                  <input
                    type="color"
                    value={tint}
                    onChange={(e) => setTint(e.target.value)}
                    disabled={!tintOn}
                    style={{ width: 30, height: 22, padding: 0, border: '1px solid #b7c6d4', background: '#fff' }}
                    aria-label="Model tint color"
                  />
                </label>
              </div>
              <div style={{ marginTop: 8 }}>
                <div style={{ fontSize: 10, color: '#7b8896', marginBottom: 4 }}>Classic colors:</div>
                <BrickSwatches
                  value={tintOn ? tint : undefined}
                  onPick={(hex) => { setTint(hex); setTintOn(true) }}
                />
              </div>
              <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 4 }}>
                A texture wraps every surface that has no texture of its own. The tint only paints the parts that arrived plain white —
                the model&rsquo;s own Blender colors always show.
              </div>
              {/* PBR material — the Blender metallic / roughness sliders */}
              <div style={{ borderTop: '1px dashed #c9d6e2', marginTop: 10, paddingTop: 8 }}>
                <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 2 }}>Material — metallic &amp; roughness</div>
                <div style={{ fontSize: 10, color: '#8ba0b3', marginBottom: 6 }}>
                  Set the metal feel of your model — what you see here is what every player gets, on the site and in game.
                </div>
                <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: '#1c2733' }}>
                    <input
                      type="checkbox"
                      checked={metMode === 'custom'}
                      onChange={(e) => {
                        setMetMode(e.target.checked ? 'custom' : 'file')
                        if (e.target.checked && item.metallic != null) setMetVal(item.metallic)
                      }}
                    />
                    <span style={{ color: '#5a6b7b', width: 56 }}>Metallic</span>
                    <input
                      type="range" min={0} max={100} step={1} value={Math.round((metMode === 'custom' ? metVal : (item.metallic ?? 0)) * 100)}
                      onChange={(e) => { setMetMode('custom'); setMetVal(Number(e.target.value) / 100) }}
                      style={{ width: 120 }}
                      aria-label="Metallic"
                    />
                    <span style={{ fontFamily: 'monospace', width: 34, textAlign: 'right' }}>
                      {Math.round((metMode === 'custom' ? metVal : (item.metallic ?? 0)) * 100)}%
                    </span>
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: '#1c2733' }}>
                    <input
                      type="checkbox"
                      checked={rghMode === 'custom'}
                      onChange={(e) => {
                        setRghMode(e.target.checked ? 'custom' : 'file')
                        if (e.target.checked && item.roughness != null) setRghVal(item.roughness)
                      }}
                    />
                    <span style={{ color: '#5a6b7b', width: 56 }}>Roughness</span>
                    <input
                      type="range" min={0} max={100} step={1} value={Math.round((rghMode === 'custom' ? rghVal : (item.roughness ?? 0.85)) * 100)}
                      onChange={(e) => { setRghMode('custom'); setRghVal(Number(e.target.value) / 100) }}
                      style={{ width: 120 }}
                      aria-label="Roughness"
                    />
                    <span style={{ fontFamily: 'monospace', width: 34, textAlign: 'right' }}>
                      {Math.round((rghMode === 'custom' ? rghVal : (item.roughness ?? 0.85)) * 100)}%
                    </span>
                  </label>
                </div>
                <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 4 }}>
                  Unticked = use whatever the model file carries. Ticked = this value is applied everywhere.
                  {' '}{metMode === 'custom' && metVal >= 0.7 ? 'Shiny metal! 0% roughness is a mirror, 30-50% is brushed steel.' : rghMode === 'custom' && rghVal <= 0.25 ? 'Glossy — strong highlights.' : 'Classic matte plastic is 0% metallic / 85% roughness.'}
                </div>
              </div>
              <input
                ref={textureRef}
                type="file"
                accept="image/*"
                style={{ display: 'none' }}
                onChange={(e) => {
                  pickTexture(e.target.files?.[0] || null)
                  e.target.value = ''
                }}
              />
            </div>
          )}
          <label style={{ display: 'block', fontSize: 11, color: '#1c4e7c', marginBottom: 8 }}>
            Name
            <input className="rb-input" value={name} onChange={(e) => setName(e.target.value)} maxLength={40} style={{ width: '100%', fontSize: 11, marginTop: 2 }} />
          </label>
          <label style={{ display: 'block', fontSize: 11, color: '#1c4e7c', marginBottom: 8 }}>
            Description
            <textarea className="rb-input" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={600} rows={2} style={{ width: '100%', fontSize: 11, marginTop: 2, resize: 'vertical' }} />
          </label>
          <div style={{ border: '1px solid #dbe4ec', background: '#f8fbfe', padding: '8px 10px', marginBottom: 10 }}>
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center', fontSize: 11 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
                <input type="radio" name={`pm-${item.id}`} checked={priceMode === 'free'} onChange={() => setPriceMode('free')} />
                Free
              </label>
              <label style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
                <input type="radio" name={`pm-${item.id}`} checked={priceMode === 'paid'} onChange={() => setPriceMode('paid')} />
                Paid:
                <span style={{ color: '#5d4a0a', fontFamily: 'monospace' }}>T$</span>
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  max={1000000}
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                  disabled={priceMode !== 'paid' || (limited && item.isLimited && !isAdmin)}
                  style={{ width: 90, fontSize: 11 }}
                  aria-label="Price in Tix"
                />
              </label>
              <label
                style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer', color: limited ? '#8a6d1a' : '#1c4e7c' }}
                title="Limited — a collectible badge for rare items"
              >
                <input type="checkbox" checked={limited} onChange={(e) => setLimited(e.target.checked)} />
                ★ Limited
              </label>
            </div>
            <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 4 }}>
              {limited && item.isLimited && !isAdmin
                ? 'Limited prices are LOCKED — the price rises automatically as copies sell. Only a site admin can change the original price.'
                : limited
                  ? isAdmin
                    ? 'Admin: you can adjust the original price. The rising sale price is computed from it automatically.'
                    : 'Limiteds are collectibles — buyers pay exactly this price.'
                  : priceMode === 'paid'
                    ? 'Buyers pay this price in Tix from their wallet.'
                    : 'Anyone can grab it for free.'}
            </div>
            {limited && (
              <div style={{ marginTop: 8, fontSize: 11, color: '#1c4e7c', display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <span>Stock (total copies ever):</span>
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  value={stock}
                  onChange={(e) => setStock(e.target.value)}
                  placeholder="unlimited"
                  style={{ width: 90, fontSize: 11 }}
                  aria-label="Limited stock"
                />
                <span style={{ fontSize: 10, color: '#8ba0b3' }}>
                  {stock.trim() === ''
                    ? 'empty = unlimited copies'
                    : item.sold >= Math.max(1, Math.floor(Number(stock) || 1))
                      ? `SOLD OUT — all ${stock} copies are gone`
                      : `${Math.max(0, Math.floor(Number(stock) || 0) - item.sold)} left after ${item.sold} sold`}
                </span>
              </div>
            )}
            {isAdmin && (
              <div style={{ marginTop: 8, fontSize: 11, color: '#1c4e7c', display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <span title="Added to the REAL owners count on display — the ledger itself never changes">Displayed owners boost (admin):</span>
                <input
                  className="rb-input"
                  type="number"
                  min={0}
                  value={ownersBoost}
                  onChange={(e) => setOwnersBoost(e.target.value)}
                  style={{ width: 90, fontSize: 11 }}
                  aria-label="Owners count boost"
                />
                <span style={{ fontSize: 10, color: '#8ba0b3' }}>shows as {item.sold + Math.max(0, Math.floor(Number(ownersBoost) || 0)).toLocaleString('en-US')} owned</span>
              </div>
            )}
          </div>
          {error && <div style={{ fontSize: 11, color: '#a81a13', marginBottom: 6 }}>{error}</div>}
          <div style={{ display: 'flex', gap: 6 }}>
            <button className="rb-btn rb-btn-green" style={{ fontSize: 11, flex: 1 }} disabled={busy} onClick={save}>
              {busy ? 'Saving...' : '✓ Save changes'}
            </button>
            <button className="rb-btn" style={{ fontSize: 11 }} onClick={onClose} disabled={busy}>
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

/* ---------------- publish form ---------------- */

function PublishForm({ onDone, groups }: { onDone: () => void; groups: GroupOpt[] }) {
  const { setToast } = useRetro()
  const [name, setName] = useState('')
  const [type, setType] = useState('hat')
  const [description, setDescription] = useState('')
  const [groupId, setGroupId] = useState('')
  const [image, setImage] = useState<File | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [converting, setConverting] = useState(false)
  // progress line for big (chunked) uploads — shown on the publish button
  const [uploadNote, setUploadNote] = useState('')
  // pricing: free or paid in Tix; ★ Limited is a collectible badge — the price is the price
  const [priceMode, setPriceMode] = useState<'free' | 'paid'>('free')
  const [price, setPrice] = useState('')
  const [limited, setLimited] = useState(false)
  // limited stock: how many copies will ever exist (empty = unlimited)
  const [stockInput, setStockInput] = useState('')
  // 3D flow state: the converted GLB, the creator's placement, the thumbnail
  const [modelBlob, setModelBlob] = useState<Blob | null>(null)
  const [placement, setPlacement] = useState<Placement | null>(null)
  const [thumbUrl, setThumbUrl] = useState<string | null>(null)
  const [editorOpen, setEditorOpen] = useState(false)
  const [dragOver, setDragOver] = useState(false)
  // set when the uploaded model arrived with no material colors — the classic
  // "my UGC is plain white in game" Blender export trap, caught at upload
  const [modelNotice, setModelNotice] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)
  // creator surface: a texture image wrapped around the model, or a flat tint
  const [texture, setTexture] = useState<File | null>(null)
  const [textureUrl, setTextureUrl] = useState<string | null>(null)
  const [colorOn, setColorOn] = useState(false)
  const [itemColor, setItemColor] = useState('#4da6ff')
  // PBR material sliders (metallic / roughness) — 3D UGC only. They START
  // from what the converter detected in the model (a Blender .glb keeps the
  // creator's real metallic; FBX/OBJ lands on the matte plastic defaults)
  // and can be tuned before publishing.
  const [pbrMetallic, setPbrMetallic] = useState(0)
  const [pbrRoughness, setPbrRoughness] = useState(0.85)
  const textureRef = useRef<HTMLInputElement>(null)
  const textureUrlRef = useRef<string | null>(null)
  const is3D = is3DType(type)
  const rigged = isRiggedType(type)
  const priceNum = Math.floor(Number(price) || 0)
  // ---- rigged pipeline (emote / bundle / anim) ----
  const [clipNames, setClipNames] = useState<string[]>([])
  const [clipMap, setClipMap] = useState<Partial<Record<AnimSlot, string>>>({})
  const [previewClip, setPreviewClip] = useState('')
  const [detectedParts, setDetectedParts] = useState<string[]>([])
  // "animate a bundle / normal avatar / with ugc" — the preview context
  const [targetKind, setTargetKind] = useState<'avatar' | 'bundle' | 'ugc'>('avatar')
  const [targetAssetId, setTargetAssetId] = useState('')
  const [marketRigs, setMarketRigs] = useState<CatalogItem[]>([])
  const [marketUgc, setMarketUgc] = useState<CatalogItem[]>([])

  /* live painted preview — the picked GLB as a local object URL so the
     picker box shows the model WITH its texture / flat color the moment
     you choose one, before you ever publish */
  const previewModelUrl = useMemo(
    () => (modelBlob ? URL.createObjectURL(modelBlob) : null),
    [modelBlob]
  )

  /* the preview context: classic avatar, a marketplace bundle, or wearing a
     marketplace UGC piece — "animate a bundle or normal avatar or with ugc" */
  const previewLook = useMemo<AvatarLook3D>(() => {
    const base = buildPreviewParts(DEFAULT_AVATAR, (id) => resolveDefaultAsset(id))
    const look: AvatarLook3D = {
      skin: base.skin,
      shirtColor: base.shirtColor,
      shirtImage: base.shirtImage || null,
      pantsColor: base.pantsColor,
      pantsImage: base.pantsImage || null,
      faceUrl: base.faceUrl,
      tshirtUrls: [],
      models: [],
    }
    if (targetKind === 'bundle' && targetAssetId) {
      const b = marketRigs.find((r) => r.assetId === targetAssetId)
      if (b?.modelFileId) look.bundle = { url: `/api/files/${b.modelFileId}` }
    } else if (targetKind === 'ugc' && targetAssetId) {
      const u = marketUgc.find((r) => r.assetId === targetAssetId)
      if (u?.modelFileId) {
        look.models = [{
          url: `/api/files/${u.modelFileId}`,
          imageUrl: `/api/files/${u.imageFileId}`,
          placement: u.placement,
          textureUrl: u.textureFileId ? `/api/files/${u.textureFileId}` : undefined,
          color: u.baseColor || undefined,
          animClips: u.animClips?.clips,
        }]
      }
    }
    return look
  }, [targetKind, targetAssetId, marketRigs, marketUgc])

  /* the realtime cycle order for an anim pack: mapped slots first (the moves
     that take over the classic ones), any remaining clips after */
  const animCycleClips = useMemo(() => {
    const mapped = ANIM_SLOTS.map((s) => clipMap[s]).filter(Boolean) as string[]
    const rest = clipNames.filter((c) => !mapped.includes(c))
    return [...mapped, ...rest].slice(0, 6)
  }, [clipMap, clipNames])
  useEffect(() => {
    return () => {
      if (previewModelUrl) URL.revokeObjectURL(previewModelUrl)
    }
  }, [previewModelUrl])

  /* ---- rigged GLB intake: enumerate the Blender clips + detect body parts,
     then auto-capture the catalog thumbnail from a mid-clip pose. This is
     the door for "upload a rig with anims and preview the anim". */
  async function ingestRiggedGlb(glb: Blob) {
    const url = URL.createObjectURL(glb)
    try {
      const loader = new GLTFLoader()
      const gltf = await loader.loadAsync(url)
      const names = (gltf.animations || []).map((c: { name: string }) => c.name).filter(Boolean)
      setClipNames(names)
      setPreviewClip(names[0] || '')
      // keep any existing mapping whose clip still exists (re-picking a model)
      setClipMap((old) => {
        const next: Partial<Record<AnimSlot, string>> = {}
        for (const slot of ANIM_SLOTS) {
          const v = old[slot]
          if (v && names.includes(v)) next[slot] = v
        }
        return next
      })
      // bundle parts are detected from the mesh names (matchPart aliases)
      const aliaseNames: Record<string, string[]> = {
        head: ['head'], torso: ['torso'],
        armL: ['left arm', 'leftarm', 'arm_l', 'l arm'], armR: ['right arm', 'rightarm', 'arm_r', 'r arm'],
        legL: ['left leg', 'leftleg', 'leg_l', 'l leg'], legR: ['right leg', 'rightleg', 'leg_r', 'r leg'],
      }
      const norm = (s: string) => s.toLowerCase().replace(/[\s._]+/g, ' ').trim()
      const parts = new Set<string>()
      gltf.scene.traverse((o: { name?: string; isMesh?: boolean }) => {
        if (!(o as unknown as { isMesh?: boolean }).isMesh) return
        const n = norm(o.name || '')
        for (const [key, aliases] of Object.entries(aliaseNames)) {
          if (aliases.some((a) => n === a || n.startsWith(a + ' ') || n.startsWith(a + '_'))) parts.add(key)
        }
      })
      setDetectedParts([...parts])
      // auto-capture the catalog shot from a nice mid-clip pose
      try {
        const thumb = await captureRiggedThumb(url, names[0] || undefined)
        setThumbUrl((old) => {
          if (old) URL.revokeObjectURL(old)
          return URL.createObjectURL(thumb)
        })
      } catch { /* the publish still works — the creator can edit the thumb later */ }
    } finally {
      URL.revokeObjectURL(url)
    }
  }

  /* ---- file opening that works EVERYWHERE ----------------------------
   * The old picker was a <div onClick> opening a display:none input —
   * brittle in exactly the ways that make people say "the + button can't
   * be clicked". Now: the picker is a real <button>, the input is
   * visually-hidden (NOT display:none, so every browser opens a chooser
   * for it), showPicker() is tried first where supported, and a big green
   * Choose button gives a second, unmistakable path. */
  function openFile(input: HTMLInputElement | null) {
    if (!input) return
    const withPicker = input as HTMLInputElement & { showPicker?: () => void }
    if (typeof withPicker.showPicker === 'function') {
      try {
        withPicker.showPicker()
        return
      } catch {
        /* Safari/older engines refuse showPicker outside a gesture — click() below */
      }
    }
    input.click()
  }

  function applyTexture(f: File) {
    if (f.size > 8 * 1024 * 1024) { setError('Texture too large (max 8MB).'); return }
    if (f.type && !f.type.startsWith('image/')) { setError('Textures must be images (PNG / JPG).'); return }
    setError('')
    setTexture(f)
    if (textureUrlRef.current) URL.revokeObjectURL(textureUrlRef.current)
    const u = URL.createObjectURL(f)
    textureUrlRef.current = u
    setTextureUrl(u)
  }

  function removeTexture() {
    setTexture(null)
    if (textureUrlRef.current) {
      URL.revokeObjectURL(textureUrlRef.current)
      textureUrlRef.current = null
    }
    setTextureUrl(null)
    if (textureRef.current) textureRef.current.value = ''
  }

  /** one validation + routing path for EVERY way a file can arrive:
   *  picker click, Choose button, drop on the box, drop ANYWHERE on the page */
  function acceptDroppedFile(f: File) {
    if (is3DType(type) || rigged) {
      // dropped an image on a 3D publish — that's a texture, not a mistake
      if (is3DType(type) && (/\.(png|jpe?g|gif|webp|bmp)$/i.test(f.name) || f.type.startsWith('image/'))) {
        applyTexture(f)
        return
      }
      if (!/\.(fbx|glb|gltf|obj)$/i.test(f.name)) {
        setError(`${TYPE_SINGULAR[type] || type} takes a 3D model (FBX / GLB / OBJ) — "${f.name}" is not one.${is3DType(type) ? ' Images dropped here become the model texture.' : ''}`)
        return
      }
      pick(f)
      return
    }
    if (!f.type.startsWith('image/')) {
      setError(`${TYPE_SINGULAR[type] || type} takes an image (PNG / JPG / GIF) — "${f.name}" is not one.`)
      return
    }
    pick(f)
  }

  // latest routing readable from the window-level drop listener
  const acceptRef = useRef(acceptDroppedFile)
  acceptRef.current = acceptDroppedFile

  /* dropping ANYWHERE while this form is open uploads the file — and the
   * document-level preventDefault stops the browser from navigating to the
   * file (which looks like the whole site "ate" your session — a classic
   * way people think their UGC got deleted) */
  useEffect(() => {
    const onDragOver = (e: DragEvent) => {
      if (e.dataTransfer && Array.from(e.dataTransfer.types || []).includes('Files')) {
        e.preventDefault()
        setDragOver(true)
      }
    }
    const onDragLeave = (e: DragEvent) => {
      if (!e.relatedTarget) setDragOver(false)
    }
    const onDrop = (e: DragEvent) => {
      e.preventDefault()
      setDragOver(false)
      const f = e.dataTransfer?.files?.[0]
      if (f) acceptRef.current(f)
    }
    window.addEventListener('dragover', onDragOver)
    window.addEventListener('dragleave', onDragLeave)
    window.addEventListener('drop', onDrop)
    return () => {
      window.removeEventListener('dragover', onDragOver)
      window.removeEventListener('dragleave', onDragLeave)
      window.removeEventListener('drop', onDrop)
    }
  }, [])

  // mid-publish protection: never lose a picked model / running upload to an
  // accidental tab close or refresh
  useEffect(() => {
    const guard = (e: BeforeUnloadEvent) => {
      if (busy || converting || modelBlob || image) {
        e.preventDefault()
        e.returnValue = ''
      }
    }
    window.addEventListener('beforeunload', guard)
    return () => window.removeEventListener('beforeunload', guard)
  }, [busy, converting, modelBlob, image])

  // switching type only resets the pick when the MODE changes (rigged <-> 3D
  // <-> image) — a shirt image can't become a hat model, but a picked hat
  // model survives moving to Gear, so nobody's upload silently "disappears"
  function publishMode(t: string): 'rigged' | '3d' | 'image' {
    if (isRiggedType(t)) return 'rigged'
    if (is3DType(t)) return '3d'
    return 'image'
  }
  function switchType(t: string) {
    const was = publishMode(type)
    const will = publishMode(t)
    setType(t)
    setError('')
    if (was !== will) {
      setImage(null)
      setPreview(null)
      setModelBlob(null)
      setPlacement(null)
      setThumbUrl(null)
      setClipNames([])
      setClipMap({})
      setPreviewClip('')
      setDetectedParts([])
      setModelNotice('')
      removeTexture()
      setColorOn(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  function pick(f: File | null) {
    setError('')
    if (rigged) {
      // rigged: convert to GLB KEEPING the Blender clips, then enumerate them
      if (!f) return
      const tooBig = modelTooBig(f)
      if (tooBig) { setError(tooBig); return }
      setConverting(true)
      fileToGlb(f, { keepAnimations: true })
        .then(async (glb) => {
          setModelBlob(glb)
          setEditorOpen(false)
          await ingestRiggedGlb(glb)
        })
        .catch((e) => setError(e instanceof Error ? e.message : 'Could not read that model.'))
        .finally(() => setConverting(false))
      return
    }
    if (is3DType(type)) {
      // 3D: convert to GLB in the browser, then open the placement editor.
      // The conversion also checks the materials — a model that landed with
      // no colors at all would be plain white in game, so we say so NOW.
      if (!f) return
      const tooBig = modelTooBig(f)
      if (tooBig) { setError(tooBig); return }
      setConverting(true)
      fileToGlbWithCheck(f)
        .then(({ glb, colorWarning, metallic, roughness }) => {
          setModelBlob(glb)
          setModelNotice(colorWarning || '')
          setPbrMetallic(metallic)
          setPbrRoughness(roughness)
          setEditorOpen(true)
        })
        .catch((e) => setError(e instanceof Error ? e.message : 'Could not read that model.'))
        .finally(() => setConverting(false))
      return
    }
    setImage(f)
    if (f) {
      const r = new FileReader()
      r.onload = () => setPreview(String(r.result))
      r.readAsDataURL(f)
    } else setPreview(null)
  }

  function onPlaced(result: { placement: Placement; thumb: Blob }) {
    setPlacement(result.placement)
    setThumbUrl((old) => {
      if (old) URL.revokeObjectURL(old)
      return URL.createObjectURL(result.thumb)
    })
    setEditorOpen(false)
    setModelBlob((mb) => (mb ? new File([mb], 'model.glb', { type: 'model/gltf-binary' }) : mb))
    setImage((_) => null)
  }

  // marketplace rigs + UGC for the "preview on / base it on" pickers
  useEffect(() => {
    if (!rigged) return
    let alive = true
    Promise.all([
      api<{ items: CatalogItem[] }>('/api/catalog?type=emote').catch(() => ({ items: [] })),
      api<{ items: CatalogItem[] }>('/api/catalog?type=anim').catch(() => ({ items: [] })),
      api<{ items: CatalogItem[] }>('/api/catalog?type=bundle').catch(() => ({ items: [] })),
      api<{ items: CatalogItem[] }>('/api/catalog').catch(() => ({ items: [] })),
    ]).then(([emotes, anims, bundles, all]) => {
      if (!alive) return
      const rigs = [...emotes.items, ...anims.items, ...bundles.items].filter((i) => i.modelFileId)
      setMarketRigs(rigs)
      setMarketUgc(all.items.filter((i) => i.modelFileId && (is3DType(i.type) || i.type === 'bundle')))
    })
    return () => { alive = false }
  }, [rigged])

  /** base an emote/anim on a marketplace rig that already exists — its GLB is
   *  fetched and re-published as the creator's own item with fresh clips. */
  async function useMarketplaceRig(assetId: string) {
    const src = marketRigs.find((r) => r.assetId === assetId)
    if (!src?.modelFileId) return
    setError('')
    setConverting(true)
    try {
      const res = await fetch(`/api/files/${src.modelFileId}`)
      const blob = await res.blob()
      const file = new File([blob], `${src.assetId}.glb`, { type: 'model/gltf-binary' })
      setModelBlob(file)
      await ingestRiggedGlb(file)
      flash(setToast, `Rig from "${src.name}" loaded — map your clips and publish.`)
    } catch {
      setError('Could not load that rig — try uploading your own GLB.')
    } finally {
      setConverting(false)
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    if (name.trim().length < 3) { setError('Give it a name (3+ characters).'); return }
    const finalPrice = priceMode === 'paid' ? priceNum : 0
    if (priceMode === 'paid' && finalPrice < 1) { setError('Paid items need a price of at least T$ 1 (or mark it Free).'); return }
    if (limited && finalPrice < 1) { setError('Limited items need a price of at least T$ 1.'); return }
    if (rigged) {
      if (!modelBlob) { setError('Pick a rigged GLB first (exported from Blender with its rig + animations).'); return }
      if (type === 'anim' && clipNames.length === 0) { setError('Your GLB has no animation clips — an animation pack needs at least one.'); return }
      if (type === 'anim' && Object.keys(clipMap).length === 0) { setError('Map at least one move (Idle / Walk / Jump / Climb / Fall) to a clip from your GLB.'); return }
    } else if (is3D) {
      if (!modelBlob) { setError('Pick a 3D model file first (FBX, GLB or OBJ).'); return }
      if (!placement) { setError('Place the item on the player model in 3D before publishing.'); return }
      if (!thumbUrl) { setError('Missing the preview image — place the item again.'); return }
    } else if (!image) {
      setError('Pick an image for your item.'); return
    }
    setBusy(true)
    setUploadNote('')
    try {
      const fd = new FormData()
      fd.append('name', name.trim())
      fd.append('type', type)
      fd.append('description', description.trim())
      fd.append('price', String(finalPrice))
      fd.append('limited', limited ? '1' : '0')
      if (limited && stockInput.trim() !== '') fd.append('stock', stockInput.trim())
      if (groupId) fd.append('groupId', groupId)
      if (rigged && modelBlob) {
        // the rigged GLB IS the item; the catalog shot is captured automatically
        await attachUpload(fd, 'model', modelBlob, 'model.glb', 'model/gltf-binary', setUploadNote)
        const capUrl = previewModelUrl || URL.createObjectURL(modelBlob)
        try {
          const thumbBlob = await captureRiggedThumb(capUrl, type === 'anim' ? (clipMap.idle || clipNames[0]) : (previewClip || clipNames[0] || undefined))
          await attachUpload(fd, 'image', thumbBlob, 'thumbnail.png', 'image/png', setUploadNote)
        } catch {
          throw new Error('Could not capture the preview image — re-pick the model and try again.')
        }
        if (type === 'bundle') {
          if (detectedParts.length > 0) fd.append('bundleParts', JSON.stringify(detectedParts))
        } else {
          fd.append('animClips', JSON.stringify({ clips: clipNames, ...(type === 'anim' ? { map: clipMap } : {}) }))
          fd.append('animTarget', JSON.stringify({ kind: targetKind, ...(targetKind !== 'avatar' && targetAssetId ? { assetId: targetAssetId } : {}) }))
        }
      } else if (is3D && modelBlob && placement && thumbUrl) {
        await attachUpload(fd, 'model', modelBlob, 'model.glb', 'model/gltf-binary', setUploadNote)
        const thumbBlob = await (await fetch(thumbUrl)).blob()
        await attachUpload(fd, 'image', thumbBlob, 'thumbnail.png', 'image/png', setUploadNote)
        fd.append('placement', placementJson(placement))
        // the creator's surface: texture first, flat color when there is none
        if (texture) await attachUpload(fd, 'texture', texture, texture.name || 'texture.png', texture.type || 'image/png', setUploadNote)
        else if (colorOn) fd.append('color', itemColor)
        // PBR material feel (metallic / roughness), saved on the item so the
        // site AND the Godot player render it identically
        fd.append('metallic', String(pbrMetallic))
        fd.append('roughness', String(pbrRoughness))
      } else if (image) {
        await attachUpload(fd, 'image', image, image.name || 'image.png', image.type || 'image/png', setUploadNote)
      }
      const res = await api<{ item: { assetId: string; name: string } }>('/api/catalog', { method: 'POST', body: fd })
      flash(setToast, `Published! Asset id: ${res.item.assetId}`)
      onDone()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Publish failed')
      setUploadNote('')
      setBusy(false)
    }
  }

  return (
    <div className="rb-box" style={{ marginBottom: 12 }}>
      <div className="rb-panel-head"><span>Publish Avatar UGC</span></div>
      {/* full-page drop target — drop a file ANYWHERE while publishing;
          pointer-events none so the overlay itself never blocks the drop */}
      {dragOver && (
        <div
          aria-hidden
          style={{
            position: 'fixed', inset: 0, zIndex: 80, pointerEvents: 'none',
            background: 'rgba(46,158,62,0.12)', border: '3px dashed #2e9e3e',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <div className="rb-box" style={{ padding: '14px 24px', fontSize: 14, color: '#1c2733' }}>
            Drop to upload {is3D ? 'your model — images become its texture' : 'your image'}
          </div>
        </div>
      )}
      <form onSubmit={submit} style={{ padding: 12, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        {/* picker / thumbnail preview — a REAL button, so the click always
            lands (the old div-onClick was the "+ button you can't click") */}
        <div style={{ width: 140, flexShrink: 0 }}>
          <button
            type="button"
            aria-label="Choose or drop a file"
            onClick={() => openFile(fileRef.current)}
            onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
            onDragLeave={() => setDragOver(false)}
            style={{
              width: 140, height: 140, border: `2px dashed ${dragOver ? '#2e9e3e' : '#8ba0b3'}`,
              background: dragOver ? '#e9f7ea' : PREVIEW_BG,
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
              flexDirection: 'column', gap: 4, overflow: 'hidden', textAlign: 'center',
              outline: dragOver ? '2px solid #2e9e3e' : undefined, padding: 0, fontFamily: 'inherit',
            }}
          >
            {rigged ? (
              thumbUrl ? (
                <img src={thumbUrl} alt="Your rig — auto-captured catalog shot" style={{ width: '100%', height: '100%', objectFit: 'contain', display: 'block' }} />
              ) : converting ? (
                <span style={{ fontSize: 10, color: '#5a7b9a', padding: 6 }}>Reading the rig...</span>
              ) : (
                <>
                  <span style={{ fontSize: 26, color: '#5a7b9a' }}>+</span>
                  <span style={{ fontSize: 10, color: '#5a7b9a' }}>Rigged GLB</span>
                  <span style={{ fontSize: 8, color: '#8ba0b3', padding: '0 6px' }}>rig + animations · from Blender</span>
                </>
              )
            ) : is3D ? (
              previewModelUrl ? (
                /* live render of the picked model — repaints instantly when
                   a texture or flat color is chosen (baked shot as fallback) */
                <ItemThumb3D
                  modelUrl={previewModelUrl}
                  placement={placement}
                  alt="Live preview of your item"
                  fallbackSrc={thumbUrl || undefined}
                  textureUrl={textureUrl || undefined}
                  color={textureUrl ? undefined : colorOn ? itemColor : undefined}
                  metallic={pbrMetallic}
                  roughness={pbrRoughness}
                  style={{ width: '100%', height: '100%', objectFit: 'contain', display: 'block', background: '#fff' }}
                />
              ) : thumbUrl ? (
                <img src={thumbUrl} alt="Your item — the clean catalog shot" style={{ width: '100%', height: '100%', objectFit: 'contain', display: 'block' }} />
              ) : converting ? (
                <span style={{ fontSize: 10, color: '#5a7b9a', padding: 6 }}>Reading the model...</span>
              ) : (
                <>
                  <span style={{ fontSize: 26, color: '#5a7b9a' }}>+</span>
                  <span style={{ fontSize: 10, color: '#5a7b9a' }}>3D model</span>
                  <span style={{ fontSize: 8, color: '#8ba0b3', padding: '0 6px' }}>Click or drop · FBX · GLB · OBJ</span>
                </>
              )
            ) : preview ? (
              <img src={preview} alt="Item preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            ) : (
              <>
                <span style={{ fontSize: 26, color: '#5a7b9a' }}>+</span>
                <span style={{ fontSize: 10, color: '#5a7b9a' }}>Item image</span>
                <span style={{ fontSize: 8, color: '#8ba0b3', padding: '0 6px' }}>Click or drop</span>
              </>
            )}
          </button>
          {/* visually hidden, NOT display:none — display:none inputs refuse to
              open their chooser in some browsers; a 1px transparent input
              always works, and focus reaches it for keyboard users */}
          <input
            ref={fileRef}
            type="file"
            accept={is3D || rigged ? MODEL_ACCEPT : 'image/*'}
            style={{ position: 'absolute', width: 1, height: 1, opacity: 0, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' }}
            onChange={(e) => pick(e.target.files?.[0] || null)}
          />
          <button
            type="button"
            className="rb-btn rb-btn-green"
            style={{ fontSize: 11, width: '100%', marginTop: 6 }}
            onClick={() => openFile(fileRef.current)}
          >
            {is3D || rigged ? 'Choose 3D model' : 'Choose image'}
          </button>
          {is3D || rigged ? (
            <>
              <div style={{ fontSize: 9, color: '#7b8896', marginTop: 4 }}>
                {rigged ? 'Click or drop — a rigged GLB (rig + clips), max 24MB' : 'Click or drop — FBX / GLB / OBJ, max 24MB'}
              </div>
              {is3D && (
                <div style={{ fontSize: 9, color: '#1c4e7c', marginTop: 3, lineHeight: 1.4 }}>
                  <strong>Using materials or textures? Upload .glb.</strong> Blender: File &gt; Export &gt; glTF 2.0
                  (format = glTF Binary) — GLB always keeps every material and texture. FBX drops them unless you use
                  Path Mode Copy + Embed Textures.
                </div>
              )}
              {is3D && modelBlob && (
                <button
                  type="button"
                  className="rb-btn"
                  style={{ fontSize: 10, width: '100%', marginTop: 6 }}
                  onClick={() => setEditorOpen(true)}
                >
                  {thumbUrl ? '✎ Edit thumbnail' : '≡ Place it in 3D'}
                </button>
              )}
              {is3D && modelNotice && (
                <div
                  style={{
                    border: '1px solid #e0c98a', background: '#fff8e8', padding: '6px 8px',
                    marginTop: 6, fontSize: 9.5, color: '#7a5c0e', lineHeight: 1.5,
                  }}
                  role="alert"
                >
                  <strong style={{ fontSize: 10 }}>⚠ No material colors found in this model.</strong>
                  <br />
                  {modelNotice}
                  <br />
                  <span style={{ color: '#5d4a0a' }}>
                    Blender recipe: Shading workspace → New Material → Base Color → pick grey / brown / anything →
                    File Export → glTF 2.0 (.glb). That export always keeps your colors.
                  </span>
                </div>
              )}
              {thumbUrl && (
                <div style={{ fontSize: 9, color: '#3e8e41', marginTop: 4, lineHeight: 1.4 }}>
                  ✓ Thumbnail saved — just the item on a transparent background. Re-open any time to re-frame it.
                </div>
              )}
            </>
          ) : (
            <>
              <div style={{ fontSize: 9, color: '#7b8896', marginTop: 4 }}>Click or drop — PNG / JPG / GIF, max 8MB</div>
              {/* official paint template (classic Roblox style: download -> paint -> upload) */}
              <a
                className="rb-link"
                style={{ fontSize: 10, display: 'inline-block', marginTop: 4 }}
                href={`/ugc-templates/${type}-template.png`}
                download
              >
                ⬇ Official {TYPE_SINGULAR[type] || type} template
              </a>
            </>
          )}
          <div style={{ fontSize: 9, color: '#8ba0b3', marginTop: 2, maxWidth: 140 }}>
            {is3D
              ? 'The catalog shot is the item alone — no player model behind it, no grid, no clutter.'
              : `${TYPE_HINTS[type] || 'Download it, paint your item, upload.'} Keep the background transparent.`}
          </div>
          {/* the item, big and alone — no avatar behind it, so the art is
              the only thing on screen (checkerboard shows transparency) */}
          {!is3D && preview && (
            <div style={{ marginTop: 8, textAlign: 'center' }}>
              <div
                style={{
                  width: 140, height: 140, border: '1px solid #b7c6d4', display: 'flex',
                  alignItems: 'center', justifyContent: 'center', overflow: 'hidden',
                  background: PREVIEW_BG, margin: '0 auto',
                }}
              >
                <img
                  src={preview}
                  alt="Your item"
                  style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', display: 'block' }}
                />
              </div>
              <div style={{ fontSize: 9, color: '#7b8896', marginTop: 2 }}>Your item — transparent areas stay see-through</div>
            </div>
          )}
        </div>

        <div style={{ flex: 1, minWidth: 220 }}>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
            <label style={{ flex: 2, minWidth: 150, fontSize: 11, color: '#1c4e7c' }}>
              Name
              <input className="rb-input" value={name} onChange={(e) => setName(e.target.value)} maxLength={40} style={{ width: '100%', fontSize: 11, marginTop: 2 }} placeholder="Golden Bloxy Hat" />
            </label>
            <label style={{ flex: 1, minWidth: 110, fontSize: 11, color: '#1c4e7c' }}>
              Type
              <select className="rb-input" value={type} onChange={(e) => switchType(e.target.value)} style={{ width: '100%', fontSize: 11, marginTop: 2 }}>
                {UGC_TYPES.map((t) => <option key={t} value={t}>{UGC_TYPE_LABELS[t]}</option>)}
              </select>
            </label>
          </div>
          <label style={{ display: 'block', fontSize: 11, color: '#1c4e7c', marginBottom: 8 }}>
            Description <span style={{ color: '#8ba0b3' }}>(optional)</span>
            <textarea className="rb-input" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={600} rows={2} style={{ width: '100%', fontSize: 11, marginTop: 2, resize: 'vertical' }} placeholder="What is it? Who made it? Any story?" />
          </label>
          {rigged && (
            /* the rigged pipeline: live animation preview on the chosen body,
               clip enumeration, move mapping and the marketplace-rig reuse */
            <div style={{ border: '1px solid #dbe4ec', background: '#f8fbfe', padding: '10px 12px', marginBottom: 8, width: '100%' }}>
              <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6, fontWeight: 'bold' }}>
                {type === 'emote' ? 'Emote preview' : type === 'bundle' ? 'Bundle preview' : 'Animation pack — realtime moves'}
              </div>
              <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
                <div style={{ width: 260, flexShrink: 0 }}>
                  {previewModelUrl ? (
                    <div style={{ border: '1px solid #b7c6d4' }}>
                      <Player3DView
                        key={previewModelUrl}
                        look={previewLook}
                        height={300}
                        anim={previewModelUrl ? { url: previewModelUrl, clips: type === 'anim' ? animCycleClips : [previewClip || clipNames[0]], single: type !== 'anim' } : null}
                      />
                    </div>
                  ) : (
                    <div style={{ height: 300, border: '1px dashed #b7c6d4', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, color: '#7b8896', textAlign: 'center', padding: 12 }}>
                      Pick a rigged GLB above and your animation preview plays here.
                    </div>
                  )}
                  {clipNames.length > 0 && (
                    <div style={{ fontSize: 10, color: '#3e8e41', marginTop: 6 }}>
                      ✓ {clipNames.length} clip{clipNames.length === 1 ? '' : 's'} found in your GLB
                      {detectedParts.length > 0 && type === 'bundle' && ` · replaces: ${detectedParts.join(', ')}`}
                    </div>
                  )}
                </div>
                <div style={{ flex: 1, minWidth: 220, fontSize: 11 }}>
                  {type !== 'bundle' && clipNames.length > 0 && (
                    <div style={{ marginBottom: 8 }}>
                      <div style={{ color: '#1c4e7c', marginBottom: 3 }}>{type === 'anim' ? 'Map each move to a clip from your GLB' : 'Clip to preview'}</div>
                      {type === 'anim' ? (
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 5 }}>
                          {ANIM_SLOTS.map((slot) => (
                            <label key={slot} style={{ fontSize: 10, color: '#41586c' }}>
                              {ANIM_SLOT_LABELS[slot]}
                              <select
                                className="rb-input"
                                value={clipMap[slot] || ''}
                                onChange={(e) => setClipMap((m) => ({ ...m, [slot]: e.target.value || undefined }))}
                                style={{ width: '100%', fontSize: 10, marginTop: 1 }}
                                aria-label={`${ANIM_SLOT_LABELS[slot]} clip`}
                              >
                                <option value="">— classic —</option>
                                {clipNames.map((c) => <option key={c} value={c}>{c}</option>)}
                              </select>
                            </label>
                          ))}
                        </div>
                      ) : (
                        <select className="rb-input" value={previewClip} onChange={(e) => setPreviewClip(e.target.value)} style={{ fontSize: 11, width: '100%' }} aria-label="Preview clip">
                          {clipNames.map((c) => <option key={c} value={c}>{c}</option>)}
                        </select>
                      )}
                    </div>
                  )}
                  {type !== 'bundle' && (
                    <div style={{ marginBottom: 8 }}>
                      <div style={{ color: '#1c4e7c', marginBottom: 3 }}>Preview it on…</div>
                      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 5 }}>
                        {([['avatar', 'Normal avatar'], ['bundle', 'A bundle'], ['ugc', 'Avatar + UGC']] as const).map(([k, label]) => (
                          <button
                            key={k}
                            type="button"
                            onClick={() => { setTargetKind(k); setTargetAssetId('') }}
                            aria-pressed={targetKind === k}
                            style={{
                              fontSize: 10, padding: '2px 8px', cursor: 'pointer',
                              border: targetKind === k ? '1px solid #0069a8' : '1px solid #b7c6d4',
                              background: targetKind === k ? '#0085cf' : '#fff',
                              color: targetKind === k ? '#fff' : '#1c4e7c',
                            }}
                          >
                            {label}
                          </button>
                        ))}
                      </div>
                      {targetKind === 'bundle' && (
                        <select className="rb-input" value={targetAssetId} onChange={(e) => setTargetAssetId(e.target.value)} style={{ fontSize: 11, width: '100%' }} aria-label="Bundle to preview on">
                          <option value="">— pick a bundle —</option>
                          {marketRigs.filter((i) => i.type === 'bundle').map((i) => <option key={i.assetId} value={i.assetId}>{i.name} ({i.assetId})</option>)}
                        </select>
                      )}
                      {targetKind === 'ugc' && (
                        <select className="rb-input" value={targetAssetId} onChange={(e) => setTargetAssetId(e.target.value)} style={{ fontSize: 11, width: '100%' }} aria-label="UGC to wear in preview">
                          <option value="">— pick a marketplace item —</option>
                          {marketUgc.map((i) => <option key={i.assetId} value={i.assetId}>{i.name} ({UGC_TYPE_LABELS[i.type] || i.type})</option>)}
                        </select>
                      )}
                      <div style={{ fontSize: 9, color: '#8ba0b3', marginTop: 3 }}>
                        {targetKind === 'avatar' && 'Plays on the classic blocky body.'}
                        {targetKind === 'bundle' && 'Plays on the bundle you pick — animate a bundle!'}
                        {targetKind === 'ugc' && 'Your item worn with a marketplace UGC piece — pets flying around you.'}
                      </div>
                    </div>
                  )}
                  <div>
                    <div style={{ color: '#1c4e7c', marginBottom: 3 }}>No rig yet? Start from one that exists:</div>
                    <select
                      className="rb-input"
                      value=""
                      onChange={(e) => { if (e.target.value) useMarketplaceRig(e.target.value) }}
                      style={{ fontSize: 11, width: '100%' }}
                      aria-label="Use a marketplace rig"
                    >
                      <option value="">— use a marketplace rig ({marketRigs.length}) —</option>
                      {marketRigs.map((i) => <option key={i.assetId} value={i.assetId}>{i.name} · {UGC_TYPE_LABELS[i.type] || i.type}</option>)}
                    </select>
                    <a className="rb-link" style={{ fontSize: 10, display: 'inline-block', marginTop: 5 }} href="/models/retroblox-rig-template.glb" download>
                      ⬇ Official R6 rig template (.glb) — animate these parts in Blender
                    </a>
                  </div>
                </div>
              </div>
            </div>
          )}
          {is3D && (
            /* the model's surface: a texture image wrapped around it, or a
               flat tint when there is no texture — visible in the placement
               editor while you place, and on the catalog card forever */
            <div style={{ border: '1px solid #dbe4ec', background: '#f8fbfe', padding: '8px 10px', marginBottom: 8 }}>
              <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>Texture or color — how your model is painted</div>
              <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', alignItems: 'center', fontSize: 11 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                  <button
                    type="button"
                    aria-label="Choose or drop a texture image"
                    onClick={() => openFile(textureRef.current)}
                    style={{
                      width: 44, height: 44, border: '2px dashed #8ba0b3', background: textureUrl ? '#fff' : '#fbfdff',
                      display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
                      overflow: 'hidden', padding: 0, flexShrink: 0,
                    }}
                  >
                    {textureUrl ? (
                      <img src={textureUrl} alt="Your texture" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                    ) : (
                      <span style={{ fontSize: 18, color: '#5a7b9a' }}>+</span>
                    )}
                  </button>
                  <div>
                    <div style={{ fontSize: 11, color: '#1c2733' }}>{texture ? texture.name.slice(0, 22) : 'Texture image'}</div>
                    <div style={{ fontSize: 9, color: '#7b8896' }}>PNG / JPG · wraps the whole model</div>
                    {texture && (
                      <button
                        type="button"
                        className="rb-link"
                        style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }}
                        onClick={removeTexture}
                      >
                        remove texture
                      </button>
                    )}
                  </div>
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 5, cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={colorOn}
                    onChange={(e) => setColorOn(e.target.checked)}
                    disabled={!!texture}
                  />
                  Flat color
                  <input
                    type="color"
                    value={itemColor}
                    onChange={(e) => { setItemColor(e.target.value); setColorOn(true) }}
                    disabled={!!texture}
                    style={{ width: 30, height: 24, padding: 0, border: '1px solid #b7c6d4', background: '#fff' }}
                    aria-label="Model color"
                  />
                </label>
              </div>
              <div style={{ marginTop: 8 }}>
                <div style={{ fontSize: 10, color: '#7b8896', marginBottom: 4 }}>
                  Classic colors{texture ? ' — remove the texture to use these' : ':'}
                </div>
                <BrickSwatches
                  value={colorOn ? itemColor : undefined}
                  disabled={!!texture}
                  onPick={(hex) => { setItemColor(hex); setColorOn(true) }}
                />
              </div>
              <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 4 }}>
                {texture
                  ? 'A texture wraps every surface that has no texture of its own — your model\'s own colors and textures always show.'
                  : 'No texture? A flat color only paints the parts that arrived plain white — your model\'s own Blender colors always show. You can also just drop an image anywhere on this form.'}
              </div>
              {/* PBR material — the Blender metallic / roughness sliders */}
              <div style={{ borderTop: '1px dashed #c9d6e2', marginTop: 10, paddingTop: 8 }}>
                <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 2 }}>Material — metallic &amp; roughness</div>
                <div style={{ fontSize: 10, color: '#8ba0b3', marginBottom: 6 }}>
                  Detected in your model. A Principled BSDF .glb from Blender keeps its real metal feel; FBX starts matte. Tune it here —
                  what you see is what every player gets, on the site and in game.
                </div>
                <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: '#1c2733' }}>
                    <span style={{ color: '#5a6b7b', width: 64 }}>Metallic</span>
                    <input
                      type="range" min={0} max={100} step={1} value={Math.round(pbrMetallic * 100)}
                      onChange={(e) => setPbrMetallic(Number(e.target.value) / 100)}
                      style={{ width: 130 }}
                      aria-label="Metallic"
                    />
                    <span style={{ fontFamily: 'monospace', width: 34, textAlign: 'right' }}>{Math.round(pbrMetallic * 100)}%</span>
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: '#1c2733' }}>
                    <span style={{ color: '#5a6b7b', width: 64 }}>Roughness</span>
                    <input
                      type="range" min={0} max={100} step={1} value={Math.round(pbrRoughness * 100)}
                      onChange={(e) => setPbrRoughness(Number(e.target.value) / 100)}
                      style={{ width: 130 }}
                      aria-label="Roughness"
                    />
                    <span style={{ fontFamily: 'monospace', width: 34, textAlign: 'right' }}>{Math.round(pbrRoughness * 100)}%</span>
                  </label>
                </div>
                <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 4 }}>
                  {pbrMetallic >= 0.7
                    ? 'Shiny metal — 0% roughness is a mirror, 30-50% is brushed steel.'
                    : pbrRoughness <= 0.25
                      ? 'Glossy plastic — low roughness gives strong highlights.'
                      : 'Classic matte plastic sits around 0% metallic / 85% roughness.'}
                </div>
              </div>
              <input
                ref={textureRef}
                type="file"
                accept="image/*"
                style={{ position: 'absolute', width: 1, height: 1, opacity: 0, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' }}
                onChange={(e) => {
                  const f = e.target.files?.[0]
                  if (f) applyTexture(f)
                  e.target.value = ''
                }}
              />
            </div>
          )}
          {/* pricing — free for everyone, or Tix; ★ Limited marks a collectible */}
          <div style={{ border: '1px solid #dbe4ec', background: '#f8fbfe', padding: '8px 10px', marginBottom: 8 }}>
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>Price</div>
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center', fontSize: 11 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
                <input type="radio" name="priceMode" checked={priceMode === 'free'} onChange={() => setPriceMode('free')} />
                Free
              </label>
              <label style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
                <input type="radio" name="priceMode" checked={priceMode === 'paid'} onChange={() => setPriceMode('paid')} />
                Paid:
                <span style={{ color: '#5d4a0a', fontFamily: 'monospace' }}>T$</span>
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  max={1000000}
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                  disabled={priceMode !== 'paid'}
                  style={{ width: 90, fontSize: 11 }}
                  aria-label="Price in Tix"
                />
              </label>
              <label
                style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer', color: limited ? '#8a6d1a' : '#1c4e7c' }}
                title="Limited — a collectible badge for rare items"
              >
                <input type="checkbox" checked={limited} onChange={(e) => setLimited(e.target.checked)} />
                ★ Limited
              </label>
            </div>
            <div style={{ fontSize: 10, color: limited ? '#8a6d1a' : '#8ba0b3', marginTop: 4 }}>
              {limited
                ? priceMode === 'paid' && priceNum >= 1
                  ? `The ORIGINAL price is T$ ${priceNum.toLocaleString('en-US')} — it DOUBLES with every copy sold: T$ ${(priceNum * 2).toLocaleString('en-US')}, then T$ ${(priceNum * 4).toLocaleString('en-US')}...`
                  : 'Limiteds are collectibles — give yours a price of T$ 1 or more.'
                : priceMode === 'paid'
                  ? 'Buyers pay your price in Tix from their wallet.'
                  : 'Anyone can grab it for free.'}
            </div>
            {limited && (
              <div style={{ marginTop: 8, fontSize: 11, color: '#1c4e7c', display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <span>Stock (total copies ever):</span>
                <input
                  className="rb-input"
                  type="number"
                  min={1}
                  value={stockInput}
                  onChange={(e) => setStockInput(e.target.value)}
                  placeholder="unlimited"
                  style={{ width: 90, fontSize: 11 }}
                  aria-label="Limited stock"
                />
                <span style={{ fontSize: 10, color: '#8ba0b3' }}>
                  {stockInput.trim() === ''
                    ? 'empty = unlimited copies'
                    : `only ${stockInput} will ever exist — when they are gone, it is SOLD OUT forever`}
                </span>
              </div>
            )}
          </div>
          {groups.length > 0 && (
            <label style={{ display: 'block', fontSize: 11, color: '#1c4e7c', marginBottom: 8 }}>
              Publish as group
              <select className="rb-input" value={groupId} onChange={(e) => setGroupId(e.target.value)} style={{ width: '100%', fontSize: 11, marginTop: 2 }}>
                <option value="">— Just me (personal UGC) —</option>
                {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              </select>
            </label>
          )}
          {error && <div style={{ fontSize: 11, color: '#a81a13', marginBottom: 6 }}>{error}</div>}
          <button className="rb-btn rb-btn-green" type="submit" disabled={busy} style={{ fontSize: 11 }}>
            {busy ? (uploadNote || 'Publishing...') : 'Publish to Catalog'}
          </button>
          <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 6 }}>
            Publishing is free. You get the first copy automatically and can delete your own items any time.
          </div>
        </div>
      </form>

      {/* the 3D space: player model in the middle, creator places the item */}
      {editorOpen && modelBlob && (
        <PlacementEditor
          glb={modelBlob}
          textureUrl={textureUrl || undefined}
          color={textureUrl ? undefined : colorOn ? itemColor : undefined}
          metallic={pbrMetallic}
          roughness={pbrRoughness}
          onCancel={() => setEditorOpen(false)}
          onSave={onPlaced}
        />
      )}
    </div>
  )
}
