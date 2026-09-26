import { Page } from '@/components/retro/Shell'
import { ProfileView } from '@/components/retro/ProfileFriends'

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <ProfileView id={id} />
    </Page>
  )
}
