/* Official template GLB: clips must still retarget verbatim onto the noob. */
import * as fs from 'node:fs'
import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import * as THREE from 'three'
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js'
import { retargetClipWithRest, clipHasBoneTracks, matchPart } from '../src/lib/three/rig'

/* node-side stand-in for prepareRigView (loadRig needs a browser URL) */
function buildNoobView(): THREE.Group {
  const u8 = fs.readFileSync('/home/z/my-project/public/models/R6IK.fbx')
  const ab = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)
  const fbx = new FBXLoader().parse(ab as ArrayBuffer, '')
  const yawWrap = new THREE.Group()
  yawWrap.add(fbx)
  fbx.rotation.y = Math.PI
  const box = new THREE.Box3().setFromObject(yawWrap)
  yawWrap.scale.setScalar(5 / Math.max(box.getSize(new THREE.Vector3()).y, 0.0001))
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
  const norm = (s: string) => s.toLowerCase().replace(/[$][a-z0-9_]+/g, '').replace(/[\s._]+/g, ' ').trim()
  const boneNames = new Set<string>()
  group.traverse((o) => { if ((o as THREE.Bone).isBone && o.name) boneNames.add(norm(o.name)) })
  group.traverse((o) => {
    if ((o as THREE.Bone).isBone || !o.name) return
    if (boneNames.has(norm(o.name))) o.name = `${o.name}.Mesh`
  })
  void matchPart
  return group
}

const URLany = URL as unknown as Record<string, unknown>
if (typeof URLany.createObjectURL !== 'function') URLany.createObjectURL = () => ''

async function main() {
  const bytes = fs.readFileSync('/home/z/my-project/public/models/retroblox-rig-template.glb')
  const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
  const gltf = await new GLTFLoader().parseAsync(ab, '')
  const scene = gltf.scene as THREE.Group
  const clips = gltf.animations || []
  console.log('template clips:', clips.map((c) => `${c.name}(${c.tracks.length})`).join(', ') || 'NONE')
  const view = buildNoobView()
  let checked = 0
  for (const clip of clips) {
    if (!clipHasBoneTracks(clip, scene)) { console.log(`  "${clip.name}" filtered as object-junk`); continue }
    const out = retargetClipWithRest(clip, scene, view)
    if (!out) { console.log(`  "${clip.name}" bound NOTHING`); continue }
    // verbatim check: same track count, values unchanged for quaternion tracks
    let same = out.tracks.length === clip.tracks.filter((t) => !t.name.endsWith('.scale')).length
    for (const t of out.tracks) {
      const src = clip.tracks.find((x) => x.name === t.name)
      if (!src) { same = false; break }
      for (let i = 0; i < t.values.length; i++) {
        if (Math.abs((t.values[i] as number) - (src.values[i] as number)) > 1e-6) { same = false; break }
      }
    }
    console.log(`  "${clip.name}": ${out.tracks.length} tracks, verbatim=${same}`)
    checked++
    if (!same) process.exitCode = 1
  }
  console.log(checked > 0 ? 'TEMPLATE_CHECK_DONE' : 'NO_CLIPS_IN_TEMPLATE (nothing to check)')
}
main().catch((e) => { console.error(e); process.exit(1) })
