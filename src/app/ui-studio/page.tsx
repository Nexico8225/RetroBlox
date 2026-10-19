'use client'

import { Page, Title } from '@/components/retro/Shell'
import { UiStudioView } from '@/components/retro/UiStudioView'

export default function UiStudioPage() {
  return (
    <Page>
      <Title t="UI Studio" />
      <UiStudioView />
    </Page>
  )
}
