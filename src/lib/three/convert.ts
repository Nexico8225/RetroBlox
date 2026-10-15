'use client'

/* ------------------------------------------------------------------
   Publish-time 3D conversion — every uploaded UGC model becomes GLB.

   Why: one format everywhere. The placement editor, the try-on scenes
   and the Unity SDK all load the exact same GLB the creator uploaded
   (converted in their browser, textures embedded), so nothing is lost
   and no server-side model pipeline is needed.
------------------------------------------------------------------ */

import * as THREE from 'three'
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js'
import { TGALoader } from 'three/examples/jsm/loaders/TGALoader.js'
import { OBJLoader } from 'three/examples/jsm/loaders/OBJLoader.js'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js'

export const MODEL_ACCEPT = '.fbx,.glb,.gltf,.obj'
export const MAX_MODEL_MB = 24

/** linear-space threshold for "this material is plain white" (~sRGB 0.97+) */
const NO_COLOR_EPSILON = 0.93

function stripNonMeshes(root: THREE.Object3D) {
  const trash: THREE.Object3D[] = []
  root.traverse((o) => {
    if ((o as THREE.Light).isLight || (o as THREE.Camera).isCamera) trash.push(o)
  })
  trash.forEach((o) => o.parent?.remove(o))
}

function hasRealColor(m: THREE.MeshStandardMaterial): boolean {
  if (m.map) return true
  const c = m.color
  return !(c.r >= NO_COLOR_EPSILON && c.g >= NO_COLOR_EPSILON && c.b >= NO_COLOR_EPSILON)
}

/** Parse an FBX AND wait for its embedded textures to finish decoding.
 *
 *  Blender-embedded .tga textures are common (older pipelines save images as
 *  TGA), and FBXLoader SILENTLY DROPS them — "TGA loader not found, skipping"
 *  — when no handler is registered. A dropped texture is one of the classic
 *  "my model uploads fully white" causes, even with Path Mode Copy + Embed
 *  Textures ticked. So a TGALoader is registered on the LoadingManager.
 *
 *  THE RACE THIS FIXES: FBXLoader.parse() returns SYNCHRONOUSLY, but texture
 *  decodes (TGA, PNG, JPG — all of them) run ASYNC through the LoadingManager.
 *  GLTFExporter throws "THREE.GLTFExporter: Invalid image type" on any texture
 *  whose image is not decoded yet — which failed the whole publish. So after
 *  parse we drain the manager (onLoad) before the scene moves on. A timeout
 *  guards against a texture that never finishes; objectToGlb strips any
 *  still-unloaded texture so the export survives with what did decode. */
async function parseFbx(buffer: ArrayBuffer): Promise<THREE.Group & { animations: THREE.AnimationClip[] }> {
  const manager = new THREE.LoadingManager()
  manager.addHandler(/\.tga$/i, new TGALoader())

  // itemStart fires once per requested texture — the only signal that tells
  // us whether to wait (itemsTotal is a closure variable we cannot read).
  let texturesRequested = 0
  const realStart = manager.itemStart.bind(manager)
  manager.itemStart = (url: string) => {
    texturesRequested++
    realStart(url)
  }

  const obj = new FBXLoader(manager).parse(buffer, '') as THREE.Group & { animations: THREE.AnimationClip[] }

  if (texturesRequested > 0) {
    await new Promise<void>((resolve) => {
      let settled = false
      const finish = () => {
        if (!settled) {
          settled = true
          resolve()
        }
      }
      manager.onLoad = finish
      setTimeout(finish, 8000) // never hang the publish form on a stuck texture
    })
  }
  return obj
}

/** Does this texture carry an image GLTFExporter can actually embed?
 *  Mirrors the exporter's own checks (processImage): it throws "No valid
 *  image data found" on image === null and crashes reading .width when
 *  image === undefined, and DataTexture payloads only work when they hold
 *  real bytes. Anything half-decoded gets rejected here, dropped there. */
export function textureIsExportable(tex: THREE.Texture | null | undefined): boolean {
  if (!tex) return true // no texture in this slot = nothing to guard
  const img = tex.image as
    | HTMLImageElement | HTMLCanvasElement | ImageBitmap | OffscreenCanvas
    | { data?: unknown; width?: unknown; height?: unknown }
    | null | undefined
  if (img == null) return false // null / undefined — decode never finished
  if (
    (typeof HTMLImageElement !== 'undefined' && img instanceof HTMLImageElement) ||
    (typeof HTMLCanvasElement !== 'undefined' && img instanceof HTMLCanvasElement) ||
    (typeof ImageBitmap !== 'undefined' && img instanceof ImageBitmap) ||
    (typeof OffscreenCanvas !== 'undefined' && img instanceof OffscreenCanvas)
  ) {
    return true
  }
  // DataTexture payload (what TGALoader produces once decoded)
  const d = img as { data?: unknown; width?: unknown; height?: unknown }
  return d.data != null && typeof d.width === 'number' && d.width > 0 && typeof d.height === 'number' && d.height > 0
}

