'use client'

/* ------------------------------------------------------------------
   RETROBLOX 3D — the real player model (R6IK.fbx) + UGC pipeline.

   The rig is the user's own Blender R6 rig (Head / Torso / 2 Arms /
   2 Legs + IK bones). We load it once, normalize it to 5 units tall
   standing on y=0, and expose the body parts by name so clothing and
   UGC can attach.

   SACRED PLACEMENT RULE: 3D UGC (hats / gear / accessories) carries a
   Placement authored by its creator in the placement editor. We apply
   p / r / s EXACTLY as stored — no auto-centering, no auto-fit, no
   "smart" repositioning. What the creator placed is what everyone sees.

   Clothing semantics (matches the user's description):
     tshirt -> just an image decal on the FRONT of the torso
     shirt  -> a texture that wraps the torso + arms (template zones
               when the official 300x190 template is detected)
     pants  -> same idea, wraps the legs (220x190 template zones)
     face   -> image decal on the front of the head
------------------------------------------------------------------ */

import * as THREE from 'three'
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { clone as skeletonClone } from 'three/examples/jsm/utils/SkeletonUtils.js'
import {
  SHIRT_TEMPLATE,
  PANTS_TEMPLATE,
  faceImageUrl,
  sanitizeFaceScale,
  type AssetInfo,
  type AvatarConfigT,
  type AvatarPartColors,
  type Placement,
} from '@/lib/avatarAssets'

export const RIG_MODEL_URL = '/models/R6IK.fbx'
export const RIG_HEIGHT = 5 // normalized rig height in world units
/** The official R6 rig template every animator can download and rig against
 *  in Blender — its node names (Head / Torso / Left Arm / Right Arm /
 *  Left Leg / Right Leg) are what animation clips retarget from. */
export const R6_TEMPLATE_URL = '/models/retroblox-rig-template.glb'

/** UGC models are normalized to this max dimension BEFORE the creator's
 *  placement applies — the placement editor does the exact same normalize
 *  at authoring time, so every renderer reproduces the editor's world 1:1. */
export const UGC_IMPORT_SIZE = 1.6

/* ---------------- rig loading ---------------- */

export type PartKey = 'head' | 'torso' | 'armL' | 'armR' | 'legL' | 'legR'

const PART_ALIASES: Record<PartKey, string[]> = {
  head: ['head'],
  torso: ['torso'],
  armL: ['left arm', 'leftarm', 'arm_l', 'l arm'],
  armR: ['right arm', 'rightarm', 'arm_r', 'r arm'],
  legL: ['left leg', 'leftleg', 'leg_l', 'l leg'],
  legR: ['right leg', 'rightleg', 'leg_r', 'r leg'],
}

export interface LoadedRig {
  /** identity group standing on y=0, facing +Z, exactly RIG_HEIGHT tall */
  group: THREE.Group
  parts: Map<PartKey, THREE.Object3D[]>
  /** part bounding boxes in group-local space (= world when group sits at origin) */
  boxes: Map<PartKey, THREE.Box3>
  /** the part's REAL front surface (world z, from actual vertices) — some
   *  FBX bboxes run AHEAD of the true mesh, which used to make the face
   *  decal float visibly in front of the head. Anchored to vertices now. */
  frontZ: Map<PartKey, number>
}

let rigPromise: Promise<LoadedRig> | null = null

function normName(name: string): string {
  return name.toLowerCase().replace(/\$[a-z0-9_]+/g, '').replace(/[\s\._]+/g, ' ').trim()
}

function matchPart(name: string): PartKey | null {
  const n = normName(name)
  if (!n) return null
  for (const key of Object.keys(PART_ALIASES) as PartKey[]) {
    for (const alias of PART_ALIASES[key]) {
      if (n === alias || n.startsWith(alias + ' ') || n.startsWith(alias + '.') || n.startsWith(alias + '_')) return key
    }
  }
  return null
}
export { matchPart }

