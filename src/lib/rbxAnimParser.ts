import * as THREE from 'three'
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js'

export interface KeyframePose {
  name: string
  position: [number, number, number]
  quaternion: [number, number, number, number]
  weight?: number
  children?: KeyframePose[]
}

export interface ParsedKeyframe {
  time: number
  poses: Record<string, { position: [number, number, number]; quaternion: [number, number, number, number] }>
}

export interface RbxAnimationData {
  name: string
  loop: boolean
  priority: number
  length: number
  keyframes: ParsedKeyframe[]
  threeClip?: THREE.AnimationClip
}

export interface RbxAnimationPackage {
  animations: RbxAnimationData[]
  clipNames: string[]
  threeClips: Record<string, THREE.AnimationClip>
  defaultClip: string
  animSavesCount: number
}

/**
 * Standard R6 Bone mapping from Roblox Pose names to standard R6 hierarchy.
 */
export const R6_BONE_MAP: Record<string, string> = {
  'Torso': 'Torso',
  'Head': 'Head',
  'Right Arm': 'RightArm',
  'Left Arm': 'LeftArm',
  'Right Leg': 'RightLeg',
  'Left Leg': 'LeftLeg',
  'RightArm': 'RightArm',
  'LeftArm': 'LeftArm',
  'RightLeg': 'RightLeg',
  'LeftLeg': 'LeftLeg',
  'HumanoidRootPart': 'HumanoidRootPart',
}

const R6_BONES = ['HumanoidRootPart', 'Torso', 'Head', 'RightArm', 'LeftArm', 'RightLeg', 'LeftLeg'] as const

function makeCFrameMatrix(
  x: number, y: number, z: number,
  r00 = 1, r01 = 0, r02 = 0,
  r10 = 0, r11 = 1, r12 = 0,
  r20 = 0, r21 = 0, r22 = 1
): THREE.Matrix4 {
  const m = new THREE.Matrix4()
  m.set(
    r00, r01, r02, x,
    r10, r11, r12, y,
    r20, r21, r22, z,
    0, 0, 0, 1
  )
  return m
}

/**
 * Official Roblox R6 Motor6D joint definitions:
 * C0 specifies the joint transform relative to Part0 (Torso or RootPart).
 */
