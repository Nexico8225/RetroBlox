'use client'

import { Page, Title } from '@/components/retro/Shell'
import { RbxStoreView } from '@/components/retro/RbxStoreView'

export default function StorePage() {
  return (
    <Page>
      <Title t="Tix Store" />
      <RbxStoreView />
    </Page>
  )
}