/** Load + normalize the R6 player model once per session (cached). */
export function loadRig(): Promise<LoadedRig> {
  if (rigPromise) return rigPromise
  rigPromise = (async () => {
    const fbx = await new FBXLoader().loadAsync(RIG_MODEL_URL)

    // The R6IK rig comes out of Blender facing -Z; turn it to face us (+Z).
    const yawWrap = new THREE.Group()
    yawWrap.add(fbx)
    fbx.rotation.y = Math.PI

    // normalize: 5 units tall, feet on y=0, centered on x/z
    const box = new THREE.Box3().setFromObject(yawWrap)
    const size = box.getSize(new THREE.Vector3())
    const s = RIG_HEIGHT / Math.max(size.y, 0.0001)
    yawWrap.scale.setScalar(s)
    yawWrap.updateMatrixWorld(true)

    const group = new THREE.Group()
    group.add(yawWrap)
    group.updateMatrixWorld(true)

    const nb = new THREE.Box3().setFromObject(group)
    const nc = nb.getCenter(new THREE.Vector3())
    yawWrap.position.x -= nc.x
    yawWrap.position.z -= nc.z
    yawWrap.position.y -= nb.min.y
    group.updateMatrixWorld(true)

    // find body part meshes + hide everything that is not body (IK controls,
    // helper planes the rig author left around, etc.)
    const parts = new Map<PartKey, THREE.Object3D[]>()
    const bodyish: THREE.Object3D[] = []
    group.traverse((o) => {
      const mesh = o as THREE.Mesh
      if (!mesh.isMesh) return
      const key = matchPart(o.name)
      const geoName = mesh.geometry?.name || ''
      if (key || matchPart(geoName)) {
        const k = key || matchPart(geoName)!
        const list = parts.get(k) || []
        list.push(mesh)
        parts.set(k, list)
        bodyish.push(o)
      }
    })
    group.traverse((o) => {
      const mesh = o as THREE.Mesh
      if (!mesh.isMesh) return
      if (bodyish.includes(o)) return
      o.visible = false // IK control meshes, helper planes, etc.
    })

    const boxes = new Map<PartKey, THREE.Box3>()
    const frontZ = new Map<PartKey, number>()
    const vtx = new THREE.Vector3()
    for (const key of Object.keys(PART_ALIASES) as PartKey[]) {
      const list = parts.get(key)
      if (!list || list.length === 0) continue
      const b = new THREE.Box3()
      let zmax = -Infinity
      for (const m of list) {
        b.expandByObject(m)
        // walk the REAL vertices — the rendered surface is the truth
        const mesh = m as THREE.Mesh
        const pos = mesh.geometry?.attributes?.position
        if (pos) {
          mesh.updateWorldMatrix(true, false)
          for (let i = 0; i < pos.count; i++) {
            vtx.set(pos.getX(i), pos.getY(i), pos.getZ(i)).applyMatrix4(mesh.matrixWorld)
            if (vtx.z > zmax) zmax = vtx.z
          }
        }
      }
      boxes.set(key, b)
      if (Number.isFinite(zmax)) frontZ.set(key, zmax)
    }

    if (typeof window !== 'undefined') {
      window.__rbRigDump = () => {
        const lines: string[] = []
        group.traverse((o) => {
          const mesh = o as THREE.Mesh
          const type = mesh.isMesh ? ((mesh as unknown as { isSkinnedMesh?: boolean }).isSkinnedMesh ? 'SkinnedMesh' : 'Mesh') : o.type
          lines.push(`${o.name || '<anon>'} [${type}] parent=${o.parent?.name || '<none>'} visible=${o.visible} geo=${mesh.geometry?.name || ''}`)
        })
        return lines.join('\n')
      }
    }

    return { group, parts, boxes, frontZ }
  })()
  return rigPromise
}

// Console hook: after any 3D view loads, `__rbRigDump()` in DevTools prints
// the rig's scene tree — handy when a creator's rig uses unexpected names.
declare global {
  interface Window { __rbRigDump?: () => void }
}

/** Deep-clone the cached rig for one view + give it its own materials. */
export async function prepareRigView(): Promise<{ view: THREE.Group; rig: LoadedRig }> {
  const rig = await loadRig()
  const view = skeletonClone(rig.group) as THREE.Group
  view.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!mesh.isMesh) return
    mesh.castShadow = true
    const mat = mesh.material as THREE.Material | THREE.Material[]
    if (Array.isArray(mat)) mesh.material = mat.map((m) => m.clone())
    else mesh.material = mat.clone()
  })
  return { view, rig }
}

/* ---------------- look (what the player wears) ---------------- */

export interface AvatarLook3D {
  skin: string
  shirtColor: string
  shirtImage?: string | null
  pantsColor: string
  pantsImage?: string | null
  faceUrl?: string | null
  /** face decal size multiplier — 1 = the classic look (face-size slider) */
  faceScale?: number
  /** advanced per-part body colors (Body Colors editor) — overrides skin/shirt/pants mapping */
  partColors?: AvatarPartColors
  tshirtUrls?: string[]
  /** 3D UGC to attach. url may be '' for legacy image-only items (rendered as a decal instead).
   *  animClips: names of clips inside the model's own GLB to loop while worn
   *  ("a pet flying around you") — the item carries its own animation. */
  models?: { url: string; imageUrl?: string; placement: Placement | null; textureUrl?: string; color?: string; roughness?: number | null; metallic?: number | null; animClips?: string[] }[]
  /** worn bundle — a rigged body model that REPLACES the matching body parts.
   *  Normalized to the rig's exact height + footprint, painted with the
   *  Body Colors where its part names match. */
  bundle?: { url: string } | null
}

