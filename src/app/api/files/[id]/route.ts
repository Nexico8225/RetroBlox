import { NextRequest, NextResponse } from 'next/server'
import { createReadStream, existsSync, statSync } from 'fs'
import { Readable } from 'stream'
import path from 'path'
import { db } from '@/lib/db'

/** big game builds live as KEPT CHUNK rows — stream them row by row */
export const maxDuration = 60

/**
 * FILE SERVICE — GET /api/files/{id}  (images, GLB models, audio, video, zips)
 *
 * Serves the bytes stored IN the database (UploadedFile.data BLOB) so files
 * resolve on every host the app runs on — including the deployed domain,
 * which has the DB but not this server's disk. If a row has no BLOB
 * (legacy rows before the backfill), fall back to the disk path.
 *
 * Range support so <video> can stream + seek (YouTube-style playback).
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const file = await db.uploadedFile.findUnique({ where: { id } })
  if (!file) {
    // big game builds live as KEPT CHUNK ROWS (never one giant blob) —
    // stream the chunks one row at a time so the function never holds the
    // whole file in memory and the browser sees a real Content-Length
    const prefix = `keep:${id}:`
    const rows = await db.uploadedFile.findMany({
      where: { path: { startsWith: prefix } },
      orderBy: { path: 'asc' },
      select: { id: true, path: true, size: true, filename: true, mimeType: true },
    })
    if (rows.length === 0) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 })
    }
    for (let i = 0; i < rows.length; i++) {
      if (Number(rows[i].path.slice(prefix.length)) !== i) {
        return NextResponse.json({ error: 'File chunks broken' }, { status: 500 })
      }
    }
    const total = rows.reduce((s, r) => s + (r.size || 0), 0)
    const download = new URL(req.url).searchParams.get('dl') === '1'
    const headers: Record<string, string> = {
      'Content-Type': rows[0].mimeType || 'application/zip',
      'Content-Length': String(total),
      'Accept-Ranges': 'none',
    }
    if (download) {
      headers['Content-Disposition'] = `attachment; filename="${path.basename(rows[0].filename || 'game.zip')}"`
    }
    const ids = rows.map((r) => r.id)
    const stream = new ReadableStream({
      async start(controller) {
        try {
          for (const cid of ids) {
            const row = await db.uploadedFile.findUnique({ where: { id: cid }, select: { data: true } })
            if (!row?.data) break
            controller.enqueue(new Uint8Array(row.data))
          }
          controller.close()
        } catch (e) {
          controller.error(e)
        }
      },
    })
    return new NextResponse(stream, { headers })
  }

  const download = new URL(req.url).searchParams.get('dl') === '1'

  const baseHeaders: Record<string, string> = {
    'Content-Type': file.mimeType || 'application/octet-stream',
    'Accept-Ranges': 'bytes',
  }
  if (download) {
    baseHeaders['Content-Disposition'] = `attachment; filename="${path.basename(file.filename)}"`
  }

  // ---- BLOB path: bytes live in the DB (host-independent) ----
  if (file.data) {
    const buf = Buffer.from(file.data)
    const size = buf.length

    // v6: game-file downloads carry their game's identity — when the game
    // page downloads a .retroplace with ?game=<id>, inject the id so the
    // desktop player can fetch the owner's PUBLISHED UI for everyone
    const gameId = new URL(req.url).searchParams.get('game')
    if (gameId && /\.(retroplace|json)$/i.test(file.filename || '') && buf.length < 2_000_000) {
      try {
        const parsed: unknown = JSON.parse(buf.toString('utf8'))
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
          const obj = parsed as Record<string, unknown>
          if (!obj.gameId) {
            obj.gameId = gameId
            const out = JSON.stringify(obj)
            return new NextResponse(out, {
              headers: {
                ...baseHeaders,
                'Content-Type': 'application/json',
                'Content-Length': String(Buffer.byteLength(out)),
                'Content-Disposition': `attachment; filename="${path.basename(file.filename)}"`,
              },
            })
          }
        }
      } catch { /* not JSON — serve raw bytes below */ }
    }

    const range = req.headers.get('range')
    if (range && !download) {
      const m = /bytes=(\d*)-(\d*)/.exec(range)
      if (m) {
        const start = m[1] ? parseInt(m[1], 10) : 0
        const end = m[2] ? Math.min(parseInt(m[2], 10), size - 1) : size - 1
        if (isNaN(start) || isNaN(end) || start > end || start >= size) {
          return new NextResponse(null, {
            status: 416,
            headers: { 'Content-Range': `bytes */${size}` },
          })
        }
        const slice = buf.subarray(start, end + 1)
        return new NextResponse(new Uint8Array(slice), {
          status: 206,
          headers: {
            ...baseHeaders,
            'Content-Range': `bytes ${start}-${end}/${size}`,
            'Content-Length': String(end - start + 1),
          },
        })
      }
    }

    return new NextResponse(new Uint8Array(buf), {
      headers: { ...baseHeaders, 'Content-Length': String(size) },
    })
  }

  // ---- disk fallback (legacy rows with no BLOB yet) ----
  if (!existsSync(file.path)) {
    return NextResponse.json({ error: 'File not found' }, { status: 404 })
  }
  const size = statSync(file.path).size

  const range = req.headers.get('range')
  if (range && !download) {
    const m = /bytes=(\d*)-(\d*)/.exec(range)
    if (m) {
      const start = m[1] ? parseInt(m[1], 10) : 0
      const end = m[2] ? Math.min(parseInt(m[2], 10), size - 1) : size - 1
      if (isNaN(start) || isNaN(end) || start > end || start >= size) {
        return new NextResponse(null, {
          status: 416,
          headers: { 'Content-Range': `bytes */${size}` },
        })
      }
      const stream = Readable.toWeb(createReadStream(file.path, { start, end })) as unknown as ReadableStream
      return new NextResponse(stream, {
        status: 206,
        headers: {
          ...baseHeaders,
          'Content-Range': `bytes ${start}-${end}/${size}`,
          'Content-Length': String(end - start + 1),
        },
      })
    }
  }

  const stream = Readable.toWeb(createReadStream(file.path)) as unknown as ReadableStream
  return new NextResponse(stream, { headers: { ...baseHeaders, 'Content-Length': String(size) } })
}