/** Last-resort guard right before export: any texture whose image never
 *  decoded (manager timeout hit) would make GLTFExporter throw. Drop it so
 *  the publish goes through with every texture that DID decode. */
export function dropUnloadedTextures(root: THREE.Object3D) {
  const SLOTS = ['map', 'normalMap', 'bumpMap', 'aoMap', 'emissiveMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'specularMap'] as const
  root.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!mesh.isMesh || mesh.material == null) return
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
    for (const m of mats) {
      const std = m as THREE.MeshStandardMaterial
      for (const slot of SLOTS) {
        const tex = std[slot] as THREE.Texture | null | undefined
        if (tex && !textureIsExportable(tex)) {
          ;(std as unknown as Record<string, unknown>)[slot] = null
          std.needsUpdate = true
        }
      }
    }
  })
}

/** Normalize every material to matte PBR before the GLB is written, so the
 *  item looks IDENTICAL on the site, in the Godot kit and in future SDKs.
 *
 *  THE ROBLOX RULE — DATA WINS: everything the model file carries comes
 *  through. Blender FBX files arrive as Phong/Lambert materials, and this
 *  copies the FULL set of data they hold (base color, diffuse texture,
 *  normal map, bump map, AO map, emissive map, opacity, vertex colors),
 *  not just the paint. Metalness is zeroed because the classic look is
 *  matte plastic — never a metal mirror.
 *
 *  Returns a warning string when the model landed with NO material colors
 *  at all — that is the classic "my UGC is plain white in game" trap that
 *  happens when the Blender material never made it into the export. */
function normalizeMaterials(root: THREE.Object3D): string | null {
  let meshes = 0
  let colored = false
  root.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!(mesh as THREE.Mesh).isMesh || mesh.material == null) return
    meshes++
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
    const next = mats.map((m) => {
      const src = m as THREE.MeshStandardMaterial
      const isPbrSource = src.isMeshStandardMaterial === true
      const std = isPbrSource
        ? (src.clone() as THREE.MeshStandardMaterial)
        : new THREE.MeshStandardMaterial()
      if (std !== src) {
        // Phong / Lambert (what FBX and OBJ come in as) -> PBR, keeping
        // EVERY piece of data the source material holds — grey stays grey,
        // brown stays brown, textures and lighting extras survive too.
        std.name = src.name
        const phong = src as unknown as THREE.MeshPhongMaterial
        std.color = (src.color ?? new THREE.Color(1, 1, 1)).clone()
        if (phong.map) std.map = phong.map
        if (phong.normalMap) std.normalMap = phong.normalMap
        if (phong.bumpMap) {
          std.bumpMap = phong.bumpMap
          std.bumpScale = phong.bumpScale
        }
        if (phong.aoMap) {
          std.aoMap = phong.aoMap
          std.aoMapIntensity = phong.aoMapIntensity
        }
        if (phong.emissiveMap) std.emissiveMap = phong.emissiveMap
        if (phong.specularMap) std.roughnessMap = phong.specularMap
        if (phong.emissive) std.emissive = phong.emissive.clone()
        std.transparent = src.transparent
        std.opacity = src.opacity
        std.alphaTest = src.alphaTest
        std.side = src.side
        std.depthWrite = src.depthWrite
        std.vertexColors = (src as unknown as THREE.MeshBasicMaterial).vertexColors === true
      }
      // SURFACE FINISH — data wins here too. A .glb out of Blender carries the
      // creator's real Metallic / Roughness sliders (their steel, gold, glass),
      // so those pass through UNTOUCHED. FBX/OBJ arrive as Phong/Lambert which
      // simply has no finish data — those get the classic matte-plastic look.
      if (!isPbrSource) {
        std.metalness = 0
        std.roughness = 0.85
      }
      if (hasRealColor(std)) colored = true
      return std
    })
    mesh.material = Array.isArray(mesh.material) ? next : next[0]
    // FACE-CORNER DATA: if the mesh carries per-corner colors (Blender
    // vertex paint, exported as COLOR_0), force the materials to use them —
    // otherwise the GLB export silently drops COLOR_0 and that data is
    // gone forever. Roblox keeps this data; so do we.
    const geom = mesh.geometry as THREE.BufferGeometry | undefined
    if (geom?.attributes?.color) {
      const arr = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
      arr.forEach((mm) => {
        const std = mm as THREE.MeshStandardMaterial
        std.vertexColors = true
        std.needsUpdate = true
      })
      colored = true
    }
  })
  if (meshes === 0 || colored) return null
  return (
    'This model has no material colors — it would show up plain white in game. ' +
    'Fix in Blender: give every material a Principled BSDF with Base Color (grey, brown, anything). ' +
    'Image textures: connect straight into Base Color, re-save TGA/TIFF images as PNG first, and export with Path Mode "Copy" + "Embed Textures" — ' +
    'or just export .glb (glTF 2.0), which always keeps colors and textures. ' +
    'You can also paint it here with a texture or a flat color.'
  )
}

