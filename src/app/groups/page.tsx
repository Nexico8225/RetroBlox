'use client'

import { Page, Title } from '@/components/retro/Shell'
import { GroupsView } from '@/components/retro/GroupsView'

export default function GroupsPage() {
  return (
    <Page>
      <Title t="Groups" />
      <GroupsView />
    </Page>
  )
}
