'use client'

import { Page, Title } from '@/components/retro/Shell'
import { SdkView } from '@/components/retro/SdkView'

export default function SdkPage() {
  return (
    <Page>
      <Title t="RetroBlox Player System" />
      <SdkView />
    </Page>
  )
}
