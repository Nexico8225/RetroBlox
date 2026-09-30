'use client'

import { Page, Title } from '@/components/retro/Shell'
import { TradesView } from '@/components/retro/TradesView'

export default function TradesPage() {
  return (
    <Page>
      <Title t="Trades & Market" />
      <TradesView />
    </Page>
  )
}
