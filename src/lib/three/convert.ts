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

/** Normalize every material to PBR before the GLB is written, so the
 *  item looks IDENTICAL on the site, in the Godot kit and in future SDKs.
 *
 *  THE ROBLOX RULE — DATA WINS: everything the model file carries comes
 *  through. Blender FBX files arrive as Phong/Lambert materials, and this
 *  copies the FULL set of data they hold (base color, diffuse texture,
 *  normal map, bump map, AO map, emissive map, opacity, vertex colors),
 *  not just the paint.
 *
 *  METALLIC + ROUGHNESS ARE DATA TOO: a .glb exported from Blender's
 *  Principled BSDF arrives as a real PBR material with the creator's
 *  metallic/roughness — those are kept EXACTLY (this is how "I made it
 *  metallic in Blender" survives). Only non-PBR sources (Phong/Lambert
 *  from FBX/OBJ, which carry NO metal data at all) get the classic matte
 *  plastic defaults (0 / 0.85). Creators can fine-tune both afterwards
 *  with the item's material sliders (stored on the item, applied at
 *  render time by the site and the Godot player).
 *
 *  Returns a warning string when the model landed with NO material colors
 *  at all — that is the classic "my UGC is plain white in game" trap that
 *  happens when the Blender material never made it into the export. */
function normalizeMaterials(root: THREE.Object3D): { warning: string | null; metallic: number; roughness: number } {
  let meshes = 0
  let colored = false
  // PBR bookkeeping for the material sliders' starting values: the AVERAGE
  // across every surface (a uniform Blender metal averages to itself; a
  // mixed model gives the honest overall feel)
  let metalSum = 0
  let roughSum = 0
  let matCount = 0
  root.traverse((o) => {
    const mesh = o as THREE.Mesh
    if (!(mesh as THREE.Mesh).isMesh || mesh.material == null) return
    meshes++
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
    const next = mats.map((m) => {
      const src = m as THREE.MeshStandardMaterial
      const std =
        src.isMeshStandardMaterial === true
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
      if (src.isMeshStandardMaterial === true) {
        // PBR source (a .glb/.gltf from Blender, SketchUp, ...): metallic /
        // roughness are CREATOR DATA — keep them untouched.
      } else {
        // Phong / Lambert (FBX, OBJ) carry no metal data: the classic matte
        // plastic defaults apply (the sliders can change them later)
        std.metalness = 0
        std.roughness = 0.85
      }
      metalSum += std.metalness
      roughSum += std.roughness
      matCount++
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
  const fallback = { warning: null as string | null, metallic: 0, roughness: 0.85 }
  if (meshes === 0 || matCount === 0) return fallback
  const pbr = {
    metallic: Math.min(1, Math.max(0, metalSum / matCount)),
    roughness: Math.min(1, Math.max(0, roughSum / matCount)),
  }
  if (colored) return { ...pbr, warning: null }
  return {
    ...pbr,
    warning:
      'This model has no material colors — it would show up plain white in game. ' +
      'Fix in Blender: give every material a Principled BSDF with Base Color (grey, brown, anything). ' +
      'Image textures: connect straight into Base Color, re-save TGA/TIFF images as PNG first, and export with Path Mode "Copy" + "Embed Textures" — ' +
      'or just export .glb (glTF 2.0), which always keeps colors and textures. ' +
      'You can also paint it here with a texture or a flat color.',
  }
}

export interface GlbWithCheck {
  glb: Blob
  /** non-null when every material came in plain white — shown to the creator */
  colorWarning: string | null
  /** the model's own PBR feel (average across its materials) — saved on the
   *  item at publish so the material sliders START from the file's values.
   *  metallic 0 = matte plastic, 1 = full metal; roughness 0 = gloss, 1 = matte */
  metallic: number
  roughness: number
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

  const { warning: colorWarning, metallic, roughness } = normalizeMaterials(object)
  return { glb: await objectToGlb(object, animations), colorWarning, metallic, roughness }
}

async function objectToGlb(object: THREE.Object3D, animations?: THREE.AnimationClip[]): Promise<Blob> {
  stripNonMeshes(object)
  dropUnloadedTextures(object)
  const exporter = new GLTFExporter()
  const buf = (await exporter.parseAsync(object, {
    binary: true,
    onlyVisible: true,
    ...(animations && animations.length > 0 ? { animations } : {}),
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
