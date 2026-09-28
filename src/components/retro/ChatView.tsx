'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, timeAgo, flash, type RetroUser } from '@/lib/store'
import { Avatar, OnlineDot } from './Shell'

/* Chat — private Discord-flavored DMs. Open to ALL members: friends,
   people you've messaged before, and pending friend-request partners
   (that's how you nudge someone to accept!). Text, images, videos and
   audio supported. Polls lightly. */

interface ChatMsg {
  id: string
  text: string
  fileId: string | null
  fileType: string | null
  fileName: string | null
  fromMe: boolean
  createdAt: string
}

interface Conversation {
  friend: RetroUser
  pending?: boolean
  friendshipId?: string | null
  lastMessage: { text: string; fileId: string | null; fileType: string | null; fromMe: boolean; createdAt: string } | null
  unread: number
}

export function mediaRender(fileId: string | null, fileType: string | null, name?: string | null) {
  if (!fileId || !fileType) return null
  const url = `/api/files/${fileId}`
  if (fileType === 'image') {
    return <img src={url} alt={name || 'picture'} className="rb-media rb-img" />
  }
  if (fileType === 'video') {
    return <video src={url} controls preload="metadata" className="rb-media" style={{ maxHeight: 300 }} />
  }
  if (fileType === 'audio') {
    return (
      <div className="rb-audio-row">
        <audio src={url} controls preload="metadata" />
      </div>
    )
  }
  return null
}

const EMOJIS = [':)', ':D', ':P', ';)', '<3', '^_^', ':o', 'XD', ':(', 'o7']

/* ================= Chat conversation list (/chat) ================= */

/* NUDGE — a tiny shoulder-tap on a pending friend request. Sits right
   inside the conversation row; the row is a Link, so the click must
   preventDefault to stay put. Rate-limited server-side (1 / 10 min). */
function NudgeChip({ friendshipId }: { friendshipId?: string | null }) {
  const { setToast } = useRetro()
  const [state, setState] = useState<'idle' | 'busy' | 'done'>('idle')

  // invisible when there is no pending row to nudge
  if (!friendshipId) {
    return (
      <span style={{ fontSize: 8, color: '#6b5413', background: '#fdf6e4', border: '1px solid #e0d3a6', borderRadius: 3, padding: '1px 5px', flexShrink: 0 }}>
        request pending
      </span>
    )
  }

  if (state === 'done') {
    return (
      <span style={{ fontSize: 8, color: '#2c6e31', background: '#eaf6ea', border: '1px solid #bcdcbc', borderRadius: 3, padding: '1px 5px', flexShrink: 0 }}>
        nudged ✓
      </span>
    )
  }

  async function nudge(e: React.MouseEvent) {
    e.preventDefault()
    e.stopPropagation()
    if (state !== 'idle') return
    setState('busy')
    try {
      await api(`/api/friends/${friendshipId}`, { method: 'POST', body: JSON.stringify({ action: 'nudge' }) })
      setState('done')
      flash(setToast, 'Nudge sent — it will pop up in their bell!', 2400)
    } catch (err) {
      flash(setToast, err instanceof Error ? err.message : 'Failed to nudge', 2600)
      setState('idle')
    }
  }

  return (
    <button
      type="button"
      onClick={nudge}
      disabled={state === 'busy'}
      title="Remind them about your pending friend request"
      style={{
        fontSize: 8, color: '#fff', background: '#0d69ac', border: '1px solid #084a7c',
        borderRadius: 3, padding: '1px 6px', flexShrink: 0, cursor: 'pointer',
        fontFamily: 'inherit', fontWeight: 700,
      }}
    >
      {state === 'busy' ? '...' : 'Nudge'}
    </button>
  )
}

