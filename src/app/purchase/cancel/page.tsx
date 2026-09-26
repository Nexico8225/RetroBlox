'use client'

/* /purchase/cancel — the player bailed out of Stripe Checkout. Nothing was
   charged, nothing is owed, and no RBX moves. */

import Link from 'next/link'
import { Page, Title } from '@/components/retro/Shell'

export default function PurchaseCancelPage() {
  return (
    <Page>
      <Title t="Checkout Cancelled" />
      <div className="rb-box" style={{ maxWidth: 560, margin: '0 auto', padding: 24, textAlign: 'center' }}>
        <div style={{ fontSize: 34, marginBottom: 6 }}>🚫</div>
        <div className="rb-panel-head" style={{ marginBottom: 0 }}><span>Checkout cancelled</span></div>
        <div style={{ padding: 16, fontSize: 12, color: '#41586c', lineHeight: 1.8 }}>
          You cancelled at Stripe, so you were <b>not</b> charged and no Tix were added.
          Nothing is owed. The packages are still right where you left them.
        </div>
        <div style={{ display: 'flex', gap: 8, justifyContent: 'center', padding: '0 16px 16px', flexWrap: 'wrap' }}>
          <Link href="/store" className="rb-btn rb-btn-green" style={{ fontSize: 11, textDecoration: 'none' }}>Back to the Tix Store</Link>
        </div>
      </div>
    </Page>
  )
}
