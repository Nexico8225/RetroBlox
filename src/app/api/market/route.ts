import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { MarketError, moveTix, moveRobux, transferItem, pricePoint, notify, paidByOwner, resaleValue, parseIdArray, assertOwnsAll } from '@/lib/market'

/**
 * GET /api/market                — everything active on the resale market
 * GET /api/market?itemId=<id>    — the listings for one item (+ my involvement)
 * GET /api/market?mine=1         — my listings + offers I received / sent
 *
 * POST /api/market — { action, ... }
 *   list          {itemId, price, title?, description?}      put a copy up for sale (pitch it!)
 *   set_price     {listingId, price}                 lower the asking price while haggling
 *   cancel        {listingId}                        take the listing down
 *   buy           {listingId}                        buy NOW at the asking price
 *   offer         {listingId, amount, robux?, offerItemIds?, message?}
 *                                                    send Tix and/or Robux and/or UGC — the seller takes a guess to keep
 *                                                    the item or hand it over (accept = everything swaps)
 *   accept_offer  {offerId}                          seller accepts: they get the Tix + Robux + offered UGC, the buyer gets the item
 *   decline_offer {offerId}                          seller declines
 */

const LISTING_TITLE_MAX = 80
const LISTING_DESC_MAX = 300
const MAX_OFFER_ITEMS = 4

/** Offer previews for every offer row the UI is about to render —
 *  the buyer's UGC-on-the-table shown as chips next to the Tix. */
