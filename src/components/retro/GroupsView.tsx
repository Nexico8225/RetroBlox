'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, fmtDate, timeAgo, flash, type RetroUser } from '@/lib/store'
import { Avatar, OnlineDot } from './Shell'
import { GameCard, GameSummary } from './HomeView'
import { RetroVideoPlayer } from './RetroVideoPlayer'
import dynamic from 'next/dynamic'
import type { Placement } from '@/lib/avatarAssets'

/** clean white item-only thumb for group-published 3D UGC */
const ItemThumb3D = dynamic(() => import('./ItemThumb3D'), { ssr: false })

/* ================= Groups directory (/groups) ================= */

interface GroupSummary {
  id: string
  name: string
  description: string
  iconUrl: string | null
  owner: { id: string; username: string; avatarUrl: string | null }
  memberCount: number
  gameCount: number
  createdAt: string
}

export function GroupsView() {
  const { setToast } = useRetro()
  const router = useRouter()
  const [groups, setGroups] = useState<GroupSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [showCreate, setShowCreate] = useState(false)
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [icon, setIcon] = useState<File | null>(null)
  const [iconPreview, setIconPreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const iconRef = useRef<HTMLInputElement>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = await api<{ groups: GroupSummary[] }>('/api/groups')
      setGroups(res.groups)
    } catch { /* ignore */ } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function createGroup(e?: React.FormEvent) {
    e?.preventDefault()
    setError('')
    if (name.trim().length < 3) {
      setError('Group name must be at least 3 characters.')
      return
    }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('name', name.trim())
      fd.append('description', description.trim())
      if (icon) fd.append('icon', icon)
      const res = await api<{ group: { id: string } }>('/api/groups', { method: 'POST', body: fd })
      flash(setToast, 'Group created! You are the owner.')
      router.push(`/groups/${res.group.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create group')
      setBusy(false)
    }
  }

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>Groups</span>
          <button className="rb-btn rb-btn-green" style={{ fontSize: 10, padding: '3px 10px' }} onClick={() => setShowCreate((s) => !s)}>
            {showCreate ? 'Close' : '+ Create a Group'}
          </button>
        </div>
        <div style={{ padding: '8px 12px', fontSize: 11, color: '#5a6b7b' }}>
          Groups are crews of blockheads — post on the wall, hand out roles, and publish games straight into it.
        </div>
      </div>

      {showCreate && (
        <form className="rb-box" style={{ marginBottom: 12 }} onSubmit={createGroup}>
          <div className="rb-panel-head"><span>Start a New Group</span></div>
          <div style={{ padding: 12, display: 'grid', gap: 10 }}>
            {error && (
              <div role="alert" style={{ background: '#fdebe9', border: '1px solid #e1231a', color: '#a81a13', fontSize: 11, padding: '7px 10px', borderRadius: 3 }}>
                {error}
              </div>
            )}
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
              <div style={{ textAlign: 'center' }}>
                <button
                  type="button"
                  onClick={() => iconRef.current?.click()}
                  title="Choose group emblem"
                  style={{
                    width: 64, height: 64, borderRadius: 6, border: icon ? '1px solid #4c9e34' : '1px dashed #8ba0b3',
                    padding: 0, overflow: 'hidden', background: '#eef4fa', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22, color: '#5a7b9a',
                  }}
                >
                  {iconPreview ? <img src={iconPreview} alt="Group emblem" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : '?'}
                </button>
                <input ref={iconRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={(e) => {
                  const f = e.target.files?.[0] || null
                  setIcon(f)
                  if (!f) { setIconPreview(null); return }
                  const r = new FileReader()
                  r.onload = () => setIconPreview(r.result as string)
                  r.readAsDataURL(f)
                  e.target.value = ''
                }} />
                <div style={{ fontSize: 9, color: '#7b8896', marginTop: 4 }}>Emblem</div>
              </div>
              <div style={{ flex: 1, minWidth: 220, display: 'grid', gap: 8, alignContent: 'start' }}>
                <div>
                  <label style={{ fontSize: 11, color: '#24425f', display: 'block', marginBottom: 3 }} htmlFor="gr-name">Group Name *</label>
                  <input id="gr-name" className="rb-input" style={{ width: '100%' }} value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="enter your group name" />
                </div>
                <div>
                  <label style={{ fontSize: 11, color: '#24425f', display: 'block', marginBottom: 3 }} htmlFor="gr-desc">Description</label>
                  <textarea id="gr-desc" className="rb-textarea" style={{ width: '100%' }} rows={2} value={description} onChange={(e) => setDescription(e.target.value)} maxLength={1000} placeholder="What is this group about?" />
                </div>
              </div>
            </div>
            <div>
              <button className="rb-btn rb-btn-green" type="submit" disabled={busy}>
                {busy ? 'Creating...' : 'Create Group'}
              </button>
              <span style={{ fontSize: 10, color: '#7b8896', marginLeft: 10 }}>You become the owner and the first member.</span>
            </div>
          </div>
        </form>
      )}

      {loading ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading groups...</div>
      ) : groups.length === 0 ? (
        <div className="rb-box" style={{ padding: '40px 20px', textAlign: 'center', color: '#5a6b7b' }}>
          <div style={{ fontSize: 15, marginBottom: 6 }}>No groups yet</div>
          <div style={{ fontSize: 11 }}>Be the first — start a crew and rule it like it is 2007.</div>
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: 10 }}>
          {groups.map((g) => (
            <Link
              key={g.id}
              href={`/groups/${g.id}`}
              className="rb-clickable"
              style={{
                background: '#fff', border: '1px solid #a8b6c2', borderRadius: 4, padding: 10,
                display: 'flex', gap: 10, textDecoration: 'none', alignItems: 'center',
              }}
              aria-label={`Open group ${g.name}`}
            >
              <span
                style={{
                  width: 48, height: 48, borderRadius: 6, border: '1px solid #8ba0b3', background: '#eef4fa', overflow: 'hidden',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, color: '#5a7b9a', flexShrink: 0,
                }}
              >
                {g.iconUrl ? <img src={g.iconUrl} alt={`${g.name} emblem`} style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : '?'}
              </span>
              <span style={{ minWidth: 0, flex: 1 }}>
                <span className="rb-link" style={{ fontSize: 12, display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{g.name}</span>
                <span style={{ display: 'block', fontSize: 10, color: '#5a6b7b', marginTop: 2 }}>
                  {g.memberCount} member{g.memberCount === 1 ? '' : 's'} · {g.gameCount} game{g.gameCount === 1 ? '' : 's'}
                </span>
                <span style={{ display: 'block', fontSize: 9, color: '#7b8896', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  Led by {g.owner.username}
                </span>
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

/* ================= Group detail (/groups/[id]) ================= */

interface GroupRoleT {
  id: string
  name: string
  color: string
  rank: number
  perms: string[]
}

interface GroupPostT {
  id: string
  body: string
  mediaFileId: string | null
  mediaType: string | null
  mediaName: string | null
  likeIds: string[]
  author: { id: string; username: string; avatarUrl: string | null; role: string }
  createdAt: string
  replies: { id: string; text: string; author: { id: string; username: string; avatarUrl: string | null; role: string }; createdAt: string }[]
}

interface GroupDetailT {
  group: {
    id: string
    name: string
    description: string
    iconUrl: string | null
    owner: { id: string; username: string; avatarUrl: string | null; role: string }
    createdAt: string
    members: { id: string; role: string; joinedAt: string; user: RetroUser & { createdAt: string } }[]
    roles: GroupRoleT[]
    posts: GroupPostT[]
    games: GameSummary[]
  }
  ugcItems: {
    id: string
    assetId: string
    name: string
    description: string
    type: string
    imageFileId: string
    modelFileId?: string | null
    textureFileId?: string | null
    baseColor?: string | null
    roughness?: number | null
    metallic?: number | null
    placement?: Placement | null
    creator: { id: string; username: string; avatarUrl: string | null }
    createdAt: string
  }[]
  myMembership: { role: string } | null
  myPerms: string[]
  myRole: string | null
}

const PERM_LABELS: Record<string, string> = {
  post: 'Post on the wall',
  moderate: 'Moderate wall (delete posts)',
  roles: 'Manage + assign roles',
  games: 'Manage group games',
  ugc: 'Publish group UGC (hats, gear...)',
  settings: 'Edit group settings',
}

function RoleBadge({ name, color }: { name: string; color: string }) {
  return (
    <span
      style={{
        fontSize: 9,
        padding: '1px 7px',
        borderRadius: 8,
        background: `${color}22`,
        border: `1px solid ${color}`,
        color,
        whiteSpace: 'nowrap',
      }}
    >
      {name}
    </span>
  )
}

function memberRoleInfo(m: { role: string }, roles: GroupRoleT[], ownerId: string): { label: string; color: string } {
  if (m.role === 'owner') return { label: 'Owner', color: '#b8860b' }
  const role = roles.find((r) => r.name === m.role)
  if (role) return { label: role.name, color: role.color }
  return { label: 'Member', color: '#7b8896' }
}

export function GroupDetailView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const [data, setData] = useState<GroupDetailT | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [tab, setTab] = useState<'wall' | 'games' | 'ugc' | 'members' | 'settings'>('wall')

  const load = useCallback(async () => {
    try {
      const res = await api<GroupDetailT>(`/api/groups/${id}`)
      setData(res)
      setError('')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load group')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => { load() }, [load])

  useEffect(() => {
    if (data) document.title = `${data.group.name} - RetroBlox`
  }, [data])

  async function act(payload: Record<string, unknown>, okMsg?: string) {
    try {
      const res = await api<Record<string, unknown>>(`/api/groups/${id}`, { method: 'POST', body: JSON.stringify(payload) })
      if (okMsg) flash(setToast, okMsg)
      await load()
      return res
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
      return null
    }
  }

  async function joinLeave(action: 'join' | 'leave') {
    setBusy(true)
    await act({ action }, action === 'join' ? 'Welcome to the group!' : 'You left the group.')
    setBusy(false)
  }

  async function deleteGroup() {
    if (!data) return
    if (!window.confirm(`Really delete "${data.group.name}" and remove it from all its games?`)) return
    try {
      await api(`/api/groups/${id}`, { method: 'DELETE' })
      flash(setToast, 'Group deleted.')
      router.push('/groups')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

  if (loading) return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading group...</div>
  if (error || !data) {
    return (
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#a81a13' }}>
        {error || 'Group not found'}
        <div style={{ marginTop: 12 }}>
          <button className="rb-btn" onClick={() => router.push('/groups')}>All Groups</button>
        </div>
      </div>
    )
  }

  const g = data.group
  const isMember = !!data.myMembership
  const isOwner = user?.id === g.owner.id
  const isAdmin = user?.role === 'admin'
  const canManageRoles = isOwner || isAdmin || data.myPerms.includes('roles')
  const canModerate = isOwner || isAdmin || data.myPerms.includes('moderate')
  const canPublishUgc = isOwner || isAdmin || data.myPerms.includes('ugc')

  return (
    <div>
      {/* header */}
      <div className="rb-box" style={{ overflow: 'hidden', marginBottom: 12 }}>
        <div className="rb-panel-head"><span>{g.name}</span><span style={{ fontSize: 10, color: '#5a6b7b' }}>Group</span></div>
        <div style={{ background: 'linear-gradient(180deg,#e9eef3,#cfd9e2)', padding: 14, display: 'flex', gap: 14, flexWrap: 'wrap', alignItems: 'center' }}>
          <span
            style={{
              width: 84, height: 84, borderRadius: 8, border: '2px solid #8ba0b3', background: '#eef4fa', overflow: 'hidden',
              display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 30, color: '#5a7b9a', flexShrink: 0,
              boxShadow: '2px 2px 0 rgba(0,0,0,.18)',
            }}
          >
            {g.iconUrl ? <img src={g.iconUrl} alt={`${g.name} emblem`} style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : '?'}
          </span>
          <div style={{ flex: 1, minWidth: 200 }}>
            <h1 style={{ fontSize: 22, color: '#1c2733', margin: 0 }}>{g.name}</h1>
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 4 }}>
              Created {fmtDate(g.createdAt)} · {g.members.length} member{g.members.length === 1 ? '' : 's'} · {g.games.length} game{g.games.length === 1 ? '' : 's'} · {g.posts.length} wall post{g.posts.length === 1 ? '' : 's'}
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 4, display: 'flex', alignItems: 'center', gap: 6 }}>
              Owner: <Link href={`/users/${g.owner.id}`} className="rb-link" style={{ fontSize: 11 }}>{g.owner.username}</Link>
              {data.myRole && data.myRole !== 'member' && (
                <>
                  {' · '}Your role:{' '}
                  {data.myRole === 'owner'
                    ? <RoleBadge name="Owner" color="#b8860b" />
                    : <RoleBadge name={data.myRole} color={g.roles.find((r) => r.name === data.myRole)?.color || '#0d69ac'} />}
                </>
              )}
            </div>
            <div style={{ marginTop: 10, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {isMember ? (
                <button className="rb-btn" disabled={busy || isOwner} onClick={() => joinLeave('leave')} title={isOwner ? 'Owners cannot leave' : undefined}>
                  ✓ Member
                </button>
              ) : (
                <button className="rb-btn rb-btn-green" disabled={busy} onClick={() => joinLeave('join')}>+ Join Group</button>
              )}
              {isMember && (
                <Link className="rb-btn" href={`/create?group=${g.id}`} style={{ textDecoration: 'none' }}>
                  Upload Game to Group
                </Link>
              )}
              {(isOwner || isAdmin) && (
                <button className="rb-btn rb-btn-red" onClick={deleteGroup}>Delete Group</button>
              )}
            </div>
          </div>
        </div>
        <div style={{ padding: 12, borderTop: '1px solid #e4eaf0', fontSize: 12, color: '#2c3e50', lineHeight: 1.65, whiteSpace: 'pre-wrap' }}>
          {g.description || 'This group has not written a description yet.'}
        </div>
      </div>

      {/* tab bar: Wall | Games | Members | Settings */}
      <div className="rb-box" style={{ padding: 0, overflow: 'hidden', marginBottom: 12 }}>
        <div style={{ display: 'flex', flexWrap: 'wrap' }}>
          {([
            ['wall', 'Wall'],
            ['games', `Games (${g.games.length})`],
            ['ugc', `UGC (${data.ugcItems.length})`],
            ['members', `Members (${g.members.length})`],
            ['settings', 'Settings'],
          ] as const).map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => setTab(key)}
              aria-pressed={tab === key}
              style={{
                flex: 1,
                textAlign: 'center',
                padding: '9px 6px',
                background: tab === key ? '#e3edf7' : 'transparent',
                border: 'none',
                borderLeft: key !== 'wall' ? '1px solid #e4eaf0' : 'none',
                borderBottom: tab === key ? '2px solid #2f7bc0' : '2px solid transparent',
                fontSize: 11,
                color: tab === key ? '#0a4f82' : '#5a6b7b',
                cursor: 'pointer',
                whiteSpace: 'nowrap',
              }}
            >
              {key === 'settings' && canManageRoles ? '⚙ Settings' : label}
            </button>
          ))}
        </div>
      </div>

      {tab === 'wall' && <GroupWall group={g} isMember={isMember} canModerate={canModerate} onChanged={load} />}

      {tab === 'games' && (
        <div className="rb-box">
          <div className="rb-panel-head"><span>Group Games ({g.games.length})</span></div>
          <div style={{ padding: 12, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(170px, 1fr))', gap: 10 }}>
            {g.games.length === 0 && (
              <div style={{ color: '#7b8896', fontSize: 11, padding: 6 }}>
                No games in this group yet.
                {isMember && <> Members can publish one from <Link className="rb-link" href={`/create?group=${g.id}`}>Create</Link>.</>}
              </div>
            )}
            {g.games.map((game) => <GameCard key={game.id} game={game} />)}
          </div>
        </div>
      )}

      {tab === 'ugc' && <GroupUgc group={g} ugcItems={data.ugcItems} canPublish={canPublishUgc} onChanged={load} />}

      {tab === 'members' && (
        <GroupMembers group={g} canManageRoles={canManageRoles} isOwner={isOwner} isSiteAdmin={isAdmin} myRole={data.myRole} onChanged={load} act={act} />
      )}

      {tab === 'settings' && canManageRoles && (
        <GroupRolesManager group={g} onChanged={load} act={act} />
      )}

      {tab === 'settings' && !canManageRoles && (
        <div className="rb-box" style={{ padding: 24, textAlign: 'center', color: '#5a6b7b', fontSize: 11 }}>
          Group settings are for the owner and role managers. Ask them for the Roles permission if you need it.
        </div>
      )}
    </div>
  )
}

/* ---------------- Wall: post + feed ---------------- */

function GroupWall({
  group, isMember, canModerate, onChanged,
}: {
  group: GroupDetailT['group']
  isMember: boolean
  canModerate: boolean
  onChanged: () => Promise<void>
}) {
  const { user, setToast } = useRetro()
  const [text, setText] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [filePreview, setFilePreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [replyBoxes, setReplyBoxes] = useState<Record<string, string>>({})
  const fileRef = useRef<HTMLInputElement>(null)

  async function post(e?: React.FormEvent) {
    e?.preventDefault()
    if (!user) return
    if (!text.trim()) return
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('body', text.trim())
      if (file) fd.append('file', file)
      await api(`/api/groups/${group.id}`, { method: 'POST', body: fd })
      setText('')
      setFile(null)
      setFilePreview(null)
      flash(setToast, 'Posted to the wall!')
      await onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed to post', 2400)
    } finally {
      setBusy(false)
    }
  }

  async function like(post: GroupPostT) {
    if (!user) return
    try {
      await api(`/api/groups/${group.id}`, { method: 'POST', body: JSON.stringify({ action: 'like_post', postId: post.id }) })
      await onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed', 2200)
    }
  }

  async function delPost(post: GroupPostT) {
    if (!window.confirm('Delete this wall post?')) return
    try {
      await api(`/api/groups/${group.id}`, { method: 'POST', body: JSON.stringify({ action: 'delete_post', postId: post.id }) })
      await onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed', 2200)
    }
  }

  async function reply(post: GroupPostT) {
    const text = (replyBoxes[post.id] || '').trim()
    if (!text) return
    try {
      await api(`/api/groups/${group.id}`, { method: 'POST', body: JSON.stringify({ action: 'reply', postId: post.id, text }) })
      setReplyBoxes((r) => ({ ...r, [post.id]: '' }))
      await onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed', 2200)
    }
  }

  async function delReply(postId: string, replyId: string) {
    try {
      await api(`/api/groups/${group.id}`, { method: 'POST', body: JSON.stringify({ action: 'delete_reply', replyId }) })
      await onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed', 2200)
    }
  }

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      {/* composer */}
      {user ? (
        isMember ? (
          <form className="rb-box" onSubmit={post}>
            <div className="rb-panel-head"><span>Post to the Wall</span></div>
            <div style={{ padding: 10, display: 'grid', gap: 8 }}>
              <textarea
                className="rb-textarea"
                value={text}
                onChange={(e) => setText(e.target.value)}
                rows={3}
                maxLength={2000}
                placeholder={`Say something to ${group.name}...`}
                style={{ width: '100%' }}
                aria-label="Wall post text"
              />
              {filePreview && file?.type.startsWith('image/') && (
                <img src={filePreview} alt="Attachment preview" style={{ maxHeight: 180, maxWidth: '100%', border: '1px solid #c3cdd7', borderRadius: 4 }} />
              )}
              {file && file.type.startsWith('video/') && (
                <div style={{ fontSize: 10, color: '#2c6e31', background: '#e8f5e4', border: '1px solid #9fce93', borderRadius: 4, padding: '5px 8px' }}>
                  ▶ Video attached: {file.name} ({Math.ceil(file.size / (1024 * 1024))}MB) — plays right on the wall.
                </div>
              )}
              <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/*,video/*"
                  style={{ display: 'none' }}
                  onChange={(e) => {
                    const f = e.target.files?.[0] || null
                    setFile(f)
                    if (!f) { setFilePreview(null); return }
                    if (f.type.startsWith('image/')) {
                      const r = new FileReader()
                      r.onload = () => setFilePreview(r.result as string)
                      r.readAsDataURL(f)
                    } else {
                      setFilePreview(null)
                    }
                    e.target.value = ''
                  }}
                />
                <button type="button" className="rb-btn" style={{ fontSize: 10 }} onClick={() => fileRef.current?.click()}>
                  + Image / Video
                </button>
                {file && (
                  <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }} onClick={() => { setFile(null); setFilePreview(null) }}>
                    remove
                  </button>
                )}
                <span style={{ marginLeft: 'auto', fontSize: 9, color: '#7b8896' }}>Images 8MB · Videos 100MB</span>
                <button className="rb-btn rb-btn-green" type="submit" disabled={busy || !text.trim()} style={{ fontSize: 11 }}>
                  {busy ? 'Posting...' : 'Post to Wall'}
                </button>
              </div>
            </div>
          </form>
        ) : (
          <div className="rb-box" style={{ padding: 14, textAlign: 'center', fontSize: 11, color: '#5a6b7b' }}>
            Join the group to post on its wall!
          </div>
        )
      ) : (
        <div className="rb-box" style={{ padding: 14, textAlign: 'center', fontSize: 11, color: '#5a6b7b' }}>
          <Link className="rb-link" href="/login" style={{ fontSize: 11 }}>Log in</Link> to join the conversation.
        </div>
      )}

      {/* feed */}
      {group.posts.length === 0 && (
        <div className="rb-box" style={{ padding: '30px 20px', textAlign: 'center', color: '#5a6b7b' }}>
          <div style={{ fontSize: 14, marginBottom: 4 }}>The wall is empty</div>
          <div style={{ fontSize: 11 }}>Post the first message — images and videos welcome.</div>
        </div>
      )}

      {group.posts.map((p) => {
        const liked = user ? p.likeIds.includes(user.id) : false
        return (
          <div key={p.id} className="rb-box" style={{ padding: 10 }}>
            <div style={{ display: 'flex', gap: 8 }}>
              <Link href={`/users/${p.author.id}`} style={{ flexShrink: 0 }}>
                <Avatar user={p.author} size={38} />
              </Link>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                  <Link href={`/users/${p.author.id}`} className="rb-link" style={{ fontSize: 11 }}>{p.author.username}</Link>
                  {p.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                  <span style={{ fontSize: 10, color: '#7b8896' }}>{timeAgo(p.createdAt)}</span>
                  {(canModerate || user?.id === p.author.id) && (
                    <button
                      type="button"
                      className="rb-link"
                      style={{ background: 'none', border: 'none', padding: 0, fontSize: 10, color: '#a03a34', marginLeft: 'auto' }}
                      onClick={() => delPost(p)}
                      title="Delete post"
                    >
                      ✕ delete
                    </button>
                  )}
                </div>
                <div style={{ fontSize: 12, color: '#2c3e50', marginTop: 3, lineHeight: 1.55, whiteSpace: 'pre-wrap' }}>{p.body}</div>
                {p.mediaFileId && p.mediaType === 'image' && (
                  <img src={`/api/files/${p.mediaFileId}`} alt={p.mediaName || 'Wall image'} style={{ marginTop: 8, maxHeight: 300, maxWidth: '100%', border: '1px solid #c3cdd7', borderRadius: 4 }} />
                )}
                {p.mediaFileId && p.mediaType === 'video' && (
                  <div style={{ marginTop: 8, maxWidth: 480 }}>
                    <RetroVideoPlayer src={`/api/files/${p.mediaFileId}`} title={p.mediaName || 'Wall video'} />
                  </div>
                )}

                {/* like + reply actions */}
                <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 10 }}>
                  <button
                    type="button"
                    className="rb-clickable"
                    onClick={() => like(p)}
                    style={{
                      background: 'none',
                      border: 'none',
                      padding: 0,
                      fontSize: 10,
                      color: liked ? '#c2570e' : '#5a6b7b',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 4,
                    }}
                    aria-pressed={liked}
                  >
                    <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true">
                      <path d="M8 1l2.1 4.3 4.7.7-3.4 3.3.8 4.7L8 11.8l-4.2 2.2.8-4.7L1.2 6l4.7-.7z" fill={liked ? '#f2b01e' : '#c3cdd7'} stroke="#a8b6c2" strokeWidth="0.8" />
                    </svg>
                    {p.likeIds.length} like{p.likeIds.length === 1 ? '' : 's'}
                  </button>
                  {user && (
                    <button
                      type="button"
                      className="rb-link"
                      style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }}
                      onClick={() =>
                        setReplyBoxes((r) => {
                          const next = { ...r }
                          if (next[p.id] !== undefined) delete next[p.id]
                          else next[p.id] = ''
                          return next
                        })
                      }
                    >
                      💬 Reply
                    </button>
                  )}
                </div>

                {/* replies */}
                {p.replies.length > 0 && (
                  <div style={{ marginTop: 8, borderLeft: '2px solid #e4eaf0', paddingLeft: 10, display: 'grid', gap: 6 }}>
                    {p.replies.map((r) => (
                      <div key={r.id} style={{ display: 'flex', gap: 6 }}>
                        <Link href={`/users/${r.author.id}`} style={{ flexShrink: 0 }}>
                          <Avatar user={r.author} size={24} />
                        </Link>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                            <Link href={`/users/${r.author.id}`} className="rb-link" style={{ fontSize: 10 }}>{r.author.username}</Link>
                            <span style={{ fontSize: 9, color: '#7b8896' }}>{timeAgo(r.createdAt)}</span>
                            {(canModerate || user?.id === r.author.id) && (
                              <button
                                type="button"
                                className="rb-link"
                                style={{ background: 'none', border: 'none', padding: 0, fontSize: 9, color: '#a03a34', marginLeft: 'auto' }}
                                onClick={() => delReply(p.id, r.id)}
                              >
                                ✕
                              </button>
                            )}
                          </div>
                          <div style={{ fontSize: 11, color: '#2c3e50', whiteSpace: 'pre-wrap' }}>{r.text}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}

                {/* reply box */}
                {user && replyBoxes[p.id] !== undefined && (
                  <div style={{ marginTop: 8, display: 'flex', gap: 6 }}>
                    <input
                      className="rb-input"
                      value={replyBoxes[p.id] || ''}
                      onChange={(e) => setReplyBoxes((r) => ({ ...r, [p.id]: e.target.value }))}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') reply(p)
                      }}
                      maxLength={500}
                      placeholder="Write a reply..."
                      style={{ flex: 1, fontSize: 11 }}
                      aria-label="Reply to wall post"
                    />
                    <button className="rb-btn rb-btn-green" type="button" style={{ fontSize: 10 }} onClick={() => reply(p)} disabled={!(replyBoxes[p.id] || '').trim()}>
                      Send
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}

/* ---------------- Members tab: list + role assignment ---------------- */

function GroupMembers({
  group, canManageRoles, isOwner, isSiteAdmin, myRole, onChanged, act,
}: {
  group: GroupDetailT['group']
  canManageRoles: boolean
  isOwner: boolean
  isSiteAdmin: boolean
  myRole: string | null
  onChanged: () => Promise<void>
  act: (payload: Record<string, unknown>, okMsg?: string) => Promise<Record<string, unknown> | null>
}) {
  const myRoleRow = myRole && myRole !== 'owner' && myRole !== 'member'
    ? group.roles.find((r) => r.name === myRole)
    : null
  const myRank = isOwner || isSiteAdmin ? 0 : myRoleRow ? myRoleRow.rank : 50

  return (
    <div className="rb-box">
      <div className="rb-panel-head"><span>Members ({group.members.length})</span></div>
      <div style={{ padding: 10, display: 'grid', gap: 8 }}>
        {canManageRoles && (
          <div style={{ fontSize: 10, color: '#5a6b7b', background: '#f4f8fb', border: '1px solid #c3cdd7', borderRadius: 4, padding: '6px 10px' }}>
            Assign roles with the dropdown — you can only give roles below your own rank.
            Create or edit roles under the ⚙ Settings tab.
          </div>
        )}
        {group.members.map((m) => {
          const info = memberRoleInfo(m, group.roles, group.owner.id)
          const isTargetOwner = m.role === 'owner'
          const targetRow = group.roles.find((r) => r.name === m.role)
          const targetRank = targetRow ? targetRow.rank : 50
          const canTouch = canManageRoles && !isTargetOwner && m.user.id !== group.owner.id && (isOwner || isSiteAdmin || myRank < targetRank)
          return (
            <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <Link href={`/users/${m.user.id}`} style={{ position: 'relative', display: 'inline-block' }} aria-label={`View ${m.user.username}`}>
                <Avatar user={m.user} size={34} />
                <span style={{ position: 'absolute', right: -2, bottom: 0 }}>
                  <OnlineDot online={m.user.online} />
                </span>
              </Link>
              <div style={{ flex: 1, minWidth: 120 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 5, flexWrap: 'wrap' }}>
                  <Link href={`/users/${m.user.id}`} className="rb-link" style={{ fontSize: 11, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {m.user.username}
                  </Link>
                  <RoleBadge name={info.label} color={info.color} />
                </div>
                <span style={{ fontSize: 9, color: '#7b8896' }}>Joined {timeAgo(m.joinedAt)}</span>
              </div>
              {canTouch && (
                <select
                  className="rb-select"
                  value={m.role === 'member' || m.role === 'owner' ? 'member' : m.role}
                  onChange={(e) => act({ action: 'set_role', userId: m.user.id, role: e.target.value }, `${m.user.username} is now ${e.target.value === 'member' ? 'a plain member' : e.target.value}!`)}
                  style={{ fontSize: 10, padding: '2px 5px', maxWidth: 140 }}
                  aria-label={`Role for ${m.user.username}`}
                >
                  <option value="member">Member (no role)</option>
                  {group.roles
                    .slice()
                    .sort((a, b) => a.rank - b.rank)
                    .filter((r) => isOwner || isSiteAdmin || r.rank > myRank)
                    .map((r) => (
                      <option key={r.id} value={r.name}>{r.name}</option>
                    ))}
                </select>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}

/* ---------------- Settings tab: roles manager ---------------- */

function GroupRolesManager({
  group, onChanged, act,
}: {
  group: GroupDetailT['group']
  onChanged: () => Promise<void>
  act: (payload: Record<string, unknown>, okMsg?: string) => Promise<Record<string, unknown> | null>
}) {
  const [name, setName] = useState('')
  const [color, setColor] = useState('#0d69ac')
  const [rank, setRank] = useState(30)
  const [perms, setPerms] = useState<string[]>([])
  const [editing, setEditing] = useState<string | null>(null) // role name being edited

  const SWATCHES = ['#0d69ac', '#4c9e34', '#c43c3c', '#b8860b', '#7d3c98', '#e07b00', '#16808c', '#5a6b7b']

  function startEdit(role: GroupRoleT) {
    setEditing(role.name)
    setName(role.name)
    setColor(role.color)
    setRank(role.rank)
    setPerms(role.perms)
  }

  function resetForm() {
    setEditing(null)
    setName('')
    setColor('#0d69ac')
    setRank(30)
    setPerms([])
  }

  async function saveRole() {
    if (!name.trim()) return
    const payload = editing
      ? { action: 'update_role', originalName: editing, name: name.trim(), color, rank, perms }
      : { action: 'add_role', name: name.trim(), color, rank, perms }
    const res = await act(payload, editing ? 'Role updated!' : `Role "${name.trim()}" created!`)
    if (res) resetForm()
  }

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      {/* existing roles */}
      <div className="rb-box">
        <div className="rb-panel-head"><span>Roles ({group.roles.length})</span></div>
        <div style={{ padding: 10, display: 'grid', gap: 8 }}>
          <div style={{ fontSize: 10, color: '#5a6b7b', background: '#f4f8fb', border: '1px solid #c3cdd7', borderRadius: 4, padding: '6px 10px' }}>
            Rank = power level. Lower number = more power. Members can only assign/edit roles with a HIGHER rank number than their own.
            The group owner (rank 0) always outranks everyone.
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 2px', borderBottom: '1px solid #e4eaf0' }}>
            <RoleBadge name="Owner" color="#b8860b" />
            <span style={{ fontSize: 10, color: '#7b8896' }}>Rank 0 · everything allowed · the group founder</span>
          </div>

          {group.roles.length === 0 && (
            <div style={{ fontSize: 11, color: '#7b8896', padding: '4px 2px' }}>
              No custom roles yet. Create one below — e.g. &quot;Admin&quot; or &quot;Moderator&quot;.
            </div>
          )}

          {group.roles.slice().sort((a, b) => a.rank - b.rank).map((role) => (
            <div key={role.id} style={{ border: '1px solid #e4eaf0', borderRadius: 4, padding: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <RoleBadge name={role.name} color={role.color} />
                <span style={{ fontSize: 10, color: '#7b8896' }}>Rank {role.rank}</span>
                <span style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
                  <button type="button" className="rb-btn" style={{ fontSize: 9, padding: '2px 8px' }} onClick={() => startEdit(role)}>Edit</button>
                  <button
                    type="button"
                    className="rb-btn rb-btn-red"
                    style={{ fontSize: 9, padding: '2px 8px' }}
                    onClick={() => {
                      if (window.confirm(`Delete role "${role.name}"? Members holding it drop back to plain Member.`)) {
                        act({ action: 'delete_role', name: role.name }, 'Role deleted.')
                      }
                    }}
                  >
                    Delete
                  </button>
                </span>
              </div>
              <div style={{ marginTop: 4, fontSize: 9, color: '#5a6b7b', display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {Object.keys(PERM_LABELS).map((perm) => (
                  <span
                    key={perm}
                    style={{
                      fontSize: 9,
                      padding: '1px 6px',
                      borderRadius: 8,
                      border: `1px solid ${role.perms.includes(perm) ? '#4c9e34' : '#c3cdd7'}`,
                      background: role.perms.includes(perm) ? '#e8f5e4' : '#f4f8fb',
                      color: role.perms.includes(perm) ? '#2c6e31' : '#7b8896',
                    }}
                  >
                    {PERM_LABELS[perm].replace(' on the wall', '').replace(' (delete posts)', '').replace(' + assign roles', '').replace(' group games', '')}
                  </span>
                ))}
                {role.perms.length === 0 && <span style={{ color: '#7b8896' }}>No permissions — badge only</span>}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* create / edit form */}
      <div className="rb-box">
        <div className="rb-panel-head"><span>{editing ? `Edit Role: ${editing}` : 'Create a Role'}</span></div>
        <div style={{ padding: 12, display: 'grid', gap: 10 }}>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
            <div style={{ flex: '1 1 180px' }}>
              <label style={{ fontSize: 11, color: '#24425f', display: 'block', marginBottom: 3 }} htmlFor="role-name">Role Name *</label>
              <input id="role-name" className="rb-input" value={name} onChange={(e) => setName(e.target.value)} maxLength={24} placeholder="Admin, Moderator, Builder..." style={{ width: '100%' }} />
            </div>
            <div>
              <label style={{ fontSize: 11, color: '#24425f', display: 'block', marginBottom: 3 }} htmlFor="role-rank">Rank (10 = boss, 90 = peon)</label>
              <input id="role-rank" type="number" min={10} max={90} className="rb-input" value={rank} onChange={(e) => setRank(parseInt(e.target.value) || 50)} style={{ width: 110 }} />
            </div>
          </div>

          <div>
            <div style={{ fontSize: 11, color: '#24425f', marginBottom: 4 }}>Badge Color</div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
              {SWATCHES.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setColor(c)}
                  aria-label={`Color ${c}`}
                  style={{
                    width: 24,
                    height: 24,
                    background: c,
                    border: color === c ? '2px solid #1c2733' : '1px solid #8ba0b3',
                    borderRadius: 4,
                    cursor: 'pointer',
                    padding: 0,
                  }}
                />
              ))}
              <input type="color" value={color} onChange={(e) => setColor(e.target.value)} aria-label="Custom color" style={{ width: 30, height: 26, padding: 0, border: '1px solid #8ba0b3', borderRadius: 4, background: '#fff' }} />
              <RoleBadge name={name.trim() || 'Preview'} color={color} />
            </div>
          </div>

          <div>
            <div style={{ fontSize: 11, color: '#24425f', marginBottom: 4 }}>Permissions</div>
            <div style={{ display: 'grid', gap: 4 }}>
              {Object.entries(PERM_LABELS).map(([perm, label]) => (
                <label key={perm} style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: '#2c3e50', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={perms.includes(perm)}
                    onChange={(e) => setPerms((ps) => (e.target.checked ? [...ps, perm] : ps.filter((p) => p !== perm)))}
                  />
                  {label}
                </label>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8 }}>
            <button className="rb-btn rb-btn-green" onClick={saveRole} disabled={!name.trim()} type="button">
              {editing ? 'Save Role' : 'Create Role'}
            </button>
            {editing && (
              <button className="rb-btn" onClick={resetForm} type="button">Cancel</button>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

/* ---------------- UGC tab: publish + browse the group's avatar items ---------------- */

function GroupUgc({
  group, ugcItems, canPublish, onChanged,
}: {
  group: GroupDetailT['group']
  ugcItems: GroupDetailT['ugcItems']
  canPublish: boolean
  onChanged: () => void
}) {
  const { setToast } = useRetro()
  const [name, setName] = useState('')
  const [type, setType] = useState('hat')
  const [description, setDescription] = useState('')
  const [image, setImage] = useState<File | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const { user } = useRetro()

  function pick(f: File | null) {
    setImage(f)
    if (f) {
      const r = new FileReader()
      r.onload = () => setPreview(r.result as string)
      r.readAsDataURL(f)
    } else setPreview(null)
  }

  async function publish(e: React.FormEvent) {
    e.preventDefault()
    if (name.trim().length < 3) { flash(setToast, 'Give the item a name (3+ characters).'); return }
    if (!image) { flash(setToast, 'Pick an image for the item.'); return }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('name', name.trim())
      fd.append('type', type)
      fd.append('description', description.trim())
      fd.append('groupId', group.id)
      if (image) fd.append('image', image)
      const res = await api<{ item: { assetId: string } }>('/api/catalog', { method: 'POST', body: fd })
      flash(setToast, `Published for ${group.name}! Asset id: ${res.item.assetId}`)
      setName(''); setDescription(''); setImage(null); setPreview(null); setShowForm(false)
      onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Publish failed', 2600)
    } finally {
      setBusy(false)
    }
  }

  async function removeItem(item: GroupDetailT['ugcItems'][number]) {
    if (!window.confirm(`Delete "${item.name}" from the catalog?`)) return
    try {
      await api(`/api/catalog/${item.id}`, { method: 'DELETE' })
      flash(setToast, 'UGC deleted.')
      onChanged()
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed', 2400)
    }
  }

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>{group.name} UGC</span>
          {canPublish && (
            <button className="rb-btn rb-btn-green" style={{ fontSize: 10, padding: '3px 10px' }} onClick={() => setShowForm(!showForm)}>
              {showForm ? 'Close' : '+ Publish Item'}
            </button>
          )}
        </div>
        <div style={{ padding: '10px 12px', fontSize: 11, color: '#41586c' }}>
          Hats, faces and gear published in this group's name. Anyone can Get them from the{' '}
          <Link href="/catalog" className="rb-link">Catalog</Link> and wear them in every RetroBlox game.
          {canPublish && <> Give a role the <span style={{ fontFamily: 'monospace' }}>ugc</span> permission (Settings) to let its members publish here too.</>}
        </div>
      </div>

      {showForm && canPublish && (
        <div className="rb-box" style={{ marginBottom: 12 }}>
          <div className="rb-panel-head"><span>Publish Avatar UGC for {group.name}</span></div>
          <form onSubmit={publish} style={{ padding: 12, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
            <div
              onClick={() => fileRef.current?.click()}
              role="button"
              tabIndex={0}
              onKeyDown={(e) => { if (e.key === 'Enter') fileRef.current?.click() }}
              style={{
                width: 120, height: 120, border: '2px dashed #8ba0b3', background: '#f4f8fb', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', flexShrink: 0,
              }}
            >
              {preview ? <img src={preview} alt="Item preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : <span style={{ fontSize: 24, color: '#5a7b9a' }}>+</span>}
            </div>
            <input ref={fileRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={(e) => pick(e.target.files?.[0] || null)} />
            <div style={{ flex: 1, minWidth: 220 }}>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
                <input className="rb-input" value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="enter your item name" style={{ flex: 2, minWidth: 150, fontSize: 11 }} />
                <select className="rb-input" value={type} onChange={(e) => setType(e.target.value)} style={{ flex: 1, minWidth: 100, fontSize: 11 }} aria-label="Item type">
                  <option value="hat">Hat</option>
                  <option value="face">Face</option>
                  <option value="shirt">Shirt</option>
                  <option value="pants">Pants</option>
                  <option value="gear">Gear</option>
                </select>
              </div>
              <textarea className="rb-textarea" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={600} rows={2} placeholder="Description (optional)" style={{ width: '100%', fontSize: 11, marginBottom: 8, resize: 'vertical' }} />
              <button className="rb-btn rb-btn-green" type="submit" disabled={busy} style={{ fontSize: 11 }}>
                {busy ? 'Publishing...' : 'Publish'}
              </button>
            </div>
          </form>
        </div>
      )}

      {ugcItems.length === 0 ? (
        <div className="rb-box" style={{ padding: 30, textAlign: 'center', color: '#7b8896', fontSize: 11 }}>
          This group hasn't published any avatar items yet.
          {canPublish ? ' Publish the first one above!' : ''}
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 10 }}>
          {ugcItems.map((item) => (
            <div key={item.id} className="rb-box rb-card" style={{ padding: 0, overflow: 'hidden' }}>
              {/* saved shot paints first, live 3D render covers it — slot can never be blank */}
              <div style={{ position: 'relative' }}>
                <img src={`/api/files/${item.imageFileId}`} alt={item.name} style={{ width: '100%', aspectRatio: '1', objectFit: 'cover', display: 'block', background: '#fff' }} />
                {item.modelFileId && (
                  <div style={{ position: 'absolute', inset: 0 }}>
                    <ItemThumb3D
                      modelUrl={`/api/files/${item.modelFileId}`}
                      placement={item.placement}
                      alt={item.name}
                      fallbackSrc={`/api/files/${item.imageFileId}`}
                      textureUrl={item.textureFileId ? `/api/files/${item.textureFileId}` : undefined}
                      color={item.baseColor || undefined}
                      roughness={item.roughness}
                      metallic={item.metallic}
                      style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', background: '#fff' }}
                    />
                  </div>
                )}
              </div>
              <div style={{ padding: 8 }}>
                <div style={{ fontSize: 12, color: '#1c2733', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.name}</div>
                <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#7b8896', margin: '2px 0' }}>{item.assetId} · {item.type}</div>
                <div style={{ fontSize: 10, color: '#5a6b7b' }}>by {item.creator.username} · {timeAgo(item.createdAt)}</div>
                {(canPublish || user?.id === item.creator.id) && (
                  <button className="rb-btn rb-btn-red" style={{ fontSize: 10, padding: '2px 8px', marginTop: 6 }} onClick={() => removeItem(item)}>
                    Delete
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
