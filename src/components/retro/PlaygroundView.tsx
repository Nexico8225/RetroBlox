'use client'

import { useEffect, useRef } from 'react'
import * as THREE from 'three'
import { useRetro } from '@/lib/store'

/* ==================================================================
   PlaygroundView — the RetroBlox PLAYER SYSTEM, prototype v1.

   A real 3D playground: your blocky character (classic yellow head,
   blue torso, green legs) walks, jumps and climbs around a baseplate.
   WASD / arrows to move, SPACE to jump, drag the mouse to orbit the
   camera, wheel to zoom. Your username floats over your head just
   like the real thing.

   Prototype scope (v2 will add more): no multiplayer yet, no world
   saving, keyboard controls only. Everything runs client-side.
================================================================== */

type Obstacle = {
  minX: number; maxX: number
  minZ: number; maxZ: number
  topY: number
  height: number
}

const PLAYER_HALF_W = 0.45
const PLAYER_HEIGHT = 2.4
const SPEED = 4.2
const JUMP_V = 7.4
const GRAVITY = 20

export function PlaygroundView() {
  const mountRef = useRef<HTMLDivElement>(null)
  const user = useRetro((s) => s.user)
  const nameRef = useRef(user?.username || 'Guest')

  useEffect(() => { nameRef.current = user?.username || 'Guest' }, [user])

  useEffect(() => {
    const mount = mountRef.current
    if (!mount) return

    // ---------------- renderer / scene / camera ----------------
    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(mount.clientWidth, mount.clientHeight)
    renderer.shadowMap.enabled = true
    renderer.shadowMap.type = THREE.PCFSoftShadowMap
    mount.appendChild(renderer.domElement)
    renderer.domElement.style.touchAction = 'none'
    renderer.domElement.style.display = 'block'

    const scene = new THREE.Scene()
    scene.background = new THREE.Color(0x9fd7ff)
    scene.fog = new THREE.Fog(0x9fd7ff, 45, 110)

    const camera = new THREE.PerspectiveCamera(
      60, mount.clientWidth / mount.clientHeight, 0.1, 300
    )

    // ---------------- lights ----------------
    scene.add(new THREE.HemisphereLight(0xffffff, 0x88aa66, 0.9))
    const sun = new THREE.DirectionalLight(0xffffff, 1.15)
    sun.position.set(18, 30, 12)
    sun.castShadow = true
    sun.shadow.mapSize.set(2048, 2048)
    sun.shadow.camera.left = -40; sun.shadow.camera.right = 40
    sun.shadow.camera.top = 40; sun.shadow.camera.bottom = -40
    scene.add(sun)

    // ---------------- baseplate with stud-ish grid ----------------
    const gridCanvas = document.createElement('canvas')
    gridCanvas.width = gridCanvas.height = 256
    const g = gridCanvas.getContext('2d')!
    g.fillStyle = '#3f9b45'; g.fillRect(0, 0, 256, 256)
    g.strokeStyle = 'rgba(0,0,0,.18)'; g.lineWidth = 2
    for (let i = 0; i <= 256; i += 32) {
      g.beginPath(); g.moveTo(i, 0); g.lineTo(i, 256); g.stroke()
      g.beginPath(); g.moveTo(0, i); g.lineTo(256, i); g.stroke()
    }
    const gridTex = new THREE.CanvasTexture(gridCanvas)
    gridTex.wrapS = gridTex.wrapT = THREE.RepeatWrapping
    gridTex.repeat.set(24, 24)

    const BASE = 60
    const baseplate = new THREE.Mesh(
      new THREE.BoxGeometry(BASE, 1, BASE),
      new THREE.MeshLambertMaterial({ map: gridTex })
    )
    baseplate.position.y = -0.5
    baseplate.receiveShadow = true
    scene.add(baseplate)

    // ---------------- colorful climbable blocks ----------------
    const blockDefs: Array<{ x: number; z: number; w: number; h: number; d: number; c: number }> = [
      { x: -6, z: -4, w: 4, h: 1, d: 4, c: 0xe2231a },
      { x: -2, z: -8, w: 4, h: 2, d: 4, c: 0x00a2ff },
      { x: 4, z: -6, w: 3, h: 3, d: 3, c: 0xf5cd30 },
      { x: 8, z: 2, w: 5, h: 1.2, d: 5, c: 0x02b757 },
      { x: 0, z: 6, w: 6, h: 0.6, d: 6, c: 0xffffff },
      { x: -9, z: 6, w: 2.4, h: 4.2, d: 2.4, c: 0xff8c00 },
    ]
    const obstacles: Obstacle[] = []
    for (const b of blockDefs) {
      const m = new THREE.Mesh(
        new THREE.BoxGeometry(b.w, b.h, b.d),
        new THREE.MeshLambertMaterial({ color: b.c })
      )
      m.position.set(b.x, b.h / 2, b.z)
      m.castShadow = true; m.receiveShadow = true
      scene.add(m)
      obstacles.push({
        minX: b.x - b.w / 2, maxX: b.x + b.w / 2,
        minZ: b.z - b.d / 2, maxZ: b.z + b.d / 2,
        topY: b.h, height: b.h,
      })
    }

    // ---------------- the player (classic blocky avatar) ----------------
    const avatar = new THREE.Group()

    const mat = (c: number) => new THREE.MeshLambertMaterial({ color: c })
    const YELLOW = 0xf5cd30, BLUE = 0x0d69ac, GREEN = 0xa4bd47
    const box = (w: number, h: number, d: number, m: THREE.Material) => {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m)
      mesh.castShadow = true
      return mesh
    }

    // torso: 2 x 2 x 1 (roblox units scaled down), limbs 1 x 2 x 1
    // all pieces TOUCH: legs 0→0.9, torso 0.9→1.8, head 1.8→2.34
    const U = 0.45
    const torso = box(2 * U, 2 * U, U, mat(BLUE))
    torso.position.y = 1.35
    avatar.add(torso)

    const head = box(1.2 * U, 1.2 * U, 1.2 * U, mat(YELLOW))
    head.position.y = 2.07
    avatar.add(head)

    // the classic face — drawn on a canvas, stuck to the front of the head
    const faceCanvas = document.createElement('canvas')
    faceCanvas.width = faceCanvas.height = 128
    const f = faceCanvas.getContext('2d')!
    f.fillStyle = '#f5cd30'; f.fillRect(0, 0, 128, 128)
    f.fillStyle = '#1a1a1a'
    for (const ex of [40, 88]) {
      f.beginPath(); f.ellipse(ex, 50, 8, 13, 0, 0, Math.PI * 2); f.fill()
    }
    f.strokeStyle = '#1a1a1a'; f.lineWidth = 7; f.lineCap = 'round'
    f.beginPath(); f.arc(64, 62, 28, Math.PI * 0.18, Math.PI * 0.82); f.stroke()
    const faceTex = new THREE.CanvasTexture(faceCanvas)
    const faceMat = new THREE.MeshLambertMaterial({ map: faceTex })
    const facePlane = new THREE.Mesh(new THREE.PlaneGeometry(1.18 * U, 1.18 * U), faceMat)
    facePlane.position.set(0, 2.07, 0.271)
    avatar.add(facePlane)

    const armL = box(U, 2 * U, U, mat(YELLOW)); armL.position.set(-1.5 * U, 1.2, 0)
    const armR = box(U, 2 * U, U, mat(YELLOW)); armR.position.set(1.5 * U, 1.2, 0)
    const legL = box(U, 2 * U, U, mat(GREEN)); legL.position.set(-0.5 * U, 0.2, 0)
    const legR = box(U, 2 * U, U, mat(GREEN)); legR.position.set(0.5 * U, 0.2, 0)
    // pivot limbs from the top so they swing while walking
    const pivot = (mesh: THREE.Mesh, y: number) => {
      const p = new THREE.Group()
      mesh.position.y = -U
      p.add(mesh); p.position.y = y
      return p
    }
    const armLp = pivot(armL, 1.8), armRp = pivot(armR, 1.8)
    const legLp = pivot(legL, 0.9), legRp = pivot(legR, 0.9)
    avatar.add(armLp, armRp, legLp, legRp)
    scene.add(avatar)

    // ---------------- name tag ----------------
    const tagCanvas = document.createElement('canvas')
    const drawTag = (name: string) => {
      tagCanvas.width = 512; tagCanvas.height = 128
      const t = tagCanvas.getContext('2d')!
      t.clearRect(0, 0, 512, 128)
      t.font = 'bold 64px Verdana, sans-serif'
      t.textAlign = 'center'; t.textBaseline = 'middle'
      t.lineWidth = 10; t.strokeStyle = '#000'
      t.strokeText(name, 256, 64)
      t.fillStyle = '#fff'; t.fillText(name, 256, 64)
    }
    drawTag(nameRef.current)
    const tagTex = new THREE.CanvasTexture(tagCanvas)
    const tag = new THREE.Sprite(new THREE.SpriteMaterial({ map: tagTex, depthTest: false }))
    tag.scale.set(2.6, 0.65, 1)
    tag.position.y = 2.85
    avatar.add(tag)
    let lastName = nameRef.current

    // ---------------- input ----------------
    const keys = new Set<string>()
    const onKeyDown = (e: KeyboardEvent) => {
      keys.add(e.code)
      if (e.code === 'Space') e.preventDefault()
    }
    const onKeyUp = (e: KeyboardEvent) => keys.delete(e.code)
    window.addEventListener('keydown', onKeyDown)
    window.addEventListener('keyup', onKeyUp)

    let yaw = Math.PI, pitch = 0.42, dist = 9
    let dragging = false, lastX = 0, lastY = 0
    const dom = renderer.domElement
    const onDown = (e: PointerEvent) => {
      dragging = true; lastX = e.clientX; lastY = e.clientY
      dom.setPointerCapture(e.pointerId)
    }
    const onMove = (e: PointerEvent) => {
      if (!dragging) return
      yaw -= (e.clientX - lastX) * 0.006
      pitch = Math.max(0.05, Math.min(1.35, pitch + (e.clientY - lastY) * 0.005))
      lastX = e.clientX; lastY = e.clientY
    }
    const onUp = () => { dragging = false }
    const onWheel = (e: WheelEvent) => {
      dist = Math.max(4, Math.min(24, dist + e.deltaY * 0.01))
      e.preventDefault()
    }
    dom.addEventListener('pointerdown', onDown)
    dom.addEventListener('pointermove', onMove)
    dom.addEventListener('pointerup', onUp)
    dom.addEventListener('wheel', onWheel, { passive: false })

    // ---------------- player state ----------------
    const pos = new THREE.Vector3(0, 0, 10)
    const vel = new THREE.Vector3()
    let grounded = true
    let walkPhase = 0

    function collideAndMove(dx: number, dz: number, dy: number) {
      // horizontal, axis by axis, pushed out of block sides
      const tryAxis = (delta: number, axis: 'x' | 'z') => {
        const before = pos[axis]
        pos[axis] += delta
        const feet = pos.y, top = pos.y + PLAYER_HEIGHT
        for (const o of obstacles) {
          const overlapXZ =
            pos.x + PLAYER_HALF_W > o.minX && pos.x - PLAYER_HALF_W < o.maxX &&
            pos.z + PLAYER_HALF_W > o.minZ && pos.z - PLAYER_HALF_W < o.maxZ
          const overlapY = feet < o.topY - 0.25 && top > 0.05
          if (overlapXZ && overlapY && feet < o.topY) {
            pos[axis] = before // blocked — simple and sturdy
            break
          }
        }
        // keep inside the baseplate
        const lim = BASE / 2 - 1
        pos.x = Math.max(-lim, Math.min(lim, pos.x))
        pos.z = Math.max(-lim, Math.min(lim, pos.z))
      }
      tryAxis(dx, 'x')
      tryAxis(dz, 'z')

      // vertical: land on ground or block tops
      const prevFeet = pos.y
      pos.y += dy
      let landed = false
      const groundTop = 0
      const surfaces = [{ minX: -BASE / 2, maxX: BASE / 2, minZ: -BASE / 2, maxZ: BASE / 2, topY: groundTop }, ...obstacles]
      if (dy <= 0) {
        for (const o of surfaces) {
          const within =
            pos.x + PLAYER_HALF_W > o.minX && pos.x - PLAYER_HALF_W < o.maxX &&
            pos.z + PLAYER_HALF_W > o.minZ && pos.z - PLAYER_HALF_W < o.maxZ
          if (within && prevFeet >= o.topY - 0.02 && pos.y <= o.topY) {
            pos.y = o.topY; vel.y = 0; landed = true
            break
          }
        }
      }
      grounded = landed
    }

    // ---------------- main loop ----------------
    const clock = new THREE.Clock()
    let raf = 0
    const camTarget = new THREE.Vector3()

    function tick() {
      raf = requestAnimationFrame(tick)
      const dt = Math.min(clock.getDelta(), 0.05)

      // name tag follows renames instantly
      if (nameRef.current !== lastName) {
        lastName = nameRef.current
        drawTag(lastName); tagTex.needsUpdate = true
      }

      // move relative to camera yaw
      let ix = 0, iz = 0
      if (keys.has('KeyW') || keys.has('ArrowUp')) iz -= 1
      if (keys.has('KeyS') || keys.has('ArrowDown')) iz += 1
      if (keys.has('KeyA') || keys.has('ArrowLeft')) ix -= 1
      if (keys.has('KeyD') || keys.has('ArrowRight')) ix += 1
      const moving = ix !== 0 || iz !== 0
      if (moving) {
        const len = Math.hypot(ix, iz); ix /= len; iz /= len
        const sin = Math.sin(yaw), cos = Math.cos(yaw)
        const dx = ix * cos + iz * sin
        const dz = -ix * sin + iz * cos
        collideAndMove(dx * SPEED * dt, dz * SPEED * dt, 0)
        // face movement direction
        avatar.rotation.y = Math.atan2(dx, dz)
      }
      if (keys.has('Space') && grounded) {
        vel.y = JUMP_V; grounded = false
      }
      vel.y -= GRAVITY * dt
      collideAndMove(0, 0, vel.y * dt)
      if (pos.y < 0) { pos.y = 0; vel.y = 0; grounded = true }

      // walk animation
      if (moving && grounded) {
        walkPhase += dt * 9
        const swing = Math.sin(walkPhase) * 0.7
        armLp.rotation.x = swing; armRp.rotation.x = -swing
        legLp.rotation.x = -swing; legRp.rotation.x = swing
      } else if (!grounded) {
        armLp.rotation.x = -2.6; armRp.rotation.x = -2.6 // arms up mid-air!
        legLp.rotation.x = 0.35; legRp.rotation.x = -0.35
      } else {
        for (const p of [armLp, armRp, legLp, legRp]) p.rotation.x *= 0.8
      }

      avatar.position.copy(pos)

      // camera follow
      const cx = pos.x + dist * Math.sin(yaw) * Math.cos(pitch)
      const cz = pos.z + dist * Math.cos(yaw) * Math.cos(pitch)
      const cy = pos.y + dist * Math.sin(pitch) + 1.4
      camera.position.lerp(new THREE.Vector3(cx, cy, cz), 0.22)
      camTarget.lerp(new THREE.Vector3(pos.x, pos.y + 1.5, pos.z), 0.35)
      camera.lookAt(camTarget)
      sun.position.set(pos.x + 18, 30, pos.z + 12)
      sun.target.position.copy(pos)
      sun.target.updateMatrixWorld()

      renderer.render(scene, camera)
    }
    tick()

    // ---------------- resize + cleanup ----------------
    const onResize = () => {
      if (!mount) return
      camera.aspect = mount.clientWidth / mount.clientHeight
      camera.updateProjectionMatrix()
      renderer.setSize(mount.clientWidth, mount.clientHeight)
    }
    window.addEventListener('resize', onResize)

    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('keyup', onKeyUp)
      window.removeEventListener('resize', onResize)
      dom.removeEventListener('pointerdown', onDown)
      dom.removeEventListener('pointermove', onMove)
      dom.removeEventListener('pointerup', onUp)
      dom.removeEventListener('wheel', onWheel)
      scene.traverse((o) => {
        const mesh = o as THREE.Mesh
        if (mesh.geometry) mesh.geometry.dispose()
        const m = mesh.material as THREE.Material | THREE.Material[] | undefined
        if (Array.isArray(m)) m.forEach((x) => x.dispose())
        else if (m) m.dispose()
      })
      tagTex.dispose(); faceTex.dispose(); gridTex.dispose()
      renderer.dispose()
      if (dom.parentElement === mount) mount.removeChild(dom)
    }
  }, [])

  return (
    <div>
      <div
        ref={mountRef}
        style={{
          width: '100%', height: '68vh', minHeight: 380,
          border: '2px solid #b6c0cb', borderRadius: 6,
          overflow: 'hidden', background: '#9fd7ff', position: 'relative',
        }}
      />
      <div
        style={{
          marginTop: 8, fontSize: 12, color: '#5c6a78', lineHeight: 1.6,
        }}
      >
        <b>How to play:</b> WASD or arrow keys to walk &middot; SPACE to jump &middot; drag the mouse to look around &middot; scroll to zoom.
        Climb the blocks! More worlds, multiplayer and items are coming in v2.
      </div>
    </div>
  )
}
