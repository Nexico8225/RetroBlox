import * as THREE from 'three'

export interface KeyframePose {
  name: string
  position: [number, number, number] // x, y, z
  quaternion: [number, number, number, number] // x, y, z, w
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
  'HumanoidRootPart': 'HumanoidRootPart'
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

/**
 * Parse Roblox XML Animation (.rbxmx / XML .rbxm) containing a KeyframeSequence.
 */
export function parseRbxmxAnimation(xmlString: string): RbxAnimationData | null {
  try {
    const parser = new DOMParser()
    const doc = parser.parseFromString(xmlString, 'text/xml')
    
    // Look for KeyframeSequence Item
    let kfs = doc.querySelector('Item[class="KeyframeSequence"]')
    if (!kfs) {
      // In some exports, the root or child might just contain Keyframes
      kfs = doc.querySelector('KeyframeSequence') || doc.documentElement
    }

    let animName = 'RobloxAnimation'
    let loop = true
    let priority = 2

    // Properties of KeyframeSequence
    const props = kfs.querySelector(':scope > Properties') || kfs.querySelector('Properties')
    if (props) {
      const nameEl = props.querySelector('string[name="Name"]')
      if (nameEl && nameEl.textContent) animName = nameEl.textContent.trim()
      
      const loopEl = props.querySelector('bool[name="Loop"]')
      if (loopEl && loopEl.textContent) loop = loopEl.textContent.trim().toLowerCase() === 'true'

      const prioEl = props.querySelector('token[name="Priority"], int[name="Priority"]')
      if (prioEl && prioEl.textContent) priority = parseInt(prioEl.textContent.trim(), 10) || 2
    }

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

      // Recursively parse Pose items
      function extractPoses(parentEl: Element) {
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
              poses[mappedName] = {
                position: [x, y, z],
                quaternion: quat
              }
            }
          }
          // Recursively process nested child poses
          extractPoses(poseItem)
        }
      }

      extractPoses(kfEl)
      parsedKeyframes.push({ time, poses })
    }

    // Sort keyframes by time
    parsedKeyframes.sort((a, b) => a.time - b.time)

    // Build Three.js AnimationClip
    const tracks: THREE.KeyframeTrack[] = []
    const bones = ['Torso', 'Head', 'RightArm', 'LeftArm', 'RightLeg', 'LeftLeg']

    for (const bone of bones) {
      const times: number[] = []
      const quatValues: number[] = []
      const posValues: number[] = []

      for (const kf of parsedKeyframes) {
        if (kf.poses[bone]) {
          times.push(kf.time)
          const p = kf.poses[bone]
          quatValues.push(p.quaternion[0], p.quaternion[1], p.quaternion[2], p.quaternion[3])
          posValues.push(p.position[0], p.position[1], p.position[2])
        }
      }

      if (times.length > 0) {
        // Rotation track
        const rotTrack = new THREE.QuaternionKeyframeTrack(`${bone}.quaternion`, times, quatValues)
        tracks.push(rotTrack)
        // Position track (only for root or Torso)
        if (bone === 'Torso' || bone === 'HumanoidRootPart') {
          const posTrack = new THREE.VectorKeyframeTrack(`${bone}.position`, times, posValues)
          tracks.push(posTrack)
        }
      }
    }

    const duration = Math.max(maxTime, 0.1)
    const threeClip = new THREE.AnimationClip(animName, duration, tracks)

    return {
      name: animName,
      loop,
      priority,
      length: duration,
      keyframes: parsedKeyframes,
      threeClip
    }
  } catch (err) {
    console.warn('Failed to parse rbxmx animation:', err)
    return null
  }
}

/**
 * Detects whether a file or buffer is an .rbxm / .rbxmx animation and parses it.
 */
export async function parseRbxAnimationFile(file: File | Blob): Promise<RbxAnimationData | null> {
  const text = await file.text()
  if (text.includes('<roblox') || text.includes('KeyframeSequence') || text.includes('class="Keyframe"')) {
    return parseRbxmxAnimation(text)
  }
  // If binary .rbxm header
  const buf = await file.arrayBuffer()
  const u8 = new Uint8Array(buf.slice(0, 8))
  const header = String.fromCharCode(...u8)
  if (header.startsWith('<roblox!')) {
    // Binary rbxm: extract any readable string metadata or convert
    console.info('Detected binary .rbxm file format')
    // Attempt text search inside binary for sequence names
    const fullText = new TextDecoder('latin1').decode(buf)
    const nameMatch = fullText.match(/Name[\x00-\x1f]+([A-Za-z0-9_-]{3,30})/)
    const animName = nameMatch ? nameMatch[1] : 'RobloxAnim'
    return {
      name: animName,
      loop: true,
      priority: 2,
      length: 1.0,
      keyframes: []
    }
  }
  return null
}
