import { NextRequest, NextResponse } from 'next/server'
import { Prisma } from '@prisma/client'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload, resolveUpload } from '@/lib/uploads'
import {
  UGC_TYPES, UGC_TYPE_LABELS, is3DType, isRiggedType, parseAssetId, parsePlacement, placementJson,
  sanitizeAnimClips, sanitizeAnimTarget, sanitizeBundleParts, parseAnimClipsJson, parseAnimTargetJson, parseBundlePartsJson,
  sanitizeFinish,
} from '@/lib/avatarAssets'
import { buyPrice } from '@/lib/rbx'

/** Parse a JSON form field (animClips / animTarget / bundleParts). */
async function safeFormJson(v: FormDataEntryValue | null): Promise<unknown> {
  if (typeof v !== 'string' || !v.trim()) return null
  try {
    return JSON.parse(v)
  } catch {
    return null
  }
}

/** who can publish UGC in the name of a group: owner, site admin, or a role with the `ugc` permission */
async function canPublishForGroup(groupId: string, userId: string, siteAdmin: boolean): Promise<boolean> {
  const group = await db.group.findUnique({ where: { id: groupId }, select: { ownerId: true } })
  if (!group) return false
  if (group.ownerId === userId || siteAdmin) return true
  const membership = await db.groupMember.findUnique({ where: { groupId_userId: { groupId, userId } } })
  if (!membership) return false
  const role = await db.groupRole.findUnique({ where: { groupId_name: { groupId, name: membership.role } } })
  try {
    const perms = JSON.parse(role?.permsJson || '[]')
    return Array.isArray(perms) && perms.includes('ugc')
  } catch {
    return false
  }
}

/** next free asset id for a UGC type: hat_1, hat_2 ... (never collides) */
async function nextAssetId(type: string): Promise<string> {
  let n = 1
  // keep scanning until the id is free (deleted items leave gaps, that's fine)
  for (;;) {
    const candidate = `${type}_${n}`
    const clash = await db.avatarItem.findUnique({ where: { assetId: candidate }, select: { id: true } })
    if (!clash) return candidate
    n++
    if (n > 9999) return `${type}_${Date.now()}` // paranoia fallback
  }
}