/** Turn an AvatarConfig + resolver into a AvatarLook3D (same rules as buildPreviewParts). */
export function buildLook3D(cfg: AvatarConfigT, resolve: (id: string) => AssetInfo | null): AvatarLook3D {
  const body = resolve(cfg.bodyAssetId)
  const head = resolve(cfg.headAssetId)
  const shirt = resolve(cfg.shirtAssetId)
  const pants = resolve(cfg.pantsAssetId)
  const acc = cfg.accessories.map(resolve).filter(Boolean) as AssetInfo[]
  const bundleInfo = cfg.bundleAssetId ? resolve(cfg.bundleAssetId) : null
  return {
    skin: body?.color || '#FFD34E',
    shirtColor: shirt?.color || '#2E7DC4',
    shirtImage: shirt?.imageUrl || null,
    pantsColor: pants?.color || '#39516B',
    pantsImage: pants?.imageUrl || null,
    faceUrl: head?.imageUrl || faceImageUrl('head_01'),
    faceScale: sanitizeFaceScale(cfg.faceScale),
    partColors: cfg.colors,
    tshirtUrls: acc.filter((a) => a.kind === 'tshirt' && a.imageUrl).map((a) => a.imageUrl!),
    models: acc
      .filter((a) => a.kind !== 'tshirt')
      .map((a) => ({
        url: a.modelUrl || '',
        imageUrl: a.imageUrl,
        placement: a.placement || null,
        textureUrl: a.textureUrl,
        color: a.color,
        roughness: a.roughness,
        metallic: a.metallic,
        animClips: a.animClips?.clips,
      })),
    bundle: bundleInfo?.modelUrl ? { url: bundleInfo.modelUrl } : null,
  }
}

/* ---------------- texture cache ---------------- */

const texCache = new Map<string, THREE.Texture>()

function getTexture(url: string): Promise<THREE.Texture> {
  const hit = texCache.get(url)
  if (hit) return Promise.resolve(hit)
  return new THREE.TextureLoader().loadAsync(url).then((tex) => {
    tex.colorSpace = THREE.SRGBColorSpace
    tex.anisotropy = 4
    texCache.set(url, tex)
    return tex
  })
}

/* ---------------- clothing helpers ---------------- */

/** Does this image look like the official shirt template (300x190)? */
function isShirtTemplate(tex: THREE.Texture): boolean {
  const img = tex.image as { width?: number; height?: number }
  if (!img?.width || !img?.height) return false
  return Math.abs(img.width / img.height - SHIRT_TEMPLATE.w / SHIRT_TEMPLATE.h) < 0.06
}
/** Does this image look like the official pants template (220x190)? */
function isPantsTemplate(tex: THREE.Texture): boolean {
  const img = tex.image as { width?: number; height?: number }
  if (!img?.width || !img?.height) return false
  return Math.abs(img.width / img.height - PANTS_TEMPLATE.w / PANTS_TEMPLATE.h) < 0.06
}

interface UvRect { u0: number; v0: number; u1: number; v1: number }

function zoneToUv(zone: { x: number; y: number; w: number; h: number }, tplW: number, tplH: number): UvRect {
  return {
    u0: zone.x / tplW,
    u1: (zone.x + zone.w) / tplW,
    v0: 1 - (zone.y + zone.h) / tplH, // three UV origin is bottom-left, images are top-down
    v1: 1 - zone.y / tplH,
  }
}

function fullUv(): UvRect {
  return { u0: 0, v0: 0, u1: 1, v1: 1 }
}

/** Re-map every face of a BoxGeometry to a uv rect. Face order: +X -X +Y -Y +Z -Z. */
function boxFaceUv(geo: THREE.BoxGeometry, rects: UvRect[]) {
  const uv = geo.attributes.uv as THREE.BufferAttribute
  const cornerRow = [1, 1, 0, 0] // v for the 4 corners of each face
  const cornerCol = [0, 1, 0, 1] // u for the 4 corners
  for (let f = 0; f < 6; f++) {
    const r = rects[f] || rects[0]
    for (let c = 0; c < 4; c++) {
      const i = f * 4 + c
      uv.setXY(i, r.u0 + cornerCol[c] * (r.u1 - r.u0), r.v0 + cornerRow[c] * (r.v1 - r.v0))
    }
  }
  uv.needsUpdate = true
}

function overlayMaterial(map: THREE.Texture | null, color?: string): THREE.MeshLambertMaterial {
  // only pass color when it exists — THREE warns on `color: undefined`
  const params: THREE.MeshLambertMaterialParameters = {
    map: map || null,
    transparent: true,
    alphaTest: 0.01,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  }
  if (color) params.color = new THREE.Color(color)
  return new THREE.MeshLambertMaterial(params)
}

/** A clothing box hugging one body part, textured like the classic template wrap. */
async function clothingBox(box: THREE.Box3, tex: THREE.Texture, zone: UvRect | null): Promise<THREE.Mesh> {
  const size = box.getSize(new THREE.Vector3())
  const center = box.getCenter(new THREE.Vector3())
  const geo = new THREE.BoxGeometry(size.x * 1.02, size.y * 1.02, size.z * 1.02)
  const rect = zone || fullUv()
  boxFaceUv(geo, [rect, rect, rect, rect, rect, rect])
  const mesh = new THREE.Mesh(geo, overlayMaterial(tex))
  mesh.position.copy(center)
  mesh.castShadow = true
  return mesh
}

