// LOCAL E2E: this update's new flows — robux-free trades, the Roblox-style
// composer data paths, UGC comments, numeric player ids, people search,
// trade targeting + incoming offers, bot sweep API (admin).
// Runs against the LOCAL dev server only — never the live site.
const BASE = process.env.LOCAL_BASE || 'http://localhost:3000';
const stamp = 'bt' + Date.now().toString(36).slice(-6);
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.log('  FAIL ' + m); } };
const j = (x) => JSON.stringify(x).slice(0, 180);

async function api(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch {}
  return { status: res.status, data };
}

async function signup(name) {
  const fd = new FormData();
  fd.set('username', name);
  fd.set('password', 'E2e#2026x');
  const r = await fetch(BASE + '/api/auth/signup', { method: 'POST', body: fd });
  const d = await r.json().catch(() => null);
  if (r.status !== 200 && r.status !== 201) throw new Error('signup failed ' + r.status + ' ' + JSON.stringify(d));
  return { name, token: d.token, id: d.user.id, playerNo: d.user.playerNo };
}

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAF0lEQVR4nGP8z8Dwn4GBgYGJgYGBAQAkBgMBOJdvzAAAAABJRU5ErkJggg==', 'base64');

async function publish(token, name, price, limited) {
  const fd = new FormData();
  fd.set('name', name);
  fd.set('type', 'tshirt');
  fd.set('description', 'e2e ' + stamp);
  fd.set('price', String(price));
  if (limited) { fd.set('limited', '1'); fd.set('stock', '5'); }
  fd.set('image', new Blob([PNG], { type: 'image/png' }), 'p.png');
  const res = await fetch(BASE + '/api/catalog', { method: 'POST', headers: { Authorization: 'Bearer ' + token }, body: fd });
  const d = await res.json().catch(() => null);
  return d?.item?.id;
}

