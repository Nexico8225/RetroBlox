/* ------------------------------------------------------------------
   RETROBLOX PLATFORM — AVATAR ASSET SYSTEM (R6 player model)
   The player model is the classic R6 rig (the same one shipped with
   the Unity SDK as Models/R6IK.fbx — Head / Torso / 2 Arms / 2 Legs):

     front view, 100x100 units:      part sizes (studs):
       HEAD   x41..59  y16..34       1.2 x 1.2
       TORSO  x35..65  y34..64       2   x 2
       ARM R  x20..35  y34..64       1   x 2   (character's right)
       ARM L  x65..80  y34..64       1   x 2   (character's left)
       LEG R  x35..50  y64..94       1   x 2
       LEG L  x50..65  y64..94       1   x 2

   UGC PLACEMENT IS SACRED: an item is rendered EXACTLY where its
   creator painted it on the official template — 1:1, no auto-offset,
   no auto-stacking. The templates are the coordinate system:
     hat / gear  -> 140x140 canvas == the 48x48 slot over the head
                    (R6 guide printed on it)  -> R6.HAT_SLOT
     t-shirt     -> 140x140 canvas == the 48x48 slot over the torso
                    -> R6.TSHIRT_SLOT
     face        -> 140x140 canvas == the head front, 1:1 -> R6.HEAD
     shirt       -> 300x190 canvas, zone-cropped onto torso + arms
                    -> SHIRT_TEMPLATE (RIGHT ARM | TORSO | LEFT ARM)
     pants       -> 220x190 canvas, zone-cropped onto both legs
                    -> PANTS_TEMPLATE (RIGHT LEG | LEFT LEG)

   The same library powers the website's avatar editor preview and the
   server-side asset service, so what you see on the site is exactly
   what games build through the Unity SDK.
------------------------------------------------------------------ */

export type AvatarKind =
  | 'body' | 'head' | 'shirt' | 'pants'
  | 'hat' | 'hair' | 'face' | 'gear' | 'tshirt'
  | 'accessory' | 'neck' | 'shoulder' | 'front' | 'waist'
  | 'emote' | 'bundle' | 'anim'

/**
 * Creator-placed transform for 3D UGC (hats / gear / accessories).
 * SACRED RULE: this is authored in the 3D placement editor by whoever
 * uploaded the model — p = position, r = rotation in DEGREES,
 * s = scale. Every renderer (site, 3D try-on, Unity SDK) applies it
 * EXACTLY as stored. Nothing ever auto-repositions or auto-fits a
 * creator's placement.
 */
export interface Placement {
  p: [number, number, number]
  r: [number, number, number] // degrees
  s: [number, number, number]
}

export function placementJson(p: Placement): string {
  return JSON.stringify(p)
}

export function parsePlacement(raw: string | null | undefined): Placement | null {
  if (!raw) return null
  try {
    const v = JSON.parse(raw) as Placement
    const ok =
      Array.isArray(v.p) && v.p.length === 3 &&
      Array.isArray(v.r) && v.r.length === 3 &&
      Array.isArray(v.s) && v.s.length === 3 &&
      [...v.p, ...v.r, ...v.s].every((n) => typeof n === 'number' && isFinite(n))
    return ok ? v : null
  } catch {
    return null
  }
}

