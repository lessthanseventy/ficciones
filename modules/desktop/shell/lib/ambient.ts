// The ambient set for the zen backdrop: each mode owns the dot canvas for a while. Lorenz
// (the attractor), Life (seeded at random), boids (a flock), rule 30 (falling rows). Every
// mode is a pure `step` over the CharGrid so the backdrop only paces and switches them.
import { CharGrid } from "./chargrid"

export type Mode = { name: string; colour: string; init(g: CharGrid): void; step(g: CharGrid): void; poke?(g: CharGrid, x: number, y: number): void }

const lorenz = (): Mode => {
  const t = [{ x: 0.1, y: 0, z: 0 }, { x: -0.2, y: 0.1, z: 20 }, { x: 8, y: 8, z: 27 }]
  return {
    name: "lorenz", colour: "amber",
    init(g) { g.clear() },
    poke(g, x, y) {
      // spawn near the attractor (clamped), keep the three originals, at most three extras
      const px = Math.max(-18, Math.min(18, (x / (g.cols * 2)) * 48 - 24))
      const pz = Math.max(5, Math.min(45, (1 - y / (g.rows * 4)) * 50 + 2))
      t.push({ x: px, y: px, z: pz })
      if (t.length > 6) t.splice(3, 1)
    },
    step(g) {
      g.decay(0.03)
      t.forEach((p, k) => {
        for (let i = 0; i < 22; i++) {
          const dt = 0.004
          const dx = 10 * (p.y - p.x), dy = p.x * (28 - p.z) - p.y, dz = p.x * p.y - (8 / 3) * p.z
          p.x += dx * dt; p.y += dy * dt; p.z += dz * dt
          g.plot((p.x + 24) / 48 * g.cols * 2, (1 - (p.z - 2) / 50) * g.rows * 4, k)
        }
        // a runaway (numerical or a wild spawn) comes home
        if (!Number.isFinite(p.x + p.y + p.z) || Math.abs(p.x) > 60 || Math.abs(p.y) > 80 || p.z > 100 || p.z < -20) { p.x = 0.1; p.y = 0; p.z = 20 }
      })
    },
  }
}

const life = (): Mode => {
  let w = 0, h = 0, a = new Uint8Array(0), b = new Uint8Array(0), age = new Uint8Array(0)
  return {
    name: "life", colour: "green",
    init(g) {
      w = g.cols * 2; h = g.rows * 4
      a = new Uint8Array(w * h); b = new Uint8Array(w * h)
      for (let i = 0; i < a.length; i++) a[i] = Math.random() < 0.18 ? 1 : 0
      age = new Uint8Array(w * h)
    },
    poke(g, px, py) {
      const gx = Math.floor(px), gy = Math.floor(py)
      for (const [dx, dy] of [[1, 0], [2, 1], [0, 2], [1, 2], [2, 2]]) a[((gy + dy) % h) * w + ((gx + dx) % w)] = 1
    },
    step(g) {
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        let n = 0
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dy) continue
          n += a[((y + dy + h) % h) * w + ((x + dx + w) % w)]
        }
        const i = y * w + x
        b[i] = a[i] ? (n === 2 || n === 3 ? 1 : 0) : n === 3 ? 1 : 0
      }
      ;[a, b] = [b, a]
      g.clear()
      for (let i = 0; i < a.length; i++) age[i] = a[i] ? Math.min(255, age[i] + 1) : 0
      // newborn green, settled amber, ancient cyan/lilac — hue by age band
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = y * w + x
        if (a[i]) g.plot(x, y, age[i] < 3 ? 1 : age[i] < 12 ? 0 : age[i] < 40 ? 3 : 4)
      }
    },
  }
}

const boids = (): Mode => {
  type B = { x: number; y: number; vx: number; vy: number; hue: number }
  let flock: B[] = []
  let W = 0, H = 0
  return {
    name: "boids", colour: "pink",
    init(g) {
      W = g.cols * 2; H = g.rows * 4
      // every boid keeps the colour it was born with — a colourful flock, not a shifting one
      flock = Array.from({ length: 70 }, (_, i) => ({ x: Math.random() * W, y: Math.random() * H, vx: Math.random() - 0.5, vy: Math.random() - 0.5, hue: i % 5 }))
      g.clear()
    },
    poke(g, px, py) {
      for (const b of flock) {
        const dx = b.x - px, dy = b.y - py, d = Math.hypot(dx, dy) || 1
        if (d < 120) { b.vx += (dx / d) * 3; b.vy += (dy / d) * 3 }
      }
    },
    step(g) {
      g.decay(0.12)
      for (const b of flock) {
        let cx = 0, cy = 0, ax = 0, ay = 0, sx = 0, sy = 0, n = 0
        for (const o of flock) {
          if (o === b) continue
          const dx = o.x - b.x, dy = o.y - b.y, d2 = dx * dx + dy * dy
          if (d2 < 900) { cx += o.x; cy += o.y; ax += o.vx; ay += o.vy; n++; if (d2 < 64) { sx -= dx; sy -= dy } }
        }
        if (n) {
          b.vx += ((cx / n - b.x) * 0.004) + ((ax / n - b.vx) * 0.05) + sx * 0.02
          b.vy += ((cy / n - b.y) * 0.004) + ((ay / n - b.vy) * 0.05) + sy * 0.02
        }
        const sp = Math.hypot(b.vx, b.vy) || 1
        const max = 1.6
        if (sp > max) { b.vx = b.vx / sp * max; b.vy = b.vy / sp * max }
        b.x = (b.x + b.vx + W) % W; b.y = (b.y + b.vy + H) % H
        g.plot(b.x, b.y, b.hue); g.plot(b.x - b.vx, b.y - b.vy, b.hue)
      }
    },
  }
}

const rule30 = (): Mode => {
  let row = new Uint8Array(0)
  let rows: Uint8Array[] = []
  return {
    name: "rule 30", colour: "cyan",
    init(g) {
      row = new Uint8Array(g.cols * 2); row[row.length >> 1] = 1
      rows = []
      g.clear()
    },
    poke(g, px) { row[Math.floor(px) % row.length] = 1 },
    step(g) {
      const w = row.length, next = new Uint8Array(w)
      for (let x = 0; x < w; x++) {
        const l = row[(x - 1 + w) % w], c = row[x], r = row[(x + 1) % w]
        next[x] = (l ^ (c | r)) & 1
      }
      row = next
      rows.push(row)
      const H = g.rows * 4
      if (rows.length > H) rows.shift()
      g.clear()
      rows.forEach((r, y) => { for (let x = 0; x < w; x++) if (r[x]) g.plot(x, y, Math.floor((x / w) * 5)) })
    },
  }
}

/** A fresh set per canvas, so two monitors never share a flock or a tracer. */
export const makeModes = (): Mode[] => [lorenz(), life(), boids(), rule30()]
