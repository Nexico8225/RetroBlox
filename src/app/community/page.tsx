'use client'

import { Suspense } from 'react'
import { Page, Title } from '@/components/retro/Shell'
import { CommunityView } from '@/components/retro/CommunityView'

export default function CommunityPage() {
  return (
    <Page>
      <Title t="Community" />
      <Suspense fallback={<div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading the lounge...</div>}>
        <CommunityView />
      </Suspense>
    </Page>
  )
}
