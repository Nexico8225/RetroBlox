import { Page, Title } from '@/components/retro/Shell'
import { CatalogView } from '@/components/retro/CatalogView'

/** /catalog — the UGC marketplace. ?type=hat / ?q=wizard preselect the filters
 *  (the item page's breadcrumb deep-links here). */
export default async function CatalogPage({ searchParams }: { searchParams: Promise<{ type?: string; q?: string }> }) {
  const sp = await searchParams
  return (
    <Page>
      <Title t="Catalog" />
      <CatalogView initialType={sp.type || ''} initialQ={sp.q || ''} />
    </Page>
  )
}
