import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, isOnline } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'
import { parsePlacement } from '@/lib/avatarAssets'

const PERMS = ['post', 'moderate', 'roles', 'games', 'ugc', 'settings'] as const

function parsePerms(role: { permsJson: string } | null | undefined): string[] {
  try {
    const p = JSON.parse(role?.permsJson || '[]')
    return Array.isArray(p) ? p.filter((x) => typeof x === 'string') : []
  } catch {
    return []
  }
}

/* Effective permissions for a member in a group:
   - owner: everything
   - site admin: everything
   - member with a GroupRole: whatever that role's permsJson grants
   - plain member: can post on the wall only */
async function effectivePerms(groupId: string, userId: string | null, siteAdmin: boolean) {
  if (!userId) return { isMember: false, isOwner: false, perms: [] as string[], role: null }
  const membership = await db.groupMember.findUnique({
    where: { groupId_userId: { groupId, userId } },
  })
  if (!membership) return { isMember: false, isOwner: false, perms: [] as string[], role: null }
  const group = await db.group.findUnique({ where: { id: groupId } })
  const isOwner = group?.ownerId === userId
  if (isOwner || siteAdmin) {
    return { isMember: true, isOwner, perms: [...PERMS], role: isOwner ? 'owner' : membership.role }
  }
  if (membership.role === 'member' || membership.role === 'owner') {
    return { isMember: true, isOwner, perms: membership.role === 'owner' ? [...PERMS] : ['post'], role: membership.role }
  }
  const role = await db.groupRole.findUnique({
    where: { groupId_name: { groupId, name: membership.role } },
  })
  return { isMember: true, isOwner, perms: parsePerms(role), role: membership.role }
}

// GET /api/groups/[id] — group page data (wall, games, members, roles)
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const viewer = await getUserFromReq(req)

  const group = await db.group.findUnique({
    where: { id },
    include: {
      owner: { select: { id: true, username: true, avatarUrl: true, role: true } },
      members: {
        include: { user: { select: { id: true, username: true, avatarUrl: true, lastSeen: true, createdAt: true } } },
        orderBy: { joinedAt: 'asc' },
      },
      roles: { orderBy: { rank: 'asc' } },
      ugcItems: {
        include: {
          creator: { select: { id: true, username: true, avatarUrl: true } },
        },
        orderBy: { createdAt: 'desc' },
      },
      games: {
        include: {
          creator: { select: { id: true, username: true, avatarUrl: true } },
          likes: true,
          _count: { select: { comments: true, favorites: true } },
        },
        orderBy: { createdAt: 'desc' },
      },
      posts: {
        include: {
          author: { select: { id: true, username: true, avatarUrl: true, role: true } },
          replies: {
            include: { author: { select: { id: true, username: true, avatarUrl: true, role: true } } },
            orderBy: { createdAt: 'asc' },
          },
        },
        orderBy: { createdAt: 'desc' },
        take: 50,
      },
    },
  })
  if (!group) return NextResponse.json({ error: 'Group not found' }, { status: 404 })

  const games = group.games.map((g) => {
    const likes = g.likes.filter((l) => l.value === 1).length
    const dislikes = g.likes.filter((l) => l.value === -1).length
    return {
      id: g.id,
      name: g.name,
      genre: g.genre,
      subgenre: g.subgenre,
      engine: g.engine,
      maturity: g.maturity,
      iconUrl: g.iconUrl,
      thumbnailUrl: g.thumbnailUrl,
      downloads: g.downloads,
      createdAt: g.createdAt,
      updatedAt: g.updatedAt,
      creator: g.creator,
      likes,
      dislikes,
      rating: likes + dislikes > 0 ? Math.round((likes / (likes + dislikes)) * 100) : null,
      commentCount: g._count.comments,
      favoriteCount: g._count.favorites,
    }
  })

  const myMembership = viewer ? group.members.find((m) => m.userId === viewer.id) : null
  const eff = await effectivePerms(id, viewer?.id || null, viewer?.role === 'admin')

  return NextResponse.json({
    group: {
      id: group.id,
      name: group.name,
      description: group.description,
      iconUrl: group.iconUrl,
      owner: group.owner,
      createdAt: group.createdAt,
      members: group.members.map((m) => ({
        id: m.id,
        role: m.role,
        joinedAt: m.joinedAt,
        user: { ...m.user, online: isOnline(m.user.lastSeen) },
      })),
      roles: group.roles.map((r) => ({
        id: r.id,
        name: r.name,
        color: r.color,
        rank: r.rank,
        perms: parsePerms(r),
      })),
      posts: group.posts.map((p) => ({
        id: p.id,
        body: p.body,
        mediaFileId: p.mediaFileId,
        mediaType: p.mediaType,
        mediaName: p.mediaName,
        likeIds: JSON.parse(p.likeIds || '[]') as string[],
        author: p.author,
        createdAt: p.createdAt,
        replies: p.replies.map((r) => ({
          id: r.id,
          text: r.text,
          author: r.author,
          createdAt: r.createdAt,
        })),
      })),
      games,
    },
    ugcItems: group.ugcItems.map((i) => ({
      id: i.id,
      assetId: i.assetId,
      name: i.name,
      description: i.description,
      type: i.type,
      imageFileId: i.imageFileId,
      modelFileId: i.modelFileId,
      textureFileId: i.textureFileId,
      baseColor: i.baseColor,
      placement: parsePlacement(i.placementJson),
      creator: i.creator,
      createdAt: i.createdAt,
    })),
    myMembership: myMembership ? { role: myMembership.role } : null,
    myPerms: eff.perms,
    myRole: eff.role,
  })
}

