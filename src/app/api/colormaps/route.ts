import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload, resolveUpload } from '@/lib/uploads'

/**
 * COLORWORLD — community paint maps.
 *
 * GET  /api/colormaps            — the community map list (newest first)
 * POST /api/colormaps            — upload a map (login required)
 *      fields: name, map (File or mapId=chunked upload id), image (optional
 *      File or imageId) — the GLB that becomes a white + outline paint world
 *      and the custom placeholder image shown on the map card.
 *
 * A map is a plain GLB model. The game turns every part white (unshaded)
 * with a black outline and the player paints it with the brush, so ANY
 * static model works — buildings, characters, anything.
 */

const MAX_MAP_BYTES = 24 * 1024 * 1024
const MAX_IMAGE_BYTES = 3 * 1024 * 1024

export async function GET() {
  const maps = await db.colorMap.findMany({
    orderBy: { createdAt: 'desc' },
    take: 100,
    include: { uploader: { select: { id: true, username: true, avatarUrl: true } } },
  })
  return NextResponse.json({
    maps: maps.map((m) => ({
      id: m.id,
      name: m.name,
      uploader: m.uploader,
      plays: m.plays,
      createdAt: m.createdAt,
      mapUrl: `/api/files/${m.fileId}`,
      imageUrl: m.imageId ? `/api/files/${m.imageId}` : null,
    })),
  })
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  let form: FormData
  try {
    form = await req.formData()
  } catch {
    return NextResponse.json({ error: 'Bad form data.' }, { status: 400 })
  }

  const name = String(form.get('name') || '').trim()
  if (name.length < 2 || name.length > 40) {
    return NextResponse.json({ error: 'Map name must be 2-40 characters.' }, { status: 400 })
  }

  // the GLB — direct file or a chunked upload assembled by resolveUpload
  // (the site's attachUpload() helper appends "mapUploadId" for big files)
  const mapFile = await resolveUpload(form.get('map'), form.get('mapUploadId'))
  if (!mapFile) return NextResponse.json({ error: 'Attach a GLB map file.' }, { status: 400 })
  if (mapFile.size > MAX_MAP_BYTES) return NextResponse.json({ error: 'Map too large (max 24MB).' }, { status: 413 })
  const head = Buffer.from(await mapFile.slice(0, 4).arrayBuffer()).toString('latin1')
  if (head !== 'glTF') {
    return NextResponse.json({ error: 'That is not a GLB file — export your model as glTF Binary (.glb).' }, { status: 400 })
  }

  const imageFile = await resolveUpload(form.get('image'), form.get('imageUploadId'))
  if (imageFile) {
    if (imageFile.size > MAX_IMAGE_BYTES) return NextResponse.json({ error: 'Image too large (max 3MB).' }, { status: 413 })
    if (imageFile.type && !imageFile.type.startsWith('image/')) {
      return NextResponse.json({ error: 'The placeholder must be an image.' }, { status: 400 })
    }
  }

  const mapRow = await saveUpload(mapFile, user.id)
  const imageRow = imageFile ? await saveUpload(imageFile, user.id) : null

  const created = await db.colorMap.create({
    data: {
      name,
      fileId: mapRow.id,
      imageId: imageRow?.id ?? null,
      uploaderId: user.id,
    },
  })

  return NextResponse.json({ id: created.id, name: created.name })
}
