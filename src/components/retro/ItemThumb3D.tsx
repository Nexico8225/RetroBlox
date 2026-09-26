'use client'

/* ItemThumb3D — the CLEAN catalog thumbnail for 3D UGC, rendered live.
   Older items were published before the clean capture existed, so their
   stored PNG has the old blue sky + player model + gizmo arrows baked in.
   Instead of asking every creator to re-upload, we render the item alone
   (its saved placement applied EXACTLY) onto a WHITE background and show
   that everywhere a thumbnail appears. Same rule as the editor's capture:
   the shot is the art alone — no player, no grid, no arrows, no sky. */

import { useEffect, useState } from 'react'
import * as THREE from 'three'
import { clone as skeletonClone } from 'three/examples/jsm/utils/SkeletonUtils.js'
import { attachPlacedModel, applyModelSurface, loadGltfModel } from '@/lib/three/rig'
import type { Placement } from '@/lib/avatarAssets'

/* One cache per browser session: model url + placement -> white data-url.
   WebGL contexts are scarce (browsers cap them ~8-16) — every render
   force-loses its context so a catalog full of 3D items can never exhaust
   the pool and blank out thumbnails (the "ugc images dont show up" bug). */
const thumbCache = new Map<string, string>()
const inflight = new Map<string, Promise<string>>()

function cacheKey(modelUrl: string, placement: Placement | null, zoom: number, textureUrl?: string, color?: string) {
  return `${modelUrl}|${placement ? JSON.stringify(placement) : 'none'}|${zoom}|${textureUrl || ''}|${color || ''}`
}

/** Render the placed item alone onto a white square, return a PNG data-url. */
async function renderItemThumb(
  modelUrl: string,
  placement: Placement | null,
  zoom: number,
  textureUrl?: string,
  color?: string
): Promise<string> {
  const SIZE = 512
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
  renderer.setPixelRatio(1)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.setSize(SIZE, SIZE, false)

  const scene = new THREE.Scene()
  scene.background = null // composited onto white by the 2d canvas below
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8899aa, 1.15))
  const sun = new THREE.DirectionalLight(0xffffff, 1.6)
  sun.position.set(4, 9, 6)
  scene.add(sun)
  const sun2 = new THREE.DirectionalLight(0xffffff, 0.7)
  sun2.position.set(-6, 3, -4)
  scene.add(sun2)

  // the item, exactly where its creator left it (placement wraps the
  // normalized model — never overrides the model's own scale)
  const src = await loadGltfModel(modelUrl)
  const inst = skeletonClone(src)
  // the creator's texture / color, exactly as published
  await applyModelSurface(inst, { textureUrl, color })
  const holder = attachPlacedModel(inst, placement)
  scene.add(holder)
  scene.updateMatrixWorld(true)

  // frame ONLY the item (a touch of headroom so nothing clips)
  const box = new THREE.Box3().setFromObject(holder)
  if (box.isEmpty()) throw new Error('empty model')
  const center = box.getCenter(new THREE.Vector3())
  const size = box.getSize(new THREE.Vector3())
  const maxDim = Math.max(size.x, size.y, size.z, 0.001)
  const fov = 32 // narrow fov = the flat "product shot" look
  const dist = (maxDim / 2) / Math.tan((fov * Math.PI) / 360) * 1.12 * zoom

  // a friendly three-quarter view of the item (front-right, slightly above)
  const cam = new THREE.PerspectiveCamera(fov, 1, 0.01, 500)
  cam.position.set(center.x + dist * 0.42, center.y + dist * 0.34, center.z + dist * 0.86)
  cam.lookAt(center)

  renderer.render(scene, cam)

  // composite onto WHITE — the user asked for white, not transparency
  const out = document.createElement('canvas')
  out.width = SIZE
  out.height = SIZE
  const ctx = out.getContext('2d')!
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, SIZE, SIZE)
  ctx.drawImage(renderer.domElement, 0, 0, SIZE, SIZE)

  // free the GPU + CPU copies before returning — forceContextLoss releases
  // the WebGL context IMMEDIATELY (dispose alone leaves it to the GC)
  renderer.dispose()
  renderer.forceContextLoss()
  holder.traverse((o) => {
    const m = o as THREE.Mesh
    if (!m.isMesh) return
    m.geometry?.dispose()
    const mat = m.material as THREE.Material | THREE.Material[]
    if (Array.isArray(mat)) mat.forEach((x) => x.dispose())
    else mat?.dispose()
  })

  return out.toDataURL('image/png')
}

function getThumb(modelUrl: string, placement: Placement | null, zoom: number, textureUrl?: string, color?: string): Promise<string> {
  const key = cacheKey(modelUrl, placement, zoom, textureUrl, color)
  const hit = thumbCache.get(key)
  if (hit) return Promise.resolve(hit)
  let p = inflight.get(key)
  if (!p) {
    p = renderItemThumb(modelUrl, placement, zoom, textureUrl, color)
      .then((url) => {
        thumbCache.set(key, url)
        inflight.delete(key)
        return url
      })
      .catch((e) => {
        inflight.delete(key)
        throw e
      })
    inflight.set(key, p)
  }
  return p
}

export default function ItemThumb3D({
  modelUrl,
  placement,
  alt,
  zoom = 1,
  style,
  fallbackSrc,
  textureUrl,
  color,
}: {
  modelUrl: string
  placement?: Placement | null
  alt: string
  /** > 1 zooms out (small item in frame), < 1 zooms in */
  zoom?: number
  style?: React.CSSProperties
  /** the item's SAVED thumbnail — shown while rendering and if the live
   *  3D render ever fails, so the image slot can never end up blank */
  fallbackSrc?: string
  /** optional creator texture wrapped around the model */
  textureUrl?: string
  /** optional tint when the model has no texture */
  color?: string
}) {
  const [src, setSrc] = useState<string | null>(() => thumbCache.get(cacheKey(modelUrl, placement || null, zoom, textureUrl, color)) || null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let alive = true
    // async 3D render -> can only resolve client-side after mount, so the
    // result legitimately lands in state from this effect. `failed` is only
    // ever set asynchronously — never synchronously in the effect body.
    getThumb(modelUrl, placement || null, zoom, textureUrl, color)
      .then((url) => { if (alive) { setSrc(url); setFailed(false) } })
      .catch(() => { if (alive) setFailed(true) })
    return () => { alive = false }
  }, [modelUrl, placement, zoom, textureUrl, color])

  if (failed || !src) {
    // rendering, or the live render failed — the saved thumbnail stands in
    if (fallbackSrc) return <img src={fallbackSrc} alt={alt} style={style} />
  }

  if (failed) {
    // no fallback provided — fall back to whatever is behind us (callers keep the stored image underneath)
    return null
  }

  return src ? (
    <img src={src} alt={alt} style={style} />
  ) : (
    <span
      aria-label={alt}
      style={{
        ...style,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: '#fff', color: '#9aa7b4', fontSize: 10, fontFamily: 'Verdana, sans-serif',
      }}
    >
      ...
    </span>
  )
}
