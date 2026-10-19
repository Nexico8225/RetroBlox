'use client'

import { Page, Title } from '@/components/retro/Shell'
import { TemplatesView } from '@/components/retro/TemplatesView'

export default function TemplatesPage() {
  return (
    <Page>
      <Title t="Game Templates" />
      <TemplatesView />
    </Page>
  )
}
