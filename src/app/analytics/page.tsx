'use client'

import { Page, Title } from '@/components/retro/Shell'
import { AnalyticsView } from '@/components/retro/AnalyticsView'

export default function AnalyticsPage() {
  return (
    <Page>
      <Title t="Analytics" />
      <AnalyticsView />
    </Page>
  )
}
