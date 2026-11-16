'use client'

/* RetroBlox Creator Studio & SDK Page
   Provides downloads for the official Godot 4.5+ Creator SDK, Studio Plugin,
   Orchestrator Blueprints, Cyclops Level Builder, Custom Nodes, and Toaster Scalability mode.
   Strictly NO EMOJIS. Authentic classic Roblox Studio styling. */

import { useState } from 'react'
import Link from 'next/link'

const SDK_ZIP_URL = '/downloads/RetroBlox_SDK.zip'
const PLAYER_ZIP_URL = '/godot/retroblox-godot-player.zip'

export function SdkView() {
  const [copiedLink, setCopiedLink] = useState(false)

  const handleCopyLink = () => {
    if (typeof window !== 'undefined') {
      navigator.clipboard?.writeText(window.location.origin + SDK_ZIP_URL)
      setCopiedLink(true)
      setTimeout(() => setCopiedLink(false), 2000)
    }
  }

  return (
    <div style={{ maxWidth: 780, margin: '20px auto 60px', padding: '0 16px' }}>
      {/* Main Studio & SDK Container */}
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
        {/* Top Header Accent */}
        <div
          style={{
            height: 5,
            background: 'linear-gradient(90deg, #0d69ac 0%, #1e8449 50%, #0d69ac 100%)',
          }}
        />

        <div style={{ padding: '36px 28px 28px', textAlign: 'center' }}>
          {/* Godot Engine Badge Icon */}
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 76,
              height: 76,
              borderRadius: 14,
              background: 'linear-gradient(135deg, #1f374d 0%, #0e2233 100%)',
              border: '2px solid rgba(255, 255, 255, 0.15)',
              boxShadow: '0 6px 18px rgba(0, 112, 182, 0.25)',
              marginBottom: 16,
            }}
          >
            <img
              src="/icons/godot-icon.svg"
              alt="Godot Engine"
              width={46}
              height={46}
              style={{ display: 'block' }}
              draggable={false}
            />
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
            RetroBlox Creator Studio &amp; SDK
          </h1>

          <p
            style={{
              fontSize: 14,
              color: '#5b6f82',
              margin: '0 auto 20px',
              maxWidth: 580,
              lineHeight: 1.5,
            }}
          >
            The official Godot 4.5+ sandbox creator suite. Build multiplayer worlds with visual
            blueprints, Cyclops blockout tools, 11 plug-and-play nodes, and toaster-optimized editor presets.
          </p>

          {/* Feature Badges - No emojis */}
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
              '[Godot 4.5+ & 4.8 Compatible]',
              '[Orchestrator Visual Blueprints]',
              '[Cyclops Level Builder Dock]',
              '[11 Custom Gameplay Nodes]',
              '[Toaster / Low-Spec Editor Mode]',
              '[Jolt 3D & Box2D Physics]',
              '[Lighting Preset Browser]',
              '[Toolbox UGC Models & Gears]',
            ].map((badge) => (
              <span
                key={badge}
                style={{
                  fontSize: 11,
                  fontWeight: 600,
                  color: '#0e527f',
                  background: '#e8f4fc',
                  border: '1px solid #c2e0f4',
                  borderRadius: 4,
                  padding: '3px 8px',
                }}
              >
                {badge}
              </span>
            ))}
          </div>

          {/* Download Action Buttons */}
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
              href={SDK_ZIP_URL}
              download="RetroBlox_SDK.zip"
              className="rb-btn rb-btn-green"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 8,
                textDecoration: 'none',
                padding: '12px 24px',
                fontSize: 14,
                fontWeight: 700,
              }}
            >
              <span>Download Full SDK Project (.zip)</span>
            </a>

            <a
              href={PLAYER_ZIP_URL}
              download="retroblox-godot-player.zip"
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
              <span>Download Player Engine Only</span>
            </a>
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
            <span>~30.5 MB</span>
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
            <Link href="/launcher" className="rb-link">
              Need the game launcher instead?
            </Link>
          </div>
        </div>

        {/* 4-Step Quick Start Guide */}
        <div
          style={{
            borderTop: '1px solid #d2dbe5',
            background: '#f8fafc',
            padding: '18px 24px',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))',
            gap: 12,
          }}
        >
          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 22,
                height: 22,
                borderRadius: '50%',
                background: '#0d69ac',
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
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 12 }}>Extract SDK</div>
              <div style={{ fontSize: 11, color: '#64748b' }}>Unpack RetroBlox_SDK.zip into any folder.</div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 22,
                height: 22,
                borderRadius: '50%',
                background: '#0d69ac',
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
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 12 }}>Open in Godot</div>
              <div style={{ fontSize: 11, color: '#64748b' }}>In Godot 4.5+ or 4.8, import project.godot.</div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 22,
                height: 22,
                borderRadius: '50%',
                background: '#0d69ac',
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
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 12 }}>Enable Plugin</div>
              <div style={{ fontSize: 11, color: '#64748b' }}>Project Settings -&gt; Plugins -&gt; RetroBlox Studio.</div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <div
              style={{
                width: 22,
                height: 22,
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
              4
            </div>
            <div>
              <div style={{ fontWeight: 700, color: '#13283b', fontSize: 12 }}>Build &amp; Test</div>
              <div style={{ fontSize: 11, color: '#64748b' }}>Press [B] for Builder dock, click +Node, or test in F5!</div>
            </div>
          </div>
        </div>
      </div>

      {/* Built-in Features Grid */}
      <div className="rb-box" style={{ padding: 16 }}>
        <div className="rb-panel-head" style={{ margin: '-16px -16px 14px -16px' }}>
          <span>RetroBlox Studio Tools &amp; Features</span>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 12 }}>
          <div style={{ border: '1px solid #dbe4ec', background: '#f8fafc', padding: 12, borderRadius: 4 }}>
            <div style={{ fontSize: 12, fontWeight: 'bold', color: '#0d69ac', marginBottom: 4 }}>
              Orchestrator Blueprints
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.4 }}>
              Node graph visual scripting editor. Wire touch triggers, timers, kill bricks, and teleporters without writing code.
            </div>
          </div>

          <div style={{ border: '1px solid #dbe4ec', background: '#f8fafc', padding: 12, borderRadius: 4 }}>
            <div style={{ fontSize: 12, fontWeight: 'bold', color: '#0d69ac', marginBottom: 4 }}>
              Cyclops &amp; Retro Builder
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.4 }}>
              Draggable and resizable Builder panel (Hotkey: B). Supports blockout, wedges, stairs, thin walls, extrude, slicing, and classic studs.
            </div>
          </div>

          <div style={{ border: '1px solid #dbe4ec', background: '#f8fafc', padding: 12, borderRadius: 4 }}>
            <div style={{ fontSize: 12, fontWeight: 'bold', color: '#0d69ac', marginBottom: 4 }}>
              11 Custom Nodes Library
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.4 }}>
              Instant placement for KillZones, JumpPads, SpeedBoosts, Teleporters, Conveyors, RotatingParts, DisappearingPlatforms, CoinPickups, Checkpoints, Shakers, and PhantomCameras.
            </div>
          </div>

          <div style={{ border: '1px solid #dbe4ec', background: '#f8fafc', padding: 12, borderRadius: 4 }}>
            <div style={{ fontSize: 12, fontWeight: 'bold', color: '#0d69ac', marginBottom: 4 }}>
              Toaster / Low-Spec Scalability
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.4 }}>
              Unreal-style scalability presets (Epic, High, Medium, Low/Toaster). Reduces editor 3D scaling to 60%, caps FPS to 30, and runs in-editor occlusion culling while keeping the exported game pristine.
            </div>
          </div>

          <div style={{ border: '1px solid #dbe4ec', background: '#f8fafc', padding: 12, borderRadius: 4 }}>
            <div style={{ fontSize: 12, fontWeight: 'bold', color: '#0d69ac', marginBottom: 4 }}>
              Jolt 3D &amp; Box2D Physics
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.4 }}>
              Configured with Jolt Physics 3D and Box2D for fast, stable physics, precise collision handling, and classic brick stacking.
            </div>
          </div>

          <div style={{ border: '1px solid #dbe4ec', background: '#f8fafc', padding: 12, borderRadius: 4 }}>
            <div style={{ fontSize: 12, fontWeight: 'bold', color: '#0d69ac', marginBottom: 4 }}>
              Lighting Presets &amp; Cloud Upload
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.4 }}>
              Visual preset browser with 1-click lighting application (Golden Sun, Retro 2006, Neon Night, Sunset, Spooky Fog, Overcast) and community lighting sharing.
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
