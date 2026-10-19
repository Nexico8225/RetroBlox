import { Page } from '@/components/retro/Shell'
import { WebGamePlayer } from '@/components/retro/WebGamePlayer'

export default async function PlayWebPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <WebGamePlayer id={id} />
    </Page>
  )
}
