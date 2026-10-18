'use client'

/* ================= the /download starter page =================
   The classic download dance, exactly like the big sites do it:
   press a download button -> a bare page opens (nothing on it but
   the url bar) -> the download starts by itself -> the tab closes.
   ?u=<encoded file url>&n=<suggested filename> */

import { useEffect, useRef, useState } from 'react'

export default function DownloadPage() {
  const [src, setSrc] = useState('')
  const [name, setName] = useState('')
  const [gone, setGone] = useState(false)
  const started = useRef(false)

  useEffect(() => {
    const p = new URLSearchParams(window.location.search)
    const u = p.get('u') || ''
    const n = p.get('n') || ''
    setName(n)
    // only same-origin file urls may ride the iframe — no open redirects
    if (u.startsWith('/') || u.startsWith(window.location.origin)) {
      started.current = true
      setSrc(u)
    }
    // the tab closes itself once the download is rolling (works when the
    // page was opened by a button — script-opened tabs may close)
    const t = setTimeout(() => {
      window.close()
      // if the browser refuses the auto-close, say so and stop spinning
      setGone(true)
    }, 1800)
    return () => clearTimeout(t)
  }, [])

  return (
    <div style={{
      minHeight: '100vh', background: '#ffffff', display: 'flex',
      flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      fontFamily: 'Arial, Helvetica, sans-serif', gap: 10,
    }}>
      <div style={{ fontSize: 14, color: '#1c3a52', fontWeight: 600 }}>
        {gone ? 'Your download has started.' : 'Your download will start...'}
      </div>
      {name ? <div style={{ fontSize: 11, color: '#8a97a3' }}>{name}</div> : null}
      {gone ? (
        <a href={src} style={{ fontSize: 11, color: '#00639e' }}>Didn&apos;t start? Tap here.</a>
      ) : null}
      {src ? <iframe src={src} style={{ display: 'none' }} title="download" /> : null}
    </div>
  )
}