/** A flat decal stuck on the FRONT face of a part (t-shirts, faces).
 *  surfaceZ = the part's REAL front surface (vertex-accurate) — decals hug
 *  the mesh instead of floating ahead of a loose bounding box. */
function frontDecal(box: THREE.Box3, tex: THREE.Texture, maxW: number, maxH: number, surfaceZ?: number): THREE.Mesh {
  const center = box.getCenter(new THREE.Vector3())
  const img = tex.image as { width?: number; height?: number }
  const aspect = img?.width && img?.height ? img.width / img.height : 1
  let w = maxW
  let h = w / aspect
  if (h > maxH) {
    h = maxH
    w = h * aspect
  }
  const geo = new THREE.PlaneGeometry(w, h)
  const mesh = new THREE.Mesh(geo, overlayMaterial(tex))
  const z = (surfaceZ !== undefined ? surfaceZ : box.max.z) + 0.008
  mesh.position.set(center.x, center.y, z)
  return mesh
}

function disposeObject(root: THREE.Object3D) {
  root.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!mesh.isMesh) return
    mesh.geometry?.dispose()
    const mat = mesh.material as THREE.Material | THREE.Material[]
    if (Array.isArray(mat)) mat.forEach((m) => m.dispose())
    else mat?.dispose()
  })
}

/* ---------------- accessory (3D UGC) attach ---------------- */

const gltfCache = new Map<string, Promise<THREE.Group>>()

/** Same as loadGltfModel but ALSO returns the GLB's animation clips —
 *  the door for emotes, bundles-with-anims and self-animated UGC. */
export function loadGltfWithClips(url: string): Promise<{ scene: THREE.Group; clips: THREE.AnimationClip[] }> {
  const hit = gltfCache.get(url)
  if (hit) {
    // the cached promise resolves to the group; fetch clips via a side cache
    const clips = gltfClipsCache.get(url)
    if (clips) return hit.then((scene) => ({ scene, clips: clips() }))
  }
  const clipsRef: { current: THREE.AnimationClip[] } = { current: [] }
  const p = new GLTFLoader()
    .loadAsync(url)
    .then((g) => {
      const root = g.scene
      clipsRef.current = g.animations || []
      // SAME normalization the placement editor did when the creator placed
      // the item (max dimension -> UGC_IMPORT_SIZE). Without this the stored
      // placement lands the item at the wrong size / spot when worn.
      const box = new THREE.Box3().setFromObject(root)
      if (!box.isEmpty()) {
        const size = box.getSize(new THREE.Vector3())
        const maxDim = Math.max(size.x, size.y, size.z, 0.0001)
        root.scale.setScalar(UGC_IMPORT_SIZE / maxDim)
      }
      root.traverse((o) => {
        const mesh = o as THREE.Mesh
        if (mesh.isMesh) {
          mesh.castShadow = true
          const mat = mesh.material as THREE.MeshStandardMaterial | THREE.MeshStandardMaterial[]
          const mats = Array.isArray(mat) ? mat : [mat]
          mats.forEach((m) => {
            if (m && 'map' in m && m.map) m.map.colorSpace = THREE.SRGBColorSpace
          })
        }
      })
      return root
    })
  gltfCache.set(url, p)
  gltfClipsCache.set(url, () => clipsRef.current)
  return p.then((scene) => ({ scene, clips: clipsRef.current }))
}

/** side cache: url -> accessor for the clips captured at load time */
const gltfClipsCache = new Map<string, () => THREE.AnimationClip[]>()

export function loadGltfModel(url: string): Promise<THREE.Group> {
  const hit = gltfCache.get(url)
  if (hit) return hit
  return loadGltfWithClips(url).then((r) => r.scene)
}

/* ---------------- UGC model surface (texture / color) ---------------- */

export interface ModelSurface {
  /** optional texture image wrapped around the model (wins over color) */
  textureUrl?: string
  /** optional tint painted on the model when it has no texture (#RRGGBB) */
  color?: string
  /** creator surface finish overrides 0..1 — when set they WIN over the
   *  model's own materials (that is the whole point: "make it shiny/matte") */
  roughness?: number | null
  metallic?: number | null
}

/** linear-space threshold for "this surface arrived with no real paint"
 *  (same ~sRGB 0.97+ rule the publish converter uses) */
const PAINT_EPSILON = 0.93

function isUnpainted(std: THREE.MeshStandardMaterial): boolean {
  if (std.map) return false
  const c = std.color
  return c.r >= PAINT_EPSILON && c.g >= PAINT_EPSILON && c.b >= PAINT_EPSILON
}

