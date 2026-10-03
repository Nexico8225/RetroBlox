import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { getAvatarConfig, avatarPayload, enrichAvatarPayload, validateAvatarConfig } from '@/lib/platform'
import { parsePlacement, parseAnimClipsJson, parseBundlePartsJson, sanitizePartColors, sanitizeFaceScale, type AvatarConfigT } from '@/lib/avatarAssets'

/**
 * Own avatar config (website editor):
 *   GET /api/me/avatar — my current avatar (+ inventory with rigged data)
 *   PUT /api/me/avatar — save my avatar (session required, ids validated)
 * Change it here once and EVERY RetroBlox game sees the new look —
 * bundle and animation pack included.
 */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const cfg = await getAvatarConfig(user.id)

  // inventory: UGC this account can wear
  const inventory = await db.inventoryEntry.findMany({
    where: { userId: user.id },
    include: { item: { include: { group: { select: { name: true } } } } },
    orderBy: { acquiredAt: 'desc' },
  })

  const rigged = await enrichAvatarPayload(user.id, cfg)
  return NextResponse.json({
    ...avatarPayload(user.id, user.username, cfg),
    bundle: rigged.bundle,
    animPack: rigged.animPack,
    emotes: rigged.emotes,
    inventory: inventory.map((e) => ({
      itemId: e.itemId,
      assetId: e.item.assetId,
      name: e.item.name,
      type: e.item.type,
      imageFileId: e.item.imageFileId,
      modelFileId: e.item.modelFileId,
      textureFileId: e.item.textureFileId,
      baseColor: e.item.baseColor,
      roughness: e.item.roughness,
      metallic: e.item.metallic,
      placement: parsePlacement(e.item.placementJson),
      animClips: parseAnimClipsJson(e.item.animClipsJson),
      bundleParts: parseBundlePartsJson(e.item.bundlePartsJson),
      hasRig: e.item.hasRig,
      groupName: e.item.group?.name || null,
      acquiredAt: e.acquiredAt,
    })),
  })
}

export async function PUT(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => null)) as
    | (AvatarConfigT & { accessories?: string[] })
    | null
  if (!body) return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

  const cfg: AvatarConfigT = {
    bodyAssetId: String(body.bodyAssetId || ''),
    headAssetId: String(body.headAssetId || ''),
    shirtAssetId: String(body.shirtAssetId || ''),
    pantsAssetId: String(body.pantsAssetId || ''),
    accessories: Array.isArray(body.accessories) ? body.accessories.map(String) : [],
    colors: sanitizePartColors((body as { colors?: unknown }).colors),
    faceScale: sanitizeFaceScale((body as { faceScale?: unknown }).faceScale),
    bundleAssetId: String((body as { bundleAssetId?: unknown }).bundleAssetId || '') || null,
    animPackAssetId: String((body as { animPackAssetId?: unknown }).animPackAssetId || '') || null,
  }
  const err = await validateAvatarConfig(user.id, cfg)
  if (err) return NextResponse.json({ error: err }, { status: 400 })

  const colorsJson = JSON.stringify(cfg.colors || {})
  const rows = {
    bodyAssetId: cfg.bodyAssetId,
    headAssetId: cfg.headAssetId,
    shirtAssetId: cfg.shirtAssetId,
    pantsAssetId: cfg.pantsAssetId,
    accessoriesJson: JSON.stringify(cfg.accessories),
    colorsJson,
    faceScale: sanitizeFaceScale(cfg.faceScale),
    bundleAssetId: cfg.bundleAssetId,
    animPackAssetId: cfg.animPackAssetId,
  }
  await db.avatarConfig.upsert({
    where: { userId: user.id },
    update: rows,
    create: { userId: user.id, ...rows },
  })

  return NextResponse.json({ ok: true, ...avatarPayload(user.id, user.username, cfg) })
}
