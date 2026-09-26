'use client'

import { Page, Title } from '@/components/retro/Shell'
import { LabNewView } from '@/components/retro/LabsView'

export default function LabNewPage() {
  return (
    <Page>
      <Title t="New RetroLabs Post" />
      <LabNewView />
    </Page>
  )
}
