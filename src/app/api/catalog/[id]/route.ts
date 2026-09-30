import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { parsePlacement, parseAnimClipsJson, parseAnimTargetJson, parseBundlePartsJson } from '@/lib/avatarAssets'
import { buyPrice, RbxError } from '@/lib/rbx'
import { resaleValue, parseIdArray as parseIdArraySafe } from '@/lib/market'
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
  // trade targeting: press Trade beside an item -> offer the person who
  // currently sells it (cheapest active listing) or, with no listing, the
  // creator (who holds the master copy). Owners pressing Trade get routed
  // to the incoming offers below instead.
  const cheapestListing = await db.ugcListing.findFirst({
    where: { itemId: id, status: 'active' },
    orderBy: { price: 'asc' },
    select: { seller: { select: { id: true, username: true } } },
  })
  const tradeTarget = cheapestListing?.seller ?? { id: item.creator.id, username: item.creator.username }
  // pending TRADES that request this item (the owner's "offers waiting" list)
  const pendingTradeRows = await db.ugcTrade.findMany({
    where: { toUserId: tradeTarget.id, status: 'pending', takeItemIds: { contains: `"${id}"` } },
    orderBy: { updatedAt: 'desc' },
    take: 12,
    select: {
      id: true,
      tixFrom: true,
      giveItemIds: true,
      fromUser: { select: { id: true, username: true, avatarUrl: true } },
    },
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
  return NextResponse.json({
    item: {
      id: item.id,
      assetId: item.assetId,
      name: item.name,
      description: item.description,
      type: item.type,
      price: item.price, // limiteds: the ORIGINAL price
      isLimited: item.isLimited,
      stock: item.isLimited ? item.stock : null,
      sold,
      remaining: item.isLimited && item.stock != null ? Math.max(0, item.stock - sold) : null,
      ownersBoost: item.ownersBoost,
      owners: sold + item.ownersBoost,
      buyPrice: buyPrice(item, sold), // limiteds: the DOUBLING price
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
    // who a Trade button should open a trade with (listing seller ?? creator)
    tradeTarget,
    // the owner's waiting room: pending trades that want THIS item
    incomingTrades: pendingTradeRows.map((t) => ({
      id: t.id,
      tixFrom: t.tixFrom,
      giveItemIds: parseIdArraySafe(t.giveItemIds),
      fromUser: t.fromUser,
    })),
    // ---- the RESALE MARKET for this item (player-to-player economy) ----
    market: await marketData(id, item, viewer),
    // the ladder of prices this limited will climb (original, x2, x4...) —
    // the detail page draws its price chart from this
    priceLadder: item.isLimited
      ? Array.from({ length: Math.min(item.stock ?? sold + 6, Math.max(sold + 6, 8)) + 1 }, (_, k) => ({
          soldAfter: k,
          price: buyPrice(item, k),
        }))
      : null,
    sales: sales.map((s) => ({
      username: s.user.username,
      userId: s.user.id,
      avatarUrl: s.user.avatarUrl,
      at: s.acquiredAt,
      // the price THAT buyer paid (sale #k paid ladder[k-1])
      paid: item.isLimited ? buyPrice(item, Math.max(0, sold - sales.indexOf(s) - 1)) : buyPrice(item, sold),
    })),
    canDelete: !!viewer && (viewer.role === 'admin' || viewer.id === item.creatorId || (item.groupId && viewer.id === (await db.group.findUnique({ where: { id: item.groupId }, select: { ownerId: true } }))?.ownerId)),
  })
}

/** Everything the item page's Resale Market panel needs: active listings,
 *  the viewer's involvement, the real sale history (the market graph) and
 *  the viewer's own copy's serial + suggested 1.5x resale value. */
async function marketData(
  id: string,
  item: { price: number },
  viewer: { id: string } | null
) {
  const listings = await db.ugcListing.findMany({
    where: { itemId: id, status: 'active' },
    orderBy: { price: 'asc' },
    take: 20,
    include: {
      seller: { select: { id: true, username: true, avatarUrl: true } },
      offers: { where: { status: 'pending' }, select: { amount: true } },
    },
  })
  // the REAL market history — every mint + resale, oldest first (graph X axis)
  const history = await db.ugcPricePoint.findMany({
    where: { itemId: id },
    orderBy: { createdAt: 'asc' },
    take: 120,
    select: { price: true, kind: true, createdAt: true },
  })
  let myListing: string | null = null
  let myOffer: { id: string; amount: number } | null = null
  let mySerial: number | null = null
  let suggestedPrice: number | null = null
  if (viewer) {
    myListing = listings.find((l) => l.sellerId === viewer.id)?.id ?? null
    const offer = await db.ugcOffer.findFirst({
      where: { buyerId: viewer.id, status: 'pending', listing: { itemId: id, status: 'active' } },
      orderBy: { createdAt: 'desc' },
      select: { id: true, amount: true },
    })
    myOffer = offer ? { id: offer.id, amount: offer.amount } : null
    const copy = await db.inventoryEntry.findUnique({
      where: { userId_itemId: { userId: viewer.id, itemId: id } },
      select: { serial: true },
    })
    mySerial = copy?.serial ?? null
    if (copy) {
      const paid = await db.ugcPricePoint.findFirst({
        where: { itemId: id, buyerId: viewer.id },
        orderBy: { createdAt: 'desc' },
        select: { price: true },
      })
      suggestedPrice = resaleValue(paid?.price ?? 0, item.price)
    }
  }
  return {
    listings: listings.map((l) => ({
      id: l.id,
      price: l.price,
      createdAt: l.createdAt,
      seller: l.seller,
      offerCount: l.offers.length,
      topOffer: l.offers.reduce((m, o) => Math.max(m, o.amount), 0),
    })),
    history: history.map((h) => ({ price: h.price, kind: h.kind, at: h.createdAt })),
    myListing,
    myOffer,
    mySerial,
    suggestedPrice,
  }
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
  const isAdmin = user.role === 'admin'
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
          select: { id: true, name: true, assetId: true, price: true, isLimited: true, stock: true, creatorId: true, deletedAt: true },
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
        if (item.isLimited && item.stock != null && sold >= item.stock) {
          throw new RbxError('SOLD_OUT', `"${item.name}" is SOLD OUT — all ${item.stock} copies are gone forever.`)
        }

        const cost = buyPrice(item, sold) // limiteds: the rising price, fresh from the count

        if (cost <= 0 || item.creatorId === user.id) {
          // free item (or the creator grabbing a spare copy) — no money moves
          await tx.inventoryEntry.create({
            data: { userId: user.id, itemId: id, serial: item.isLimited ? sold + 1 : null },
          })
          return { message: cost <= 0 ? `"${item.name}" is yours — it was free!` : `"${item.name}" is in your inventory now.`, balanceAfter: null as number | null, creatorId: item.creatorId, itemName: item.name, assetId: item.assetId, serial: item.isLimited ? sold + 1 : (null as number | null), paid: 0 }
        }

        const buyer = await tx.user.findUnique({ where: { id: user.id }, select: { rbxBalance: true } })
        if (!buyer) throw new RbxError('NO_USER', 'That account does not exist.')
        if (buyer.rbxBalance < cost) {
          throw new RbxError('INSUFFICIENT', `Not enough Tix — this costs T$ ${cost.toLocaleString('en-US')}${item.isLimited && item.stock != null ? ` (only ${Math.max(0, item.stock - sold - 1)} left!)` : ''}. Top up in the Tix Store!`)
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
            note: `Bought "${item.name}" (${item.assetId})${item.isLimited ? ` — LIMITED #${sold + 1}${item.stock != null ? `/${item.stock}` : ''}` : ''}`,
          },
        })
        // LIMITED copies get a permanent serial (copy #3 of 25 stays #3 forever,
        // even after trades and resales) — and every sale lands on the market graph
        await tx.inventoryEntry.create({ data: { userId: user.id, itemId: id, serial: item.isLimited ? sold + 1 : null } })
        await tx.ugcPricePoint.create({ data: { itemId: id, price: cost, kind: 'mint', buyerId: user.id, sellerId: item.creatorId } })
        return { message: `"${item.name}" is yours! T$ ${after.toLocaleString('en-US')} left.`, balanceAfter: after, creatorId: item.creatorId, itemName: item.name, assetId: item.assetId, serial: item.isLimited ? sold + 1 : (null as number | null), paid: cost }
      })
      // the creator's bell rings after the sale commits (never blocks the purchase)
      if (result.creatorId && result.creatorId !== user.id && result.paid > 0) {
        try {
          await db.notification.create({
            data: {
              userId: result.creatorId,
              type: 'listing_sold',
              title: `"${result.itemName}" just sold!`,
              body: `T$ ${result.paid.toLocaleString('en-US')} — someone bought your creation straight from the catalog.`,
              link: `/catalog/${id}`,
            },
          })
        } catch { /* ignore */ }
      }
      return NextResponse.json({ ok: true, message: result.message, balanceAfter: result.balanceAfter ?? undefined, serial: result.serial ?? undefined })
    } catch (e) {
      if (e instanceof RbxError) {
        const status = e.code === 'INSUFFICIENT' ? 400 : e.code === 'NO_ITEM' ? 404 : 400
        return NextResponse.json({ error: e.message }, { status })
      }
      throw e
    }
  }

  // admin-only: undo a soft delete — the item goes straight back to the catalog
  if (body.action === 'restore') {
    if (user.role !== 'admin') return NextResponse.json({ error: 'Only an admin can restore UGC.' }, { status: 403 })
    const item = await db.avatarItem.findUnique({ where: { id }, select: { id: true, name: true, deletedAt: true } })
    if (!item) return NextResponse.json({ error: 'Item not found' }, { status: 404 })
    if (!item.deletedAt) return NextResponse.json({ error: 'This item is not deleted.' }, { status: 400 })
    await db.avatarItem.update({ where: { id }, data: { deletedAt: null } })
    return NextResponse.json({ ok: true, message: `"${item.name}" is back in the catalog.` })
  }

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
  const isAdmin = user.role === 'admin'
  if (!isCreator && !isGroupOwner && !isAdmin) {
    return NextResponse.json({ error: 'Only the creator, the group owner, or an admin can delete UGC.' }, { status: 403 })
  }

  // SOFT delete — the row (and its files) stay in the database forever, so
  // "some ugc got deleted" can never mean "gone for good": an admin can
  // always restore it from the catalog's Deleted UGC panel.
  await db.avatarItem.update({ where: { id }, data: { deletedAt: new Date() } })
  return NextResponse.json({ ok: true })
}
