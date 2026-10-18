import { Page } from '@/components/retro/Shell'
import { CommunityDetailView } from '@/components/retro/CommunityView'

export default async function CommunityPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <CommunityDetailView id={id} />
    </Page>
  )
}