// POST /api/groups/[id] — action dispatch:
//   join | leave | post | delete_post | like_post | reply | delete_reply
//   set_role | add_role | update_role | delete_role
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const group = await db.group.findUnique({ where: { id } })
  if (!group) return NextResponse.json({ error: 'Group not found' }, { status: 404 })

  const eff = await effectivePerms(id, user.id, user.role === 'admin')

  /* some actions work without JSON (multipart posts) */
  const contentType = req.headers.get('content-type') || ''

  /* ---- wall post (multipart: body + optional media) ---- */
  if (contentType.includes('multipart/form-data')) {
    const form = await req.formData()
    const body = String(form.get('body') || '').trim()
    if (!body || body.length > 2000) {
      return NextResponse.json({ error: 'Post must be 1-2000 characters.' }, { status: 400 })
    }
    if (!eff.isMember) return NextResponse.json({ error: 'Join the group to post on its wall!' }, { status: 403 })

    let mediaFileId: string | null = null
    let mediaType: string | null = null
    let mediaName: string | null = null
    const file = form.get('file')
    if (file instanceof File && file.size > 0) {
      const isVideo = file.type.startsWith('video/')
      const isImage = file.type.startsWith('image/')
      if (!isVideo && !isImage) {
        return NextResponse.json({ error: 'Wall posts can hold images or videos.' }, { status: 400 })
      }
      const maxMB = isVideo ? 100 : 8
      if (file.size > maxMB * 1024 * 1024) {
        return NextResponse.json({ error: `Attachment too large (max ${maxMB}MB).` }, { status: 400 })
      }
      const saved = await saveUpload(file, user.id)
      mediaFileId = saved.id
      mediaType = isVideo ? 'video' : 'image'
      mediaName = file.name
    }

    const post = await db.groupPost.create({
      data: { groupId: id, body, mediaFileId, mediaType, mediaName, authorId: user.id },
      include: {
        author: { select: { id: true, username: true, avatarUrl: true, role: true } },
        replies: { include: { author: { select: { id: true, username: true, avatarUrl: true, role: true } } }, orderBy: { createdAt: 'asc' } },
      },
    })
    return NextResponse.json({
      post: { ...post, likeIds: [], replies: post.replies.map((r) => ({ id: r.id, text: r.text, author: r.author, createdAt: r.createdAt })) },
    })
  }

  const body = await req.json().catch(() => ({}))
  const action = String(body.action || '')

  /* ---- join / leave ---- */
  if (action === 'join') {
    const existing = await db.groupMember.findUnique({
      where: { groupId_userId: { groupId: id, userId: user.id } },
    })
    if (!existing) {
      await db.groupMember.create({ data: { groupId: id, userId: user.id } })
      return NextResponse.json({ ok: true, member: true })
    }
    return NextResponse.json({ ok: true, member: true })
  }

  if (action === 'leave') {
    if (group.ownerId === user.id) {
      return NextResponse.json({ error: 'Owners cannot leave their own group. Delete it instead.' }, { status: 400 })
    }
    await db.groupMember.deleteMany({ where: { groupId: id, userId: user.id } })
    return NextResponse.json({ ok: true, member: false })
  }

  /* ---- wall: like / delete post / reply / delete reply ---- */
  if (action === 'like_post') {
    const post = await db.groupPost.findUnique({ where: { id: String(body.postId || '') } })
    if (!post || post.groupId !== id) return NextResponse.json({ error: 'Post not found' }, { status: 404 })
    let likeIds: string[] = []
    try { likeIds = JSON.parse(post.likeIds || '[]') } catch { /* keep [] */ }
    const has = likeIds.includes(user.id)
    const next = has ? likeIds.filter((u) => u !== user.id) : [...likeIds, user.id]
    await db.groupPost.update({ where: { id: post.id }, data: { likeIds: JSON.stringify(next) } })
    return NextResponse.json({ ok: true, likes: next.length, liked: !has })
  }

  if (action === 'reply') {
    const post = await db.groupPost.findUnique({ where: { id: String(body.postId || '') } })
    if (!post || post.groupId !== id) return NextResponse.json({ error: 'Post not found' }, { status: 404 })
    const text = String(body.text || '').trim()
    if (!text || text.length > 500) return NextResponse.json({ error: 'Reply must be 1-500 characters.' }, { status: 400 })
    if (!eff.isMember) return NextResponse.json({ error: 'Join the group to reply!' }, { status: 403 })
    const reply = await db.groupPostReply.create({
      data: { postId: post.id, text, authorId: user.id },
      include: { author: { select: { id: true, username: true, avatarUrl: true, role: true } } },
    })
    return NextResponse.json({ reply: { id: reply.id, text: reply.text, author: reply.author, createdAt: reply.createdAt } })
  }

  if (action === 'delete_post') {
    const post = await db.groupPost.findUnique({ where: { id: String(body.postId || '') } })
    if (!post || post.groupId !== id) return NextResponse.json({ error: 'Post not found' }, { status: 404 })
    const canModerate = eff.perms.includes('moderate')
    if (post.authorId !== user.id && !canModerate) {
      return NextResponse.json({ error: 'Only the author or group moderators can delete this post.' }, { status: 403 })
    }
    await db.groupPost.delete({ where: { id: post.id } })
    return NextResponse.json({ ok: true })
  }

  if (action === 'delete_reply') {
    const reply = await db.groupPostReply.findUnique({ where: { id: String(body.replyId || '') } })
    if (!reply) return NextResponse.json({ error: 'Reply not found' }, { status: 404 })
    const post = await db.groupPost.findUnique({ where: { id: reply.postId } })
    if (!post || post.groupId !== id) return NextResponse.json({ error: 'Reply not found' }, { status: 404 })
    const canModerate = eff.perms.includes('moderate')
    if (reply.authorId !== user.id && !canModerate) {
      return NextResponse.json({ error: 'Only the author or group moderators can delete this reply.' }, { status: 403 })
    }
    await db.groupPostReply.delete({ where: { id: reply.id } })
    return NextResponse.json({ ok: true })
  }

  /* ---- ROLES: assign member, create, update, delete (requires "roles" perm) ---- */
  if (action === 'set_role') {
    if (!eff.perms.includes('roles')) {
      return NextResponse.json({ error: 'You need the Roles permission to assign roles.' }, { status: 403 })
    }
    const member = await db.groupMember.findUnique({
      where: { groupId_userId: { groupId: id, userId: String(body.userId || '') } },
    })
    if (!member) return NextResponse.json({ error: 'That player is not a member of this group.' }, { status: 404 })
    if (member.userId === group.ownerId) {
      return NextResponse.json({ error: 'The owner role cannot change.' }, { status: 400 })
    }
    const newRole = String(body.role || 'member')
    if (newRole !== 'member') {
      const role = await db.groupRole.findUnique({ where: { groupId_name: { groupId: id, name: newRole } } })
      if (!role) return NextResponse.json({ error: 'That role does not exist.' }, { status: 400 })
      // cannot assign a role at or above your own rank (owner + site admin bypass)
      if (!eff.isOwner && user.role !== 'admin') {
        const myRoleName = eff.role
        const myRole = myRoleName && myRoleName !== 'owner' && myRoleName !== 'member'
          ? await db.groupRole.findUnique({ where: { groupId_name: { groupId: id, name: myRoleName } } })
          : null
        if (!myRole || role.rank < myRole.rank) {
          return NextResponse.json({ error: 'You cannot assign a role at or above your own rank.' }, { status: 403 })
        }
      }
    }
    await db.groupMember.update({ where: { id: member.id }, data: { role: newRole } })
    return NextResponse.json({ ok: true, role: newRole })
  }

  if (action === 'add_role' || action === 'update_role') {
    if (!eff.perms.includes('roles')) {
      return NextResponse.json({ error: 'You need the Roles permission to manage roles.' }, { status: 403 })
    }
    const name = String(body.name || '').trim()
    if (!name || name.length > 24) return NextResponse.json({ error: 'Role name must be 1-24 characters.' }, { status: 400 })
    if (name.toLowerCase() === 'owner') return NextResponse.json({ error: 'The Owner title belongs to the group owner.' }, { status: 400 })
    const color = /^#[0-9a-fA-F]{6}$/.test(String(body.color || '')) ? String(body.color) : '#0d69ac'
    const rank = Math.min(Math.max(parseInt(String(body.rank ?? '50')) || 50, 10), 90)
    const perms = Array.isArray(body.perms) ? (body.perms as string[]).filter((p) => (PERMS as readonly string[]).includes(p)) : []

    if (action === 'add_role') {
      const exists = await db.groupRole.findUnique({ where: { groupId_name: { groupId: id, name } } })
      if (exists) return NextResponse.json({ error: `A role named "${name}" already exists.` }, { status: 400 })
      const role = await db.groupRole.create({ data: { groupId: id, name, color, rank, permsJson: JSON.stringify(perms) } })
      return NextResponse.json({ role: { id: role.id, name: role.name, color: role.color, rank: role.rank, perms } })
    }

    const existing = await db.groupRole.findUnique({ where: { groupId_name: { groupId: id, name: String(body.originalName || name) } } })
    if (!existing) return NextResponse.json({ error: 'Role not found.' }, { status: 404 })
    const role = await db.groupRole.update({
      where: { id: existing.id },
      data: { name, color, rank, permsJson: JSON.stringify(perms) },
    })
    // keep member.role labels in sync when a role is renamed
    if (existing.name !== name) {
      await db.groupMember.updateMany({ where: { groupId: id, role: existing.name }, data: { role: name } })
    }
    return NextResponse.json({ role: { id: role.id, name: role.name, color: role.color, rank: role.rank, perms } })
  }

  if (action === 'delete_role') {
    if (!eff.perms.includes('roles')) {
      return NextResponse.json({ error: 'You need the Roles permission to manage roles.' }, { status: 403 })
    }
    const existing = await db.groupRole.findUnique({ where: { groupId_name: { groupId: id, name: String(body.name || '') } } })
    if (!existing) return NextResponse.json({ error: 'Role not found.' }, { status: 404 })
    // members holding this role drop back to plain "member"
    await db.groupMember.updateMany({ where: { groupId: id, role: existing.name }, data: { role: 'member' } })
    await db.groupRole.delete({ where: { id: existing.id } })
    return NextResponse.json({ ok: true })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}

// DELETE /api/groups/[id] — owner or admin only
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const group = await db.group.findUnique({ where: { id } })
  if (!group) return NextResponse.json({ error: 'Group not found' }, { status: 404 })
  if (group.ownerId !== user.id && user.role !== 'admin') {
    return NextResponse.json({ error: 'Only the group owner can delete this group.' }, { status: 403 })
  }

  await db.group.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