async function offerItemMapFor(offers: { offerItemIdsJson: string }[]) {
  const ids = new Set<string>()
  for (const o of offers) for (const id of parseIdArray(o.offerItemIdsJson)) ids.add(id)
  if (!ids.size) return {}
  const items = await db.avatarItem.findMany({
    where: { id: { in: [...ids] } },
    select: { id: true, name: true, type: true, imageFileId: true, isLimited: true },
  })
  return Object.fromEntries(items.map((i) => [i.id, i]))
}
export async function GET(req: NextRequest) {
  const url = new URL(req.url)
  const viewer = await getUserFromReq(req)
  const itemId = url.searchParams.get('itemId') || ''
  const mine = url.searchParams.get('mine') === '1'

  if (mine) {
    if (!viewer) return NextResponse.json({ error: 'Login required' }, { status: 401 })
    const listings = await db.ugcListing.findMany({
      where: { sellerId: viewer.id },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: {
        item: { select: { id: true, assetId: true, name: true, type: true, imageFileId: true, isLimited: true, price: true, stock: true } },
        offers: { where: { status: 'pending' }, orderBy: { createdAt: 'desc' }, include: { buyer: { select: { id: true, username: true, avatarUrl: true } } } },
        _count: { select: { messages: true } },
      },
    })
    const offersSent = await db.ugcOffer.findMany({
      where: { buyerId: viewer.id },
      orderBy: { createdAt: 'desc' },
      take: 30,
      include: {
        listing: {
          include: {
            item: { select: { id: true, assetId: true, name: true, type: true, imageFileId: true, isLimited: true } },
            seller: { select: { id: true, username: true, avatarUrl: true } },
          },
        },
      },
    })
    const offerItemMap = await offerItemMapFor([...listings.flatMap((l) => l.offers), ...offersSent])
    return NextResponse.json({ listings, offersSent, offerItemMap })
  }

  if (itemId) {
    const listings = await db.ugcListing.findMany({
      where: { itemId, status: 'active' },
      orderBy: { price: 'asc' },
      take: 20,
      include: {
        seller: { select: { id: true, username: true, avatarUrl: true } },
        offers: { where: { status: 'pending' }, select: { amount: true, buyerId: true } },
      },
    })
    const soldHistory = await db.ugcListing.findMany({
      where: { itemId, status: 'sold' },
      orderBy: { soldAt: 'desc' },
      take: 10,
      select: { soldPrice: true, soldAt: true, seller: { select: { username: true } }, buyer: { select: { username: true } } },
    })
    let myListing: string | null = null
    let myOffer: { id: string; amount: number } | null = null
    let suggestedPrice: number | null = null
    if (viewer) {
      const mine = listings.find((l) => l.sellerId === viewer.id)
      myListing = mine?.id ?? null
      const sent = await db.ugcOffer.findFirst({
        where: { buyerId: viewer.id, status: 'pending', listing: { itemId, status: 'active' } },
        orderBy: { createdAt: 'desc' },
        select: { id: true, amount: true },
      })
      myOffer = sent ? { id: sent.id, amount: sent.amount } : null
      const owned = await db.inventoryEntry.findUnique({
        where: { userId_itemId: { userId: viewer.id, itemId } },
        select: { serial: true },
      })
      if (owned) {
        const item = await db.avatarItem.findUnique({ where: { id: itemId }, select: { price: true } })
        if (item) suggestedPrice = resaleValue(await paidByOwner(itemId, viewer.id), item.price)
      }
    }
    return NextResponse.json({
      listings: listings.map((l) => ({ id: l.id, title: l.title, price: l.price, createdAt: l.createdAt, seller: l.seller, offerCount: l.offers.length, topOffer: l.offers.reduce((m, o) => Math.max(m, o.amount), 0) })),
      soldHistory,
      myListing,
      myOffer,
      suggestedPrice,
    })
  }

  // the whole active market — newest first, for the market browser
  const listings = await db.ugcListing.findMany({
    where: { status: 'active' },
    orderBy: { createdAt: 'desc' },
    take: 60,
    include: {
      item: { select: { id: true, assetId: true, name: true, type: true, imageFileId: true, isLimited: true, price: true, stock: true } },
      seller: { select: { id: true, username: true, avatarUrl: true } },
      _count: { select: { offers: true } },
    },
  })
  return NextResponse.json({ listings, offerItemMap: {} })
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const action = String(body.action || '')

  try {
    // ---------------- list a copy for sale (with a pitch) ----------------
    if (action === 'list') {
      const itemId = String(body.itemId || '')
      const price = Math.floor(Number(body.price))
      const title = String(body.title || '').trim().slice(0, LISTING_TITLE_MAX)
      const description = String(body.description || '').trim().slice(0, LISTING_DESC_MAX)
      if (!Number.isFinite(price) || price < 1 || price > 1_000_000) {
        return NextResponse.json({ error: 'Asking price must be between T$ 1 and T$ 1,000,000.' }, { status: 400 })
      }
      const item = await db.avatarItem.findUnique({ where: { id: itemId }, select: { id: true, name: true, deletedAt: true } })
      if (!item || item.deletedAt) return NextResponse.json({ error: 'Item not found.' }, { status: 404 })
      const dup = await db.ugcListing.findFirst({ where: { itemId, sellerId: user.id, status: 'active' } })
      if (dup) return NextResponse.json({ error: 'You already have this copy up for sale — lower its price instead.' }, { status: 400 })
      await db.$transaction(async (tx) => {
        const owned = await tx.inventoryEntry.findUnique({ where: { userId_itemId: { userId: user.id, itemId } }, select: { id: true } })
        if (!owned) throw new MarketError('NOT_OWNED', 'You do not own this item.')
        await tx.ugcListing.create({ data: { itemId, sellerId: user.id, price, title, description } })
      })
      return NextResponse.json({ ok: true, message: `"${item.name}" is on the market for T$ ${price.toLocaleString('en-US')}.` })
    }

    // ---------------- lower the asking price (haggling) ----------------
    if (action === 'set_price') {
      const listingId = String(body.listingId || '')
      const price = Math.floor(Number(body.price))
      if (!Number.isFinite(price) || price < 1 || price > 1_000_000) {
        return NextResponse.json({ error: 'Price must be between T$ 1 and T$ 1,000,000.' }, { status: 400 })
      }
      const listing = await db.ugcListing.findUnique({ where: { id: listingId } })
      if (!listing) return NextResponse.json({ error: 'Listing not found.' }, { status: 404 })
      if (listing.sellerId !== user.id) return NextResponse.json({ error: 'Only the seller can change the price.' }, { status: 403 })
      if (listing.status !== 'active') return NextResponse.json({ error: 'This listing is no longer active.' }, { status: 400 })
      await db.ugcListing.update({ where: { id: listingId }, data: { price } })
      // let everyone with a pending offer know the price moved
      const offerers = await db.ugcOffer.findMany({
        where: { listingId, status: 'pending' },
        select: { buyerId: true, amount: true },
      })
      for (const o of offerers) {
        if (o.buyerId === user.id) continue
        await notify(o.buyerId, {
          type: 'listing_offer',
          title: 'The price dropped!',
          body: `A seller lowered their asking price to T$ ${price.toLocaleString('en-US')} (you offered T$ ${o.amount.toLocaleString('en-US')}).`,
          link: `/catalog/${listing.itemId}`,
        })
      }
      return NextResponse.json({ ok: true, message: `Asking price is now T$ ${price.toLocaleString('en-US')}.` })
    }

    // ---------------- take the listing down ----------------
    if (action === 'cancel') {
      const listingId = String(body.listingId || '')
      const listing = await db.ugcListing.findUnique({ where: { id: listingId } })
      if (!listing) return NextResponse.json({ error: 'Listing not found.' }, { status: 404 })
      if (listing.sellerId !== user.id) return NextResponse.json({ error: 'Only the seller can cancel.' }, { status: 403 })
      if (listing.status !== 'active') return NextResponse.json({ error: 'This listing is no longer active.' }, { status: 400 })
      await db.$transaction(async (tx) => {
        await tx.ugcListing.update({ where: { id: listingId }, data: { status: 'cancelled' } })
        await tx.ugcOffer.updateMany({ where: { listingId, status: 'pending' }, data: { status: 'cancelled', respondedAt: new Date() } })
      })
      return NextResponse.json({ ok: true, message: 'Listing taken down.' })
    }

    // ---------------- buy NOW at the asking price ----------------
    if (action === 'buy') {
      const listingId = String(body.listingId || '')
      const result = await db.$transaction(async (tx) => {
        const listing = await tx.ugcListing.findUnique({
          where: { id: listingId },
          include: { item: { select: { id: true, name: true, price: true } } },
        })
        if (!listing) throw new MarketError('NO_LISTING', 'Listing not found.')
        if (listing.status !== 'active') throw new MarketError('NOT_ACTIVE', 'This listing is gone — someone else was faster.')
        if (listing.sellerId === user.id) throw new MarketError('SELF', 'That is your own listing!')
        const owned = await tx.inventoryEntry.findUnique({
          where: { userId_itemId: { userId: listing.sellerId, itemId: listing.itemId } },
          select: { id: true },
        })
        if (!owned) throw new MarketError('NOT_OWNED', 'The seller no longer owns this copy.')

        const buyer = await tx.user.findUnique({ where: { id: user.id }, select: { rbxBalance: true } })
        if (!buyer) throw new MarketError('NO_USER', 'That account does not exist.')
        if (buyer.rbxBalance < listing.price) {
          throw new MarketError('NO_FUNDS', `Not enough Tix — it costs T$ ${listing.price.toLocaleString('en-US')} and you have T$ ${buyer.rbxBalance.toLocaleString('en-US')}.`)
        }

        await moveTix(tx, user.id, listing.sellerId, listing.price, `Bought "${listing.item.name}" from the resale market`)
        await transferItem(tx, listing.itemId, listing.sellerId, user.id)
        await tx.ugcListing.update({
          where: { id: listingId },
          data: { status: 'sold', buyerId: user.id, soldPrice: listing.price, soldAt: new Date() },
        })
        await tx.ugcOffer.updateMany({ where: { listingId, status: 'pending' }, data: { status: 'cancelled', respondedAt: new Date() } })
        await pricePoint(tx, listing.itemId, listing.price, 'resale', user.id, listing.sellerId)
        return { sellerId: listing.sellerId, itemName: listing.item.name, itemId: listing.itemId, cost: listing.price }
      })
      await notify(result.sellerId, {
        type: 'listing_sold',
        title: `"${result.itemName}" sold!`,
        body: `T$ ${result.cost.toLocaleString('en-US')} was paid into your wallet.`,
        link: `/catalog/${result.itemId}`,
      })
      return NextResponse.json({ ok: true, message: `"${result.itemName}" is yours! T$ ${result.cost.toLocaleString('en-US')} paid.` })
    }

    // ---------------- send an offer (Tix and/or Robux and/or UGC — the seller decides) ----------------
    if (action === 'offer') {
      const listingId = String(body.listingId || '')
      const amount = Math.max(0, Math.floor(Number(body.amount) || 0))
      const robux = Math.max(0, Math.floor(Number(body.robux) || 0))
      const offerItemIds = [...new Set(parseIdArray(JSON.stringify(body.offerItemIds ?? [])))]
      const message = String(body.message || '').trim().slice(0, 300)
      if (amount > 1_000_000 || robux > 1_000_000) {
        return NextResponse.json({ error: 'Offers must be between 1 and 1,000,000.' }, { status: 400 })
      }
      if (offerItemIds.length > MAX_OFFER_ITEMS) {
        return NextResponse.json({ error: `Keep it to ${MAX_OFFER_ITEMS} items on the table.` }, { status: 400 })
      }
      if (amount < 1 && robux < 1 && offerItemIds.length === 0) {
        return NextResponse.json({ error: 'Offer some Tix, some Robux or some UGC — an empty offer is just a wave.' }, { status: 400 })
      }
      const listing = await db.ugcListing.findUnique({ where: { id: listingId } })
      if (!listing) return NextResponse.json({ error: 'Listing not found.' }, { status: 404 })
      if (listing.status !== 'active') return NextResponse.json({ error: 'This listing is no longer active.' }, { status: 400 })
      if (listing.sellerId === user.id) return NextResponse.json({ error: 'That is your own listing!' }, { status: 400 })
      if (offerItemIds.includes(listing.itemId)) {
        return NextResponse.json({ error: 'That is the item being sold — offer something else!' }, { status: 400 })
      }
      const dup = await db.ugcOffer.findFirst({ where: { listingId, buyerId: user.id, status: 'pending' } })
      if (dup) return NextResponse.json({ error: 'You already have a pending offer here — wait for an answer or send a message.' }, { status: 400 })
      // early sanity so nothing weird lands on the table: I own what I put up,
      // and the seller can never receive an item they already own (one per member)
      if (offerItemIds.length) {
        await db.$transaction(async (tx) => {
          await assertOwnsAll(tx, user.id, offerItemIds)
          for (const itId of offerItemIds) {
            const sellerHas = await tx.inventoryEntry.findUnique({
              where: { userId_itemId: { userId: listing.sellerId, itemId: itId } },
              select: { id: true },
            })
            if (sellerHas) {
              const it = await tx.avatarItem.findUnique({ where: { id: itId }, select: { name: true } })
              throw new MarketError('ALREADY_OWNED', `The seller already owns "${it?.name || 'that item'}" — pick something they don't have.`)
            }
          }
          if (amount > 0) {
            const u = await tx.user.findUnique({ where: { id: user.id }, select: { rbxBalance: true } })
            if (!u || u.rbxBalance < amount) {
              throw new MarketError('NO_FUNDS', `You only have T$ ${(u?.rbxBalance ?? 0).toLocaleString('en-US')} — not enough for this offer.`)
            }
          }
          if (robux > 0) {
            const u = await tx.user.findUnique({ where: { id: user.id }, select: { robuxBalance: true } })
            if (!u || u.robuxBalance < robux) {
              throw new MarketError('NO_ROBUX', `You only have R$ ${(u?.robuxBalance ?? 0).toLocaleString('en-US')} — not enough Robux for this offer.`)
            }
          }
        })
      }
      const offer = await db.ugcOffer.create({ data: { listingId, buyerId: user.id, amount, robux, offerItemIdsJson: JSON.stringify(offerItemIds) } })
      if (message) {
        await db.ugcListingMessage.create({ data: { listingId, senderId: user.id, text: message } })
      }
      const item = await db.avatarItem.findUnique({ where: { id: listing.itemId }, select: { name: true } })
      const offerBits = [
        amount > 0 ? `T$ ${amount.toLocaleString('en-US')}` : '',
        robux > 0 ? `R$ ${robux.toLocaleString('en-US')}` : '',
        `${offerItemIds.length} item${offerItemIds.length === 1 ? '' : 's'}`,
      ].filter(Boolean).join(' + ')
      await notify(listing.sellerId, {
        type: 'listing_offer',
        title: `${user.username} offered ${offerBits}`,
        body: `For "${item?.name || 'your item'}". Take it and hand it over, or haggle in the chat.`,
        link: `/catalog/${listing.itemId}`,
        data: { listingId, offerId: offer.id },
      })
      return NextResponse.json({ ok: true, message: `Offer sent — ${offerBits}. The seller decides.` })
    }

    // ---------------- seller accepts an offer: Tix for UGC ----------------
    if (action === 'accept_offer') {
      const offerId = String(body.offerId || '')
      const result = await db.$transaction(async (tx) => {
        const offer = await tx.ugcOffer.findUnique({
          where: { id: offerId },
          include: { listing: { include: { item: { select: { id: true, name: true } } } } },
        })
        if (!offer) throw new MarketError('NO_OFFER', 'Offer not found.')
        if (offer.listing.sellerId !== user.id) throw new MarketError('FORBIDDEN', 'Only the seller can answer offers.')
        if (offer.status !== 'pending') throw new MarketError('NOT_PENDING', 'This offer was already answered.')
        if (offer.listing.status !== 'active') throw new MarketError('NOT_ACTIVE', 'This listing is no longer active.')
        const owned = await tx.inventoryEntry.findUnique({
          where: { userId_itemId: { userId: user.id, itemId: offer.listing.itemId } },
          select: { id: true },
        })
        if (!owned) throw new MarketError('NOT_OWNED', 'You no longer own this copy.')

        // the buyer's UGC on the table — verified fresh, moved with everything else
        const offerItemIds = parseIdArray(offer.offerItemIdsJson)
        await assertOwnsAll(tx, offer.buyerId, offerItemIds)

        await moveTix(tx, offer.buyerId, user.id, offer.amount, `Offer accepted on "${offer.listing.item.name}"`)
        if (offer.robux > 0) await moveRobux(tx, offer.buyerId, user.id, offer.robux, `Offer accepted on "${offer.listing.item.name}"`)
        await transferItem(tx, offer.listing.itemId, user.id, offer.buyerId)
        // offered UGC crosses to the seller — the listed item already moved,
        // so a seller-side copy clash can only come from the offered items
        for (const itId of offerItemIds) await transferItem(tx, itId, offer.buyerId, user.id)
        await tx.ugcListing.update({
          where: { id: offer.listingId },
          data: { status: 'sold', buyerId: offer.buyerId, soldPrice: offer.amount, soldAt: new Date() },
        })
        await tx.ugcOffer.update({ where: { id: offerId }, data: { status: 'accepted', respondedAt: new Date() } })
        await tx.ugcOffer.updateMany({
          where: { listingId: offer.listingId, status: 'pending' },
          data: { status: 'declined', respondedAt: new Date() },
        })
        // only cash sales draw the price graph — a pure UGC-for-UGC swap
        // has no Tix price to plot (the ledger + notifications tell that story)
        if (offer.amount > 0) await pricePoint(tx, offer.listing.itemId, offer.amount, 'resale', offer.buyerId, user.id)
        return offer
      })
      await notify(result.buyerId, {
        type: 'offer_accepted',
        title: 'Offer accepted!',
        body: `"${result.listing.item.name}" is in your inventory — T$ ${result.amount.toLocaleString('en-US')}${result.robux > 0 ? ` + R$ ${result.robux.toLocaleString('en-US')}` : ''} was taken from your wallet${parseIdArray(result.offerItemIdsJson).length ? ' and the UGC you offered went to the seller' : ''}.`,
        link: `/catalog/${result.listing.itemId}`,
      })
      return NextResponse.json({ ok: true, message: `Sold for T$ ${result.amount.toLocaleString('en-US')}${result.robux > 0 ? ` + R$ ${result.robux.toLocaleString('en-US')}` : ''} — the money is in your wallet.` })
    }

    // ---------------- seller declines an offer ----------------
    if (action === 'decline_offer') {
      const offerId = String(body.offerId || '')
      const offer = await db.ugcOffer.findUnique({
        where: { id: offerId },
        include: { listing: { select: { sellerId: true, itemId: true, item: { select: { name: true } } } } },
      })
      if (!offer) return NextResponse.json({ error: 'Offer not found.' }, { status: 404 })
      if (offer.listing.sellerId !== user.id) return NextResponse.json({ error: 'Only the seller can answer offers.' }, { status: 403 })
      if (offer.status !== 'pending') return NextResponse.json({ error: 'This offer was already answered.' }, { status: 400 })
      await db.ugcOffer.update({ where: { id: offerId }, data: { status: 'declined', respondedAt: new Date() } })
      await notify(offer.buyerId, {
        type: 'offer_declined',
        title: 'Offer declined',
        body: `They kept "${offer.listing.item.name}" — try a message, a higher offer, or a trade.`,
        link: `/catalog/${offer.listing.itemId}`,
      })
      return NextResponse.json({ ok: true, message: 'Offer declined.' })
    }

    return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
  } catch (e) {
    if (e instanceof MarketError) {
      const status = e.code === 'FORBIDDEN' ? 403 : 400
      return NextResponse.json({ error: e.message }, { status })
    }
    throw e
  }
}
