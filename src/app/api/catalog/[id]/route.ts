import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, isUserAdmin } from '@/lib/auth'
import { parsePlacement, parseAnimClipsJson, parseAnimTargetJson, parseBundlePartsJson } from '@/lib/avatarAssets'
import { buyPrice, RbxError } from '@/lib/rbx'
import { saveUpload, resolveUpload } from '@/lib/uploads'

/**
 * GET    /api/catalog/[id] — one item + whether the viewer owns it
 * PATCH  /api/catalog/[id] — edit your own item (name, description, price, limited)
 * POST   /api/catalog/[id] — action "get": add a FREE item to your inventory
 *                            action "buy": pay Tix for it (the price the creator set)
 * DELETE /api/catalog/[id] — remove UGC (creator, group owner, or site admin)
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const viewer = await getUserFromReq(_req)
  const item = await db.avatarItem.findUnique({
    where: { id },
    include: {
      creator: { select: { id: true, username: true, avatarUrl: true } },
      group: { select: { id: true, name: true } },
      _count: { select: { ownedBy: true } },
    },
  })
  if (!item) return NextResponse.json({ error: 'Item not found' }, { status: 404 })
  const owned = viewer
    ? !!(await db.inventoryEntry.findUnique({ where: { userId_itemId: { userId: viewer.id, itemId: id } } }))
    : false
  // sold = REAL BUYERS (the creator's own auto-granted copy is not a sale)
  const sold = await db.inventoryEntry.count({
    where: { itemId: id, NOT: { userId: item.creatorId } },
  })
  // the sales ledger for the item page: WHO bought and WHEN (newest first)
  const sales = await db.inventoryEntry.findMany({
    where: { itemId: id, NOT: { userId: item.creatorId } },
    orderBy: { acquiredAt: 'desc' },
    take: 14,
    select: {
      acquiredAt: true,
      user: { select: { id: true, username: true, avatarUrl: true } },
    },
  })
  // active resale listings for this item
  const activeListings = await db.ugcListing.findMany({
    where: { itemId: id, status: 'active' },
    orderBy: { price: 'asc' },
    include: {
      seller: { select: { id: true, username: true, avatarUrl: true } },
    },
  })
  const bestPrice = activeListings.length > 0 ? activeListings[0].price : null
  const myListing = viewer ? activeListings.find((l) => l.sellerId === viewer.id) : null

  // RAP (Recent Average Price): average of completed sales, fallback to item.price
  const recentPricePoints = await db.ugcPricePoint.findMany({
    where: { itemId: id },
    orderBy: { createdAt: 'desc' },
    take: 10,
    select: { price: true },
  })
  const rap = recentPricePoints.length > 0
    ? Math.round(recentPricePoints.reduce((acc, p) => acc + p.price, 0) / recentPricePoints.length)
    : (bestPrice ?? item.price)

  // Serial number of the viewer's copy if owned
  let userSerial: number | null = null
  if (owned && viewer) {
    const allOwners = await db.inventoryEntry.findMany({
      where: { itemId: id },
      orderBy: { acquiredAt: 'asc' },
      select: { userId: true },
    })
    const idx = allOwners.findIndex((e) => e.userId === viewer.id)
    if (idx !== -1) userSerial = idx + 1
  }

  // Effective buy price:
  // If in stock -> original price
  // If sold out limited -> best resale price
  const isSoldOutLimited = item.isLimited && item.stock != null && sold >= item.stock
  const effectiveBuyPrice = isSoldOutLimited ? (bestPrice ?? item.price) : item.price

  return NextResponse.json({
    item: {
      id: item.id,
      assetId: item.assetId,
      name: item.name,
      description: item.description,
      type: item.type,
      price: item.price,
      isLimited: item.isLimited,
      isSuperLimited: item.isSuperLimited ?? false,
      stock: item.isLimited ? item.stock : null,
      sold,
      remaining: item.isLimited && item.stock != null ? Math.max(0, item.stock - sold) : null,
      ownersBoost: item.ownersBoost,
      owners: sold + item.ownersBoost,
      buyPrice: effectiveBuyPrice,
      imageFileId: item.imageFileId,
      modelFileId: item.modelFileId,
      textureFileId: item.textureFileId,
      baseColor: item.baseColor,
      placement: parsePlacement(item.placementJson),
      animClips: parseAnimClipsJson(item.animClipsJson),
      animTarget: parseAnimTargetJson(item.animTargetJson),
      bundleParts: parseBundlePartsJson(item.bundlePartsJson),
      hasRig: item.hasRig,
      creator: item.creator,
      group: item.group,
      createdAt: item.createdAt,
    },
    owned,
    rap,
    bestPrice,
    userSerial,
    myListing: myListing ? { id: myListing.id, price: myListing.price, createdAt: myListing.createdAt } : null,
    resellers: activeListings.map((l) => ({
      id: l.id,
      price: l.price,
      title: l.title,
      createdAt: l.createdAt,
      seller: l.seller,
    })),
    priceLadder: null,
    sales: sales.map((s) => ({
      username: s.user.username,
      userId: s.user.id,
      avatarUrl: s.user.avatarUrl,
      at: s.acquiredAt,
      paid: item.price,
    })),
    canDelete: !!viewer && (isUserAdmin(viewer) || viewer.id === item.creatorId || (item.groupId && viewer.id === (await db.group.findUnique({ where: { id: item.groupId }, select: { ownerId: true } }))?.ownerId)),
  })
}

/** PATCH /api/catalog/[id] — the OWNER (creator, group owner, or site admin)
 *  edits their own item: name, description, price, the Limited flag and
 *  (new) the thumbnail/artwork image itself.
 *  The asset id, type and model never change — re-publish for that. */
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const item = await db.avatarItem.findUnique({ where: { id }, include: { group: { select: { ownerId: true } } } })
  if (!item) return NextResponse.json({ error: 'Item not found' }, { status: 404 })

  const isCreator = item.creatorId === user.id
  const isGroupOwner = !!item.group && item.group.ownerId === user.id
  const isAdmin = isUserAdmin(user)
  if (!isCreator && !isGroupOwner && !isAdmin) {
    return NextResponse.json({ error: 'Only the owner of this item can edit it.' }, { status: 403 })
  }

  const contentType = req.headers.get('content-type') || ''
  let body: Record<string, unknown> = {}
  let newImageFileId: string | null = null
  let newTextureFileId: string | null = null

  if (contentType.includes('multipart/form-data')) {
    const form = await req.formData()
    body = {
      name: form.get('name') ?? undefined,
      description: form.get('description') ?? undefined,
      price: form.get('price') ?? undefined,
      limited: form.get('limited') ?? undefined,
      stock: form.get('stock') ?? undefined,
      ownersBoost: form.get('ownersBoost') ?? undefined,
      color: form.get('color') ?? undefined,
      clearColor: form.get('clearColor') ?? undefined,
      clearTexture: form.get('clearTexture') ?? undefined,
    }
    const file = await resolveUpload(form.get('image'), form.get('imageUploadId'))
    if (file instanceof File && file.size > 0) {
      if (!file.type.startsWith('image/')) {
        return NextResponse.json({ error: 'The thumbnail must be an image.' }, { status: 400 })
      }
      if (file.size > 8 * 1024 * 1024) {
        return NextResponse.json({ error: 'The thumbnail is too large (max 8MB).' }, { status: 400 })
      }
      const saved = await saveUpload(file, user.id)
      newImageFileId = saved.id
    }
    const tex = await resolveUpload(form.get('texture'), form.get('textureUploadId'))
    if (tex instanceof File && tex.size > 0) {
      if (!tex.type.startsWith('image/')) {
        return NextResponse.json({ error: 'The texture must be an image (PNG / JPG).' }, { status: 400 })
      }
      if (tex.size > 8 * 1024 * 1024) {
        return NextResponse.json({ error: 'The texture is too large (max 8MB).' }, { status: 400 })
      }
      const saved = await saveUpload(tex, user.id)
      newTextureFileId = saved.id
    }
  } else {
    body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  }

  const data: { name?: string; description?: string; price?: number; isLimited?: boolean; imageFileId?: string; textureFileId?: string | null; baseColor?: string | null; stock?: number | null; ownersBoost?: number } = {}

  if (body.name !== undefined) {
    const name = String(body.name).trim()
    if (name.length < 3 || name.length > 40) {
      return NextResponse.json({ error: 'Name must be 3-40 characters.' }, { status: 400 })
    }
    data.name = name
  }
  if (body.description !== undefined) {
    data.description = String(body.description).trim().slice(0, 600)
  }
  if (body.price !== undefined || body.limited !== undefined) {
    const price = Math.floor(Number(body.price !== undefined ? body.price : item.price))
    const limited = body.limited !== undefined ? body.limited === true || body.limited === '1' : item.isLimited
    if (!Number.isFinite(price) || price < 0 || price > 1_000_000) {
      return NextResponse.json({ error: 'Price must be between T$ 0 and T$ 1,000,000.' }, { status: 400 })
    }
    if (limited && price < 1) {
      return NextResponse.json({ error: 'Limited items need a price of at least T$ 1.' }, { status: 400 })
    }
    // LIMITED PRICE LOCK: a limited's (original) price is frozen the moment it
    // exists — its value RISES with sales, so letting the creator cut it later
    // would cheat every buyer. Only a site admin can touch it.
    if (limited && !isAdmin && item.isLimited && price !== item.price) {
      return NextResponse.json(
        { error: 'A limited\u2019s price is locked — it rises automatically with every sale. Only a site admin can change the original price.' },
        { status: 403 }
      )
    }
    data.price = price
    data.isLimited = limited
  }
  if (body.superLimited !== undefined) {
    data.isSuperLimited = body.superLimited === true || body.superLimited === '1'
    if (data.isSuperLimited) data.isLimited = true
  }
  if (body.placement !== undefined) {
    data.placementJson = String(body.placement).slice(0, 500)
  }
  // limited stock — the total print run. The creator OR an admin can set it;
  // lowering it below the copies already sold instantly means SOLD OUT.
  if (body.stock !== undefined) {
    const raw = String(body.stock).trim()
    if (raw === '') {
      data.stock = null // unlimited
    } else {
      const n = Math.floor(Number(raw))
      if (!Number.isFinite(n) || n < 1) {
        return NextResponse.json({ error: 'Stock must be 1 or more copies (empty = unlimited).' }, { status: 400 })
      }
      data.stock = n
    }
  }
  // displayed buyers boost — ADMIN ONLY (the real ledger never changes)
  if (body.ownersBoost !== undefined && String(body.ownersBoost).trim() !== '') {
    if (!isAdmin) {
      return NextResponse.json({ error: 'Only a site admin can change the displayed owners count.' }, { status: 403 })
    }
    const n = Math.floor(Number(body.ownersBoost))
    if (!Number.isFinite(n) || n < 0) {
      return NextResponse.json({ error: 'The owners boost must be 0 or more.' }, { status: 400 })
    }
    data.ownersBoost = n
  }
  if (newImageFileId) {
    data.imageFileId = newImageFileId
  }
  // texture / tint — only meaningful on 3D UGC; owners can swap or clear them
  if (item.modelFileId) {
    if (newTextureFileId) {
      data.textureFileId = newTextureFileId
      data.baseColor = null // a texture replaces the tint
    }
    if (body.clearTexture === '1' || body.clearTexture === 1 || body.clearTexture === true) {
      data.textureFileId = null
    }
    if (body.color !== undefined && body.color !== null && String(body.color).trim() !== '') {
      const color = String(body.color).trim()
      if (!/^#[0-9a-fA-F]{6}$/.test(color)) {
        return NextResponse.json({ error: 'The color must be a hex color like #4da6ff.' }, { status: 400 })
      }
      data.baseColor = color.toLowerCase()
      if (!newTextureFileId) data.textureFileId = item.textureFileId // keep texture if present
    }
    if (body.clearColor === '1' || body.clearColor === 1 || body.clearColor === true) {
      data.baseColor = null
    }
  }

  if (Object.keys(data).length === 0) {
    return NextResponse.json({ error: 'Nothing to change.' }, { status: 400 })
  }

  const updated = await db.avatarItem.update({ where: { id }, data })
  const updatedSold = await db.inventoryEntry.count({
    where: { itemId: id, NOT: { userId: updated.creatorId } },
  })
  return NextResponse.json({
    ok: true,
    item: {
      id: updated.id,
      assetId: updated.assetId,
      name: updated.name,
      description: updated.description,
      price: updated.price,
      isLimited: updated.isLimited,
      stock: updated.stock,
      sold: updatedSold,
      remaining: updated.isLimited && updated.stock != null ? Math.max(0, updated.stock - updatedSold) : null,
      owners: updatedSold + updated.ownersBoost,
      buyPrice: buyPrice(updated, updatedSold),
    },
  })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as { action?: string }

  if (body.action === 'get') {
    const item = await db.avatarItem.findUnique({ where: { id }, select: { id: true, name: true } })
    if (!item) return NextResponse.json({ error: 'Item not found' }, { status: 404 })
    await db.inventoryEntry.upsert({
      where: { userId_itemId: { userId: user.id, itemId: id } },
      update: {},
      create: { userId: user.id, itemId: id },
    })
    return NextResponse.json({ ok: true, message: `"${item.name}" is in your inventory now.` })
  }

  if (body.action === 'buy') {
    const nameGuess = await db.avatarItem.findUnique({ where: { id }, select: { name: true } })
    if (!nameGuess) return NextResponse.json({ error: 'Item not found' }, { status: 404 })

    // EVERYTHING happens inside ONE transaction: the sold count, the stock
    // check and the RISING price are all computed from the same snapshot, so
    // two buyers racing the last copy of a limited can never both win, and
    // nobody ever buys at a stale price.
    try {
      const result = await db.$transaction(async (tx) => {
        const item = await tx.avatarItem.findUnique({
          where: { id },
          select: { id: true, name: true, assetId: true, price: true, isLimited: true, isSuperLimited: true, stock: true, creatorId: true, deletedAt: true },
        })
        if (!item || item.deletedAt) throw new RbxError('NO_ITEM', 'Item not found')

        const already = await tx.inventoryEntry.findUnique({
          where: { userId_itemId: { userId: user.id, itemId: id } },
          select: { id: true },
        })
        if (already) throw new RbxError('ALREADY', 'You already own this item.')

        const sold = await tx.inventoryEntry.count({
          where: { itemId: id, NOT: { userId: item.creatorId } },
        })
        const inStock = (!item.isLimited && !item.isSuperLimited) || item.isSuperLimited || item.stock == null || sold < item.stock

        if (!inStock) {
          // Limited item is sold out in the mint shop -> buy from active resellers!
          const reqListingId = (body as { listingId?: string }).listingId
          const listing = reqListingId
            ? await tx.ugcListing.findUnique({
                where: { id: String(reqListingId) },
                include: { seller: { select: { id: true, username: true, rbxBalance: true } } },
              })
            : await tx.ugcListing.findFirst({
                where: { itemId: id, status: 'active', sellerId: { not: user.id } },
                orderBy: { price: 'asc' },
                include: { seller: { select: { id: true, username: true, rbxBalance: true } } },
              })

          if (!listing || listing.status !== 'active') {
            throw new RbxError('SOLD_OUT', `"${item.name}" is SOLD OUT and has no active resellers right now. Trade for it!`)
          }
          if (listing.sellerId === user.id) {
            throw new RbxError('SELF', 'You cannot buy your own listing!')
          }

          const buyer = await tx.user.findUnique({ where: { id: user.id }, select: { rbxBalance: true } })
          if (!buyer) throw new RbxError('NO_USER', 'That account does not exist.')
          if (buyer.rbxBalance < listing.price) {
            throw new RbxError('INSUFFICIENT', `Not enough Tix ? this copy costs T$ ${listing.price.toLocaleString('en-US')}.`)
          }

          const fee = Math.floor(listing.price * 0.10)
          const payout = listing.price - fee
          const buyerAfter = buyer.rbxBalance - listing.price
          const sellerAfter = listing.seller.rbxBalance + payout

          await tx.user.update({ where: { id: user.id }, data: { rbxBalance: buyerAfter } })
          await tx.user.update({ where: { id: listing.sellerId }, data: { rbxBalance: sellerAfter } })

          await tx.rbxTransaction.create({
            data: {
              userId: user.id,
              amount: -listing.price,
              type: 'spend',
              balanceBefore: buyer.rbxBalance,
              balanceAfter: buyerAfter,
              note: `Bought "${item.name}" from @${listing.seller.username} (Resale)`,
            },
          })
          await tx.rbxTransaction.create({
            data: {
              userId: listing.sellerId,
              amount: payout,
              type: 'admin_grant',
              balanceBefore: listing.seller.rbxBalance,
              balanceAfter: sellerAfter,
              note: `Sold "${item.name}" on the market (-10% fee)`,
            },
          })

          await tx.inventoryEntry.deleteMany({ where: { userId: listing.sellerId, itemId: id } })
          await tx.inventoryEntry.create({ data: { userId: user.id, itemId: id } })

          await tx.ugcListing.update({
            where: { id: listing.id },
            data: { status: 'sold', buyerId: user.id, soldPrice: listing.price, soldAt: new Date() },
          })

          await tx.ugcPricePoint.create({
            data: {
              itemId: id,
              price: listing.price,
              kind: 'resale',
              buyerId: user.id,
              sellerId: listing.sellerId,
            },
          })

          return {
            message: `Bought "${item.name}" from @${listing.seller.username} for T$ ${listing.price.toLocaleString('en-US')}!`,
            balanceAfter: buyerAfter,
          }
        }

        const cost = item.price // original mint price

        if (cost <= 0 || item.creatorId === user.id) {
          await tx.inventoryEntry.create({ data: { userId: user.id, itemId: id } })
          return { message: cost <= 0 ? `"${item.name}" is yours ? it was free!` : `"${item.name}" is in your inventory now.`, balanceAfter: null as number | null }
        }

        const buyer = await tx.user.findUnique({ where: { id: user.id }, select: { rbxBalance: true } })
        if (!buyer) throw new RbxError('NO_USER', 'That account does not exist.')
        if (buyer.rbxBalance < cost) {
          throw new RbxError('INSUFFICIENT', `Not enough Tix ? this costs T$ ${cost.toLocaleString('en-US')}.`)
        }

        const after = buyer.rbxBalance - cost
        await tx.user.update({ where: { id: user.id }, data: { rbxBalance: after } })
        await tx.rbxTransaction.create({
          data: {
            userId: user.id,
            amount: -cost,
            type: 'spend',
            balanceBefore: buyer.rbxBalance,
            balanceAfter: after,
            note: `Bought "${item.name}" (${item.assetId})${item.isLimited ? ` ? LIMITED #${sold + 1}${item.stock != null ? `/${item.stock}` : ''}` : ''}`,
          },
        })
        await tx.inventoryEntry.create({ data: { userId: user.id, itemId: id } })
        await tx.ugcPricePoint.create({
          data: {
            itemId: id,
            price: cost,
            kind: 'mint',
            buyerId: user.id,
            sellerId: item.creatorId,
          },
        })

        // Super limited doubles its price on every purchase!
        if (item.isSuperLimited) {
          const nextPrice = Math.max(1, cost * 2)
          await tx.avatarItem.update({ where: { id }, data: { price: nextPrice } })
        }

        return {
          message: item.isSuperLimited
            ? `"${item.name}" is yours! (Super Limited price doubled to T$ ${(Math.max(1, cost * 2)).toLocaleString('en-US')}!) T$ ${after.toLocaleString('en-US')} left.`
            : `"${item.name}" is yours! T$ ${after.toLocaleString('en-US')} left.`,
          balanceAfter: after,
        }
      })
      return NextResponse.json({ ok: true, message: result.message, balanceAfter: result.balanceAfter ?? undefined })
    } catch (e) {
      if (e instanceof RbxError) {
        const status = e.code === 'INSUFFICIENT' ? 400 : e.code === 'NO_ITEM' ? 404 : 400
        return NextResponse.json({ error: e.message }, { status })
      }
      throw e
    }
  }

  // admin-only restore of the old soft delete — REMOVED. Delete means delete:
  // the row is gone, there is nothing to restore.
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const item = await db.avatarItem.findUnique({ where: { id }, include: { group: { select: { ownerId: true } } } })
  if (!item) return NextResponse.json({ error: 'Item not found' }, { status: 404 })

  const isCreator = item.creatorId === user.id
  const isGroupOwner = !!item.group && item.group.ownerId === user.id
  const isAdmin = isUserAdmin(user)
  if (!isCreator && !isGroupOwner && !isAdmin) {
    return NextResponse.json({ error: 'Only the creator, the group owner, or an admin can delete UGC.' }, { status: 403 })
  }

  // HARD delete — remove means remove. The row (and every inventory copy
  // through the cascade) is gone from the database for real; there is no
  // recycle bin and no restore. The full-screen confirm on the catalog card
  // exists exactly because this cannot be undone.
  await db.avatarItem.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
