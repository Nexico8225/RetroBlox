import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { notify } from '@/lib/market'

/**
 * GET  /api/market/[id] — one listing: item, seller, offers and the haggle chat.
 *      The seller sees every offer; everyone logged-in can read and post in the chat.
 * POST /api/market/[id] — { text } post a haggle message ("lower the price and it's a deal")
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const viewer = await getUserFromReq(req)

  const listing = await db.ugcListing.findUnique({
    where: { id },
    include: {
      item: { select: { id: true, assetId: true, name: true, type: true, imageFileId: true, isLimited: true, price: true, stock: true } },
      seller: { select: { id: true, username: true, avatarUrl: true } },
      buyer: { select: { id: true, username: true, avatarUrl: true } },
    },
  })
  if (!listing) return NextResponse.json({ error: 'Listing not found' }, { status: 404 })

  const isSeller = viewer?.id === listing.sellerId
  const offers = await db.ugcOffer.findMany({
    where: { listingId: id, ...(isSeller ? {} : viewer ? { OR: [{ status: 'pending' }, { buyerId: viewer.id }] } : { status: 'pending' }) },
    orderBy: { createdAt: 'desc' },
    take: 30,
    include: { buyer: { select: { id: true, username: true, avatarUrl: true } } },
  })
  const messages = await db.ugcListingMessage.findMany({
    where: { listingId: id },
    orderBy: { createdAt: 'asc' },
    take: 100,
    include: { sender: { select: { id: true, username: true, avatarUrl: true } } },
  })

  return NextResponse.json({
    listing: {
      id: listing.id,
      price: listing.price,
      status: listing.status,
      soldPrice: listing.soldPrice,
      soldAt: listing.soldAt,
      createdAt: listing.createdAt,
      item: listing.item,
      seller: listing.seller,
      buyer: listing.buyer,
    },
    isSeller,
    myPendingOffer: viewer ? (offers.find((o) => o.buyerId === viewer.id && o.status === 'pending') ?? null) : null,
    offers: isSeller ? offers : [],
    messages,
  })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const text = String(body.text || '').trim().slice(0, 300)
  if (!text) return NextResponse.json({ error: 'Type a message first.' }, { status: 400 })

  const listing = await db.ugcListing.findUnique({ where: { id }, select: { id: true, sellerId: true, status: true, itemId: true } })
  if (!listing) return NextResponse.json({ error: 'Listing not found' }, { status: 404 })

  await db.ugcListingMessage.create({ data: { listingId: id, senderId: user.id, text } })

  if (listing.status === 'active') {
    if (user.id === listing.sellerId) {
      // the seller spoke — ping everyone with skin in the game (pending offerers)
      const offerers = await db.ugcOffer.findMany({
        where: { listingId: id, status: 'pending' },
        select: { buyerId: true },
        distinct: ['buyerId'],
      })
      for (const o of offerers.slice(0, 10)) {
        await notify(o.buyerId, {
          type: 'listing_offer',
          title: `${user.username} replied on a listing`,
          body: text.slice(0, 140),
          link: `/catalog/${listing.itemId}`,
        })
      }
    } else {
      await notify(listing.sellerId, {
        type: 'listing_offer',
        title: `${user.username} is haggling with you`,
        body: text.slice(0, 140),
        link: `/catalog/${listing.itemId}`,
      })
    }
  }

  return NextResponse.json({ ok: true })
}
