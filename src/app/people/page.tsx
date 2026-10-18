'use client'

import { Page, Title } from '@/components/retro/Shell'
import { PeopleView } from '@/components/retro/PeopleView'

export default function PeoplePage() {
  return (
    <Page>
      <Title t="People" />
      <PeopleView />
    </Page>
  )
}
