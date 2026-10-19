// The ambient set for the zen backdrop: each mode owns the dot canvas for a while. Lorenz
// (the attractor), Life (seeded at random), boids (a flock), rule 30 (falling rows), and the
// terminal classics: pipes, bonsai, a maze, a starfield, a flow field, Langton's ants, rain.
// Every mode is a pure `step` over the CharGrid so the backdrop only paces and switches them.
// Densities sit ~10% under what first shipped: ambient, not wallpaper (Andrew, 2026-09-11).
import { CharGrid } from "./chargrid"
import { Babel, ensureBooks } from "./babel"

/** `text` supersedes the dot grid: the mode paints whole rows of markup itself (the Library).
 * `smooth` steps at FAST_HZ, each step `dt` of a SLOW_HZ one; the rest step at SLOW_HZ. */
export type Mode = { name: string; colour: string; smooth?: true; init(g: CharGrid): void; step(g: CharGrid): void; poke?(g: CharGrid, x: number, y: number): void; text?(): string[] }

export const SLOW_HZ = 5
export let FAST_HZ = 15
let dt = SLOW_HZ / FAST_HZ
/** FAST_HZ must be a whole multiple of SLOW_HZ: the slow modes skip FAST_HZ / SLOW_HZ ticks */
export function setFastHz(hz: number) {
  FAST_HZ = Math.max(SLOW_HZ, Math.round(hz / SLOW_HZ) * SLOW_HZ)
  dt = SLOW_HZ / FAST_HZ
}
/** a SLOW_HZ step's decay as one smooth step's, so a trail fades as fast at either rate */
const fade = (p: number) => 1 - (1 - p) ** dt

