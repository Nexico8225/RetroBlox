'use client'

/* ================= Avatar Editor (/avatar) =================
   The avatar belongs to your RetroBlox ACCOUNT — not to any game.
   Change it here once and every RetroBlox game (through the platform
   API + Unity SDK) spawns you wearing exactly this. */

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import dynamic from 'next/dynamic'
import { useRetro, api, flash } from '@/lib/store'
import {
  BODY_ASSETS, HEAD_ASSETS, SHIRT_ASSETS, PANTS_ASSETS,
  resolveDefaultAsset,
  AVATAR_PART_KEYS, AVATAR_PART_LABELS,
  UGC_TYPES, UGC_TYPE_LABELS, ACCESSORY_KINDS, DEFAULT_AVATAR,
  FACE_SCALE_MIN, FACE_SCALE_MAX, FACE_SCALE_DEFAULT,
  ANIM_SLOTS, ANIM_SLOT_LABELS,
  type AvatarConfigT, type AvatarPartColorKey, type AvatarPartColors, type AssetInfo, type Placement, type AnimClipsT,
} from '@/lib/avatarAssets'
import { buildLook3D, type AvatarLook3D } from '@/lib/three/rig'

/* three.js view loads on demand, browser-only */
const Player3DView = dynamic(() => import('./Player3DView'), { ssr: false })
/** clean white item-only thumb for owned 3D UGC (no player/arrow baked shots) */
const ItemThumb3D = dynamic(() => import('./ItemThumb3D'), { ssr: false })

/* the classic body-color palette — BrickColor-flavoured retro shades */
const COLOR_PALETTE = [
  // the classic BrickColor set — the exact swatches the 2016 Body Colors
  // picker gave you (White, Medium stone grey, Black, Bright red, ...)
  '#F2F3F3', '#A3A2A5', '#635F62', '#1B2A35',
  '#C4281C', '#DA8541', '#F5CD30', '#D7C59A',
  '#CC8E69', '#694028', '#4B974B', '#80BBDB',
  '#0D69AC', '#6B327C', '#FF66CC', '#04AFEC',
  // plus the site's own classic body colors
  '#FFD34E', '#B8C4CE', '#7EC855', '#E8845C',
]

interface InvEntry {
  itemId: string
  assetId: string
  name: string
  type: string
  imageFileId: string
  modelFileId: string | null
  textureFileId?: string | null
  baseColor?: string | null
  placement: Placement | null
  animClips?: AnimClipsT | null
  bundleParts?: string[] | null
  hasRig?: boolean
  groupName: string | null
  acquiredAt: string
}

