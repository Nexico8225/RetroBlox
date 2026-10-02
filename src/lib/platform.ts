/* ------------------------------------------------------------------
   RETROBLOX PLATFORM — shared server-side helpers
   The public API shape every game consumes (Unity SDK included):

     GET /api/users/{userId}/avatar  ->
       { "userId": "...", "username": "Nexico", "avatar": {
           "body": "body_01", "head": "head_01",
           "shirt": "shirt_01", "pants": "pants_01",
           "accessories": ["hat_15"] } }

   Unity (or any engine) talks to THESE endpoints only — it never
   touches the database. Protected routes validate the session token
   before returning anything about an account.
------------------------------------------------------------------ */

import { db } from '@/lib/db'
import { DEFAULT_AVATAR, resolveDefaultAsset, parsePlacement, sanitizePartColors, sanitizeFaceScale, ACCESSORY_KINDS, parseAnimClipsJson, parseAnimTargetJson, parseBundlePartsJson, type AvatarConfigT, type AssetInfo, type AnimClipsT, type AnimTargetT } from '@/lib/avatarAssets'

/** Load a user's avatar config from the database (defaults if they never customized). */
export async function getAvatarConfig(userId: string): Promise<AvatarConfigT> {
  const cfg = await db.avatarConfig.findUnique({ where: { userId } })
  if (!cfg) return { ...DEFAULT_AVATAR }
  let accessories: string[] = []
  try {
    accessories = JSON.parse(cfg.accessoriesJson || '[]')
    if (!Array.isArray(accessories)) accessories = []
  } catch {
    accessories = []
  }
  return {
    bodyAssetId: cfg.bodyAssetId,
    headAssetId: cfg.headAssetId,
    shirtAssetId: cfg.shirtAssetId,
    pantsAssetId: cfg.pantsAssetId,
    accessories,
    colors: sanitizePartColors(safeJson(cfg.colorsJson)),
    faceScale: sanitizeFaceScale((cfg as { faceScale?: unknown }).faceScale),
    bundleAssetId: cfg.bundleAssetId || null,
    animPackAssetId: cfg.animPackAssetId || null,
  }
}

