import { randomBytes } from 'crypto'
import { writeFile, mkdir, rm, readdir, stat } from 'fs/promises'
import { createReadStream, createWriteStream, existsSync, statSync, mkdirSync } from 'fs'
import { pipeline } from 'stream/promises'
import { Readable } from 'stream'
import { tmpdir } from 'os'
import path from 'path'
import { db } from '@/lib/db'

export const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(process.cwd(), 'upload', 'games')
export const TMP_UPLOAD_DIR = path.join(tmpdir(), 'retroblox-uploads')

// Ensure upload root dirs exist
try {
  mkdirSync(UPLOAD_DIR, { recursive: true })
} catch {}
try {
  mkdirSync(TMP_UPLOAD_DIR, { recursive: true })
} catch {}

/**
 * Save an uploaded file to DISK (fast local cache / large-file streaming)
 * AND into the DATABASE as a BLOB if small enough (source of truth for serving).
 *
 * Supports files up to 5 GB: for large files (>16MB), data is streamed
 * directly to disk and the database row stores { path, size, data: null }.
 */
export async function saveUpload(file: File, userId?: string) {
  const id = randomBytes(12).toString('hex')
  const safeName = file.name.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'game.bin'
  const diskName = `${id}_${safeName}`

  let diskPath = path.join(UPLOAD_DIR, diskName)
  const isLarge = file.size > 16 * 1024 * 1024

  for (const dir of [UPLOAD_DIR, TMP_UPLOAD_DIR]) {
    try {
      await mkdir(dir, { recursive: true })
      diskPath = path.join(dir, diskName)
      if (isLarge) {
        // Stream directly to disk to prevent RAM exhaustion on 100MB-5GB files
        const webStream = file.stream()
        const nodeStream = Readable.fromWeb(webStream as any)
        await pipeline(nodeStream, createWriteStream(diskPath))
      } else {
        const buf = Buffer.from(await file.arrayBuffer())
        await writeFile(diskPath, buf)
      }
      break
    } catch {
      continue
    }
  }

  let finalSize = file.size
  try {
    if (existsSync(diskPath)) {
      finalSize = statSync(diskPath).size
    }
  } catch {}

  // For small files, also keep the Buffer in SQLite for host portability
  let dbBuf: Buffer | null = null
  if (!isLarge) {
    try {
      dbBuf = Buffer.from(await file.arrayBuffer())
    } catch {}
  }

  return db.uploadedFile.create({
    data: {
      id,
      filename: file.name,
      path: diskPath,
      mimeType: file.type || 'application/octet-stream',
      size: finalSize,
      data: dbBuf,
    },
  })
}

/* ------------------------------------------------------------------
   CHUNKED UPLOADS — Supports UGC models and games up to 5 GB.
   Chunks are streamed directly to disk in temporary upload folders,
   then concatenated with 0 RAM spikes when completed.
------------------------------------------------------------------ */

export const CHUNK_PREFIX = 'chunk:'

/** Save a raw chunk to disk in a dedicated upload temp folder */
export async function saveDiskChunk(
  uploadId: string,
  idx: number,
  chunkBuf: Buffer,
  name: string = 'game.bin',
  mime: string = 'application/octet-stream'
): Promise<number> {
  const uploadDir = path.join(TMP_UPLOAD_DIR, uploadId)
  await mkdir(uploadDir, { recursive: true })

  const chunkPath = path.join(uploadDir, `${String(idx).padStart(6, '0')}.chunk`)
  await writeFile(chunkPath, chunkBuf)

  // Write a small meta file so we remember the original name and mime
  const metaPath = path.join(uploadDir, 'meta.json')
  await writeFile(metaPath, JSON.stringify({ name, mime }), 'utf8').catch(() => {})

  return chunkBuf.length
}

/**
 * Assemble disk-based chunks into a single file in UPLOAD_DIR and create
 * an UploadedFile database row with data: null and the final size (up to 5 GB).
 */
export async function finalizeDiskChunkUpload(
  uploadId: string,
  customName?: string,
  customMime?: string
): Promise<{ id: string; filename: string; path: string; size: number } | null> {
  const uploadDir = path.join(TMP_UPLOAD_DIR, uploadId)
  if (!existsSync(uploadDir)) return null

  let filename = customName || 'game.bin'
  let mimeType = customMime || 'application/octet-stream'

  const metaPath = path.join(uploadDir, 'meta.json')
  if (existsSync(metaPath)) {
    try {
      const meta = JSON.parse(await import('fs/promises').then((m) => m.readFile(metaPath, 'utf8')))
      if (!customName && meta.name) filename = meta.name
      if (!customMime && meta.mime) mimeType = meta.mime
    } catch {}
  }

  const entries = await readdir(uploadDir)
  const chunkFiles = entries
    .filter((f) => f.endsWith('.chunk'))
    .sort()

  if (chunkFiles.length === 0) return null

  // Verify indices are contiguous
  for (let i = 0; i < chunkFiles.length; i++) {
    const chunkNum = parseInt(chunkFiles[i].replace('.chunk', ''), 10)
    if (chunkNum !== i) {
      console.error(`Chunk missing at index ${i} for upload ${uploadId}`)
      return null
    }
  }

  const id = uploadId.slice(0, 24)
  const safeName = filename.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'game.bin'
  const diskName = `${id}_${safeName}`
  const finalDiskPath = path.join(UPLOAD_DIR, diskName)

  await mkdir(UPLOAD_DIR, { recursive: true })

  const outStream = createWriteStream(finalDiskPath)
  for (const chunkFile of chunkFiles) {
    const chunkPath = path.join(uploadDir, chunkFile)
    const inStream = createReadStream(chunkPath)
    await pipeline(inStream, outStream, { end: false })
  }
  outStream.end()
  await new Promise((resolve) => outStream.on('finish', resolve))

  const finalStats = statSync(finalDiskPath)

  // Clean up temp directory
  rm(uploadDir, { recursive: true, force: true }).catch(() => {})

  const row = await db.uploadedFile.create({
    data: {
      id,
      filename,
      path: finalDiskPath,
      mimeType,
      size: finalStats.size,
      data: null,
    },
  })

  return {
    id: row.id,
    filename: row.filename,
    path: row.path,
    size: row.size,
  }
}

