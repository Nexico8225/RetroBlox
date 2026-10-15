'use client'

/* ==================================================================
   COLORWORLD — the paint-the-world game.

   Every map (built-in or a community GLB upload) is turned into a
   white UNSHADED world with black outlines. You hold the LEFT mouse
   button and move to fill it with color. The screen shows how many
   spots you have painted, and every map gives you 10 hints.

   Controls:
     LEFT mouse (hold + move)  paint
     RIGHT mouse               orbit the camera
     MIDDLE mouse / wheel      pan / zoom
     one finger                paint (touch)
     two fingers               orbit + zoom (touch)
================================================================== */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { api, useRetro, attachUpload } from '@/lib/store'
import { BUILTIN_MAPS, placeholderImage, type BuiltinMap } from './colorworld/maps'

const HINTS_PER_MAP = 10
const OUTLINE = 0x151a1f

const PALETTE: [string, string][] = [
  ['red', '#e2231a'], ['orange', '#ff7f27'], ['yellow', '#ffd400'], ['green', '#22b14c'],
  ['teal', '#00b7a8'], ['blue', '#0063c9'], ['purple', '#8a3ff0'], ['pink', '#ff7bb5'],
  ['brown', '#8b5a2b'], ['black', '#2b3138'],
]

interface CommunityMap {
  id: string
  name: string
  plays: number
  createdAt: string
  mapUrl: string
  imageUrl: string | null
  uploader: { id: string; username: string; avatarUrl: string | null }
}

/* one paintable mesh: non-indexed geometry + a per-triangle color bucket */
interface Part {
  mesh: THREE.Mesh
  colors: THREE.BufferAttribute
  centroids: Float32Array
  painted: Uint8Array
  count: number
  tris: number
}

