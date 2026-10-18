import { Page, Title } from '@/components/retro/Shell'
import { FavoritesView } from '@/components/retro/MyGamesView'

export default function FavoritesPage() {
  return (
    <Page>
      <Title t="Favorites" />
      <FavoritesView />
    </Page>
  )
}
