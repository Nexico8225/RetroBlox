'use client'

import { Page, Title } from '@/components/retro/Shell'
import { FriendsView } from '@/components/retro/ProfileFriends'

export default function FriendsPage() {
  return (
    <Page>
      <Title t="Friends" />
      <FriendsView />
    </Page>
  )
}
