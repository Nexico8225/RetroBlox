import * as THREE from 'three'

/* ------------------------------------------------------------------
   COLORWORLD — built-in maps.
   Each map is a plain THREE.Group of meshes. The game turns every
   part white (unshaded) with a black outline, so the ORIGINAL colors
   here are just for the menu preview snapshot — the paint world is
   always born completely white.
------------------------------------------------------------------ */

export interface BuiltinMap {
  id: string
  name: string
  blurb: string
  build: () => THREE.Group
}

/* tiny builders — everything sits on y = 0 */
function box(w: number, h: number, d: number, x: number, y: number, z: number, color: number, ry = 0) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), new THREE.MeshLambertMaterial({ color }))
  m.position.set(x, y + h / 2, z)
  m.rotation.y = ry
  return m
}
function cyl(rt: number, rb: number, h: number, x: number, y: number, z: number, color: number, seg = 12) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), new THREE.MeshLambertMaterial({ color }))
  m.position.set(x, y + h / 2, z)
  return m
}
function cone(r: number, h: number, x: number, y: number, z: number, color: number, seg = 12) {
  const m = new THREE.Mesh(new THREE.ConeGeometry(r, h, seg), new THREE.MeshLambertMaterial({ color }))
  m.position.set(x, y + h / 2, z)
  return m
}
function sph(r: number, x: number, y: number, z: number, color: number, seg = 12) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, seg, Math.max(6, Math.round(seg * 0.75))), new THREE.MeshLambertMaterial({ color }))
  m.position.set(x, y, z)
  return m
}
function tree(x: number, z: number, s = 1) {
  const g = new THREE.Group()
  g.add(cyl(0.14 * s, 0.18 * s, 1.1 * s, x, 0, z, 0x7a4a21))
  g.add(cone(0.85 * s, 1.3 * s, x, 0.9 * s, z, 0x2e9e4f, 10))
  g.add(cone(0.65 * s, 1.1 * s, x, 1.7 * s, z, 0x37b45c, 10))
  return g
}
function house(x: number, z: number, ry: number, wall: number, roof: number) {
  const g = new THREE.Group()
  g.add(box(3, 2.2, 2.6, 0, 0, 0, wall))
  g.add(box(0.7, 1.4, 0.12, -0.7, 0, 1.31, 0x5a3a1e)) // door
  g.add(box(0.6, 0.6, 0.12, 0.8, 1.0, 1.31, 0x9fd8ef)) // window
  const roofMesh = new THREE.Mesh(new THREE.ConeGeometry(2.35, 1.4, 4), new THREE.MeshLambertMaterial({ color: roof }))
  roofMesh.position.y = 2.2 + 0.7
  roofMesh.rotation.y = Math.PI / 4
  g.add(roofMesh)
  g.add(box(0.35, 1.1, 0.35, 1.05, 2.9, -0.7, 0x8a8f96)) // chimney
  g.position.set(x, 0, z)
  g.rotation.y = ry
  return g
}
function lamppost(x: number, z: number) {
  const g = new THREE.Group()
  g.add(cyl(0.08, 0.1, 2.6, x, 0, z, 0x3d4650, 8))
  g.add(sph(0.22, x, 2.75, z, 0xffe38a, 8))
  return g
}
function fence(x: number, z: number, len: number, ry = 0) {
  const g = new THREE.Group()
  const n = Math.max(2, Math.round(len / 0.9))
  for (let i = 0; i < n; i++) {
    const t = -len / 2 + (len / (n - 1)) * i
    g.add(box(0.12, 0.85, 0.12, t, 0, 0, 0xb98a4a))
  }
  g.add(box(len, 0.1, 0.06, 0, 0.55, 0, 0xc79a58))
  g.add(box(len, 0.1, 0.06, 0, 0.28, 0, 0xc79a58))
  g.position.set(x, 0, z)
  g.rotation.y = ry
  return g
}

/* ---------------- the three launch maps ---------------- */

function buildVillage(): THREE.Group {
  const g = new THREE.Group()
  g.add(box(16, 0.4, 16, 0, -0.4, 0, 0x59b65c)) // grass slab
  g.add(box(1.6, 0.08, 13, 0, 0.0, 0, 0xc9c1ad)) // path
  g.add(house(-3.6, -3.2, 0.35, 0xf2d8a7, 0xc94f3d))
  g.add(house(3.8, -2.6, -0.5, 0xa9cbe8, 0x4f6fc9))
  g.add(house(-0.4, 3.8, 0.05, 0xe8a9b8, 0x8a4f6f))
  g.add(tree(-6.2, 1.8, 1.15))
  g.add(tree(6.1, 2.4, 0.95))
  g.add(tree(5.6, -5.4, 1.3))
  g.add(tree(-5.8, -5.6, 0.85))
  // the well
  const well = new THREE.Group()
  well.add(cyl(0.7, 0.75, 0.8, 0, 0, 0, 0x9aa0a6, 14))
  well.add(box(0.14, 1.5, 0.14, -0.55, 0.8, 0, 0x7a4a21))
  well.add(box(0.14, 1.5, 0.14, 0.55, 0.8, 0, 0x7a4a21))
  const wrm = new THREE.Mesh(new THREE.ConeGeometry(0.95, 0.6, 4), new THREE.MeshLambertMaterial({ color: 0xc94f3d }))
  wrm.position.y = 2.45
  wrm.rotation.y = Math.PI / 4
  well.add(wrm)
  well.position.set(1.6, 0, 0.2)
  g.add(well)
  g.add(fence(0, -6.6, 12))
  g.add(lamppost(-1.9, -1.2))
  g.add(lamppost(2.4, 1.6))
  return g
}