/**
 * Apply a creator's texture or color to a (cloned) UGC model.
 * SkeletonUtils.clone SHARES materials between instances, so every mesh
 * material is cloned here first — many views can wear the same item with
 * different surfaces without stomping on each other.
 * THE ROBLOX RULE — DATA WINS: whatever materials the model file carries
 * (Blender grey, brown, textures) always show. The creator's texture only
 * wraps surfaces that have no texture of their own, and the tint only
 * paints surfaces that arrived unpainted (no texture + plain white) —
 * exactly how Roblox treats SurfaceAppearance vs MeshPart color.
 */
export async function applyModelSurface(root: THREE.Object3D, surface: ModelSurface | null | undefined): Promise<void> {
  if (!surface || (!surface.textureUrl && !surface.color && surface.roughness == null && surface.metallic == null)) return
  const finishRough = typeof surface.roughness === 'number' ? Math.min(1, Math.max(0, surface.roughness)) : null
  const finishMetal = typeof surface.metallic === 'number' ? Math.min(1, Math.max(0, surface.metallic)) : null
  root.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!mesh.isMesh) return
    const mat = mesh.material as THREE.MeshStandardMaterial | THREE.MeshStandardMaterial[]
    if (Array.isArray(mat)) mesh.material = mat.map((m) => m.clone())
    else if (mat) mesh.material = mat.clone()
  })
  const jobs: Promise<unknown>[] = []
  root.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!mesh.isMesh) return
    const mat = mesh.material as THREE.MeshStandardMaterial | THREE.MeshStandardMaterial[]
    const mats = Array.isArray(mat) ? mat : [mat]
    mats.forEach((m) => {
      if (!m || !('color' in m)) return
      const std = m as THREE.MeshStandardMaterial
      // finish overrides apply to EVERY surface of the item — an explicit
      // creator choice always beats what the file happens to carry
      if (finishRough != null) {
        std.roughness = finishRough
        std.needsUpdate = true
      }
      if (finishMetal != null) {
        std.metalness = finishMetal
        std.needsUpdate = true
      }
      if (surface.textureUrl) {
        if (std.map) return // the model's own texture is data — it wins
        // tracked so callers can await the texture before their first render
        jobs.push(
          getTexture(surface.textureUrl!)
            .then((tex) => {
              tex.wrapS = THREE.RepeatWrapping
              tex.wrapT = THREE.RepeatWrapping
              std.map = tex
              std.color = new THREE.Color('#ffffff')
              std.needsUpdate = true
            })
            .catch(() => { /* a broken texture url never breaks the item */ })
        )
      } else if (surface.color) {
        if (!isUnpainted(std)) return // real color/texture data — keep it
        std.color = new THREE.Color(surface.color)
        std.needsUpdate = true
      }
    })
  })
  await Promise.all(jobs)
}

/** THE SACRED RULE — apply the creator's placement verbatim, everywhere. */
export function applyPlacement(obj: THREE.Object3D, placement: Placement | null) {
  if (!placement) return
  obj.position.set(placement.p[0], placement.p[1], placement.p[2])
  obj.rotation.set(
    THREE.MathUtils.degToRad(placement.r[0]),
    THREE.MathUtils.degToRad(placement.r[1]),
    THREE.MathUtils.degToRad(placement.r[2])
  )
  obj.scale.set(placement.s[0], placement.s[1], placement.s[2])
}

/** Wrap a (normalized) UGC model in a group that carries the creator's
 *  placement. The model KEEPS its own import normalization — the placement
 *  applies around it, exactly like the editor's holder/wrap scene graph. */
export function attachPlacedModel(model: THREE.Object3D, placement: Placement | null): THREE.Group {
  const holder = new THREE.Group()
  holder.add(model)
  applyPlacement(holder, placement)
  return holder
}

/* ---------------- animation clips: retargeting + mixers ----------------
   Clips exported from Blender carry track names like "Left Arm.quaternion".
   THREE.PropertyBinding matches those names EXACTLY, but rigs name their
   parts differently ("LeftArm", "arm_l"...). retargetClipToRoot rewrites
   every track's node name to the target scene's ACTUAL node (matched through
   the same normalization the body-part matcher uses), so a clip made on the
   R6 template plays straight onto the player model — and onto any worn
   bundle whose parts follow the same naming. */

/** Rewrite a clip's track names to the node names that exist under `root`.
 *  Returns null when nothing in the clip matches anything in the rig. */
export function retargetClipToRoot(clip: THREE.AnimationClip, root: THREE.Object3D): THREE.AnimationClip | null {
  const nameMap = new Map<string, string>()
  root.updateMatrixWorld(true)
  root.traverse((o) => {
    if (!o.name) return
    const n = normName(o.name)
    if (n && !nameMap.has(n)) nameMap.set(n, o.name)
  })
  if (nameMap.size === 0) return null

  const tracks: THREE.KeyframeTrack[] = []
  for (const track of clip.tracks) {
    const dot = track.name.lastIndexOf('.')
    if (dot < 1) continue
    const nodeName = track.name.slice(0, dot)
    const prop = track.name.slice(dot) // ".quaternion" / ".position" / ".scale"
    const mapped = nameMap.get(normName(nodeName))
    if (!mapped) continue
    const nt = track.clone()
    nt.name = `${mapped}${prop}`
    tracks.push(nt)
  }
  if (tracks.length === 0) return null
  const out = new THREE.AnimationClip(clip.name, clip.duration, tracks, clip.blendMode)
  return out
}

