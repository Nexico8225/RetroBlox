// Reproduce the counter failure against local dev
const BASE = 'http://localhost:3000'
const api = async (path, { method = 'GET', token, body, form } = {}) => {
  const headers = {}
  if (token) headers.Authorization = `Bearer ${token}`
  if (!form) headers['Content-Type'] = 'application/json'
  const res = await fetch(BASE + path, { method, headers, body: form ? form : body ? JSON.stringify(body) : undefined })
  const data = await res.json().catch(() => ({}))
  return { status: res.status, data }
}
const stamp = () => 'dbg' + Math.random().toString(36).slice(2, 8)
async function signup(username) {
  const form = new FormData()
  form.append('username', username)
  form.append('password', 'test12345')
  const r = await api('/api/auth/signup', { method: 'POST', form })
  return { id: r.data.user.id, username, token: r.data.token }
}
async function main() {
  const s = stamp()
  const a = await signup(`d_${s}_a`)
  const b = await signup(`d_${s}_b`)
  // a trades nothing but tix to b — empty items both sides, tixFrom only (a has 0 tix but counter validation happens before? no, create needs funds only for tix>0 — tix 0 + robux 0 + no items = rejected). Give items? publish is heavy; use robux-only trade
  // actually: a offers robux-only trade (robux 3) — a has no robux → rejected? funds check exists. b has none either. So: just check the counter validation path with a pure robux trade after seeding via sqlite? skip sqlite, test counter validation on a trade of robux only:
  const r = await api('/api/trades', { method: 'POST', token: a.token, body: { toUserId: b.id, giveItemIds: [], takeItemIds: [], tix: 0, robux: 0 } })
  console.log('create empty:', r.status, JSON.stringify(r.data))
  const r2 = await api('/api/trades', { method: 'POST', token: a.token, body: { toUserId: b.id, giveItemIds: [], takeItemIds: [], tix: 0, robux: 1 } })
  console.log('create robux-only (a has 0 robux):', r2.status, JSON.stringify(r2.data))
  // the real counter scenario: b counters a's trade with robuxTo — needs an actual trade; use items via catalog publish as tshirt
  const PNG = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de0000000c4944415408d763f8cfc00000030101', 'hex') + Buffer.from('00', 'hex')
  const pub = async (user, name) => {
    const form = new FormData()
    form.append('name', name)
    form.append('type', 'tshirt')
    form.append('price', '0')
    form.append('image', new File([PNG], 't.png', { type: 'image/png' }))
    const rr = await api('/api/catalog', { method: 'POST', token: user.token, form })
    return rr.data.item
  }
  const itemA = await pub(a, `dbgA_${s}`)
  const itemB = await pub(b, `dbgB_${s}`)
  const t = await api('/api/trades', { method: 'POST', token: a.token, body: { toUserId: b.id, giveItemIds: [itemA.id], takeItemIds: [itemB.id], tix: 0, robux: 0 } })
  console.log('create item trade:', t.status, JSON.stringify(t.data))
  const tradeId = t.data.tradeId
  const c = await api(`/api/trades/${tradeId}`, { method: 'POST', token: b.token, body: { action: 'counter', giveItemIds: [itemA.id], takeItemIds: [itemB.id], tixFrom: 100, tixTo: 200, robuxFrom: 3, robuxTo: 4 } })
  console.log('counter with robux:', c.status, JSON.stringify(c.data))
  const room = await api(`/api/trades/${tradeId}`, { token: a.token })
  console.log('terms after counter:', JSON.stringify({ tixFrom: room.data.trade?.tixFrom, tixTo: room.data.trade?.tixTo, robuxFrom: room.data.trade?.robuxFrom, robuxTo: room.data.trade?.robuxTo }))
}
main().catch((e) => { console.error(e); process.exit(1) })