function buildRobotPark(): THREE.Group {
  const g = new THREE.Group()
  g.add(box(16, 0.4, 16, 0, -0.4, 0, 0x74c06a))
  // THE ROBOT — the star of the park
  const r = new THREE.Group()
  r.add(box(1.1, 1.0, 0.8, -0.75, 0, 0, 0x8e9aa6)) // legs
  r.add(box(1.1, 1.0, 0.8, 0.75, 0, 0, 0x8e9aa6))
  r.add(box(0.9, 0.35, 0.9, -0.75, 1.0, 0, 0x5f6b76)) // feet
  r.add(box(0.9, 0.35, 0.9, 0.75, 1.0, 0, 0x5f6b76))
  r.add(box(2.6, 2.2, 1.4, 0, 1.35, 0, 0xb8c4ce)) // torso
  r.add(box(0.6, 1.9, 0.7, -1.75, 1.5, 0, 0x8e9aa6)) // arms
  r.add(box(0.6, 1.9, 0.7, 1.75, 1.5, 0, 0x8e9aa6))
  r.add(sph(0.32, -1.75, 1.42, 0, 0x39424b, 8))
  r.add(sph(0.32, 1.75, 1.42, 0, 0x39424b, 8))
  r.add(box(1.5, 1.1, 1.2, 0, 3.55, 0, 0xd7dee4)) // head
  r.add(sph(0.16, -0.35, 3.85, 0.61, 0x22303c, 8)) // eyes
  r.add(sph(0.16, 0.35, 3.85, 0.61, 0x22303c, 8))
  r.add(cyl(0.05, 0.05, 0.7, 0, 4.65, 0, 0x5f6b76, 6)) // antenna
  r.add(sph(0.14, 0, 5.4, 0, 0xe2231a, 8))
  r.position.set(-2.2, 0, -1.5)
  r.rotation.y = 0.5
  g.add(r)
  // playground
  const slide = new THREE.Group()
  slide.add(box(2.2, 0.15, 0.7, 0, 1.5, 0, 0xf2c53d))
  slide.add(box(0.16, 1.5, 0.16, -0.95, 0, 0, 0x8e9aa6))
  slide.add(box(0.16, 1.5, 0.16, 0.95, 0, 0, 0x8e9aa6))
  const ramp = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.12, 0.7), new THREE.MeshLambertMaterial({ color: 0x4f9ee8 }))
  ramp.position.set(1.1, 0.75, 0)
  ramp.rotation.z = 0.62
  slide.add(ramp)
  slide.add(box(0.16, 1.55, 0.16, 2.25, 0, 0, 0x8e9aa6))
  slide.position.set(2.8, 0, 1.6)
  slide.rotation.y = -0.4
  g.add(slide)
  // benches + seesaw + lamps
  g.add(box(1.8, 0.12, 0.5, 0.4, 0.42, 4.6, 0xb98a4a))
  g.add(box(1.8, 0.5, 0.1, 0.4, 0.5, 4.9, 0xb98a4a))
  g.add(box(0.15, 0.42, 0.45, -0.3, 0, 4.6, 0x5f6b76))
  g.add(box(0.15, 0.42, 0.45, 1.1, 0, 4.6, 0x5f6b76))
  const see = new THREE.Group()
  see.add(box(0.18, 0.5, 0.18, 0, 0, 0, 0x5f6b76))
  const plank = box(2.6, 0.1, 0.4, 0, 0.5, 0, 0xe2884f)
  plank.rotation.z = 0.18
  see.add(plank)
  see.position.set(-4.4, 0, 3.4)
  g.add(see)
  g.add(tree(5.9, -4.9, 1.2))
  g.add(tree(-6.1, -4.2, 1.0))
  g.add(lamppost(3.2, -3.4))
  g.add(lamppost(-2.6, 2.2))
  g.add(fence(0, 6.6, 13))
  return g
}

