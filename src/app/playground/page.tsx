'use client'

import { Page, Title } from '@/components/retro/Shell'
import { PlaygroundView } from '@/components/retro/PlaygroundView'

export default function PlaygroundPage() {
  return (
    <Page>
      <Title t="Playground" />
      <PlaygroundView />
    </Page>
  )
}
