import { Page } from '@/components/retro/Shell'
import { VideoWatchView } from '@/components/retro/VideosView'

export default async function WatchPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <VideoWatchView id={id} />
    </Page>
  )
}
