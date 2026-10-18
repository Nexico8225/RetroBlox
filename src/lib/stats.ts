// Daily stats helpers for game analytics (stored as JSON on Game.statsJson)

export type DayStat = { v: number; d: number } // views, downloads

export function bumpStats(statsJson: string, key: 'v' | 'd'): string {
  const day = new Date().toISOString().slice(0, 10)
  let s: Record<string, DayStat> = {}
  try {
    s = JSON.parse(statsJson || '{}')
  } catch { /* corrupt json -> start fresh */ }
  const cur = s[day] || { v: 0, d: 0 }
  cur[key] = (cur[key] || 0) + 1
  s[day] = cur
  return JSON.stringify(s)
}

/** Returns an array of the last N days (oldest first) with {day, label, views, downloads}. */
export function parseStatsSeries(statsJson: string, days = 14): { day: string; label: string; views: number; downloads: number }[] {
  let s: Record<string, DayStat> = {}
  try {
    s = JSON.parse(statsJson || '{}')
  } catch { /* ignore */ }
  const out: { day: string; label: string; views: number; downloads: number }[] = []
  const now = new Date()
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 86400000)
    const key = d.toISOString().slice(0, 10)
    const st = s[key] || { v: 0, d: 0 }
    out.push({
      day: key,
      label: `${d.getMonth() + 1}/${d.getDate()}`,
      views: st.v || 0,
      downloads: st.d || 0,
    })
  }
  return out
}

export function parseIds(json: string): string[] {
  try {
    const v = JSON.parse(json || '[]')
    return Array.isArray(v) ? v.map(String) : []
  } catch {
    return []
  }
}
