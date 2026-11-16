'use client'

/* RetroBlox Universal Game Launcher Page
   Dedicated download page for the RetroBlox Windows Client / Launcher.
   Strictly NO EMOJIS. Classic Roblox client installation layout. */

import { useState } from 'react'
import Link from 'next/link'

const LAUNCHER_EXE_URL = '/downloads/RetroBloxLauncher.exe'
const LAUNCHER_ZIP_URL = '/downloads/RetroBlox_SDK.zip'

export function LauncherView() {
  const [copiedLink, setCopiedLink] = useState(false)

  const handleCopyLink = () => {
    if (typeof window !== 'undefined') {
      navigator.clipboard?.writeText(window.location.origin + LAUNCHER_EXE_URL)
      setCopiedLink(true)
      setTimeout(() => setCopiedLink(false), 2000)
    }
  }

  return (
    <div style={{ maxWidth: 760, margin: '20px auto 60px', padding: '0 16px' }}>
      {/* Main Launcher Banner Container */}
      <div
        className="rb-box"
        style={{
          background: '#ffffff',
          borderRadius: 8,
          border: '1px solid #c2d1df',
          boxShadow: '0 4px 16px rgba(18, 38, 63, 0.08)',
          overflow: 'hidden',
          marginBottom: 20,
        }}
      >
        <div
          style={{
            height: 5,
            background: 'linear-gradient(90deg, #1e8449 0%, #2ecc71 50%, #1e8449 100%)',
          }}
        />

        <div style={{ padding: '36px 28px 28px', textAlign: 'center' }}>
          {/* RetroBlox Logo / Client Icon */}
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 76,
              height: 76,
              borderRadius: 14,
              background: 'linear-gradient(135deg, #c81c14 0%, #8a130e 100%)',
              border: '2px solid rgba(255, 255, 255, 0.25)',
              boxShadow: '0 6px 18px rgba(200, 28, 20, 0.28)',
              marginBottom: 16,
              color: '#ffffff',
              fontWeight: 900,
              fontSize: 38,
              fontFamily: 'Impact, "Arial Black", sans-serif',
            }}
          >
            R
          </div>

          <h1
            style={{
              fontSize: 26,
              fontWeight: 800,
              color: '#13283b',
              margin: '0 0 8px 0',
              fontFamily: 'var(--rb-display, "Source Sans Pro", -apple-system, sans-serif)',
            }}
          >
            RetroBlox Game Launcher for Windows
          </h1>

          <p
            style={{
              fontSize: 14,
              color: '#5b6f82',
              margin: '0 auto 20px',
              maxWidth: 560,
              lineHeight: 1.5,
            }}
          >
            Download the official RetroBlox desktop game client to play any game directly from
            the website. Features 1-click browser join (retroblox://), high-speed RAM streaming,
            and authentic multiplayer gameplay.
          </p>

          {/* Highlights */}
          <div
            style={{
              display: 'flex',
              justifyContent: 'center',
              flexWrap: 'wrap',
              gap: 6,
              marginBottom: 24,
            }}
          >
            {[
              '[Windows 10 / 11 Compatible]',
              '[1-Click Browser Join]',
              '[In-RAM Fast Streaming]',
              '[Toaster / Low-Spec Support]',
              '[In-Game Tix Store & Inventory]',
              '[Instant Client Auto-Updates]',
            ].map((feature) => (
              <span
                key={feature}
                style={{
                  fontSize: 11,
                  fontWeight: 600,
                  color: '#155724',
                  background: '#d4edda',
                  border: '1px solid #c3e6cb',
                  borderRadius: 4,
                  padding: '3px 8px',
                }}
              >
                {feature}
              </span>
            ))}
          </div>

          {/* Download Launcher Button */}
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
              href={LAUNCHER_EXE_URL}
              download="RetroBloxLauncher.exe"
              className="rb-btn rb-btn-green"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 8,
                textDecoration: 'none',
                padding: '12px 26px',
                fontSize: 15,
                fontWeight: 700,
              }}
            >
              <span>Download Launcher (Windows .exe)</span>
            </a>

            <Link
              href="/games"
              className="rb-btn rb-btn-blue"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 8,
                textDecoration: 'none',
                padding: '12px 20px',
                fontSize: 13,
                fontWeight: 700,
              }}
            >
              <span>Browse Games to Play</span>
            </Link>
          </div>

          <div
            style={{
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              gap: 10,
              fontSize: 11.5,
              color: '#657788',
            }}
          >
            <span>Windows Standalone Executable</span>
            <span>|</span>
            <button
              onClick={handleCopyLink}
              style={{
                background: 'none',
                border: 'none',
                color: copiedLink ? '#029446' : '#0070b6',
                cursor: 'pointer',
                fontSize: 11.5,
                fontWeight: 600,
                padding: 0,
              }}
            >
              {copiedLink ? 'Link Copied!' : 'Copy Direct Link'}
            </button>
            <span>|</span>
            <Link href="/sdk" className="rb-link">
              Want to create games? Visit the SDK page
            </Link>
          </div>
        </div>

        {/* 3 Steps to Play */}
        <div
          style={{
            borderTop: '1px solid #d2dbe5',
            background: '#f8fafc',
            padding: '18px 24px',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
            gap: 14,
          }}
        >
          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 24,
                height: 24,
                borderRadius: '50%',
                background: '#1e8449',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 11,
                flexShrink: 0,
                marginTop: 2,
              }}
            >
              1
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Download &amp; Run</div>
              <div style={{ fontSize: 11, color: '#64748b', lineHeight: 1.4 }}>
                Click Download Launcher and run RetroBloxLauncher.exe. No complex installation required.
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 24,
                height: 24,
                borderRadius: '50%',
                background: '#1e8449',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 11,
                flexShrink: 0,
                marginTop: 2,
              }}
            >
              2
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Register Protocol</div>
              <div style={{ fontSize: 11, color: '#64748b', lineHeight: 1.4 }}>
                The launcher self-registers the retroblox:// URL protocol on your PC so web buttons can launch games.
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 24,
                height: 24,
                borderRadius: '50%',
                background: '#1e8449',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 11,
                flexShrink: 0,
                marginTop: 2,
              }}
            >
              3
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 13 }}>Click Play &amp; Enjoy</div>
              <div style={{ fontSize: 11, color: '#64748b', lineHeight: 1.4 }}>
                Go to any game on RetroBlox and hit the green Play button. The launcher streams the world into RAM and launches immediately!
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Troubleshooting & System Info */}
      <div className="rb-box" style={{ padding: 16 }}>
        <div className="rb-panel-head" style={{ margin: '-16px -16px 14px -16px' }}>
          <span>Launcher Information &amp; FAQ</span>
        </div>

        <div style={{ display: 'grid', gap: 10, fontSize: 11.5, color: '#4a5b6d' }}>
          <div>
            <b>System Requirements:</b> Windows 10 or Windows 11 (64-bit), 2 GB RAM, and any DirectX 11 / OpenGL compatible graphics card.
          </div>
          <div>
            <b>Browser Integration:</b> When you click &quot;Play&quot; on a game, your browser will ask for permission to open RetroBlox Launcher. Check &quot;Always allow&quot; for instant 1-click joining.
          </div>
          <div>
            <b>Trouble Launching?</b> If the browser does not recognize the link, run RetroBloxLauncher.exe directly once to refresh the protocol handler.
          </div>
        </div>
      </div>
    </div>
  )
}
