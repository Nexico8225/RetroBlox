'use client'

import { Page, Title } from '@/components/retro/Shell'
import { SubsNewView } from '@/components/retro/CommunitySubs'

export default function SubsNewPage() {
  return (
    <Page>
      <Title t="Create a Community" />
      <SubsNewView />
    </Page>
  )
}
