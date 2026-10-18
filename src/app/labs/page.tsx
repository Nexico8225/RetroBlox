'use client'

import { Page, Title } from '@/components/retro/Shell'
import { LabsView } from '@/components/retro/LabsView'

export default function LabsPage() {
  return (
    <Page>
      <Title t="RetroLabs" />
      <LabsView />
    </Page>
  )
}
