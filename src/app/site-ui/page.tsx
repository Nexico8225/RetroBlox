'use client'

/* ------------------------------------------------------------------
   SITE UI EDITOR — /site-ui  (admin only)

   This is where the OWNER edits the WEB ITSELF: the colors, the site
   name, the navbar links, the welcome banner and the footer.

   Every keystroke / color pick applies LIVE to the whole site (the
   CSS variables are global), so you edit the real pages, not a mock.
   Nothing is permanent until you hit SAVE — Save writes the config
   to the database and every visitor gets it on their next load.
------------------------------------------------------------------ */

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { Page, Title, GameIcon } from '@/components/retro/Shell'
import { useRetro, api } from '@/lib/store'
import { applySiteUi, normalizeSiteUi, useSiteUi, type SiteUiConfig, type SiteUiLink } from '@/lib/siteui'

/* one color row: swatch + hex text, edits apply instantly */
function ColorRow({ label, hint, value, onChange }: { label: string; hint: string; value: string; onChange: (v: string) => void }) {
  const valid = /^#[0-9a-fA-F]{6}$/.test(value)
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
      <input
        type="color"
        value={valid ? value : '#000000'}
        onChange={(e) => onChange(e.target.value.toLowerCase())}
        aria-label={label}
        style={{ width: 34, height: 26, padding: 0, border: '1px solid var(--rb-border)', borderRadius: 4, background: '#fff', cursor: 'pointer' }}
      />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12, fontWeight: 700 }}>{label}</div>
        <div style={{ fontSize: 10, color: 'var(--rb-text-dim)' }}>{hint}</div>
      </div>
      <input
        className="rb-input"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        style={{ width: 90, fontSize: 11, fontFamily: 'monospace', textAlign: 'center' }}
        spellCheck={false}
      />
    </div>
  )
}

function Field({ label, value, onChange, max = 120, mono }: { label: string; value: string; onChange: (v: string) => void; max?: number; mono?: boolean }) {
  return (
    <label style={{ display: 'block', marginBottom: 8 }}>
      <div style={{ fontSize: 11, fontWeight: 700, marginBottom: 3 }}>{label}</div>
      <input className="rb-input" value={value} maxLength={max} onChange={(e) => onChange(e.target.value)} style={{ width: '100%', fontSize: 12, fontFamily: mono ? 'monospace' : undefined }} spellCheck={false} />
    </label>
  )
}

export default function SiteUiPage() {
  return (
    <Page>
      <Title t="Site UI Editor" />
      <SiteUiEditor />
    </Page>
  )
}

