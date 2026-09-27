import { randomBytes } from 'crypto'
import { writeFile, mkdir } from 'fs/promises'
import { tmpdir } from 'os'
import path from 'path'
import { db } from '@/lib/db'

const UPLOAD_DIR = '/home/z/my-project/uploads/games'
const TMP_UPLOAD_DIR = 'retroblox-uploads'

/**
 * Save an uploaded file to DISK (fast local cache / large-file streaming)
 * AND into the DATABASE as a BLOB (source of truth for serving).
 *
 * Why both? The live domain (retroblox.space-z.ai) runs the app with the
 * database but WITHOUT this server's disk — disk-only files 404 there.
 * Bytes in the DB travel wherever the DB goes, so images/models/audio
 * always resolve on every host.
 */
export async function saveUpload(file: File, userId: string) {
  const id = randomBytes(12).toString('hex')
  const safeName = file.name.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'game.bin'
  const diskName = `${id}_${safeName}`
  const buf = Buffer.from(await file.arrayBuffer())

  // Best-effort disk copy (streaming fallback + easy debugging) — the DB row
  // below is the source of truth. Serverless hosts (Vercel) have a READ-ONLY
  // filesystem outside /tmp: the unguarded `mkdir(UPLOAD_DIR)` used to THROW
  // there and kill every publish with a bare "Something went wrong". Now we
  // try the project dir first (self-hosted), then /tmp (serverless), and give
  // up silently if even that fails — publishing still works from the DB blob.
  let diskPath = path.join(UPLOAD_DIR, diskName)
  for (const dir of [UPLOAD_DIR, path.join(tmpdir(), TMP_UPLOAD_DIR)]) {
    try {
      await mkdir(dir, { recursive: true })
      diskPath = path.join(dir, diskName)
      await writeFile(diskPath, buf)
      break
    } catch {
      continue // read-only host — DB blob is what the file API serves
    }
  }

  return db.uploadedFile.create({
    data: {
      id,
      filename: file.name,
      path: diskPath,
      mimeType: file.type || 'application/octet-stream',
      size: buf.length,
      data: buf,
    },
  })
}

/* ------------------------------------------------------------------
   CHUNKED UPLOADS — Vercel serverless functions reject request
   bodies over 4.5MB, but creators can publish models up to 24MB
   (a GLB with embedded textures crosses that line easily). Big
   files go up first as ~2.5MB chunks via /api/uploads/chunk, then
   the API route assembles them. Zero new schema: chunks are
   ordinary UploadedFile rows tagged with a `chunk:<id>:<idx>` path.
------------------------------------------------------------------ */

const CHUNK_PREFIX = 'chunk:'

/** hygiene — remove chunk rows from failed/abandoned publishes (older than a day) */
export async function purgeStaleChunks(): Promise<void> {
  try {
    await db.uploadedFile.deleteMany({
      where: {
        path: { startsWith: CHUNK_PREFIX },
        createdAt: { lt: new Date(Date.now() - 24 * 60 * 60 * 1000) },
      },
    })
  } catch {
    // hygiene only — never block an upload
  }
}

/** assemble the chunks of one upload into ONE UploadedFile row (and delete
 *  the chunks). Returns null when nothing was uploaded under that id.
 *  The zero-padded idx inside the path makes lexicographic order numeric;
 *  contiguity is verified so a dropped chunk can never publish a broken
 *  file — it fails loudly instead. */
export async function assembleUpload(uploadId: string): Promise<{ filename: string; mimeType: string; data: Buffer } | null> {
  const prefix = CHUNK_PREFIX + uploadId + ':'
  const chunks = await db.uploadedFile.findMany({
    where: { path: { startsWith: prefix } },
    orderBy: { path: 'asc' },
  })
  if (chunks.length === 0) return null
  for (let i = 0; i < chunks.length; i++) {
    const idx = Number(chunks[i].path.slice(prefix.length))
    if (!Number.isInteger(idx) || idx !== i) return null
  }
  const parts: Buffer[] = []
  let total = 0
  for (const c of chunks) {
    const buf = Buffer.from(c.data ?? new Uint8Array())
    parts.push(buf)
    total += buf.length
  }
  await db.uploadedFile.deleteMany({ where: { path: { startsWith: prefix } } })
  return {
    filename: chunks[0].filename || 'model.bin',
    mimeType: chunks[0].mimeType || 'application/octet-stream',
    data: Buffer.concat(parts, total),
  }
}

/** resolve a form file field: either the direct File, or an uploadId that
 *  references chunks uploaded via /api/uploads/chunk. Returns null when
 *  neither is present (the caller's existing "field is required" errors
 *  keep working unchanged). */
export async function resolveUpload(field: FormDataEntryValue | null, idField: FormDataEntryValue | null): Promise<File | null> {
  if (field instanceof File && field.size > 0) return field
  const uploadId = typeof idField === 'string' ? idField.trim() : ''
  if (!uploadId || !/^[a-zA-Z0-9]{8,64}$/.test(uploadId)) return null
  const row = await assembleUpload(uploadId)
  if (!row || row.data.length === 0) return null
  return new File([row.data as unknown as BlobPart], row.filename, { type: row.mimeType })
}