// GET /api/catalog?type=hat&q=wizard&group=<groupId>&limited=1 — browse avatar UGC
//   admins can pass deleted=1 to list soft-deleted UGC (for the restore panel)
export async function GET(req: NextRequest) {
  const url = new URL(req.url)
  const type = url.searchParams.get('type') || ''
  const q = (url.searchParams.get('q') || '').trim()
  const groupId = url.searchParams.get('group') || ''
  const wantDeleted = url.searchParams.get('deleted') === '1'
  const onlyLimited = url.searchParams.get('limited') === '1'
  const viewer = await getUserFromReq(req)
  const isAdmin = viewer?.role === 'admin'

  const items = await db.avatarItem.findMany({
    where: {
      // soft-deleted UGC stays out of every list unless an admin asks for it
      deletedAt: wantDeleted && isAdmin ? { not: null } : null,
      ...(type && UGC_TYPES.includes(type as never) ? { type } : {}),
      ...(groupId ? { groupId } : {}),
      ...(onlyLimited ? { isLimited: true } : {}),
      ...(q
        ? {
            OR: [
              { name: { contains: q } },
              { description: { contains: q } },
              { creator: { is: { username: { contains: q } } } },
            ],
          }
        : {}),
    },
    include: {
      creator: { select: { id: true, username: true, avatarUrl: true } },
      group: { select: { id: true, name: true } },
      _count: { select: { ownedBy: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })

  const owned = viewer
    ? await db.inventoryEntry.findMany({ where: { userId: viewer.id }, select: { itemId: true } })
    : []

  // sold = REAL BUYERS — the creator's own auto-granted copy is NOT a sale
  // (stock means sellable copies). One grouped query with a join excludes it.
  const itemIds = items.map((i) => i.id)
  const soldMap = new Map<string, number>()
  if (itemIds.length > 0) {
    const soldRows = await db.$queryRaw<{ itemId: string; n: bigint }[]>`
      SELECT e.itemId AS itemId, COUNT(*) AS n
      FROM InventoryEntry e
      JOIN AvatarItem i ON e.itemId = i.id
      WHERE e.itemId IN (${Prisma.join(itemIds)}) AND e.userId != i.creatorId
      GROUP BY e.itemId`
    for (const r of soldRows) soldMap.set(r.itemId, Number(r.n))
  }

  return NextResponse.json({
    items: items.map((i) => {
      const sold = soldMap.get(i.id) ?? 0
      return {
        id: i.id,
        assetId: i.assetId,
        name: i.name,
        description: i.description,
        type: i.type,
        price: i.price, // for limiteds this is the ORIGINAL price
        isLimited: i.isLimited,
        stock: i.isLimited ? i.stock : null,
        sold,
        remaining: i.isLimited && i.stock != null ? Math.max(0, i.stock - sold) : null,
        ownersBoost: i.ownersBoost,
        owners: sold + i.ownersBoost, // displayed buyers count — REAL buyers only (creator's own copy is not a sale) + admin boost
        buyPrice: buyPrice(i, sold), // limiteds: the RISING price
        imageFileId: i.imageFileId,
        modelFileId: i.modelFileId,
        textureFileId: i.textureFileId,
        baseColor: i.baseColor,
        roughness: i.roughness,
        metallic: i.metallic,
        placement: parsePlacement(i.placementJson),
        animClips: parseAnimClipsJson(i.animClipsJson),
        animTarget: parseAnimTargetJson(i.animTargetJson),
        bundleParts: parseBundlePartsJson(i.bundlePartsJson),
        hasRig: i.hasRig,
        creator: i.creator,
        group: i.group,
        createdAt: i.createdAt,
        deletedAt: i.deletedAt,
      }
    }),
    ownedItemIds: owned.map((o) => o.itemId),
  })
}

// POST /api/catalog — publish avatar UGC (multipart)
//   2D types (face|tshirt|shirt|pants):  name, type, description, image, [groupId]
//   3D types (hat|gear|accessory):       name, type, description, image = try-on
//                                        thumbnail, model = GLB, placement = JSON, [groupId]
//   rigged types (emote|bundle|anim):    name, type, description, image = auto-captured
//                                        shot, model = rigged GLB, animClips/animTarget/
//                                        bundleParts = JSON, [limited: stock = N], [groupId]
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const name = String(form.get('name') || '').trim()
  const type = String(form.get('type') || '').trim()
  const description = String(form.get('description') || '').trim().slice(0, 600)
  const groupIdRaw = String(form.get('groupId') || '').trim()
  // files arrive either directly (< 3MB, under the serverless body cap) or as
  // an uploadId referencing chunks uploaded via /api/uploads/chunk (models up
  // to 24MB). resolveUpload returns null when neither is present.
  const image = await resolveUpload(form.get('image'), form.get('imageUploadId'))
  const model = await resolveUpload(form.get('model'), form.get('modelUploadId'))
  const texture = await resolveUpload(form.get('texture'), form.get('textureUploadId'))
  const colorRaw = String(form.get('color') || '').trim()
  const placementRaw = String(form.get('placement') || '').trim()
  // pricing: 0 = free item; limiteds are collectibles — the price is the price
  const price = Math.floor(Number(form.get('price') || 0))
  const isLimited = String(form.get('limited') || '') === '1'
  // limited stock: the total print run (empty/null = unlimited copies)
  const stockRaw = String(form.get('stock') || '').trim()
  let stock: number | null = null
  if (isLimited && stockRaw !== '') {
    stock = Math.floor(Number(stockRaw))
    if (!Number.isFinite(stock) || stock < 1) {
      return NextResponse.json({ error: 'Limited stock must be at least 1 copy (or leave it empty for unlimited).' }, { status: 400 })
    }
  }
  // rigged UGC payloads (emote / bundle / anim)
  const rigged = isRiggedType(type)
  let animClipsJsonStr: string | null = null
  let animTargetJsonStr: string | null = null
  let bundlePartsJsonStr: string | null = null
  let hasRig = false
  if (rigged) {
    const clips = sanitizeAnimClips(await safeFormJson(form.get('animClips')))
    const target = sanitizeAnimTarget(await safeFormJson(form.get('animTarget')))
    const parts = sanitizeBundleParts(await safeFormJson(form.get('bundleParts')))
    if (type === 'anim' && !clips) {
      return NextResponse.json({ error: 'An animation pack needs at least one clip from your GLB.' }, { status: 400 })
    }
    if (clips) animClipsJsonStr = JSON.stringify(clips)
    if (target) animTargetJsonStr = JSON.stringify(target)
    if (parts) bundlePartsJsonStr = JSON.stringify(parts)
    hasRig = !!clips
  }

  if (!Number.isFinite(price) || price < 0 || price > 1_000_000) {
    return NextResponse.json({ error: 'Price must be between T$ 0 and T$ 1,000,000.' }, { status: 400 })
  }
  if (isLimited && price < 1) {
    return NextResponse.json({ error: 'Limited items need a price of at least T$ 1.' }, { status: 400 })
  }

  if (name.length < 3 || name.length > 40) {
    return NextResponse.json({ error: 'Name must be 3-40 characters.' }, { status: 400 })
  }
  if (!UGC_TYPES.includes(type as never)) {
    return NextResponse.json({ error: 'Pick a valid UGC type.' }, { status: 400 })
  }

  let modelFileId: string | null = null
  let placementJsonStr: string | null = null
  let textureFileId: string | null = null
  let baseColor: string | null = null
  let roughness: number | null = null
  let metallic: number | null = null

  // creator surface for 3D UGC: an optional texture image wrapped around the
  // model, or a tint color when there is no texture (texture wins at render).
  // Roughness / metallic: OPTIONAL finish overrides — empty = the model's own.
  if (is3DType(type)) {
    roughness = sanitizeFinish(form.get('roughness') ?? undefined)
    metallic = sanitizeFinish(form.get('metallic') ?? undefined)
    if (colorRaw) {
      if (!/^#[0-9a-fA-F]{6}$/.test(colorRaw)) {
        return NextResponse.json({ error: 'The color must be a hex color like #4da6ff.' }, { status: 400 })
      }
      baseColor = colorRaw.toLowerCase()
    }
    if (texture instanceof File && texture.size > 0) {
      if (texture.size > 8 * 1024 * 1024) {
        return NextResponse.json({ error: 'Texture too large (max 8MB).' }, { status: 400 })
      }
      if (texture.type && !texture.type.startsWith('image/')) {
        return NextResponse.json({ error: 'The texture must be an image (PNG / JPG).' }, { status: 400 })
      }
    }
  }

  if (is3DType(type)) {
    // 3D UGC: the GLB model is the item; the image is the try-on thumbnail
    // captured in the placement editor; placement is the creator's transform
    if (!(model instanceof File) || model.size === 0) {
      return NextResponse.json({ error: `A 3D model is required for ${UGC_TYPE_LABELS[type] || type}.` }, { status: 400 })
    }
    if (model.size > 24 * 1024 * 1024) {
      return NextResponse.json({ error: 'Model too large (max 24MB).' }, { status: 400 })
    }
    const head = Buffer.from(await model.slice(0, 4).arrayBuffer())
    if (head.toString('ascii') !== 'glTF') {
      return NextResponse.json({ error: 'The model must be a GLB file (the site converts it for you).' }, { status: 400 })
    }
    const placement = parsePlacement(placementRaw)
    if (!placement) {
      return NextResponse.json({ error: 'Missing placement — place the item on the player model first.' }, { status: 400 })
    }
    placementJsonStr = placementJson(placement)
  } else if (rigged) {
    // rigged UGC: the rigged GLB IS the item; no placement editor — the
    // animation plays on the body, the bundle replaces it
    if (!(model instanceof File) || model.size === 0) {
      return NextResponse.json({ error: `A rigged GLB model is required for ${UGC_TYPE_LABELS[type] || type}.` }, { status: 400 })
    }
    if (model.size > 24 * 1024 * 1024) {
      return NextResponse.json({ error: 'Model too large (max 24MB).' }, { status: 400 })
    }
    const head = Buffer.from(await model.slice(0, 4).arrayBuffer())
    if (head.toString('ascii') !== 'glTF') {
      return NextResponse.json({ error: 'The model must be a GLB file (the site converts it for you).' }, { status: 400 })
    }
  } else if (model) {
    return NextResponse.json({ error: 'Only 3D-worn UGC (hats, hair, accessories, gear...) takes a 3D model.' }, { status: 400 })
  }

  if (!(image instanceof File) || image.size === 0) {
    return NextResponse.json(
      { error: is3DType(type) || rigged ? 'A preview image is required.' : 'An image is required — draw it or export it from your editor.' },
      { status: 400 }
    )
  }
  if (image.size > 8 * 1024 * 1024) {
    return NextResponse.json({ error: 'Image too large (max 8MB).' }, { status: 400 })
  }
  if (image.type && !image.type.startsWith('image/')) {
    return NextResponse.json({ error: 'Only image files are allowed for the picture.' }, { status: 400 })
  }

  let groupId: string | null = null
  if (groupIdRaw) {
    if (!(await canPublishForGroup(groupIdRaw, user.id, user.role === 'admin'))) {
      return NextResponse.json({ error: 'You need the UGC permission in that group to publish for it.' }, { status: 403 })
    }
    groupId = groupIdRaw
  }

  const file = await saveUpload(image, user.id)
  if (model instanceof File && model.size > 0) {
    const mf = await saveUpload(model, user.id)
    modelFileId = mf.id
  }
  if (is3DType(type) && texture instanceof File && texture.size > 0) {
    const tf = await saveUpload(texture, user.id)
    textureFileId = tf.id
  }
  const assetId = await nextAssetId(type)
  if (!parseAssetId(assetId)) {
    return NextResponse.json({ error: 'Could not allocate an asset id' }, { status: 500 })
  }

  // create the item + the publisher's first inventory copy. If anything goes
  // wrong here the publish NEVER silently eats the upload — the error comes
  // back and the (harmless) file rows are retried on the next attempt.
  const baseData = {
    name,
    description,
    type,
    price,
    isLimited,
    stock: isLimited ? stock : null,
    imageFileId: file.id,
    modelFileId,
    placementJson: placementJsonStr,
    textureFileId,
    baseColor,
    roughness,
    metallic,
    animClipsJson: animClipsJsonStr,
    animTargetJson: animTargetJsonStr,
    bundlePartsJson: bundlePartsJsonStr,
    hasRig,
    creatorId: user.id,
    groupId,
  }
  let item
  try {
    item = await db.avatarItem.create({ data: { assetId, ...baseData } })
  } catch {
    // one retry with a fresh asset id (a clash is the only realistic failure)
    const retryId = await nextAssetId(type)
    item = await db.avatarItem.create({ data: { assetId: retryId, ...baseData } })
  }

  // publishers own what they make — it goes straight into their inventory
  await db.inventoryEntry.create({ data: { userId: user.id, itemId: item.id } })

  return NextResponse.json({ ok: true, item: { id: item.id, assetId: item.assetId, name: item.name, type: item.type } })
}