export interface GlbWithCheck {
  glb: Blob
  /** non-null when every material came in plain white — shown to the creator */
  colorWarning: string | null
}

/** Same conversion as fileToGlb, plus the material normalization and the
 *  "no colors detected" check the publish form shows as a warning. */
export async function fileToGlbWithCheck(file: File, opts?: { keepAnimations?: boolean }): Promise<GlbWithCheck> {
  const keep = !!opts?.keepAnimations
  const name = (file.name || '').toLowerCase()

  let object: THREE.Object3D
  let animations: THREE.AnimationClip[] | undefined

  if (name.endsWith('.glb')) {
    const loader = new GLTFLoader()
    const gltf = await loader.parseAsync(await file.arrayBuffer(), '')
    object = gltf.scene
    animations = keep ? gltf.animations : undefined
  } else if (name.endsWith('.fbx')) {
    try {
      const obj = await parseFbx(await file.arrayBuffer())
      object = obj
      animations = keep ? obj.animations : undefined
    } catch (e) {
      throw new Error(
        `Could not read that FBX${e instanceof Error ? ` (${e.message.slice(0, 90)})` : ''}. ` +
          'Re-export it from your 3D app as FBX 7.4 binary, or as GLB.'
      )
    }
  } else if (name.endsWith('.obj')) {
    try {
      object = new OBJLoader().parse(await file.text())
    } catch {
      throw new Error('Could not read that OBJ file. Try exporting it as GLB instead.')
    }
  } else if (name.endsWith('.gltf')) {
    try {
      const json = JSON.parse(await file.text())
      const gltf = await new GLTFLoader().parseAsync(JSON.stringify(json), '')
      object = gltf.scene
      animations = keep ? gltf.animations : undefined
    } catch {
      throw new Error(
        'That .gltf points to external files (bin/textures). Export a single self-contained .glb instead.'
      )
    }
  } else {
    throw new Error('Unsupported model type — upload FBX, GLB, GLTF or OBJ.')
  }

  const colorWarning = normalizeMaterials(object)
  return { glb: await objectToGlb(object, animations), colorWarning }
}

/** FBX files can carry HUNDREDS of object-level takes (Blender bakes every
 *  mesh object's animation as its own take — measured: a wave FBX produced
 *  458 clips named "Head|Right Arm|Old_Idle", 392 of them single-node
 *  cross-product slices of the imported actions). Writing all of them into
 *  the GLB balloons the file past the 24MB upload cap and floods the NLA
 *  track picker with dead names. What can pose a skinned body: clips that
 *  drive BONES, across at least two nodes (every baked armature take is
 *  multi-bone; single-node takes are mesh objects). The same action often
 *  appears several times ("wave" and "Armature|wave") — dedupe by the
 *  ACTION TAIL and keep the richest take. A rig with no bones at all
 *  (blocky mesh characters) keeps everything. */
export function worthyClips(object: THREE.Object3D, animations: THREE.AnimationClip[]): THREE.AnimationClip[] {
  const bones = new Set<string>()
  object.traverse((o) => {
    if ((o as THREE.Bone).isBone && o.name) {
      bones.add(o.name.toLowerCase().replace(/\$[a-z0-9_]+/g, '').replace(/[\s._]+/g, ' ').trim())
    }
  })
  const hasBones = bones.size > 0
  const byTail = new Map<string, THREE.AnimationClip>()
  for (const clip of animations) {
    if (clip.tracks.length === 0) continue
    const nodes = new Set<string>()
    let boneHit = false
    for (const t of clip.tracks) {
      const dot = t.name.lastIndexOf('.')
      if (dot < 1) continue
      const nodeName = t.name.slice(0, dot).toLowerCase().replace(/\$[a-z0-9_]+/g, '').replace(/[\s._]+/g, ' ').trim()
      nodes.add(nodeName)
      if (bones.has(nodeName)) boneHit = true
    }
    if (hasBones && (!boneHit || nodes.size < 2)) continue
    const raw = clip.name || ''
    const tail = raw.includes('|') ? raw.slice(raw.lastIndexOf('|') + 1) : raw
    const key = tail || `clip${byTail.size}`
    const prev = byTail.get(key)
    if (!prev || clip.tracks.length > prev.tracks.length) byTail.set(key, clip)
    if (byTail.size >= 64) break // paranoia cap — no emote needs 64 actions
  }
  return [...byTail.values()]
}

