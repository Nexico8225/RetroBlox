#!/usr/bin/env node
/* E2E addendum: profile trading + UGC-on-offers + listing pitches.
 * Run against a LOCAL server: node scripts/e2e_market2.cjs http://localhost:3000
 *
 * Covers:
 *   - listing a copy WITH a title + description (the market pitch)
 *   - offer validation: no empty offers, can't offer the listed item,
 *     can't offer something the seller already owns
 *   - a MIXED offer (Tix + UGC) and a PURE UGC offer (T$ 0)
 *   - accept moves the offered items AND the Tix, serials travel,
 *     pure-UGC accepts add NO price point (the graph stays honest)
 *   - /api/users/[id] exposes `inventory` (the profile UGC shelf, serials in)
 *   - a profile-style trade (give item + request their limited + T$ 6000)
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

const stamp = () => 'e2x' + Math.random().toString(36).slice(2, 8)

async function signup(username) {
  const form = new FormData()
  form.append('username', username)
  form.append('password', 'test12345')
  form.append('birthday', '2000-01-01')
  form.append('gender', 'male')
  const r = await api('/api/auth/signup', { method: 'POST', form })
  if (r.status !== 200) throw new Error(`signup failed for ${username}: ${JSON.stringify(r.data)}`)
  return { id: r.data.user.id, username, token: r.data.token }
}

// 1x1 red PNG
const PNG = Buffer.from('89504e470d0a1a0a0000000d494844520000000100000001080200000090775' +
  '3de0000000c4944415408d763f8cfc00000030101', 'hex') + Buffer.from('00', 'hex')
const pngFile = () => new File([PNG], 't.png', { type: 'image/png' })

async function publishItem(user, name, price, limited) {
  const form = new FormData()
  form.append('name', name)
  form.append('type', 'tshirt')
  form.append('description', 'e2e market2 item')
  form.append('price', String(price))
  form.append('limited', limited ? '1' : '0')
  if (limited) form.append('stock', '5')
  form.append('image', pngFile())
  const r = await api('/api/catalog', { method: 'POST', token: user.token, form })
  if (r.status !== 200) throw new Error(`publish failed: ${JSON.stringify(r.data)}`)
  return r.data.item
}

async function main() {
  console.log(`E2E market2 (profile trades + UGC offers) against ${BASE}`)
  const s = stamp()
  const alice = await signup(`mx_${s}_a`) // creator
  const bob = await signup(`mx_${s}_b`)   // first buyer / seller
  const carol = await signup(`mx_${s}_c`) // mixed-offer trader
  ok('three players signed up', !!alice.token && !!bob.token && !!carol.token)

  const { execSync } = require('node:child_process')
  const py = (id, amt) => `python3 -c "import sqlite3;c=sqlite3.connect('db/custom.db');c.execute(\\"UPDATE User SET rbxBalance=${amt} WHERE id='${id}'\\");c.commit()"`
  execSync(py(bob.id, 100000))
  execSync(py(carol.id, 100000))

  // ---- mint: alice publishes a limited, bob buys copy #1 ----
  const gem = await publishItem(alice, `Profile Gem ${s}`, 1000, true)
  ok('limited published', !!gem?.id)
  let r = await api(`/api/catalog/${gem.id}`, { method: 'POST', token: bob.token, body: { action: 'buy' } })
  ok('bob buys the gem at mint price', r.status === 200, r.data.message || r.data.error)

  // ---- bob publishes his copy WITH a pitch (title + description) ----
  r = await api('/api/market', { method: 'POST', token: bob.token, body: { action: 'list', itemId: gem.id, price: 1500, title: `CHEAP Gem ${s}!`, description: 'Accepting UGC or Tix — haggle me in chat.' } })
  ok('bob lists the copy with title + description', r.status === 200, r.data.message || r.data.error)

  let detail = await api(`/api/market?itemId=${gem.id}`)
  const listingId = detail.data.listings?.[0]?.id
  ok('the market browser shows the listing title', detail.data.listings?.[0]?.title === `CHEAP Gem ${s}!`, `title=${JSON.stringify(detail.data.listings?.[0]?.title)}`)
  const ld0 = await api(`/api/market/${listingId}`, { token: bob.token })
  ok('listing detail carries the pitch too', ld0.data.listing?.title === `CHEAP Gem ${s}!` && !!ld0.data.listing?.description)

  // ---- two extra items: one bob owns (for the seller-has-it rejection), one carol owns (offer fodder) ----
  const bobExtra = await publishItem(alice, `Bob Only ${s}`, 10, false)
  r = await api(`/api/catalog/${bobExtra.id}`, { method: 'POST', token: bob.token, body: { action: 'buy' } })
  ok('bob buys a second normal item', r.status === 200)
  const hat = await publishItem(carol, `Carols Hat ${s}`, 50, false)
  ok('carol auto-owns her published hat', !!hat?.id)

  // ---- offer validation ----
  r = await api('/api/market', { method: 'POST', token: carol.token, body: { action: 'offer', listingId, amount: 0, offerItemIds: [] } })
  ok('empty offer rejected', r.status === 400, r.data.error)
  r = await api('/api/market', { method: 'POST', token: carol.token, body: { action: 'offer', listingId, amount: 0, offerItemIds: [gem.id] } })
  ok('offering the item being sold rejected', r.status === 400, r.data.error)
  r = await api('/api/market', { method: 'POST', token: carol.token, body: { action: 'offer', listingId, amount: 100, offerItemIds: [bobExtra.id] } })
  ok('offering an item the seller already owns rejected', r.status === 400, r.data.error)

  // ---- the MIXED offer: Tix + UGC on the table ----
  r = await api('/api/market', { method: 'POST', token: carol.token, body: { action: 'offer', listingId, amount: 100, offerItemIds: [hat.id], message: 'gem for my hat + 100 tix?' } })
  ok('carol sends a mixed offer (T$ 100 + her hat)', r.status === 200, r.data.message || r.data.error)

  let mine = await api('/api/market?mine=1', { token: bob.token })
  const mo = mine.data.listings?.[0]?.offers?.[0]
  ok('bob sees the offered item ids on his listing', !!mo && mo.offerItemIdsJson.includes(hat.id))
  ok('the offer item map resolves carol\'s hat preview', mine.data.offerItemMap?.[hat.id]?.name === `Carols Hat ${s}`)
  const ld = await api(`/api/market/${listingId}`, { token: bob.token })
  ok('listing detail shows the offer + item previews', ld.data.offers?.[0]?.offerItemIdsJson?.includes(hat.id) && !!ld.data.offerItemMap?.[hat.id])

  // ---- accept: Tix AND the UGC cross ----
  r = await api('/api/market', { method: 'POST', token: bob.token, body: { action: 'accept_offer', offerId: mo.id } })
  ok('bob accepts the mixed offer', r.status === 200, r.data.message || r.data.error)
  let gemState = await api(`/api/catalog/${gem.id}`, { token: carol.token })
  ok('carol owns the gem now, SAME serial #1', gemState.data.owned === true && gemState.data.market?.mySerial === 1)
  const hatState = await api(`/api/catalog/${hat.id}`, { token: bob.token })
  ok('bob received carol\'s hat in the same accept', hatState.data.owned === true)
  const bobBal = (await api('/api/me', { token: bob.token })).data.user.rbxBalance
  const carolBal = (await api('/api/me', { token: carol.token })).data.user.rbxBalance
  ok('bob wallet: 100000 - 1000 mint - 10 extra item + 100 offer', bobBal === 99090, `balance=${bobBal}`)
  ok('carol wallet: 100000 - 100 offer', carolBal === 99900, `balance=${carolBal}`)
  gemState = await api(`/api/catalog/${gem.id}`, { token: carol.token })
  ok('history: mint(1000) + resale(100) — graph honest', (gemState.data.market?.history || []).length === 2, `points=${gemState.data.market?.history?.length}`)

  // ---- carol flips the gem back; bob offers PURE UGC (T$ 0) ----
  r = await api('/api/market', { method: 'POST', token: carol.token, body: { action: 'list', itemId: gem.id, price: 2000, title: `Flip ${s}`, description: 'UGC trades preferred.' } })
  ok('carol lists the gem for 2000', r.status === 200)
  const listing2 = (await api(`/api/market?itemId=${gem.id}`)).data.listings[0]?.id
  r = await api('/api/market', { method: 'POST', token: bob.token, body: { action: 'offer', listingId: listing2, amount: 0, offerItemIds: [hat.id] } })
  ok('bob sends a PURE UGC offer (hat, no Tix)', r.status === 200, r.data.message || r.data.error)
  const ld2 = await api(`/api/market/${listing2}`, { token: carol.token })
  r = await api('/api/market', { method: 'POST', token: carol.token, body: { action: 'accept_offer', offerId: ld2.data.offers[0].id } })
  ok('carol accepts the pure-UGC offer', r.status === 200, r.data.message || r.data.error)
  gemState = await api(`/api/catalog/${gem.id}`, { token: bob.token })
  ok('bob owns the gem again, serial still #1', gemState.data.owned === true && gemState.data.market?.mySerial === 1)
  ok('NO price point added for the T$ 0 swap (still 2)', (gemState.data.market?.history || []).length === 2, `points=${gemState.data.market?.history?.length}`)

  // ---- the profile UGC shelf ----
  const bobProfile = await api(`/api/users/${bob.id}`, { token: carol.token })
  ok('bob\'s profile exposes his UGC inventory', (bobProfile.data.inventory || []).some((e) => e.id === gem.id), `items=${bobProfile.data.inventory?.length}`)
  ok('the shelf carries the limited serial', bobProfile.data.inventory?.find((e) => e.id === gem.id)?.serial === 1)
  const carolProfile = await api(`/api/users/${carol.id}`, { token: bob.token })
  ok('carol\'s profile shelf shows her hat back', (carolProfile.data.inventory || []).some((e) => e.id === hat.id))

  // ---- profile-style trade: carol requests the gem from bob's shelf + T$ 6000 ----
  const charm = await publishItem(carol, `Carols Charm ${s}`, 20, false)
  r = await api('/api/trades', { method: 'POST', token: carol.token, body: { toUserId: bob.id, giveItemIds: [charm.id], takeItemIds: [gem.id], tix: 6000, message: 'Saw the gem on your profile — 6000 + my charm?' } })
  ok('carol sends the profile trade (charm + T$ 6000 for the gem)', r.status === 200, r.data.message || r.data.error)
  const tradeId = r.data.tradeId
  const bobIn = await api('/api/trades', { token: bob.token })
  ok('bob sees the incoming trade with both item sets', bobIn.data.incoming?.length === 1 && bobIn.data.incoming[0].takeItemIds?.includes(gem.id) && bobIn.data.incoming[0].giveItemIds?.includes(charm.id))
  r = await api(`/api/trades/${tradeId}`, { method: 'POST', token: bob.token, body: { action: 'accept' } })
  ok('bob accepts -> the swap completes', r.status === 200, r.data.message || r.data.error)
  gemState = await api(`/api/catalog/${gem.id}`, { token: carol.token })
  ok('carol owns the gem after the profile trade, serial #1 forever', gemState.data.owned === true && gemState.data.market?.mySerial === 1)
  const carolBal2 = (await api('/api/me', { token: carol.token })).data.user.rbxBalance
  const bobBal2 = (await api('/api/me', { token: bob.token })).data.user.rbxBalance
  ok('carol paid 6000 tix (99900 - 6000)', carolBal2 === 93900, `balance=${carolBal2}`)
  ok('bob got the 6000 (99090 + 6000)', bobBal2 === 105090, `balance=${bobBal2}`)

  // ---- notifications fired for everyone ----
  const bobN = await api('/api/notifications', { token: bob.token })
  ok('bob was notified about the trade offer', (bobN.data.items || []).some((n) => n.type === 'trade_offer'))
  const carolN = await api('/api/notifications', { token: carol.token })
  ok('carol was notified her mixed offer was accepted', (carolN.data.items || []).some((n) => n.type === 'offer_accepted'))

  console.log(`\nRESULT: ${passed} passed, ${failed} failed`)
  process.exit(failed ? 1 : 0)
}

main().catch((e) => {
  console.error('E2E crashed:', e)
  process.exit(1)
})
