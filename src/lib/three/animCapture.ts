'use client'

/* ------------------------------------------------------------------
   Publish-time thumbnails for RIGGED uploads (emotes / bundles / anims).
   The catalog shot is captured from the actual upload: pose it at ANY
   moment the creator wants (the timeline marker) or a nice mid-clip
   default, frame it on white, and hand back a PNG blob.

   captureNoobThumb is the EMOTE ICON: the classic GREY NOOB plays the
   clip at the marked moment — that exact pose becomes the icon shown
   on the marketplace card and inside the in-game emote wheel.
------------------------------------------------------------------ */

import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { applyLook, prepareRigView, retargetClipToRoot, type AvatarLook3D } from '@/lib/three/rig'

/** Seek ONE action to an exact time and sample the pose (mixer.update(0)
 *  evaluates at action.time — setTime would fight the mixer's own clock). */
function poseAt(mixer: THREE.AnimationMixer, actions: THREE.AnimationAction[], t: number) {
  for (const a of actions) {
    a.play()
    a.paused = true
    a.time = Math.max(0, Math.min(t, a.getClip().duration))
  }
  mixer.update(0)
}

/** Shared white-square shot: light `root`, frame it alone, return a PNG blob. */
async function shootIsolated(root: THREE.Object3D, size: number): Promise<Blob> {
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
  renderer.setPixelRatio(1)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.setSize(size, size, false)

  const scene = new THREE.Scene()
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8899aa, 1.25))
  const sun = new THREE.DirectionalLight(0xffffff, 1.7)
  sun.position.set(4, 9, 7)
  scene.add(sun)
  const sun2 = new THREE.DirectionalLight(0xffffff, 0.7)
  sun2.position.set(-6, 3, -4)
  scene.add(sun2)
  scene.add(root)
  scene.updateMatrixWorld(true)

  // frame ONLY the model (a touch of headroom)
  const box = new THREE.Box3().setFromObject(root)
  if (box.isEmpty()) throw new Error('empty model')
  const center = box.getCenter(new THREE.Vector3())
  const modelSize = box.getSize(new THREE.Vector3())
  const maxDim = Math.max(modelSize.x, modelSize.y, modelSize.z, 0.001)
  const fov = 32
  const dist = (maxDim / 2) / Math.tan((fov * Math.PI) / 360) * 1.14
  const cam = new THREE.PerspectiveCamera(fov, 1, 0.01, 500)
  cam.position.set(center.x + dist * 0.32, center.y + dist * 0.22, center.z + dist * 0.92)
  cam.lookAt(center)
  renderer.render(scene, cam)

  const out = document.createElement('canvas')
  out.width = size
  out.height = size
  const ctx = out.getContext('2d')!
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, size, size)
  ctx.drawImage(renderer.domElement, 0, 0, size, size)

  root.removeFromParent()
  renderer.dispose()
  renderer.forceContextLoss()

  return await new Promise<Blob>((resolve, reject) => {
    out.toBlob((b) => (b ? resolve(b) : reject(new Error('capture failed'))), 'image/png')
  })
}

/** Render a rigged GLB alone onto a white square. When clipName is given the
 *  model is posed at `atTime` (or a nice default moment) before the shot. */
export async function captureRiggedThumb(
  url: string,
  clipName?: string,
  size = 512,
  atTime?: number
): Promise<Blob> {
  const gltf = await new GLTFLoader().loadAsync(url)
  const root = gltf.scene

  // pose the model: play the clip silently and hold it at the chosen moment
  if (clipName && gltf.animations?.length) {
    const clip = gltf.animations.find((c) => c.name === clipName) || gltf.animations[0]
    const mixer = new THREE.AnimationMixer(root)
    const action = mixer.clipAction(clip)
    const t = typeof atTime === 'number' && Number.isFinite(atTime)
      ? atTime
      : Math.min(clip.duration * 0.35, 0.8)
    poseAt(mixer, [action], t)
    root.updateMatrixWorld(true)
  }

  return shootIsolated(root, size)
}

/** The GREY NOOB icon: the classic body plays the clip at `atTime` and that
 *  exact pose becomes the emote icon (marketplace card + in-game wheel). */
export async function captureNoobThumb(
  url: string,
  clipName: string | undefined,
  atTime: number,
  size = 512
): Promise<Blob> {
  const { view, rig } = await prepareRigView()

  // all-grey noob — no face, no clothes, just the classic blocky body
  const noob: AvatarLook3D = {
    skin: '#9aa0a6',
    shirtColor: '#8f959c',
    shirtImage: null,
    pantsColor: '#868c93',
    pantsImage: null,
    faceUrl: null,
    tshirtUrls: [],
    models: [],
    bundle: null,
  }
  await applyLook(view, rig, noob).catch(() => {})

  // the clip retargets onto the body by part name (LeftArm -> "Left Arm"...)
  let posed = false
  if (clipName) {
    try {
      const { clips } = await new GLTFLoader().loadAsync(url).then((g) => ({ clips: g.animations || [] }))
      const clip = clips.find((c) => c.name === clipName) || clips[0]
      if (clip) {
        const bound = retargetClipToRoot(clip, view)
        if (bound) {
          const mixer = new THREE.AnimationMixer(view)
          poseAt(mixer, [mixer.clipAction(bound)], Math.max(0, atTime))
          posed = true
        }
      }
    } catch { /* fall through to a standing pose */ }
  }
  if (!posed) view.updateMatrixWorld(true)

  return shootIsolated(view, size)
}