const lorenz = (): Mode => {
  const t = [{ x: 0.1, y: 0, z: 0 }, { x: -0.2, y: 0.1, z: 20 }, { x: 8, y: 8, z: 27 }]
  return {
    name: "lorenz", colour: "amber", smooth: true,
    init(g) { g.clear() },
    poke(g, x, y) {
      // spawn near the attractor (clamped), keep the three originals, at most three extras
      const px = Math.max(-18, Math.min(18, (x / (g.cols * 2)) * 48 - 24))
      const pz = Math.max(5, Math.min(45, (1 - y / (g.rows * 4)) * 50 + 2))
      t.push({ x: px, y: px, z: pz })
      if (t.length > 6) t.splice(3, 1)
    },
    step(g) {
      g.decay(fade(0.034))
      // 22 integrations of 0.004 a slow step: as many plots a second, spread over the smooth steps
      const n = Math.round(22 * dt), h = (0.004 * 22 * dt) / n
      t.forEach((p, k) => {
        for (let i = 0; i < n; i++) {
          const dx = 10 * (p.y - p.x), dy = p.x * (28 - p.z) - p.y, dz = p.x * p.y - (8 / 3) * p.z
          p.x += dx * h; p.y += dy * h; p.z += dz * h
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
      for (let i = 0; i < a.length; i++) a[i] = Math.random() < 0.16 ? 1 : 0
      age = new Uint8Array(w * h)
    },
    poke(_g, px, py) {
      const gx = Math.floor(px), gy = Math.floor(py)
      for (const [dx, dy] of [[1, 0], [2, 1], [0, 2], [1, 2], [2, 2]]) a[((gy + dy) % h) * w + ((gx + dx) % w)] = 1
    },
    step(g) {
      // the torus wrap resolved once per row and column, not per neighbour: this loop is 107k
      // cells × 8 a step on each monitor, and the per-lookup modulo made life the dearest mode
      for (let y = 0; y < h; y++) {
        const up = ((y - 1 + h) % h) * w, mid = y * w, dn = ((y + 1) % h) * w
        for (let x = 0; x < w; x++) {
          const l = x === 0 ? w - 1 : x - 1, r = x === w - 1 ? 0 : x + 1
          const n = a[up + l] + a[up + x] + a[up + r] + a[mid + l] + a[mid + r] + a[dn + l] + a[dn + x] + a[dn + r]
          b[mid + x] = n === 3 || (n === 2 && a[mid + x]) ? 1 : 0
        }
      }
      ;[a, b] = [b, a]
      g.clear()
      // newborn green, settled amber, ancient cyan/lilac — hue by age band
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = y * w + x
        if (!a[i]) { age[i] = 0; continue }
        const t = age[i] = Math.min(255, age[i] + 1)
        g.plot(x, y, t < 3 ? 1 : t < 12 ? 0 : t < 40 ? 3 : 4)
      }
    },
  }
}

const boids = (): Mode => {
  type B = { x: number; y: number; vx: number; vy: number; hue: number }
  let flock: B[] = []
  let W = 0, H = 0
  return {
    name: "boids", colour: "pink", smooth: true,
    init(g) {
      W = g.cols * 2; H = g.rows * 4
      // every boid keeps the colour it was born with — a colourful flock, not a shifting one
      flock = Array.from({ length: 63 }, (_, i) => ({ x: Math.random() * W, y: Math.random() * H, vx: Math.random() - 0.5, vy: Math.random() - 0.5, hue: i % 5 }))
      g.clear()
    },
    poke(_g, px, py) {
      for (const b of flock) {
        const dx = b.x - px, dy = b.y - py, d = Math.hypot(dx, dy) || 1
        if (d < 120) { b.vx += (dx / d) * 3; b.vy += (dy / d) * 3 }
      }
    },
    step(g) {
      g.decay(fade(0.12))
      for (const b of flock) {
        let cx = 0, cy = 0, ax = 0, ay = 0, sx = 0, sy = 0, n = 0
        for (const o of flock) {
          if (o === b) continue
          const dx = o.x - b.x, dy = o.y - b.y, d2 = dx * dx + dy * dy
          if (d2 < 900) { cx += o.x; cy += o.y; ax += o.vx; ay += o.vy; n++; if (d2 < 64) { sx -= dx; sy -= dy } }
        }
        if (n) {
          b.vx += (((cx / n - b.x) * 0.004) + ((ax / n - b.vx) * 0.05) + sx * 0.02) * dt
          b.vy += (((cy / n - b.y) * 0.004) + ((ay / n - b.vy) * 0.05) + sy * 0.02) * dt
        }
        const sp = Math.hypot(b.vx, b.vy) || 1
        const max = 1.6
        if (sp > max) { b.vx = b.vx / sp * max; b.vy = b.vy / sp * max }
        b.x = (b.x + b.vx * dt + W) % W; b.y = (b.y + b.vy * dt + H) % H
        g.plot(b.x, b.y, b.hue); g.plot(b.x - b.vx, b.y - b.vy, b.hue)
      }
    },
  }
}

// Every row it has ever made, faded by age: the newest dense, thinning to nothing at the top
// (keeping them all at full density, in five hue bands, covered the screen — 2026-09-11).
const rule30 = (): Mode => {
  let row = new Uint8Array(0)
  let rows: Uint8Array[] = []
  let masks: Float32Array[] = [] // a fixed draw per dot, so a row thins without flickering
  return {
    name: "rule 30", colour: "cyan",
    init(g) {
      row = new Uint8Array(g.cols * 2); row[row.length >> 1] = 1
      rows = []; masks = []
      g.clear()
    },
    poke(_g, px) { row[Math.floor(px) % row.length] = 1 },
    step(g) {
      const w = row.length, next = new Uint8Array(w)
      for (let x = 0; x < w; x++) {
        const l = row[(x - 1 + w) % w], c = row[x], r = row[(x + 1) % w]
        next[x] = (l ^ (c | r)) & 1
      }
      row = next
      rows.push(row); masks.push(Float32Array.from({ length: w }, Math.random))
      const H = g.rows * 4
      if (rows.length > H) { rows.shift(); masks.shift() }
      g.clear()
      const n = rows.length
      rows.forEach((r, y) => {
        const keep = 0.9 * (1 - (n - 1 - y) / H) // newest row 90%, the screen's height back: none
        const m = masks[y], hue = n - 1 - y < H / 3 ? 3 : 4
        for (let x = 0; x < w; x++) if (r[x] && m[x] < keep) g.plot(x, y, hue)
      })
    },
  }
}

// pipes.sh: a few pipes run on a 4-dot lattice, turning at right angles; when the screen has
// had its fill they fade and start over
const pipes = (): Mode => {
  type P = { x: number; y: number; dx: number; dy: number; hue: number }
  let ps: P[] = [], W = 0, H = 0, laid = 0, fading = 0
  const edge = (hue: number): P => {
    const d = Math.random() < 0.5 ? 1 : -1
    return Math.random() < 0.5
      ? { x: d > 0 ? 0 : W - 1, y: Math.floor((Math.random() * H) / 4) * 4, dx: d, dy: 0, hue }
      : { x: Math.floor((Math.random() * W) / 4) * 4, y: d > 0 ? 0 : H - 1, dx: 0, dy: d, hue }
  }
  const start = (g: CharGrid) => { W = g.cols * 2; H = g.rows * 4; laid = 0; fading = 0; ps = [0, 1, 3].map(edge); g.clear() }
  return {
    name: "pipes", colour: "green",
    init: start,
    poke(_g, x, y) { ps.push({ x: Math.round(x / 4) * 4, y: Math.round(y / 4) * 4, dx: 1, dy: 0, hue: 2 }); if (ps.length > 5) ps.splice(3, 1) },
    step(g) {
      if (fading) { g.decay(0.08); if (++fading > 60) start(g); return }
      for (const p of ps) for (let i = 0; i < 8; i++) {
        // turns only on the lattice, so runs lie parallel like the terminal's
        if (p.x % 4 === 0 && p.y % 4 === 0 && Math.random() < 0.12) {
          const [dx, dy] = Math.random() < 0.5 ? [-p.dy, p.dx] : [p.dy, -p.dx]
          p.dx = dx; p.dy = dy
        }
        p.x += p.dx; p.y += p.dy
        if (p.x < 0 || p.y < 0 || p.x >= W || p.y >= H) Object.assign(p, edge(p.hue))
        g.plot(p.x, p.y, p.hue)
      }
      laid += ps.length * 8
      if (laid > 14000) fading = 1
    },
  }
}

// cbonsai: a tree grows out of a pot, branch by branch, leaves at the tips; it stands a while,
// fades, and another grows somewhere else
const bonsai = (): Mode => {
  type B = { x: number; y: number; a: number; life: number; depth: number }
  const UP = -Math.PI / 2
  let br: B[] = [], W = 0, H = 0, hold = 0, fading = 0, trunk = 0
  const leaves = (g: CharGrid, b: B, n: number) => {
    for (let i = 0; i < n; i++) {
      const r = Math.random() * 6, t = Math.random() * Math.PI * 2
      g.plot(b.x + Math.cos(t) * r * 1.4, b.y + Math.sin(t) * r, Math.random() < 0.15 ? 2 : 1)
    }
  }
  const start = (g: CharGrid) => {
    W = g.cols * 2; H = g.rows * 4; hold = 0; fading = 0
    g.clear()
    const x0 = Math.round(W * (0.25 + Math.random() * 0.5)), top = H - 16
    // the pot: a rim, two slanted sides, a foot
    for (let x = -30; x <= 30; x++) g.plot(x0 + x, top, 4)
    for (let r = 1; r <= 11; r++) { g.plot(x0 - 30 + r, top + r, 4); g.plot(x0 + 30 - r, top + r, 4) }
    for (let x = -19; x <= 19; x++) g.plot(x0 + x, top + 11, 4)
    // lengths from the screen's height, each generation ~72% of the last: the crown fits above the pot
    trunk = H * (0.22 + Math.random() * 0.08)
    br = [{ x: x0, y: top - 1, a: UP, life: trunk, depth: 0 }]
  }
  return {
    name: "bonsai", colour: "green",
    init: start,
    step(g) {
      if (fading) { g.decay(0.06); if (++fading > 70) start(g); return }
      if (!br.length) { if (++hold > 150) fading = 1; return }
      const next: B[] = []
      for (const b of br) {
        for (let i = 0; i < 2; i++) {
          // wander; the trunk is pulled upright, the branches only gently
          b.a += (Math.random() - 0.5) * 0.3 + (UP - b.a) * (b.depth ? 0.015 : 0.05)
          b.x += Math.cos(b.a); b.y += Math.sin(b.a) * 0.9
          const th = Math.max(0, 2 - b.depth), nx = -Math.sin(b.a), ny = Math.cos(b.a)
          for (let k = -th; k <= th; k++) g.plot(b.x + nx * k, b.y + ny * k, 0)
          b.life--
        }
        if (b.x < 0 || b.x >= W || b.y < 0) continue
        if (b.life > 0) { next.push(b); continue }
        if (b.depth >= 2) leaves(g, b, b.depth >= 4 ? 24 : 10)
        if (b.depth >= 5) continue
        const sides = b.depth === 0 ? [-1, 0, 1] : [-1, 1]
        for (const side of sides) next.push({ x: b.x, y: b.y, a: b.a + side * (0.35 + Math.random() * 0.55), life: trunk * 0.55 * 0.72 ** b.depth * (0.7 + Math.random() * 0.6), depth: b.depth + 1 })
      }
      br = next
    },
  }
}

// a maze carved by a backtracking walk, then solved: corridors in lilac, the way through in
// pink, drawn as it is found; it stands, fades, and another is carved
const maze = (): Mode => {
  const C = 8 // dots a cell
  let cw = 0, ch = 0, seen = new Uint8Array(0), par = new Int32Array(0), stack: number[] = []
  let path: number[] = [], k = 0, hold = 0, fading = 0
  const seg = (g: CharGrid, a: number, b: number, hue: number) => {
    const ax = (a % cw) * C + C / 2, ay = Math.floor(a / cw) * C + C / 2
    const bx = (b % cw) * C + C / 2, by = Math.floor(b / cw) * C + C / 2
    for (let s = 0; s <= C; s++) g.plot(ax + ((bx - ax) * s) / C, ay + ((by - ay) * s) / C, hue)
  }
  const start = (g: CharGrid) => {
    cw = Math.floor((g.cols * 2) / C); ch = Math.floor((g.rows * 4) / C)
    seen = new Uint8Array(cw * ch); par = new Int32Array(cw * ch).fill(-1)
    stack = [0]; seen[0] = 1; path = []; k = 0; hold = 0; fading = 0
    g.clear()
  }
  return {
    name: "maze", colour: "lilac",
    init: start,
    step(g) {
      if (fading) { g.decay(0.07); if (++fading > 60) start(g); return }
      if (stack.length) {
        for (let n = 0; n < 30 && stack.length; n++) {
          const c = stack[stack.length - 1], x = c % cw, y = Math.floor(c / cw)
          const nb: number[] = []
          if (x > 0 && !seen[c - 1]) nb.push(c - 1)
          if (x < cw - 1 && !seen[c + 1]) nb.push(c + 1)
          if (y > 0 && !seen[c - cw]) nb.push(c - cw)
          if (y < ch - 1 && !seen[c + cw]) nb.push(c + cw)
          if (!nb.length) { stack.pop(); continue }
          const d = nb[Math.floor(Math.random() * nb.length)]
          seen[d] = 1; par[d] = c; stack.push(d); seg(g, c, d, 4)
        }
        // carved: the carving is a tree from the first cell, so the way to the last is its parents
        if (!stack.length) for (let c = cw * ch - 1; c > 0; c = par[c]) path.unshift(c)
        return
      }
      if (k < path.length) { for (let n = 0; n < 10 && k < path.length; n++, k++) seg(g, k ? path[k - 1] : 0, path[k], 2); return }
      if (++hold > 120) fading = 1
    },
  }
}

// a slow flight through a starfield: stars come out of the centre and streak as they pass
const stars = (): Mode => {
  type S = { x: number; y: number; z: number; px: number; py: number }
  let st: S[] = [], W = 0, H = 0
  const born = (z: number): S => ({ x: Math.random() * 2 - 1, y: Math.random() * 2 - 1, z, px: NaN, py: NaN })
  return {
    name: "stars", colour: "cyan", smooth: true,
    init(g) { W = g.cols * 2; H = g.rows * 4; st = Array.from({ length: 150 }, () => born(0.1 + Math.random() * 0.9)); g.clear() },
    step(g) {
      g.decay(fade(0.45))
      const f = H * 0.35
      for (const s of st) {
        s.z -= 0.005 * dt
        const x = W / 2 + (s.x / s.z) * f, y = H / 2 + (s.y / s.z) * f
        if (s.z <= 0.02 || x < 0 || x >= W || y < 0 || y >= H) { Object.assign(s, born(1)); continue }
        const hue = s.z < 0.2 ? 0 : s.z < 0.5 ? 3 : 4
        // a near star moves several dots a tick: a short streak back to where it was
        const n = Number.isNaN(s.px) ? 1 : Math.min(6, Math.ceil(Math.hypot(x - s.px, y - s.py) / 2))
        for (let i = 0; i < n; i++) g.plot(x + ((s.px - x) * i) / n || x, y + ((s.py - y) * i) / n || y, hue)
        s.px = x; s.py = y
      }
    },
  }
}

// particles drifting on a slowly turning current: a sum of sines is smooth enough, no noise table
const flow = (): Mode => {
  type F = { x: number; y: number; life: number; hue: number }
  let ps: F[] = [], W = 0, H = 0, t = 0
  const spawn = (p: F): F => Object.assign(p, { x: Math.random() * W, y: Math.random() * H, life: 40 + Math.random() * 120, hue: Math.random() < 0.7 ? 3 : Math.random() < 0.6 ? 1 : 4 })
  const angle = (x: number, y: number) => Math.sin(x * 0.017 + t) * 1.6 + Math.cos(y * 0.023 - t * 0.7) * 1.4 + Math.sin((x + y) * 0.008 + t * 0.4)
  return {
    name: "flow", colour: "cyan", smooth: true,
    init(g) { W = g.cols * 2; H = g.rows * 4; t = Math.random() * 100; ps = Array.from({ length: 240 }, () => spawn({ x: 0, y: 0, life: 0, hue: 3 })); g.clear() },
    poke(_g, px, py) {
      for (let i = 0; i < 30; i++) ps.push({ x: px + (Math.random() - 0.5) * 20, y: py + (Math.random() - 0.5) * 20, life: 60 + Math.random() * 60, hue: 2 })
      if (ps.length > 330) ps.splice(240, ps.length - 330)
    },
    step(g) {
      g.decay(fade(0.07)); t += 0.003 * dt
      for (const p of ps) {
        const a = angle(p.x, p.y)
        p.x += Math.cos(a) * 1.8 * dt; p.y += Math.sin(a) * 1.8 * dt; g.plot(p.x, p.y, p.hue)
        if ((p.life -= dt) < 0 || p.x < 0 || p.x >= W || p.y < 0 || p.y >= H) spawn(p)
      }
    },
  }
}

// Langton's ants: each turns right on an empty dot and left on a laid one, flipping it as it
// goes; out of the noise, some ten thousand steps in, each builds its highway
const ant = (): Mode => {
  const DX = [0, 1, 0, -1], DY = [-1, 0, 1, 0]
  type A = { x: number; y: number; d: number; hue: number }
  let W = 0, H = 0, cells = new Uint8Array(0), ants: A[] = [], on = 0
  const place = (x: number, y: number, hue: number): A => ({ x: Math.floor(x), y: Math.floor(y), d: Math.floor(Math.random() * 4), hue })
  const start = (g: CharGrid) => {
    W = g.cols * 2; H = g.rows * 4; cells = new Uint8Array(W * H); on = 0
    ants = [0, 1, 3].map((hue) => place(W * (0.3 + Math.random() * 0.4), H * (0.3 + Math.random() * 0.4), hue))
    g.clear()
  }
  return {
    name: "ant", colour: "amber",
    init: start,
    poke(_g, x, y) { ants.push(place(x, y, 2)); if (ants.length > 5) ants.splice(3, 1) },
    step(g) {
      for (const a of ants) for (let i = 0; i < 90; i++) {
        const k = a.y * W + a.x
        if (cells[k]) { a.d = (a.d + 3) & 3; cells[k] = 0; on-- } else { a.d = (a.d + 1) & 3; cells[k] = a.hue + 1; on++ }
        a.x = (a.x + DX[a.d] + W) % W; a.y = (a.y + DY[a.d] + H) % H
      }
      // highways wrap the torus and would pave it: start over once an eighth of it is laid
      if (on > (W * H) / 8) { start(g); return }
      g.clear()
      for (let i = 0; i < cells.length; i++) if (cells[i]) g.plot(i % W, (i / W) | 0, cells[i] - 1)
    },
  }
}

// rain on dark water: drops land at random, their rings spread flat and thin out
const rain = (): Mode => {
  type R = { x: number; y: number; r: number; max: number }
  let rings: R[] = [], W = 0, H = 0
  return {
    name: "rain", colour: "cyan", smooth: true,
    init(g) { W = g.cols * 2; H = g.rows * 4; rings = []; g.clear() },
    poke(_g, x, y) { rings.push({ x, y, r: 0, max: 50 }) },
    step(g) {
      // as many rings as the canvas has room for (a fixed dozen read as empty on a full screen)
      if (rings.length < (W * H) / 3000 && Math.random() < 0.6 * dt) rings.push({ x: Math.random() * W, y: H * 0.1 + Math.random() * H * 0.85, r: 0, max: 16 + Math.random() * 40 })
      g.clear()
      rings = rings.filter((q) => (q.r += 0.8 * dt) < q.max)
      for (const q of rings) {
        const life = 1 - q.r / q.max, n = Math.ceil(q.r * 3)
        for (let j = 0; j < n; j++) {
          if (Math.random() > life * 0.9) continue
          const a = (j / n) * Math.PI * 2
          g.plot(q.x + Math.cos(a) * q.r, q.y + Math.sin(a) * q.r * 0.45, life > 0.5 ? 3 : 4)
        }
      }
    },
  }
}

const babel = (): Mode => {
  let lib: Babel | null = null
  return {
    name: "babel", colour: "amber",
    init(g) { ensureBooks(); lib = new Babel(g.cols, g.rows); lib.scroll = Math.random() * 1000; g.clear() },
    // a click hurries the drift for a moment — a reader turning pages
    poke() { if (lib) { lib.speed = 0.6; setTimeout(() => { if (lib) lib.speed = 0.06 }, 1500) } },
    step() { lib?.step() },
    text() { return lib?.lines() ?? [] },
  }
}

/** A fresh set per canvas, so two monitors never share a flock or a tracer. */
export const makeModes = (): Mode[] => [lorenz(), babel(), life(), boids(), rule30(), pipes(), bonsai(), maze(), stars(), flow(), ant(), rain()]
