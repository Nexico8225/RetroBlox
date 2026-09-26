'use client'

/* ------------------------------------------------------------------
   r/ COMMUNITIES — the player-created part of the RETROBLOX lounge.
   - CommunitySidebar: the Reddit-style right rail (About card per r/,
     communities list with icons + member counts, Trending, Rules)
   - SubsBrowseView: /subs — browse + join every community
   - SubsNewView: /subs/new — create your own r/ community
------------------------------------------------------------------ */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, flash, timeAgo } from '@/lib/store'
import { Avatar } from './Shell'
import { FxText } from '@/lib/textfx'

export interface SubT {
  id: string
  slug: string
  name: string
  description: string
  iconFileId: string | null
  bannerFileId: string | null
  color: string
  members: number
  posts: number
  creator: { id: string; username: string; avatarUrl: string | null; role: string }
  createdAt: string
  joined: boolean
}

/* ------- default r/ categories of the lounge ------- */

export const DEFAULT_R = [
  { r: 'r/general', label: 'r/general', blurb: 'hang out, say hi', color: '#0d69ac' },
  { r: 'r/memes', label: 'r/memes', blurb: 'blocky humor only', color: '#c2570e' },
  { r: 'r/help', label: 'r/help', blurb: 'stuck? ask here', color: '#2c6e31' },
  { r: 'r/finds', label: 'r/finds', blurb: 'cool games you discovered', color: '#5e3f9e' },
  { r: 'r/offtopic', label: 'r/offtopic', blurb: 'anything else', color: '#a03a34' },
  { r: 'r/videos', label: 'r/videos', blurb: 'watch player uploads', color: '#c81c14' },
]

/* r/ icon with letter/color fallback for player-created communities */
export function SubIcon({ sub, size = 26 }: { sub: { slug: string; color?: string; iconFileId?: string | null }; size?: number }) {
  const [err, setErr] = useState(false)
  const letter = (sub.slug || 'r').charAt(0).toUpperCase()
  if (sub.iconFileId && !err) {
    return (
      <img
        src={`/api/files/${sub.iconFileId}`}
        alt={`r/${sub.slug}`}
        width={size}
        height={size}
        onError={() => setErr(true)}
        style={{ width: size, height: size, borderRadius: '50%', objectFit: 'cover', border: '1px solid #c3cdd7', background: '#fff', flexShrink: 0 }}
      />
    )
  }
  return (
    <span
      aria-hidden="true"
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: sub.color || '#0d69ac',
        color: '#fff',
        fontSize: Math.round(size * 0.46),
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: "Verdana, sans-serif",
        flexShrink: 0,
        border: '1px solid rgba(0,0,0,.18)',
      }}
    >
      {letter}
    </span>
  )
}

/* ------- hook: the list of player-created subs ------- */

export function useSubs() {
  const [subs, setSubs] = useState<SubT[]>([])
  const [loaded, setLoaded] = useState(false)
  const reload = useCallback(async () => {
    try {
      const res = await api<{ subs: SubT[] }>('/api/subs')
      setSubs(res.subs)
    } catch {
      setSubs([])
    } finally {
      setLoaded(true)
    }
  }, [])
  useEffect(() => {
    reload()
    // any surface can ping this after a join/leave/create to refresh all rails
    const onChange = () => reload()
    window.addEventListener('rb:subs-changed', onChange)
    return () => window.removeEventListener('rb:subs-changed', onChange)
  }, [reload])
  return { subs, loaded, reload }
}

/* =================================================================
   RIGHT RAIL — Reddit-style sidebar used across /community surfaces
================================================================= */

const R_BLURBS: Record<string, string> = {
  'r/general': 'hang out, say hi, meet blockheads',
  'r/memes': 'blocky humor only — the funnier the better',
  'r/help': 'stuck in a game? ask the lounge',
  'r/finds': 'cool games and stuff you discovered',
  'r/offtopic': 'everything else goes here',
  'r/videos': 'player uploads — watch them right in the feed',
}

