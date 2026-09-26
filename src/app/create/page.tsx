'use client'

import { Suspense } from 'react'
import { Page, Title, BootScreen } from '@/components/retro/Shell'
import { CreateView } from '@/components/retro/CreateView'

export default function CreatePage() {
  return (
    <Suspense fallback={<BootScreen />}>
      <Page>
        <Title t="Create" />
        <CreateView />
      </Page>
    </Suspense>
  )
}
