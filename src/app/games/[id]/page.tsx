import { Page } from '@/components/retro/Shell'
import { GameDetailView } from '@/components/retro/GameDetailView'

export default async function GamePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <GameDetailView id={id} />
    </Page>
  )
}
