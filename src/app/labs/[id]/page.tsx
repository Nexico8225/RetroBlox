import { Page } from '@/components/retro/Shell'
import { LabDetailView } from '@/components/retro/LabsView'

export default async function LabPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <LabDetailView id={id} />
    </Page>
  )
}
