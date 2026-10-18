'use client'

import { Suspense, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Page, Title, BootScreen } from '@/components/retro/Shell'

/* Videos merged into the Community tab (Posts | Videos switcher).
   This URL now forwards there — watch pages stay at /videos/[id]. */
export default function VideosPage() {
  return (
    <Suspense fallback={<BootScreen />}>
      <VideosRedirect />
    </Suspense>
  )
}

function VideosRedirect() {
  const router = useRouter()
  useEffect(() => {
    router.replace('/community?tab=videos')
  }, [router])
  return (
    <Page>
      <Title t="Videos" />
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>
        Videos now live inside the Community tab — taking you there...
      </div>
    </Page>
  )
}
