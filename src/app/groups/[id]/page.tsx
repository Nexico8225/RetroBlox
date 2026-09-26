import { Page } from '@/components/retro/Shell'
import { GroupDetailView } from '@/components/retro/GroupsView'

export default async function GroupPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <GroupDetailView id={id} />
    </Page>
  )
}