async function objectToGlb(object: THREE.Object3D, animations?: THREE.AnimationClip[]): Promise<Blob> {
  stripNonMeshes(object)
  dropUnloadedTextures(object)
  const clips = animations && animations.length > 0 ? worthyClips(object, animations) : undefined
  const exporter = new GLTFExporter()
  const buf = (await exporter.parseAsync(object, {
    binary: true,
    onlyVisible: true,
    ...(clips && clips.length > 0 ? { animations: clips } : {}),
  })) as ArrayBuffer
  return new Blob([buf], { type: 'model/gltf-binary' })
}

/** Convert any supported model file to GLB (GLB files pass through untouched).
 *  keepAnimations: rigged uploads (emotes / bundles / anim packs) need the
 *  Blender clips to SURVIVE the conversion — the plain path drops them. */
export async function fileToGlb(file: File, opts?: { keepAnimations?: boolean }): Promise<Blob> {
  const keep = !!opts?.keepAnimations
  const name = (file.name || '').toLowerCase()
  if (name.endsWith('.glb')) return file

  if (name.endsWith('.fbx')) {
    try {
      const obj = await parseFbx(await file.arrayBuffer())
      return await objectToGlb(obj, keep ? obj.animations : undefined)
    } catch (e) {
      throw new Error(
        `Could not read that FBX${e instanceof Error ? ` (${e.message.slice(0, 90)})` : ''}. ` +
          'Re-export it from your 3D app as FBX 7.4 binary, or as GLB.'
      )
    }
  }

  if (name.endsWith('.obj')) {
    try {
      const text = await file.text()
      const obj = new OBJLoader().parse(text)
      return await objectToGlb(obj)
    } catch {
      throw new Error('Could not read that OBJ file. Try exporting it as GLB instead.')
    }
  }

  if (name.endsWith('.gltf')) {
    try {
      const text = await file.text()
      const json = JSON.parse(text)
      const loader = new GLTFLoader()
      const gltf = await loader.parseAsync(JSON.stringify(json), '')
      return await objectToGlb(gltf.scene, keep ? gltf.animations : undefined)
    } catch {
      throw new Error(
        'That .gltf points to external files (bin/textures). Export a single self-contained .glb instead.'
      )
    }
  }

  throw new Error('Unsupported model type — upload FBX, GLB, GLTF or OBJ.')
}

/** Size guard for the publish form. */
export function modelTooBig(file: File | Blob): string | null {
  const mb = file.size / (1024 * 1024)
  if (mb > MAX_MODEL_MB) return `Model too large (${mb.toFixed(1)}MB) — the limit is ${MAX_MODEL_MB}MB.`
  return null
}

/* ------------------------------------------------------------------
   GLB ANIMATION INSPECTOR — reads the raw glTF JSON chunk straight
   out of the binary (no three.js involved). When a rigged upload
   lands with ZERO playable clips, this tells us WHICH failure it is:

   - rawCount === 0  -> the file truly carries no animation data: the
     creator's export never included the action (Animation box off,
     action never pushed down into the NLA / not the active action).
     The publish form shows the exact Blender recipe.
   - rawCount  >  0  -> the clips EXIST but GLTFLoader could not turn
     them into playable AnimationClips (keyed objects that did not
     export, or a broken exporter flag). Different fix, same dialog.

   GLB layout: 12-byte header, then chunks: [len u32][type u32][data].
   Chunk 0 is always JSON ('JSON' = 0x4E4F534A little-endian).
------------------------------------------------------------------ */
export interface GlbAnimInfo {
  rawCount: number
  rawNames: string[]
}

export async function inspectGlbAnimations(file: File | Blob): Promise<GlbAnimInfo> {
  const empty: GlbAnimInfo = { rawCount: 0, rawNames: [] }
  try {
    const head = new Uint8Array(await file.slice(0, 20).arrayBuffer())
    // magic 'glTF' = 0x67 0x6C 0x54 0x46
    if (head.length < 20 || head[0] !== 0x67 || head[1] !== 0x6c || head[2] !== 0x54 || head[3] !== 0x46) return empty
    const hv = new DataView(head.buffer)
    const jsonLen = hv.getUint32(12, true)
    const jsonType = hv.getUint32(16, true)
    if (jsonType !== 0x4e4f534a || jsonLen < 2) return empty
    const jsonBytes = new Uint8Array(await file.slice(20, 20 + jsonLen).arrayBuffer())
    const json = JSON.parse(new TextDecoder().decode(jsonBytes)) as { animations?: { name?: string }[] }
    const anims = Array.isArray(json.animations) ? json.animations : []
    return {
      rawCount: anims.length,
      rawNames: anims.map((a, i) => (a && typeof a.name === 'string' && a.name.trim() ? a.name.trim() : `Clip ${i + 1}`)),
    }
  } catch {
    return empty
  }
}
