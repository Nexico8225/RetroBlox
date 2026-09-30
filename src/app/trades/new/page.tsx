import { Page, BootScreen } from '@/components/retro/Shell'
import { Suspense } from 'react'
import { TradeComposer } from '@/components/retro/TradeComposer'

export default function NewTradePage() {
  return (
    <Page>
      <Suspense fallback={<BootScreen />}>
        <TradeComposer />
      </Suspense>
    </Page>
  )
}
