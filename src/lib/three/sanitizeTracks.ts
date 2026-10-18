'use client'

/* ------------------------------------------------------------------
   Animation track sanitizer — THE "100X BROKEN" FIX.

   Blender's FBX exporter bakes bone Lcl Translation keys in a DIFFERENT
   space than the rest locals every loader computes. Measured on the
   official R6IK.fbx through the real FBXLoader: "Left_Arm" position key
   0.347 vs rest local 0.003 (ratio 124), "Torso" key ~0.0 vs rest 0.38
   (the bone would collapse INTO the origin), "Right_Arm" ratio 2424. The
   junk survives the FBX -> GLB conversion, so EVERY renderer that replays
   those keys verbatim — the studio preview, the item page, and the Godot
   game — blows the character apart ("the anim is 100X broken", an arm on
   the floor, a torso at the origin). The real motion lives in the
   ROTATION tracks, which transfer cleanly.

   Rules (per position/scale track GROUP — an FBX take can carry a mesh
   object AND a bone under one name: two tracks, one junk):
     - BONES FIRST: name slots resolve to the BONE when a mesh shares the
       name (the same two-pass rule the retarget engine uses).
     - BONES ONLY: position/scale keys are only meaningful on bones —
       tracks resolving to mesh objects or skeleton CONTAINER nodes
       ("Armature") are file layout, not pose — dropped.
     - REST CONSISTENCY: a bone position/scale track whose CLOSEST key
       still misses the node's own rest transform by >2% is in a foreign
       space — dropped. Among same-name duplicates the FIRST
       rest-consistent one wins; if none is consistent the whole group
       drops.
     - Rotation tracks (the actual wave/step motion) pass untouched.

   Used at BOTH ends: convert.ts drops the junk before the GLB is stored
   (so the Godot game downloads a clean file), and rig.ts /
   animCapture.ts sanitize at playback time (covers GLB uploads that
   carry the same junk baked in by other exporters).
------------------------------------------------------------------ */

import * as THREE from 'three'

function normName(name: string): string {
  return name.toLowerCase().replace(/\$[a-z0-9_]+/g, '').replace(/[\s._]+/g, ' ').trim()
}

/** Give BONES first claim on their names before anything resolves tracks to
 *  nodes. An FBX/scene can carry a skinned MESH and a BONE sharing one name
 *  (the official R6IK.fbx has "Head" the mesh AND "Head" the bone), and
 *  every track-name lookup — GLTFExporter's findNode at export, THREE's
 *  PropertyBinding at playback — grabs the FIRST match, which is the mesh.
 *  A bone-space constant position track (1.839) landing on the head MESH is
 *  the "head floating away" bug in one line. Renaming the MESH to
 *  "<name> Mesh" makes the bone the unique owner of its name; the normName
 *  of "Head Mesh" ("head mesh") still starts with "head " so body-part
 *  alias matching, clothing and UGC attachment are untouched — the exact
 *  convention loadRig already uses on the site rig. Mutates names in place;
 *  call BEFORE sanitizeBoneTracks and before any export. */
export function dedupeBoneNameCollisions(root: THREE.Object3D): void {
  root.updateMatrixWorld(true)
  const boneNames = new Set<string>()
  root.traverse((o) => {
    if ((o as THREE.Bone).isBone && o.name) boneNames.add(normName(o.name))
  })
  if (boneNames.size === 0) return
  root.traverse((o) => {
    if ((o as THREE.Bone).isBone || !o.name) return
    if (!boneNames.has(normName(o.name))) return
    o.name = `${o.name} Mesh`
  })
}

export function sanitizeBoneTracks(clips: THREE.AnimationClip[], root: THREE.Object3D): THREE.AnimationClip[] {
  root.updateMatrixWorld(true)
  // two-pass name map: bones claim every slot first (a skinned mesh and a
  // bone often share one name — animation must measure against the BONE)
  const rests = new Map<string, { isBone: boolean; pos: THREE.Vector3; scl: THREE.Vector3 }>()
  for (const pass of [0, 1]) {
    root.traverse((o) => {
      if (!o.name) return
      const isBone = (o as THREE.Bone).isBone === true
      if (pass === 0 && !isBone) return
      if (pass === 1 && isBone) return
      const n = normName(o.name)
      if (n && !rests.has(n)) rests.set(n, { isBone, pos: o.position.clone(), scl: o.scale.clone() })
    })
  }
  if (rests.size === 0) return clips
  const minRelDeviation = (track: THREE.KeyframeTrack, rest: THREE.Vector3): number => {
    const v = track.values as Float32Array
    const ref = Math.max(rest.length(), 1e-6)
    let best = Infinity
    for (let i = 0; i + 2 < v.length; i += 3) {
      const d = Math.hypot(v[i] - rest.x, v[i + 1] - rest.y, v[i + 2] - rest.z) / ref
      if (d < best) best = d
      if (best < 0.02) return best // good enough — stop scanning
    }
    return best
  }
  return clips.map((clip) => {
    let changed = false
    const out: THREE.KeyframeTrack[] = []
    // group same-name tracks first: an FBX take routinely carries a mesh
    // object hold AND the real bone keys under one track name
    const groups = new Map<string, THREE.KeyframeTrack[]>()
    for (const t of clip.tracks) {
      const g = groups.get(t.name)
      if (g) g.push(t)
      else groups.set(t.name, [t])
    }
    for (const [name, group] of groups) {
      const dot = name.lastIndexOf('.')
      const prop = dot > 0 ? name.slice(dot) : ''
      if (dot < 1 || (prop !== '.position' && prop !== '.scale')) {
        out.push(...group) // rotations, morph targets, everything else — untouched
        continue
      }
      const rest = rests.get(normName(name.slice(0, dot)))
      // bones only: position/scale keys on mesh objects or Armature containers
      // would drag file layout into the pose
      if (!rest || !rest.isBone) { changed = true; continue }
      const restVec = prop === '.position' ? rest.pos : rest.scl
      const winner = group.find((t) => minRelDeviation(t, restVec) < 0.02)
      if (winner) out.push(winner)
      else changed = true // every candidate is foreign-space — drop the group
    }
    if (!changed) return clip
    return new THREE.AnimationClip(clip.name, clip.duration, out, clip.blendMode)
  })
}
