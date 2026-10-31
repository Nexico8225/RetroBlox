'use client'

import { Page, Title } from '@/components/retro/Shell'
import { BotCleanupView } from '@/components/retro/BotCleanupView'

export default function BotCleanupPage() {
  return (
    <Page>
      <Title t="Bot Cleanup — RetroBlox Admin" />
      <BotCleanupView />
    </Page>
  )
}