export function AvatarView() {
  const { setToast } = useRetro()
  const [cfg, setCfg] = useState<AvatarConfigT | null>(null)
  const [inventory, setInventory] = useState<InvEntry[]>([])
  const [savedFlash, setSavedFlash] = useState(false)
  const [busy, setBusy] = useState(false)
  const [viewTab, setViewTab] = useState<'3d' | '2d'>('3d')
  const [colorPart, setColorPart] = useState<AvatarPartColorKey>('head')
  // editor sections live in two tabs — Colors (paint) / UGC (owned items).
  // Inside UGC there are category sub-tabs like the Catalog's (All, Faces,
  // Hats, Back, ...).
  const [pickTab, setPickTab] = useState<'colors' | 'ugc'>('colors')
  const [ugcSub, setUgcSub] = useState<string>('all')

  const load = useCallback(async () => {
    try {
      const res = await api<{ avatar: { body: string; head: string; shirt: string; pants: string; accessories: string[]; colors?: AvatarPartColors | null; faceScale?: number; bundle?: string | null; animPack?: string | null }; inventory: InvEntry[] }>('/api/me/avatar')
      setCfg({
        bodyAssetId: res.avatar.body,
        headAssetId: res.avatar.head,
        shirtAssetId: res.avatar.shirt,
        pantsAssetId: res.avatar.pants,
        accessories: res.avatar.accessories || [],
        colors: res.avatar.colors || {},
        faceScale: typeof res.avatar.faceScale === 'number' ? res.avatar.faceScale : FACE_SCALE_DEFAULT,
        bundleAssetId: res.avatar.bundle || '',
        animPackAssetId: res.avatar.animPack || '',
      })
      setInventory((res.inventory || []).map((e: InvEntry) => ({
        ...e,
        modelFileId: e.modelFileId || null,
        placement: e.placement || null,
      })))
    } catch {
      flash(setToast, 'Could not load your avatar.')
    }
  }, [setToast])

  useEffect(() => { load() }, [load])

  // every asset id this account can resolve (defaults + owned UGC)
  const ownedMap = useMemo(() => {
    const m = new Map<string, AssetInfo>()
    for (const e of inventory) {
      m.set(e.assetId, {
        assetId: e.assetId,
        kind: e.type as AssetInfo['kind'],
        name: e.name,
        imageUrl: `/api/files/${e.imageFileId}`,
        modelUrl: e.modelFileId ? `/api/files/${e.modelFileId}` : undefined,
        textureUrl: e.textureFileId ? `/api/files/${e.textureFileId}` : undefined,
        color: e.baseColor || undefined,
        placement: e.placement,
        animClips: e.animClips || undefined,
        bundleParts: e.bundleParts || undefined,
        hasRig: e.hasRig,
        itemId: e.itemId,
      })
    }
    return m
  }, [inventory])

  const resolve = useCallback(
    (assetId: string): AssetInfo | null => resolveDefaultAsset(assetId) || ownedMap.get(assetId) || null,
    [ownedMap]
  )

  // the SAME outfit as the player model — shown from a locked front camera,
  // which IS the site's 2D render (no orbiting, no special pose)
  const look3d = useMemo<AvatarLook3D | null>(
    () => (cfg ? buildLook3D(cfg, resolve) : null),
    [cfg, resolve]
  )

  /* the ACTIVE ANIMATION PACK plays in realtime on the preview — its mapped
     clips take over the classic idle / walk / jump / climb / fall */
  const animPackEntry = useMemo(
    () => (cfg?.animPackAssetId ? inventory.find((e) => e.assetId === cfg.animPackAssetId) : undefined),
    [cfg?.animPackAssetId, inventory]
  )
  const previewAnim = useMemo(() => {
    if (!animPackEntry?.modelFileId || !animPackEntry.animClips) return null
    const map = animPackEntry.animClips.map || {}
    const mapped = ANIM_SLOTS.map((s) => map[s]).filter(Boolean) as string[]
    const rest = (animPackEntry.animClips.clips || []).filter((c) => !mapped.includes(c))
    const clips = [...mapped, ...rest].slice(0, 6)
    return clips.length > 0 ? { url: `/api/files/${animPackEntry.modelFileId}`, clips, single: false } : null
  }, [animPackEntry])

  /* emote playback — click an owned emote and it performs on your avatar */
  const [playingEmote, setPlayingEmote] = useState<InvEntry | null>(null)
  const [emoteClip, setEmoteClip] = useState('')

  if (!cfg) return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading your avatar...</div>

  /** the classic color a part falls back to (before any Body Colors override) */
  function partBaseColor(key: AvatarPartColorKey): string {
    if (key === 'torso') return resolve(cfg!.shirtAssetId)?.color || '#2E7DC4'
    if (key === 'legL' || key === 'legR') return resolve(cfg!.pantsAssetId)?.color || '#39516B'
    return resolve(cfg!.bodyAssetId)?.color || '#FFD34E'
  }
  const partEffective = (key: AvatarPartColorKey): string => cfg.colors?.[key] || partBaseColor(key)

  function setPartColor(key: AvatarPartColorKey, hex: string) {
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return
    patch({ colors: { ...(cfg!.colors || {}), [key]: hex.toLowerCase() } })
  }
  function clearPartColor(key: AvatarPartColorKey) {
    const next = { ...(cfg!.colors || {}) }
    delete next[key]
    patch({ colors: next })
  }

  /** the screen color picker (Chrome/Edge EyeDropper) — a real eyedropper,
   *  with an honest message on browsers that don't ship it */
  async function pickFromScreen() {
    const EyeDropperCtor = (window as unknown as {
      EyeDropper?: new () => { open(): Promise<{ sRGBHex: string }> }
    }).EyeDropper
    if (!EyeDropperCtor) {
      flash(setToast, 'Screen picking needs Chrome or Edge — use the palette or the color wheel here.', 3600)
      return
    }
    try {
      const res = await new EyeDropperCtor().open()
      if (res?.sRGBHex) setPartColor(colorPart, res.sRGBHex)
    } catch {
      /* the player cancelled the eyedropper — nothing to do */
    }
  }

  function patch(p: Partial<AvatarConfigT>) {
    setCfg((c) => (c ? { ...c, ...p } : c))
    setSavedFlash(false)
  }

  function toggleAccessory(assetId: string) {
    const worn = cfg!.accessories.includes(assetId)
    if (worn) patch({ accessories: cfg!.accessories.filter((a) => a !== assetId) })
    else if (cfg!.accessories.length >= 6) flash(setToast, 'Six accessories max — take one off first.')
    else patch({ accessories: [...cfg!.accessories, assetId] })
  }

  async function save() {
    setBusy(true)
    try {
      await api('/api/me/avatar', { method: 'PUT', body: JSON.stringify(cfg) })
      setSavedFlash(true)
      flash(setToast, 'Avatar saved — every RetroBlox game sees this now!')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Save failed')
    } finally {
      setBusy(false)
    }
  }

  const ownedByType = (t: string) => inventory.filter((e) => e.type === t)

  /* UGC icons render BIG (the 52px chips were too small to read 3D thumbs) */
  const CHIP = 96

  const chipStyle = (active: boolean): React.CSSProperties => ({
    width: CHIP,
    height: CHIP,
    border: active ? '2px solid #1c6bb5' : '1px solid #8ba0b3',
    background: active ? '#dbeaf7' : '#fff',
    cursor: 'pointer',
    padding: 3,
    position: 'relative',
    boxShadow: active ? '0 0 0 2px #a8cbe8' : 'none',
    overflow: 'hidden',
  })

  /** a classic built-in chip (bodies / faces / shirts / pants) */
  const builtinChip = (assetId: string, active: boolean, onClick: () => void) => {
    const info = resolveDefaultAsset(assetId)
    return (
      <button
        key={assetId}
        type="button"
        aria-pressed={active}
        onClick={onClick}
        title={`${info?.name || assetId} (${assetId})`}
        style={chipStyle(active)}
      >
        {info?.color ? (
          <span style={{ width: '100%', height: '100%', background: info.color, border: '1px solid rgba(0,0,0,.25)', display: 'block' }} />
        ) : info?.imageUrl ? (
          <img src={info.imageUrl} alt={info.name} style={{ width: '100%', height: '100%', objectFit: 'contain', background: '#fff' }} />
        ) : null}
      </button>
    )
  }

  /** is a piece of owned UGC currently worn? */
  const wornState = (e: InvEntry): boolean => {
    if (e.type === 'face') return cfg!.headAssetId === e.assetId
    if (e.type === 'shirt') return cfg!.shirtAssetId === e.assetId
    if (e.type === 'pants') return cfg!.pantsAssetId === e.assetId
    if (e.type === 'bundle') return cfg!.bundleAssetId === e.assetId
    if (e.type === 'anim') return cfg!.animPackAssetId === e.assetId
    return cfg!.accessories.includes(e.assetId)
  }

  /** click any owned item: faces/shirts/pants take their slot (click again
   *  for the classic default), bundles/anims toggle on/off, emotes PLAY,
   *  accessory-style items toggle on/off */
  function toggleOwnedItem(e: InvEntry) {
    if (e.type === 'face') {
      patch({ headAssetId: cfg!.headAssetId === e.assetId ? DEFAULT_AVATAR.headAssetId : e.assetId })
    } else if (e.type === 'shirt') {
      patch({ shirtAssetId: cfg!.shirtAssetId === e.assetId ? DEFAULT_AVATAR.shirtAssetId : e.assetId })
    } else if (e.type === 'pants') {
      patch({ pantsAssetId: cfg!.pantsAssetId === e.assetId ? DEFAULT_AVATAR.pantsAssetId : e.assetId })
    } else if (e.type === 'bundle') {
      // bundles REPLACE the body — one at a time; click again = classic body
      patch({ bundleAssetId: cfg!.bundleAssetId === e.assetId ? '' : e.assetId })
    } else if (e.type === 'anim') {
      // the active pack's clips play in realtime instead of the classic moves
      patch({ animPackAssetId: cfg!.animPackAssetId === e.assetId ? '' : e.assetId })
    } else if (e.type === 'emote') {
      // emotes aren't worn — they perform. Open the player.
      setPlayingEmote(e)
      setEmoteClip(e.animClips?.clips?.[0] || '')
    } else if (ACCESSORY_KINDS.includes(e.type)) {
      toggleAccessory(e.assetId)
    }
  }

  function clickBuiltinSlot(slotKey: 'bodyAssetId' | 'headAssetId' | 'shirtAssetId' | 'pantsAssetId', id: string) {
    patch({ [slotKey]: cfg![slotKey] === id ? DEFAULT_AVATAR[slotKey] : id } as Partial<AvatarConfigT>)
  }

  /** an owned UGC chip — big, with the live 3D thumb + type tag + ON badge */
  const ugcChip = (e: InvEntry, showType = false) => {
    const worn = wornState(e)
    return (
      <button
        key={e.itemId}
        type="button"
        onClick={() => toggleOwnedItem(e)}
        aria-pressed={worn}
        title={`${e.name} (${e.assetId})${e.groupName ? ` · by ${e.groupName}` : ''}`}
        style={chipStyle(worn)}
      >
        <img
          src={`/api/files/${e.imageFileId}`}
          alt={e.name}
          style={{ width: '100%', height: '100%', objectFit: e.modelFileId ? 'contain' : 'cover', background: '#fff' }}
          onError={(ev) => { (ev.target as HTMLImageElement).style.visibility = 'hidden' }}
        />
        {e.modelFileId && (
          <ItemThumb3D
            modelUrl={`/api/files/${e.modelFileId}`}
            placement={e.placement}
            alt={e.name}
            textureUrl={e.textureFileId ? `/api/files/${e.textureFileId}` : undefined}
            color={e.baseColor || undefined}
            style={{ position: 'absolute', inset: 3, width: 'calc(100% - 6px)', height: 'calc(100% - 6px)', objectFit: 'contain', background: '#fff' }}
          />
        )}
        {showType && (
          <span
            style={{
              position: 'absolute', top: 0, left: 0, fontSize: 8,
              background: 'rgba(28,78,124,.88)', color: '#fff', padding: '1px 4px',
            }}
          >
            {UGC_TYPE_LABELS[e.type] || e.type}
          </span>
        )}
        {worn && (
          <span style={{ position: 'absolute', bottom: -1, right: -1, fontSize: 9, background: '#1c6bb5', color: '#fff', padding: '0 3px' }}>
            ON
          </span>
        )}
      </button>
    )
  }

  /* UGC tab sub-tabs — the SAME categories the Catalog has */
  const SUB_TABS: [string, string][] = [
    ['all', 'All'],
    ...UGC_TYPES.map((t) => [t, UGC_TYPE_LABELS[t] || t] as [string, string]),
  ]
  const SLOT_SUBS: Record<string, {
    slotKey: 'headAssetId' | 'shirtAssetId' | 'pantsAssetId'
    builtins: { assetId: string; color?: string }[]
    label: string
  }> = {
    face: { slotKey: 'headAssetId', builtins: HEAD_ASSETS, label: 'Faces' },
    shirt: { slotKey: 'shirtAssetId', builtins: SHIRT_ASSETS, label: 'Shirts' },
    pants: { slotKey: 'pantsAssetId', builtins: PANTS_ASSETS, label: 'Pants' },
  }
  const subDef = SLOT_SUBS[ugcSub] || null
  const subLabel = ugcSub === 'all' ? 'Everything you own' : (UGC_TYPE_LABELS[ugcSub] || ugcSub)
  const subItems = ugcSub === 'all'
    ? UGC_TYPES.flatMap((t) => ownedByType(t))
    : ownedByType(ugcSub)

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Avatar Editor</span></div>
        <div style={{ padding: 12, fontSize: 11, color: '#41586c' }}>
          Your look belongs to your RetroBlox account, not to one game. Dress up here and every
          RetroBlox game spawns you like this — the player fetches it from the platform the moment you press play.
        </div>
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'flex-start' }}>
        {/* preview — big, with a 3D tab (orbit it) and a 2D tab (the locked
            front render). Both are the REAL player model. */}
        <div className="rb-box" style={{ width: 360, flexShrink: 0 }}>
          <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span>Preview</span>
            <span style={{ display: 'flex', gap: 3 }} role="tablist" aria-label="Preview view">
              {(['3d', '2d'] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  role="tab"
                  aria-selected={viewTab === t}
                  onClick={() => setViewTab(t)}
                  className="rb-btn"
                  style={{
                    fontSize: 10, padding: '1px 10px',
                    background: viewTab === t ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#fff',
                    color: viewTab === t ? '#fff' : '#1c4e7c',
                  }}
                >
                  {t === '3d' ? '3D' : '2D'}
                </button>
              ))}
            </span>
          </div>
          <div style={{ padding: 10, textAlign: 'center' }}>
            {look3d ? (
              <div style={{ border: '1px solid #b7c6d4' }}>
                {viewTab === '3d' ? (
                  <Player3DView key="3d" look={look3d} height={520} interactive anim={previewAnim} />
                ) : (
                  <Player3DView key="2d" look={look3d} height={520} flat anim={previewAnim} />
                )}
              </div>
            ) : (
              <div style={{ padding: 60, color: '#5a6b7b', fontSize: 11 }}>Loading your look...</div>
            )}
            <div style={{ fontSize: 9, color: '#8ba0b3', marginTop: 6 }}>
              {viewTab === '3d'
                ? '3D — drag to spin the camera, scroll to zoom'
                : '2D — the same model, locked straight to the front'}
            </div>
            {previewAnim && animPackEntry && (
              <div style={{ fontSize: 10, color: '#8a6d1a', background: '#fff8e8', border: '1px solid #e0c98a', padding: '3px 6px', marginTop: 6 }}>
                ▶ {animPackEntry.name} active — its moves play live (idle → walk → jump…)
              </div>
            )}
            {look3d?.bundle && (
              <div style={{ fontSize: 10, color: '#1c4e7c', background: '#eaf2f9', border: '1px solid #b7c6d4', padding: '3px 6px', marginTop: 4 }}>
                Bundle worn — the classic body parts it replaces are hidden.
              </div>
            )}
            <div style={{ fontSize: 10, color: '#7b8896', marginTop: 2, fontFamily: 'monospace' }}>
              body:{cfg.bodyAssetId} head:{cfg.headAssetId}
            </div>
            <button className="rb-btn rb-btn-green" style={{ width: '100%', marginTop: 8 }} disabled={busy} onClick={save}>
              {busy ? 'Saving...' : savedFlash ? '✓ Saved' : 'Save Avatar'}
            </button>
          </div>
        </div>

        {/* pickers — two tabs: Colors (paint) / UGC (owned items, with
            category sub-tabs like the Catalog: All, Faces, Hats, Back...) */}
        <div className="rb-box" style={{ flex: 1, minWidth: 280 }}>
          <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span>Customize</span>
            <span style={{ display: 'flex', gap: 3 }} role="tablist" aria-label="Editor sections">
              {([['colors', 'Colors'], ['ugc', 'UGC']] as const).map(([t, label]) => (
                <button
                  key={t}
                  type="button"
                  role="tab"
                  aria-selected={pickTab === t}
                  onClick={() => setPickTab(t)}
                  className="rb-btn"
                  style={{
                    fontSize: 10, padding: '1px 12px',
                    background: pickTab === t ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#fff',
                    color: pickTab === t ? '#fff' : '#1c4e7c',
                  }}
                >
                  {label}
                </button>
              ))}
            </span>
          </div>
          <div style={{ padding: 12 }}>
            {pickTab === 'colors' && (
            <>
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>Body Colors <span style={{ color: '#8ba0b3' }}>(pick a part, then a color — or grab one straight off your screen)</span></div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 8 }}>
              {AVATAR_PART_KEYS.map((key) => {
                const active = colorPart === key
                const custom = !!cfg.colors?.[key]
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setColorPart(key)}
                    aria-pressed={active}
                    title={`${AVATAR_PART_LABELS[key]}${custom ? ` — custom ${cfg.colors![key]}` : ''}`}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 4,
                      border: active ? '2px solid #1c6bb5' : '1px solid #8ba0b3',
                      background: active ? '#dbeaf7' : '#fff',
                      fontSize: 10, color: '#41586c',
                      padding: '2px 7px', cursor: 'pointer',
                    }}
                  >
                    <span style={{ width: 11, height: 11, background: partEffective(key), border: '1px solid rgba(0,0,0,.3)', display: 'inline-block' }} />
                    {AVATAR_PART_LABELS[key]}
                    {custom && <span style={{ color: '#1c6bb5', fontSize: 8 }}>•</span>}
                  </button>
                )
              })}
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 8 }}>
              {COLOR_PALETTE.map((hex) => (
                <button
                  key={hex}
                  type="button"
                  onClick={() => setPartColor(colorPart, hex)}
                  title={hex}
                  aria-label={`Paint ${AVATAR_PART_LABELS[colorPart]} ${hex}`}
                  style={{
                    width: 22, height: 22, background: hex,
                    border: partEffective(colorPart).toLowerCase() === hex.toLowerCase() ? '2px solid #1c6bb5' : '1px solid rgba(0,0,0,.35)',
                    cursor: 'pointer', padding: 0,
                  }}
                />
              ))}
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', marginBottom: 4 }}>
              <input
                type="color"
                value={partEffective(colorPart)}
                onChange={(e) => setPartColor(colorPart, e.target.value)}
                aria-label={`Custom color for ${AVATAR_PART_LABELS[colorPart]}`}
                style={{ width: 34, height: 24, padding: 0, border: '1px solid #8ba0b3', background: '#fff', cursor: 'pointer' }}
              />
              <input
                className="rb-input"
                type="text"
                value={cfg.colors?.[colorPart] || ''}
                placeholder={`#${partBaseColor(colorPart).slice(1)} default`}
                onChange={(e) => setPartColor(colorPart, e.target.value.startsWith('#') ? e.target.value : `#${e.target.value}`)}
                style={{ width: 86, fontSize: 10, fontFamily: 'monospace' }}
                maxLength={7}
                aria-label={`Hex color for ${AVATAR_PART_LABELS[colorPart]}`}
              />
              <button className="rb-btn" style={{ fontSize: 10 }} onClick={pickFromScreen} title="Pick any color from anywhere on your screen">
                ⛶ Pick from screen
              </button>
              {cfg.colors?.[colorPart] && (
                <button className="rb-btn" style={{ fontSize: 10 }} onClick={() => clearPartColor(colorPart)}>
                  ↺ Reset {AVATAR_PART_LABELS[colorPart]}
                </button>
              )}
            </div>
            <div style={{ fontSize: 9, color: '#8ba0b3', marginBottom: 14 }}>
              Custom colors save with your avatar and show up in every game through the player system.
            </div>

            {/* the classic body presets live here too — they ARE body colors */}
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>
              Classic Body <span style={{ color: '#8ba0b3' }}>(click the worn one to go back to the classic look)</span>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {BODY_ASSETS.map((b) =>
                builtinChip(b.assetId, cfg.bodyAssetId === b.assetId, () => clickBuiltinSlot('bodyAssetId', b.assetId))
              )}
            </div>
            </>
            )}

            {pickTab === 'ugc' && (
            <>
            {/* category sub-tabs — the same categories the Catalog has */}
            <div role="tablist" aria-label="UGC categories" style={{ display: 'flex', flexWrap: 'wrap', gap: 3, marginBottom: 12 }}>
              {SUB_TABS.map(([t, label]) => (
                <button
                  key={t}
                  type="button"
                  role="tab"
                  aria-selected={ugcSub === t}
                  onClick={() => setUgcSub(t)}
                  className="rb-btn"
                  style={{
                    fontSize: 10, padding: '1px 8px',
                    background: ugcSub === t ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#fff',
                    color: ugcSub === t ? '#fff' : '#1c4e7c',
                  }}
                >
                  {label}
                </button>
              ))}
            </div>

            {/* faces: the classic size slider lives with the face items */}
            {ugcSub === 'face' && (
            <>
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>
              Face size <span style={{ color: '#8ba0b3' }}>(scales the face on your head — games see the same size)</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12, flexWrap: 'wrap' }}>
              <input
                type="range"
                min={FACE_SCALE_MIN}
                max={FACE_SCALE_MAX}
                step={0.05}
                value={cfg.faceScale || FACE_SCALE_DEFAULT}
                onChange={(e) => patch({ faceScale: Number(e.target.value) })}
                style={{ flex: 1, minWidth: 140, accentColor: '#2a6cad' }}
                aria-label="Face size"
              />
              <span style={{ fontFamily: 'monospace', fontSize: 11, color: '#41586c', minWidth: 34, textAlign: 'right' }}>
                {(cfg.faceScale || FACE_SCALE_DEFAULT).toFixed(2)}×
              </span>
              {Math.abs((cfg.faceScale || FACE_SCALE_DEFAULT) - FACE_SCALE_DEFAULT) > 0.001 && (
                <button
                  className="rb-btn"
                  style={{ fontSize: 10 }}
                  onClick={() => patch({ faceScale: FACE_SCALE_DEFAULT })}
                >
                  ↺ Classic size
                </button>
              )}
            </div>
            </>
            )}

            {/* classic built-ins for slot categories (Faces / Shirts / Pants) */}
            {subDef && (
              <div style={{ marginBottom: 14 }}>
                <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 5 }}>Classic {subDef.label}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                  {subDef.builtins.map((b) =>
                    builtinChip(b.assetId, cfg[subDef.slotKey] === b.assetId, () => clickBuiltinSlot(subDef.slotKey, b.assetId))
                  )}
                </div>
              </div>
            )}

            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>
              {subDef ? 'Your' : ''} {subLabel}
              {ugcSub === 'bundle' ? (
                <span style={{ color: '#8ba0b3' }}> — click to wear the bundle (it replaces your body), click again for the classic body</span>
              ) : ugcSub === 'anim' ? (
                <span style={{ color: '#8ba0b3' }}> — click to activate; its clips play live as your idle/walk/jump/climb</span>
              ) : ugcSub === 'emote' ? (
                <span style={{ color: '#8ba0b3' }}> — click to PLAY it on your avatar right now</span>
              ) : ACCESSORY_KINDS.includes(ugcSub) || ugcSub === 'all' ? (
                <span style={{ color: '#8ba0b3' }}> — click to wear, click again to take off (6 accessories max)</span>
              ) : (
                <span style={{ color: '#8ba0b3' }}> — click to wear, click again for the classic one</span>
              )}
            </div>
            {subItems.length === 0 ? (
              <div style={{ fontSize: 11, color: '#7b8896', padding: '4px 0' }}>
                {inventory.length === 0 ? 'Nothing in your inventory yet. ' : `No ${subLabel.toLowerCase()} in your inventory yet. `}
                <Link href="/catalog" className="rb-link">Browse the Catalog</Link> — or publish your own!
              </div>
            ) : (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {subItems.map((e) => ugcChip(e, ugcSub === 'all'))}
              </div>
            )}
            {/* quick links for the rigged pipeline */}
            {['emote', 'bundle', 'anim'].includes(ugcSub) && (
              <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 10, lineHeight: 1.5 }}>
                {ugcSub === 'emote' && 'Emotes are rigged GLBs published from the Catalog\u2019s Publish form — upload a rig with an animation and it lands here.'}
                {ugcSub === 'bundle' && 'Bundles replace your body parts — publish one from the Catalog with a rigged body model.'}
                {ugcSub === 'anim' && 'Animation packs replace your REAL moves — animate the R6 template in Blender, map the clips at publish, and they play everywhere.'}
                {' '}<a className="rb-link" href="/models/retroblox-rig-template.glb" download>⬇ R6 rig template (.glb)</a>
              </div>
            )}
            </>
            )}
          </div>
        </div>
      </div>

      {/* emote player — the avatar performs the emote right here */}
      {playingEmote && look3d && (
        <div
          style={{
            position: 'fixed', inset: 0, zIndex: 90, background: 'rgba(20,32,44,0.72)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 14,
          }}
          role="dialog"
          aria-modal="true"
          aria-label={`Playing ${playingEmote.name}`}
          onClick={(e) => { if (e.target === e.currentTarget) setPlayingEmote(null) }}
        >
          <div className="rb-box" style={{ width: 'min(560px, 100%)', background: '#fff' }}>
            <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span>Playing: {playingEmote.name}</span>
              <button className="rb-btn" style={{ fontSize: 10, padding: '2px 8px' }} onClick={() => setPlayingEmote(null)}>✕</button>
            </div>
            <div style={{ padding: 12 }}>
              <Player3DView
                key={`${playingEmote.assetId}-${emoteClip}`}
                look={look3d}
                height={380}
                anim={playingEmote.modelFileId ? { url: `/api/files/${playingEmote.modelFileId}`, clips: [emoteClip || playingEmote.animClips?.clips?.[0] || ''], single: true } : null}
              />
              {(playingEmote.animClips?.clips?.length || 0) > 1 && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10 }}>
                  <span style={{ fontSize: 11, color: '#1c4e7c' }}>Clip:</span>
                  <select
                    className="rb-input"
                    value={emoteClip}
                    onChange={(e) => setEmoteClip(e.target.value)}
                    style={{ fontSize: 11, flex: 1 }}
                    aria-label="Emote clip"
                  >
                    {(playingEmote.animClips?.clips || []).map((c) => <option key={c} value={c}>{c}</option>)}
                  </select>
                </div>
              )}
              <div style={{ fontSize: 10, color: '#8ba0b3', marginTop: 8 }}>
                Every RetroBlox game can trigger this emote through the platform API — your avatar carries it everywhere.
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
