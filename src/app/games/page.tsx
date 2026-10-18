'use client'

import { Suspense } from 'react'
import { Page, Title, BootScreen } from '@/components/retro/Shell'
import { GamesView } from '@/components/retro/HomeView'
import { useSearchParams } from 'next/navigation'

export default function GamesPage() {
  return (
    <Suspense fallback={<BootScreen />}>
      <GamesInner />
    </Suspense>
  )
}

function GamesInner() {
  const params = useSearchParams()
  const q = params.get('q') || ''
  const genre = params.get('genre') || 'All Genres'
  const sort = params.get('sort') || 'popular'

  return (
    <Page>
      <Title t={q ? `Search: ${q}` : genre !== 'All Genres' ? `${genre} Games` : 'Games'} />
      <GamesView q={q} genre={genre} sort={sort} />
    </Page>
  )
}
