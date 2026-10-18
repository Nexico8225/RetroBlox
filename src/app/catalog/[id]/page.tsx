import { Page } from '@/components/retro/Shell'
import { ItemDetailView } from '@/components/retro/ItemDetailView'

/** /catalog/[id] — the item detail page (Roblox-style, but better) */
export default async function CatalogItemPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <Page>
      <ItemDetailView id={id} />
    </Page>
  )
}
