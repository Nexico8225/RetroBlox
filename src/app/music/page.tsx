'use client'

import { Page, Title } from '@/components/retro/Shell'
import { MusicView } from '@/components/retro/MusicView'

export default function MusicPage() {
  return (
    <Page>
      <Title t="Music" />
      <MusicView />
    </Page>
  )
}
