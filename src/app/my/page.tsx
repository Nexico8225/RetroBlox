'use client'

import { Page, Title } from '@/components/retro/Shell'
import { MyGamesView } from '@/components/retro/MyGamesView'

export default function MyGamesPage() {
  return (
    <Page>
      <Title t="My Games" />
      <MyGamesView />
    </Page>
  )
}
