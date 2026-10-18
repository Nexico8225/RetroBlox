'use client'

import { Page, Title } from '@/components/retro/Shell'
import { RbxAdminView } from '@/components/retro/RbxAdminView'

export default function AdminPage() {
  return (
    <Page>
      <Title t="Tix Admin" />
      <RbxAdminView />
    </Page>
  )
}
