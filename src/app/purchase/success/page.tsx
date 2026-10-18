'use client'

/* /purchase/success — Stripe bounced us back here after payment.
   This page NEVER grants RBX. The webhook is the authority: we just watch
   the server-side balance until the bank hook lands (usually seconds). */

import { useEffect, useState, Suspense } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { Page, Title } from '@/components/retro/Shell'
import { useRetro, api } from '@/lib/store'
import { tixFull } from '@/lib/tix'

function PurchaseSuccessInner() {
  const { setUser, user } = useRetro()
  const searchParams = useSearchParams()
  const sessionId = searchParams.get('session_id') || ''
  const [balance, setBalance] = useState<number | null>(null)
  const [landed, setLanded] = useState(false)
  const [seconds, setSeconds] = useState(0)
  const [gaveUp, setGaveUp] = useState(false)

  useEffect(() => {
    let alive = true
    let last: number | null = user?.rbxBalance ?? null

    const poll = async () => {
      try {
        // 1) the AUTHORITATIVE check: did THIS checkout grant its Tix?
        //    (both the Stripe webhook and the Test Bank mark the Payment
        //    row succeeded — so this works even when the header already
        //    refreshed the balance before this page mounted)
        if (sessionId) {
          const st = await api<{ granted: boolean; status: string }>(
            `/api/rbx/session-status?session_id=${encodeURIComponent(sessionId)}`
          )
          if (!alive) return
          if (st.granted) setLanded(true)
        }
        // 2) the balance itself (for display + the no-session fallback)
        const res = await api<{ balance: number }>('/api/rbx/balance')
        if (!alive) return
        setBalance(res.balance)
        if (!sessionId && last !== null && res.balance > last) setLanded(true)
        last = res.balance
        // keep the header chip honest too
        const u = useRetro.getState().user
        if (u) setUser({ ...u, rbxBalance: res.balance })
      } catch { /* keep polling */ }
    }

    poll()
    const t = setInterval(() => {
      if (!alive) return
      setSeconds((s) => {
        const n = s + 1
        if (n > 45) setGaveUp(true)
        return n
      })
      poll()
    }, 2500)
    return () => {
      alive = false
      clearInterval(t)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId])

  return (
    <Page>
      <Title t="Payment Received" />
      <div className="rb-box" style={{ maxWidth: 560, margin: '0 auto', padding: 24, textAlign: 'center' }}>
        {/* the celebration pile — your new Tix, rendered */}
        <img
          src={landed ? '/tix/tix-pile-4.png' : '/tix/tix-pile-3.png'}
          alt="A pile of Tix"
          draggable={false}
          className="rb-auth-float"
          style={{ width: 150, height: 'auto', margin: '2px auto 8px', display: 'block', filter: 'drop-shadow(0 8px 12px rgba(90,60,0,.35))' }}
        />
        <div className="rb-panel-head" style={{ marginBottom: 0 }}><span>Payment received — nice one!</span></div>
        <div style={{ padding: 16, fontSize: 12, color: '#41586c', lineHeight: 1.8 }}>
          Stripe took your payment and sent you back. Your Tix are added by our bank hook the moment it
          confirms the payment with Stripe — this page watches your wallet and updates itself.
          {sessionId && (
            <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#8ba0b3', marginTop: 6 }}>
              checkout: {sessionId.slice(0, 28)}…
            </div>
          )}
        </div>
        <div
          style={{
            margin: '0 16px 14px',
            padding: 12,
            background: landed ? 'linear-gradient(180deg,#eefbe8,#dff5d2)' : '#f4f8fb',
            border: `1px solid ${landed ? '#4c9e34' : '#b7c6d4'}`,
            fontSize: 13,
            color: landed ? '#2c6e31' : '#41586c',
          }}
        >
          {landed ? (
            <>Tix landed! New balance: <b style={{ fontFamily: 'monospace' }}>{tixFull(balance ?? 0)} Tix</b></>
          ) : gaveUp ? (
            <>Still verifying — Stripe is telling our server about the payment. It lands within a minute or two;
            your balance is safe either way. Check the <Link href="/store" className="rb-link">Tix Store</Link> in a moment.</>
          ) : (
            <>Verifying with the bank… current balance: <b style={{ fontFamily: 'monospace' }}>{tixFull(balance ?? 0)} Tix</b> ({seconds}s)</>
          )}
        </div>
        <div style={{ display: 'flex', gap: 8, justifyContent: 'center', padding: '0 16px 16px', flexWrap: 'wrap' }}>
          <Link href="/store" className="rb-btn" style={{ fontSize: 11, textDecoration: 'none' }}>Back to the Tix Store</Link>
          <Link href="/catalog" className="rb-btn rb-btn-green" style={{ fontSize: 11, textDecoration: 'none' }}>Spend it in the Catalog</Link>
        </div>
      </div>
    </Page>
  )
}

export default function PurchaseSuccessPage() {
  return (
    <Suspense fallback={<Page><Title t="Payment Received" /><div className="rb-box" style={{ maxWidth: 560, margin: '0 auto', padding: 24, textAlign: 'center', color: '#5a6b7b', fontSize: 12 }}>Loading...</div></Page>}>
      <PurchaseSuccessInner />
    </Suspense>
  )
}
