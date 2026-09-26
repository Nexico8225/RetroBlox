'use client'

import { create } from 'zustand'
import { saveSessionToken, clearSessionToken, getStoredToken } from '@/lib/session'

export interface RetroUser {
  id: string
  username: string
  avatarUrl: string | null
  role: string
  gender: string | null
  bio: string
  createdAt: string
  lastSeen: string
  online: boolean
  rbxBalance?: number
}

interface RetroState {
  booted: boolean
  user: RetroUser | null
  pendingRequests: number
  unreadChats: number
  toast: string | null
  setToast: (t: string | null) => void
  setUser: (u: RetroUser | null) => void
  setPendingRequests: (n: number) => void
  setUnreadChats: (n: number) => void
  setBooted: (b: boolean) => void
}

export const useRetro = create<RetroState>((set) => ({
  booted: false,
  user: null,
  pendingRequests: 0,
  unreadChats: 0,
  toast: null,
  setToast: (t) => set({ toast: t }),
  setUser: (u) => set({ user: u }),
  setPendingRequests: (n) => set({ pendingRequests: n }),
  setUnreadChats: (n) => set({ unreadChats: n }),
  setBooted: (b) => set({ booted: b }),
}))

/* Flash a retro toast that auto-dismisses */
export function flash(setToast: (t: string | null) => void, msg: string, ms = 2600) {
  setToast(msg)
  setTimeout(() => setToast(null), ms)
}

/** Re-pull the wallet balance into the header chip (after buys, grants, payments). */
export async function refreshBalance() {
  try {
    const res = await api<{ user: { rbxBalance?: number } | null }>('/api/me')
    const u = useRetro.getState().user
    if (u && res.user) useRetro.getState().setUser({ ...u, rbxBalance: res.user.rbxBalance ?? 0 })
  } catch { /* ignore */ }
}

// ---- client-side helpers ----

/* ------------------------------------------------------------------
   Auth token belt-and-braces — now powered by lib/session.ts which
   keeps the token in localStorage AND a JS cookie AND benefits from
   the httpOnly server cookie, plus Storage Access API support for
   the cross-site preview iframe. login/signup also return the raw
   session token and api() sends it as an Authorization header on
   every call — the fallback that ALWAYS works.
------------------------------------------------------------------ */

export function saveAuthToken(token?: string | null) {
  saveSessionToken(token)
}

export function clearAuthToken() {
  clearSessionToken()
}

export function getAuthToken(): string {
  return getStoredToken()
}

export async function api<T>(url: string, options?: RequestInit): Promise<T> {
  const token = getAuthToken()
  const baseHeaders: Record<string, string> = { ...(options?.headers as Record<string, string>) }
  if (!(options?.body instanceof FormData)) baseHeaders['Content-Type'] = 'application/json'
  if (token) baseHeaders['Authorization'] = `Bearer ${token}`
  const res = await fetch(url, { ...options, headers: baseHeaders })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((data as { error?: string }).error || 'Something went wrong')
  return data as T
}

export function timeAgo(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  const s = Math.floor((Date.now() - d.getTime()) / 1000)
  if (s < 60) return 'just now'
  const m = Math.floor(s / 60)
  if (m < 60) return `${m} minute${m > 1 ? 's' : ''} ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h} hour${h > 1 ? 's' : ''} ago`
  const days = Math.floor(h / 24)
  if (days < 30) return `${days} day${days > 1 ? 's' : ''} ago`
  const months = Math.floor(days / 30)
  if (months < 12) return `${months} month${months > 1 ? 's' : ''} ago`
  return `${Math.floor(months / 12)} year${months >= 24 ? 's' : ''} ago`
}

export function fmtDate(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return d.toLocaleDateString('en-US', { month: 'numeric', day: 'numeric', year: 'numeric' })
}

export function fmtCount(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M+`
  if (n >= 10_000) return `${(n / 1000).toFixed(1)}K+`
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`
  return String(n)
}

