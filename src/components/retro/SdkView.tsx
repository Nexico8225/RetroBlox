'use client'

import { useState } from 'react'
import Link from 'next/link'

const V_TAG = 'v2.0'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=2.0'
const COLORWORLD_ZIP_URL = '/godot/colorworld-godot-game.zip'

export function SdkView() {
  const [copiedSdk, setCopiedSdk] = useState(false)
  const [copiedCw, setCopiedCw] = useState(false)
  const [activeTab, setActiveTab] = useState<'all' | 'sdk' | 'colorworld'>('all')

  const handleCopySdkLink = () => {
    navigator.clipboard?.writeText(window.location.origin + ZIP_URL)
    setCopiedSdk(true)
    setTimeout(() => setCopiedSdk(false), 2000)
  }

  const handleCopyCwLink = () => {
    navigator.clipboard?.writeText(window.location.origin + COLORWORLD_ZIP_URL)
    setCopiedCw(true)
    setTimeout(() => setCopiedCw(false), 2000)
  }

  return (
    <div style={{ maxWidth: 740, margin: '24px auto 60px', padding: '0 16px' }}>
      {/* Category Filter Pills */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          gap: 10,
          marginBottom: 24,
          flexWrap: 'wrap',
        }}
      >
        <button
          onClick={() => setActiveTab('all')}
          style={{
            padding: '7px 16px',
            fontSize: 13,
            fontWeight: 700,
            borderRadius: 20,
            cursor: 'pointer',
            transition: 'all 0.15s ease',
            border: activeTab === 'all' ? '1px solid #0070b6' : '1px solid #d2dbe5',
            background: activeTab === 'all' ? '#0070b6' : '#ffffff',
            color: activeTab === 'all' ? '#ffffff' : '#4a5b6d',
            boxShadow: activeTab === 'all' ? '0 2px 8px rgba(0, 112, 182, 0.25)' : 'none',
          }}
        >
          All Downloads (2)
        </button>
        <button
          onClick={() => setActiveTab('sdk')}
          style={{
            padding: '7px 16px',
            fontSize: 13,
            fontWeight: 700,
            borderRadius: 20,
            cursor: 'pointer',
            transition: 'all 0.15s ease',
            border: activeTab === 'sdk' ? '1px solid #0070b6' : '1px solid #d2dbe5',
            background: activeTab === 'sdk' ? '#0070b6' : '#ffffff',
            color: activeTab === 'sdk' ? '#ffffff' : '#4a5b6d',
            boxShadow: activeTab === 'sdk' ? '0 2px 8px rgba(0, 112, 182, 0.25)' : 'none',
          }}
        >
          🚀 RetroBlox SDK &amp; Launcher
        </button>
        <button
          onClick={() => setActiveTab('colorworld')}
          style={{
            padding: '7px 16px',
            fontSize: 13,
            fontWeight: 700,
            borderRadius: 20,
            cursor: 'pointer',
            transition: 'all 0.15s ease',
            border: activeTab === 'colorworld' ? '1px solid #ff5d4d' : '1px solid #d2dbe5',
            background: activeTab === 'colorworld' ? '#ff5d4d' : '#ffffff',
            color: activeTab === 'colorworld' ? '#ffffff' : '#4a5b6d',
            boxShadow: activeTab === 'colorworld' ? '0 2px 8px rgba(255, 93, 77, 0.25)' : 'none',
          }}
        >
          🎨 ColorWorld 3D Game
        </button>
      </div>

      {/* ========================================================= */}
      {/* 1. RETROBLOX PLAYER & SDK v2.0 CONTAINER                  */}
      {/* ========================================================= */}
      {(activeTab === 'all' || activeTab === 'sdk') && (
        <div
          className="rb-box"
          style={{
            background: '#ffffff',
            borderRadius: 16,
            border: '1px solid #d2dbe5',
            boxShadow: '0 12px 36px rgba(18, 38, 63, 0.08), 0 2px 6px rgba(0,0,0,0.04)',
            overflow: 'hidden',
            marginBottom: activeTab === 'all' ? 36 : 0,
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

          <div style={{ padding: '40px 32px 32px', textAlign: 'center' }}>
            {/* Godot App Icon with Ambient Glow */}
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: 84,
                height: 84,
                borderRadius: 22,
                background: 'linear-gradient(135deg, #1f374d 0%, #0e2233 100%)',
                border: '2px solid rgba(255, 255, 255, 0.15)',
                boxShadow: '0 10px 24px rgba(0, 112, 182, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.2)',
                marginBottom: 18,
                position: 'relative',
              }}
            >
              <img
                src="/icons/godot-icon.svg"
                alt="Godot Engine"
                width={50}
                height={50}
                style={{ display: 'block', filter: 'drop-shadow(0 3px 6px rgba(0,0,0,0.4))' }}
                draggable={false}
              />
            </div>

            {/* Heading */}
            <h1
              style={{
                fontSize: 30,
                fontWeight: 800,
                color: '#13283b',
                margin: '0 0 10px 0',
                letterSpacing: '-0.5px',
                fontFamily: 'var(--rb-display, "Source Sans Pro", -apple-system, sans-serif)',
              }}
            >
              RetroBlox Player &amp; SDK v2.0
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 15,
                color: '#5b6f82',
                margin: '0 auto 24px',
                maxWidth: 520,
                lineHeight: 1.55,
              }}
            >
              The official Godot sandbox client and creator studio. Features 1-click web launching,
              RAM streaming for .rbxpkg packages, in-game Tix GamePasses, built-in toolbox, and visual node editing.
            </p>

            {/* Feature Badges */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'center',
                flexWrap: 'wrap',
                gap: 8,
                marginBottom: 28,
              }}
            >
              {[
                '✓ 1-Click Browser Launch (retroblox://)',
                '✓ In-RAM .rbxpkg Streaming',
                '✓ In-Game Tix Spending & GamePasses',
                '✓ Studio Toolbox & Built-in Assets',
                '✓ R6 Rig & 21 Classic Gears',
                '✓ Godot 4.5+ Compatible',
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
            <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 14 }}>
              <a
                href={ZIP_URL}
                download="retroblox-godot-player.zip"
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 12,
                  textDecoration: 'none',
                  background: 'linear-gradient(180deg, #02b757 0%, #018f43 100%)',
                  color: '#ffffff',
                  border: '1px solid #017a39',
                  borderRadius: 12,
                  padding: '14px 32px',
                  fontSize: 16,
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
                  width={22}
                  height={22}
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
                <span>Download SDK &amp; Launcher ({V_TAG}) — .zip</span>
              </a>
            </div>

            {/* Mirror & Copy Actions */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                gap: 12,
                fontSize: 12,
                color: '#657788',
              }}
            >
              <span>~6.5 MB</span>
              <span>•</span>
              <button
                onClick={handleCopySdkLink}
                style={{
                  background: 'none',
                  border: 'none',
                  color: copiedSdk ? '#029446' : '#0070b6',
                  cursor: 'pointer',
                  fontSize: 12,
                  fontWeight: 600,
                  padding: 0,
                  transition: 'color 0.15s ease',
                }}
              >
                {copiedSdk ? '✓ Direct Link Copied!' : 'Copy Direct Link'}
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
              padding: '20px 26px',
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
              gap: 14,
            }}
          >
            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  background: '#0070b6',
                  color: '#fff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: 13,
                  flexShrink: 0,
                }}
              >
                1
              </div>
              <div>
                <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Extract Zip</div>
                <div style={{ fontSize: 11, color: '#64748b' }}>Unpack into your projects folder.</div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  background: '#0070b6',
                  color: '#fff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: 13,
                  flexShrink: 0,
                }}
              >
                2
              </div>
              <div>
                <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Register Protocol</div>
                <div style={{ fontSize: 11, color: '#64748b' }}>Run register_retroblox_protocol.bat</div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  background: '#029446',
                  color: '#fff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: 13,
                  flexShrink: 0,
                }}
              >
                3
              </div>
              <div>
                <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>1-Click Play &amp; Build</div>
                <div style={{ fontSize: 11, color: '#64748b' }}>Launch games in 1 click or edit in Godot!</div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* 2. COLORWORLD 3D GAME CONTAINER (STANDALONE GODOT KIT)    */}
      {/* ========================================================= */}
      {(activeTab === 'all' || activeTab === 'colorworld') && (
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
          {/* Top Multi-Color Rainbow Accent Bar */}
          <div
            style={{
              height: 6,
              background: 'linear-gradient(90deg, #ff5d4d 0%, #ff9d2e 20%, #ffe14d 40%, #5dd15d 60%, #4dc3ff 80%, #b06dff 100%)',
            }}
          />

          <div style={{ padding: '40px 32px 32px', textAlign: 'center' }}>
            {/* ColorWorld Badge Icon */}
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: 84,
                height: 84,
                borderRadius: 22,
                background: 'linear-gradient(135deg, #2b3947 0%, #172433 100%)',
                border: '2px solid rgba(255, 255, 255, 0.2)',
                boxShadow: '0 10px 24px rgba(255, 93, 77, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.25)',
                marginBottom: 18,
                position: 'relative',
              }}
            >
              <span style={{ fontSize: 40, lineHeight: 1 }} role="img" aria-label="Palette">
                🎨
              </span>
            </div>

            {/* Heading */}
            <h2
              style={{
                fontSize: 30,
                fontWeight: 800,
                color: '#13283b',
                margin: '0 0 10px 0',
                letterSpacing: '-0.5px',
                fontFamily: 'var(--rb-display, "Source Sans Pro", -apple-system, sans-serif)',
              }}
            >
              ColorWorld 3D — Godot Game Kit
            </h2>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 15,
                color: '#5b6f82',
                margin: '0 auto 24px',
                maxWidth: 540,
                lineHeight: 1.55,
              }}
            >
              The standalone 3D painting game. Every world begins pure white with sharp black outlines — hold left
              mouse to splash colors with your brush, orbit to find hidden angles, and paint 100% of the world to win!
              Includes full human-readable Godot source code.
            </p>

            {/* Feature Badges */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'center',
                flexWrap: 'wrap',
                gap: 8,
                marginBottom: 28,
              }}
            >
              {[
                '✓ 3 Built-in Worlds (Village, Robot, Space)',
                '✓ Real-Time 3D Triangle Surface Painting',
                '✓ Community GLB Map Import & Normalizer',
                '✓ 10 Hints per Map & 100% Win State',
                '✓ Orbit Camera & Palette HUD',
                '✓ Full Godot 4.5+ / 4.7 Source Included',
              ].map((badge) => (
                <span
                  key={badge}
                  style={{
                    fontSize: 12,
                    fontWeight: 600,
                    color: '#8c2e00',
                    background: '#fff2ea',
                    border: '1px solid #ffd3bc',
                    borderRadius: 20,
                    padding: '4px 12px',
                  }}
                >
                  {badge}
                </span>
              ))}
            </div>

            {/* Dual Action: Download Standalone Zip + Play in Web Browser */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                gap: 12,
                flexWrap: 'wrap',
                marginBottom: 14,
              }}
            >
              <a
                href={COLORWORLD_ZIP_URL}
                download="colorworld-godot-game.zip"
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 12,
                  textDecoration: 'none',
                  background: 'linear-gradient(180deg, #ff7043 0%, #d84315 100%)',
                  color: '#ffffff',
                  border: '1px solid #bf360c',
                  borderRadius: 12,
                  padding: '14px 28px',
                  fontSize: 16,
                  fontWeight: 700,
                  boxShadow: '0 4px 0 #a32c06, 0 10px 24px rgba(216, 67, 21, 0.35)',
                  transition: 'all 0.12s ease',
                  cursor: 'pointer',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.filter = 'brightness(1.08)'
                  e.currentTarget.style.transform = 'translateY(-2px)'
                  e.currentTarget.style.boxShadow = '0 6px 0 #a32c06, 0 14px 28px rgba(216, 67, 21, 0.45)'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.filter = 'none'
                  e.currentTarget.style.transform = 'translateY(0)'
                  e.currentTarget.style.boxShadow = '0 4px 0 #a32c06, 0 10px 24px rgba(216, 67, 21, 0.35)'
                }}
              >
                <svg
                  width={22}
                  height={22}
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
                <span>Download ColorWorld (.zip)</span>
              </a>

              <Link
                href="/colorworld"
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 10,
                  textDecoration: 'none',
                  background: '#f1f5f9',
                  color: '#1e293b',
                  border: '1px solid #cbd5e1',
                  borderRadius: 12,
                  padding: '14px 24px',
                  fontSize: 16,
                  fontWeight: 700,
                  boxShadow: '0 4px 0 #94a3b8',
                  transition: 'all 0.12s ease',
                  cursor: 'pointer',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = '#e2e8f0'
                  e.currentTarget.style.transform = 'translateY(-2px)'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = '#f1f5f9'
                  e.currentTarget.style.transform = 'translateY(0)'
                }}
              >
                <span>🎮 Play in Browser</span>
              </Link>
            </div>

            {/* Mirror & Copy Actions */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                gap: 12,
                fontSize: 12,
                color: '#657788',
              }}
            >
              <span>~22 KB</span>
              <span>•</span>
              <button
                onClick={handleCopyCwLink}
                style={{
                  background: 'none',
                  border: 'none',
                  color: copiedCw ? '#029446' : '#d84315',
                  cursor: 'pointer',
                  fontSize: 12,
                  fontWeight: 600,
                  padding: 0,
                  transition: 'color 0.15s ease',
                }}
              >
                {copiedCw ? '✓ Direct Link Copied!' : 'Copy Direct Link'}
              </button>
              <span>•</span>
              <span>Open with Godot 4.5+</span>
            </div>
          </div>

          {/* 3-Step Quick Start Footer */}
          <div
            style={{
              borderTop: '1px solid #e2e8f0',
              background: '#f8fafc',
              padding: '20px 26px',
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
              gap: 14,
            }}
          >
            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  background: '#d84315',
                  color: '#fff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: 13,
                  flexShrink: 0,
                }}
              >
                1
              </div>
              <div>
                <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Extract Zip</div>
                <div style={{ fontSize: 11, color: '#64748b' }}>Unpack into your Godot projects folder.</div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  background: '#d84315',
                  color: '#fff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: 13,
                  flexShrink: 0,
                }}
              >
                2
              </div>
              <div>
                <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Open in Godot</div>
                <div style={{ fontSize: 11, color: '#64748b' }}>Import ColorWorld/project.godot in Godot 4.</div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  background: '#029446',
                  color: '#fff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: 13,
                  flexShrink: 0,
                }}
              >
                3
              </div>
              <div>
                <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Paint &amp; Mod</div>
                <div style={{ fontSize: 11, color: '#64748b' }}>Press F5 to paint, or add your own custom 3D maps!</div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
