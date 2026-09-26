'use client'

import { Page, Title } from '@/components/retro/Shell'
import { CommunityNewView } from '@/components/retro/CommunityView'

export default function CommunityNewPage() {
  return (
    <Page>
      <Title t="New Community Post" />
      <CommunityNewView />
    </Page>
  )
}
