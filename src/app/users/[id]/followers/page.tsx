import { Page } from '@/components/retro/Shell'
import { FollowListView } from '@/components/retro/ProfileFriends'

export default async function FollowersPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <FollowListView id={id} type="followers" />
    </Page>
  )
}
