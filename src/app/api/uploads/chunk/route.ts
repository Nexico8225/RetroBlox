import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { purgeStaleChunks } from '@/lib/uploads'

export const runtime = 'nodejs'

/** POST /api/uploads/chunk — one slice of a big upload (models up to 24MB).
 *
 *  Why: Vercel serverless functions reject request bodies over 4.5MB, so a
 *  GLB with embedded textures (easily 5-20MB) could never reach the catalog
 *  POST — the creator just saw "Something went wrong". The publish form now
 *  sends files over 3MB here as ~2.5MB base64 chunks; the catalog POST then
 *  assembles them with resolveUpload()/assembleUpload().
 *
 *  Zero new schema: each chunk is an ordinary UploadedFile row whose `path`
 *  is `chunk:<uploadId>:<zero-padded idx>` (lexicographic order == numeric
 *  order, verified again at assembly). Stale chunks are purged after a day. */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = (await req.json().catch(() => null)) as
    | { uploadId?: string; idx?: number; name?: string; mime?: string; b64?: string }
    | null

  const uploadId = typeof body?.uploadId === 'string' ? body.uploadId.trim() : ''
  const idx = Number(body?.idx)
  const name =
    typeof body?.name === 'string' && body.name.trim() !== ''
      ? body.name.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80)
      : 'model.bin'
  const mime =
    typeof body?.mime === 'string' && /^[\w.+-]{1,100}\/[\w.+-]{1,100}$/.test(body.mime)
      ? body.mime
      : 'application/octet-stream'

  if (!/^[a-zA-Z0-9]{8,64}$/.test(uploadId)) {
    return NextResponse.json({ error: 'Bad upload id.' }, { status: 400 })
  }
  if (!Number.isInteger(idx) || idx < 0 || idx > 99) {
    return NextResponse.json({ error: 'Bad chunk index.' }, { status: 400 })
  }
  if (typeof body?.b64 !== 'string' || body.b64.length === 0) {
    return NextResponse.json({ error: 'Missing chunk data.' }, { status: 400 })
  }
  // 5MB of base64 ~ 3.6MB binary — far above our 2.5MB chunks, way under the 4.5MB body cap
  if (body.b64.length > 5 * 1024 * 1024) {
    return NextResponse.json({ error: 'Chunk too large.' }, { status: 413 })
  }

  let buf: Buffer
  try {
    buf = Buffer.from(body.b64, 'base64')
  } catch {
    return NextResponse.json({ error: 'Chunk data is not valid base64.' }, { status: 400 })
  }
  if (buf.length === 0) {
    return NextResponse.json({ error: 'Chunk decoded to zero bytes.' }, { status: 400 })
  }

  const path = `chunk:${uploadId}:${String(idx).padStart(4, '0')}`
  await db.uploadedFile.deleteMany({ where: { path } }) // re-send of the same chunk = replace
  await db.uploadedFile.create({
    data: { filename: name, path, mimeType: mime, size: buf.length, data: new Uint8Array(buf) },
  })
  await purgeStaleChunks()

  return NextResponse.json({ ok: true, idx, size: buf.length })
}
