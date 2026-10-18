/* EMOTE REPRO — runs the Blender-exported wave (authored ON the real R6IK rig)
 * through the EXACT production pipeline and measures what the grey noob does:
 *   GLB path:  GLTFLoader -> clips -> retargetClipWithRest -> pose on the noob
 *   FBX path:  fileToGlb (FBXLoader + GLTFExporter roundtrip, what production
 *              stores) -> same as above
 * Measured: head world displacement (should stay ON the body), arm world
 * rotation vs rest (should transfer the authored 60deg wave), arm drift.
 * Run: npx tsx scripts/emote_repro.ts
 */
import * as fs from 'node:fs'
import * as path from 'node:path'
import * as THREE from 'three'
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { worthyClips } from '../src/lib/three/convert'
import { retargetClipWithRest, matchPart, clipHasBoneTracks } from '../src/lib/three/rig'

const URLany = URL as unknown as Record<string, unknown>
if (typeof URLany.createObjectURL !== 'function') URLany.createObjectURL = () => ''
// FBXLoader decodes embedded textures through FileReader — node polyfill
if (typeof globalThis.FileReader === 'undefined') {
  class FR {
    result: unknown = null
    onloadend: (() => void) | null = null
    onload: (() => void) | null = null
    onerror: (() => void) | null = null
    readAsArrayBuffer(b: Blob) {
      ;(b as Blob).arrayBuffer().then((r) => { this.result = r; this.onloadend?.(); this.onload?.() })
    }
    readAsDataURL(b: Blob) {
      ;(b as Blob).arrayBuffer().then((r) => {
        let bin = ''
        const u8 = new Uint8Array(r)
        for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i])
        this.result = `data:application/octet-stream;base64,${Buffer.from(bin, 'binary').toString('base64')}`
        this.onloadend?.(); this.onload?.()
      })
    }
  }
  ;(globalThis as unknown as Record<string, unknown>).FileReader = FR
}

const DEG = 180 / Math.PI

/* ---- the noob "view" — replicates loadRig(): same normalize math ---- */
function buildNoobView(): THREE.Group {
  const u8 = fs.readFileSync(path.join(__dirname, '..', 'public', 'models', 'R6IK.fbx'))
  const ab = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)
  const fbx = new FBXLoader().parse(ab as ArrayBuffer, '')
  const yawWrap = new THREE.Group()
  yawWrap.add(fbx)
  fbx.rotation.y = Math.PI
  const box = new THREE.Box3().setFromObject(yawWrap)
  const size = box.getSize(new THREE.Vector3())
  const s = 5 / Math.max(size.y, 0.0001)
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
  // replicate loadRig's mesh rename (unique bone names)
  const norm = (s: string) => s.toLowerCase().replace(/\$[a-z0-9_]+/g, '').replace(/[\s._]+/g, ' ').trim()
  const boneNames = new Set<string>()
  group.traverse((o) => { if ((o as THREE.Bone).isBone && o.name) boneNames.add(norm(o.name)) })
  group.traverse((o) => {
    if ((o as THREE.Bone).isBone || !o.name) return
    if (!boneNames.has(norm(o.name))) return
    o.name = `${o.name}.Mesh`
  })
  return group
}

/* find a bone node on the noob by part alias or name */
function boneOf(root: THREE.Object3D, name: string): THREE.Object3D | null {
  let hit: THREE.Object3D | null = null
  root.traverse((o) => { if (!hit && (o.name === name || matchPart(o.name) === name)) hit = o })
  return hit
}

/* probe BONES only — the noob carries a mesh and a bone both named "Head";
 * PropertyBinding may pick either, but the skeleton is what must move */
function boneProbe(root: THREE.Object3D, name: string, part: string): THREE.Object3D | null {
  let hit: THREE.Object3D | null = null
  root.traverse((o) => {
    if (hit || !(o as THREE.Bone).isBone) return
    if (o.name === name || matchPart(o.name) === part) hit = o
  })
  return hit
}

interface Measurement {
  headDisp: number
  headAngle: number
  armAngle: number
  armDisp: number
  torsoDisp: number
  lowerArmAngle: number
  lowerArmDisp: number
}

