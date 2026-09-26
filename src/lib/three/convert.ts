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

function stripNonMeshes(root: THREE.Object3D) {
  const trash: THREE.Object3D[] = []
  root.traverse((o) => {
    if ((o as THREE.Light).isLight || (o as THREE.Camera).isCamera) trash.push(o)
  })
  trash.forEach((o) => o.parent?.remove(o))
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
