'use client'

import { FONT_GLYPHS } from '@/lib/retrofont-meta'

/* RetroBlox image font — the letters were cropped from the classic font sheet
   (public/retro/font/A..Z.png). Renders a word as a row of letter sprites.
   Uppercase-only font (like the era); other chars fall back to bold Verdana.
   BRANDING-ONLY by design: header logo, footer brand, auth titles. */

const GLYPHS = FONT_GLYPHS

export function RetroFontText({
  text,
  size = 14,
  style,
  className,
  title,
}: {
  text: string
  /** letter height in px */
  size?: number
  style?: React.CSSProperties
  className?: string
  /** hover/aria text (defaults to the text itself) */
  title?: string
}) {
  const chars = Array.from(text || '')
  return (
    <span
      className={className ? `rb-retrofont ${className}` : 'rb-retrofont'}
      style={{ display: 'inline-flex', alignItems: 'center', flexWrap: 'wrap', lineHeight: 1, ...style }}
      title={title ?? undefined}
      aria-label={text}
      role="img"
    >
      {chars.map((ch, i) => {
        if (ch === ' ') {
          return <span key={i} style={{ display: 'inline-block', width: Math.round(size * 0.28) }} aria-hidden="true" />
        }
        const g = GLYPHS[ch.toUpperCase()]
        if (g === undefined || !/[A-Za-z]/.test(ch)) {
          return (
            <span
              key={i}
              aria-hidden="true"
              style={{ fontWeight: 900, fontSize: Math.round(size * 0.82), lineHeight: 1, margin: `0 ${Math.round(size * 0.04)}px`, color: '#fff' }}
            >
              {ch}
            </span>
          )
        }
        return (
          <img
            key={i}
            src={`/retro/font/${ch.toUpperCase()}.png`}
            alt=""
            aria-hidden="true"
            draggable={false}
            style={{
              height: size,
              width: Math.round(size * g),
              marginRight: Math.round(size * 0.035),
              display: 'inline-block',
              userSelect: 'none',
            }}
          />
        )
      })}
    </span>
  )
}
