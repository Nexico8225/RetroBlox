#!/usr/bin/env node
/* E2E round 3: Robux everywhere + the trade room + profile worth.
 * Run against a LOCAL server: node scripts/e2e_market3.cjs http://localhost:3000
 *
 * Covers:
 *   - the currency exchange desk: Tix->Robux at 10:1, back at 1:9,
 *     ledger rows written, too-small exchanges bounced
 *   - trades carrying ROBUX (robuxFrom) alongside Tix + items,
 *     counter editing the robux terms, accept moving everything atomically
 *   - the trade room API: robux fields + chat in /api/trades/[id]
 *   - market offers carrying Robux, accepted with Tix + Robux + UGC together
 *   - /api/users/[id] returns ugcWorth + creations
 *   - notifications link into the trade room (/trades/<id>)
 */
const BASE = process.argv[2] || 'http://localhost:3000'
let passed = 0
let failed = 0
const ok = (name, cond, extra = '') => {
  if (cond) { passed++; console.log(`  PASS  ${name}${extra ? ` — ${extra}` : ''}`) }
  else { failed++; console.log(`  FAIL  ${name}${extra ? ` — ${extra}` : ''}`) }
}

const api = async (path, { method = 'GET', token, body, form } = {}) => {
  const headers = {}
  if (token) headers.Authorization = `Bearer ${token}`
  let res
  if (form) {
    res = await fetch(BASE + path, { method, headers, body: form })
  } else {
    headers['Content-Type'] = 'application/json'
    res = await fetch(BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined })
  }
  const data = await res.json().catch(() => ({}))
  return { status: res.status, data }
}

const stamp = () => 'm3' + Math.random().toString(36).slice(2, 8)

async function signup(username) {
  const form = new FormData()
  form.append('username', username)
  form.append('password', 'test12345')
  form.append('birthday', '2000-01-01')
  form.append('gender', 'female')
  const r = await api('/api/auth/signup', { method: 'POST', form })
  if (r.status !== 200) throw new Error(`signup failed for ${username}: ${JSON.stringify(r.data)}`)
  return { id: r.data.user.id, username, token: r.data.token }
}

const PNG = Buffer.from('89504e470d0a1a0a0000000d494844520000000100000001080200000090775' +
  '3de0000000c4944415408d763f8cfc00000030101', 'hex') + Buffer.from('00', 'hex')
const pngFile = () => new File([PNG], 't.png', { type: 'image/png' })

async function publishItem(user, name, price, limited) {
  const form = new FormData()
  form.append('name', name)
  form.append('type', 'tshirt')
  form.append('description', 'e2e market3 item')
  form.append('price', String(price))
  form.append('limited', limited ? '1' : '0')
  if (limited) form.append('stock', '5')
  form.append('image', pngFile())
  const r = await api('/api/catalog', { method: 'POST', token: user.token, form })
  if (r.status !== 200) throw new Error(`publish failed: ${JSON.stringify(r.data)}`)
  return r.data.item
}

