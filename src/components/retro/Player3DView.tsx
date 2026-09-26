'use client'

/* Player3DView — the R6 player model rendered live in 3D, wearing whatever
   the look says (clothing textures, t-shirt/face decals, placed 3D UGC).
   Used by the Avatar Editor (try-on like Roblox) and the Catalog ("Try on
   in 3D"). One shared renderer per instance; orbit camera when interactive. */

import { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import {
  applyLook,
  loadClipsRetargeted,
  prepareRigView,
  stopWornMixers,
  updateWornMixers,
  type AvatarLook3D,
  type LoadedRig,
} from '@/lib/three/rig'

/** Animation playback on the player model: retargeted by node-name, so a
 *  clip made on the R6 template drives the real body.
 *  - single: loop one clip forever (an EMOTE playing)
 *  - cycle : run the mapped clips in sequence (idle -> walk -> jump -> climb
 *            -> fall) — the REALTIME "my anims replace the classic moves" look */
export interface RigAnim {
  url: string
  clips: string[]
  single?: boolean
}

interface Player3DViewProps {
  look: AvatarLook3D
  height?: number
  /** orbit camera on/off (drag = rotate view) */
  interactive?: boolean
  /** camera distance multiplier (1 = default framing) */
  zoom?: number
  /** 2D render mode: the SAME model locked to a straight front camera and
   *  non-interactive — exactly how a catalog listing shows the character. */
  flat?: boolean
  className?: string
  /** rigged clips to play ON the body (emote / animation pack) */
  anim?: RigAnim | null
}

export default function Player3DView({ look, height = 320, interactive = true, zoom = 1, flat = false, className, anim = null }: Player3DViewProps) {
  const hostRef = useRef<HTMLDivElement>(null)
  const [ready, setReady] = useState(false)
  const stateRef = useRef<{ view: THREE.Group; rig: LoadedRig } | null>(null)
  const lookRef = useRef<AvatarLook3D>(look)
  // the look object arrives fresh each render — key it by its data
  const lookKey = JSON.stringify(look)
  const animKey = anim ? `${anim.url}|${anim.clips.join(',')}|${anim.single ? 1 : 0}` : ''
  // the retargeted clip sequence, shared between the anim effect and the raf loop
  const mixerSeqRef = useRef<{ mixer: THREE.AnimationMixer; seq: THREE.AnimationAction[]; idx: number; timer: number; single: boolean } | null>(null)

  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    let disposed = false
    let raf = 0
    let ro: ResizeObserver | null = null

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.shadowMap.enabled = true
    renderer.shadowMap.type = THREE.PCFSoftShadowMap
    renderer.outputColorSpace = THREE.SRGBColorSpace
    renderer.domElement.style.display = 'block'
    renderer.domElement.style.width = '100%'
    renderer.domElement.style.touchAction = interactive && !flat ? 'none' : 'auto'
    host.appendChild(renderer.domElement)

    const scene = new THREE.Scene()
    scene.background = new THREE.Color('#dcebf5') // the same sky the 2D preview paints

    /* STUDIO LIGHTING — a proper three-point setup so the character pops
       (the old single-hemisphere look was flat and dull):
       - soft hemisphere base so nothing ever goes pitch black
       - warm KEY sun from the front-right-top (casts the self-shadow)
       - cool FILL from the front-left lifts the shadow side
       - RIM from behind separates the character from the sky */
    const hemi = new THREE.HemisphereLight(0xffffff, 0x9db4c6, 1.35)
    scene.add(hemi)
    const sun = new THREE.DirectionalLight(0xfff4e0, 2.1) // warm key
    sun.position.set(5, 10, 7)
    sun.castShadow = true
    sun.shadow.mapSize.set(2048, 2048)
    sun.shadow.camera.left = -4
    sun.shadow.camera.right = 4
    sun.shadow.camera.top = 7
    sun.shadow.camera.bottom = -1
    sun.shadow.bias = -0.0004
    scene.add(sun)
    const fill = new THREE.DirectionalLight(0xdfeeff, 0.85) // cool fill
    fill.position.set(-7, 4, 6)
    scene.add(fill)
    const rim = new THREE.DirectionalLight(0xffffff, 1.15) // back rim
    rim.position.set(-2, 8, -9)
    scene.add(rim)

    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 200)
    // framed so a hat at the top of the head (y ~6.6) stays in shot
    camera.position.set(6.8 * zoom, 4.8 * zoom, 10.4 * zoom)

    // 2D mode: dead-straight front camera, no controls — it LOOKS like a
    // flat render because it literally cannot move
    if (flat) {
      camera.position.set(0, 3.0, 10.6 * zoom)
      camera.lookAt(0, 2.95, 0)
    }

    const controls = interactive && !flat ? new OrbitControls(camera, renderer.domElement) : null
    if (controls) {
      controls.target.set(0, 2.55, 0)
      controls.enableDamping = true
      controls.dampingFactor = 0.08
      controls.minDistance = 3
      controls.maxDistance = 30
      // no ground plane anymore — allow orbiting almost fully around/under
      controls.maxPolarAngle = Math.PI * 0.85
      controls.update()
    }

    const resize = () => {
      const w = host.clientWidth || 240
      const h = host.clientHeight || height
      renderer.setSize(w, h, false)
      camera.aspect = w / Math.max(h, 1)
      camera.updateProjectionMatrix()
    }
    ro = new ResizeObserver(resize)
    ro.observe(host)
    resize()

    const animate = () => {
      if (disposed) return
      raf = requestAnimationFrame(animate)
      controls?.update()
      // advance the retargeted clip sequence (emote loop / anim-pack cycle)
      const seq = mixerSeqRef.current
      if (seq) {
        seq.mixer.update(1 / 60)
        seq.timer += 1 / 60
        if (!seq.single && seq.seq.length > 1) {
          const cur = seq.seq[seq.idx]
          const dur = Math.min(cur.getClip().duration, 2.6)
          if (seq.timer >= dur) {
            seq.timer = 0
            cur.fadeOut(0.24)
            seq.idx = (seq.idx + 1) % seq.seq.length
            seq.seq[seq.idx].reset().fadeIn(0.24).play()
          }
        }
      }
      // advance self-animated UGC worn on this view (pets, wings, ...)
      const stash = stateRef.current
      if (stash) updateWornMixers(stash.view, 1 / 60)
      renderer.render(scene, camera)
    }
    animate()

    prepareRigView()
      .then(({ view, rig }) => {
        if (disposed) return
        stateRef.current = { view, rig }
        scene.add(view)
        setReady(true)
        return applyLook(view, rig, lookRef.current)
      })
      .catch(() => {
        if (!disposed) setReady(true) // stop the spinner even on failure
      })

    return () => {
      disposed = true
      cancelAnimationFrame(raf)
      ro?.disconnect()
      controls?.dispose()
      const stash = stateRef.current
      if (stash) {
        stopWornMixers(stash.view)
        scene.remove(stash.view)
        stash.view.traverse((o) => {
          const m = o as THREE.Mesh
          if (!m.isMesh) return
          const mat = m.material as THREE.Material | THREE.Material[]
          if (Array.isArray(mat)) mat.forEach((x) => x.dispose())
          else mat?.dispose()
        })
        stateRef.current = null
      }
      renderer.dispose()
      if (renderer.domElement.parentElement === host) host.removeChild(renderer.domElement)
    }
    // rebuild the whole scene when the framing changes; look changes are handled below
  }, [interactive, zoom, flat])

  // look changes — re-dress the existing rig instead of rebuilding the scene
  useEffect(() => {
    lookRef.current = JSON.parse(lookKey) as AvatarLook3D
    const stash = stateRef.current
    if (!stash) return // mount effect applies the first look once ready
    applyLook(stash.view, stash.rig, lookRef.current).catch(() => {})
  }, [lookKey])

  // rigged clips — load, retarget by node name, and hand to the animate loop.
  // single=true loops one clip (an emote); otherwise the mapped clips cycle
  // in order: the realtime idle -> walk -> jump -> climb -> fall takeover.
  useEffect(() => {
    if (!anim || anim.clips.length === 0) return
    let cancelled = false
    const stash = stateRef.current
    if (!stash) return
    const view = stash.view
    loadClipsRetargeted(anim.url, view)
      .then((bound) => {
        if (cancelled || bound.length === 0) return
        const ordered: THREE.AnimationClip[] = []
        for (const name of anim.clips) {
          const hit = bound.find((c) => c.name === name)
          if (hit) ordered.push(hit)
        }
        if (ordered.length === 0) ordered.push(...bound)
        const mixer = new THREE.AnimationMixer(view)
        const actions = ordered.map((c) => mixer.clipAction(c))
        actions.forEach((a, i) => a.play())
        // restart the sequence when the component re-animates — a fresh
        // seq ref keeps the animate loop below from advancing a dead mixer
        mixerSeqRef.current = { mixer, seq: actions, idx: 0, timer: 0, single: !!anim.single }
        if (anim.single && actions[0]) {
          actions.slice(1).forEach((a) => a.stop())
        }
      })
      .catch(() => {})
    return () => {
      cancelled = true
      const cur = mixerSeqRef.current
      if (cur) {
        cur.mixer.stopAllAction()
        mixerSeqRef.current = null
      }
    }
  }, [animKey])

  return (
    <div
      ref={hostRef}
      className={className}
      style={{ position: 'relative', height, width: '100%', overflow: 'hidden', background: '#dcebf5' }}
    >
      {!ready && (
        <div
          style={{
            position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 11, color: '#5a6b7b', background: '#eaf2f9', zIndex: 2,
          }}
        >
          warming up the player model...
        </div>
      )}
    </div>
  )
}