function safeJson(raw: string | null | undefined): unknown {
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

/** The exact payload shape the RetroBlox API contract promises. */
export function avatarPayload(userId: string, username: string, cfg: AvatarConfigT) {
  return {
    userId,
    username,
    avatar: {
      body: cfg.bodyAssetId,
      head: cfg.headAssetId,
      shirt: cfg.shirtAssetId,
      pants: cfg.pantsAssetId,
      accessories: cfg.accessories,
      colors: cfg.colors && Object.keys(cfg.colors).length > 0 ? cfg.colors : null,
      faceScale: sanitizeFaceScale(cfg.faceScale),
      bundle: cfg.bundleAssetId || null,
      animPack: cfg.animPackAssetId || null,
    },
  }
}

/* ---------------- rigged payload (emotes / bundles / anim packs) ----------------
   Games fetch THIS through the platform API: the worn bundle (with its GLB +
   replaced parts), the active animation pack (with its GLB + slot map) and
   every emote the account owns (so the game can play them on demand). */

export interface EnrichedAvatar {
  bundle: {
    assetId: string
    name: string
    modelUrl: string
    imageUrl: string
    textureUrl: string | null
    color: string | null
    metallic: number | null
    roughness: number | null
    parts: string[] | null
  } | null
  animPack: {
    assetId: string
    name: string
    modelUrl: string
    clips: AnimClipsT | null
  } | null
  emotes: {
    assetId: string
    itemId: string
    name: string
    modelUrl: string
    clips: AnimClipsT | null
  }[]
}

/** Resolve the rigged parts of a look (bundle / anim pack / owned emotes).
 *  Non-fatal by design: a broken or missing UGC row degrades to null/[] so
 *  a game can always spawn the player. */
export async function enrichAvatarPayload(userId: string, cfg: AvatarConfigT): Promise<EnrichedAvatar> {
  const out: EnrichedAvatar = { bundle: null, animPack: null, emotes: [] }

  const decorate = (info: AssetInfo | null) => {
    if (!info || !info.itemId) return null
    return db.avatarItem.findUnique({ where: { id: info.itemId } }).catch(() => null)
  }

  const jobs: Promise<unknown>[] = []

  if (cfg.bundleAssetId) {
    jobs.push(
      (async () => {
        const info = await resolveAsset(cfg.bundleAssetId!).catch(() => null)
        const item = await decorate(info)
        if (info && item) {
          out.bundle = {
            assetId: info.assetId,
            name: info.name,
            modelUrl: item.modelFileId ? `/api/files/${item.modelFileId}` : '',
            imageUrl: `/api/files/${item.imageFileId}`,
            textureUrl: item.textureFileId ? `/api/files/${item.textureFileId}` : null,
            color: item.baseColor || null,
            metallic: item.metallic,
            roughness: item.roughness,
            parts: parseBundlePartsJson(item.bundlePartsJson),
          }
        }
      })()
    )
  }

  if (cfg.animPackAssetId) {
    jobs.push(
      (async () => {
        const info = await resolveAsset(cfg.animPackAssetId!).catch(() => null)
        const item = await decorate(info)
        if (info && item) {
          out.animPack = {
            assetId: info.assetId,
            name: info.name,
            modelUrl: item.modelFileId ? `/api/files/${item.modelFileId}` : '',
            clips: parseAnimClipsJson(item.animClipsJson),
          }
        }
      })()
    )
  }

  jobs.push(
    (async () => {
      const rows = await db.inventoryEntry
        .findMany({
          where: { userId, item: { type: 'emote', deletedAt: null } },
          include: { item: { select: { id: true, assetId: true, name: true, modelFileId: true, animClipsJson: true } } },
          orderBy: { acquiredAt: 'desc' },
          take: 50,
        })
        .catch(() => [])
      out.emotes = rows
        .filter((r) => r.item.modelFileId)
        .map((r) => ({
          assetId: r.item.assetId,
          itemId: r.item.id,
          name: r.item.name,
          modelUrl: `/api/files/${r.item.modelFileId}`,
          clips: parseAnimClipsJson(r.item.animClipsJson),
        }))
    })()
  )

  await Promise.all(jobs)
  return out
}

/** Resolve ANY asset id — built-in defaults or published UGC — server side. */
export async function resolveAsset(assetId: string): Promise<AssetInfo | null> {
  const builtin = resolveDefaultAsset(assetId)
  if (builtin) return builtin
  const item = await db.avatarItem.findUnique({
    where: { assetId },
    include: { creator: { select: { id: true, username: true } }, group: { select: { id: true, name: true } } },
  })
  if (!item) return null
  return {
    assetId: item.assetId,
    kind: item.type as AssetInfo['kind'],
    name: item.name,
    description: item.description,
    imageUrl: `/api/files/${item.imageFileId}`,
    modelUrl: item.modelFileId ? `/api/files/${item.modelFileId}` : undefined,
    textureUrl: item.textureFileId ? `/api/files/${item.textureFileId}` : undefined,
    color: item.baseColor || undefined,
    metallic: item.metallic,
    roughness: item.roughness,
    placement: parsePlacement(item.placementJson),
    animClips: parseAnimClipsJson(item.animClipsJson),
    animTarget: parseAnimTargetJson(item.animTargetJson),
    bundleParts: parseBundlePartsJson(item.bundlePartsJson),
    hasRig: item.hasRig,
    itemId: item.id,
    creatorId: item.creatorId,
    creatorName: item.creator.username,
    groupId: item.groupId,
    groupName: item.group?.name || null,
    createdAt: item.createdAt.toISOString(),
  }
}

/** Validate a full avatar config: every id must exist (defaults or OWNED UGC). */
export async function validateAvatarConfig(userId: string, cfg: AvatarConfigT): Promise<string | null> {
  const slots: [string, string][] = [
    [cfg.bodyAssetId, 'body'],
    [cfg.headAssetId, 'head'],
    [cfg.shirtAssetId, 'shirt'],
    [cfg.pantsAssetId, 'pants'],
  ]
  for (const [assetId, slot] of slots) {
    const info = await resolveAsset(assetId)
    if (!info) return `Unknown ${slot} asset: ${assetId}`
    // head slot accepts head defaults or published face UGC
    if (slot === 'head' && info.kind !== 'head' && info.kind !== 'face') {
      return `${assetId} is not a head or face asset`
    }
    if ((slot === 'body' || slot === 'shirt' || slot === 'pants') && info.kind !== slot) {
      return `${assetId} is not a ${slot} asset`
    }
  }
  if (cfg.accessories.length > 6) return 'Too many accessories (6 max)'
  for (const acc of cfg.accessories) {
    const info = await resolveAsset(acc)
    if (!info) return `Unknown accessory asset: ${acc}`
    // accessories = accessory-style UGC worn on/off (hats, hair, back, neck,
    // shoulder, front, waist, gear — placed by their creators) and t-shirts
    if (!ACCESSORY_KINDS.includes(info.kind)) {
      return `${acc} is not a wearable accessory (${info.kind})`
    }
    // only UGC needs ownership — defaults are for everyone
    if (info.itemId) {
      const owned = await db.inventoryEntry.findUnique({
        where: { userId_itemId: { userId, itemId: info.itemId } },
      })
      if (!owned) return `You do not own ${acc} yet — get it from the Catalog first.`
    }
  }

  // the worn bundle: must be a published bundle AND owned
  if (cfg.bundleAssetId) {
    const info = await resolveAsset(cfg.bundleAssetId)
    if (!info) return `Unknown bundle asset: ${cfg.bundleAssetId}`
    if (info.kind !== 'bundle') return `${cfg.bundleAssetId} is not a bundle`
    if (info.itemId) {
      const owned = await db.inventoryEntry.findUnique({
        where: { userId_itemId: { userId, itemId: info.itemId } },
      })
      if (!owned) return `You do not own ${cfg.bundleAssetId} yet — get it from the Catalog first.`
    }
  }

  // the active animation pack: must be a published anim pack AND owned
  if (cfg.animPackAssetId) {
    const info = await resolveAsset(cfg.animPackAssetId)
    if (!info) return `Unknown animation asset: ${cfg.animPackAssetId}`
    if (info.kind !== 'anim') return `${cfg.animPackAssetId} is not an animation pack`
    if (info.itemId) {
      const owned = await db.inventoryEntry.findUnique({
        where: { userId_itemId: { userId, itemId: info.itemId } },
      })
      if (!owned) return `You do not own ${cfg.animPackAssetId} yet — get it from the Catalog first.`
    }
  }
  return null
}

/** CORS headers so the Unity SDK (standalone player / WebGL build) can call the API. */
export const PLATFORM_CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
} as const
