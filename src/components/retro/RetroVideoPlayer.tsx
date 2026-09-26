'use client'

/* ------------------------------------------------------------------
   RetroVideoPlayer — a YouTube-style player with a 2006 skin.
   - red seek bar you can click OR drag to any moment (like jumping to 1:10)
   - skip back / forward 10 seconds
   - playback speed (0.5x → 2x)
   - big timestamp readout + hover preview while scrubbing
   - volume, fullscreen, retro beveled chrome
------------------------------------------------------------------ */

import { useCallback, useEffect, useRef, useState } from 'react'

function fmtTime(t: number): string {
  if (!isFinite(t) || t < 0) t = 0
  const h = Math.floor(t / 3600)
  const m = Math.floor((t % 3600) / 60)
  const s = Math.floor(t % 60)
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${m}:${String(s).padStart(2, '0')}`
}

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2]

export function RetroVideoPlayer({
  src,
  poster,
  title,
  autoPlay = false,
}: {
  src: string
  poster?: string
  title?: string
  autoPlay?: boolean
}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const wrapRef = useRef<HTMLDivElement>(null)
  const barRef = useRef<HTMLDivElement>(null)
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const [playing, setPlaying] = useState(false)
  const [duration, setDuration] = useState(0)
  const [time, setTime] = useState(0)
  const [buffered, setBuffered] = useState(0)
  const [scrubbing, setScrubbing] = useState(false)
  const [hoverInfo, setHoverInfo] = useState<{ x: number; t: number } | null>(null)
  const [speed, setSpeed] = useState(1)
  const [speedOpen, setSpeedOpen] = useState(false)
  const [muted, setMuted] = useState(false)
  const [volume, setVolume] = useState(1)
  const [fullscreen, setFullscreen] = useState(false)
  const [started, setStarted] = useState(autoPlay)
  const [waiting, setWaiting] = useState(false)

  const controlsVisible = !playing || scrubbing || speedOpen || waiting

  /* keep React in sync with the element */
  useEffect(() => {
    const v = videoRef.current
    if (!v) return
    v.playbackRate = speed
  }, [speed])

  useEffect(() => {
    const v = videoRef.current
    if (!v) return
    const onTime = () => {
      if (!scrubbing) setTime(v.currentTime)
      if (v.buffered.length > 0) {
        setBuffered(v.buffered.end(v.buffered.length - 1))
      }
    }
    const onMeta = () => setDuration(v.duration || 0)
    const onEnd = () => setPlaying(false)
    const onPlay = () => { setPlaying(true); setStarted(true) }
    const onPause = () => setPlaying(false)
    const onWait = () => setWaiting(true)
    const onGoing = () => setWaiting(false)
    v.addEventListener('timeupdate', onTime)
    v.addEventListener('progress', onTime)
    v.addEventListener('loadedmetadata', onMeta)
    v.addEventListener('durationchange', onMeta)
    v.addEventListener('ended', onEnd)
    v.addEventListener('play', onPlay)
    v.addEventListener('pause', onPause)
    v.addEventListener('waiting', onWait)
    v.addEventListener('playing', onGoing)
    return () => {
      v.removeEventListener('timeupdate', onTime)
      v.removeEventListener('progress', onTime)
      v.removeEventListener('loadedmetadata', onMeta)
      v.removeEventListener('durationchange', onMeta)
      v.removeEventListener('ended', onEnd)
      v.removeEventListener('play', onPlay)
      v.removeEventListener('pause', onPause)
      v.removeEventListener('waiting', onWait)
      v.removeEventListener('playing', onGoing)
    }
  }, [scrubbing])

  useEffect(() => {
    function onFs() {
      setFullscreen(document.fullscreenElement === wrapRef.current)
    }
    document.addEventListener('fullscreenchange', onFs)
    return () => document.removeEventListener('fullscreenchange', onFs)
  }, [])

  const togglePlay = useCallback(() => {
    const v = videoRef.current
    if (!v) return
    if (v.paused) {
      v.play().catch(() => {})
    } else {
      v.pause()
    }
  }, [])

  const skip = useCallback((delta: number) => {
    const v = videoRef.current
    if (!v) return
    v.currentTime = Math.min(Math.max(0, v.currentTime + delta), v.duration || 0)
    setTime(v.currentTime)
  }, [])

  const seekTo = useCallback((t: number) => {
    const v = videoRef.current
    if (!v) return
    const clamped = Math.min(Math.max(0, t), v.duration || 0)
    v.currentTime = clamped
    setTime(clamped)
  }, [])

  /* seek bar: click + drag scrubbing (YouTube-style) */
  function barPos(e: { clientX: number }): number {
    const bar = barRef.current
    if (!bar) return 0
    const rect = bar.getBoundingClientRect()
    const ratio = Math.min(Math.max((e.clientX - rect.left) / rect.width, 0), 1)
    return ratio * (videoRef.current?.duration || 0)
  }

  function onBarDown(e: React.MouseEvent) {
    e.preventDefault()
    setScrubbing(true)
    seekTo(barPos(e))
    const move = (ev: MouseEvent) => {
      const t = barPos(ev)
      seekTo(t)
      setTime(t)
    }
    const up = () => {
      setScrubbing(false)
      window.removeEventListener('mousemove', move)
      window.removeEventListener('mouseup', up)
    }
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
  }

  function onBarHover(e: React.MouseEvent) {
    const bar = barRef.current
    if (!bar) return
    const rect = bar.getBoundingClientRect()
    const x = Math.min(Math.max(e.clientX - rect.left, 0), rect.width)
    setHoverInfo({ x, t: (x / rect.width) * (videoRef.current?.duration || 0) })
  }

  async function toggleFullscreen() {
    const wrap = wrapRef.current
    if (!wrap) return
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen()
      } else {
        await wrap.requestFullscreen()
      }
    } catch { /* not supported */ }
  }

  const pct = duration > 0 ? (time / duration) * 100 : 0
  const bufPct = duration > 0 ? Math.min((buffered / duration) * 100, 100) : 0

  return (
    <div
      ref={wrapRef}
      data-testid="retro-video-player"
      style={{
        position: 'relative',
        width: '100%',
        aspectRatio: '16/9',
        background: '#000',
        overflow: 'hidden',
        userSelect: 'none',
      }}
      onMouseLeave={() => setHoverInfo(null)}
    >
      <video
        ref={videoRef}
        src={src}
        poster={poster}
        autoPlay={autoPlay}
        playsInline
        preload="metadata"
        onClick={togglePlay}
        style={{ width: '100%', height: '100%', objectFit: 'contain', display: 'block', cursor: 'pointer' }}
        aria-label={title || 'Video player'}
      />

      {/* big center play badge before the first play (old YouTube red button) */}
      {!started && (
        <button
          onClick={togglePlay}
          aria-label="Play video"
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'transparent',
            border: 'none',
            cursor: 'pointer',
          }}
        >
          <span
            style={{
              width: 64,
              height: 64,
              borderRadius: '50%',
              background: 'rgba(225,35,26,.92)',
              border: '3px solid #fff',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 2px 10px rgba(0,0,0,.55)',
            }}
          >
            <svg width="26" height="26" viewBox="0 0 20 20"><path d="M6 3 L6 17 L17 10 Z" fill="#fff" /></svg>
          </span>
        </button>
      )}

      {/* buffering spinner */}
      {waiting && started && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
          <span
            style={{
              width: 34,
              height: 34,
              border: '4px solid rgba(255,255,255,.25)',
              borderTopColor: '#e1231a',
              borderRadius: '50%',
              animation: 'rb-spin .8s linear infinite',
            }}
          />
        </div>
      )}

      {/* control chrome */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(180deg, rgba(10,14,20,0) 0%, rgba(10,14,20,.82) 60%)',
          padding: '18px 8px 6px',
          opacity: controlsVisible ? 1 : 0,
          transition: 'opacity .2s',
          pointerEvents: controlsVisible ? 'auto' : 'none',
        }}
        onMouseEnter={() => {
          if (hideTimer.current) clearTimeout(hideTimer.current)
        }}
      >
        {/* seek bar */}
        <div
          ref={barRef}
          onMouseDown={onBarDown}
          onMouseMove={onBarHover}
          role="slider"
          aria-label="Seek bar"
          aria-valuemin={0}
          aria-valuemax={Math.round(duration)}
          aria-valuenow={Math.round(time)}
          aria-valuetext={`${fmtTime(time)} of ${fmtTime(duration)}`}
          style={{
            position: 'relative',
            height: 12,
            cursor: 'pointer',
            margin: '0 4px',
          }}
        >
          {/* hover timestamp bubble */}
          {hoverInfo !== null && duration > 0 && (
            <span
              style={{
                position: 'absolute',
                left: hoverInfo.x,
                top: -22,
                transform: 'translateX(-50%)',
                background: '#1c2733',
                color: '#fff',
                fontSize: 10,
                fontFamily: "'Courier New', monospace",
                padding: '1px 6px',
                borderRadius: 3,
                border: '1px solid #3d4a5a',
                whiteSpace: 'nowrap',
                pointerEvents: 'none',
                zIndex: 3,
              }}
            >
              {fmtTime(hoverInfo.t)}
            </span>
          )}
          {/* track */}
          <div style={{ position: 'absolute', left: 0, right: 0, top: 5, height: 4, background: 'rgba(255,255,255,.22)' }} />
          {/* buffered */}
          <div style={{ position: 'absolute', left: 0, top: 5, height: 4, width: `${bufPct}%`, background: 'rgba(255,255,255,.38)' }} />
          {/* THE RED LINE */}
          <div style={{ position: 'absolute', left: 0, top: 5, height: 4, width: `${pct}%`, background: '#e1231a' }} />
          {/* playhead knob */}
          <div
            style={{
              position: 'absolute',
              left: `calc(${pct}% - 6px)`,
              top: 0,
              width: 12,
              height: 12,
              borderRadius: '50%',
              background: '#e1231a',
              border: '2px solid #fff',
              boxShadow: '0 1px 3px rgba(0,0,0,.5)',
              opacity: scrubbing || hoverInfo !== null ? 1 : 0.9,
            }}
          />
        </div>

        {/* buttons row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 2, marginTop: 3, flexWrap: 'wrap' }}>
          <CtlButton onClick={togglePlay} label={playing ? 'Pause' : 'Play'}>
            {playing ? (
              <svg width="13" height="13" viewBox="0 0 16 16"><rect x="3" y="2" width="4" height="12" fill="#fff" /><rect x="9" y="2" width="4" height="12" fill="#fff" /></svg>
            ) : (
              <svg width="13" height="13" viewBox="0 0 16 16"><path d="M4 2 L4 14 L14 8 Z" fill="#fff" /></svg>
            )}
          </CtlButton>

          <CtlButton onClick={() => skip(-10)} label="Back 10 seconds">
            <span style={{ display: 'flex', alignItems: 'center' }}>
              <svg width="13" height="13" viewBox="0 0 16 16"><path d="M9 3 L3 8 L9 13 Z M15 3 L9 8 L15 13 Z" fill="#fff" /></svg>
              <span style={{ fontSize: 8, color: '#fff', marginLeft: 2 }}>10</span>
            </span>
          </CtlButton>

          <CtlButton onClick={() => skip(10)} label="Forward 10 seconds">
            <span style={{ display: 'flex', alignItems: 'center' }}>
              <span style={{ fontSize: 8, color: '#fff', marginRight: 2 }}>10</span>
              <svg width="13" height="13" viewBox="0 0 16 16"><path d="M7 3 L13 8 L7 13 Z M1 3 L7 8 L1 13 Z" fill="#fff" /></svg>
            </span>
          </CtlButton>

          {/* timestamp — jump-readout like YouTube */}
          <span
            style={{
              fontFamily: "'Courier New', monospace",
              fontSize: 11,
              color: '#fff',
              margin: '0 8px',
              textShadow: '0 1px 2px rgba(0,0,0,.8)',
            }}
            aria-live="off"
          >
            {fmtTime(time)} / {fmtTime(duration)}
          </span>

          <span style={{ flex: 1 }} />

          {/* speed menu */}
          <div style={{ position: 'relative' }}>
            <button
              onClick={() => setSpeedOpen((o) => !o)}
              aria-label="Playback speed"
              aria-expanded={speedOpen}
              style={{
                background: speed !== 1 ? 'rgba(225,35,26,.75)' : 'rgba(255,255,255,.12)',
                border: '1px solid rgba(255,255,255,.25)',
                borderRadius: 3,
                color: '#fff',
                fontSize: 10,
                padding: '3px 7px',
                cursor: 'pointer',
              }}
            >
              {speed}×
            </button>
            {speedOpen && (
              <div
                style={{
                  position: 'absolute',
                  bottom: 'calc(100% + 6px)',
                  right: 0,
                  background: '#1c2733',
                  border: '1px solid #3d4a5a',
                  borderRadius: 4,
                  padding: 4,
                  display: 'grid',
                  gap: 2,
                  zIndex: 5,
                  boxShadow: '0 3px 10px rgba(0,0,0,.5)',
                }}
              >
                {SPEEDS.map((s) => (
                  <button
                    key={s}
                    onClick={() => {
                      setSpeed(s)
                      setSpeedOpen(false)
                      if (videoRef.current) videoRef.current.playbackRate = s
                    }}
                    style={{
                      background: s === speed ? '#e1231a' : 'transparent',
                      color: '#fff',
                      border: 'none',
                      borderRadius: 3,
                      fontSize: 10,
                      padding: '3px 14px',
                      cursor: 'pointer',
                      textAlign: 'left',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    {s === 1 ? 'Normal' : `${s}×`}
                  </button>
                ))}
              </div>
            )}
          </div>

          <CtlButton
            onClick={() => {
              const v = videoRef.current
              if (!v) return
              v.muted = !v.muted
              setMuted(v.muted)
            }}
            label={muted ? 'Unmute' : 'Mute'}
          >
            {muted ? (
              <svg width="13" height="13" viewBox="0 0 16 16"><path d="M2 6h3l4-3v10l-4-3H2z" fill="#fff" /><path d="M11 5l4 6M15 5l-4 6" stroke="#e1231a" strokeWidth="1.6" /></svg>
            ) : (
              <svg width="13" height="13" viewBox="0 0 16 16"><path d="M2 6h3l4-3v10l-4-3H2z" fill="#fff" /><path d="M11.5 5.5a4 4 0 010 5" stroke="#fff" strokeWidth="1.4" fill="none" /></svg>
            )}
          </CtlButton>

          {/* volume slider */}
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={muted ? 0 : volume}
            onChange={(e) => {
              const nv = parseFloat(e.target.value)
              setVolume(nv)
              setMuted(nv === 0)
              if (videoRef.current) {
                videoRef.current.volume = nv
                videoRef.current.muted = nv === 0
              }
            }}
            aria-label="Volume"
            style={{ width: 64, accentColor: '#e1231a', height: 4, cursor: 'pointer' }}
          />

          <CtlButton onClick={toggleFullscreen} label="Fullscreen">
            <svg width="12" height="12" viewBox="0 0 16 16"><path d="M2 6V2h4M10 2h4v4M14 10v4h-4M6 14H2v-4" stroke="#fff" strokeWidth="1.8" fill="none" /></svg>
          </CtlButton>
        </div>
      </div>
    </div>
  )
}

function CtlButton({ children, onClick, label }: { children: React.ReactNode; onClick: () => void; label: string }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      style={{
        background: 'transparent',
        border: 'none',
        padding: '4px 6px',
        cursor: 'pointer',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: 3,
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = 'rgba(255,255,255,.14)'
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = 'transparent'
      }}
    >
      {children}
    </button>
  )
}
