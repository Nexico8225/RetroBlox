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

/* Fallback SVG generator so broken/missing models or files NEVER show a blank white box */
function thumbPlaceholder(label: string): string {
  const cleanLabel = (label || 'UGC').toUpperCase().slice(0, 14)
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'>`
    + `<rect width='220' height='220' fill='#f5f8fb'/>`
    + `<rect x='10' y='10' width='200' height='200' fill='none' stroke='#d0dbe5' stroke-width='3' stroke-dasharray='8 6' rx='12'/>`
    + `<circle cx='110' cy='85' r='30' fill='none' stroke='#b0c2d2' stroke-width='4'/>`
    + `<path d='M65 160 L95 115 L115 138 L135 110 L160 160 Z' fill='#d8e3ed'/>`
    + `<text x='110' y='194' font-family='Verdana,sans-serif' font-size='15' font-weight='bold' fill='#8da0b2' text-anchor='middle'>${cleanLabel}</text>`
    + `</svg>`
  return `data:image/svg+xml,${encodeURIComponent(svg)}`
}

/* One cache per browser session: model url + placement -> white data-url. */
const thumbCache = new Map<string, string>()
const inflight = new Map<string, Promise<string>>()

/* QUEUE RENDERING: Browsers strictly cap active WebGL contexts (~8 to 16).
   If 20 catalog cards render simultaneously, contexts get destroyed by the browser,
   causing cards to turn into blank white boxes.
   Running them through a serialized queue guarantees at most 1 active context at any time. */
let renderQueue: Promise<unknown> = Promise.resolve()

function queueRender<T>(task: () => Promise<T>): Promise<T> {
  const run = () => task()
  const p = renderQueue.then(run, run)
  renderQueue = p.then(() => {}, () => {})
  return p
}

function cacheKey(
  modelUrl: string,
  placement: Placement | null,
  zoom: number,
  textureUrl?: string,
  color?: string,
  roughness?: number | null,
  metallic?: number | null
) {
  return `${modelUrl}|${placement ? JSON.stringify(placement) : 'none'}|${zoom}|${textureUrl || ''}|${color || ''}|${roughness ?? ''}|${metallic ?? ''}`
}

/** Render the placed item alone onto a white square, return a PNG data-url. */
async function renderItemThumb(
  modelUrl: string,
  placement: Placement | null,
  zoom: number,
  textureUrl?: string,
  color?: string,
  roughness?: number | null,
  metallic?: number | null
): Promise<string> {
  const SIZE = 512
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
  renderer.setPixelRatio(1)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.setSize(SIZE, SIZE, false)

  const scene = new THREE.Scene()
  scene.background = null // composited onto white by the 2d canvas below
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8899aa, 1.25))
  const sun = new THREE.DirectionalLight(0xffffff, 1.6)
  sun.position.set(5, 10, 7)
  scene.add(sun)
  const sun2 = new THREE.DirectionalLight(0xffffff, 0.75)
  sun2.position.set(-7, 4, -5)
  scene.add(sun2)

  // Load the model
  const src = await loadGltfModel(modelUrl)
  const inst = skeletonClone(src)
  await applyModelSurface(inst, { textureUrl, color, roughness, metallic })
  const holder = attachPlacedModel(inst, placement)
  scene.add(holder)
  scene.updateMatrixWorld(true)

  // CALCULATE PROPER BOUNDS & CAMERA DISTANCE:
  // Using bounding sphere radius + trigonometric field-of-view formula ensures
  // wide items (like Traffic Cone, wide hats, crowns) never clip out of the frame!
  const box = new THREE.Box3().setFromObject(holder)
  if (box.isEmpty()) throw new Error('empty model')
  const center = box.getCenter(new THREE.Vector3())
  const size = box.getSize(new THREE.Vector3())
  const maxDim = Math.max(size.x, size.y, size.z, 0.001)

  const sphere = new THREE.Sphere()
  box.getBoundingSphere(sphere)
  const radius = Math.max(sphere.radius, maxDim * 0.6)

  const fov = 32 // narrow fov = clean orthographic-like product shot
  const fovRad = (fov * Math.PI) / 180
  // Standard sphere-in-frustum distance with ~35% safety margin:
  const dist = (radius / Math.sin(fovRad / 2)) * 1.35 * zoom

  // Three-quarter angle: front-right, slightly elevated
  const cam = new THREE.PerspectiveCamera(fov, 1, 0.01, 500)
  cam.position.set(
    center.x + dist * 0.42,
    center.y + dist * 0.35,
    center.z + dist * 0.85
  )
  cam.lookAt(center)

  renderer.render(scene, cam)

  // Composite onto crisp white background
  const out = document.createElement('canvas')
  out.width = SIZE
  out.height = SIZE
  const ctx = out.getContext('2d')!
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, SIZE, SIZE)
  ctx.drawImage(renderer.domElement, 0, 0, SIZE, SIZE)

  // Immediately release WebGL resources to preserve GPU contexts
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

function getThumb(
  modelUrl: string,
  placement: Placement | null,
  zoom: number,
  textureUrl?: string,
  color?: string,
  roughness?: number | null,
  metallic?: number | null
): Promise<string> {
  const key = cacheKey(modelUrl, placement, zoom, textureUrl, color, roughness, metallic)
  const hit = thumbCache.get(key)
  if (hit) return Promise.resolve(hit)
  let p = inflight.get(key)
  if (!p) {
    p = queueRender(() =>
      renderItemThumb(modelUrl, placement, zoom, textureUrl, color, roughness, metallic)
    )
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
  roughness,
  metallic,
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
  /** optional creator finish overrides (0..1) — null = the model's own */
  roughness?: number | null
  metallic?: number | null
}) {
  const [src, setSrc] = useState<string | null>(() =>
    thumbCache.get(cacheKey(modelUrl, placement || null, zoom, textureUrl, color, roughness, metallic)) || null
  )
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let alive = true
    getThumb(modelUrl, placement || null, zoom, textureUrl, color, roughness, metallic)
      .then((url) => {
        if (alive) {
          setSrc(url)
          setFailed(false)
        }
      })
      .catch(() => {
        if (alive) {
          setFailed(true)
        }
      })
    return () => {
      alive = false
    }
  }, [modelUrl, placement, zoom, textureUrl, color, roughness, metallic])

  // If live 3D thumbnail finished successfully:
  if (src) {
    return <img src={src} alt={alt} style={style} />
  }

  // If render failed: show fallbackSrc or retro placeholder SVG (never a white void)
  if (failed) {
    const defaultPlaceholder = thumbPlaceholder(alt)
    return (
      <img
        src={fallbackSrc || defaultPlaceholder}
        alt={alt}
        style={style}
        onError={(e) => {
          if (!e.currentTarget.src.startsWith('data:')) {
            e.currentTarget.src = defaultPlaceholder
          }
        }}
      />
    )
  }

  // Still rendering: show fallback image or placeholder while 3D queues
  return fallbackSrc ? (
    <img
      src={fallbackSrc}
      alt={alt}
      style={style}
      onError={(e) => {
        const ph = thumbPlaceholder(alt)
        if (!e.currentTarget.src.startsWith('data:')) {
          e.currentTarget.src = ph
        }
      }}
    />
  ) : (
    <img
      src={thumbPlaceholder(alt)}
      alt={alt}
      style={style}
    />
  )
}