function measure(root: THREE.Object3D, rest: Map<string, { pos: THREE.Vector3; quat: THREE.Quaternion }>): Measurement {
  root.updateMatrixWorld(true)
  const head = boneProbe(root, 'Head', 'head')!
  const arm = boneProbe(root, 'LeftUpperArm', 'armL')!
  const lower = root.getObjectByName('LeftArm002')! // unique name — the bone the wave keys
  const torso = boneProbe(root, 'Torso', 'torso')!
  const hw = head.getWorldPosition(new THREE.Vector3())
  const hq = head.getWorldQuaternion(new THREE.Quaternion())
  const aw = arm.getWorldPosition(new THREE.Vector3())
  const aq = arm.getWorldQuaternion(new THREE.Quaternion())
  const lw = lower.getWorldPosition(new THREE.Vector3())
  const lq = lower.getWorldQuaternion(new THREE.Quaternion())
  const tw = torso.getWorldPosition(new THREE.Vector3())
  const hRest = rest.get('head')!
  const aRest = rest.get('armL')!
  const lRest = rest.get('lowerArmL')!
  const tRest = rest.get('torso')!
  return {
    headDisp: hw.distanceTo(hRest.pos),
    headAngle: hq.angleTo(hRest.quat) * DEG,
    armAngle: aq.angleTo(aRest.quat) * DEG,
    armDisp: aw.distanceTo(aRest.pos),
    torsoDisp: tw.distanceTo(tRest.pos),
    lowerArmAngle: lq.angleTo(lRest.quat) * DEG,
    lowerArmDisp: lw.distanceTo(lRest.pos),
  }
}

function restSnapshot(root: THREE.Object3D): Map<string, { pos: THREE.Vector3; quat: THREE.Quaternion }> {
  root.updateMatrixWorld(true)
  const m = new Map<string, { pos: THREE.Vector3; quat: THREE.Quaternion }>()
  for (const key of ['head', 'armL', 'torso', 'lowerArmL'] as const) {
    const o = key === 'lowerArmL' ? root.getObjectByName('LeftArm002')! : boneProbe(root, key.toUpperCase(), key)!
    m.set(key, { pos: o.getWorldPosition(new THREE.Vector3()), quat: o.getWorldQuaternion(new THREE.Quaternion()) })
  }
  return m
}

async function gltfFromBuffer(buf: ArrayBuffer, label: string): Promise<{ scene: THREE.Group; clips: THREE.AnimationClip[] }> {
  const loader = new GLTFLoader()
  const gltf = await loader.parseAsync(buf, '')
  const clips = (gltf.animations || []).filter((c) => c.tracks.length > 0)
  console.log(`\n===== ${label} =====`)
  console.log(`clips: ${JSON.stringify(gltf.animations.map((c) => c.name))}`)
  for (const c of clips) {
    console.log(`  clip "${c.name}" dur=${c.duration.toFixed(2)}s tracks=${c.tracks.length}: ${c.tracks.slice(0, 8).map((t) => t.name).join(' | ')}${c.tracks.length > 8 ? ' ...' : ''}`)
  }
  return { scene: gltf.scene as THREE.Group, clips }
}

