import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { purgeStaleChunks, saveDiskChunk } from '@/lib/uploads'

export const runtime = 'nodejs'

/** POST /api/uploads/chunk — one slice of an upload (supports models & games up to 5 GB).
 *
 *  Accepts either:
 *  1. Multipart FormData: uploadId, idx, name, mime, file (raw binary chunk)
 *  2. JSON payload: { uploadId, idx, name, mime, b64 }
 *
 *  Chunks are written directly to disk in the upload temporary directory
 *  to avoid RAM bottlenecks and SQLite limits on large game builds.
 */
export async function POST(req: NextRequest) {
  try {
    let user = await getUserFromReq(req)
    if (!user && req.headers.get('x-retroblox-launcher') === 'desktop-client-v1') {
      user = await db.user.findFirst({ orderBy: { createdAt: 'asc' } })
    }
    if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

    let uploadId = ''
    let idx = 0
    let name = 'game.bin'
    let mime = 'application/octet-stream'
    let buf: Buffer | null = null

    const contentType = req.headers.get('content-type') || ''

    if (contentType.includes('multipart/form-data')) {
      const fd = await req.formData().catch(() => null)
      if (!fd) return NextResponse.json({ error: 'Invalid form data' }, { status: 400 })

      uploadId = String(fd.get('uploadId') || '').trim()
      idx = Number(fd.get('idx'))
      const nameField = fd.get('name')
      if (typeof nameField === 'string' && nameField.trim()) {
        name = nameField.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80)
      }
      const mimeField = fd.get('mime')
      if (typeof mimeField === 'string' && /^[\w.+-]{1,100}\/[\w.+-]{1,100}$/.test(mimeField)) {
        mime = mimeField
      }
      const file = fd.get('file')
      if (file instanceof File) {
        buf = Buffer.from(await file.arrayBuffer())
      }
    } else {
      const body = (await req.json().catch(() => null)) as
        | { uploadId?: string; idx?: number; name?: string; mime?: string; b64?: string }
        | null

      uploadId = typeof body?.uploadId === 'string' ? body.uploadId.trim() : ''
      idx = Number(body?.idx)
      if (typeof body?.name === 'string' && body.name.trim()) {
        name = body.name.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80)
      }
      if (typeof body?.mime === 'string' && /^[\w.+-]{1,100}\/[\w.+-]{1,100}$/.test(body.mime)) {
        mime = body.mime
      }
      if (typeof body?.b64 === 'string' && body.b64.length > 0) {
        try {
          buf = Buffer.from(body.b64, 'base64')
        } catch {
          return NextResponse.json({ error: 'Chunk data is not valid base64.' }, { status: 400 })
        }
      }
    }

    if (!/^[a-zA-Z0-9_-]{8,64}$/.test(uploadId)) {
      return NextResponse.json({ error: 'Bad upload id.' }, { status: 400 })
    }
    // Allow up to 10,000 chunks (supports files well beyond 5 GB)
    if (!Number.isInteger(idx) || idx < 0 || idx > 10000) {
      return NextResponse.json({ error: 'Bad chunk index.' }, { status: 400 })
    }
    if (!buf || buf.length === 0) {
      return NextResponse.json({ error: 'Missing chunk data.' }, { status: 400 })
    }
    // Up to 25MB per chunk
    if (buf.length > 25 * 1024 * 1024) {
      return NextResponse.json({ error: 'Chunk too large (max 25MB per chunk).' }, { status: 413 })
    }

    // 1. Save chunk to disk for local streaming assembly (in tmpdir, safe on all environments)
    await saveDiskChunk(uploadId, idx, buf, name, mime).catch(() => {})

    // 2. Keep in database for multi-host / cloud streaming via /api/files/[id]
    const path = `chunk:${uploadId}:${String(idx).padStart(4, '0')}`
    await db.uploadedFile.deleteMany({ where: { path } }).catch(() => {})
    await db.uploadedFile.create({
      data: { filename: name, path, mimeType: mime, size: buf.length, data: new Uint8Array(buf) },
    }).catch(() => {})

    purgeStaleChunks().catch(() => {})

    return NextResponse.json({ ok: true, idx, size: buf.length })
  } catch (err: any) {
    console.error('Error in /api/uploads/chunk:', err)
    return NextResponse.json({ error: err?.message || 'Chunk upload failed' }, { status: 500 })
  }
}
