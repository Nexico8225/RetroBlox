'use client'

import { Page, Title } from '@/components/retro/Shell'
import { LauncherView } from '@/components/retro/LauncherView'

export default function LauncherPage() {
  return (
    <Page>
      <Title t="RetroBlox Launcher" />
      <LauncherView />
    </Page>
  )
}