async function main() {
  const view = buildNoobView()
  const rest = restSnapshot(view)
  console.log('noob rest: head y=' + rest.get('head')!.pos.y.toFixed(2) + ' arm pos=' + rest.get('armL')!.pos.toArray().map((v) => v.toFixed(2)).join(','))

  for (const [file, kind] of [['wave.glb', 'GLB path (direct upload)'], ['wave.fbx', 'FBX path (converted like production)']] as const) {
    const p = path.join('/tmp/emoterepro', file)
    let scene: THREE.Group
    let clips: THREE.AnimationClip[]
    if (file.endsWith('.fbx')) {
      // EXACT production conversion steps — in the BROWSER fileToGlb runs
      // these verbatim (textures embed through FileReader there; node cannot
      // decode them, so the harness drops the map slots — texture plumbing
      // is browser-proven and irrelevant to the pose math).
      const bytes = fs.readFileSync(p)
      const ab2 = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
      const obj = new FBXLoader().parse(ab2, '') as THREE.Group & { animations: THREE.AnimationClip[] }
      obj.traverse((o) => {
        const mesh = o as THREE.Mesh
        if (!mesh.isMesh || mesh.material == null) return
        const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
        for (const m of mats) {
          const std = m as THREE.MeshStandardMaterial & { map?: unknown; normalMap?: unknown; bumpMap?: unknown; aoMap?: unknown; emissiveMap?: unknown; roughnessMap?: unknown; metalnessMap?: unknown; alphaMap?: unknown; specularMap?: unknown }
          for (const slot of ['map', 'normalMap', 'bumpMap', 'aoMap', 'emissiveMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'specularMap']) std[slot] = null
        }
      })
      const kept = worthyClips(obj, obj.animations || [])
      console.log(`\n===== ${kind} =====`)
      console.log(`FBX carried ${(obj.animations || []).length} takes -> worthyClips kept ${kept.length}: ${kept.map((c) => c.name).join(' | ')}`)
      const exporter = new (await import('three/examples/jsm/exporters/GLTFExporter.js')).GLTFExporter()
      const buf = (await exporter.parseAsync(obj, { binary: true, onlyVisible: true, animations: kept })) as ArrayBuffer
      const r = await gltfFromBuffer(buf, 'converted GLB')
      scene = r.scene
      clips = r.clips
    } else {
      const bytes = fs.readFileSync(p)
      const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
      const r = await gltfFromBuffer(ab, kind)
      scene = r.scene
      clips = r.clips
    }

    for (const clip of clips) {
      if (!clipHasBoneTracks(clip, scene)) { console.log(`  "${clip.name}": object-level junk — filtered out`); continue }
      const retargeted = retargetClipWithRest(clip, scene, view)
      if (!retargeted) { console.log(`  "${clip.name}": retargeted NOTHING`); continue }
      console.log(`  -> "${clip.name}" retargeted: ${retargeted.tracks.length} tracks: ${retargeted.tracks.map((t) => t.name).join(' | ')}`)
      // sample at key moments: rest(0), peak(frame 8 = 60deg), back(15 = -20deg)
      const rows: string[] = []
      let maxDisp = 0
      let peakAngle = 0
      for (const t of [0, 8 / 30, 0.5, 15 / 30, 29 / 30]) {
        const mixer = new THREE.AnimationMixer(view)
        const action = mixer.clipAction(retargeted)
        action.play()
        action.paused = true
        action.time = t
        mixer.update(0)
        const m = measure(view, rest)
        rows.push(`     t=${t.toFixed(3)}s headDisp=${m.headDisp.toFixed(3)} headRot=${m.headAngle.toFixed(1)} armDisp=${m.armDisp.toFixed(3)} armAngle=${m.armAngle.toFixed(1)} lowerArmRot=${m.lowerArmAngle.toFixed(1)} lowerArmDisp=${m.lowerArmDisp.toFixed(3)} torsoDisp=${m.torsoDisp.toFixed(3)}`)
        maxDisp = Math.max(maxDisp, m.headDisp, m.armDisp, m.torsoDisp, m.lowerArmDisp)
        peakAngle = Math.max(peakAngle, m.lowerArmAngle)
        // restore rest transforms for the next sample
        for (const [key, r] of rest) {
          const o = key === 'lowerArmL' ? view.getObjectByName('LeftArm002')! : boneProbe(view, key.toUpperCase(), key)!
          const freshRoot = buildNoobView()
          const fresh = key === 'lowerArmL' ? freshRoot.getObjectByName('LeftArm002')! : boneProbe(freshRoot, key.toUpperCase(), key)!
          o.position.copy(fresh.position)
          o.quaternion.copy(fresh.quaternion)
          void r
        }
        view.updateMatrixWorld(true)
      }
      rows.forEach((r) => console.log(r))
      if (/wave/i.test(clip.name)) {
        const okRest = maxDisp < 0.2
        const okWave = Math.abs(peakAngle - 60) < 20
        console.log(`     ${okRest ? 'PASS' : 'FAIL'} body stays together (max disp ${maxDisp.toFixed(3)})`)
        console.log(`     ${okWave ? 'PASS' : 'FAIL'} wave transfers (peak ${peakAngle.toFixed(1)}deg, expected ~60)`)
        if (!okRest || !okWave) process.exitCode = 1
      }
    }
  }
  console.log('\nREPRO_DONE')
}

main().catch((e) => { console.error(e); process.exit(1) })