export function ColorWorldView() {
  const user = useRetro((s) => s.user)

  const [view, setView] = useState<'menu' | 'loading' | 'play'>('menu')
  const [loadingMsg, setLoadingMsg] = useState('Loading…')
  const [loadError, setLoadError] = useState('')
  const [tab, setTab] = useState<'maps' | 'community'>('maps')
  const [community, setCommunity] = useState<CommunityMap[]>([])
  const [communityLoading, setCommunityLoading] = useState(false)
  const [thumbs, setThumbs] = useState<Record<string, string>>({})
  const [hintsLeft, setHintsLeft] = useState(HINTS_PER_MAP)
  const [brush, setBrush] = useState(3)
  const [colorIdx, setColorIdx] = useState(0)
  const [done, setDone] = useState(false)
  const [mapName, setMapName] = useState('')
  const [showUpload, setShowUpload] = useState(false)
  const [upName, setUpName] = useState('')
  const [upFile, setUpFile] = useState<File | null>(null)
  const [upImage, setUpImage] = useState<File | null>(null)
  const [upNote, setUpNote] = useState('')
  const [upError, setUpError] = useState('')

  const mountRef = useRef<HTMLDivElement | null>(null)
  const counterRef = useRef<HTMLSpanElement | null>(null)
  const barRef = useRef<HTMLDivElement | null>(null)
  const threeRef = useRef<{
    renderer: THREE.WebGLRenderer
    scene: THREE.Scene
    camera: THREE.PerspectiveCamera
    controls: OrbitControls
    raycaster: THREE.Raycaster
    world: THREE.Group | null
    parts: Part[]
    total: number
    paintedTotal: number
    hints: number
    brush: number
    color: THREE.Color
    painting: boolean
    markers: { obj: THREE.Mesh; ttl: number }[]
    raf: number
    clock: THREE.Clock
    resize: () => void
  } | null>(null)
  const stateRef = useRef({ brush: 3, colorIdx: 0, done: false })

  stateRef.current.brush = brush
  stateRef.current.colorIdx = colorIdx
  stateRef.current.done = done

  /* ---------------- three.js plumbing ---------------- */

  const ensureThree = useCallback(() => {
    if (threeRef.current || !mountRef.current) return
    const mount = mountRef.current
    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1))
    renderer.setSize(mount.clientWidth, mount.clientHeight)
    mount.appendChild(renderer.domElement)
    renderer.domElement.style.touchAction = 'none'
    renderer.domElement.style.display = 'block'

    const scene = new THREE.Scene()
    scene.background = new THREE.Color(0xdff1fb)
    const camera = new THREE.PerspectiveCamera(50, mount.clientWidth / Math.max(1, mount.clientHeight), 0.05, 2000)
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.dampingFactor = 0.08
    controls.maxPolarAngle = Math.PI * 0.52
    // LEFT = paint (handled by us) — RIGHT rotates, MIDDLE dollies
    controls.mouseButtons = { LEFT: null, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE }
    controls.touches = { ONE: null, TWO: THREE.TOUCH.DOLLY_ROTATE }

    const resize = () => {
      if (!mountRef.current) return
      const w = mountRef.current.clientWidth
      const h = Math.max(1, mountRef.current.clientHeight)
      renderer.setSize(w, h)
      camera.aspect = w / h
      camera.updateProjectionMatrix()
    }
    window.addEventListener('resize', resize)

    const t = {
      renderer, scene, camera, controls,
      raycaster: new THREE.Raycaster(),
      world: null, parts: [] as Part[], total: 0, paintedTotal: 0,
      hints: HINTS_PER_MAP, brush: 3, color: new THREE.Color(PALETTE[0][1]),
      painting: false, markers: [] as { obj: THREE.Mesh; ttl: number }[],
      raf: 0, clock: new THREE.Clock(), resize,
    }
    threeRef.current = t

    const paintAtPointer = (e: PointerEvent) => {
      const T = threeRef.current
      if (!T || !T.world || T.parts.length === 0) return
      const rect = renderer.domElement.getBoundingClientRect()
      const ndc = new THREE.Vector2(
        ((e.clientX - rect.left) / rect.width) * 2 - 1,
        -((e.clientY - rect.top) / rect.height) * 2 + 1
      )
      T.raycaster.setFromCamera(ndc, camera)
      const hits = T.raycaster.intersectObjects(T.parts.map((p) => p.mesh), false)
      const hit = hits[0]
      if (!hit || hit.faceIndex == null) return
      const local = T.world.worldToLocal(hit.point.clone())
      stroke(T, local, stateRef.current.brush * 0.11 + 0.08, PALETTE[stateRef.current.colorIdx][1])
    }

    const onDown = (e: PointerEvent) => {
      if (e.button !== 0) return
      t.painting = true
      paintAtPointer(e)
    }
    const onMove = (e: PointerEvent) => { if (t.painting) paintAtPointer(e) }
    const onUp = () => { t.painting = false }
    const noCtx = (e: Event) => e.preventDefault()
    renderer.domElement.addEventListener('pointerdown', onDown)
    renderer.domElement.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
    renderer.domElement.addEventListener('contextmenu', noCtx)

    const tick = () => {
      t.raf = requestAnimationFrame(tick)
      const dt = t.clock.getDelta()
      controls.update()
      // hint markers pulse + expire
      const now = t.clock.elapsedTime
      for (let i = t.markers.length - 1; i >= 0; i--) {
        const m = t.markers[i]
        const s = 1 + Math.sin(now * 9) * 0.25
        m.obj.scale.setScalar(s)
        m.ttl -= dt
        if (m.ttl <= 0) {
          t.scene.remove(m.obj)
          m.obj.geometry.dispose()
          ;(m.obj.material as THREE.Material).dispose()
          t.markers.splice(i, 1)
        }
      }
      renderer.render(scene, camera)
    }
    tick()
  }, [])

  /* paint every triangle whose centroid is inside the brush radius */
  function stroke(T: NonNullable<typeof threeRef.current>, center: THREE.Vector3, radius: number, hex: string) {
    const col = new THREE.Color(hex)
    const r2 = radius * radius
    let changed = false
    for (const p of T.parts) {
      const c = p.centroids
      for (let tri = 0; tri < p.tris; tri++) {
        if (p.painted[tri]) continue
        const dx = c[tri * 3] - center.x
        const dy = c[tri * 3 + 1] - center.y
        const dz = c[tri * 3 + 2] - center.z
        if (dx * dx + dy * dy + dz * dz > r2) continue
        p.colors.setXYZ(tri * 3, col.r, col.g, col.b)
        p.colors.setXYZ(tri * 3 + 1, col.r, col.g, col.b)
        p.colors.setXYZ(tri * 3 + 2, col.r, col.g, col.b)
        p.painted[tri] = 1
        p.count++
        T.paintedTotal++
        changed = true
        if (T.paintedTotal >= T.total) break
      }
      if (changed) p.colors.needsUpdate = true
      if (T.paintedTotal >= T.total) break
    }
    if (changed) updateCounter()
    if (!stateRef.current.done && T.total > 0 && T.paintedTotal >= T.total) {
      stateRef.current.done = true
      setDone(true)
    }
  }

  function updateCounter() {
    const T = threeRef.current
    if (!T) return
    const pct = T.total ? Math.floor((T.paintedTotal / T.total) * 100) : 0
    if (counterRef.current) {
      counterRef.current.textContent = `${T.paintedTotal.toLocaleString()} / ${T.total.toLocaleString()}  (${pct}%)`
    }
    if (barRef.current) barRef.current.style.width = `${pct}%`
  }

  /* turn ANY model into a white unshaded + black outline paint world */
  function worldify(root: THREE.Object3D): { world: THREE.Group; parts: Part[]; total: number } {
    root.updateMatrixWorld(true)
    const world = new THREE.Group()
    const parts: Part[] = []
    const whiteMat = new THREE.MeshBasicMaterial({ vertexColors: true })
    const lineMat = new THREE.LineBasicMaterial({ color: OUTLINE })
    root.traverse((o) => {
      const m = o as THREE.Mesh
      if (!m.isMesh || !m.geometry) return
      let g = m.geometry.clone()
      if ((o as THREE.SkinnedMesh).isSkinnedMesh) return // prototype: static maps only
      const nong = g.toNonIndexed ? g.toNonIndexed() : g
      if (nong !== g) g.dispose()
      g = nong
      g.morphAttributes = {}
      g.deleteAttribute('skinIndex')
      g.deleteAttribute('skinWeight')
      g.deleteAttribute('normal')
      g.deleteAttribute('uv')
      g.deleteAttribute('uv1')
      g.applyMatrix4(m.matrixWorld)
      const n = g.attributes.position.count
      if (n < 3) { g.dispose(); return }
      const colors = new Float32Array(n * 3).fill(1)
      g.setAttribute('color', new THREE.BufferAttribute(colors, 3))
      g.computeBoundingSphere()
      const pos = g.attributes.position.array as ArrayLike<number>
      const tris = Math.floor(n / 3)
      const centroids = new Float32Array(tris * 3)
      for (let t = 0; t < tris; t++) {
        const i = t * 9
        centroids[t * 3] = (pos[i] + pos[i + 3] + pos[i + 6]) / 3
        centroids[t * 3 + 1] = (pos[i + 1] + pos[i + 4] + pos[i + 7]) / 3
        centroids[t * 3 + 2] = (pos[i + 2] + pos[i + 5] + pos[i + 8]) / 3
      }
      const mesh = new THREE.Mesh(g, whiteMat)
      world.add(mesh)
      mesh.add(new THREE.LineSegments(new THREE.EdgesGeometry(g, 22), lineMat))
      parts.push({ mesh, colors: g.attributes.color as THREE.BufferAttribute, centroids, painted: new Uint8Array(tris), count: 0, tris })
    })
    const total = parts.reduce((s, p) => s + p.tris, 0)
    return { world, parts, total }
  }

  /* normalize: scale to a friendly size, sit on the ground, center */
  function normalizeWorld(world: THREE.Group): THREE.Box3 {
    const pre = new THREE.Box3().setFromObject(world)
    const size = pre.getSize(new THREE.Vector3())
    const h = Math.max(0.001, size.y)
    const s = 13 / h
    world.scale.setScalar(s)
    const box = new THREE.Box3().setFromObject(world)
    const c = box.getCenter(new THREE.Vector3())
    world.position.x -= c.x
    world.position.z -= c.z
    world.position.y -= box.min.y
    const out = new THREE.Box3().setFromObject(world)
    return out
  }

  function disposeWorld() {
    const T = threeRef.current
    if (!T || !T.world) return
    T.scene.remove(T.world)
    T.world.traverse((o) => {
      const mesh = o as THREE.Mesh
      if (mesh.isMesh || (o as THREE.LineSegments).isLineSegments) {
        mesh.geometry?.dispose()
      }
    })
    T.world = null
    T.parts = []
  }

  const enterWithObject = useCallback((src: THREE.Object3D, name: string) => {
    const T = threeRef.current!
    disposeWorld()
    const { world, parts, total } = worldify(src)
    const box = normalizeWorld(world)
    T.scene.add(world)
    T.world = world
    T.parts = parts
    T.total = total
    T.paintedTotal = 0
    T.hints = HINTS_PER_MAP
    stateRef.current.done = false
    setDone(false)
    setHintsLeft(HINTS_PER_MAP)
    setMapName(name)
    // camera fit
    const size = box.getSize(new THREE.Vector3())
    const c = box.getCenter(new THREE.Vector3())
    const R = Math.max(1, size.length() / 2)
    const dist = R / Math.sin((50 / 2) * (Math.PI / 180))
    T.camera.position.set(c.x + dist * 0.55, c.y + dist * 0.5, c.z + dist * 0.75)
    T.camera.lookAt(c.x, c.y * 0.85, c.z)
    T.controls.target.set(c.x, c.y * 0.85, c.z)
    T.controls.minDistance = R * 0.35
    T.controls.maxDistance = R * 6
    T.controls.update()
    setView('play')
    // the mount div was display:none while loading — size the renderer now
    requestAnimationFrame(() => {
      T.resize()
      updateCounter()
    })
  }, [])

  const enterBuiltin = useCallback((def: BuiltinMap) => {
    setLoadError('')
    setLoadingMsg(`Building ${def.name}…`)
    setView('loading')
    // let the loading screen actually paint before we build
    setTimeout(() => {
      try {
        ensureThree()
        enterWithObject(def.build(), def.name)
      } catch (err) {
        setView('menu')
        setLoadError(String((err as Error)?.message || err))
      }
    }, 60)
  }, [ensureThree, enterWithObject])

  const enterCommunity = useCallback((m: CommunityMap) => {
    setLoadError('')
    setLoadingMsg(`Downloading ${m.name}…`)
    setView('loading')
    api(`/api/colormaps/${m.id}/play`, { method: 'POST' }).catch(() => {})
    fetch(m.mapUrl)
      .then((r) => { if (!r.ok) throw new Error('Could not download the map.'); return r.arrayBuffer() })
      .then((buf) => new Promise<void>((resolve, reject) => {
        setLoadingMsg(`Unpacking ${m.name}…`)
        try {
          new GLTFLoader().parse(buf, '', (gltf) => {
            try {
              ensureThree()
              enterWithObject(gltf.scene, m.name)
              resolve()
            } catch (e) { reject(e) }
          }, (e) => reject(new Error(e?.message || 'This GLB could not be parsed.')))
        } catch (e) { reject(e) }
      }))
      .catch((err) => {
        setView('menu')
        setLoadError(String((err as Error)?.message || err))
      })
  }, [ensureThree, enterWithObject])

  /* ---------------- hints ---------------- */

  const useHint = useCallback(() => {
    const T = threeRef.current
    if (!T || !T.world || T.hints <= 0 || T.paintedTotal >= T.total) return
    // find a random unpainted triangle
    let target: { part: Part; tri: number } | null = null
    for (let i = 0; i < 900 && !target; i++) {
      const p = T.parts[Math.floor(Math.random() * T.parts.length)]
      const tri = Math.floor(Math.random() * p.tris)
      if (!p.painted[tri]) target = { part: p, tri }
    }
    if (!target) {
      outer: for (const p of T.parts) {
        for (let tri = 0; tri < p.tris; tri++) if (!p.painted[tri]) { target = { part: p, tri }; break outer }
      }
    }
    if (!target) return
    const c = target.part.centroids
    const spot = new THREE.Vector3(c[target.tri * 3], c[target.tri * 3 + 1], c[target.tri * 3 + 2])
    T.world.localToWorld(spot)
    // auto-fill a blob around it with the current color
    const local = T.world.worldToLocal(spot.clone())
    stroke(T, local, (stateRef.current.brush * 0.11 + 0.08) * 1.9, PALETTE[stateRef.current.colorIdx][1])
    // marker so you can see where the hint landed
    const mk = new THREE.Mesh(
      new THREE.SphereGeometry(0.35, 10, 8),
      new THREE.MeshBasicMaterial({ color: 0xffd400, transparent: true, opacity: 0.75 })
    )
    mk.position.copy(spot)
    T.scene.add(mk)
    T.markers.push({ obj: mk, ttl: 2.2 })
    T.hints--
    setHintsLeft(T.hints)
  }, [])

  /* ---------------- reset ---------------- */

  const resetMap = useCallback(() => {
    const T = threeRef.current
    if (!T) return
    for (const p of T.parts) {
      const a = p.colors.array as Float32Array
      a.fill(1)
      p.colors.needsUpdate = true
      p.painted.fill(0)
      p.count = 0
    }
    T.paintedTotal = 0
    T.hints = HINTS_PER_MAP
    stateRef.current.done = false
    setDone(false)
    setHintsLeft(HINTS_PER_MAP)
    updateCounter()
  }, [])

  const backToMenu = useCallback(() => {
    disposeWorld()
    setView('menu')
    setDone(false)
  }, [])

  /* ---------------- menu data ---------------- */

  const loadCommunity = useCallback(() => {
    setCommunityLoading(true)
    api<{ maps: CommunityMap[] }>('/api/colormaps')
      .then((r) => setCommunity(r.maps))
      .catch(() => setCommunity([]))
      .finally(() => setCommunityLoading(false))
  }, [])

  useEffect(() => {
    if (view !== 'menu') return
    loadCommunity()
    // snapshot the built-in maps once for the menu cards
    if (Object.keys(thumbs).length > 0) return
    const next: Record<string, string> = {}
    const rt = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true })
    rt.setSize(320, 200)
    const sc = new THREE.Scene()
    sc.background = new THREE.Color(0xdff1fb)
    const cam = new THREE.PerspectiveCamera(45, 320 / 200, 0.05, 500)
    let i = 0
    let cancelled = false
    const step = () => {
      if (cancelled) { rt.dispose(); return }
      if (i >= BUILTIN_MAPS.length) { rt.dispose(); setThumbs({ ...next }); return }
      const def = BUILTIN_MAPS[i++]
      const g = def.build()
      sc.add(g)
      const box = new THREE.Box3().setFromObject(g)
      const c = box.getCenter(new THREE.Vector3())
      const R = Math.max(1, box.getSize(new THREE.Vector3()).length() / 2)
      cam.position.set(c.x + R * 0.9, c.y + R * 0.75, c.z + R * 1.05)
      cam.lookAt(c.x, c.y * 0.8, c.z)
      rt.render(sc, cam)
      next[def.id] = rt.domElement.toDataURL('image/png')
      sc.remove(g)
      g.traverse((o) => { const mm = o as THREE.Mesh; if (mm.isMesh) { mm.geometry.dispose(); (mm.material as THREE.Material).dispose() } })
      setTimeout(step, 30)
    }
    step()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, loadCommunity])

  /* ---------------- upload ---------------- */

  const submitUpload = useCallback(async () => {
    setUpError('')
    if (!user) { setUpError('Log in to upload a map.'); return }
    if (!upFile) { setUpError('Choose your GLB map file.'); return }
    if (upName.trim().length < 2) { setUpError('Give the map a name (2+ letters).'); return }
    try {
      setUpNote('Preparing upload…')
      const fd = new FormData()
      fd.append('name', upName.trim())
      await attachUpload(fd, 'map', upFile, upFile.name, 'model/gltf-binary', (n) => setUpNote(n))
      if (upImage) {
        if (upImage.size > 3 * 1024 * 1024) throw new Error('Placeholder image too large (max 3MB).')
        await attachUpload(fd, 'image', upImage, upImage.name, upImage.type || 'image/png')
      }
      setUpNote('Publishing…')
      await api('/api/colormaps', { method: 'POST', body: fd })
      setUpNote('')
      setUpName(''); setUpFile(null); setUpImage(null)
      setShowUpload(false)
      setTab('community')
      loadCommunity()
    } catch (err) {
      setUpNote('')
      setUpError(String((err as Error)?.message || err))
    }
  }, [user, upFile, upImage, upName, loadCommunity])

  /* ---------------- unmount cleanup ---------------- */
  useEffect(() => {
    return () => {
      const T = threeRef.current
      if (!T) return
      cancelAnimationFrame(T.raf)
      disposeWorld()
      T.controls.dispose()
      T.renderer.dispose()
      T.renderer.domElement.remove()
      threeRef.current = null
    }
  }, [])

  /* ---------------- render ---------------- */

  const INK = '#1c3a52'
  const DIM = '#5a6b7b'

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 40, background: '#cfe3ef', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      {/* top bar */}
      <div style={{ background: 'linear-gradient(180deg,#0f83c9,#00639e)', color: '#fff', padding: '7px 14px', display: 'flex', alignItems: 'center', gap: 12, flexShrink: 0 }}>
        <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 16, letterSpacing: 1 }}>
          {'COLORWORLD'.split('').map((ch, i) => (
            <span key={i} style={{ color: ['#ff5d4d', '#ff9d2e', '#ffe14d', '#5dd15d', '#4dc3ff', '#b06dff', '#ff7bb5'][i % 7] }}>{ch}</span>
          ))}
        </div>
        <div style={{ fontSize: 11, opacity: 0.9, flex: 1 }}>paint the whole world — everything starts white!</div>
        <Link href="/" style={{ color: '#fff', fontSize: 11, textDecoration: 'underline' }}>retroblox.com</Link>
      </div>

      {/* ============ MENU ============ */}
      {view === 'menu' && (
        <div style={{ flex: 1, overflowY: 'auto', padding: '18px 14px 40px' }}>
          <div style={{ maxWidth: 980, margin: '0 auto' }}>
            <div style={{ background: '#fff', border: '2px solid #24425f', boxShadow: '0 3px 0 rgba(28,58,82,.35)', padding: '14px 16px', marginBottom: 14 }}>
              <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 22, color: INK }}>Pick a world. Paint it all.</div>
              <div style={{ fontSize: 12, color: DIM, marginTop: 4 }}>
                Every wall, roof, rock and rocket is WHITE with a black outline. Grab a color, hold the LEFT mouse button and
                move the brush to fill the world. The screen counts every spot you painted — and each map gives you
                <b style={{ color: INK }}> {HINTS_PER_MAP} hints</b> if you get stuck. Paint 100% to complete the map!
              </div>
              <div style={{ fontSize: 11, color: DIM, marginTop: 6, fontFamily: 'monospace' }}>
                HOLD LEFT MOUSE = paint · RIGHT MOUSE = look around · WHEEL = zoom · touch: 1 finger paint, 2 fingers turn
              </div>
            </div>

            <div style={{ display: 'flex', gap: 8, marginBottom: 12, flexWrap: 'wrap' }}>
              <button className="rb-btn" style={{ fontWeight: tab === 'maps' ? 700 : 400, textDecoration: 'none' }} onClick={() => setTab('maps')}>Maps</button>
              <button className="rb-btn" style={{ fontWeight: tab === 'community' ? 700 : 400, textDecoration: 'none' }} onClick={() => setTab('community')}>Community Map Play</button>
              <button className="rb-btn rb-btn-blue" style={{ textDecoration: 'none' }} onClick={() => setShowUpload((v) => !v)}>⬆ Upload your map</button>
            </div>

            {loadError && (
              <div style={{ background: '#fdecea', border: '1px solid #e2231a', color: '#8a1712', fontSize: 12, padding: '8px 10px', marginBottom: 12 }}>
                {loadError}
              </div>
            )}

            {tab === 'maps' && (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))', gap: 12 }}>
                {BUILTIN_MAPS.map((def) => (
                  <div key={def.id} style={{ background: '#fff', border: '2px solid #24425f', boxShadow: '0 3px 0 rgba(28,58,82,.35)', overflow: 'hidden' }}>
                    <div style={{ height: 132, background: '#dff1fb', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
                      {thumbs[def.id]
                        ? <img src={thumbs[def.id]} alt={def.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                        : <span style={{ fontSize: 11, color: DIM }}>building preview…</span>}
                    </div>
                    <div style={{ padding: '8px 10px' }}>
                      <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 13, color: INK }}>{def.name}</div>
                      <div style={{ fontSize: 11, color: DIM, marginBottom: 8 }}>{def.blurb} · built-in map</div>
                      <button className="rb-btn rb-btn-green" style={{ width: '100%', textDecoration: 'none', fontSize: 13 }} onClick={() => enterBuiltin(def)}>▶ Play</button>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {tab === 'community' && (
              <div>
                <div style={{ fontSize: 12, color: DIM, marginBottom: 10 }}>
                  Maps painted by the community. Choose a map, enter it, play it — and upload your own GLB to add one.
                </div>
                {communityLoading ? (
                  <div style={{ fontSize: 12, color: DIM }}>Loading community maps…</div>
                ) : community.length === 0 ? (
                  <div style={{ background: '#fff', border: '2px solid #24425f', padding: 16, fontSize: 12, color: DIM }}>
                    No community maps yet — be the FIRST! Hit <b>Upload your map</b>, pick a GLB model, and it becomes a
                    white + outline paint world for everyone.
                  </div>
                ) : (
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))', gap: 12 }}>
                    {community.map((m) => (
                      <div key={m.id} style={{ background: '#fff', border: '2px solid #24425f', boxShadow: '0 3px 0 rgba(28,58,82,.35)', overflow: 'hidden' }}>
                        <div style={{ height: 132, background: '#dff1fb', overflow: 'hidden' }}>
                          <img
                            src={m.imageUrl || placeholderImage(m.name)}
                            alt={m.name}
                            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                            onError={(e) => { (e.target as HTMLImageElement).src = placeholderImage(m.name) }}
                          />
                        </div>
                        <div style={{ padding: '8px 10px' }}>
                          <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 13, color: INK, wordBreak: 'break-word' }}>{m.name}</div>
                          <div style={{ fontSize: 11, color: DIM, marginBottom: 8 }}>
                            by {m.uploader?.username || 'someone'} · {m.plays} play{m.plays === 1 ? '' : 's'}
                          </div>
                          <button className="rb-btn rb-btn-green" style={{ width: '100%', textDecoration: 'none', fontSize: 13 }} onClick={() => enterCommunity(m)}>▶ Enter map</button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {showUpload && (
              <div style={{ background: '#fff', border: '2px solid #24425f', boxShadow: '0 3px 0 rgba(28,58,82,.35)', padding: 14, marginTop: 14, maxWidth: 560 }}>
                <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 14, color: INK, marginBottom: 8 }}>Upload a community map</div>
                <div style={{ fontSize: 11, color: DIM, marginBottom: 10 }}>
                  Take ANY model exported as <b>glTF Binary (.glb)</b> — a building, a statue, a whole town. ColorWorld turns
                  every part white with a black outline and players paint it. Add an optional placeholder image for your map card.
                </div>
                {!user ? (
                  <div style={{ fontSize: 12, color: INK }}>
                    <Link href="/login" className="rb-link">Log in</Link> to upload maps.
                  </div>
                ) : (
                  <div style={{ display: 'grid', gap: 8 }}>
                    <input className="rb-input" placeholder="Map name (e.g. Neon City)" value={upName} maxLength={40} onChange={(e) => setUpName(e.target.value)} />
                    <div style={{ fontSize: 11, color: DIM }}>Map model (.glb, up to 24MB):</div>
                    <input type="file" accept=".glb,model/gltf-binary" onChange={(e) => setUpFile(e.target.files?.[0] || null)} />
                    <div style={{ fontSize: 11, color: DIM }}>Placeholder image (optional, up to 3MB):</div>
                    <input type="file" accept="image/*" onChange={(e) => setUpImage(e.target.files?.[0] || null)} />
                    {upNote && <div style={{ fontSize: 11, color: DIM }}>{upNote}</div>}
                    {upError && <div style={{ fontSize: 11, color: '#8a1712', background: '#fdecea', border: '1px solid #e2231a', padding: '6px 8px' }}>{upError}</div>}
                    <button className="rb-btn rb-btn-green" style={{ textDecoration: 'none' }} onClick={submitUpload}>Publish map</button>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ============ LOADING ============ */}
      {view === 'loading' && (
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 12 }}>
          <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 20, color: INK }}>{loadingMsg}</div>
          <div style={{ fontSize: 12, color: DIM }}>turning everything white…</div>
        </div>
      )}

      {/* ============ PLAY ============ */}
      {(view === 'play' || view === 'loading') && (
        <div ref={mountRef} style={{ flex: 1, position: 'relative', minHeight: 0, display: view === 'play' ? 'block' : 'none' }}>
          {/* HUD */}
          <div style={{ position: 'absolute', top: 10, left: 10, background: 'rgba(255,255,255,.94)', border: '2px solid #24425f', boxShadow: '0 3px 0 rgba(28,58,82,.35)', padding: '8px 10px', minWidth: 240, fontFamily: 'Verdana', zIndex: 5 }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: INK, marginBottom: 2 }}>{mapName}</div>
            <div style={{ fontSize: 11, color: DIM, marginBottom: 4 }}>Painted on your screen:</div>
            <span ref={counterRef} style={{ fontSize: 13, fontWeight: 700, color: '#0b6b3a', fontFamily: 'monospace' }}>0 / 0  (0%)</span>
            <div style={{ height: 8, border: '1px solid #24425f', background: '#eef3f7', marginTop: 6 }}>
              <div ref={barRef} style={{ height: '100%', width: '0%', background: 'linear-gradient(90deg,#22b14c,#8fe088)' }} />
            </div>
            <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              <button
                className="rb-btn rb-btn-blue"
                style={{ textDecoration: 'none', fontSize: 11, padding: '5px 10px', opacity: hintsLeft > 0 ? 1 : 0.5 }}
                onClick={useHint}
                disabled={hintsLeft <= 0}
              >
                💡 Hint ({hintsLeft} left)
              </button>
              <button className="rb-btn" style={{ textDecoration: 'none', fontSize: 11, padding: '5px 10px' }} onClick={resetMap}>Reset</button>
              <button className="rb-btn" style={{ textDecoration: 'none', fontSize: 11, padding: '5px 10px' }} onClick={backToMenu}>Menu</button>
            </div>
          </div>

          {/* palette */}
          <div style={{ position: 'absolute', bottom: 12, left: '50%', transform: 'translateX(-50%)', background: 'rgba(255,255,255,.94)', border: '2px solid #24425f', boxShadow: '0 3px 0 rgba(28,58,82,.35)', padding: '7px 10px', display: 'flex', gap: 6, alignItems: 'center', zIndex: 5, flexWrap: 'wrap', justifyContent: 'center', maxWidth: '92%' }}>
            {PALETTE.map(([name, hex], i) => (
              <button
                key={name}
                title={name}
                onClick={() => setColorIdx(i)}
                style={{
                  width: 26, height: 26, background: hex, border: colorIdx === i ? '3px solid #1c3a52' : '2px solid #24425f',
                  borderRadius: 4, cursor: 'pointer', padding: 0, boxShadow: colorIdx === i ? '0 0 0 2px #fff inset' : 'none',
                }}
              />
            ))}
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginLeft: 6 }}>
              <span style={{ fontSize: 10, color: DIM }}>brush</span>
              <input type="range" min={1} max={6} value={brush} onChange={(e) => setBrush(Number(e.target.value))} style={{ width: 90 }} />
            </div>
          </div>

          {/* controls cheat sheet */}
          <div style={{ position: 'absolute', bottom: 12, right: 12, fontSize: 10, color: INK, background: 'rgba(255,255,255,.8)', border: '1px solid #24425f', padding: '5px 8px', zIndex: 5, fontFamily: 'monospace' }}>
            HOLD LEFT = paint · RIGHT = look · WHEEL = zoom
          </div>

          {/* WIN overlay */}
          {done && (
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(12,30,44,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 10 }}>
              <div style={{ background: '#fff', border: '3px solid #24425f', boxShadow: '0 6px 0 rgba(28,58,82,.4)', padding: '22px 26px', textAlign: 'center', maxWidth: 420 }}>
                <div style={{ fontFamily: 'Verdana', fontWeight: 700, fontSize: 24, color: '#0b6b3a' }}>WORLD COMPLETE!</div>
                <div style={{ fontSize: 12, color: DIM, margin: '8px 0 4px' }}>
                  You painted every last spot of <b style={{ color: INK }}>{mapName}</b> — {counterRef.current?.textContent || '100%'}.
                  {hintsLeft > 0 ? ` You even saved ${hintsLeft} hint${hintsLeft === 1 ? '' : 's'}.` : ' Not a single hint wasted… none left!'}
                </div>
                <div style={{ display: 'flex', gap: 8, justifyContent: 'center', marginTop: 12 }}>
                  <button className="rb-btn rb-btn-green" style={{ textDecoration: 'none' }} onClick={() => setDone(false)}>Keep painting</button>
                  <button className="rb-btn" style={{ textDecoration: 'none' }} onClick={backToMenu}>Back to menu</button>
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
