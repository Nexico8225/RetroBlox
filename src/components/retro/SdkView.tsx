'use client'

import { useState } from 'react'

const V_TAG = 'v11.1'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=11.1'

export function SdkView() {
  const [copied, setCopied] = useState(false)

  const handleCopyLink = () => {
    navigator.clipboard?.writeText(window.location.origin + ZIP_URL)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div style={{ maxWidth: 720, margin: '24px auto 60px', padding: '0 16px' }}>
      {/* Premium Download Container */}
      <div
        className="rb-box"
        style={{
          background: '#ffffff',
          borderRadius: 16,
          border: '1px solid #d2dbe5',
          boxShadow: '0 12px 36px rgba(18, 38, 63, 0.08), 0 2px 6px rgba(0,0,0,0.04)',
          overflow: 'hidden',
          transition: 'box-shadow 0.2s ease',
        }}
      >
        {/* Top Accent Gradient Bar */}
        <div
          style={{
            height: 6,
            background: 'linear-gradient(90deg, #00A2FF 0%, #00d26a 50%, #0070b6 100%)',
          }}
        />

        <div style={{ padding: '44px 32px 36px', textAlign: 'center' }}>
          {/* Godot App Icon with Ambient Glow */}
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 88,
              height: 88,
              borderRadius: 22,
              background: 'linear-gradient(135deg, #1f374d 0%, #0e2233 100%)',
              border: '2px solid rgba(255, 255, 255, 0.15)',
              boxShadow: '0 10px 24px rgba(0, 112, 182, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.2)',
              marginBottom: 20,
              position: 'relative',
            }}
          >
            <img
              src="/icons/godot-icon.svg"
              alt="Godot Engine"
              width={54}
              height={54}
              style={{ display: 'block', filter: 'drop-shadow(0 3px 6px rgba(0,0,0,0.4))' }}
              draggable={false}
            />
          </div>

          {/* Heading */}
          <h1
            style={{
              fontSize: 32,
              fontWeight: 800,
              color: '#13283b',
              margin: '0 0 10px 0',
              letterSpacing: '-0.5px',
              fontFamily: 'var(--rb-display, "Source Sans Pro", -apple-system, sans-serif)',
            }}
          >
            RetroBlox Player &amp; SDK
          </h1>

          {/* Subtitle */}
          <p
            style={{
              fontSize: 16,
              color: '#5b6f82',
              margin: '0 auto 28px',
              maxWidth: 480,
              lineHeight: 1.55,
            }}
          >
            The official Godot sandbox client. Play multiplayer places online and visually
            edit your map, UI, and player avatar directly with Godot scene nodes.
          </p>

          {/* Feature Badges */}
          <div
            style={{
              display: 'flex',
              justifyContent: 'center',
              flexWrap: 'wrap',
              gap: 8,
              marginBottom: 32,
            }}
          >
            {[
              '✓ Visual Node Scenes',
              '✓ Editable Map & UI',
              '✓ R6 Character Rig',
            ].map((badge) => (
              <span
                key={badge}
                style={{
                  fontSize: 12,
                  fontWeight: 600,
                  color: '#0e527f',
                  background: '#e8f4fc',
                  border: '1px solid #c2e0f4',
                  borderRadius: 20,
                  padding: '4px 12px',
                }}
              >
                {badge}
              </span>
            ))}
          </div>

          {/* Prominent Primary Download Action */}
          <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}>
            <a
              href={ZIP_URL}
              download="retroblox-godot-player.zip"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 14,
                textDecoration: 'none',
                background: 'linear-gradient(180deg, #02b757 0%, #018f43 100%)',
                color: '#ffffff',
                border: '1px solid #017a39',
                borderRadius: 12,
                padding: '16px 36px',
                fontSize: 17,
                fontWeight: 700,
                boxShadow: '0 4px 0 #016830, 0 10px 24px rgba(2, 183, 87, 0.35)',
                transition: 'all 0.12s ease',
                cursor: 'pointer',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.filter = 'brightness(1.08)'
                e.currentTarget.style.transform = 'translateY(-2px)'
                e.currentTarget.style.boxShadow = '0 6px 0 #016830, 0 14px 28px rgba(2, 183, 87, 0.45)'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.filter = 'none'
                e.currentTarget.style.transform = 'translateY(0)'
                e.currentTarget.style.boxShadow = '0 4px 0 #016830, 0 10px 24px rgba(2, 183, 87, 0.35)'
              }}
            >
              <svg
                width={24}
                height={24}
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2.4}
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                <polyline points="7 10 12 15 17 10" />
                <line x1="12" y1="15" x2="12" y2="3" />
              </svg>
              <span>Download SDK ({V_TAG}) — .zip</span>
            </a>
          </div>

          {/* Mirror & Copy Actions */}
          <div
            style={{
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              gap: 12,
              fontSize: 13,
              color: '#657788',
            }}
          >
            <span>~4.5 MB</span>
            <span>•</span>
            <button
              onClick={handleCopyLink}
              style={{
                background: 'none',
                border: 'none',
                color: copied ? '#029446' : '#0070b6',
                cursor: 'pointer',
                fontSize: 13,
                fontWeight: 600,
                padding: 0,
                transition: 'color 0.15s ease',
              }}
            >
              {copied ? '✓ Direct Link Copied!' : 'Copy Direct Link'}
            </button>
            <span>•</span>
            <span>Compatible with Godot 4.5+</span>
          </div>
        </div>

        {/* 3-Step Quick Start Footer */}
        <div
          style={{
            borderTop: '1px solid #e2e8f0',
            background: '#f8fafc',
            padding: '22px 28px',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
            gap: 16,
          }}
        >
          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: '50%',
                background: '#0070b6',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 14,
                flexShrink: 0,
              }}
            >
              1
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Extract Zip</div>
              <div style={{ fontSize: 12, color: '#64748b' }}>Unpack into your projects folder.</div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: '50%',
                background: '#0070b6',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 14,
                flexShrink: 0,
              }}
            >
              2
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Open in Godot</div>
              <div style={{ fontSize: 12, color: '#64748b' }}>Import project.godot in 4.5+.</div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: '50%',
                background: '#029446',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 14,
                flexShrink: 0,
              }}
            >
              3
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Play &amp; Edit</div>
              <div style={{ fontSize: 12, color: '#64748b' }}>Press F5 to play or edit nodes!</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