/** rename a chunk set to its kept form; returns the chunk count (0 = no set). */
export async function keepChunks(uploadId: string): Promise<number> {
  const prefix = CHUNK_PREFIX + uploadId + ':'
  const chunks = await db.uploadedFile.findMany({
    where: { path: { startsWith: prefix } },
    orderBy: { path: 'asc' },
    select: { id: true, path: true },
  })
  if (chunks.length === 0) return 0
  for (let i = 0; i < chunks.length; i++) {
    const idx = chunks[i].path.slice(prefix.length)
    if (Number(idx) !== i) return 0
    await db.uploadedFile.update({
      where: { id: chunks[i].id },
      data: { path: `keep:${uploadId}:${idx}` },
    })
  }
  return chunks.length
}

/** hygiene — remove chunk rows from failed/abandoned publishes (older than a day) */
export async function purgeStaleChunks(): Promise<void> {
  try {
    await db.uploadedFile.deleteMany({
      where: {
        path: { startsWith: CHUNK_PREFIX },
        createdAt: { lt: new Date(Date.now() - 24 * 60 * 60 * 1000) },
      },
    })
  } catch {}
}

/** assemble small UGC model chunks into ONE UploadedFile row (and delete the chunks) */
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

/** resolve a form file field: direct File or uploadId */
export async function resolveUpload(field: FormDataEntryValue | null, idField: FormDataEntryValue | null): Promise<File | null> {
  if (field instanceof File && field.size > 0) return field
  const uploadId = typeof idField === 'string' ? idField.trim() : ''
  if (!uploadId || !/^[a-zA-Z0-9]{8,64}$/.test(uploadId)) return null
  const row = await assembleUpload(uploadId)
  if (!row || row.data.length === 0) return null
  return new File([row.data as unknown as BlobPart], row.filename, { type: row.mimeType })
}

/**
 * Universal Game File Resolver: handles direct Files (up to 5GB) or chunked uploadIds.
 * Returns the saved UploadedFile record.
 */
export async function resolveGameUpload(
  field: FormDataEntryValue | null,
  idField: FormDataEntryValue | null,
  fileNameField?: FormDataEntryValue | null,
  userId?: string
): Promise<{ id: string; filename: string; size: number } | null> {
  const uploadId = typeof idField === 'string' ? idField.trim() : ''
  const customName = typeof fileNameField === 'string' ? fileNameField.trim() : ''

  if (uploadId && /^[a-zA-Z0-9]{8,64}$/.test(uploadId)) {
    // 1. Rename chunk: -> keep: in database (universal across Vercel, Turso cloud DB, and local)
    const keptCount = await keepChunks(uploadId)
    if (keptCount > 0) {
      finalizeDiskChunkUpload(uploadId, customName).catch(() => {})
      const chunkRow = await db.uploadedFile.findFirst({
        where: { path: { startsWith: `keep:${uploadId}:` } },
        select: { filename: true, mimeType: true },
      })
      const totalAgg = await db.uploadedFile.aggregate({
        where: { path: { startsWith: `keep:${uploadId}:` } },
        _sum: { size: true },
      })
      const totalSize = totalAgg._sum.size || 0
      const resolvedName = customName || chunkRow?.filename || 'game.exe'

      await db.uploadedFile.upsert({
        where: { id: uploadId },
        create: {
          id: uploadId,
          filename: resolvedName,
          path: path.join(UPLOAD_DIR, `${uploadId}_${resolvedName}`),
          mimeType: chunkRow?.mimeType || 'application/octet-stream',
          size: totalSize,
          data: null,
        },
        update: {
          filename: resolvedName,
          size: totalSize,
        },
      }).catch(() => {})

      return { id: uploadId, filename: resolvedName, size: totalSize }
    }

    // 2. Check if finalized on disk
    const diskResult = await finalizeDiskChunkUpload(uploadId, customName)
    if (diskResult) return diskResult

    // 3. Check if already exists in uploadedFile table
    const existing = await db.uploadedFile.findUnique({ where: { id: uploadId } })
    if (existing) {
      return { id: existing.id, filename: existing.filename, size: existing.size }
    }

    // 4. Fallback to DB-backed chunks
    const assembled = await assembleUpload(uploadId)
    if (assembled) {
      const saved = await db.uploadedFile.create({
        data: {
          id: uploadId,
          filename: customName || assembled.filename,
          path: path.join(UPLOAD_DIR, `${uploadId}_${customName || assembled.filename}`),
          mimeType: assembled.mimeType,
          size: assembled.data.length,
          data: assembled.data.length < 16 * 1024 * 1024 ? assembled.data : null,
        },
      })
      return { id: saved.id, filename: saved.filename, size: saved.size }
    }
  }

  if (field instanceof File && field.size > 0) {
    const saved = await saveUpload(field, userId)
    return { id: saved.id, filename: saved.filename, size: saved.size }
  }

  return null
}
