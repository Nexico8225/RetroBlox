import { NextRequest, NextResponse } from 'next/server'
import { createReadStream, existsSync, statSync } from 'fs'
import { Readable } from 'stream'
import path from 'path'
import { db } from '@/lib/db'

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
    return NextResponse.json({ error: 'File not found' }, { status: 404 })
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
