'use client'

import { Page, Title } from '@/components/retro/Shell'
import { HomeView } from '@/components/retro/HomeView'

export default function HomePage() {
  return (
    <Page>
      <Title t="RetroBlox" />
      <HomeView />
    </Page>
  )
}