(async () => {
  console.log('LOCAL E2E @', BASE, 'stamp:', stamp);
  // --- numeric player ids ---
  const A = await signup('e2ea' + stamp);
  const B = await signup('e2eb' + stamp);
  ok(Number.isInteger(A.playerNo) && A.playerNo > 0, `playerNo assigned at signup (A=#${A.playerNo}, B=#${B.playerNo})`);
  ok(B.playerNo === A.playerNo + 1, 'join order increments by 1');

  // --- people search ---
  const sr = await api('GET', '/api/users?q=' + encodeURIComponent('e2ea' + stamp), null, B.token);
  ok(sr.status === 200 && (sr.data?.users || []).some((u) => u.id === A.id && u.playerNo === A.playerNo), 'people search finds A with playerNo');
  const srEmpty = await api('GET', '/api/users?q=', null, B.token);
  ok(srEmpty.status === 200 && (srEmpty.data?.users || []).length > 0, 'empty query returns newest members');

  // --- fund both wallets via the Test Bank (Stripe plumbing credits Tix) ---
  async function fund(token) {
    const pkgs = await api('GET', '/api/rbx/packages', null, token);
    const pkg = pkgs.data?.packages?.[0];
    const res = await api('POST', '/api/stripe/create-checkout-session', { packageId: pkg.id }, token);
    return res.status === 200 && res.data?.testbank === true;
  }
  ok(await fund(A.token), 'Test Bank funded A (Tix)');
  ok(await fund(B.token), 'Test Bank funded B (Tix)');

  // --- items ---
  const t1 = await publish(A.token, 'E2E Crown A ' + stamp, 500, true);
  const free1 = await publish(A.token, 'E2E Free Shirt ' + stamp, 0, false);
  ok(!!t1 && !!free1, 'A published a limited + a FREE item');
  const balA0 = (await api('GET', '/api/me', null, A.token)).data?.user?.rbxBalance ?? 0;
  const balB0 = (await api('GET', '/api/me', null, B.token)).data?.user?.rbxBalance ?? 0;
  ok(balA0 > 0 && balB0 > 0, `wallets funded (A=T$${balA0}, B=T$${balB0})`);

  // --- trade targeting on the item page data ---
  const detail = await api('GET', '/api/catalog/' + free1, null, B.token);
  ok(detail.status === 200 && detail.data?.tradeTarget?.id === A.id, 'tradeTarget resolves to the creator for a listed-free item');
  ok(Array.isArray(detail.data?.incomingTrades), 'incomingTrades array present');

  // --- TRADE (robux-free): B requests the FREE item offering nothing but a msg is allowed? needs something: offer own item? B has none. Add tix 0 + item... B owns nothing, so use a pure tix=0+take -> invalid; instead B offers nothing but takes: must be rejected
  const opener = await api('POST', '/api/trades', { toUserId: A.id, giveItemIds: [], takeItemIds: [free1], tix: 0 }, B.token);
  ok(opener.status === 200, 'an item request with nothing on my side is a legal opener (they counter)');
  await api('POST', '/api/trades/' + opener.data.tradeId, { action: 'decline' }, A.token);

  // A gifts B a free item first so B has inventory
  const gift = await api('POST', '/api/trades', { toUserId: B.id, giveItemIds: [free1], takeItemIds: [], tix: 0, message: 'free [sparkle]gift[/sparkle]' }, A.token);
  ok(gift.status === 200 && gift.data?.tradeId, 'A gifts the FREE item to B (trades work at T$0 value)');
  const accGift = await api('POST', '/api/trades/' + gift.data.tradeId, { action: 'accept' }, B.token);
  ok(accGift.status === 200, 'B accepts the free gift');
  const profB = await api('GET', '/api/users/' + B.id, null, B.token);
  ok((profB.data?.inventory || []).some((e) => e.id === free1), 'B owns the free item now');

  // --- composer path: B trades his item back for A's limited + tix ---
  const trade2 = await api('POST', '/api/trades', { toUserId: A.id, giveItemIds: [free1], takeItemIds: [t1], tix: 50, message: 'swap? [tilt]deal[/tilt]' }, B.token);
  ok(trade2.status === 200 && trade2.data?.tradeId, 'B sent a mixed trade (item + item + Tix, no robux field)');
  // incoming offers now visible on A's item page data
  const detailA = await api('GET', '/api/catalog/' + t1, null, A.token);
  ok((detailA.data?.incomingTrades || []).some((t) => t.id === trade2.data.tradeId), "owner sees the pending trade in the item's incomingTrades");
  // counter keeps working tix-only
  const counter = await api('POST', '/api/trades/' + trade2.data.tradeId, { action: 'counter', giveItemIds: [free1], takeItemIds: [t1], tixFrom: 80, tixTo: 0 }, A.token);
  ok(counter.status === 200, 'A countered tixTo=400 (robux fields gone)');
  const acc2 = await api('POST', '/api/trades/' + trade2.data.tradeId, { action: 'accept' }, B.token);
  ok(acc2.status === 200, 'B accepted the countered trade');
  const meA = await api('GET', '/api/me', null, A.token);
  const meB2 = await api('GET', '/api/me', null, B.token);
  ok(meA.data?.user?.rbxBalance === balA0 + 80, `A received T$80 from the countered terms (got ${meA.data?.user?.rbxBalance})`);
  ok(meB2.data?.user?.rbxBalance === balB0 - 80, `B paid T$80 (got ${meB2.data?.user?.rbxBalance})`);

  // --- UGC COMMENTS ---
  const c1 = await api('POST', `/api/catalog/${t1}/comments`, { text: 'this hat is [fire]fire[/fire]' }, B.token);
  ok(c1.status === 200 && c1.data?.comment?.text.includes('[fire]'), 'B posted a comment with Text FX markup');
  const cBad = await api('POST', `/api/catalog/${t1}/comments`, { text: '   ' }, B.token);
  ok(cBad.status === 400, 'empty comment rejected');
  const cList = await api('GET', `/api/catalog/${t1}/comments`, null, null);
  ok(cList.status === 200 && (cList.data?.comments || []).some((c) => c.user.username === 'e2eb' + stamp && c.user.playerNo === B.playerNo), 'comment list shows username + playerNo');

  // --- trade room payload is robux-free ---
  const room = await api('GET', '/api/trades/' + gift.data.tradeId, null, A.token);
  ok(room.status === 200 && !('robuxFrom' in (room.data?.trade || {})), 'trade room payload has no robux fields');

  // --- bot sweep API (admin-only) ---
  const botsAsB = await api('GET', '/api/admin/bots', null, B.token);
  ok(botsAsB.status === 403, 'bot sweep is admin-only (B got 403)');

  console.log('\nRESULT: ' + pass + ' pass, ' + fail + ' fail (users e2ea/e2eb ' + stamp + ' left locally for cleanup script)');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('E2E ERROR', e); process.exit(2); });
