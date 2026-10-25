'use client'

import { useState } from 'react'

const V_TAG = 'v16.0'
const ZIP_URL = '/godot/retroblox-godot-player.zip?v=16.0'

export function SdkView() {
  const [copied, setCopied] = useState(false)

  const handleCopyLink = () => {
    navigator.clipboard?.writeText(window.location.origin + ZIP_URL)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div style={{ maxWidth: 880, margin: '14px auto 48px', padding: '0 8px' }}>
      {/* Classic 2008-2011 RetroBlox Banner Box */}
      <div className="rb-box" style={{ marginBottom: 14 }}>
        <div className="rb-panel-head">
          <span>RETROBLOX PLAYER &amp; STUDIO SDK — OFFICIAL CLIENT DOWNLOAD ({V_TAG})</span>
          <span style={{ fontSize: 11, fontWeight: 700, color: '#ffea79' }}>
            GODOT 4.5 / 4.6 / 4.7 COMPATIBLE
          </span>
        </div>

        <div
          style={{
            padding: '20px 22px',
            background: '#ffffff',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
            gap: 20,
            alignItems: 'center',
          }}
        >
          {/* Left Column: Classic Emblem + Description */}
          <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 84,
                height: 84,
                background: 'linear-gradient(180deg, #1b354f 0%, #0f2030 100%)',
                border: '2px solid #4a6b8a',
                boxShadow: 'inset 1px 1px 0 rgba(255,255,255,0.25), 2px 2px 0 rgba(0,0,0,0.2)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                flexShrink: 0,
              }}
            >
              <img
                src="/icons/godot-icon.svg"
                alt="RetroBlox Godot SDK"
                width={54}
                height={54}
                style={{ display: 'block' }}
                draggable={false}
              />
            </div>

            <div>
              <h1
                style={{
                  margin: '0 0 6px 0',
                  fontSize: 22,
                  fontWeight: 800,
                  color: '#0b2540',
                  fontFamily: 'Verdana, Tahoma, Arial, sans-serif',
                  letterSpacing: '-0.2px',
                }}
              >
                RetroBlox Player ({V_TAG})
              </h1>
              <p
                style={{
                  margin: '0 0 10px 0',
                  fontSize: 12,
                  color: '#2c3e50',
                  lineHeight: 1.5,
                  fontFamily: 'Verdana, Tahoma, Arial, sans-serif',
                }}
              >
                Download the complete standalone <b>RetrobloxPlayer</b> client &amp; map kit. Play
                online multiplayer places, chat with <b>/</b>, climb ladders, and build your own
                classic places in Godot&apos;s 3D editor.
              </p>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {[
                  'R6 Character Rig',
                  'Torso-Touch Ladders',
                  'Realistic Ultra Mode',
                  'Moving Platforms & Bricks',
                ].map((tag) => (
                  <span
                    key={tag}
                    style={{
                      fontSize: 11,
                      fontWeight: 700,
                      color: '#093966',
                      background: '#dbeaf7',
                      border: '1px solid #7ea6cc',
                      padding: '2px 7px',
                      fontFamily: 'Verdana, Tahoma, sans-serif',
                    }}
                  >
                    {tag}
                  </span>
                ))}
              </div>
            </div>
          </div>

          {/* Right Column: Classic Beveled Download Box */}
          <div
            style={{
              background: '#eef4fa',
              border: '2px solid #8ba7c2',
              boxShadow: 'inset 1px 1px 0 #ffffff',
              padding: '16px 18px',
              textAlign: 'center',
            }}
          >
            <div
              style={{
                fontSize: 11,
                fontWeight: 700,
                color: '#1b3f63',
                textTransform: 'uppercase',
                marginBottom: 8,
                fontFamily: 'Verdana, Tahoma, sans-serif',
              }}
            >
              Full Client &amp; Editable SDK Package
            </div>

            <a
              href={ZIP_URL}
              download="retroblox-godot-player.zip"
              className="rb-btn rb-btn-green"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 10,
                width: '100%',
                padding: '11px 16px',
                fontSize: 14,
                fontWeight: 800,
                textDecoration: 'none',
                border: '2px solid #005216',
                boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.45), 0 2px 0 #003b0f',
              }}
            >
              <span>▼ DOWNLOAD SDK ({V_TAG}) — .ZIP</span>
            </a>

            <div
              style={{
                marginTop: 10,
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                gap: 8,
                fontSize: 11,
                color: '#3f566d',
                fontFamily: 'Verdana, Tahoma, sans-serif',
              }}
            >
              <span>Archive: retroblox-godot-player.zip</span>
              <span>|</span>
              <button
                onClick={handleCopyLink}
                style={{
                  background: 'none',
                  border: 'none',
                  color: copied ? '#007a28' : '#0055b3',
                  fontWeight: 700,
                  fontSize: 11,
                  textDecoration: 'underline',
                  padding: 0,
                }}
              >
                {copied ? 'Link Copied!' : 'Copy Direct Link'}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Two-Column Classic Info Grid: Quick Start + Built-in Kit Parts */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
          gap: 14,
        }}
      >
        {/* Left Box: 3-Step Installation */}
        <div className="rb-box">
          <div className="rb-panel-head">
            <span>HOW TO INSTALL &amp; PLAY (3 STEPS)</span>
          </div>
          <div style={{ padding: 14, background: '#ffffff' }}>
            {[
              {
                num: '1',
                title: 'Extract retroblox-godot-player.zip',
                desc: 'Unzip the downloaded folder anywhere on your computer.',
              },
              {
                num: '2',
                title: 'Import project.godot in Godot 4.5+',
                desc: 'Open Godot Engine, click Import, and select project.godot inside the folder.',
              },
              {
                num: '3',
                title: 'Press F5 to Play or Open scenes/game.tscn',
                desc: 'Log in with your RetroBlox account or edit scenes/game.tscn to build your own map!',
              },
            ].map((step, i) => (
              <div
                key={step.num}
                style={{
                  display: 'flex',
                  gap: 12,
                  alignItems: 'flex-start',
                  padding: '9px 10px',
                  background: i % 2 === 0 ? '#f3f7fb' : '#ffffff',
                  border: '1px solid #c5d5e5',
                  marginBottom: i < 2 ? 8 : 0,
                }}
              >
                <div
                  style={{
                    width: 24,
                    height: 24,
                    background: '#0d69ac',
                    border: '2px solid #073e68',
                    color: '#ffffff',
                    fontWeight: 800,
                    fontSize: 12,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                    fontFamily: 'Verdana, sans-serif',
                  }}
                >
                  {step.num}
                </div>
                <div>
                  <div
                    style={{
                      fontWeight: 700,
                      fontSize: 12,
                      color: '#0b2540',
                      fontFamily: 'Verdana, sans-serif',
                    }}
                  >
                    {step.title}
                  </div>
                  <div
                    style={{
                      fontSize: 11,
                      color: '#465c70',
                      marginTop: 2,
                      fontFamily: 'Verdana, sans-serif',
                    }}
                  >
                    {step.desc}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Right Box: Interactive Bricks & Mechanics Reference */}
        <div className="rb-box">
          <div className="rb-panel-head">
            <span>INCLUDED KIT BRICKS &amp; CONTROLS</span>
          </div>
          <div style={{ padding: 14, background: '#ffffff' }}>
            <table
              style={{
                width: '100%',
                borderCollapse: 'collapse',
                fontSize: 11,
                fontFamily: 'Verdana, Tahoma, sans-serif',
              }}
            >
              <thead>
                <tr style={{ background: '#dfe9f3', color: '#0b2540', textAlign: 'left' }}>
                  <th style={{ padding: '6px 8px', border: '1px solid #9ab4cd' }}>Brick / Node</th>
                  <th style={{ padding: '6px 8px', border: '1px solid #9ab4cd' }}>
                    Group / Inspector Setup
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5', fontWeight: 700 }}>
                    Moveable Platform
                  </td>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5' }}>
                    <code>moving_platform.gd</code> — Point A to Point B, Always Move or Move on
                    Stand, editable Easing
                  </td>
                </tr>
                <tr style={{ background: '#f5f9fc' }}>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5', fontWeight: 700 }}>
                    Damage &amp; Kill Bricks
                  </td>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5' }}>
                    Group <code>&quot;damage&quot;</code> (-20 HP) or <code>&quot;kill&quot;</code>{' '}
                    (Insta-Kill)
                  </td>
                </tr>
                <tr>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5', fontWeight: 700 }}>
                    Heal &amp; Insta-Heal
                  </td>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5' }}>
                    Group <code>&quot;heal&quot;</code> (+15 HP) or{' '}
                    <code>&quot;insta_heal&quot;</code> (100% HP)
                  </td>
                </tr>
                <tr style={{ background: '#f5f9fc' }}>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5', fontWeight: 700 }}>
                    Climbable Ladder
                  </td>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5' }}>
                    Group <code>&quot;ladder&quot;</code> — Climbs when Torso touches, smooth top
                    step-off
                  </td>
                </tr>
                <tr>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5', fontWeight: 700 }}>
                    In-Game Controls
                  </td>
                  <td style={{ padding: '6px 8px', border: '1px solid #c5d5e5' }}>
                    <b>/</b> Open Chat · <b>Shift</b> Shift Lock · <b>ESC</b> Menu · <b>V</b> Voice
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
