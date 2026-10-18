'use client'

import { Page, Title } from '@/components/retro/Shell'
import { SubsBrowseView } from '@/components/retro/CommunitySubs'

export default function SubsPage() {
  return (
    <Page>
      <Title t="Communities" />
      <SubsBrowseView />
    </Page>
  )
}