export function ChatListView() {
  const { user, setUnreadChats } = useRetro()
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    try {
      const res = await api<{ conversations: Conversation[] }>('/api/chat')
      setConversations(res.conversations)
      const total = res.conversations.reduce((s, c) => s + c.unread, 0)
      setUnreadChats(total)
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [setUnreadChats])

  useEffect(() => {
    load()
    const t = setInterval(load, 8000)
    return () => clearInterval(t)
  }, [load])

  useEffect(() => {
    document.title = 'Chat - RetroBlox'
  }, [])

  if (!user) return null

  return (
    <div className="rb-box">
      <div className="rb-panel-head">
        <span>Chat — Private Messages</span>
        <span style={{ fontSize: 10, color: '#5a6b7b' }}>like Discord, but 2006</span>
      </div>
      <div style={{ padding: 8 }}>
        {loading && <div style={{ padding: 24, textAlign: 'center', color: '#5a6b7b', fontSize: 11 }}>Loading chats...</div>}
        {!loading && conversations.length === 0 && (
          <div style={{ padding: '30px 16px', textAlign: 'center', color: '#5a6b7b' }}>
            <div style={{ fontSize: 14, marginBottom: 6 }}>No conversations yet</div>
            <div style={{ fontSize: 11, marginBottom: 12, lineHeight: 1.6 }}>
              You can message ANY player on RetroBlox —<br />
              even before they accept your friend request.
            </div>
            <div style={{ display: 'flex', gap: 8, justifyContent: 'center', flexWrap: 'wrap' }}>
              <Link className="rb-btn rb-btn-green" href="/people" style={{ textDecoration: 'none', display: 'inline-block' }}>
                Browse People
              </Link>
              <Link className="rb-btn" href="/friends" style={{ textDecoration: 'none', display: 'inline-block' }}>
                Go to Friends
              </Link>
            </div>
          </div>
        )}
        {conversations.map((c) => (
          <Link
            key={c.friend.id}
            href={`/chat/${c.friend.id}`}
            className="rb-chat-friend"
            style={{ textDecoration: 'none' }}
          >
            <span style={{ position: 'relative', display: 'inline-block' }}>
              <Avatar user={c.friend} size={38} rounded="50%" />
              <span style={{ position: 'absolute', right: -1, bottom: 0 }}>
                <OnlineDot online={c.friend.online} />
              </span>
            </span>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 12, color: '#1c4e7c', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.friend.username}</span>
                {c.pending && <NudgeChip friendshipId={c.friendshipId} />}
              </span>
              <span
                style={{
                  display: 'block',
                  fontSize: 10,
                  color: '#7b8896',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {c.lastMessage
                  ? `${c.lastMessage.fromMe ? 'You: ' : ''}${
                      c.lastMessage.text ||
                      (c.lastMessage.fileType === 'image'
                        ? 'sent a picture'
                        : c.lastMessage.fileType === 'video'
                          ? 'sent a video'
                          : c.lastMessage.fileType === 'audio'
                            ? 'sent audio'
                            : 'sent a file')
                    } · ${timeAgo(c.lastMessage.createdAt)}`
                  : 'Say hi!'}
              </span>
            </span>
            {c.unread > 0 && <span className="rb-badge">{c.unread}</span>}
          </Link>
        ))}
      </div>
    </div>
  )
}

/* ================= Chat thread (/chat/[userId]) ================= */

export function ChatThreadView({ userId }: { userId: string }) {
  const { user, setUnreadChats, setToast } = useRetro()
  const router = useRouter()
  const [friend, setFriend] = useState<RetroUser | null>(null)
  const [contacts, setContacts] = useState<Conversation[]>([])
  const [messages, setMessages] = useState<ChatMsg[]>([])
  const [text, setText] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [emojiOpen, setEmojiOpen] = useState(false)
  const msgsRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const lastCountRef = useRef(-1)

  /* open the file picker with a specific accept filter (images vs media) */
  function pickFile(accept: string) {
    if (fileRef.current) {
      fileRef.current.accept = accept
      fileRef.current.click()
    }
  }

  const load = useCallback(async () => {
    try {
      const [thread, convs] = await Promise.all([
        api<{ friend: RetroUser; messages: ChatMsg[] }>(`/api/chat/${userId}`),
        api<{ conversations: Conversation[] }>('/api/chat'),
      ])
      setFriend(thread.friend)
      setMessages(thread.messages)
      setContacts(convs.conversations)
      setUnreadChats(0)
      if (thread.messages.length !== lastCountRef.current) {
        lastCountRef.current = thread.messages.length
        requestAnimationFrame(() => {
          const el = msgsRef.current
          if (el) el.scrollTop = el.scrollHeight
        })
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load chat')
    }
  }, [userId, setUnreadChats])

  useEffect(() => {
    load()
    const t = setInterval(load, 3500)
    return () => clearInterval(t)
  }, [load])

  useEffect(() => {
    if (friend) document.title = `${friend.username} - Chat - RetroBlox`
  }, [friend])

  async function send() {
    if (busy || (!text.trim() && !file)) return
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('text', text.trim())
      if (file) fd.append('file', file)
      const res = await api<{ message: ChatMsg }>(`/api/chat/${userId}`, { method: 'POST', body: fd })
      setMessages((ms) => [...ms, res.message])
      setText('')
      setFile(null)
      setEmojiOpen(false)
      requestAnimationFrame(() => {
        const el = msgsRef.current
        if (el) el.scrollTop = el.scrollHeight
      })
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to send', 2400)
    } finally {
      setBusy(false)
    }
  }

  if (!user) return null

  if (error) {
    return (
      <div className="rb-box" style={{ padding: 36, textAlign: 'center', color: '#a81a13' }}>
        {error}
        <div style={{ marginTop: 12 }}>
          <button className="rb-btn" onClick={() => router.push(friend ? `/users/${friend.id}` : '/')}>
            Back
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="rb-chat-wrap">
      {/* conversations sidebar — switch chats like Discord */}
      <div className="rb-box rb-chat-side">
        <div className="rb-panel-head"><span>Conversations</span></div>
        <div style={{ maxHeight: 460, overflowY: 'auto' }}>
          {contacts.length === 0 && (
            <div style={{ padding: 12, fontSize: 10, color: '#7b8896' }}>
              Message anyone from the People page!
            </div>
          )}
          {contacts.map((c) => (
            <Link
              key={c.friend.id}
              href={`/chat/${c.friend.id}`}
              className={`rb-chat-friend${c.friend.id === userId ? ' rb-active' : ''}`}
              style={{ textDecoration: 'none' }}
            >
              <span style={{ position: 'relative', display: 'inline-block' }}>
                <Avatar user={c.friend} size={30} rounded="50%" />
                <span style={{ position: 'absolute', right: -1, bottom: 0 }}>
                  <OnlineDot online={c.friend.online} />
                </span>
              </span>
              <span style={{ flex: 1, minWidth: 0, fontSize: 11, color: '#1c4e7c', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {c.friend.username}
                {c.pending ? ' ·' : ''}
              </span>
              {c.unread > 0 && c.friend.id !== userId && <span className="rb-badge">{c.unread}</span>}
            </Link>
          ))}
        </div>
      </div>

      {/* conversation */}
      <div className="rb-box rb-chat-main">
        <div className="rb-panel-head">
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
            {friend ? (
              <>
                <Avatar user={friend} size={24} rounded="50%" />
                <Link href={`/users/${friend.id}`} className="rb-link" style={{ fontSize: 12 }}>
                  {friend.username}
                </Link>
                <OnlineDot online={friend.online} />
                <span style={{ fontSize: 10, color: '#5a6b7b' }}>{friend.online ? 'Online' : 'Offline'}</span>
              </>
            ) : (
              'Loading...'
            )}
          </span>
          <span style={{ fontSize: 10, color: '#5a6b7b' }}>Private Chat</span>
        </div>

        <div className="rb-chat-msgs" ref={msgsRef}>
          {messages.length === 0 && (
            <div style={{ textAlign: 'center', color: '#7b8896', fontSize: 11, margin: 'auto' }}>
              This is the beginning of your conversation with{' '}
              <span style={{ color: '#24425f' }}>{friend?.username || 'them'}</span>. Say hi!
            </div>
          )}
          {messages.map((m) => (
            <div key={m.id} className={`rb-chat-row${m.fromMe ? ' rb-mine' : ''}`}>
              {!m.fromMe && friend && <Avatar user={friend} size={30} rounded="50%" />}
              {m.fromMe && <Avatar user={user as RetroUser} size={30} rounded="50%" />}
              <div className="rb-chat-bubble">
                <div className="rb-chat-meta">
                  {m.fromMe ? 'You' : friend?.username || ''} · {timeAgo(m.createdAt)}
                </div>
                {m.text && <div className="rb-chat-text">{m.text}</div>}
                {mediaRender(m.fileId, m.fileType, m.fileName)}
              </div>
            </div>
          ))}
        </div>

        <div className="rb-chat-inputbar">
          {emojiOpen && (
            <div className="rb-chat-emojirow">
              {EMOJIS.map((e) => (
                <button key={e} type="button" onClick={() => setText((t) => `${t}${e} `)} aria-label={`Insert ${e}`}>
                  {e}
                </button>
              ))}
            </div>
          )}
          {file && (
            <div className="rb-chat-attach-chip">
              <span>
                {file.name.length > 30 ? `${file.name.slice(0, 30)}...` : file.name} ({Math.ceil(file.size / 1024)} KB)
              </span>
              <button
                type="button"
                className="rb-link"
                style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }}
                onClick={() => setFile(null)}
              >
                remove
              </button>
            </div>
          )}
          <div className="rb-chat-inputrow">
            <button
              type="button"
              className="rb-btn"
              style={{ fontSize: 10, padding: '5px 8px' }}
              title="Send a picture"
              onClick={() => pickFile('image/*')}
            >
              + Image
            </button>
            <button
              type="button"
              className="rb-btn"
              style={{ fontSize: 10, padding: '5px 8px' }}
              title="Attach a video or audio clip"
              onClick={() => pickFile('video/*,audio/*')}
            >
              + Media
            </button>
            <button
              type="button"
              className="rb-btn"
              style={{ fontSize: 10, padding: '5px 8px' }}
              title="Emotes"
              onClick={() => setEmojiOpen((o) => !o)}
            >
              :)
            </button>
            <input
              ref={fileRef}
              type="file"
              accept="image/*,video/*,audio/*"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) setFile(f)
                e.target.value = ''
              }}
            />
            <input
              className="rb-input"
              type="text"
              placeholder={`Message ${friend?.username || ''}...`}
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && send()}
              style={{ flex: 1, minWidth: 0 }}
              aria-label="Chat message"
              maxLength={2000}
            />
            <button className="rb-btn rb-btn-green" onClick={send} disabled={busy || (!text.trim() && !file)} style={{ fontSize: 11 }}>
              Send
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
