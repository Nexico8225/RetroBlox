'use client'

import { Page, Title } from '@/components/retro/Shell'
import { SettingsView } from '@/components/retro/SettingsView'

export default function SettingsPage() {
  return (
    <Page>
      <Title t="Settings" />
      <SettingsView />
    </Page>
  )
}