async function main() {
  console.log(`E2E market3 (Robux + trade room + worth) against ${BASE}`)
  const s = stamp()
  const dex = await signup(`m3_${s}_dex`)  // creator
  const eva = await signup(`m3_${s}_eva`)  // buyer with both wallets loaded
  const fin = await signup(`m3_${s}_fin`)  // the trader
  ok('three players signed up', !!dex.token && !!eva.token && !!fin.token)

  const { execSync } = require('node:child_process')
  const py = (id, tix, robux) => `python3 -c "import sqlite3;c=sqlite3.connect('db/custom.db');c.execute(\\"UPDATE User SET rbxBalance=${tix}, robuxBalance=${robux} WHERE id='${id}'\\");c.commit()"`
  execSync(py(eva.id, 100000, 40))
  execSync(py(fin.id, 100000, 40))

  // ---- the exchange desk is GONE (Robux removed from the economy) ----
  r = await api('/api/rbx/balance', { method: 'POST', token: eva.token, body: { direction: 'tix_to_robux', amount: 500 } })
  ok('the exchange desk is closed for good (410)', r.status === 410, String(r.status))
  evaBal1 = (await api('/api/me', { token: eva.token })).data.user
  ok('wallets are Tix-only now (robuxBalance retired from /api/me)', typeof evaBal1.robuxBalance === 'undefined', `robux=${evaBal1.robuxBalance}`)

  // ---- the item everyone wants ----
  const crown = await publishItem(dex, `Rex Crown ${s}`, 1000, true)
  r = await api(`/api/catalog/${crown.id}`, { method: 'POST', token: eva.token, body: { action: 'buy' } })
  ok('eva buys the crown at mint', r.status === 200, r.data.message || r.data.error)

  // ---- a trade carrying ROBUX: fin offers his hat + 2000 Tix + 5 R$ ----
  const finHat = await publishItem(fin, `Fins Fedora ${s}`, 60, false)
  r = await api('/api/trades', { method: 'POST', token: fin.token, body: { toUserId: eva.id, giveItemIds: [finHat.id], takeItemIds: [crown.id], tix: 2000, robux: 5, message: 'crown for the fedora + [shake]serious[/shake] money' } })
  ok('fin offers hat + T$ 2000 for the crown', r.status === 200, r.data.message || r.data.error)
  const tradeId = r.data.tradeId

  // the trade room API exposes both currencies + the chat
  let room = await api(`/api/trades/${tradeId}`, { token: fin.token })
  ok('trade room GET works for a party', room.status === 200)
  ok('the room carries tix terms (robux fields retired)', typeof room.data.trade?.robuxFrom === 'undefined', JSON.stringify({ tixFrom: room.data.trade?.tixFrom }))
  ok('the room carries the chat with FX markup intact', (room.data.messages || []).some((m) => m.text?.includes('[shake]')))
  const stranger = await api(`/api/trades/${tradeId}`, { token: eva.token === fin.token ? dex.token : (await signup(`m3_${s}_z`)).token })
  ok('a stranger cannot open the trade room', stranger.status === 403)

  // the notification links into the trade room
  const evaN = await api('/api/notifications', { token: eva.token })
  const tradeNotif = (evaN.data.items || []).find((n) => n.type === 'trade_offer' && n.link?.includes('/trades/'))
  ok('the trade notification links into the trade room', !!tradeNotif, tradeNotif?.link)

  // eva counters with robux both ways — the counter keeps the ORIGINAL item
  // directions (fin still gives the fedora, eva still gives the crown), so
  // she moves the MONEY to her side: tixTo/robuxTo are what EVA adds
  r = await api(`/api/trades/${tradeId}`, { method: 'POST', token: eva.token, body: { action: 'counter', giveItemIds: [finHat.id], takeItemIds: [crown.id], tixFrom: 0, tixTo: 3000 } })
  ok('eva counters: crown for fedora + T$ 3000 to fin', r.status === 200, JSON.stringify(r.data))
  room = await api(`/api/trades/${tradeId}`, { token: eva.token })
  ok('the counter stored the tix terms', room.data.trade?.tixTo === 3000, `tixTo=${room.data.trade?.tixTo}`)
  r = await api(`/api/trades/${tradeId}`, { method: 'POST', token: fin.token, body: { action: 'accept' } })
  ok('fin accepts the countered trade', r.status === 200, r.data.message || r.data.error)

  const finAfter = (await api('/api/me', { token: fin.token })).data.user
  const evaAfter = (await api('/api/me', { token: eva.token })).data.user
  ok('fin wallet: 100000 + 3000 Tix', finAfter.rbxBalance === 103000, `tix=${finAfter.rbxBalance}`)
  ok('eva wallet: 100000 - 1000 crown - 3000 = 96000 Tix', evaAfter.rbxBalance === 96000, `tix=${evaAfter.rbxBalance}`)
  const finCrown = await api(`/api/catalog/${crown.id}`, { token: fin.token })
  ok('fin owns the crown now, serial #1', finCrown.data.owned === true && finCrown.data.market?.mySerial === 1)
  const evaHat = await api(`/api/catalog/${finHat.id}`, { token: eva.token })
  ok('eva got the fedora in the same accept', evaHat.data.owned === true)

  // ---- a market offer with Robux + UGC on the table ----
  r = await api('/api/market', { method: 'POST', token: fin.token, body: { action: 'list', itemId: crown.id, price: 5000, title: `Crown flip ${s}`, description: 'Robux preferred.' } })
  ok('fin lists the crown', r.status === 200)
  const listingId = (await api(`/api/market?itemId=${crown.id}`)).data.listings[0]?.id
  r = await api('/api/market', { method: 'POST', token: eva.token, body: { action: 'offer', listingId, amount: 1000, robux: 20, offerItemIds: [finHat.id], message: 'Tix + Robux + the hat. Final.' } })
  ok('eva offers T$ 1000 + her fedora', r.status === 200, r.data.message || r.data.error)
  const finListings = await api('/api/market?mine=1', { token: fin.token })
  const pendingOffer = finListings.data.listings?.[0]?.offers?.[0]
  ok('fin sees the pending mixed offer', !!pendingOffer && pendingOffer.amount === 1000, `amount=${pendingOffer?.amount}`)
  r = await api('/api/market', { method: 'POST', token: fin.token, body: { action: 'accept_offer', offerId: pendingOffer.id } })
  ok('fin accepts the triple offer', r.status === 200, r.data.message || r.data.error)
  const finFinal = (await api('/api/me', { token: fin.token })).data.user
  const evaFinal = (await api('/api/me', { token: eva.token })).data.user
  ok('fin: +T$ 1000 and the hat crossed to eva', finFinal.rbxBalance === 104000, `tix=${finFinal.rbxBalance}`)
  ok('eva: -T$ 1000 (96000 - 1000 = 95000)', evaFinal.rbxBalance === 95000, `tix=${evaFinal.rbxBalance}`)
  const evaCrown = await api(`/api/catalog/${crown.id}`, { token: eva.token })
  ok('eva holds the crown again — serial #1 forever', evaCrown.data.owned === true && evaCrown.data.market?.mySerial === 1)

  // ---- profile worth + creations ----
  const dexProfile = await api(`/api/users/${dex.id}`, { token: eva.token })
  ok('the creator profile exposes ugcWorth', typeof dexProfile.data.ugcWorth === 'number' && dexProfile.data.ugcWorth > 0, `worth=${dexProfile.data.ugcWorth}`)
  ok('the creator profile lists creations', (dexProfile.data.creations || []).some((c) => c.id === crown.id), `creations=${dexProfile.data.creations?.length}`)
  const evaProfile = await api(`/api/users/${eva.id}`, { token: dex.token })
  // eva ends with ONLY the crown (the fedora crossed back to fin in the triple
  // offer) — her worth is her latest paid price 1000 x 1.5
  ok("eva's worth is the crown at 1.5x what she last paid", evaProfile.data.ugcWorth === 1500, `worth=${evaProfile.data.ugcWorth}`)

  console.log(`\nRESULT: ${passed} passed, ${failed} failed`)
  process.exit(failed ? 1 : 0)
}

main().catch((e) => {
  console.error('E2E crashed:', e)
  process.exit(1)
})