function SiteUiEditor() {
  const { user, booted, setToast } = useRetro()
  const saved = useSiteUi((s) => s.config)
  const loaded = useSiteUi((s) => s.loaded)
  /* the working copy — the saved config is only touched on Save/Reset */
  const [draft, setDraft] = useState<SiteUiConfig | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (draft === null && loaded) setDraft(saved)
  }, [draft, loaded, saved])

  if (booted && (!user || user.role !== 'admin')) {
    return (
      <div className="rb-box" style={{ padding: 22, textAlign: 'center' }}>
        <div className="rb-page-title">Site UI Editor</div>
        <p style={{ fontSize: 12, color: 'var(--rb-text-dim)' }}>
          Only the site owner can edit the web UI. Everyone else sees the site the owner built.
        </p>
        <Link className="rb-btn rb-btn-blue" href="/" style={{ textDecoration: 'none', display: 'inline-block', marginTop: 6 }}>
          Back Home
        </Link>
      </div>
    )
  }

  if (!draft) return <div style={{ padding: 30, color: 'var(--rb-text-dim)' }}>Loading the editor...</div>

  /* live: every change recolors / renames the REAL site immediately */
  const patch = (fn: (d: SiteUiConfig) => SiteUiConfig) => {
    const next = fn(draft)
    setDraft(next)
    applySiteUi(next)
  }

  const setColors = (k: keyof SiteUiConfig['colors']) => (v: string) =>
    patch((d) => ({ ...d, colors: { ...d.colors, [k]: v.toLowerCase() } }))
  const setHero = (k: keyof SiteUiConfig['hero'], v: unknown) => patch((d) => ({ ...d, hero: { ...d.hero, [k]: v } }))
  const setFooter = (k: keyof SiteUiConfig['footer']) => (v: string) => patch((d) => ({ ...d, footer: { ...d.footer, [k]: v } }))

  const setLink = (i: number, p: Partial<SiteUiLink>) =>
    patch((d) => ({ ...d, links: d.links.map((l, j) => (j === i ? { ...l, ...p } : l)) }))
  const moveLink = (i: number, dir: -1 | 1) =>
    patch((d) => {
      const j = i + dir
      if (j < 0 || j >= d.links.length) return d
      const links = [...d.links]
      ;[links[i], links[j]] = [links[j], links[i]]
      return { ...d, links }
    })
  const addLink = () => patch((d) => ({ ...d, links: [...d.links, { label: 'New Page', href: '/games', show: true }] }))
  const delLink = (i: number) => patch((d) => ({ ...d, links: d.links.filter((_, j) => j !== i) }))

  const setCta = (i: number, p: Partial<SiteUiConfig['hero']['ctas'][number]>) =>
    patch((d) => ({ ...d, hero: { ...d.hero, ctas: d.hero.ctas.map((c, j) => (j === i ? { ...c, ...p } : c)) } }))

  async function save(config: SiteUiConfig) {
    setSaving(true)
    try {
      const res = await api<{ ok?: boolean; error?: string }>('/api/site-ui', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ config }),
      })
      if (res.error) throw new Error(res.error)
      useSiteUi.getState().setConfig(normalizeSiteUi(config))
      applySiteUi(normalizeSiteUi(config))
      setToast('Site UI saved - live for everyone')
    } catch {
      setToast('Could not save (are you the site owner?)')
    } finally {
      setSaving(false)
    }
  }

  const head = (t: string) => (
    <div className="rb-panel-head" style={{ marginTop: 14 }}>
      <span>{t}</span>
    </div>
  )

  return (
    <div style={{ maxWidth: 860 }}>
      {/* live preview header — the real thing is above you already */}
      <div className="rb-box" style={{ padding: '14px 16px', marginBottom: 4 }}>
        <div className="rb-page-title">Site UI Editor</div>
        <div style={{ fontSize: 12, color: 'var(--rb-text-dim)' }}>
          You are editing the web itself. Every change on this page applies to the real site instantly while you
          type — hit SAVE to make it permanent for every visitor. The blue bar, the white link strip, the welcome
          banner on the home page and the footer are all yours.
        </div>
      </div>

      <div style={{ display: 'flex', gap: 10, marginBottom: 10, flexWrap: 'wrap' }}>
        <button className="rb-btn rb-btn-green" disabled={saving} onClick={() => save(draft)} style={{ fontSize: 12, padding: '8px 22px' }}>
          {saving ? 'Saving...' : 'Save - publish to the site'}
        </button>
        <button
          className="rb-btn"
          disabled={saving}
          onClick={() => {
            const def = normalizeSiteUi(null)
            setDraft(def)
            applySiteUi(def)
          }}
          style={{ fontSize: 12 }}
        >
          Reset editor to the default look
        </button>
        <button
          className="rb-btn rb-btn-red"
          disabled={saving}
          onClick={() => save(normalizeSiteUi(null))}
          style={{ fontSize: 12 }}
        >
          Restore saved default for everyone
        </button>
      </div>

      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'flex-start' }}>
        {/* -------- column 1: identity + colors -------- */}
        <div className="rb-box" style={{ flex: 1, minWidth: 300, padding: '12px 14px' }}>
          {head('Identity')}
          <Field label="Site name (tab titles, footer)" value={draft.siteName} onChange={(v) => patch((d) => ({ ...d, siteName: v }))} max={40} />

          {head('Colors')}
          <ColorRow label="Header top" hint="top of the blue bar gradient" value={draft.colors.navLight} onChange={setColors('navLight')} />
          <ColorRow label="Header blue bar" hint="the main header color" value={draft.colors.nav} onChange={setColors('nav')} />
          <ColorRow label="Header bottom" hint="bottom of the header gradient" value={draft.colors.navDark} onChange={setColors('navDark')} />
          <ColorRow label="Link blue" hint="text links + highlights" value={draft.colors.accent} onChange={setColors('accent')} />
          <ColorRow label="Button blue" hint="blue buttons + search Go" value={draft.colors.accentDark} onChange={setColors('accentDark')} />
          <ColorRow label="Action green" hint="green buttons" value={draft.colors.green} onChange={setColors('green')} />
          <ColorRow label="Green dark" hint="green button bottom shade" value={draft.colors.greenDark} onChange={setColors('greenDark')} />
          <ColorRow label="Page background" hint="the page behind the panels" value={draft.colors.pageBg} onChange={setColors('pageBg')} />
        </div>

        {/* -------- column 2: nav + hero + footer -------- */}
        <div style={{ flex: 1, minWidth: 320 }}>
          <div className="rb-box" style={{ padding: '12px 14px' }}>
            {head('Navbar links (top white strip)')}
            {draft.links.map((l, i) => (
              <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
                <input
                  type="checkbox"
                  checked={l.show}
                  onChange={(e) => setLink(i, { show: e.target.checked })}
                  title="Show this link"
                  style={{ width: 15, height: 15, flexShrink: 0 }}
                />
                <input className="rb-input" value={l.label} maxLength={40} onChange={(e) => setLink(i, { label: e.target.value })} style={{ width: 110, fontSize: 11 }} spellCheck={false} />
                <input className="rb-input" value={l.href} maxLength={200} onChange={(e) => setLink(i, { href: e.target.value })} style={{ flex: 1, minWidth: 80, fontSize: 11, fontFamily: 'monospace' }} spellCheck={false} />
                <button className="rb-btn" onClick={() => moveLink(i, -1)} title="Move up" style={{ padding: '2px 7px', fontSize: 11 }}>&uarr;</button>
                <button className="rb-btn" onClick={() => moveLink(i, 1)} title="Move down" style={{ padding: '2px 7px', fontSize: 11 }}>&darr;</button>
                <button className="rb-btn rb-btn-red" onClick={() => delLink(i)} title="Remove" style={{ padding: '2px 7px', fontSize: 11 }}>X</button>
              </div>
            ))}
            <button className="rb-btn rb-btn-blue" onClick={addLink} style={{ fontSize: 11 }}>+ Add a navbar link</button>

            {head('Welcome banner (home page)')}
            <label style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 12, marginBottom: 8 }}>
              <input type="checkbox" checked={draft.hero.show} onChange={(e) => setHero('show', e.target.checked)} style={{ width: 15, height: 15 }} />
              Show the welcome banner
            </label>
            <Field label="Title for logged-out visitors" value={draft.hero.guestTitle} onChange={(v) => setHero('guestTitle', v)} max={80} />
            <Field label="Title for members ({name} = their username)" value={draft.hero.memberTitle} onChange={(v) => setHero('memberTitle', v)} max={80} />
            <Field label="Subtitle line" value={draft.hero.subtitle} onChange={(v) => setHero('subtitle', v)} max={200} />
            <div style={{ fontSize: 11, fontWeight: 700, margin: '8px 0 4px' }}>Buttons on the banner</div>
            {draft.hero.ctas.map((c, i) => (
              <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
                <input type="checkbox" checked={c.show} onChange={(e) => setCta(i, { show: e.target.checked })} style={{ width: 15, height: 15, flexShrink: 0 }} title="Show this button" />
                <input className="rb-input" value={c.label} maxLength={60} onChange={(e) => setCta(i, { label: e.target.value })} style={{ width: 130, fontSize: 11 }} spellCheck={false} />
                <input className="rb-input" value={c.href} maxLength={200} onChange={(e) => setCta(i, { href: e.target.value })} style={{ flex: 1, minWidth: 80, fontSize: 11, fontFamily: 'monospace' }} spellCheck={false} />
              </div>
            ))}

            {head('Footer')}
            <Field label="Tagline (next to the logo)" value={draft.footer.tagline} onChange={setFooter('tagline')} max={200} />
            <Field label="Bottom line" value={draft.footer.bottom} onChange={setFooter('bottom')} max={120} />
          </div>

          {/* what the owner is editing — a small cheat sheet */}
          <div className="rb-box" style={{ padding: '12px 14px', marginTop: 12 }}>
            {head('What this controls')}
            <ul style={{ fontSize: 12, color: 'var(--rb-text-dim)', paddingLeft: 18, margin: '6px 0 0', lineHeight: 1.7 }}>
              <li>Header blue bar + gradients: every page, top of the site</li>
              <li>Link + button colors: site-wide, all rb-link and action buttons</li>
              <li>Navbar links: the white strip under the blue bar (order, labels, hide, custom pages)</li>
              <li>Welcome banner: the home page card with your name and its buttons</li>
              <li>Footer: tagline + bottom line on every page</li>
              <li>Site name: browser tab titles</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
