'use client'

/* PlacementEditor — the 3D space where a creator places their UGC.
   The player model (R6IK.fbx) stands in the middle. The creator moves /
   rotates / scales the uploaded model with the gizmo OR by typing exact
   numbers (Location / Rotation / Scale, Blender-style), with real snapping
   and an editable PIVOT (the point the item rotates and scales around).

   Scene graph:  holder  <- the gizmo grabs this (transform relative to pivot)
                   └ wrap  <- sits at -pivot so the model itself stays put
   Saving decomposes holder×wrap back to a plain Placement — the stored
   format never changes, so every renderer (site + Unity SDK) applies the
   result EXACTLY as before: what you save is what everyone sees. */

import { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { TransformControls } from 'three/examples/jsm/controls/TransformControls.js'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { PLACEMENT_BOUNDS, DEFAULT_AVATAR, resolveDefaultAsset, type Placement } from '@/lib/avatarAssets'
import { applyLook, applyModelSurface, buildLook3D, prepareRigView, UGC_IMPORT_SIZE, type LoadedRig } from '@/lib/three/rig'

interface PlacementEditorProps {
  /** the uploaded model, already converted to GLB */
  glb: Blob
  /** optional texture the creator picked — shown live while placing */
  textureUrl?: string
  /** optional tint the creator picked — shown live while placing */
  color?: string
  onSave: (result: { placement: Placement; thumb: Blob }) => void
  onCancel: () => void
}

const MODES = [
  { id: 'translate', label: 'Move', key: 'W' },
  { id: 'rotate', label: 'Rotate', key: 'E' },
  { id: 'scale', label: 'Scale', key: 'R' },
] as const

type Mode = (typeof MODES)[number]['id']

const MOVE_SNAPS = [
  { v: 0, label: 'Off' },
  { v: 0.05, label: '0.05' },
  { v: 0.1, label: '0.1' },
  { v: 0.25, label: '0.25' },
  { v: 0.5, label: '0.5' },
  { v: 1, label: '1' },
]
const TURN_SNAPS = [
  { v: 0, label: 'Off' },
  { v: 5, label: '5°' },
  { v: 15, label: '15°' },
  { v: 45, label: '45°' },
  { v: 90, label: '90°' },
]
const SCALE_SNAPS = [
  { v: 0, label: 'Off' },
  { v: 0.05, label: '0.05' },
  { v: 0.1, label: '0.1' },
  { v: 0.25, label: '0.25' },
]

const AXIS_LIMIT = 5.5 // roughly the player model height — plenty for any wearable

type Vec3 = [number, number, number]

interface FormState {
  loc: Vec3
  rot: Vec3 // degrees
  scale: Vec3
  pivot: Vec3
}

const ZERO: Vec3 = [0, 0, 0]

function round(n: number): number {
  return Math.round(n * 1000) / 1000
}

export default function PlacementEditor({ glb, textureUrl, color, onSave, onCancel }: PlacementEditorProps) {
  const hostRef = useRef<HTMLDivElement>(null)
  const holderRef = useRef<THREE.Group | null>(null)
  const wrapRef = useRef<THREE.Group | null>(null)
  const tcRef = useRef<TransformControls | null>(null)
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null)
  const sceneRef = useRef<THREE.Scene | null>(null)
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null)
  const orbitRef = useRef<OrbitControls | null>(null)
  const rigViewRef = useRef<THREE.Group | null>(null)
  const [mode, setMode] = useState<Mode>('translate')
  const [snapMove, setSnapMove] = useState(0.25)
  const [snapTurn, setSnapTurn] = useState(15)
  const [snapScale, setSnapScale] = useState(0.05)
  const [status, setStatus] = useState('Loading the space...')
  const [showPlayer, setShowPlayer] = useState(true)
  // gizmo space: LOCAL = axes follow the item (Studio default), GLOBAL = world axes
  const [space, setSpace] = useState<'local' | 'world'>('local')
  // pivot mode: the gizmo moves the PIVOT POINT itself instead of the item
  const [pivotMode, setPivotMode] = useState(false)
  const [form, setForm] = useState<FormState>({ loc: [0, 5.9, 0], rot: [0, 0, 0], scale: [1, 1, 1], pivot: ZERO })
  // latest form state readable inside three.js event listeners (set post-render)
  const formRef = useRef(form)
  const pivotMarkerRef = useRef<THREE.Mesh | null>(null)
  const pivotModeRef = useRef(pivotMode)
  useEffect(() => {
    formRef.current = form
  }, [form])
  useEffect(() => {
    pivotModeRef.current = pivotMode
  }, [pivotMode])

  // latest show/hide-player toggle readable inside the scene load promise
  const showPlayerRef = useRef(showPlayer)
  useEffect(() => {
    showPlayerRef.current = showPlayer
    const view = rigViewRef.current
    if (view) view.visible = showPlayer
  }, [showPlayer])

  /** pull the live three.js transform back into the numeric inputs */
  function syncFromHolder(pivotOverride?: Vec3) {
    const holder = holderRef.current
    if (!holder) return
    setForm({
      loc: [round(holder.position.x), round(holder.position.y), round(holder.position.z)],
      rot: [
        round(THREE.MathUtils.radToDeg(holder.rotation.x)),
        round(THREE.MathUtils.radToDeg(holder.rotation.y)),
        round(THREE.MathUtils.radToDeg(holder.rotation.z)),
      ],
      scale: [round(holder.scale.x), round(holder.scale.y), round(holder.scale.z)],
      pivot: pivotOverride ?? ((formRef.current.pivot ?? ZERO) as Vec3),
    })
  }

  /** keep the pivot point inside the space + the item a sane size */
  function clampHolder() {
    const holder = holderRef.current
    if (!holder) return
    holder.position.x = THREE.MathUtils.clamp(holder.position.x, PLACEMENT_BOUNDS.min[0], PLACEMENT_BOUNDS.max[0])
    holder.position.y = THREE.MathUtils.clamp(holder.position.y, PLACEMENT_BOUNDS.min[1], PLACEMENT_BOUNDS.max[1])
    holder.position.z = THREE.MathUtils.clamp(holder.position.z, PLACEMENT_BOUNDS.min[2], PLACEMENT_BOUNDS.max[2])
    holder.scale.x = THREE.MathUtils.clamp(holder.scale.x, PLACEMENT_BOUNDS.scaleMin, PLACEMENT_BOUNDS.scaleMax)
    holder.scale.y = THREE.MathUtils.clamp(holder.scale.y, PLACEMENT_BOUNDS.scaleMin, PLACEMENT_BOUNDS.scaleMax)
    holder.scale.z = THREE.MathUtils.clamp(holder.scale.z, PLACEMENT_BOUNDS.scaleMin, PLACEMENT_BOUNDS.scaleMax)
  }

  /* ---------------- pivot ---------------- */

  /** Move the pivot WITHOUT the item jumping: shift the holder position by
   *  the exact amount the wrap offset change would move the model. */
  function setPivot(next: Vec3, initial = false) {
    const holder = holderRef.current
    const wrap = wrapRef.current
    if (!holder || !wrap) return
    const prev = (formRef.current.pivot ?? ZERO) as Vec3
    const d: Vec3 = [next[0] - prev[0], next[1] - prev[1], next[2] - prev[2]]
    if (d.some((n) => !isFinite(n))) return
    if (!initial && d.every((n) => n === 0)) return
    // model-space delta -> holder-world delta (scale per axis, then rotate)
    const v = new THREE.Vector3(
      d[0] * holder.scale.x,
      d[1] * holder.scale.y,
      d[2] * holder.scale.z
    ).applyQuaternion(holder.quaternion)
    holder.position.add(v)
    wrap.position.set(-next[0], -next[1], -next[2])
    // the yellow marker rides AT the pivot (it lives inside the holder)
    if (pivotMarkerRef.current) pivotMarkerRef.current.position.set(next[0], next[1], next[2])
    if (!initial) clampHolder()
    syncFromHolder([round(next[0]), round(next[1]), round(next[2])])
  }

  /** put the pivot at the item's bounding-box center (model-local space) */
  function centerPivotOnItem(initial = false) {
    const holder = holderRef.current
    const wrap = wrapRef.current
    if (!holder || !wrap) return
    holder.updateMatrixWorld(true)
    const box = new THREE.Box3().setFromObject(wrap)
    if (box.isEmpty()) return
    const c = box.getCenter(new THREE.Vector3())
    // world -> wrap-local: the wrap only ever carries a translation
    c.sub(wrap.position)
    setPivot([round(c.x), round(c.y), round(c.z)], initial)
  }


  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    let disposed = false
    let raf = 0

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.shadowMap.enabled = true
    renderer.shadowMap.type = THREE.PCFSoftShadowMap
    renderer.outputColorSpace = THREE.SRGBColorSpace
    renderer.domElement.style.display = 'block'
    renderer.domElement.style.touchAction = 'none'
    host.appendChild(renderer.domElement)
    rendererRef.current = renderer

    const scene = new THREE.Scene()
    scene.background = new THREE.Color('#dcebf5')
    sceneRef.current = scene

    scene.add(new THREE.HemisphereLight(0xffffff, 0x8899aa, 1.15))
    const sun = new THREE.DirectionalLight(0xffffff, 1.6)
    sun.position.set(4, 9, 6)
    sun.castShadow = true
    sun.shadow.mapSize.set(1024, 1024)
    scene.add(sun)

    // the floor of the space + the bounded box
    const grid = new THREE.GridHelper(20, 20, 0x9db8cc, 0xc9dae8)
    scene.add(grid)
    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(20, 20),
      new THREE.MeshLambertMaterial({ color: '#e8f1f8' })
    )
    floor.name = 'rb-floor'
    floor.rotation.x = -Math.PI / 2
    floor.position.y = -0.01
    floor.receiveShadow = true
    scene.add(floor)

    const bounds = new THREE.Box3(
      new THREE.Vector3(...PLACEMENT_BOUNDS.min),
      new THREE.Vector3(...PLACEMENT_BOUNDS.max)
    )
    const boundsHelper = new THREE.Box3Helper(bounds, new THREE.Color(0x2a8f3a))
    boundsHelper.name = 'rb-bounds'
    ;(boundsHelper.material as THREE.LineBasicMaterial).transparent = true
    ;(boundsHelper.material as THREE.LineBasicMaterial).opacity = 0.7
    scene.add(boundsHelper)

    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 200)
    camera.position.set(6.5, 4.6, 8.8)
    cameraRef.current = camera

    const orbit = new OrbitControls(camera, renderer.domElement)
    orbit.target.set(0, 2.6, 0)
    orbit.enableDamping = true
    orbit.dampingFactor = 0.08
    orbit.minDistance = 2.5
    orbit.maxDistance = 30
    orbit.update()
    orbitRef.current = orbit

    const tc = new TransformControls(camera, renderer.domElement)
    tc.setSize(0.85)
    tc.setSpace('local') // Studio-style default — L flips to global anytime
    const tcHelper = tc.getHelper ? tc.getHelper() : (tc as unknown as THREE.Object3D)
    scene.add(tcHelper)
    tcRef.current = tc
    tc.addEventListener('dragging-changed', (e) => {
      orbit.enabled = !(e as unknown as { value: boolean }).value
    })

    // the player model, standing in the middle of the space
    let rigLib: LoadedRig | null = null
    let rigView: THREE.Group | null = null

    const sync = () => {
      // in pivot mode the gizmo drags the PIVOT, not the item — the marker's
      // local position (it lives inside the holder) IS the model-space pivot
      if (pivotModeRef.current) {
        const marker = pivotMarkerRef.current
        if (marker) setPivot([round(marker.position.x), round(marker.position.y), round(marker.position.z)])
        return
      }
      clampHolder()
      syncFromHolder()
    }
    tc.addEventListener('objectChange', sync)

    const resize = () => {
      const w = host.clientWidth || 600
      const h = host.clientHeight || 420
      renderer.setSize(w, h, false)
      camera.aspect = w / Math.max(h, 1)
      camera.updateProjectionMatrix()
    }
    const ro = new ResizeObserver(resize)
    ro.observe(host)
    resize()

    const animate = () => {
      if (disposed) return
      raf = requestAnimationFrame(animate)
      orbit.update()
      renderer.render(scene, camera)
    }
    animate()

    // keyboard shortcuts: W/E/R = move/rotate/scale · L = local/global · P = move the pivot
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLSelectElement) return
      const k = e.key.toLowerCase()
      if (k === 'w') { setPivotMode(false); setMode('translate') }
      else if (k === 'e') { setPivotMode(false); setMode('rotate') }
      else if (k === 'r') { setPivotMode(false); setMode('scale') }
      else if (k === 'l') setSpace((s) => (s === 'local' ? 'world' : 'local'))
      else if (k === 'p') setPivotMode((v) => !v)
    }
    window.addEventListener('keydown', onKey)

    let objectUrl: string | null = null
    Promise.all([
      prepareRigView(),
      (async () => {
        objectUrl = URL.createObjectURL(glb)
        const buf = await glb.arrayBuffer()
        const gltf = await new GLTFLoader().parseAsync(buf.slice(0), '')
        return gltf.scene
      })(),
    ])
      .then(([{ view, rig }, model]) => {
        if (disposed) return
        rigView = view
        rigLib = rig
        rigViewRef.current = view
        view.visible = showPlayerRef.current
        scene.add(view)
        // the player model wears the classic look while you place your item
        applyLook(view, rig, buildLook3D(DEFAULT_AVATAR, (id) => resolveDefaultAsset(id)))

        // normalize the import so huge/tiny source files start sensible —
        // whatever the creator does from here is what gets saved
        // (UGC_IMPORT_SIZE is the SAME constant every renderer normalizes
        // with, so the saved placement replays 1:1 everywhere)
        const raw = new THREE.Box3().setFromObject(model)
        const rawSize = raw.getSize(new THREE.Vector3())
        const maxDim = Math.max(rawSize.x, rawSize.y, rawSize.z, 0.0001)
        const importSize = UGC_IMPORT_SIZE
        model.scale.setScalar(importSize / maxDim)

        // the creator's texture / color — visible WHILE placing, so what
        // they save is exactly what the catalog and every player will see
        applyModelSurface(model, { textureUrl, color })

        const wrap = new THREE.Group()
        wrap.name = 'ugc-model'
        wrap.add(model)
        const holder = new THREE.Group()
        holder.name = 'ugc'
        holder.add(wrap)
        // starts floating just above the head; the creator takes it from here
        const headTop = rig.boxes.get('head')?.max.y ?? 5
        holder.position.set(0, Math.min(headTop + importSize / 2 + 0.06, PLACEMENT_BOUNDS.max[1]), 0)
        holderRef.current = holder
        wrapRef.current = wrap
        scene.add(holder)
        tc.attach(holder)
        // rotate/scale around the item's own center from the start — the
        // pivot is editable below for anyone who wants the raw origin back
        centerPivotOnItem(true)
        // the yellow pivot marker: a child of the holder, so its local
        // position IS the model-space pivot. In pivot mode the gizmo drags
        // THIS — exactly like Studio's "move the pivot where you want".
        const marker = new THREE.Mesh(
          new THREE.SphereGeometry(0.11, 20, 14),
          new THREE.MeshBasicMaterial({ color: '#ffd23e', depthTest: false, transparent: true, opacity: 0.95 })
        )
        marker.name = 'rb-pivot-marker'
        marker.renderOrder = 999
        // wrap.position is -pivot and was JUST set by centerPivotOnItem — read
        // it directly (form state is still one render behind in this tick)
        marker.position.set(-wrap.position.x, -wrap.position.y, -wrap.position.z)
        marker.visible = false
        holder.add(marker)
        pivotMarkerRef.current = marker
        setStatus('Place your item on the player model — it stays exactly where you leave it.')
      })
      .catch(() => setStatus('Could not load that model — try a different file.'))

    return () => {
      disposed = true
      cancelAnimationFrame(raf)
      window.removeEventListener('keydown', onKey)
      ro.disconnect()
      tc.detach()
      tc.dispose()
      if (objectUrl) URL.revokeObjectURL(objectUrl)
      if (rigView) {
        scene.remove(rigView)
        rigView.traverse((o) => {
          const m = o as THREE.Mesh
          if (!m.isMesh) return
          const mat = m.material as THREE.Material | THREE.Material[]
          if (Array.isArray(mat)) mat.forEach((x) => x.dispose())
          else mat?.dispose()
        })
      }
      holderRef.current?.traverse((o) => {
        const m = o as THREE.Mesh
        if (!m.isMesh) return
        m.geometry?.dispose()
        const mat = m.material as THREE.Material | THREE.Material[]
        if (Array.isArray(mat)) mat.forEach((x) => x.dispose())
        else mat?.dispose()
      })
      pivotMarkerRef.current = null
      grid.dispose()
      floor.geometry.dispose()
      ;(floor.material as THREE.Material).dispose()
      boundsHelper.geometry?.dispose?.()
      orbit.dispose()
      renderer.dispose()
      if (renderer.domElement.parentElement === host) host.removeChild(renderer.domElement)
      void rigLib
    }
  }, [glb])

  // mode + snap values straight into the gizmo
  useEffect(() => {
    const tc = tcRef.current
    if (!tc) return
    tc.setMode(pivotMode ? 'translate' : mode)
    tc.setTranslationSnap(snapMove > 0 ? snapMove : null)
    tc.setRotationSnap(snapTurn > 0 ? THREE.MathUtils.degToRad(snapTurn) : null)
    tc.setScaleSnap(snapScale > 0 ? snapScale : null)
  }, [mode, snapMove, snapTurn, snapScale, pivotMode])

  // LOCAL <-> GLOBAL — flips the gizmo axes anytime, Studio-style
  useEffect(() => {
    tcRef.current?.setSpace(space)
  }, [space])

  // pivot mode: the gizmo grabs the yellow pivot marker instead of the item
  useEffect(() => {
    const tc = tcRef.current
    if (!tc) return
    const marker = pivotMarkerRef.current
    if (pivotMode && marker) {
      marker.visible = true
      tc.attach(marker)
      setStatus('Pivot mode — drag the yellow ball to move the pivot. Rotations and scales turn around it. Press P or Move to go back.')
    } else if (holderRef.current) {
      tc.attach(holderRef.current)
      if (marker) marker.visible = false
      if (!pivotMode) setStatus('Place your item on the player model — it stays exactly where you leave it.')
    }
  }, [pivotMode])

  /* ---------------- camera angle + show/hide the player ---------------- */

  /** Jump the camera to a preset angle around the player (keeps your zoom). */
  function setCameraAngle(preset: 'front' | 'back' | 'left' | 'right' | 'corner' | 'top') {
    const camera = cameraRef.current
    const orbit = orbitRef.current
    if (!camera || !orbit) return
    const target = orbit.target
    const dist = Math.min(Math.max(camera.position.distanceTo(target), 6), 18)
    const dirs: Record<typeof preset, [number, number, number]> = {
      front: [0, 0.12, 1],
      back: [0, 0.12, -1],
      left: [-1, 0.12, 0],
      right: [1, 0.12, 0],
      corner: [0.62, 0.42, 0.85],
      top: [0.001, 1, 0.28],
    }
    const [dx, dy, dz] = dirs[preset]
    camera.position.set(target.x + dx * dist, target.y + dy * dist, target.z + dz * dist)
    orbit.update()
  }

  function resetPivot() {
    setPivot([0, 0, 0])
  }

  /* ---------------- numeric transform inputs ---------------- */

  function applyLocation(axis: 0 | 1 | 2, value: number) {
    const holder = holderRef.current
    if (!holder || !isFinite(value)) return
    const pos = [...holder.position.toArray()] as Vec3
    pos[axis] = value
    holder.position.set(...pos)
    clampHolder()
    syncFromHolder()
  }

  function applyRotation(axis: 0 | 1 | 2, value: number) {
    const holder = holderRef.current
    if (!holder || !isFinite(value)) return
    holder.rotation.set(
      axis === 0 ? THREE.MathUtils.degToRad(value) : holder.rotation.x,
      axis === 1 ? THREE.MathUtils.degToRad(value) : holder.rotation.y,
      axis === 2 ? THREE.MathUtils.degToRad(value) : holder.rotation.z
    )
    syncFromHolder()
  }

  function applyScale(axis: 0 | 1 | 2, value: number) {
    const holder = holderRef.current
    if (!holder || !isFinite(value)) return
    const s = [...holder.scale.toArray()] as Vec3
    s[axis] = THREE.MathUtils.clamp(value, PLACEMENT_BOUNDS.scaleMin, PLACEMENT_BOUNDS.scaleMax)
    holder.scale.set(...s)
    enforceWorldSize()
    syncFromHolder()
  }

  /** Guard against runaway scaling: the item may never outgrow the space. */
  function enforceWorldSize() {
    const holder = holderRef.current
    const scene = sceneRef.current
    if (!holder || !scene) return
    scene.updateMatrixWorld(true)
    const box = new THREE.Box3().setFromObject(holder)
    const size = box.getSize(new THREE.Vector3())
    const maxDim = Math.max(size.x, size.y, size.z)
    if (maxDim > AXIS_LIMIT) {
      const f = AXIS_LIMIT / maxDim
      holder.scale.multiplyScalar(f)
    }
    clampHolder()
  }

  function resetItem() {
    const holder = holderRef.current
    if (!holder) return
    holder.position.set(0, 5.9, 0)
    holder.rotation.set(0, 0, 0)
    holder.scale.setScalar(1)
    clampHolder()
    syncFromHolder()
  }

  /* ---------------- save ---------------- */

  /** A square camera that frames ONLY the item — that is what the catalog
   *  thumbnail shows. The player model, grid and floor are hidden for the
   *  shot, and the background is transparent, so the art reads clean on any
   *  card (exactly how classic Roblox catalog thumbnails look). */
  function captureThumb(): Promise<Blob | null> | null {
    const holder = holderRef.current
    const renderer = rendererRef.current
    const scene = sceneRef.current
    const camera = cameraRef.current
    const host = hostRef.current
    if (!holder || !renderer || !scene || !camera || !host) return null

    scene.updateMatrixWorld(true)
    const box = new THREE.Box3().setFromObject(holder)
    if (box.isEmpty()) return null
    const center = box.getCenter(new THREE.Vector3())
    const size = box.getSize(new THREE.Vector3())
    const maxDim = Math.max(size.x, size.y, size.z, 0.001)

    // keep the angle the creator is looking from, then back off to frame the item
    const dir = camera.position.clone().sub(orbitRef.current?.target ?? new THREE.Vector3(0, 2.6, 0))
    if (dir.lengthSq() < 0.0001) dir.set(0.55, 0.45, 1)
    dir.normalize()
    const fovRad = (camera.fov * Math.PI) / 180
    const dist = Math.max((maxDim / 2) / Math.tan(fovRad / 2) * 1.3, maxDim * 0.8)
    const tcam = new THREE.PerspectiveCamera(camera.fov, 1, 0.05, 200)
    tcam.position.copy(center).add(dir.multiplyScalar(dist))
    tcam.lookAt(center)

    // stash + hide everything that is not the item (player, grid, floor,
    // bounds box AND the gizmo arrows/rings — the shot is the art alone)
    const sky = scene.background
    const hidden = ['rb-floor', 'rb-bounds']
    const stashed: { obj: THREE.Object3D; visible: boolean }[] = []
    scene.traverse((o) => {
      if (hidden.includes(o.name)) stashed.push({ obj: o, visible: o.visible })
    })
    const rig = rigViewRef.current
    const rigWasVisible = rig?.visible ?? false
    const grid = scene.children.find((o) => (o as unknown as { isGridHelper?: boolean }).isGridHelper === true)
    const gridWasVisible = grid?.visible ?? false
    // the yellow pivot marker must NEVER bake into the shot either
    const marker = pivotMarkerRef.current
    const markerWasVisible = marker?.visible ?? false
    // find the gizmo helper by flag (NOT via the ref — keeps the capture fn pure)
    const gizmo = scene.children.find((o) => {
      const f = o as unknown as { isTransformControls?: boolean; isTransformControlsRoot?: boolean }
      return f.isTransformControls === true || f.isTransformControlsRoot === true
    })
    const gizmoWasVisible = gizmo?.visible ?? false
    scene.background = null
    if (rig) rig.visible = false
    if (grid) grid.visible = false
    if (marker) marker.visible = false
    if (gizmo) gizmo.visible = false // NO arrows/rings baked into the shot
    stashed.forEach((s) => { s.obj.visible = false })

    // square render pass
    const W = 480
    const prevSize = new THREE.Vector2()
    renderer.getSize(prevSize)
    renderer.setSize(W, W, false)
    renderer.setClearColor(0x000000, 0)
    tcam.aspect = 1
    tcam.updateProjectionMatrix()
    renderer.render(scene, tcam)

    // WHITE background — the user asked for white catalog shots, not transparency
    const out = document.createElement('canvas')
    out.width = W
    out.height = W
    const ctx = out.getContext('2d')
    if (ctx) {
      ctx.fillStyle = '#ffffff'
      ctx.fillRect(0, 0, W, W)
      ctx.drawImage(renderer.domElement, 0, 0, W, W)
    }

    // put the editor back exactly how it was
    renderer.setSize(prevSize.x || 600, prevSize.y || 420, false)
    camera.aspect = (prevSize.x || 600) / Math.max(prevSize.y || 420, 1)
    camera.updateProjectionMatrix()
    scene.background = sky
    if (rig) rig.visible = rigWasVisible
    if (grid) grid.visible = gridWasVisible
    if (marker) marker.visible = markerWasVisible
    if (gizmo) gizmo.visible = gizmoWasVisible
    stashed.forEach((s) => { s.obj.visible = s.visible })
    renderer.render(scene, camera)

    return new Promise<Blob | null>((res) => out.toBlob(res, 'image/png'))
  }

  function save() {
    const holder = holderRef.current
    const wrap = wrapRef.current
    if (!holder || !wrap) return
    enforceWorldSize()

    // bake pivot + transform into the plain Placement format: decompose the
    // model's world matrix — renderers apply it verbatim, pivot and all
    holder.updateMatrixWorld(true)
    const m = new THREE.Matrix4().multiplyMatrices(holder.matrix, wrap.matrix)
    const pos = new THREE.Vector3()
    const quat = new THREE.Quaternion()
    const scl = new THREE.Vector3()
    m.decompose(pos, quat, scl)
    const euler = new THREE.Euler().setFromQuaternion(quat)

    const p: Placement = {
      p: [round(pos.x), round(pos.y), round(pos.z)],
      r: [
        round(THREE.MathUtils.radToDeg(euler.x)),
        round(THREE.MathUtils.radToDeg(euler.y)),
        round(THREE.MathUtils.radToDeg(euler.z)),
      ],
      s: [round(scl.x), round(scl.y), round(scl.z)],
    }

    // the catalog thumbnail: ONLY the item, transparent background
    const shot = captureThumb()
    if (!shot) {
      // extremely defensive fallback: reuse the plain editor frame
      const renderer = rendererRef.current
      if (!renderer) return
      renderer.render(sceneRef.current!, cameraRef.current!)
      const src = renderer.domElement
      const out = document.createElement('canvas')
      out.width = 240
      out.height = 240
      const ctx = out.getContext('2d')
      if (ctx) {
        ctx.fillStyle = '#dcebf5'
        ctx.fillRect(0, 0, 240, 240)
        const side = Math.min(src.width, src.height)
        ctx.drawImage(src, (src.width - side) / 2, (src.height - side) / 2, side, side, 0, 0, 240, 240)
      }
      out.toBlob((blob) => {
        if (blob) onSave({ placement: p, thumb: blob })
      }, 'image/png')
      return
    }
    shot.then((blob) => {
      if (blob) onSave({ placement: p, thumb: blob })
    })
  }

  const step = { move: snapMove || 0.01, turn: snapTurn || 1, scale: snapScale || 0.01 }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 90, background: 'rgba(20,32,44,0.72)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 14,
      }}
      role="dialog"
      aria-modal="true"
      aria-label="3D placement editor"
    >
      <div className="rb-box" style={{ width: 'min(1020px, 100%)', background: '#fff' }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Place your item in 3D</span>
          <button className="rb-btn" style={{ fontSize: 10, padding: '2px 8px' }} onClick={onCancel}>✕</button>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap' }}>
          <div ref={hostRef} style={{ flex: '1 1 420px', height: 'min(58vh, 520px)', minHeight: 300, background: '#dcebf5', position: 'relative' }} />
          <div style={{ flex: '0 0 250px', padding: 12, borderLeft: '1px solid #dbe4ec', background: '#f7fafc', maxHeight: 'min(58vh, 520px)', overflowY: 'auto' }}>
            {/* tools */}
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>Tools</div>
            <div style={{ display: 'flex', gap: 4, marginBottom: 4 }}>
              {MODES.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  onClick={() => setMode(m.id)}
                  aria-pressed={mode === m.id}
                  className="rb-btn"
                  style={{
                    fontSize: 10, flex: 1, padding: '4px 0',
                    background: mode === m.id ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#fff',
                    color: mode === m.id ? '#fff' : '#1c4e7c',
                  }}
                >
                  {m.label} <span style={{ opacity: 0.7 }}>{m.key}</span>
                </button>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 4, marginBottom: 10 }}>
              {/* LOCAL <-> GLOBAL — the gizmo axes follow the item or the world */}
              <button
                type="button"
                className="rb-btn"
                aria-pressed={space === 'world'}
                title="Gizmo space — L flips it anytime. Local follows the item, Global is the world."
                onClick={() => setSpace((s) => (s === 'local' ? 'world' : 'local'))}
                style={{
                  fontSize: 10, flex: 1, padding: '4px 0',
                  background: space === 'world' ? 'linear-gradient(180deg,#7a5cbf,#5a4296)' : '#fff',
                  color: space === 'world' ? '#fff' : '#1c4e7c',
                }}
              >
                {space === 'local' ? 'Local · L' : 'Global · L'}
              </button>
              {/* pivot mode — drag the yellow ball to move the pivot point */}
              <button
                type="button"
                className="rb-btn"
                aria-pressed={pivotMode}
                title="Move the pivot — the point rotations and scales turn around (P)"
                onClick={() => setPivotMode((v) => !v)}
                style={{
                  fontSize: 10, flex: 1, padding: '4px 0',
                  background: pivotMode ? 'linear-gradient(180deg,#e8b23a,#c78f1d)' : '#fff',
                  color: pivotMode ? '#fff' : '#1c4e7c',
                }}
              >
                {pivotMode ? '● Pivot · P' : '⊕ Pivot · P'}
              </button>
            </div>

            {/* snapping */}
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>Snapping</div>
            <div style={{ display: 'grid', gridTemplateColumns: '52px 1fr', gap: '4px 6px', alignItems: 'center', marginBottom: 10 }}>
              <label style={{ fontSize: 10, color: '#41586c' }}>Move</label>
              <select className="rb-input" style={{ fontSize: 10, padding: '2px 4px' }} value={snapMove} onChange={(e) => setSnapMove(Number(e.target.value))} aria-label="Move snap">
                {MOVE_SNAPS.map((s) => <option key={s.v} value={s.v}>{s.label}</option>)}
              </select>
              <label style={{ fontSize: 10, color: '#41586c' }}>Turn</label>
              <select className="rb-input" style={{ fontSize: 10, padding: '2px 4px' }} value={snapTurn} onChange={(e) => setSnapTurn(Number(e.target.value))} aria-label="Rotation snap">
                {TURN_SNAPS.map((s) => <option key={s.v} value={s.v}>{s.label}</option>)}
              </select>
              <label style={{ fontSize: 10, color: '#41586c' }}>Scale</label>
              <select className="rb-input" style={{ fontSize: 10, padding: '2px 4px' }} value={snapScale} onChange={(e) => setSnapScale(Number(e.target.value))} aria-label="Scale snap">
                {SCALE_SNAPS.map((s) => <option key={s.v} value={s.v}>{s.label}</option>)}
              </select>
            </div>

            {/* view: camera angle presets + hide the player */}
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>View</div>
            <div style={{ display: 'flex', gap: 3, flexWrap: 'wrap', marginBottom: 6 }}>
              {([
                ['front', 'Front'],
                ['back', 'Back'],
                ['left', 'Left'],
                ['right', 'Right'],
                ['corner', '¾'],
                ['top', 'Top'],
              ] as const).map(([preset, label]) => (
                <button
                  key={preset}
                  type="button"
                  className="rb-btn"
                  style={{ fontSize: 10, flex: '1 1 30%', padding: '3px 0' }}
                  onClick={() => setCameraAngle(preset)}
                  title={`${label} camera angle`}
                >
                  {label}
                </button>
              ))}
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10, color: '#41586c', cursor: 'pointer', marginBottom: 10 }}>
              <input
                type="checkbox"
                checked={showPlayer}
                onChange={(e) => setShowPlayer(e.target.checked)}
              />
              Show the player model {showPlayer ? '(hide to focus on the item)' : '(hidden)'}
            </label>

            {/* transform by numbers */}
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>Transform</div>
            <NumGrid
              title="Location"
              values={form.loc}
              step={step.move}
              onChange={(a, v) => applyLocation(a, v)}
            />
            <NumGrid
              title="Rotation"
              suffix="°"
              values={form.rot}
              step={step.turn}
              onChange={(a, v) => applyRotation(a, v)}
            />
            <NumGrid
              title="Scale"
              values={form.scale}
              step={step.scale}
              min={PLACEMENT_BOUNDS.scaleMin}
              max={PLACEMENT_BOUNDS.scaleMax}
              onChange={(a, v) => applyScale(a, v)}
            />

            {/* pivot */}
            <div style={{ fontSize: 11, color: '#1c4e7c', margin: '10px 0 2px' }}>Pivot <span style={{ fontWeight: 'normal', color: '#8ba0b3' }}>(turns &amp; scales around this point)</span></div>
            <NumGrid
              values={form.pivot}
              step={step.move}
              onChange={(a, v) => {
                const p = [...form.pivot] as Vec3
                p[a] = v
                setPivot(p)
              }}
            />
            <div style={{ display: 'flex', gap: 4, margin: '4px 0 8px' }}>
              <button className="rb-btn" style={{ fontSize: 10, flex: 1, padding: '3px 0' }} onClick={() => centerPivotOnItem()}>
                ⊕ Center on item
              </button>
              <button className="rb-btn" style={{ fontSize: 10, flex: 1, padding: '3px 0' }} onClick={resetPivot}>
                ↺ Reset pivot
              </button>
            </div>

            <button className="rb-btn" style={{ fontSize: 10, width: '100%', marginBottom: 8 }} onClick={resetItem}>
              ↺ Reset position
            </button>
            <div style={{ fontSize: 9, color: '#5a6b7b', lineHeight: 1.5, marginBottom: 8 }}>
              Drag the gizmo or type exact numbers. W / E / R — move / rotate / scale · L — Local ↔ Global ·
              P — move the pivot with the gizmo. Left-drag spins the camera, right-drag pans, wheel zooms.
              The green wire box is the limit — items can&apos;t leave it, and they can&apos;t be scaled huge.
            </div>
            <div style={{ fontSize: 10, color: '#41586c', marginBottom: 10, minHeight: 30 }}>{status}</div>
            <button className="rb-btn rb-btn-green" style={{ fontSize: 11, width: '100%' }} onClick={save}>
              ✓ Save placement
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

