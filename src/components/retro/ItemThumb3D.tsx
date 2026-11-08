'use client'

/* ItemThumb3D — the CLEAN catalog thumbnail for 3D UGC, rendered live.
   Older items were published before the clean capture existed, so their
   stored PNG has the old blue sky + player model + gizmo arrows baked in.
   Instead of asking every creator to re-upload, we render the item alone
   (its saved placement applied EXACTLY) onto a crisp white background and show
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

/* One cache per browser session: model url + placement -> data-url. */
const thumbCache = new Map<string, string>()
const inflight = new Map<string, Promise<string>>()

/* REUSABLE SINGLETON WEBGL RENDERER:
   Browsers strictly cap active WebGL contexts per page (~8-16).
   Destroying and recreating contexts on every card causes context loss
   and blank white cards. A single shared offscreen renderer with
   preserveDrawingBuffer: true guarantees zero context loss and reliable pixel reads. */
let sharedRenderer: THREE.WebGLRenderer | null = null

function getSharedRenderer(): THREE.WebGLRenderer {
  if (!sharedRenderer) {
    const canvas = document.createElement('canvas')
    sharedRenderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: true,
      preserveDrawingBuffer: true,
      powerPreference: 'high-performance',
    })
    sharedRenderer.setPixelRatio(1)
    sharedRenderer.outputColorSpace = THREE.SRGBColorSpace
    sharedRenderer.setSize(512, 512, false)
  }
  return sharedRenderer
}

/* Serialized queue so at most one card renders at a time on the shared renderer */
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
  const renderer = getSharedRenderer()

  const scene = new THREE.Scene()
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8899aa, 1.35))
  const sun = new THREE.DirectionalLight(0xffffff, 1.8)
  sun.position.set(5, 10, 7)
  scene.add(sun)
  const sun2 = new THREE.DirectionalLight(0xffffff, 0.85)
  sun2.position.set(-7, 4, -5)
  scene.add(sun2)

  // Load the model
  const src = await loadGltfModel(modelUrl)
  const inst = skeletonClone(src)
  await applyModelSurface(inst, { textureUrl, color, roughness, metallic })
  const holder = attachPlacedModel(inst, placement)
  // If no custom placement transform was passed, default to facing front (+Z)
  if (!placement) {
    inst.rotation.y = Math.PI
  }
  scene.add(holder)
  scene.updateMatrixWorld(true)

  // CENTER THE MODEL AT LOCAL (0, 0, 0):
  // Placement might position the hat high up on a character (e.g. Y=4.85),
  // or the model may have internal bone/mesh offsets.
  // By shifting holder.position by -center, the visual item is centered exactly at (0, 0, 0)
  // so the lights and camera frame it dead-center!
  const box = new THREE.Box3().setFromObject(holder)
  if (box.isEmpty()) throw new Error('empty model')
  const center = box.getCenter(new THREE.Vector3())
  holder.position.sub(center)
  holder.updateMatrixWorld(true)

  // Recalculate true centered bounds
  box.setFromObject(holder)
  const size = box.getSize(new THREE.Vector3())
  const maxDim = Math.max(size.x, size.y, size.z, 0.001)

  const sphere = new THREE.Sphere()
  box.getBoundingSphere(sphere)
  const radius = Math.max(sphere.radius, maxDim * 0.58)

  const fov = 32
  const fovRad = (fov * Math.PI) / 180
  // 45% margin ensures wide baseplates (traffic cone), antler horns, and tentacles never clip:
  const dist = (radius / Math.sin(fovRad / 2)) * 1.45 * zoom

  // Three-quarter angle: front-right, slightly elevated
  const cam = new THREE.PerspectiveCamera(fov, 1, 0.05, 500)
  cam.position.set(dist * 0.45, dist * 0.35, dist * 0.85)
  cam.lookAt(0, 0, 0)

  renderer.clear()
  renderer.render(scene, cam)

  // Composite onto crisp white background
  const out = document.createElement('canvas')
  out.width = SIZE
  out.height = SIZE
  const ctx = out.getContext('2d')!
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, SIZE, SIZE)
  ctx.drawImage(renderer.domElement, 0, 0, SIZE, SIZE)

  // Clean up scene without destroying shared geometry/materials from cache
  scene.remove(holder)
  scene.clear()

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
