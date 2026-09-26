'use client'

/* ------------------------------------------------------------------
   Publish-time thumbnails for RIGGED uploads (emotes / bundles / anims).
   The catalog shot is captured from the actual GLB: pose it mid-clip
   (emotes/anims) or standing straight (bundles), frame it alone on
   white, and hand back a PNG blob — zero extra work for the creator.
------------------------------------------------------------------ */

import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'

/** Render a rigged GLB alone onto a white square. When clipName is given
 *  the model is posed at a nice moment of that clip before the shot. */
export async function captureRiggedThumb(
  url: string,
  clipName?: string,
  size = 512
): Promise<Blob> {
  const gltf = await new GLTFLoader().loadAsync(url)
  const root = gltf.scene

  // pose the model: play the clip silently to a nice mid-pose
  if (clipName && gltf.animations?.length) {
    const clip = gltf.animations.find((c) => c.name === clipName) || gltf.animations[0]
    const mixer = new THREE.AnimationMixer(root)
    const action = mixer.clipAction(clip)
    action.play()
    mixer.update(Math.min(clip.duration * 0.35, 0.8))
    root.updateMatrixWorld(true)
  }

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

  renderer.dispose()
  renderer.forceContextLoss()

  return await new Promise<Blob>((resolve, reject) => {
    out.toBlob((b) => (b ? resolve(b) : reject(new Error('capture failed'))), 'image/png')
  })
}