/** Blender-style XYZ row set: a small label + three number inputs.
 *  Each field keeps its own text while you type ("0.", "-" all work) and
 *  snaps back to the live three.js value whenever the gizmo moves it. */
function NumGrid({
  title,
  values,
  step,
  suffix,
  min,
  max,
  onChange,
}: {
  title?: string
  values: [number, number, number]
  step: number
  suffix?: string
  min?: number
  max?: number
  onChange: (axis: 0 | 1 | 2, value: number) => void
}) {
  const axes = ['X', 'Y', 'Z'] as const
  return (
    <div style={{ marginBottom: 6 }}>
      {title && <div style={{ fontSize: 9, color: '#7b8896', marginBottom: 2 }}>{title}</div>}
      <div style={{ display: 'grid', gridTemplateColumns: '14px 1fr 14px 1fr 14px 1fr', gap: 3, alignItems: 'center' }}>
        {axes.map((a, i) => (
          <NumField
            key={a}
            axis={i as 0 | 1 | 2}
            label={`${title || 'Pivot'} ${a}`}
            letter={a}
            color={i === 0 ? '#b0433a' : i === 1 ? '#3d8f3d' : '#3a6db0'}
            value={values[i]}
            step={step}
            min={min}
            max={max}
            onChange={onChange}
          />
        ))}
      </div>
      {suffix && <div style={{ fontSize: 8, color: '#8ba0b3', marginTop: 1 }}>in degrees</div>}
    </div>
  )
}

