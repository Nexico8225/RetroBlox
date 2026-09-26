'use client'

/* The old separate "make a video" upload page is gone — videos are now
   uploaded straight through the community post composer, and each one
   still gets its own watch page on the Videos tab. */

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Page } from '@/components/retro/Shell'

export default function VideosNewRedirect() {
  const router = useRouter()
  useEffect(() => {
    router.replace('/community/new?video=1')
  }, [router])
  return (
    <Page>
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>
        Videos are posted through the community now — taking you there...
        <div style={{ marginTop: 10 }}>
          <a href="/community/new?video=1" className="rb-btn rb-btn-green" style={{ textDecoration: 'none', display: 'inline-block' }}>
            Post a Video
          </a>
        </div>
      </div>
    </Page>
  )
}
