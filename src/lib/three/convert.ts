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

/** Normalize every material to matte PBR before the GLB is written, so the
 *  item looks IDENTICAL on the site, in the Godot kit and in future SDKs.
 *
 *  Why this matters: Blender FBX files arrive as Phong/Lambert materials.
 *  They keep their Base Color here (grey stays grey, brown stays brown),
 *  and metalness is zeroed because the classic look is matte plastic —
 *  never a metal mirror.
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
      const std =
        src.isMeshStandardMaterial === true
          ? (src.clone() as THREE.MeshStandardMaterial)
          : new THREE.MeshStandardMaterial()
      if (std !== src) {
        // Phong / Lambert (what FBX and OBJ come in as) -> PBR, keeping the paint
        std.name = src.name
        std.color = (src.color ?? new THREE.Color(1, 1, 1)).clone()
        const phong = src as unknown as THREE.MeshPhongMaterial
        if (phong.map) std.map = phong.map
        if (phong.emissive) std.emissive = phong.emissive.clone()
        std.transparent = src.transparent
        std.opacity = src.opacity
        std.alphaTest = src.alphaTest
        std.side = src.side
      }
      std.metalness = 0
      std.roughness = 0.85
      if (hasRealColor(std)) colored = true
      return std
    })
    mesh.material = Array.isArray(mesh.material) ? next : next[0]
  })
  if (meshes === 0 || colored) return null
  return (
    'This model has no material colors — it would show up plain white in game. ' +
    'In Blender: give every material a Principled BSDF with Base Color (grey, brown, anything), ' +
    'or export glTF Binary (.glb). You can also paint it here with a texture or a flat color.'
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
      const obj = new FBXLoader().parse(await file.arrayBuffer(), '')
      object = obj
      animations = keep ? (obj as THREE.Group & { animations: THREE.AnimationClip[] }).animations : undefined
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

async function objectToGlb(object: THREE.Object3D, animations?: THREE.AnimationClip[]): Promise<Blob> {
  stripNonMeshes(object)
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
      const buf = await file.arrayBuffer()
      const obj = new FBXLoader().parse(buf, '')
      return await objectToGlb(obj, keep ? (obj as THREE.Group & { animations: THREE.AnimationClip[] }).animations : undefined)
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
