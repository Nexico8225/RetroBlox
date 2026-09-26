import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

// Update my profile: avatar image upload or bio edit
export async function PATCH(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const contentType = req.headers.get('content-type') || ''
  const data: Record<string, unknown> = {}

  if (contentType.includes('multipart/form-data')) {
    const form = await req.formData()
    const avatar = form.get('avatar')
    if (avatar instanceof File && avatar.size > 0) {
      if (avatar.size > 2 * 1024 * 1024) {
        return NextResponse.json({ error: 'Avatar image too large (max 2MB).' }, { status: 400 })
      }
      const buf = Buffer.from(await avatar.arrayBuffer())
      data.avatarUrl = `data:${avatar.type || 'image/png'};base64,${buf.toString('base64')}`
    }
    const bio = form.get('bio')
    if (typeof bio === 'string') data.bio = bio.slice(0, 300)
  } else {
    const body = await req.json()
    if (typeof body.bio === 'string') data.bio = body.bio.slice(0, 300)
    if (body.avatarRemove === true) data.avatarUrl = null
  }

  const updated = await db.user.update({ where: { id: user.id }, data: data as never })
  return NextResponse.json({ user: publicUser(updated) })
}