function NumField({
  axis,
  label,
  letter,
  color,
  value,
  step,
  min,
  max,
  onChange,
}: {
  axis: 0 | 1 | 2
  label: string
  letter: string
  color: string
  value: number
  step: number
  min?: number
  max?: number
  onChange: (axis: 0 | 1 | 2, value: number) => void
}) {
  const [txt, setTxt] = useState(String(value))
  const [prevVal, setPrevVal] = useState(value)
  // external changes (gizmo drags, snapping, resets) win over stale text —
  // the React "adjust state on prop change" pattern, done during render
  if (prevVal !== value) {
    setPrevVal(value)
    if (parseFloat(txt) !== value) setTxt(String(value))
  }
  return (
    <span style={{ display: 'contents' }}>
      <span style={{ fontSize: 9, color, textAlign: 'right', fontFamily: 'monospace' }}>{letter}</span>
      <input
        className="rb-input"
        type="number"
        value={txt}
        step={step}
        min={min}
        max={max}
        aria-label={label}
        onChange={(e) => {
          setTxt(e.target.value)
          const v = parseFloat(e.target.value)
          if (isFinite(v)) onChange(axis, v)
        }}
        style={{ fontSize: 10, padding: '2px 3px', fontFamily: 'monospace', width: '100%' }}
      />
    </span>
  )
}