export const ROBLOX_R6_JOINTS: Record<string, { C0: THREE.Matrix4; node: string; restPos: [number, number, number] }> = {
  Torso: {
    C0: makeCFrameMatrix(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
    node: 'Torso',
    restPos: [0, 3, 0],
  },
  HumanoidRootPart: {
    C0: makeCFrameMatrix(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
    node: 'Torso',
    restPos: [0, 3, 0],
  },
  Head: {
    C0: makeCFrameMatrix(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
    node: 'Head',
    restPos: [0, 1, 0],
  },
  RightArm: {
    C0: makeCFrameMatrix(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
    node: 'Right_Arm',
    restPos: [-1.5, 0.5, 0],
  },
  LeftArm: {
    C0: makeCFrameMatrix(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
    node: 'Left_Arm',
    restPos: [1.5, 0.5, 0],
  },
  RightLeg: {
    C0: makeCFrameMatrix(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
    node: 'Right_Leg',
    restPos: [-0.5, -1, 0],
  },
  LeftLeg: {
    C0: makeCFrameMatrix(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
    node: 'Left_Leg',
    restPos: [0.5, -1, 0],
  },
}

const R_Y180 = new THREE.Matrix4().makeRotationY(Math.PI)
const INV_R_Y180 = new THREE.Matrix4().copy(R_Y180).invert()

/**
 * Transform a Roblox Pose CFrame into RetroBlox Three.js space:
 * 1. Joint change-of-basis: C0 * Pose * inv(C0)
 * 2. World orientation (Roblox character faces -Z, Three.js rig faces +Z): R_Y180 * M * inv(R_Y180)
 */
export function convertRobloxPoseToThree(
  boneName: string,
  rawPos: [number, number, number],
  rawQuat: [number, number, number, number]
): { position: [number, number, number]; quaternion: [number, number, number, number] } {
  const j = ROBLOX_R6_JOINTS[boneName]
  if (!j) {
    return { position: rawPos, quaternion: rawQuat }
  }

  const rawQ = new THREE.Quaternion(rawQuat[0], rawQuat[1], rawQuat[2], rawQuat[3])
  const poseM = new THREE.Matrix4().makeRotationFromQuaternion(rawQ)
  poseM.setPosition(rawPos[0], rawPos[1], rawPos[2])

  const invC0 = new THREE.Matrix4().copy(j.C0).invert()
  const jointM_roblox = new THREE.Matrix4().multiplyMatrices(j.C0, poseM).multiply(invC0)
  const jointM_three = new THREE.Matrix4().multiplyMatrices(R_Y180, jointM_roblox).multiply(INV_R_Y180)

  const pos = new THREE.Vector3()
  const quat = new THREE.Quaternion()
  const scale = new THREE.Vector3()
  jointM_three.decompose(pos, quat, scale)

  return {
    position: [pos.x, pos.y, pos.z],
    quaternion: [quat.x, quat.y, quat.z, quat.w],
  }
}

/**
 * Convert Roblox CFrame rotation matrix (R00..R22) to Three.js Quaternion (x, y, z, w).
 */
export function cframeMatrixToQuaternion(
  r00: number, r01: number, r02: number,
  r10: number, r11: number, r12: number,
  r20: number, r21: number, r22: number
): [number, number, number, number] {
  const m = new THREE.Matrix4()
  m.set(
    r00, r01, r02, 0,
    r10, r11, r12, 0,
    r20, r21, r22, 0,
    0, 0, 0, 1
  )
  const q = new THREE.Quaternion()
  q.setFromRotationMatrix(m)
  return [q.x, q.y, q.z, q.w]
}

function buildClipFromKeyframes(
  animName: string,
  parsedKeyframes: ParsedKeyframe[],
  maxTime: number
): THREE.AnimationClip {
  parsedKeyframes.sort((a, b) => a.time - b.time)
  const tracks: THREE.KeyframeTrack[] = []

  const BONE_TARGETS: Array<{ rbx: string; nodes: string[]; restPos: [number, number, number] }> = [
    { rbx: 'Torso', nodes: ['Torso'], restPos: [0, 3, 0] },
    { rbx: 'Head', nodes: ['Head'], restPos: [0, 1, 0] },
    { rbx: 'RightArm', nodes: ['Right_Arm', 'RightArm'], restPos: [-1.5, 0.5, 0] },
    { rbx: 'LeftArm', nodes: ['Left_Arm', 'LeftArm'], restPos: [1.5, 0.5, 0] },
    { rbx: 'RightLeg', nodes: ['Right_Leg', 'RightLeg'], restPos: [-0.5, -1, 0] },
    { rbx: 'LeftLeg', nodes: ['Left_Leg', 'LeftLeg'], restPos: [0.5, -1, 0] },
    { rbx: 'HumanoidRootPart', nodes: ['HumanoidRootPart'], restPos: [0, 0, 0] },
  ]

  for (const b of BONE_TARGETS) {
    const times: number[] = []
    const quatValues: number[] = []
    const posValues: number[] = []

    for (const kf of parsedKeyframes) {
      if (kf.poses[b.rbx]) {
        times.push(kf.time)
        const p = kf.poses[b.rbx]
        const conv = convertRobloxPoseToThree(b.rbx, p.position, p.quaternion)
        quatValues.push(conv.quaternion[0], conv.quaternion[1], conv.quaternion[2], conv.quaternion[3])
        posValues.push(b.restPos[0] + conv.position[0], b.restPos[1] + conv.position[1], b.restPos[2] + conv.position[2])
      }
    }

    if (times.length > 0) {
      for (const nodeName of b.nodes) {
        tracks.push(new THREE.QuaternionKeyframeTrack(`${nodeName}.quaternion`, times, quatValues))
        if (b.rbx === 'Torso' && nodeName === 'Torso') {
          tracks.push(new THREE.VectorKeyframeTrack(`${nodeName}.position`, times, posValues))
        }
      }
    }
  }

  const duration = Math.max(maxTime, 0.1)
  return new THREE.AnimationClip(animName, duration, tracks)
}

function deduplicateName(rawName: string, usedNames: Set<string>): string {
  const base = rawName.trim() || 'RobloxAnimation'
  if (!usedNames.has(base)) {
    usedNames.add(base)
    return base
  }
  let idx = 2
  while (usedNames.has(`${base} (${idx})`)) idx++
  const unique = `${base} (${idx})`
  usedNames.add(unique)
  return unique
}

function packageFromAnimations(animations: RbxAnimationData[]): RbxAnimationPackage | null {
  if (animations.length === 0) return null
  const clipNames: string[] = []
  const threeClips: Record<string, THREE.AnimationClip> = {}
  for (const anim of animations) {
    clipNames.push(anim.name)
    if (anim.threeClip) {
      threeClips[anim.name] = anim.threeClip
    }
  }
  return {
    animations,
    clipNames,
    threeClips,
    defaultClip: clipNames[0] || '',
    animSavesCount: animations.length,
  }
}

/**
 * Parse ALL KeyframeSequences from a Roblox XML (.rbxmx / XML .rbxm) file,
 * including multi-animation AnimSaves folders.
 */
export function parseRbxmxAnimations(xmlString: string): RbxAnimationPackage | null {
  try {
    const parser = new DOMParser()
    const doc = parser.parseFromString(xmlString, 'text/xml')

    let kfsElements = Array.from(doc.querySelectorAll('Item[class="KeyframeSequence"]'))
    if (kfsElements.length === 0) {
      const fallback = doc.querySelector('KeyframeSequence')
      if (fallback) kfsElements = [fallback]
    }
    if (kfsElements.length === 0) return null

    const usedNames = new Set<string>()
    const animations: RbxAnimationData[] = []

    for (const kfs of kfsElements) {
      let rawName = 'RobloxAnimation'
      let loop = true
      let priority = 2

      const props = kfs.querySelector(':scope > Properties') || kfs.querySelector('Properties')
      if (props) {
        const nameEl = props.querySelector('string[name="Name"]')
        if (nameEl && nameEl.textContent) rawName = nameEl.textContent.trim()

        const loopEl = props.querySelector('bool[name="Loop"]')
        if (loopEl && loopEl.textContent) loop = loopEl.textContent.trim().toLowerCase() === 'true'

        const prioEl = props.querySelector('token[name="Priority"], int[name="Priority"]')
        if (prioEl && prioEl.textContent) priority = parseInt(prioEl.textContent.trim(), 10) || 2
      }

      const animName = deduplicateName(rawName, usedNames)
      const keyframeEls = Array.from(kfs.querySelectorAll('Item[class="Keyframe"]'))
      const parsedKeyframes: ParsedKeyframe[] = []
      let maxTime = 0

      for (const kfEl of keyframeEls) {
        const kfProps = kfEl.querySelector(':scope > Properties')
        let time = 0
        if (kfProps) {
          const timeEl = kfProps.querySelector('float[name="Time"]')
          if (timeEl && timeEl.textContent) {
            time = parseFloat(timeEl.textContent.trim()) || 0
          }
        }
        if (time > maxTime) maxTime = time

        const poses: Record<string, { position: [number, number, number]; quaternion: [number, number, number, number] }> = {}

        const extractPoses = (parentEl: Element) => {
          const poseItems = Array.from(parentEl.querySelectorAll(':scope > Item[class="Pose"]'))
          for (const poseItem of poseItems) {
            const pProps = poseItem.querySelector(':scope > Properties')
            if (pProps) {
              let pName = ''
              const nameEl = pProps.querySelector('string[name="Name"]')
              if (nameEl && nameEl.textContent) pName = nameEl.textContent.trim()

              const cfEl = pProps.querySelector('CoordinateFrame[name="CFrame"]')
              if (cfEl && pName) {
                const x = parseFloat(cfEl.querySelector('X')?.textContent || '0') || 0
                const y = parseFloat(cfEl.querySelector('Y')?.textContent || '0') || 0
                const z = parseFloat(cfEl.querySelector('Z')?.textContent || '0') || 0

                const r00 = parseFloat(cfEl.querySelector('R00')?.textContent || '1') || 1
                const r01 = parseFloat(cfEl.querySelector('R01')?.textContent || '0') || 0
                const r02 = parseFloat(cfEl.querySelector('R02')?.textContent || '0') || 0

                const r10 = parseFloat(cfEl.querySelector('R10')?.textContent || '0') || 0
                const r11 = parseFloat(cfEl.querySelector('R11')?.textContent || '1') || 1
                const r12 = parseFloat(cfEl.querySelector('R12')?.textContent || '0') || 0

                const r20 = parseFloat(cfEl.querySelector('R20')?.textContent || '0') || 0
                const r21 = parseFloat(cfEl.querySelector('R21')?.textContent || '0') || 0
                const r22 = parseFloat(cfEl.querySelector('R22')?.textContent || '1') || 1

                const quat = cframeMatrixToQuaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)
                const mappedName = R6_BONE_MAP[pName] || pName
                poses[mappedName] = { position: [x, y, z], quaternion: quat }
              }
            }
            extractPoses(poseItem)
          }
        }

        extractPoses(kfEl)
        parsedKeyframes.push({ time, poses })
      }

      const threeClip = buildClipFromKeyframes(animName, parsedKeyframes, maxTime)
      animations.push({
        name: animName,
        loop,
        priority,
        length: threeClip.duration,
        keyframes: parsedKeyframes,
        threeClip,
      })
    }

    return packageFromAnimations(animations)
  } catch (err) {
    console.warn('Failed to parse rbxmx animations:', err)
    return null
  }
}

/**
 * Legacy single-clip helper kept for backwards compatibility.
 */
export function parseRbxmxAnimation(xmlString: string): RbxAnimationData | null {
  const pkg = parseRbxmxAnimations(xmlString)
  return pkg ? pkg.animations[0] || null : null
}

/* ---------------- Binary .rbxm (<roblox!) parser ---------------- */

function decompressLZ4Block(src: Uint8Array, uncompressedLen: number): Uint8Array {
  const dst = new Uint8Array(uncompressedLen)
  let sIdx = 0
  let dIdx = 0

  while (sIdx < src.length) {
    const token = src[sIdx++]
    let literalLen = token >> 4
    if (literalLen === 15) {
      let b = 255
      while (b === 255 && sIdx < src.length) {
        b = src[sIdx++]
        literalLen += b
      }
    }
    for (let i = 0; i < literalLen && sIdx < src.length && dIdx < uncompressedLen; i++) {
      dst[dIdx++] = src[sIdx++]
    }
    if (sIdx >= src.length || dIdx >= uncompressedLen) break

    const offset = src[sIdx] | (src[sIdx + 1] << 8)
    sIdx += 2
    if (offset === 0) break

    let matchLen = (token & 0x0f) + 4
    if ((token & 0x0f) === 15) {
      let b = 255
      while (b === 255 && sIdx < src.length) {
        b = src[sIdx++]
        matchLen += b
      }
    }
    let mPos = dIdx - offset
    for (let i = 0; i < matchLen && dIdx < uncompressedLen; i++) {
      dst[dIdx++] = dst[mPos++]
    }
  }
  return dst
}

function unrotateInt32(v: number): number {
  return (v >>> 1) ^ -(v & 1)
}

function readInterleavedInt32(data: Uint8Array, offset: number, count: number): number[] {
  const out = new Array<number>(count)
  for (let i = 0; i < count; i++) {
    const b0 = data[offset + i]
    const b1 = data[offset + count + i]
    const b2 = data[offset + count * 2 + i]
    const b3 = data[offset + count * 3 + i]
    const raw = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    out[i] = unrotateInt32(raw)
  }
  return out
}

function readInterleavedFloat32(data: Uint8Array, offset: number, count: number): number[] {
  const out = new Array<number>(count)
  const buf = new ArrayBuffer(4)
  const view = new DataView(buf)
  for (let i = 0; i < count; i++) {
    const b0 = data[offset + i]
    const b1 = data[offset + count + i]
    const b2 = data[offset + count * 2 + i]
    const b3 = data[offset + count * 3 + i]
    const rotated = ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) >>> 0
    const raw = ((rotated >>> 1) | ((rotated & 1) << 31)) >>> 0
    view.setUint32(0, raw, false)
    out[i] = view.getFloat32(0, false)
  }
  return out
}

function orientIdToMatrix(id: number): [number, number, number, number, number, number, number, number, number] {
  // Roblox normal IDs: 0=Right(+X), 1=Top(+Y), 2=Back(+Z), 3=Left(-X), 4=Bottom(-Y), 5=Front(-Z)
  const norms: [number, number, number][] = [
    [1, 0, 0], [0, 1, 0], [0, 0, 1],
    [-1, 0, 0], [0, -1, 0], [0, 0, -1],
  ]
  const idx = id - 1
  const rIdx = Math.floor(idx / 6) % 6
  const uIdx = idx % 6
  const r = norms[rIdx] || [1, 0, 0]
  const u = norms[uIdx] || [0, 1, 0]
  const f: [number, number, number] = [
    r[1] * u[2] - r[2] * u[1],
    r[2] * u[0] - r[0] * u[2],
    r[0] * u[1] - r[1] * u[0],
  ]
  return [r[0], u[0], f[0], r[1], u[1], f[1], r[2], u[2], f[2]]
}

interface BinaryInstance {
  id: number
  className: string
  parentId: number
  name: string
  loop?: boolean
  priority?: number
  time?: number
  cframe?: { position: [number, number, number]; quaternion: [number, number, number, number] }
}

export function parseBinaryRbxmAnimations(buf: ArrayBuffer): RbxAnimationPackage | null {
  try {
    const bytes = new Uint8Array(buf)
    const view = new DataView(buf)
    if (bytes.length < 32) return null

    // Magic: "<roblox!\x89\xff\r\n\x1a\n" (14 bytes) + version(2) + classCount(4) + instanceCount(4) + reserved(8) = 32
    let pos = 32
    const decoder = new TextDecoder('utf-8')
    const classes: Record<number, { className: string; instances: number[] }> = {}
    const instances: Map<number, BinaryInstance> = new Map()

    while (pos + 16 <= bytes.length) {
      const chunkName = String.fromCharCode(bytes[pos], bytes[pos + 1], bytes[pos + 2], bytes[pos + 3])
      const compLen = view.getUint32(pos + 4, true)
      const uncompLen = view.getUint32(pos + 8, true)
      pos += 16

      if (chunkName === 'END\0') break

      const rawLen = compLen === 0 ? uncompLen : compLen
      if (pos + rawLen > bytes.length) break
      const rawSlice = bytes.subarray(pos, pos + rawLen)
      pos += rawLen

      const data = compLen === 0 ? rawSlice : decompressLZ4Block(rawSlice, uncompLen)
      const dView = new DataView(data.buffer, data.byteOffset, data.byteLength)

      if (chunkName === 'INST') {
        let p = 0
        const classId = dView.getUint32(p, true); p += 4
        const nameLen = dView.getUint32(p, true); p += 4
        const className = decoder.decode(data.subarray(p, p + nameLen)); p += nameLen
        const hasAdditional = data[p++]; // 0 or 1
        const instCount = dView.getUint32(p, true); p += 4
        const deltas = readInterleavedInt32(data, p, instCount); p += instCount * 4
        if (hasAdditional) p += instCount // skip service flags

        const ids: number[] = []
        let acc = 0
        for (let i = 0; i < instCount; i++) {
          acc += deltas[i]
          ids.push(acc)
          instances.set(acc, { id: acc, className, parentId: -1, name: className })
        }
        classes[classId] = { className, instances: ids }
      } else if (chunkName === 'PROP') {
        let p = 0
        const classId = dView.getUint32(p, true); p += 4
        const propLen = dView.getUint32(p, true); p += 4
        const propName = decoder.decode(data.subarray(p, p + propLen)); p += propLen
        const propType = data[p++]
        const cls = classes[classId]
        if (!cls) continue
        const count = cls.instances.length

        if (propType === 0x01 && propName === 'Name') {
          for (let i = 0; i < count && p + 4 <= data.length; i++) {
            const sLen = dView.getUint32(p, true); p += 4
            const val = decoder.decode(data.subarray(p, p + sLen)); p += sLen
            const inst = instances.get(cls.instances[i])
            if (inst) inst.name = val
          }
        } else if (propType === 0x02 && propName === 'Loop') {
          for (let i = 0; i < count && p < data.length; i++) {
            const inst = instances.get(cls.instances[i])
            if (inst) inst.loop = data[p] !== 0
            p++
          }
        } else if (propType === 0x03 && propName === 'Priority') {
          const vals = readInterleavedInt32(data, p, count)
          for (let i = 0; i < count; i++) {
            const inst = instances.get(cls.instances[i])
            if (inst) inst.priority = vals[i]
          }
        } else if (propType === 0x04 && propName === 'Time') {
          const vals = readInterleavedFloat32(data, p, count)
          for (let i = 0; i < count; i++) {
            const inst = instances.get(cls.instances[i])
            if (inst) inst.time = vals[i]
          }
        } else if (propType === 0x10 && propName === 'CFrame') {
          const quats: [number, number, number, number][] = []
          for (let i = 0; i < count && p < data.length; i++) {
            const orientId = data[p++]
            if (orientId === 0) {
              const m: number[] = []
              for (let k = 0; k < 9; k++) {
                m.push(dView.getFloat32(p, true))
                p += 4
              }
              quats.push(cframeMatrixToQuaternion(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]))
            } else {
              const m = orientIdToMatrix(orientId)
              quats.push(cframeMatrixToQuaternion(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]))
            }
          }
          if (p + count * 12 <= data.length) {
            const xs = readInterleavedFloat32(data, p, count)
            const ys = readInterleavedFloat32(data, p + count * 4, count)
            const zs = readInterleavedFloat32(data, p + count * 8, count)
            for (let i = 0; i < count; i++) {
              const inst = instances.get(cls.instances[i])
              if (inst) {
                inst.cframe = {
                  position: [xs[i], ys[i], zs[i]],
                  quaternion: quats[i] || [0, 0, 0, 1],
                }
              }
            }
          }
        }
      } else if (chunkName === 'PRNT') {
        let p = 0
        p++ // version
        const count = dView.getUint32(p, true); p += 4
        const childDeltas = readInterleavedInt32(data, p, count)
        const parentDeltas = readInterleavedInt32(data, p + count * 4, count)
        let cAcc = 0
        let pAcc = 0
        for (let i = 0; i < count; i++) {
          cAcc += childDeltas[i]
          pAcc += parentDeltas[i]
          const inst = instances.get(cAcc)
          if (inst) inst.parentId = pAcc
        }
      }
    }

    // Build parent -> children map
    const childrenOf = new Map<number, BinaryInstance[]>()
    const kfsList: BinaryInstance[] = []
    for (const inst of instances.values()) {
      if (!childrenOf.has(inst.parentId)) childrenOf.set(inst.parentId, [])
      childrenOf.get(inst.parentId)!.push(inst)
      if (inst.className === 'KeyframeSequence') kfsList.push(inst)
    }

    if (kfsList.length === 0) return null

    const usedNames = new Set<string>()
    const animations: RbxAnimationData[] = []

    for (const kfs of kfsList) {
      const animName = deduplicateName(kfs.name || 'RobloxAnimation', usedNames)
      const kfChildren = (childrenOf.get(kfs.id) || []).filter((c) => c.className === 'Keyframe')
      const parsedKeyframes: ParsedKeyframe[] = []
      let maxTime = 0

      for (const kf of kfChildren) {
        const t = kf.time ?? 0
        if (t > maxTime) maxTime = t
        const poses: Record<string, { position: [number, number, number]; quaternion: [number, number, number, number] }> = {}

        const walkPoses = (parentId: number) => {
          for (const ch of childrenOf.get(parentId) || []) {
            if (ch.className === 'Pose' && ch.cframe) {
              const mapped = R6_BONE_MAP[ch.name] || ch.name
              poses[mapped] = ch.cframe
            }
            walkPoses(ch.id)
          }
        }
        walkPoses(kf.id)
        parsedKeyframes.push({ time: t, poses })
      }

      const threeClip = buildClipFromKeyframes(animName, parsedKeyframes, maxTime)
      animations.push({
        name: animName,
        loop: kfs.loop ?? true,
        priority: kfs.priority ?? 2,
        length: threeClip.duration,
        keyframes: parsedKeyframes,
        threeClip,
      })
    }

    return packageFromAnimations(animations)
  } catch (err) {
    console.warn('Failed to parse binary .rbxm:', err)
    return null
  }
}

/**
 * Detects whether a file or buffer is an .rbxm / .rbxmx animation (single or multi-AnimSaves) and parses all clips.
 */
export async function parseRbxAnimationPackage(file: File | Blob): Promise<RbxAnimationPackage | null> {
  const buf = await file.arrayBuffer()
  const u8 = new Uint8Array(buf.slice(0, 16))
  const header = String.fromCharCode(...u8)

  if (header.startsWith('<roblox!')) {
    const binPkg = parseBinaryRbxmAnimations(buf)
    if (binPkg) return binPkg
    // Fallback string scan if binary contained no readable Pose CFrames
    const fullText = new TextDecoder('latin1').decode(buf)
    const nameMatch = fullText.match(/Name[\x00-\x1f]+([A-Za-z0-9_-]{3,30})/)
    const animName = nameMatch ? nameMatch[1] : 'RobloxAnim'
    const emptyClip = new THREE.AnimationClip(animName, 1.0, [])
    return packageFromAnimations([{
      name: animName,
      loop: true,
      priority: 2,
      length: 1.0,
      keyframes: [],
      threeClip: emptyClip,
    }])
  }

  const text = new TextDecoder('utf-8').decode(buf)
  if (text.includes('<roblox') || text.includes('KeyframeSequence') || text.includes('class="Keyframe"')) {
    return parseRbxmxAnimations(text)
  }

  return null
}

/**
 * Legacy single-clip file helper kept for backwards compatibility.
 */
export async function parseRbxAnimationFile(file: File | Blob): Promise<RbxAnimationData | null> {
  const pkg = await parseRbxAnimationPackage(file)
  return pkg ? pkg.animations[0] || null : null
}

/**
 * Build a standard Three.js R6 rig carrying all parsed AnimationClips and export it to a GLB Blob.
 * This allows RetroBlox's 3D preview, timeline scrubber, thumbnail capture, and catalog upload
 * to work seamlessly with .rbxm / .rbxmx AnimSaves packages.
 */
export async function buildR6AnimationGlb(pkg: RbxAnimationPackage): Promise<Blob> {
  const root = new THREE.Group()
  root.name = 'R6Rig'

  const hrp = new THREE.Object3D()
  hrp.name = 'HumanoidRootPart'
  root.add(hrp)

  const mat = new THREE.MeshStandardMaterial({ color: 0xa3a2a5, roughness: 0.7 })

  // Torso at [0, 3, 0], box 2x2x1 centered at [0, 0, 0]
  const torsoGeo = new THREE.BoxGeometry(2, 2, 1)
  const torso = new THREE.Mesh(torsoGeo, mat)
  torso.name = 'Torso'
  torso.position.set(0, 3, 0)
  hrp.add(torso)

  // Head at [0, 1, 0] (neck pivot relative to Torso), box 1.2x1.2x1.2 offset +0.6 up
  const headGeo = new THREE.BoxGeometry(1.2, 1.2, 1.2)
  headGeo.translate(0, 0.6, 0)
  const head = new THREE.Mesh(headGeo, mat)
  head.name = 'Head'
  head.position.set(0, 1, 0)

  // Right_Arm at [-1.5, 0.5, 0] (shoulder pivot relative to Torso), box 1x2x1 offset -0.5 down
  const armGeoR = new THREE.BoxGeometry(1, 2, 1)
  armGeoR.translate(0, -0.5, 0)
  const rightArm = new THREE.Mesh(armGeoR, mat)
  rightArm.name = 'Right_Arm'
  rightArm.position.set(-1.5, 0.5, 0)

  // Left_Arm at [1.5, 0.5, 0] (shoulder pivot relative to Torso), box 1x2x1 offset -0.5 down
  const armGeoL = new THREE.BoxGeometry(1, 2, 1)
  armGeoL.translate(0, -0.5, 0)
  const leftArm = new THREE.Mesh(armGeoL, mat)
  leftArm.name = 'Left_Arm'
  leftArm.position.set(1.5, 0.5, 0)

  // Right_Leg at [-0.5, -1, 0] (hip pivot relative to Torso), box 1x2x1 offset -1.0 down
  const legGeoR = new THREE.BoxGeometry(1, 2, 1)
  legGeoR.translate(0, -1.0, 0)
  const rightLeg = new THREE.Mesh(legGeoR, mat)
  rightLeg.name = 'Right_Leg'
  rightLeg.position.set(-0.5, -1, 0)

  // Left_Leg at [0.5, -1, 0] (hip pivot relative to Torso), box 1x2x1 offset -1.0 down
  const legGeoL = new THREE.BoxGeometry(1, 2, 1)
  legGeoL.translate(0, -1.0, 0)
  const leftLeg = new THREE.Mesh(legGeoL, mat)
  leftLeg.name = 'Left_Leg'
  leftLeg.position.set(0.5, -1, 0)

  torso.add(head, rightArm, leftArm, rightLeg, leftLeg)

  const clips = pkg.animations
    .map((a) => a.threeClip)
    .filter((c): c is THREE.AnimationClip => Boolean(c))

  const exporter = new GLTFExporter()
  const arrayBuf = await exporter.parseAsync(root, { binary: true, animations: clips }) as ArrayBuffer
  return new Blob([arrayBuf], { type: 'model/gltf-binary' })
}