export interface AssetInfo {
  assetId: string
  kind: AvatarKind
  name: string
  /** hex color for body / shirt / pants defaults */
  color?: string
  /** image (data URL or /api/files url) for faces, t-shirts, clothing and UGC thumbnails */
  imageUrl?: string
  /** 3D UGC only: GLB model url (data URL or /api/files url) */
  modelUrl?: string
  /** 3D UGC only: optional texture image wrapped around the model */
  textureUrl?: string
  /** 3D UGC only: PBR material overrides from the creator's sliders.
   *  null/absent = render exactly what the GLB carries; a number 0..1 =
   *  apply to every surface (the site renderer AND the Godot player). */
  metallic?: number | null
  roughness?: number | null
  /** 3D UGC only: where the creator left it in the placement editor */
  placement?: Placement | null
  /** emote / anim only: the GLB's clips (+ the idle/walk/jump/climb/fall map for anim packs) */
  animClips?: AnimClipsT | null
  /** emote / anim only: the creator's suggested preview context */
  animTarget?: AnimTargetT | null
  /** bundle only: which body parts it replaces */
  bundleParts?: string[] | null
  /** the GLB carries a rig — usable as an animation source */
  hasRig?: boolean
  /** UGC metadata (set for published items) */
  itemId?: string
  description?: string
  creatorId?: string
  creatorName?: string
  groupId?: string | null
  groupName?: string | null
  createdAt?: string
}

export interface AvatarConfigT {
  bodyAssetId: string
  headAssetId: string
  shirtAssetId: string
  pantsAssetId: string
  accessories: string[]
  /** advanced body colors, per R6 part — empty/missing = the classic defaults */
  colors?: AvatarPartColors
  /** face size multiplier — 1 = the classic look, up to 2 (huge), down to 0.5 (tiny) */
  faceScale?: number
  /** worn bundle — replaces body parts (null/'' = the classic blocky body) */
  bundleAssetId?: string | null
  /** active animation pack — clips replace idle/walk/jump/climb in realtime (null/'' = classic anims) */
  animPackAssetId?: string | null
}

/** face decal scale limits + the classic default */
export const FACE_SCALE_MIN = 0.5
export const FACE_SCALE_MAX = 2
export const FACE_SCALE_DEFAULT = 1

/** Only accept sane face scales — anything else falls back to the classic size. */
export function sanitizeFaceScale(raw: unknown): number {
  const n = typeof raw === 'number' ? raw : Number(raw)
  if (!Number.isFinite(n)) return FACE_SCALE_DEFAULT
  return Math.min(FACE_SCALE_MAX, Math.max(FACE_SCALE_MIN, Math.round(n * 100) / 100))
}

/** Custom colors per body part (the classic "Body Colors" panel).
 *  Keys are R6 parts; every value is a validated #RRGGBB hex color.
 *  Parts left out keep the classic look (skin / shirt / pants colors). */
export type AvatarPartColorKey = 'head' | 'torso' | 'armL' | 'armR' | 'legL' | 'legR'
export type AvatarPartColors = Partial<Record<AvatarPartColorKey, string>>
export const AVATAR_PART_KEYS: AvatarPartColorKey[] = ['head', 'torso', 'armL', 'armR', 'legL', 'legR']
export const AVATAR_PART_LABELS: Record<AvatarPartColorKey, string> = {
  head: 'Head',
  torso: 'Torso',
  armL: 'Left Arm',
  armR: 'Right Arm',
  legL: 'Left Leg',
  legR: 'Right Leg',
}

