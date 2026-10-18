import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// GET /api/auth/check-username?u=SomeName
// Live availability check so people see "that username is taken" while
// typing instead of only after submitting the whole form.
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const username = (searchParams.get('u') || '').trim()

  // spaces are legal — "John Doe" is a perfectly good blockhead name
  if (!/^[A-Za-z0-9_ ]{3,20}$/.test(username)) {
    return NextResponse.json({
      available: false,
      reason: !username
        ? 'empty'
        : 'Usernames are 3-20 characters: letters, numbers, spaces, underscore.',
    })
  }

  const [exact, lower] = await Promise.all([
    db.user.findUnique({ where: { username }, select: { id: true } }),
    db.user.findUnique({ where: { usernameLower: username.toLowerCase() }, select: { id: true } }),
  ])

  if (exact || lower) {
    return NextResponse.json({ available: false, reason: 'That username is already taken.' })
  }

  return NextResponse.json({ available: true, reason: '' })
}