export function CommunitySidebar({
  active,
  trending,
}: {
  active: string // "r/all" | "r/videos" | "r/memes" ... | "r/<custom-slug>"
  trending?: { title: string; href: string; score: number }[]
}) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const { subs } = useSubs()
  const [stats, setStats] = useState<{ users?: number; videos?: number; community?: number } | null>(null)
  const [joinBusy, setJoinBusy] = useState('')

  useEffect(() => {
    api<{ users?: number; videos?: number; community?: number }>('/api/stats')
      .then(setStats)
      .catch(() => setStats(null))
  }, [])

  const activeSlug = active.startsWith('r/') ? active.slice(2) : ''
  const activeSub = subs.find((s) => s.slug === activeSlug)

  async function toggleJoin(sub: SubT) {
    if (!user) {
      router.push('/login')
      return
    }
    setJoinBusy(sub.slug)
    try {
      const res = await api<{ joined: boolean; members: number }>(`/api/subs/${sub.slug}`, { method: 'PATCH' })
      flash(setToast, res.joined ? `Welcome to r/${sub.slug}!` : `Left r/${sub.slug}.`, 2200)
      window.dispatchEvent(new CustomEvent('rb:subs-changed'))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    } finally {
      setJoinBusy('')
    }
  }

  return (
    <aside style={{ width: 300, flexShrink: 0, display: 'grid', gap: 12, alignContent: 'start' }} className="rb-comm-rail">
      {/* ---------- About card (per r/) ---------- */}
      {activeSub ? (
        <div className="rb-box" style={{ overflow: 'hidden', padding: 0 }}>
          <div
            style={{
              height: 64,
              background: activeSub.bannerFileId
                ? `url(/api/files/${activeSub.bannerFileId}) center/cover`
                : `linear-gradient(120deg,${activeSub.color},#5fb35f 75%,#ffd34e)`,
            }}
          />
          <div style={{ padding: '0 12px 12px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: -18, marginBottom: 8 }}>
              <span style={{ background: '#fff', border: '1px solid #c3cdd7', borderRadius: '50%', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 1px 4px rgba(0,0,0,.25)' }}>
                <SubIcon sub={activeSub} size={36} />
              </span>
            </div>
            <div style={{ fontSize: 15, color: '#1c2733' }}>r/{activeSub.slug}</div>
            {activeSub.name !== activeSub.slug && (
              <div style={{ fontSize: 10, color: '#7b8896' }}>{activeSub.name}</div>
            )}
            <div style={{ fontSize: 10, color: '#5a6b7b', margin: '6px 0 10px', lineHeight: 1.55 }}>
              {activeSub.description || 'A player-created community in the RETROBLOX lounge.'}
            </div>
            <div style={{ display: 'flex', gap: 18, fontSize: 11, color: '#1c2733' }}>
              <div>
                <div style={{ fontSize: 14 }}>{activeSub.members}</div>
                <div style={{ fontSize: 9, color: '#7b8896' }}>Members</div>
              </div>
              <div>
                <div style={{ fontSize: 14 }}>{activeSub.posts}</div>
                <div style={{ fontSize: 9, color: '#7b8896' }}>Posts</div>
              </div>
              <div>
                <div style={{ fontSize: 14 }}>{timeAgo(activeSub.createdAt).replace(' ago', '')}</div>
                <div style={{ fontSize: 9, color: '#7b8896' }}>Age</div>
              </div>
            </div>
            <div style={{ fontSize: 9, color: '#7b8896', marginTop: 10, borderTop: '1px solid #e4eaf0', paddingTop: 8, display: 'flex', alignItems: 'center', gap: 6 }}>
              <Avatar user={activeSub.creator} size={16} rounded="50%" />
              created by <Link href={`/users/${activeSub.creator.id}`} className="rb-link" style={{ fontSize: 9 }}>u/{activeSub.creator.username}</Link>
            </div>
            <button
              type="button"
              className={`rb-btn ${activeSub.joined ? '' : 'rb-btn-green'}`}
              style={{ width: '100%', marginTop: 10, fontSize: 12, padding: '7px 0' }}
              disabled={joinBusy === activeSub.slug}
              onClick={() => toggleJoin(activeSub)}
            >
              {activeSub.joined ? 'Joined ✓ — leave' : '+ Join community'}
            </button>
          </div>
        </div>
      ) : (
        <div className="rb-box" style={{ overflow: 'hidden', padding: 0 }}>
          <div style={{ height: 56, background: 'linear-gradient(120deg,#0d69ac,#5fb35f 55%,#ffd34e)', display: 'flex', alignItems: 'flex-end', padding: '0 12px 6px' }}>
            <span style={{ background: '#fff', border: '1px solid #c3cdd7', borderRadius: '50%', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: -22, boxShadow: '0 1px 4px rgba(0,0,0,.25)' }}>
              <img src="/retro/logo.png" alt="" width={34} height={34} />
            </span>
          </div>
          <div style={{ padding: '26px 12px 12px' }}>
            <div style={{ fontSize: 14, color: '#1c2733' }}>{active === 'r/videos' ? 'r/videos' : 'r/RetroBloxLounge'}</div>
            <div style={{ fontSize: 10, color: '#5a6b7b', margin: '4px 0 10px', lineHeight: 1.55 }}>
              {active === 'r/videos'
                ? 'Every video uploaded through a post lands here AND on the Videos tab.'
                : 'The player lounge — posts, memes, finds and player videos. Reddit votes, YouTube uploads, X-speed chatter.'}
            </div>
            <div style={{ display: 'flex', gap: 18, fontSize: 11, color: '#1c2733' }}>
              <div>
                <div style={{ fontSize: 14 }}>{stats?.users ?? 1}</div>
                <div style={{ fontSize: 9, color: '#7b8896' }}>Blockheads</div>
              </div>
              <div>
                <div style={{ fontSize: 14 }}>{stats?.videos ?? 0}</div>
                <div style={{ fontSize: 9, color: '#7b8896' }}>Videos</div>
              </div>
              <div>
                <div style={{ fontSize: 14 }}>{stats?.community ?? 0}</div>
                <div style={{ fontSize: 9, color: '#7b8896' }}>Posts</div>
              </div>
            </div>
            <div style={{ fontSize: 9, color: '#7b8896', marginTop: 10, borderTop: '1px solid #e4eaf0', paddingTop: 8 }}>
              Created September 2026 · Est. 2006 vibes
            </div>
          </div>
        </div>
      )}

      {/* ---------- action buttons ---------- */}
      <div style={{ display: 'grid', gap: 6 }}>
        <Link className="rb-btn rb-btn-green" href="/community/new" style={{ textDecoration: 'none', display: 'block', textAlign: 'center', fontSize: 12, padding: '7px 0' }}>
          + Create Post
        </Link>
        <Link className="rb-btn" href="/community/new?video=1" style={{ textDecoration: 'none', display: 'block', textAlign: 'center', fontSize: 12, padding: '7px 0' }}>
          ▶ Post a Video
        </Link>
        <Link className="rb-btn" href="/subs/new" style={{ textDecoration: 'none', display: 'block', textAlign: 'center', fontSize: 12, padding: '7px 0' }}>
          🏳 Create your own r/
        </Link>
      </div>

      {/* ---------- r/ communities list ---------- */}
      <div className="rb-box" style={{ padding: 0 }}>
        <div className="rb-panel-head"><span>Communities</span></div>
        <div style={{ padding: 6 }}>
          <Link
            href="/community"
            className="rb-clickable"
            style={{
              display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 4,
              textDecoration: 'none', background: active === 'r/all' ? '#e3edf7' : 'transparent',
            }}
          >
            <span style={{ width: 22, height: 22, borderRadius: '50%', background: '#24425f', color: '#fff', fontSize: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", flexShrink: 0 }}>r/</span>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: 'block', fontSize: 11, color: '#1c4e7c' }}>r/all</span>
              <span style={{ display: 'block', fontSize: 9, color: '#7b8896' }}>everything from the lounge</span>
            </span>
          </Link>
          {DEFAULT_R.map((r) => (
            <Link
              key={r.r}
              href={`/community?r=${encodeURIComponent(r.r)}`}
              className="rb-clickable"
              style={{
                display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 4,
                textDecoration: 'none', background: active === r.r ? '#e3edf7' : 'transparent',
              }}
            >
              <span style={{ width: 22, height: 22, borderRadius: '50%', background: r.color, color: '#fff', fontSize: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", flexShrink: 0 }}>r/</span>
              <span style={{ flex: 1, minWidth: 0 }}>
                <span style={{ display: 'block', fontSize: 11, color: '#1c4e7c' }}>{r.label}</span>
                <span style={{ display: 'block', fontSize: 9, color: '#7b8896' }}>{r.blurb}</span>
              </span>
            </Link>
          ))}
          {subs.map((s) => (
            <Link
              key={s.id}
              href={`/community?r=${encodeURIComponent(`r/${s.slug}`)}`}
              className="rb-clickable"
              style={{
                display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 4,
                textDecoration: 'none', background: active === `r/${s.slug}` ? '#e3edf7' : 'transparent',
              }}
            >
              <SubIcon sub={s} size={22} />
              <span style={{ flex: 1, minWidth: 0 }}>
                <span style={{ display: 'block', fontSize: 11, color: '#1c4e7c' }}>r/{s.slug}</span>
                <span style={{ display: 'block', fontSize: 9, color: '#7b8896' }}>
                  {s.members} member{s.members === 1 ? '' : 's'} · {s.posts} post{s.posts === 1 ? '' : 's'}
                </span>
              </span>
              {s.joined && <span style={{ fontSize: 9, color: '#2c6e31' }}>✓</span>}
            </Link>
          ))}
          <Link href="/labs" className="rb-clickable" style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 4, textDecoration: 'none' }}>
            <span style={{ width: 22, height: 22, borderRadius: '50%', background: '#2f7bc0', color: '#fff', fontSize: 9, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", flexShrink: 0 }}>{'</>'}</span>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: 'block', fontSize: 11, color: '#1c4e7c' }}>r/retrolabs</span>
              <span style={{ display: 'block', fontSize: 9, color: '#7b8896' }}>the dev forum — tutorials + code</span>
            </span>
          </Link>
          <div style={{ display: 'flex', gap: 6, padding: '6px 4px 4px' }}>
            <Link href="/subs" className="rb-btn" style={{ flex: 1, fontSize: 10, textAlign: 'center', textDecoration: 'none', padding: '5px 0' }}>
              Browse all
            </Link>
            <Link href="/subs/new" className="rb-btn rb-btn-green" style={{ flex: 1, fontSize: 10, textAlign: 'center', textDecoration: 'none', padding: '5px 0' }}>
              + Create
            </Link>
          </div>
        </div>
      </div>

      {/* ---------- trending today ---------- */}
      {trending && trending.length > 0 && (
        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head"><span>Trending Today</span></div>
          <ol style={{ margin: 0, padding: '6px 10px 8px 26px', fontSize: 10, color: '#5a6b7b', lineHeight: 1.7 }}>
            {trending.slice(0, 4).map((t) => (
              <li key={t.href}>
                <Link href={t.href} className="rb-link" style={{ fontSize: 10 }}><FxText text={t.title.length > 42 ? `${t.title.slice(0, 42)}...` : t.title} /></Link>
                <span style={{ fontSize: 9, color: '#c2570e' }}> · {t.score}▲</span>
              </li>
            ))}
          </ol>
        </div>
      )}

      {/* ---------- rules ---------- */}
      <div className="rb-box" style={{ padding: 0 }}>
        <div className="rb-panel-head"><span>Community Rules</span></div>
        <ol style={{ margin: 0, padding: '8px 10px 10px 26px', fontSize: 10, color: '#5a6b7b', lineHeight: 1.7 }}>
          <li>Be a good blockhead — no bullying.</li>
          <li>Upload your own pictures and videos.</li>
          <li>No scam links, no pretending to be staff.</li>
          <li>Post in the right r/ community.</li>
          <li>Have fun. It&apos;s 2006 somewhere.</li>
        </ol>
      </div>
    </aside>
  )
}

/* =================================================================
   /subs — browse every player-created community
================================================================= */

export function SubsBrowseView() {
  const router = useRouter()
  const { user, setToast } = useRetro()
  const { subs, loaded, reload } = useSubs()
  const [busy, setBusy] = useState('')
  const [q, setQ] = useState('')

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase()
    if (!needle) return subs
    return subs.filter((s) => s.slug.includes(needle) || s.name.toLowerCase().includes(needle) || s.description.toLowerCase().includes(needle))
  }, [subs, q])

  async function toggleJoin(sub: SubT) {
    if (!user) {
      router.push('/login')
      return
    }
    setBusy(sub.slug)
    try {
      const res = await api<{ joined: boolean; members: number }>(`/api/subs/${sub.slug}`, { method: 'PATCH' })
      flash(setToast, res.joined ? `Welcome to r/${sub.slug}!` : `Left r/${sub.slug}.`, 2200)
      await reload()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    } finally {
      setBusy('')
    }
  }

  async function remove(sub: SubT) {
    if (!window.confirm(`Delete r/${sub.slug}? Its posts stay, but the community goes away.`)) return
    try {
      await api(`/api/subs/${sub.slug}`, { method: 'DELETE' })
      flash(setToast, `r/${sub.slug} deleted.`, 2200)
      reload()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      <div style={{ flex: 1, minWidth: 280, display: 'grid', gap: 10 }}>
        {/* header bar with search */}
        <div className="rb-box" style={{ padding: 0, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px', flexWrap: 'wrap' }}>
            <span style={{ fontSize: 14, color: '#1c2733' }}>Communities</span>
            <form
              onSubmit={(e) => e.preventDefault()}
              style={{ display: 'flex', flex: 1, minWidth: 150, maxWidth: 280, marginLeft: 'auto' }}
            >
              <input
                className="rb-input"
                type="search"
                placeholder="Search communities..."
                value={q}
                onChange={(e) => setQ(e.target.value)}
                style={{ flex: 1, minWidth: 0, borderRadius: '3px 0 0 3px', fontSize: 11 }}
                aria-label="Search communities"
              />
              <button className="rb-btn" type="submit" style={{ borderRadius: '0 3px 3px 0', borderLeft: 'none', fontSize: 11 }}>Go</button>
            </form>
            <Link className="rb-btn rb-btn-green" href="/subs/new" style={{ fontSize: 10, padding: '4px 12px', textDecoration: 'none', whiteSpace: 'nowrap' }}>
              + Create Community
            </Link>
          </div>
        </div>

        {!loaded && <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading communities...</div>}

        {loaded && shown.length === 0 && (
          <div className="rb-box" style={{ padding: '36px 20px', textAlign: 'center', color: '#5a6b7b' }}>
            <div style={{ fontSize: 15, marginBottom: 6 }}>{q ? `No communities match "${q}".` : 'No player communities yet.'}</div>
            <div style={{ fontSize: 11, marginBottom: 12 }}>Be the first to start one — memes, speedruns, your own game&apos;s fan club...</div>
            <Link className="rb-btn rb-btn-green" href="/subs/new" style={{ display: 'inline-block', textDecoration: 'none' }}>Create the first r/</Link>
          </div>
        )}

        {shown.map((s) => (
          <div key={s.id} className="rb-box rb-card" style={{ padding: 0, overflow: 'hidden' }}>
            <div
              style={{
                height: 58,
                background: s.bannerFileId ? `url(/api/files/${s.bannerFileId}) center/cover` : `linear-gradient(120deg,${s.color},#5fb35f 80%)`,
              }}
            />
            <div style={{ padding: '0 12px 12px' }}>
              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 10, marginTop: -16, marginBottom: 6 }}>
                <span style={{ background: '#fff', border: '1px solid #c3cdd7', borderRadius: '50%', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 1px 4px rgba(0,0,0,.2)' }}>
                  <SubIcon sub={s} size={32} />
                </span>
                <div style={{ flex: 1, minWidth: 0, paddingBottom: 2 }}>
                  <Link href={`/community?r=${encodeURIComponent(`r/${s.slug}`)}`} className="rb-link" style={{ fontSize: 13, display: 'block' }}>r/{s.slug}</Link>
                  {s.name !== s.slug && <span style={{ fontSize: 10, color: '#7b8896' }}>{s.name}</span>}
                </div>
                <button
                  type="button"
                  className={`rb-btn ${s.joined ? '' : 'rb-btn-green'}`}
                  style={{ fontSize: 10, padding: '4px 12px' }}
                  disabled={busy === s.slug}
                  onClick={() => toggleJoin(s)}
                >
                  {s.joined ? 'Joined ✓' : '+ Join'}
                </button>
                {user && (user.id === s.creator.id || user.role === 'admin') && (
                  <button type="button" className="rb-btn rb-btn-red" style={{ fontSize: 10, padding: '4px 12px' }} onClick={() => remove(s)}>
                    Delete
                  </button>
                )}
              </div>
              <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.5, minHeight: 16 }}>
                {s.description || 'A player-created community.'}
              </div>
              <div style={{ fontSize: 10, color: '#7b8896', marginTop: 6, display: 'flex', gap: 14, flexWrap: 'wrap' }}>
                <span>{s.members} member{s.members === 1 ? '' : 's'}</span>
                <span>{s.posts} post{s.posts === 1 ? '' : 's'}</span>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  by <Avatar user={s.creator} size={14} rounded="50%" /> <Link href={`/users/${s.creator.id}`} className="rb-link" style={{ fontSize: 10 }}>u/{s.creator.username}</Link>
                </span>
                <span>created {timeAgo(s.createdAt)}</span>
              </div>
            </div>
          </div>
        ))}
      </div>

      <CommunitySidebar active="r/all" />
    </div>
  )
}

/* =================================================================
   /subs/new — create your own r/ community
================================================================= */

const SUB_COLORS = ['#0d69ac', '#c81c14', '#2c6e31', '#5e3f9e', '#c2570e', '#a03a34', '#0f7f74', '#b02a72']

export function SubsNewView() {
  const { setToast } = useRetro()
  const router = useRouter()
  const [slug, setSlug] = useState('')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [color, setColor] = useState(SUB_COLORS[0])
  const [icon, setIcon] = useState<File | null>(null)
  const [iconPreview, setIconPreview] = useState<string | null>(null)
  const [banner, setBanner] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const iconRef = useRef<HTMLInputElement>(null)
  const bannerRef = useRef<HTMLInputElement>(null)

  // live availability for the community name ('bad' names are derived at render)
  const [slugState, setSlugState] = useState<'idle' | 'checking' | 'free' | 'taken'>('idle')
  const slugClean = slug.trim().toLowerCase()
  const slugValid = /^[a-z0-9_]{3,21}$/.test(slugClean)
  useEffect(() => {
    const s = slug.trim().toLowerCase()
    if (!s || !/^[a-z0-9_]{3,21}$/.test(s)) return // render guard below handles empty/invalid
    let cancelled = false
    const t = setTimeout(async () => {
      if (cancelled) return
      setSlugState('checking')
      try {
        const res = await api<{ sub: SubT | null }>(`/api/subs/${encodeURIComponent(s)}`)
        if (cancelled) return
        setSlugState(res.sub ? 'taken' : 'free')
      } catch {
        if (!cancelled) setSlugState('idle')
      }
    }, 420)
    return () => {
      cancelled = true
      clearTimeout(t)
    }
  }, [slug])

  async function submit(e?: React.FormEvent) {
    e?.preventDefault()
    setError('')
    const s = slug.trim().toLowerCase()
    if (!/^[a-z0-9_]{3,21}$/.test(s)) {
      setError('Community names are 3-21 characters: letters, numbers, underscore.')
      return
    }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('slug', s)
      fd.append('name', name.trim() || s)
      fd.append('description', description.trim())
      fd.append('color', color)
      if (icon) fd.append('icon', icon)
      if (banner) fd.append('banner', banner)
      await api('/api/subs', { method: 'POST', body: fd })
      flash(setToast, `r/${s} is live! You are the first member.`, 2800)
      router.push(`/community?r=${encodeURIComponent(`r/${s}`)}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create community')
      setBusy(false)
    }
  }

  const labelStyle = { fontSize: 11, color: '#24425f', display: 'block', marginBottom: 4 }

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      <form className="rb-box" style={{ flex: 1, minWidth: 280, maxWidth: 640, padding: 0 }} onSubmit={submit}>
        <div className="rb-panel-head">
          <span>Create your own r/ community</span>
          <span style={{ fontSize: 10, color: '#5a6b7b' }}>a home for your thing</span>
        </div>
        <div style={{ padding: 12, display: 'grid', gap: 12 }}>
          {error && (
            <div role="alert" style={{ background: '#fdebe9', border: '1px solid #e1231a', color: '#a81a13', fontSize: 11, padding: '7px 10px', borderRadius: 3 }}>
              {error}
            </div>
          )}

          <div>
            <label style={labelStyle} htmlFor="sub-slug">Community name * (this becomes r/NAME)</label>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ fontSize: 13, color: '#1c4e7c', fontFamily: "'Courier New', monospace" }}>r/</span>
              <input
                id="sub-slug"
                className="rb-input"
                style={{ flex: 1 }}
                value={slug}
                onChange={(e) => setSlug(e.target.value.replace(/[^A-Za-z0-9_]/g, ''))}
                maxLength={21}
                placeholder="brickmemes"
              />
            </div>
            {slugClean !== '' && !slugValid && (
              <div aria-live="polite" style={{ fontSize: 10, marginTop: 4, color: '#a81a13' }}>
                3-21 characters: letters, numbers, underscore.
              </div>
            )}
            {slugClean !== '' && slugValid && slugState !== 'idle' && (
              <div aria-live="polite" style={{ fontSize: 10, marginTop: 4, color: slugState === 'free' ? '#2c6e31' : slugState === 'checking' ? '#5a6b7b' : '#a81a13' }}>
                {slugState === 'free' ? '✓ r/' + slugClean + ' is available!'
                  : slugState === 'checking' ? 'Checking...'
                  : 'r/' + slugClean + ' is already taken.'}
              </div>
            )}
          </div>

          <div>
            <label style={labelStyle} htmlFor="sub-name">Display name (optional)</label>
            <input id="sub-name" className="rb-input" style={{ width: '100%' }} value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="Brick Memes HQ" />
          </div>

          <div>
            <label style={labelStyle} htmlFor="sub-desc">What is it about?</label>
            <textarea id="sub-desc" className="rb-textarea" style={{ width: '100%' }} rows={3} value={description} onChange={(e) => setDescription(e.target.value)} maxLength={500} placeholder="Tell people what belongs in this community..." />
          </div>

          <div>
            <label style={labelStyle}>Accent color</label>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {SUB_COLORS.map((c) => (
                <button
                  key={c}
                  type="button"
                  aria-label={`Color ${c}`}
                  onClick={() => setColor(c)}
                  className="rb-clickable"
                  style={{
                    width: 26, height: 26, borderRadius: '50%', background: c, cursor: 'pointer',
                    border: color === c ? '2px solid #1c2733' : '1px solid rgba(0,0,0,.25)',
                    outline: color === c ? '2px solid #fff' : 'none',
                  }}
                />
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', gap: 18, flexWrap: 'wrap' }}>
            <div>
              <label style={labelStyle}>Icon (optional, round)</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                {iconPreview ? (
                  <img src={iconPreview} alt="Icon preview" style={{ width: 44, height: 44, borderRadius: '50%', objectFit: 'cover', border: '1px solid #c3cdd7' }} />
                ) : (
                  <span style={{ width: 44, height: 44, borderRadius: '50%', background: color, color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>{(slug.trim() || 'r').charAt(0).toUpperCase()}</span>
                )}
                <button type="button" className="rb-btn" style={{ fontSize: 10 }} onClick={() => iconRef.current?.click()}>
                  {icon ? 'Change icon' : '+ Upload icon'}
                </button>
                <input
                  ref={iconRef}
                  type="file"
                  accept="image/*"
                  style={{ display: 'none' }}
                  onChange={(e) => {
                    const f = e.target.files?.[0] || null
                    setIcon(f)
                    setIconPreview(f ? URL.createObjectURL(f) : null)
                    e.target.value = ''
                  }}
                />
              </div>
            </div>
            <div>
              <label style={labelStyle}>Banner (optional)</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <button type="button" className="rb-btn" style={{ fontSize: 10 }} onClick={() => bannerRef.current?.click()}>
                  {banner ? 'Change banner' : '+ Upload banner'}
                </button>
                {banner && <span style={{ fontSize: 10, color: '#2c6e31' }}>{banner.name.slice(0, 24)}</span>}
                <input
                  ref={bannerRef}
                  type="file"
                  accept="image/*"
                  style={{ display: 'none' }}
                  onChange={(e) => {
                    setBanner(e.target.files?.[0] || null)
                    e.target.value = ''
                  }}
                />
              </div>
            </div>
          </div>

          <div>
            <button className="rb-btn rb-btn-green" type="submit" disabled={busy} style={{ fontSize: 13, padding: '9px 22px' }}>
              {busy ? 'Creating...' : `Create r/${slug.trim().toLowerCase() || 'community'}`}
            </button>
          </div>
        </div>
      </form>
      <CommunitySidebar active="r/all" />
    </div>
  )
}
