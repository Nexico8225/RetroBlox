import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

export const runtime = 'nodejs'

/**
 * GET /api/games/[id]/save
 * Pulls the user's latest Cloud Save for this game.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json({ error: 'Login required' }, { status: 401 })
  }

  const { id: gameId } = await params
  const save = await db.gameSave.findUnique({
    where: {
      gameId_userId: {
        gameId,
        userId: user.id,
      },
    },
    select: {
      data: true,
      size: true,
      updatedAt: true,
    },
  })

  if (!save || !save.data) {
    return NextResponse.json({ error: 'No cloud save found' }, { status: 404 })
  }

  return new NextResponse(save.data, {
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Length': String(save.size),
      'X-Saved-At': save.updatedAt.toISOString(),
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': '*',
    },
  })
}

/**
 * POST /api/games/[id]/save
 * Uploads an updated Cloud Save archive (typically 10KB - 5MB)
 * after a game session finishes in the launcher.
 */
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json({ error: 'Login required' }, { status: 401 })
  }

  const { id: gameId } = await params
  const contentType = req.headers.get('content-type') || ''
  let buf: Buffer | null = null

  if (contentType.includes('multipart/form-data')) {
    const fd = await req.formData().catch(() => null)
    const file = fd?.get('save') || fd?.get('file')
    if (file instanceof File) {
      buf = Buffer.from(await file.arrayBuffer())
    }
  } else {
    // Raw binary body
    const arrayBuf = await req.arrayBuffer().catch(() => null)
    if (arrayBuf && arrayBuf.byteLength > 0) {
      buf = Buffer.from(arrayBuf)
    }
  }

  if (!buf || buf.length === 0) {
    return NextResponse.json({ error: 'Missing save data' }, { status: 400 })
  }

  // Cap save file size to 15MB (save games are typically under 1MB)
  if (buf.length > 15 * 1024 * 1024) {
    return NextResponse.json({ error: 'Save file exceeds 15MB limit' }, { status: 413 })
  }

  const updated = await db.gameSave.upsert({
    where: {
      gameId_userId: {
        gameId,
        userId: user.id,
      },
    },
    create: {
      gameId,
      userId: user.id,
      data: new Uint8Array(buf),
      size: buf.length,
    },
    update: {
      data: new Uint8Array(buf),
      size: buf.length,
    },
  })

  return NextResponse.json({
    ok: true,
    size: updated.size,
    updatedAt: updated.updatedAt,
  })
}