/** Load a rigged GLB and retarget its clips onto `root` (name-matched).
 *  Returns only the clips that actually bound to something. */
export async function loadClipsRetargeted(
  url: string,
  root: THREE.Object3D
): Promise<THREE.AnimationClip[]> {
  const { clips } = await loadGltfWithClips(url)
  const out: THREE.AnimationClip[] = []
  for (const c of clips) {
    const r = retargetClipToRoot(c, root)
    if (r) out.push(r)
  }
  return out
}

/* ---------------- mixers worn on a look (self-animated UGC) ---------------- */

/** Every AnimationMixer created for a worn object registers here, tagged with
 *  the object it drives — the 3D views update + dispose them by walking the
 *  scene, so animated UGC ("a pet flying around you") just works. */
const wornMixers = new Map<THREE.AnimationMixer, THREE.Object3D>()

/** Play a model's own clips (by name) on it, looping — the "plain UGC flying
 *  around you" effect: the item carries its animation inside its GLB. */
export function playOwnClips(
  object: THREE.Object3D,
  clips: THREE.AnimationClip[],
  only?: string[]
): THREE.AnimationMixer | null {
  const usable = clips.filter((c) => !only || only.length === 0 || only.includes(c.name))
  if (usable.length === 0) return null
  const mixer = new THREE.AnimationMixer(object)
  for (const c of usable) mixer.clipAction(c).play()
  wornMixers.set(mixer, object)
  return mixer
}

function livesUnder(obj: THREE.Object3D, root: THREE.Object3D): boolean {
  let p: THREE.Object3D | null = obj
  while (p) {
    if (p === root) return true
    p = p.parent
  }
  return false
}

/** Advance every worn mixer whose object lives under `view`. Call per frame. */
export function updateWornMixers(view: THREE.Object3D, dt: number): void {
  if (wornMixers.size === 0) return
  for (const [mixer, obj] of wornMixers) {
    if (livesUnder(obj, view)) mixer.update(dt)
  }
}

/** Stop + forget every mixer under `view` (call before disposing a look). */
export function stopWornMixers(view: THREE.Object3D): void {
  for (const [mixer, obj] of wornMixers) {
    if (livesUnder(obj, view)) {
      mixer.stopAllAction()
      wornMixers.delete(mixer)
    }
  }
}

/* ---------------- bundles (body replacement) ---------------- */

/** Normalize a bundle model the way the player rig is normalized: RIG_HEIGHT
 *  tall, feet on y=0, centered on x/z — so the bundle EXACTLY occupies the
 *  space the classic body occupied. */
export function normalizeBundle(model: THREE.Object3D): THREE.Group {
  const wrap = new THREE.Group()
  wrap.add(model)
  const box = new THREE.Box3().setFromObject(wrap)
  if (!box.isEmpty()) {
    const size = box.getSize(new THREE.Vector3())
    const s = RIG_HEIGHT / Math.max(size.y, 0.0001)
    wrap.scale.setScalar(s)
    wrap.updateMatrixWorld(true)
    const nb = new THREE.Box3().setFromObject(wrap)
    const nc = nb.getCenter(new THREE.Vector3())
    wrap.position.x -= nc.x
    wrap.position.z -= nc.z
    wrap.position.y -= nb.min.y
    wrap.updateMatrixWorld(true)
  }
  return wrap
}

/** Per-part boxes + front surfaces measured from a model's REAL vertices —
 *  the same measurement loadRig does, reused for worn bundles so face
 *  decals and clothing hug the bundle's actual geometry. */
export function measureParts(model: THREE.Object3D): {
  boxes: Map<PartKey, THREE.Box3>
  frontZ: Map<PartKey, number>
  parts: Map<PartKey, THREE.Object3D[]>
} {
  const parts = new Map<PartKey, THREE.Object3D[]>()
  model.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!mesh.isMesh) return
    const key = matchPart(o.name) || matchPart(mesh.geometry?.name || '')
    if (!key) return
    const list = parts.get(key) || []
    list.push(mesh)
    parts.set(key, list)
  })
  const boxes = new Map<PartKey, THREE.Box3>()
  const frontZ = new Map<PartKey, number>()
  const vtx = new THREE.Vector3()
  for (const [key, list] of parts) {
    const b = new THREE.Box3()
    let zmax = -Infinity
    for (const m of list) {
      b.expandByObject(m)
      const mesh = m as THREE.Mesh
      const pos = mesh.geometry?.attributes?.position
      if (pos) {
        mesh.updateWorldMatrix(true, false)
        for (let i = 0; i < pos.count; i++) {
          vtx.set(pos.getX(i), pos.getY(i), pos.getZ(i)).applyMatrix4(mesh.matrixWorld)
          if (vtx.z > zmax) zmax = vtx.z
        }
      }
    }
    boxes.set(key, b)
    if (Number.isFinite(zmax)) frontZ.set(key, zmax)
  }
  return { boxes, frontZ, parts }
}

