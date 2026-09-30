import { Page } from '@/components/retro/Shell'
import { TradeDetailView } from '@/components/retro/TradeDetailView'

export default async function TradePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <TradeDetailView id={id} />
    </Page>
  )
}
