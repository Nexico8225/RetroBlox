import { randomBytes } from 'crypto'
import { writeFile, mkdir } from 'fs/promises'
import path from 'path'
import { db } from '@/lib/db'

const UPLOAD_DIR = '/home/z/my-project/uploads/games'

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
  await mkdir(UPLOAD_DIR, { recursive: true })
  const id = randomBytes(12).toString('hex')
  const safeName = file.name.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'game.bin'
  const diskName = `${id}_${safeName}`
  const diskPath = path.join(UPLOAD_DIR, diskName)
  const buf = Buffer.from(await file.arrayBuffer())

  // best-effort disk copy (streaming fallback + easy debugging); DB is the truth
  try {
    await writeFile(diskPath, buf)
  } catch {
    // disk write is optional now — DB blob is what the file API serves
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