/* ---------------- the one-call look applier ---------------- */

/**
 * (Re)builds everything worn on a prepared rig view. Call again whenever the
 * look changes — overlays are rebuilt, the rig itself is untouched.
 * Handles: body colors, shirt/pants/t-shirt/face overlays, placed 3D UGC
 * (optionally self-animated), and BUNDLES — a rigged body model that
 * replaces the matching body parts (hidden behind it, overlays re-anchored
 * to the bundle's real geometry).
 */
export async function applyLook(view: THREE.Group, rig: LoadedRig, look: AvatarLook3D): Promise<void> {
  // 0) clear previous overlays / worn items (stopping their mixers first)
  const old = view.getObjectByName('worn')
  if (old) {
    stopWornMixers(old)
    view.remove(old)
    disposeObject(old)
  }
  const worn = new THREE.Group()
  worn.name = 'worn'
  view.add(worn)

  // 0.5) the BUNDLE — loaded first because it decides which standard body
  // parts stay visible and which boxes the overlays anchor to.
  let boxes = rig.boxes
  let frontZ = rig.frontZ
  let replacedParts: PartKey[] = []
  if (look.bundle?.url) {
    try {
      const src = await loadGltfModel(look.bundle.url)
      const inst = skeletonClone(src)
      const bundleGroup = normalizeBundle(inst)
      const measured = measureParts(bundleGroup)
      replacedParts = [...measured.parts.keys()]
      // hide the standard body parts the bundle replaces
      view.traverse((o) => {
        const key = matchPart(o.name) || matchPart((o as THREE.Mesh).geometry?.name || '')
        if (key && replacedParts.includes(key)) o.visible = false
      })
      // paint the bundle with the same body colors the classic body would get
      const pc0 = look.partColors || {}
      const paintBundle = (key: PartKey, color: string) => {
        const list = measured.parts.get(key)
        if (!list) return
        for (const obj of list) {
          const mesh = obj as THREE.Mesh
          if (!mesh.isMesh) continue
          const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
          const cloned = mats.map((mat) => {
            const c = (mat as THREE.Material).clone() as THREE.MeshStandardMaterial
            if (c && c.color) c.color = new THREE.Color(color)
            return c
          })
          mesh.material = Array.isArray(mesh.material) ? cloned : cloned[0]
        }
      }
      paintBundle('head', pc0.head || look.skin)
      paintBundle('armL', pc0.armL || look.skin)
      paintBundle('armR', pc0.armR || look.skin)
      paintBundle('torso', pc0.torso || look.shirtColor)
      paintBundle('legL', pc0.legL || look.pantsColor)
      paintBundle('legR', pc0.legR || look.pantsColor)
      // overlays anchor to the bundle's real geometry where it replaced a part
      const bundleHolder = new THREE.Group()
      bundleHolder.name = 'bundle'
      bundleHolder.add(bundleGroup)
      view.add(bundleHolder)
      // merge: bundle boxes win for replaced parts, standard boxes elsewhere
      boxes = new Map(rig.boxes)
      frontZ = new Map(rig.frontZ)
      for (const [k, b] of measured.boxes) {
        boxes.set(k, b)
        const fz = measured.frontZ.get(k)
        if (fz !== undefined) frontZ.set(k, fz)
      }
    } catch {
      // a broken bundle never breaks the avatar — the classic body stays
    }
  } else {
    // no bundle — make sure every standard body part is visible again
    view.traverse((o) => {
      const key = matchPart(o.name) || matchPart((o as THREE.Mesh).geometry?.name || '')
      if (key && !o.visible) o.visible = true
    })
  }

  // 1) body colors — head/arms take skin, torso takes shirt color, legs pants color
  const paint = (key: PartKey, color: string) => {
    view.traverse((o) => {
      const m = o as THREE.Mesh
      if (!m.isMesh) return
      const geoName = m.geometry?.name || ''
      if (matchPart(m.name) !== key && matchPart(geoName) !== key) return
      const mats = Array.isArray(m.material) ? m.material : [m.material]
      mats.forEach((mat) => {
        const c = mat as THREE.MeshPhongMaterial
        if (c && c.color) c.color = new THREE.Color(color)
      })
    })
  }
  const pc = look.partColors || {}
  if (!replacedParts.includes('head')) paint('head', pc.head || look.skin)
  if (!replacedParts.includes('armL')) paint('armL', pc.armL || look.skin)
  if (!replacedParts.includes('armR')) paint('armR', pc.armR || look.skin)
  if (!replacedParts.includes('torso')) paint('torso', pc.torso || look.shirtColor)
  if (!replacedParts.includes('legL')) paint('legL', pc.legL || look.pantsColor)
  if (!replacedParts.includes('legR')) paint('legR', pc.legR || look.pantsColor)

  const jobs: Promise<unknown>[] = []

  // 2) shirt texture — wraps torso + arms (template zones when detected);
  //    skipped on parts the bundle replaced (the bundle IS the body there)
  if (look.shirtImage) {
    jobs.push(
      getTexture(look.shirtImage).then(async (tex) => {
        const tpl = isShirtTemplate(tex)
        const torsoBox = boxes.get('torso')
        if (torsoBox && !replacedParts.includes('torso')) {
          const zone = tpl ? zoneToUv(SHIRT_TEMPLATE.torso, SHIRT_TEMPLATE.w, SHIRT_TEMPLATE.h) : null
          worn.add(await clothingBox(torsoBox, tex, zone))
        }
        for (const [key, zoneDef] of [['armR', SHIRT_TEMPLATE.armR], ['armL', SHIRT_TEMPLATE.armL]] as const) {
          const b = boxes.get(key)
          if (!b || replacedParts.includes(key)) continue
          const zone = tpl ? zoneToUv(zoneDef, SHIRT_TEMPLATE.w, SHIRT_TEMPLATE.h) : null
          worn.add(await clothingBox(b, tex, zone))
        }
      })
    )
  }

  // 3) pants texture — wraps the legs (bundle-replaced legs skip it)
  if (look.pantsImage) {
    jobs.push(
      getTexture(look.pantsImage).then(async (tex) => {
        const tpl = isPantsTemplate(tex)
        for (const [key, zoneDef] of [['legR', PANTS_TEMPLATE.legR], ['legL', PANTS_TEMPLATE.legL]] as const) {
          const b = boxes.get(key)
          if (!b || replacedParts.includes(key)) continue
          const zone = tpl ? zoneToUv(zoneDef, PANTS_TEMPLATE.w, PANTS_TEMPLATE.h) : null
          worn.add(await clothingBox(b, tex, zone))
        }
      })
    )
  }

  // 4) t-shirts — an image decal on the FRONT of the torso, nothing more
  for (const url of look.tshirtUrls || []) {
    jobs.push(
      getTexture(url).then((tex) => {
        const torsoBox = boxes.get('torso')
        if (!torsoBox) return
        const size = torsoBox.getSize(new THREE.Vector3())
        worn.add(frontDecal(torsoBox, tex, size.x * 0.92, size.y * 0.92, frontZ.get('torso')))
      })
    )
  }

  // 5) face — decal on the front of the head, 62% of the face at scale 1 (the
  //    classic face size — a full-head decal makes the smile look huge).
  //    The avatar editor's Face size slider scales it around the middle.
  //    With a bundle wearing the head, the decal hugs the BUNDLE's head.
  if (look.faceUrl) {
    jobs.push(
      getTexture(look.faceUrl).then((tex) => {
        const headBox = boxes.get('head')
        if (!headBox) return
        const size = headBox.getSize(new THREE.Vector3())
        const fs = sanitizeFaceScale(look.faceScale)
        worn.add(frontDecal(headBox, tex, size.x * 0.62 * fs, size.y * 0.62 * fs, frontZ.get('head')))
      })
    )
  }

  // 6) 3D UGC — placed EXACTLY where the creator left it; models whose GLB
  //    carries clips (and the creator marked them) loop their own animation
  for (const m of look.models || []) {
    if (m.url) {
      jobs.push(
        loadGltfWithClips(m.url).then(async ({ scene: model, clips }) => {
          const inst = skeletonClone(model) // clone so many views can wear one item
          await applyModelSurface(inst, { textureUrl: m.textureUrl, color: m.color, roughness: m.roughness, metallic: m.metallic })
          const holder = attachPlacedModel(inst, m.placement)
          if (m.animClips && m.animClips.length > 0) playOwnClips(inst, clips, m.animClips)
          worn.add(holder)
        })
      )
    } else if (m.imageUrl) {
      // legacy image-only accessory: a decal floating over the head,
      // exactly like the classic 2D slot rendered it
      jobs.push(
        getTexture(m.imageUrl).then((tex) => {
          const headBox = boxes.get('head')
          if (!headBox) return
          const c = headBox.getCenter(new THREE.Vector3())
          const size = headBox.getSize(new THREE.Vector3())
          const img = tex.image as { width?: number; height?: number }
          const aspect = img?.width && img?.height ? img.width / img.height : 1
          const w = size.x * 1.6
          const geo = new THREE.PlaneGeometry(w, w / aspect)
          const mesh = new THREE.Mesh(geo, overlayMaterial(tex))
          mesh.position.set(c.x, headBox.max.y + w / aspect / 2 + 0.1, c.z)
          worn.add(mesh)
        })
      )
    }
  }

  await Promise.all(jobs)

  // dev/debug hook: lets E2E checks inspect what is actually worn
  if (typeof window !== 'undefined') {
    ;(window as unknown as { __rbLastWorn?: THREE.Group }).__rbLastWorn = worn
  }
}
