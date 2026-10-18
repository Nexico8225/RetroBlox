'use client'

/* ================= Tix Store (/store) =================
   Real Stripe Checkout: pick a package, pay on Stripe's page, the webhook
   credits the wallet. The browser only ever sends a package id — the
   server owns the price. The currency is Tix — the classic tickets. */

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, flash } from '@/lib/store'
import { tixFull, tixPileIcon } from '@/lib/tix'

interface RbxPackage {
  id: string
  code: string
  name: string
  rbxAmount: number
  priceCents: number
  currency: string
}

interface RbxTxn {
  id: string
  amount: number
  type: string
  note: string
  balanceAfter: number
  createdAt: string
  currency?: string
}

const usd = (cents: number) => `$${(cents / 100).toFixed(2)}`

const TYPE_LABEL: Record<string, string> = {
  purchase: 'Bought Tix',
  admin_grant: 'Admin grant',
  spend: 'Catalog purchase',
  refund: 'Refund reversal',
  reversal: 'Reversal',
  transfer_sent: 'Tix sent',
  transfer_received: 'Tix received',
  exchange: 'Currency exchange',
}

export function RbxStoreView() {
  const { user, setToast, setUser } = useRetro()
  const [packages, setPackages] = useState<RbxPackage[]>([])
  const [txns, setTxns] = useState<RbxTxn[]>([])
  const [mode, setMode] = useState<string>('test')
  const [bank, setBank] = useState<string>('stripe')
  const [loading, setLoading] = useState(true)
  const [buying, setBuying] = useState<string | null>(null)
  const [error, setError] = useState('')

  // send-tix state
  const [sendTo, setSendTo] = useState('')
  const [sendAmount, setSendAmount] = useState('')
  const [sendNote, setSendNote] = useState('')
  const [sending, setSending] = useState(false)
  const [sendError, setSendError] = useState('')

  const load = useCallback(async () => {
    try {
      const [pkgs, tx] = await Promise.all([
        api<{ packages: RbxPackage[]; mode: string; bank?: string }>('/api/rbx/packages'),
        api<{ transactions: RbxTxn[] }>('/api/rbx/transactions'),
      ])
      setPackages(pkgs.packages)
      setMode(pkgs.mode)
      setBank(pkgs.bank || 'stripe')
      setTxns(tx.transactions.slice(0, 12))
    } catch {
      setError('Could not load the store — refresh and try again.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function buy(pkg: RbxPackage) {
    setError('')
    setBuying(pkg.id)
    try {
      const res = await api<{ url: string; testbank?: boolean }>('/api/stripe/create-checkout-session', {
        method: 'POST',
        body: JSON.stringify({ packageId: pkg.id }),
      })
      // Stripe: off to Stripe's hosted Checkout page. Test Bank: straight to
      // the success page, which watches the balance land (it already has).
      window.location.href = res.url
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Could not start checkout', 3200)
      setBuying(null)
    }
  }

  async function sendTix() {
    setSendError('')
    const amount = Math.floor(Number(sendAmount))
    if (!sendTo.trim()) {
      setSendError('Type the username of who should get the Tix.')
      return
    }
    if (!Number.isFinite(amount) || amount < 1) {
      setSendError('Enter an amount of at least 1 Tix.')
      return
    }
    if (!window.confirm(`Send ${amount.toLocaleString('en-US')} Tix to ${sendTo.trim().replace(/^@/, '')}?`)) return
    setSending(true)
    try {
      const res = await api<{ balanceAfter: number; recipient: { username: string } }>('/api/rbx/transfer', {
        method: 'POST',
        body: JSON.stringify({ to: sendTo.trim(), amount, note: sendNote.trim() || undefined }),
      })
      flash(setToast, `Sent ${amount.toLocaleString('en-US')} Tix to ${res.recipient.username}!`, 3200)
      setSendTo('')
      setSendAmount('')
      setSendNote('')
      if (user) setUser({ ...user, rbxBalance: res.balanceAfter })
      load()
    } catch (e) {
      setSendError(e instanceof Error ? e.message : 'The transfer failed — try again.')
    } finally {
      setSending(false)
    }
  }

  const balance = user?.rbxBalance ?? 0
  // the biggest Tix-per-cent wins the classic "BEST VALUE" starburst
  const bestRatio = packages.length ? Math.max(...packages.map((p) => p.rbxAmount / Math.max(p.priceCents, 1))) : 0

  return (
    <div>
      {/* hero */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Tix Store</span></div>
        <div style={{ padding: 14, display: 'flex', flexWrap: 'wrap', gap: 14, alignItems: 'center' }}>
          {/* the biggest pile is the hero art */}
          <img
            src="/tix/tix-pile-5.png"
            alt="A mountain of Tix"
            draggable={false}
            style={{ width: 132, height: 'auto', filter: 'drop-shadow(0 6px 10px rgba(90,60,0,.35))', flexShrink: 0 }}
          />
          <div style={{ flex: 1, minWidth: 220 }}>
            <div style={{ fontSize: 17, color: '#1c2733' }}>Top up your Tix — powered by Stripe Checkout</div>
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 4 }}>
              Pick a pile, hit Buy, and Stripe completes the purchase — your wallet fills up the moment the
              bank hook confirms (usually seconds). Tix buy catalog items, limiteds and rare gear.
            </div>
          </div>
          <div
            style={{
              background: 'linear-gradient(180deg,#fff8dc,#f3e6b8)',
              border: '1px solid #8a6d1a',
              borderRadius: 4,
              padding: '8px 16px',
              textAlign: 'center',
              display: 'flex',
              alignItems: 'center',
              gap: 10,
            }}
          >
            <img src="/tix/tix-pile-1.png" alt="" draggable={false} style={{ width: 44, height: 'auto' }} />
            <div>
              <div style={{ fontSize: 10, color: '#7a611a' }}>Your balance</div>
              <div style={{ fontSize: 20, color: '#5d4a0a', fontFamily: 'monospace', fontWeight: 'bold' }}>
                {tixFull(balance)} Tix
              </div>
            </div>
          </div>
        </div>
        {bank === 'testbank' && (
          <div style={{ padding: '6px 14px 10px', fontSize: 10, color: '#2c6e31' }}>
            <b style={{ fontWeight: 400 }}>Test Bank is active</b> — Stripe keys are not configured yet, so every purchase completes
            instantly and costs you NOTHING: hit Buy and the Tix are yours. Add STRIPE_SECRET_KEY to switch to real Stripe Checkout.
          </div>
        )}
        {bank === 'stripe' && mode === 'test' && (
          <div style={{ padding: '6px 14px 10px', fontSize: 10, color: '#7a5a12' }}>
            Test mode — checkout runs against Stripe&apos;s test bank with test card 4242 4242 4242 4242. No real money moves.
          </div>
        )}
      </div>

      {error && <div className="rb-box" style={{ padding: 12, color: '#a81a13', fontSize: 12, marginBottom: 12 }}>{error}</div>}

      {/* packages */}
      {loading ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading packages...</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(170px, 1fr))', gap: 10, marginBottom: 12 }}>
          {packages.map((p) => {
            const isBest = p.rbxAmount / Math.max(p.priceCents, 1) === bestRatio && packages.length > 1
            return (
              <div
                key={p.id}
                className="rb-box"
                style={{
                  padding: 12,
                  textAlign: 'center',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 4,
                  position: 'relative',
                  border: isBest ? '2px solid #d9a400' : undefined,
                  boxShadow: isBest ? '0 0 0 3px rgba(255,211,78,.35)' : undefined,
                }}
              >
                {isBest && (
                  <div
                    style={{
                      position: 'absolute',
                      top: -9,
                      left: '50%',
                      transform: 'translateX(-50%) rotate(-2deg)',
                      background: 'linear-gradient(180deg,#ffd34e,#e8a800)',
                      border: '1px solid #a67900',
                      color: '#4a3600',
                      fontSize: 9,
                      letterSpacing: 1.5,
                      padding: '2px 10px',
                      borderRadius: 999,
                      whiteSpace: 'nowrap',
                    }}
                  >
                    BEST VALUE
                  </div>
                )}
                <img
                  src={tixPileIcon(p.rbxAmount)}
                  alt={`${tixFull(p.rbxAmount)} Tix pile`}
                  draggable={false}
                  style={{ height: 74, width: 'auto', maxWidth: '100%', margin: '2px auto 0', filter: 'drop-shadow(0 4px 6px rgba(90,60,0,.3))' }}
                />
                <div style={{ fontSize: 21, fontFamily: 'monospace', fontWeight: 'bold', color: '#1c4e7c', lineHeight: 1.15 }}>
                  {tixFull(p.rbxAmount)} <span style={{ fontSize: 12 }}>Tix</span>
                </div>
                <div style={{ fontSize: 11, color: '#7b8896' }}>{p.name}</div>
                <div style={{ fontSize: 14, color: '#1c2733' }}>{usd(p.priceCents)}</div>
                <button
                  className="rb-btn rb-btn-green"
                  style={{ fontSize: 11, width: '100%', marginTop: 'auto' }}
                  disabled={buying === p.id}
                  onClick={() => buy(p)}
                >
                  {buying === p.id ? 'Opening Stripe...' : 'Buy with Stripe'}
                </button>
              </div>
            )
          })}
          {packages.length === 0 && (
            <div className="rb-box" style={{ padding: 24, textAlign: 'center', color: '#5a6b7b', fontSize: 12 }}>
              No packages are on sale right now — check back soon.
            </div>
          )}
        </div>
      )}

      {/* send tix to another player */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Send Tix to a Player</span></div>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 11, color: '#41586c', marginBottom: 10 }}>
            Gift Tix straight from your wallet to any player — they get it instantly and it shows in
            both of your wallet activity. Type their exact username.
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'flex-start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, flex: '1 1 170px' }}>
              <label style={{ fontSize: 10, color: '#5a6b7b' }} htmlFor="send-to">To (username)</label>
              <input
                id="send-to"
                className="rb-input"
                placeholder="e.g. iLoveWaffles"
                value={sendTo}
                maxLength={20}
                onChange={(e) => setSendTo(e.target.value)}
                style={{ width: '100%' }}
              />
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, width: 140 }}>
              <label style={{ fontSize: 10, color: '#5a6b7b' }} htmlFor="send-amount">Amount (Tix)</label>
              <input
                id="send-amount"
                className="rb-input"
                placeholder="100"
                inputMode="numeric"
                value={sendAmount}
                onChange={(e) => setSendAmount(e.target.value.replace(/[^0-9]/g, ''))}
                style={{ width: '100%' }}
              />
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, flex: '1 1 150px' }}>
              <label style={{ fontSize: 10, color: '#5a6b7b' }} htmlFor="send-note">Note (optional)</label>
              <input
                id="send-note"
                className="rb-input"
                placeholder="thanks for the help!"
                maxLength={140}
                value={sendNote}
                onChange={(e) => setSendNote(e.target.value)}
                style={{ width: '100%' }}
              />
            </div>
            <button
              className="rb-btn rb-btn-green"
              style={{ fontSize: 12, padding: '8px 18px', marginTop: 18 }}
              disabled={sending || !user}
              onClick={sendTix}
            >
              {sending ? 'Sending...' : 'Send Tix'}
            </button>
          </div>
          {sendError && <div style={{ marginTop: 8, fontSize: 11, color: '#a81a13' }}>{sendError}</div>}
          {!user && (
            <div style={{ marginTop: 8, fontSize: 11, color: '#7b8896' }}>Log in to send Tix.</div>
          )}
        </div>
      </div>

      {/* how the money moves — honest words, no magic */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>How buying works</span></div>
        <div style={{ padding: 12, fontSize: 11, color: '#41586c', lineHeight: 1.7 }}>
          1. You hit Buy and RetroBlox asks Stripe (on the server) for a checkout page with that package&apos;s real price.<br />
          2. You pay on Stripe&apos;s page and come back here.<br />
          3. Stripe privately tells our server the payment went through — that webhook is the only thing that adds Tix,
          and it can never double-credit, even if Stripe retries.<br />
          4. The success page just watches your balance until it lands.
        </div>
      </div>

      {/* recent wallet activity */}
      <div className="rb-box">
        <div className="rb-panel-head"><span>Recent Wallet Activity</span></div>
        {txns.length === 0 ? (
          <div style={{ padding: 16, fontSize: 11, color: '#7b8896' }}>
            Nothing yet — your purchases, grants and refunds will show up here.
          </div>
        ) : (
          <div style={{ padding: 8 }}>
            {txns.map((t) => {
              const isRobux = t.currency === 'robux'
              const unit = isRobux ? 'R$' : 'Tix'
              return (
                <div key={t.id} style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '5px 4px', borderBottom: '1px solid #eef2f6', fontSize: 11 }}>
                  <span style={{ flex: 1, color: '#41586c', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {TYPE_LABEL[t.type] || t.type}{t.note ? ` — ${t.note}` : ''}
                  </span>
                  <span style={{ fontFamily: 'monospace', color: t.amount >= 0 ? '#2c6e31' : '#a81a13', whiteSpace: 'nowrap' }}>
                    {t.amount >= 0 ? '+' : ''}{tixFull(t.amount)} {unit}
                  </span>
                  <span style={{ fontFamily: 'monospace', color: '#7b8896', whiteSpace: 'nowrap' }}>→ {tixFull(t.balanceAfter)} {unit}</span>
                </div>
              )
            })}
            <div style={{ padding: '6px 4px 2px' }}>
              <Link href="/catalog" className="rb-link" style={{ fontSize: 11 }}>Spend it in the Catalog →</Link>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