export const GENRES = [
  'All Genres',
  'Adventure',
  'Building',
  'Fighting',
  'FPS',
  'Horror',
  'Obby',
  'Puzzle',
  'RPG',
  'Racing',
  'Sci-Fi',
  'Simulation',
  'Sports',
  'Town & City',
  'Tycoon',
  'Western',
]

export const SUBGENRE_IDEAS = [
  'Arena Fighter', 'Shooter', 'Building', 'Parkour', 'Sandbox', 'Sword Duel',
  'Incremental Simulator', 'Survival', 'Racing', 'Magic Simulator', 'Roleplay',
  'Tower Defense', 'Trading', 'Obstacle Course', 'Zombie Apocalypse',
]

// client-safe retro blockhead avatar (matches seeded style)
function hashSeed(seed: string): number {
  let h = 0
  for (let i = 0; i < seed.length; i++) h = ((h << 5) - h + seed.charCodeAt(i)) | 0
  return Math.abs(h)
}

/* Google-style letter avatar: if someone has no photo, show the first
   letter of their name on a stable color picked from their username. */
const LETTER_COLORS = ['#e1231a', '#0d69ac', '#4c9e34', '#8e44ad', '#d35400', '#16a085', '#c2185b', '#2c3e50', '#b8860b', '#5d4037']

export function letterAvatar(name: string): string {
  const clean = (name || '?').trim()
  const letter = (clean.replace(/[^A-Za-z0-9]/g, '').charAt(0) || clean.charAt(0) || '?').toUpperCase()
  const color = LETTER_COLORS[hashSeed(clean.toLowerCase()) % LETTER_COLORS.length]
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 100 100"><rect width="100" height="100" fill="${color}"/><text x="50" y="50" text-anchor="middle" dominant-baseline="central" font-family="Verdana, Arial, sans-serif" font-size="52" fill="#ffffff">${letter}</text></svg>`
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`
}
const SKIN = ['#F6C89F', '#FFD34E', '#F0B27A', '#EAB98B', '#FFCC66', '#F5CBA7']
const SHIRT = ['#1F7AB8', '#2ECC71', '#C0392B', '#8E44AD', '#16A085', '#D35400', '#2C3E50', '#C2185B']
const PANTS = ['#2C6E31', '#34495E', '#5D4037', '#4A4A4A', '#1A5276', '#6E2C00']
const pick = <T,>(arr: T[], h: number, salt: number): T => arr[(h + salt * 7919) % arr.length]

export function clientAvatar(seed: string): string {
  const h = hashSeed(seed)
  const skin = pick(SKIN, h, 1)
  const shirt = pick(SHIRT, h, 2)
  const pants = pick(PANTS, h, 3)
  const bgA = pick(['#BFE8FF', '#D8F0D8', '#FDEBD0', '#E8DAEF', '#D6EAF8'], h, 4)
  const bgB = pick(['#7FC4E8', '#A9DFBF', '#F5CBA7', '#D2B4DE', '#85C1E9'], h, 5)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 100 100"><defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${bgA}"/><stop offset="1" stop-color="${bgB}"/></linearGradient></defs><rect width="100" height="100" fill="url(#bg)"/><rect x="0" y="82" width="100" height="18" fill="#4E9A4E"/><rect x="0" y="82" width="100" height="3" fill="#5FB35F"/><rect x="38" y="62" width="10" height="24" fill="${pants}" stroke="#00000033"/><rect x="52" y="62" width="10" height="24" fill="${pants}" stroke="#00000033"/><rect x="34" y="40" width="32" height="24" fill="${shirt}" stroke="#00000033"/><rect x="24" y="40" width="9" height="24" fill="${skin}" stroke="#00000033"/><rect x="67" y="40" width="9" height="24" fill="${skin}" stroke="#00000033"/><rect x="35" y="12" width="30" height="28" fill="${skin}" stroke="#00000044"/><circle cx="44" cy="25" r="2.6" fill="#1a1a1a"/><circle cx="56" cy="25" r="2.6" fill="#1a1a1a"/><path d="M 42 31 Q 50 38 58 31" stroke="#1a1a1a" stroke-width="2.2" fill="none" stroke-linecap="round"/></svg>`
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`
}