/** Only allow real hex colors — anything else is dropped. */
export function sanitizePartColors(raw: unknown): AvatarPartColors {
  const out: AvatarPartColors = {}
  if (!raw || typeof raw !== 'object') return out
  for (const key of AVATAR_PART_KEYS) {
    const v = (raw as Record<string, unknown>)[key]
    if (typeof v === 'string' && /^#[0-9a-fA-F]{6}$/.test(v)) out[key] = v.toLowerCase()
  }
  return out
}

export const DEFAULT_AVATAR: AvatarConfigT = {
  bodyAssetId: 'body_01',
  headAssetId: 'head_01',
  shirtAssetId: 'shirt_01',
  pantsAssetId: 'pants_01',
  accessories: [],
}

/* ---------------- R6 player model geometry (see header) ---------------- */

export interface Rect { x: number; y: number; w: number; h: number }

/** Front view of the R6 rig inside the 100x100 preview box. */
export const R6: Record<string, Rect> = {
  HEAD: { x: 41, y: 16, w: 18, h: 18 },
  TORSO: { x: 35, y: 34, w: 30, h: 30 },
  ARM_R: { x: 20, y: 34, w: 15, h: 30 }, // character's right (viewer's left)
  ARM_L: { x: 65, y: 34, w: 15, h: 30 }, // character's left  (viewer's right)
  LEG_R: { x: 35, y: 64, w: 15, h: 30 },
  LEG_L: { x: 50, y: 64, w: 15, h: 30 },
  /** the face decal — 62% of the head front at scale 1 (the classic face
   *  size, matching the 3D renderer and the Unity SDK quad). The avatar
   *  editor's face-size slider scales this rect around its center. */
  FACE: { x: 44.4, y: 19.4, w: 11.2, h: 11.2 },
  /** placement-respecting slots: official 140x140 template maps 1:1 into these */
  HAT_SLOT: { x: 26, y: 1, w: 48, h: 48 }, // centred on the head
  TSHIRT_SLOT: { x: 26, y: 25, w: 48, h: 48 }, // centred on the torso
}

/** Classic Roblox-style clothing templates — zones are cropped onto parts. */
export const SHIRT_TEMPLATE = {
  w: 300,
  h: 190,
  armR: { x: 10, y: 30, w: 60, h: 120 },
  torso: { x: 80, y: 30, w: 120, h: 120 },
  armL: { x: 210, y: 30, w: 60, h: 120 },
}
export const PANTS_TEMPLATE = {
  w: 220,
  h: 190,
  legR: { x: 30, y: 30, w: 60, h: 120 },
  legL: { x: 120, y: 30, w: 60, h: 120 },
}

/* ---------------- default (built-in) assets ---------------- */

const BODY_COLORS: [string, string][] = [
  ['body_01', '#FFD34E'], // Classic — the original 2006 yellow
  ['body_02', '#B8C4CE'], // Grey blockhead
  ['body_03', '#7EC855'], // Green
  ['body_04', '#5CA6D8'], // Blue
  ['body_05', '#E8845C'], // Brick orange
  ['body_06', '#C88FD6'], // Lavender
]

const SHIRT_COLORS: [string, string][] = [
  ['shirt_01', '#2E7DC4'], // Classic blue tee
  ['shirt_02', '#43B85A'], // Green tee
  ['shirt_03', '#C74A42'], // Red tee
  ['shirt_04', '#6B4FA3'], // Purple tee
  ['shirt_05', '#3B4754'], // Charcoal tee
]

const PANTS_COLORS: [string, string][] = [
  ['pants_01', '#39516B'], // Denim
  ['pants_02', '#2F6B3C'], // Green cargo
  ['pants_03', '#4A4A4A'], // Black jeans
  ['pants_04', '#7A5230'], // Brown pants
]

export const BODY_ASSETS = BODY_COLORS.map(([id, c]) => ({ assetId: id, color: c }))
export const SHIRT_ASSETS = SHIRT_COLORS.map(([id, c]) => ({ assetId: id, color: c }))
export const PANTS_ASSETS = PANTS_COLORS.map(([id, c]) => ({ assetId: id, color: c }))

/* classic blocky faces — head_01 is the OFFICIAL default face (the classic
   smile the owner uploaded, served from /retro/default-face.png), the others
   are drawn as square SVG (transparent background) so they fill the R6 head
   front 1:1 */
const DEFAULT_FACE_URL = '/retro/default-face.png'

function faceSvg(kind: 'smile' | 'chill' | 'grin'): string {
  const parts =
    kind === 'smile'
      ? `<circle cx="14" cy="15" r="2.4" fill="#1a1a1a"/><circle cx="26" cy="15" r="2.4" fill="#1a1a1a"/><path d="M 13 24 Q 20 30 27 24" stroke="#1a1a1a" stroke-width="2.4" fill="none" stroke-linecap="round"/>`
      : kind === 'chill'
        ? `<path d="M 10 14 h 8 M 22 14 h 8" stroke="#1a1a1a" stroke-width="2.6" stroke-linecap="round"/><path d="M 14 24 Q 20 29 26 24" stroke="#1a1a1a" stroke-width="2.4" fill="none" stroke-linecap="round"/>`
        : `<circle cx="14" cy="14" r="2.6" fill="#1a1a1a"/><circle cx="26" cy="14" r="2.6" fill="#1a1a1a"/><path d="M 11 22 Q 20 34 29 22 Z" fill="#1a1a1a"/>`
  return `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">${parts}</svg>`
}

export const HEAD_ASSETS = [
  { assetId: 'head_01', name: 'Classic Smile', face: 'default' as const },
  { assetId: 'head_02', name: 'Chill', face: 'chill' as const },
  { assetId: 'head_03', name: 'Big Grin', face: 'grin' as const },
]

export function faceImageUrl(assetId: string): string {
  const head = HEAD_ASSETS.find((h) => h.assetId === assetId)
  // the official default smile is a real PNG so the site, the catalog and the
  // Unity SDK all download the exact same art
  if (!head || head.face === 'default') return DEFAULT_FACE_URL
  const svg = faceSvg(head.face)
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`
}

/* ---------------- id parsing / resolution ---------------- */

export function parseAssetId(assetId: string): { kind: AvatarKind; num: number } | null {
  const m = /^(body|head|shirt|pants|hat|hair|face|gear|tshirt|accessory|neck|shoulder|front|waist|emote|bundle|anim)_(\d+)$/.exec(assetId || '')
  if (!m) return null
  return { kind: m[1] as AvatarKind, num: parseInt(m[2], 10) }
}

/** Resolve a BUILT-IN asset id to its color / face image (no database needed). */
export function resolveDefaultAsset(assetId: string): AssetInfo | null {
  const body = BODY_COLORS.find(([id]) => id === assetId)
  if (body) return { assetId: body[0], kind: 'body', name: bodyName(body[0]), color: body[1] }
  const shirt = SHIRT_COLORS.find(([id]) => id === assetId)
  if (shirt) return { assetId: shirt[0], kind: 'shirt', name: shirtName(shirt[0]), color: shirt[1] }
  const pants = PANTS_COLORS.find(([id]) => id === assetId)
  if (pants) return { assetId: pants[0], kind: 'pants', name: pantsName(pants[0]), color: pants[1] }
  const head = HEAD_ASSETS.find((h) => h.assetId === assetId)
  if (head) return { assetId: head.assetId, kind: 'head', name: head.name, imageUrl: faceImageUrl(head.assetId) }
  return null
}

function bodyName(id: string) {
  const i = BODY_COLORS.findIndex(([x]) => x === id)
  return ['Classic Yellow', 'Grey Blockhead', 'Green', 'Blue', 'Brick Orange', 'Lavender'][i] || id
}
function shirtName(id: string) {
  const i = SHIRT_COLORS.findIndex(([x]) => x === id)
  return ['Classic Blue Tee', 'Green Tee', 'Red Tee', 'Purple Tee', 'Charcoal Tee'][i] || id
}
function pantsName(id: string) {
  const i = PANTS_COLORS.findIndex(([x]) => x === id)
  return ['Denim Jeans', 'Green Cargo', 'Black Jeans', 'Brown Pants'][i] || id
}

export const UGC_TYPES: AvatarKind[] = [
  'hat', 'hair', 'face', 'accessory', 'neck', 'shoulder', 'front', 'waist',
  'gear', 'tshirt', 'shirt', 'pants', 'emote', 'bundle', 'anim',
]
export const UGC_TYPE_LABELS: Record<string, string> = {
  hat: 'Hats',
  hair: 'Hair',
  accessory: 'Back',
  neck: 'Neck',
  shoulder: 'Shoulder',
  front: 'Front',
  waist: 'Waist',
  gear: 'Gear',
  tshirt: 'T-Shirts',
  shirt: 'Shirts',
  pants: 'Pants',
  face: 'Faces',
  emote: 'Emotes',
  bundle: 'Bundles',
  anim: 'Animations',
}

/* ------------------------------------------------------------------
   RIGGED UGC — emotes, bundles, animation packs (the Blender pipeline)
   Every one of these is a GLB exported from Blender carrying a rig:
     emote  -> one (or more) clips; playing it makes the character do the move
     bundle -> a full body model that REPLACES the player's body parts
     anim   -> clips mapped onto the REAL idle / walk / jump / climb / fall
               slots — they play in realtime, exactly like the classic moves
   Clips come from Blender by name; the R6 template
   (/models/retroblox-rig-template.glb) has the canonical part names
   (Head / Torso / Left Arm / Right Arm / Left Leg / Right Leg) so a
   template-animated clip retargets straight onto the player model.
------------------------------------------------------------------ */

/** types published as a rigged GLB (rig + animations, no placement editor) */
export const RIGGED_TYPES: string[] = ['emote', 'bundle', 'anim']
export const isRiggedType = (t: string) => RIGGED_TYPES.includes(t)

/** the realtime animation slots an anim pack can override */
export const ANIM_SLOTS = ['idle', 'walk', 'jump', 'climb', 'fall'] as const
export type AnimSlot = (typeof ANIM_SLOTS)[number]
export const ANIM_SLOT_LABELS: Record<AnimSlot, string> = {
  idle: 'Idle', walk: 'Walk', jump: 'Jump', climb: 'Climb', fall: 'Fall',
}

/** clip data stored on an emote / anim item */
export interface AnimClipsT {
  /** every clip name found in the GLB */
  clips: string[]
  /** anim packs only: slot -> clip name (a subset is fine; unmapped slots keep the classic move) */
  map?: Partial<Record<AnimSlot, string>>
}

/** the creator's suggested preview context for an emote / anim pack:
 *  play it on the normal avatar, on a bundle, or wearing a marketplace UGC item */
export interface AnimTargetT {
  kind: 'avatar' | 'bundle' | 'ugc'
  assetId?: string
}

function clipNameOk(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && v.length <= 120
}

/** Validate an animClips payload (from the publish form / DB). Returns null when unusable. */
export function sanitizeAnimClips(raw: unknown): AnimClipsT | null {
  if (!raw || typeof raw !== 'object') return null
  const obj = raw as { clips?: unknown; map?: unknown }
  const clips = Array.isArray(obj.clips)
    ? Array.from(new Set(obj.clips.filter(clipNameOk).map((c) => c.trim()))).slice(0, 40)
    : []
  if (clips.length === 0) return null
  const map: Partial<Record<AnimSlot, string>> = {}
  if (obj.map && typeof obj.map === 'object') {
    for (const slot of ANIM_SLOTS) {
      const v = (obj.map as Record<string, unknown>)[slot]
      if (clipNameOk(v) && clips.includes(v)) map[slot] = v
    }
  }
  return Object.keys(map).length > 0 ? { clips, map } : { clips }
}

export function parseAnimClipsJson(raw: string | null | undefined): AnimClipsT | null {
  if (!raw) return null
  try {
    return sanitizeAnimClips(JSON.parse(raw))
  } catch {
    return null
  }
}

/** Validate an animTarget payload. */
export function sanitizeAnimTarget(raw: unknown): AnimTargetT | null {
  if (!raw || typeof raw !== 'object') return null
  const kind = (raw as { kind?: unknown }).kind
  if (kind !== 'avatar' && kind !== 'bundle' && kind !== 'ugc') return null
  const assetId = (raw as { assetId?: unknown }).assetId
  const out: AnimTargetT = { kind }
  if (kind !== 'avatar' && clipNameOk(assetId)) out.assetId = assetId
  return out
}

export function parseAnimTargetJson(raw: string | null | undefined): AnimTargetT | null {
  if (!raw) return null
  try {
    return sanitizeAnimTarget(JSON.parse(raw))
  } catch {
    return null
  }
}

/** Validate a bundle's replaced-parts list (must name real R6 parts). */
export function sanitizeBundleParts(raw: unknown): string[] | null {
  const list = Array.isArray(raw) ? raw : null
  if (!list) return null
  const keys: AvatarPartColorKey[] = ['head', 'torso', 'armL', 'armR', 'legL', 'legR']
  const out = list.filter((v): v is string => typeof v === 'string' && keys.includes(v as AvatarPartColorKey))
  return out.length > 0 ? out : null
}

export function parseBundlePartsJson(raw: string | null | undefined): string[] | null {
  if (!raw) return null
  try {
    return sanitizeBundleParts(JSON.parse(raw))
  } catch {
    return null
  }
}

/* ---------------- the limited economy ----------------
   A limited's price DOUBLES with every copy sold: pay T$ 1,000 and the
   next buyer pays T$ 2,000, then T$ 4,000... (the classic "rich get
   rarer" scramble — the item's `price` column stays the ORIGINAL price
   and the rising one is always computed from the real sold count). The
   total print run is `stock` — sold == stock means SOLD OUT, forever.
   The real owners count is inventory rows; admins can add a display
   boost (rarity theatre is the admin's call) but the LEDGER stays real. */

/** every sold copy DOUBLES the next buyer's price (2x per sale) */
export const LIMITED_GROWTH = 2

/** The rising price: original x 2 for every copy sold.
 *  1,000 -> 1st sale 1,000 -> next price 2,000 -> then 4,000, 8,000...
 *  Computed exactly from the sold count read inside the buy transaction,
 *  so two buyers racing can never both win at the same price.
 *  The doubling is capped at 2^40 (~1.1 trillion) so an unlimited-stock
 *  item sold hundreds of times can never overflow the wallet math. */
export function limitedPrice(originalPrice: number, soldCount: number): number {
  const sold = Math.min(40, Math.max(0, Math.floor(soldCount)))
  return originalPrice * Math.pow(LIMITED_GROWTH, sold)
}

/** accessory-style UGC: worn via the 6-slot accessories array (click on/off) */
export const ACCESSORY_KINDS: string[] = [
  'hat', 'hair', 'accessory', 'neck', 'shoulder', 'front', 'waist', 'gear', 'tshirt',
]

/** Types published as a real 3D model and placed on the player model in 3D. */
export const UGC_3D_TYPES: string[] = [
  'hat', 'hair', 'accessory', 'neck', 'shoulder', 'front', 'waist', 'gear',
]
export const is3DType = (t: string) => UGC_3D_TYPES.includes(t)

/** 3D placement editor limits — placement is the creator's call, these only
 *  keep items inside the space and stop runaway scaling. */
export const PLACEMENT_BOUNDS = {
  min: [-4, 0, -4] as [number, number, number],
  max: [4, 7.5, 4] as [number, number, number],
  scaleMin: 0.05,
  scaleMax: 4, // per axis; max world size also enforced in the editor
}

/* ---------------- website preview (the R6 player model, front view) ---------------- */

export interface AvatarPartImages {
  skin: string
  shirtColor: string
  shirtImage?: string
  pantsColor: string
  pantsImage?: string
  faceUrl: string
  /** per-part overrides from the advanced Body Colors editor (optional) */
  partColors?: AvatarPartColors
  /** face size multiplier (face-size slider) — 1 = classic */
  faceScale?: number
  accessories: { assetId: string; imageUrl?: string; kind: AvatarKind }[]
}

/** Effective color for one part, honoring the advanced Body Colors. */
export function partColor(parts: AvatarPartImages, key: AvatarPartColorKey): string {
  const override = parts.partColors?.[key]
  if (override) return override
  if (key === 'head' || key === 'armL' || key === 'armR') return parts.skin
  if (key === 'torso') return parts.shirtColor
  return parts.pantsColor
}

/** Turn an AvatarConfig + resolver into the pieces the preview renderer needs. */
export function buildPreviewParts(
  cfg: AvatarConfigT,
  resolve: (assetId: string) => AssetInfo | null
): AvatarPartImages {
  const body = resolve(cfg.bodyAssetId)
  const head = resolve(cfg.headAssetId)
  const shirt = resolve(cfg.shirtAssetId)
  const pants = resolve(cfg.pantsAssetId)
  return {
    skin: body?.color || '#FFD34E',
    shirtColor: shirt?.color || '#2E7DC4',
    shirtImage: shirt?.imageUrl,
    pantsColor: pants?.color || '#39516B',
    pantsImage: pants?.imageUrl,
    faceUrl: head?.imageUrl || faceImageUrl('head_01'),
    partColors: cfg.colors,
    faceScale: sanitizeFaceScale(cfg.faceScale),
    accessories: cfg.accessories
      .map((id) => resolve(id))
      .filter(Boolean)
      .map((a) => ({ assetId: a!.assetId, imageUrl: a!.imageUrl, kind: a!.kind })),
  }
}

const SVG_NS = 'http://www.w3.org/2000/svg'

/** The face decal rect for a given scale — grows/shrinks around the head centre. */
export function faceRect(scale = 1): Rect {
  const s = Math.min(FACE_SCALE_MAX, Math.max(FACE_SCALE_MIN, scale || 1))
  const cx = R6.FACE.x + R6.FACE.w / 2
  const cy = R6.FACE.y + R6.FACE.h / 2
  const w = R6.FACE.w * s
  const h = R6.FACE.h * s
  return { x: cx - w / 2, y: cy - h / 2, w, h }
}

/**
 * Renders the R6 player model (front view) as a RAW <svg> string — the same
 * rig, proportions and placement rules the Unity SDK builds in 3D
 * (Models/R6IK.fbx). UGC lands EXACTLY where its creator placed it.
 *
 * Use the raw markup INLINE in the DOM when the preview shows server-hosted
 * UGC images: an <img> fed with a data-URL SVG is not allowed to fetch
 * external resources (browsers block it), so /api/files/... art would
 * silently disappear. Inline SVG has no such restriction.
 */
export function renderAvatarSvgMarkup(parts: AvatarPartImages, size = 200): string {
  const imgTag = (url: string, r: Rect) =>
    `<image href="${url}" x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" preserveAspectRatio="xMidYMid meet"/>`
  /** crop one zone of a clothing template onto a body part (slice fills the part) */
  const zoneCrop = (url: string, zone: Rect, tpl: { w: number; h: number }, part: Rect) =>
    `<svg x="${part.x}" y="${part.y}" width="${part.w}" height="${part.h}" viewBox="${zone.x} ${zone.y} ${zone.w} ${zone.h}" preserveAspectRatio="xMidYMid slice"><image href="${url}" width="${tpl.w}" height="${tpl.h}" preserveAspectRatio="xMidYMid slice"/></svg>`

  const shirt = parts.shirtImage
    ? zoneCrop(
        parts.shirtImage,
        SHIRT_TEMPLATE.torso,
        SHIRT_TEMPLATE,
        R6.TORSO
      )
    : ''
  const armR = parts.shirtImage ? zoneCrop(parts.shirtImage, SHIRT_TEMPLATE.armR, SHIRT_TEMPLATE, R6.ARM_R) : ''
  const armL = parts.shirtImage ? zoneCrop(parts.shirtImage, SHIRT_TEMPLATE.armL, SHIRT_TEMPLATE, R6.ARM_L) : ''
  const legR = parts.pantsImage ? zoneCrop(parts.pantsImage, PANTS_TEMPLATE.legR, PANTS_TEMPLATE, R6.LEG_R) : ''
  const legL = parts.pantsImage ? zoneCrop(parts.pantsImage, PANTS_TEMPLATE.legL, PANTS_TEMPLATE, R6.LEG_L) : ''

  // t-shirts (torso decals) and hats/gear are placement-respecting slots,
  // rendered 1:1, in the order the player wears them — no auto-offsets
  const tshirts = parts.accessories
    .filter((a) => a.imageUrl && a.kind === 'tshirt')
    .map((a) => imgTag(a.imageUrl!, R6.TSHIRT_SLOT))
    .join('')
  const hats = parts.accessories
    .filter((a) => a.imageUrl && (a.kind === 'hat' || a.kind === 'gear' || a.kind === 'accessory'))
    .map((a) => imgTag(a.imageUrl!, R6.HAT_SLOT))
    .join('')

  const svg = `<svg xmlns="${SVG_NS}" width="${size}" height="${size}" viewBox="0 0 100 100">` +
    `<rect width="100" height="100" fill="#dcebf5"/>` +
    `<rect x="0" y="94" width="100" height="6" fill="#5aa35a"/><rect x="0" y="94" width="100" height="1.6" fill="#6cbb6c"/>` +
    // legs (R6: 1x2 studs each)
    `<rect x="${R6.LEG_R.x}" y="${R6.LEG_R.y}" width="${R6.LEG_R.w}" height="${R6.LEG_R.h}" fill="${partColor(parts, 'legR')}" stroke="#00000030" stroke-width="0.8"/>` +
    `<rect x="${R6.LEG_L.x}" y="${R6.LEG_L.y}" width="${R6.LEG_L.w}" height="${R6.LEG_L.h}" fill="${partColor(parts, 'legL')}" stroke="#00000030" stroke-width="0.8"/>` +
    legR + legL +
    // arms first so the torso outline overlaps them like the classic render
    `<rect x="${R6.ARM_R.x}" y="${R6.ARM_R.y}" width="${R6.ARM_R.w}" height="${R6.ARM_R.h}" fill="${partColor(parts, 'armR')}" stroke="#00000033" stroke-width="0.8"/>` +
    `<rect x="${R6.ARM_L.x}" y="${R6.ARM_L.y}" width="${R6.ARM_L.w}" height="${R6.ARM_L.h}" fill="${partColor(parts, 'armL')}" stroke="#00000033" stroke-width="0.8"/>` +
    armR + armL +
    // torso (2x2 studs)
    `<rect x="${R6.TORSO.x}" y="${R6.TORSO.y}" width="${R6.TORSO.w}" height="${R6.TORSO.h}" fill="${partColor(parts, 'torso')}" stroke="#00000033" stroke-width="0.8"/>` +
    shirt +
    // head (1.2^ studs) + face (the face-size slider scales it around its center)
    `<rect x="${R6.HEAD.x}" y="${R6.HEAD.y}" width="${R6.HEAD.w}" height="${R6.HEAD.h}" fill="${partColor(parts, 'head')}" stroke="#00000044" stroke-width="0.8"/>` +
    imgTag(parts.faceUrl, faceRect(parts.faceScale)) +
    // UGC: t-shirts over the torso, hats/gear over the head — exactly as uploaded
    tshirts + hats +
    `</svg>`
  return svg
}

/** Same render, as a standalone data-URL image. Only safe when every
 *  referenced image is itself a data: URL (e.g. the catalog publish
 *  preview); server-hosted UGC needs renderAvatarSvgMarkup inline. */
export function renderAvatarSvg(parts: AvatarPartImages, size = 200): string {
  return `data:image/svg+xml;utf8,${encodeURIComponent(renderAvatarSvgMarkup(parts, size))}`
}