function buildSpaceBase(): THREE.Group {
  const g = new THREE.Group()
  g.add(box(16, 0.4, 16, 0, -0.4, 0, 0x8d93a1)) // moon dust pad
  // rocket
  const rk = new THREE.Group()
  rk.add(cyl(0.85, 1.0, 3.4, 0, 0, 0, 0xe8eef4, 14))
  rk.add(cone(0.85, 1.1, 0, 3.4, 0, 0xe2231a, 14))
  for (const a of [0, (Math.PI * 2) / 3, (Math.PI * 4) / 3]) {
    const fin = new THREE.Mesh(new THREE.BoxGeometry(0.12, 1.1, 0.8), new THREE.MeshLambertMaterial({ color: 0xe2231a }))
    fin.position.set(Math.sin(a) * 0.95, 0.55, Math.cos(a) * 0.95)
    fin.rotation.y = a
    rk.add(fin)
  }
  rk.add(cyl(0.55, 0.75, 0.5, 0, -0.05, 0, 0x39424b, 14))
  rk.position.set(-3.4, 0, -2.8)
  rk.rotation.y = 0.4
  g.add(rk)
  // habitat domes
  const dome1 = new THREE.Mesh(new THREE.SphereGeometry(1.5, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0x9fd8ef }))
  dome1.position.set(2.8, 0, -2.2)
  g.add(dome1)
  g.add(cyl(1.5, 1.55, 0.35, 2.8, 0, -2.2, 0xb8c4ce, 14))
  const dome2 = new THREE.Mesh(new THREE.SphereGeometry(1.0, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0x9fd8ef }))
  dome2.position.set(5.2, 0, 0.6)
  g.add(dome2)
  g.add(cyl(1.0, 1.05, 0.3, 5.2, 0, 0.6, 0xb8c4ce, 14))
  // dish antenna
  const dish = new THREE.Group()
  const bowl = new THREE.Mesh(new THREE.SphereGeometry(0.9, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2.6), new THREE.MeshLambertMaterial({ color: 0xd7dee4, side: THREE.DoubleSide }))
  bowl.rotation.x = Math.PI / 1.5
  bowl.position.y = 2.3
  dish.add(bowl)
  dish.add(cyl(0.09, 0.12, 2.1, 0, 0, 0, 0x8e9aa6, 8))
  dish.add(box(0.5, 0.08, 0.5, 0, 0, 0, 0x5f6b76))
  dish.position.set(-5.6, 0, 1.6)
  dish.rotation.y = 0.9
  g.add(dish)
  // crates + flag + rocks
  g.add(box(0.7, 0.7, 0.7, 0.6, 0, 2.9, 0xf2c53d))
  g.add(box(0.7, 0.7, 0.7, 1.35, 0, 2.85, 0xe2884f))
  g.add(box(0.7, 0.7, 0.7, 0.95, 0.7, 2.88, 0x4f9ee8))
  const flag = new THREE.Group()
  flag.add(cyl(0.05, 0.05, 2.2, 0, 0, 0, 0xb8c4ce, 6))
  flag.add(box(0.9, 0.55, 0.05, 0.48, 1.65, 0, 0x00a2e8))
  flag.position.set(-0.9, 0, 3.9)
  g.add(flag)
  g.add(sph(0.55, 5.8, 0.3, 4.6, 0x8d93a1, 8))
  g.add(sph(0.4, -5.9, 0.22, -4.9, 0x7d838f, 8))
  g.add(sph(0.3, 4.2, 0.16, 5.4, 0x9aa0ac, 8))
  return g
}

export const BUILTIN_MAPS: BuiltinMap[] = [
  { id: 'village', name: 'Sunny Village', blurb: 'Houses, trees and a well', build: buildVillage },
  { id: 'robotpark', name: 'Robot Park', blurb: 'A giant robot + playground', build: buildRobotPark },
  { id: 'spacebase', name: 'Space Base', blurb: 'Rockets, domes and moon dust', build: buildSpaceBase },
]

/* ---------------- fallback card placeholder (SVG data URL) ---------------- */
export function placeholderImage(name: string): string {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
  const hues = [h % 360, (h * 7 + 40) % 360, (h * 13 + 90) % 360]
  const cols = hues.map((hh) => `hsl(${hh} 70% 62%)`)
  const initial = (name.trim()[0] || '?').toUpperCase()
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="200">` +
    `<rect width="320" height="200" fill="#eef3f7"/>` +
    `<rect x="18" y="96" width="70" height="86" fill="${cols[0]}"/>` +
    `<rect x="100" y="56" width="70" height="126" fill="${cols[1]}"/>` +
    `<rect x="182" y="120" width="70" height="62" fill="${cols[2]}"/>` +
    `<rect x="264" y="80" width="38" height="102" fill="${cols[0]}"/>` +
    `<rect x="0" y="164" width="320" height="36" fill="#cfd9e2"/>` +
    `<circle cx="160" cy="70" r="34" fill="#ffffff" stroke="#1c3a52" stroke-width="4"/>` +
    `<text x="160" y="84" font-family="Verdana" font-size="36" font-weight="bold" fill="#1c3a52" text-anchor="middle">${initial}</text>` +
    `</svg>`
  return 'data:image/svg+xml;utf8,' + encodeURIComponent(svg)
}
