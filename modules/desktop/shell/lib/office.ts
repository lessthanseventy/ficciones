// The office scene for the right rail (surfaces/Office.tsx). A three-quarter top-down room on a
// W×H grid of logical pixels, blown up S times: the whiteboard on the back wall (the open
// worklines by stage), your glass office with the lounge beside it, the leads' rug, the floor.
// Working sessions sit at their desks; idle ones wander the lounge; one waiting on you queues at
// your door. Every walk goes through the corridor down the right edge, so nobody needs a path
// finder. Looks and habits come from a hash of the agent's name, gear from its archetype; every
// colour is a theme ROLE read at draw time.
import Cairo from "cairo"
import { ROLE, type Role } from "./palette"
import type { Agents, Seat, Thread, Ticket } from "./agents"

export const S = 3
export const W = 144
const CX = 137 // the corridor
const BAND = 34 // the back wall ends here
const DOOR_Y = [46, 68] // the gap in your office's glass wall
const FLOOR = 108 // the desks start here
const DESK_W = 42, LEAD_W = 56, BOSS_W = 58, ROW_H = 40

/** what a click on the scene means: a thread to show, a ticket to hand out, a person, or a tool */
export type Act =
  | { kind: "thread"; tid: number }
  | { kind: "ticket"; id: number }
  | { kind: "person"; agentId: number | null; name: string; tid: number | null }
  | { kind: "hire" }
  | { kind: "pen" }
export type Hit = { x: number; y: number; w: number; h: number; tip: string; act: Act }
type Dir = "down" | "up" | "left" | "right"
type Pose = "stand" | "sit" | "couch"
type Kind = "desk" | "queue" | "board" | "couch" | "cooler" | "roam" | "exit"
type Spot = { x: number; y: number; aisle: number; pose: Pose; face: Dir; kind: Kind }
type Desk = { x: number; y: number; w: number; kind: "boss" | "lead" | "worker" | "hire"; seat?: Seat }
type Look = { hair: Hair; hairRole: Role; decor: number; fav: Kind; emote: string; slow: boolean; blink: number }
type Actor = {
  seat: Seat; look: Look; x: number; y: number; path: { x: number; y: number }[]
  spot: Spot; spotKey: string; pose: Pose; face: Dir; moving: boolean
  until: number; emote: string | null; emoteUntil: number; leaving: boolean
}

const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)
const keyOf = (r: Seat) => `${r.agent}#${r.thread_id}`
const spotKey = (s: Spot) => `${s.kind}:${s.x}:${s.y}`
function hash(s: string) { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0 }

// ── sprites: one char per pixel, "." clear; letters are looked up in a paint map at draw time ──
type Hair = "mop" | "spiky" | "bun" | "long" | "bald"
const HAIRS: Hair[] = ["mop", "spiky", "bun", "long", "bald"]
const HAIR_ROLES: Role[] = ["inactive", "structure", "meta", "borderInactive"]
const TOP: Record<Hair, string[]> = {
  mop: ["............", "............", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  spiky: ["............", "...h..h..h..", "..hhhhhhhh..", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  bun: [".....hh.....", "....hhhh....", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  long: ["............", "............", "...hhhhhh...", "..hhhhhhhh..", ".hhhhhhhhhh.", ".hhffffffhh."],
  bald: ["............", "............", "............", "...ffffff...", "..ffffffff..", "..ffffffff.."],
}
const FACE = ["..fkffffkf..", "..ffffffff..", "...ffkkff...", ".....ff....."]
const SHUT = "..fkkffkkf.."
const SIDE_HEAD = ["............", "............", "....hhhhh...", "...hhhhhhhh.", "..hhhhhhhhh.", "..fffffhhhh.", ".fkffffhhh..", "..fffffffh..", "..kfffff....", ".....ff....."]
const TORSO = ["..ssssssss..", ".ssssssssss.", ".ssssssssss.", ".fssssssssf.", "..ssssssss.."]
const SIDE_TORSO = ["...ssssss...", "...ssssss...", "...sfssss...", "...ssssss...", "...ssssss..."]
const LEGS: Record<string, string[]> = {
  stand: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..bb....bb.."],
  a: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..bb....pp..", "........bb.."],
  b: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....bb..", "..bb........"],
  couch: ["..pppppppp..", "..pppppppp..", "..pp....pp..", "..bb....bb..", "............"],
  sideStand: ["...pppppp...", "....pppp....", "....pp.p....", "....pp.p....", "...bbb.bb..."],
  sideA: ["...pppppp...", "...pp..pp...", "..pp....pp..", ".pp......pp.", ".bb......bb."],
  sideB: ["...pppppp...", "....pppp....", "....pppp....", "....pp.p....", "...bbbbb...."],
}
// archetype gear, as row overlays per view
type Gear = { front?: Record<number, string>; side?: Record<number, string>; back?: Record<number, string> }
const HARDHAT = { 1: "....yyyy....", 2: "..yyyyyyyy..", 3: ".yyyyyyyyyy." }
const SAFARI = { 1: "...cccccc...", 2: "...cccccc...", 3: "cccccccccccc" }
const GEAR: Record<string, Gear> = {
  builder: { front: HARDHAT, back: HARDHAT, side: { 1: "....yyyy....", 2: "...yyyyyy...", 3: "yyyyyyyyyy.." } },
  surveyor: { front: SAFARI, back: SAFARI, side: SAFARI },
  reviewer: { front: { 6: "..gkggggkg.." }, side: { 6: ".gkgg......." } },
  assistant: {
    front: { 2: "...eeeeee...", 5: ".e........e.", 6: ".e........e.", 7: ".e........e.", 8: ".eee........" },
    back: { 2: "...eeeeee...", 5: ".e........e.", 6: ".e........e." },
    side: { 2: "....eeeee...", 5: ".......e....", 6: ".......e....", 7: "..eeeeee...." },
  },
  researcher: { front: { 10: "........ggg.", 11: ".......g...g", 12: "........ggg.", 13: ".......c...." }, side: { 10: ".ggg........", 11: "g...g.......", 12: ".ggg........", 13: "....c......." } },
  planner: { front: { 11: ".......cc...", 12: "......wwww..", 13: "......wwww..", 14: "......wwww.." }, side: { 11: "..cc........", 12: ".wwww.......", 13: ".wwww......." } },
}
const BADGE = { 11: "...y........", 12: "..yyy......." }
const TIE = { 10: ".....rr.....", 11: ".....rr.....", 12: "....rrrr....", 13: ".....rr....." }

const DECOR = [
  [".l.l.", "lllll", ".lll.", "..l..", ".ooo.", ".ooo."], // plant
  ["mmmm.", "mmm.m", "mmmm.", "mmm.."], // mug (steam drawn over it)
  ["..yy.", "..yya", "yyyy.", ".yyy."], // rubber duck
  ["akl", "akl", "akl", "akl"], // books
  ["..l..", "l.l.l", "lllll", "..l..", ".ooo.", ".ooo."], // cactus
  ["oooo", "okko", "oaao", "oooo"], // photo
]
const MONITOR = ["oooooooooo", "o........o", "o........o", "o........o", "o........o", "o........o", "oooooooooo", "....oo....", "...oooo..."]
const COOLER = [".kkkkkk.", ".kkkkkk.", ".kkkkkk.", "..kkkk..", "mmmmmmmm", "mmmmmmmm", "mmaammmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "o......o", "oo....oo"]
const BIG_PLANT = ["...l..l...", ".l.ll.l.l.", "llllllllll", ".llllllll.", "..llllll..", "...llll...", "....ll....", "....ll....", "..oooooo..", "..oooooo..", "...oooo..."]
const BUBBLE = [".aaaaa.", "aaaaaaa", "aaaaaaa", "aaaaaaa", "aaaaaaa", "aaaaaaa", ".aaaaa.", "..a...."]
const GLYPH: Record<string, string[]> = {
  "!": ["..k..", "..k..", "..k..", ".....", "..k.."],
  "?": [".kkk.", "....k", "..kk.", ".....", "..k.."],
  "…": [".....", ".....", ".....", ".....", "k.k.k"],
  "♪": ["..kk.", "..k.k", "..k..", "kkk..", "kk..."],
  "~": [".....", ".k...", "k.k.k", "...k.", "....."],
  "*": ["k.k.k", ".kkk.", "kkkkk", ".kkk.", "k.k.k"],
  "♥": [".k.k.", "kkkkk", "kkkkk", ".kkk.", "..k.."],
}
const SIGNATURES = ["♪", "♥", "*", "…"]
const ZED = ["zzzzz", "...z.", "..z..", ".z...", "zzzzz"]
const ARROW = ["vvvvv", ".vvv.", "..v.."]

function overlay(rows: string[], over: Record<number, string> | undefined) {
  if (!over) return
  for (const [k, o] of Object.entries(over)) {
    const i = Number(k), r = rows[i].split("")
    for (let c = 0; c < o.length; c++) if (o[c] !== ".") r[c] = o[c]
    rows[i] = r.join("")
  }
}

/** a 20-row figure (or 14 rows seated at a desk), facing `face` */
function figure(look: Look, archetype: string | null | undefined, lead: boolean, boss: boolean, face: Dir, pose: Pose, step: number, shut: boolean): string[] {
  const view = face === "up" ? "back" : face === "left" || face === "right" ? "side" : "front"
  const bald = look.hair === "bald"
  let rows: string[]
  if (view === "side") {
    rows = SIDE_HEAD.map((r, i) => (bald && i >= 2 && i <= 7 ? r.replaceAll("h", "f") : r))
    if (look.hair === "bun") overlay(rows, { 0: ".......hh...", 1: "......hhhh.." })
    if (look.hair === "spiky") overlay(rows, { 1: "....h.h.h..." })
    rows.push(...SIDE_TORSO, ...(pose !== "stand" ? LEGS.sideStand : step === 0 ? LEGS.sideStand : step === 1 ? LEGS.sideA : LEGS.sideB))
  } else {
    const top = [...TOP[look.hair]]
    let face4 = [...FACE]
    if (view === "back") {
      const h = bald ? "f" : "h"
      top[5] = look.hair === "long" ? ".hhhhhhhhhh." : `..${h.repeat(8)}..`
      face4 = [`..${h.repeat(8)}..`, `..${h.repeat(8)}..`, `...${h.repeat(6)}...`, ".....ff....."]
      if (look.hair === "long") face4 = [".hhhhhhhhhh.", ".hhhhhhhhhh.", ".hhhhhhhhhh.", ".....ff....."]
    } else {
      if (shut) face4[0] = SHUT
      if (look.hair === "long") face4 = face4.map((r, i) => (i < 3 ? `.h${r.slice(2, 10)}h.` : r))
      if (bald) face4[1] = "..ffhhhhff.." // the mustache
    }
    rows = [...top, ...face4, ...TORSO, ...(pose === "couch" ? LEGS.couch : step === 1 ? LEGS.a : step === 2 ? LEGS.b : LEGS.stand)]
  }
  const gear = GEAR[archetype ?? ""]
  overlay(rows, view === "front" ? gear?.front : view === "back" ? gear?.back : gear?.side)
  if (view === "front" && lead) overlay(rows, BADGE)
  if (view === "front" && boss) overlay(rows, TIE)
  if (face === "right") rows = rows.map((r) => r.split("").reverse().join(""))
  return pose === "sit" ? rows.slice(0, 14) : rows
}

function lookOf(name: string): Look {
  const h = hash(name)
  return {
    hair: HAIRS[h % HAIRS.length],
    hairRole: HAIR_ROLES[(h >>> 4) % HAIR_ROLES.length],
    decor: (h >>> 8) % DECOR.length,
    fav: (["board", "couch", "cooler"] as Kind[])[(h >>> 12) % 3],
    emote: SIGNATURES[(h >>> 16) % SIGNATURES.length],
    slow: ((h >>> 20) & 1) === 1,
    blink: (h >>> 22) % 50,
  }
}
const BOSS_LOOK: Look = { hair: "mop", hairRole: "structure", decor: 1, fav: "board", emote: "…", slow: false, blink: 7 }

// ── the room ──────────────────────────────────────────────────────────────────────────────
function layout(a: Agents) {
  const desks: Desk[] = [{ x: 6, y: 42, w: BOSS_W, kind: "boss" }]
  const leads = a.roster.filter((r) => r.lead), floor = a.roster.filter((r) => !r.lead)
  const help = floor.length
  let y = FLOOR
  leads.forEach((r, i) => {
    const n = Math.min(2, leads.length - Math.floor(i / 2) * 2)
    const gap = (130 - n * LEAD_W) / (n + 1)
    desks.push({ x: Math.round(gap + (i % 2) * (LEAD_W + gap)), y: y + Math.floor(i / 2) * ROW_H, w: LEAD_W, kind: "lead", seat: r })
  })
  const leadRows = Math.ceil(leads.length / 2)
  y += leadRows * ROW_H + (leadRows ? 4 : 0)
  floor.forEach((r, i) => desks.push({ x: 2 + (i % 3) * 43, y: y + Math.floor(i / 3) * ROW_H, w: DESK_W, kind: "worker", seat: r }))
  desks.push({ x: 2 + (help % 3) * 43, y: y + Math.floor(help / 3) * ROW_H, w: DESK_W, kind: "hire" })
  const height = y + Math.ceil((help + 1) / 3) * ROW_H + 10
  return { desks, leadRows, height }
}
const seatX = (d: Desk) => d.x + Math.round(d.w / 2) + 4
const deskSpot = (d: Desk): Spot => ({ x: seatX(d), y: d.y + 25, aisle: d.y + 3, pose: "sit", face: "down", kind: "desk" })
const QUEUE: Spot[] = [80, 91, 102, 113, 124].map((x) => ({ x, y: 66, aisle: 66, pose: "stand", face: "left", kind: "queue" }))
const LOUNGE: Spot[] = [
  { x: 84, y: 46, aisle: 46, pose: "stand", face: "up", kind: "board" },
  { x: 106, y: 46, aisle: 46, pose: "stand", face: "up", kind: "board" },
  { x: 84, y: 98, aisle: 98, pose: "couch", face: "down", kind: "couch" },
  { x: 98, y: 98, aisle: 98, pose: "couch", face: "down", kind: "couch" },
  { x: 112, y: 100, aisle: 100, pose: "stand", face: "right", kind: "cooler" },
]
const STAGE_COL: Record<string, number> = { intent: 1, spec: 1, plan: 2, build: 3, verify: 3, review: 4 }
const COLS = ["TICKETS", "SPEC", "PLAN", "BUILD", "REVIEW"]
const COL_W = 27, PER_ROW = 4, PER_COL = 16
/** a coworker on the bench with no thread: a person without a desk (thread_id is minus the agent id) */
const benchOnly = (a: Agents): Seat[] =>
  a.bench.filter((c) => !a.roster.some((r) => r.agent === c.name)).map((c) => ({ agent: c.name, thread_id: -c.agent_id, title: "", warm: false, archetype: c.archetype, lead: c.lead }))

export class OfficeSim {
  private actors = new Map<string, Actor>()
  private tick = 0
  private seeded = false

  /** advance one tick (100 ms): retarget everyone from the roster, then walk */
  step(a: Agents) {
    this.tick++
    const { desks, height } = layout(a)
    const exit: Spot = { x: CX, y: height - 2, aisle: height - 2, pose: "stand", face: "down", kind: "exit" }
    const threadOf = (id: number) => a.threads.find((t) => t.id === id)
    const asks = a.roster.filter((r) => needsYou(threadOf(r.thread_id))).sort((p, q) => p.thread_id - q.thread_id)
    const people = [...a.roster, ...benchOnly(a)]
    const live = new Set(people.map(keyOf))
    for (const r of people) {
      const k = keyOf(r)
      const actor = this.actors.get(k)
      if (actor) { actor.seat = r; actor.leaving = false; continue }
      // the same person under a new key (a session ended, or began): they keep where they stand
      const was = [...this.actors].find(([ok, x]) => !live.has(ok) && x.seat.agent === r.agent)
      if (was) { this.actors.delete(was[0]); was[1].seat = r; was[1].leaving = false; this.actors.set(k, was[1]); continue }
      const d = desks.find((x) => x.seat && keyOf(x.seat) === k)
      const at = this.seeded ? exit : d ? deskSpot(d) : LOUNGE[this.actors.size % LOUNGE.length]
      this.actors.set(k, { seat: r, look: lookOf(r.agent), x: at.x, y: at.y, path: [], spot: at, spotKey: this.seeded ? "" : spotKey(at), pose: at.pose, face: at.face, moving: false, until: 0, emote: null, emoteUntil: 0, leaving: false })
    }
    if (a.ok) this.seeded = true
    for (const [k, actor] of this.actors) if (!live.has(k)) actor.leaving = true

    const held = new Set([...this.actors.values()].map((x) => x.spotKey))
    for (const [k, actor] of this.actors) {
      const slot = asks.findIndex((r) => keyOf(r) === k)
      const d = desks.find((x) => x.seat && keyOf(x.seat) === k)
      let goal: Spot
      if (actor.leaving) goal = exit
      else if (slot >= 0) goal = QUEUE[Math.min(slot, QUEUE.length - 1)]
      else if (actor.seat.warm && d) goal = deskSpot(d)
      else goal = this.idleGoal(actor, held, desks)
      const gk = spotKey(goal)
      if (gk !== actor.spotKey) {
        held.delete(actor.spotKey); held.add(gk)
        const from = actor.path.length === 0 && actor.spot.kind === "desk" ? actor.spot.aisle : actor.y
        actor.path = [{ x: actor.x, y: from }, { x: CX, y: from }, { x: CX, y: goal.aisle }, { x: goal.x, y: goal.aisle }, { x: goal.x, y: goal.y }]
        actor.spot = goal; actor.spotKey = gk; actor.pose = "stand"
        actor.until = this.tick + 80 + Math.floor(Math.random() * 120)
      }
      this.walk(actor, goal.kind === "desk" || goal.kind === "queue" || !actor.look.slow ? 2 : 1)
      if (actor.leaving && !actor.moving && actor.path.length === 0) { this.actors.delete(k); continue }
      if (actor.emote && this.tick > actor.emoteUntil) actor.emote = null
      if (!actor.emote && !actor.moving && Math.random() < 0.006) {
        const e = { board: "?", cooler: "~" } as Record<string, string>
        actor.emote = e[actor.spot.kind] ?? actor.look.emote
        actor.emoteUntil = this.tick + 25
      }
    }
  }

  private idleGoal(actor: Actor, held: Set<string>, desks: Desk[]): Spot {
    const cur = actor.spot
    const idle = cur.kind === "board" || cur.kind === "couch" || cur.kind === "cooler" || cur.kind === "roam"
    if (idle && this.tick < actor.until) return cur
    const free = LOUNGE.filter((s) => !held.has(spotKey(s)) && spotKey(s) !== actor.spotKey)
    const fav = free.filter((s) => s.kind === actor.look.fav)
    const pool = fav.length && Math.random() < 0.6 ? fav : free
    const pick = pool[Math.floor(Math.random() * pool.length)]
    if (pick) return pick
    // the lounge is full: a stroll down an aisle
    const rows = desks.filter((d) => d.kind !== "boss")
    const row = rows[Math.floor(Math.random() * rows.length)]
    const y = row ? row.y + 3 : FLOOR + 3
    return { x: 10 + Math.floor(Math.random() * 110), y, aisle: y, pose: "stand", face: "down", kind: "roam" }
  }

  private walk(actor: Actor, speed: number) {
    actor.moving = false
    let budget = speed
    while (budget > 0 && actor.path.length) {
      const p = actor.path[0]
      const dx = p.x - actor.x, dy = p.y - actor.y
      if (dx === 0 && dy === 0) { actor.path.shift(); continue }
      actor.moving = true
      if (dx !== 0) { const s = Math.sign(dx) * Math.min(budget, Math.abs(dx)); actor.x += s; budget -= Math.abs(s); actor.face = dx < 0 ? "left" : "right" }
      else { const s = Math.sign(dy) * Math.min(budget, Math.abs(dy)); actor.y += s; budget -= Math.abs(s); actor.face = dy < 0 ? "up" : "down" }
    }
    if (!actor.path.length) { actor.pose = actor.spot.pose; if (!actor.moving) actor.face = actor.spot.face }
  }

  /** paint the room; returns the click targets (widget pixels) and the scene's height (lpx) */
  draw(cr: Cairo.Context, areaW: number, a: Agents, picked: number | null, armed: number | null): { hits: Hit[]; height: number } {
    const t = this.tick, f = Math.floor(t / 4)
    const { desks, leadRows, height } = layout(a)
    const ox = Math.floor((areaW - W * S) / 2)
    const threadOf = (id: number) => a.threads.find((x) => x.id === id)
    cr.setAntialias(Cairo.Antialias.NONE)
    const paint = (c: string) => { const x = c.replace("#", ""); cr.setSourceRGB(parseInt(x.slice(0, 2), 16) / 255, parseInt(x.slice(2, 4), 16) / 255, parseInt(x.slice(4, 6), 16) / 255) }
    const px = (x: number, y: number, pw: number, ph: number, c: string) => { paint(c); cr.rectangle(ox + x * S, y * S, pw * S, ph * S); cr.fill() }
    const blit = (rows: string[], x: number, y: number, map: Record<string, string>) =>
      rows.forEach((row, j) => { for (let i = 0; i < row.length; i++) { const c = map[row[i]]; if (c) px(x + i, y + j, 1, 1, c) } })
    const text = (s: string, cx: number, baseline: number, c: string, size = 12) => {
      cr.setFontSize(size); paint(c)
      const tw = cr.textExtents(s).width
      cr.moveTo(Math.round(cx - tw / 2), baseline); cr.showText(s)
    }
    cr.selectFontFace("ComicShannsMono Nerd Font", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
    const hits: Hit[] = []
    const people: Hit[] = []
    const shirtOf = (r?: Seat) => ROLE[(r?.archetype ?? "") as Role] ?? ROLE.body

    // floors and walls
    for (let ty = BAND; ty < height; ty += 8) for (let tx = 0; tx < W; tx += 8) px(tx, ty, 8, 8, ((tx + ty) / 8) % 2 ? ROLE.panel : ROLE.ground)
    px(0, BAND, 71, 104 - BAND, ROLE.raised)
    px(0, 0, W, BAND - 1, ROLE.edge)
    px(0, BAND - 1, W, 1, ROLE.structure)
    if (leadRows) px(2, FLOOR - 2, 128, leadRows * ROW_H, ROLE.raised)
    px(CX - 6, height - 4, 12, 3, ROLE.borderInactive)

    // the whiteboard: one sticky per open workline, in its stage's column, in its coworker's colour
    px(3, 2, 138, 30, ROLE.structure)
    px(4, 3, 136, 27, ROLE.ground)
    px(4, 30, 136, 2, ROLE.borderInactive)
    blit(["kk.aa.ll"], 100, 30, { k: ROLE.key, a: ROLE.alarm, l: ROLE.live })
    type Note = { tip: string; act: Act; colour: string; mark?: string; blink?: boolean }
    const cols: Note[][] = [[], [], [], [], []]
    for (const tk of a.tickets as Ticket[])
      cols[0].push({ tip: `ticket #${tk.id} ${tk.title}\nclick, then click a coworker to hand it over`, act: { kind: "ticket", id: tk.id }, colour: ROLE.prose, mark: tk.priority === "high" ? ROLE.alarm : undefined, blink: tk.id === armed })
    for (const th of a.threads) {
      const c = STAGE_COL[th.stage ?? ""]
      if (c === undefined) continue
      const r = a.roster.find((x) => x.thread_id === th.id)
      const asks = needsYou(th)
      cols[c].push({ tip: `#${th.id} ${th.title}\n${th.stage}${r ? ` · ${r.agent}` : ""}${asks ? "\nwaiting on you" : ""}`, act: { kind: "thread", tid: th.id }, colour: r ? shirtOf(r) : ROLE.inactive, blink: asks })
    }
    cols.forEach((list, c) => {
      const x0 = 6 + c * COL_W
      if (c) px(x0 - 2, 4, 1, 25, ROLE.edge)
      text(`${COLS[c]} ${list.length}`, ox + (x0 + 12) * S, 10 * S, ROLE.key, 10)
      const shown = c === 0 ? [...list.slice(0, PER_COL - 1), null] : list.slice(0, PER_COL)
      shown.forEach((n, i) => {
        const sx = x0 + (i % PER_ROW) * 6, sy = 12 + Math.floor(i / PER_ROW) * 5
        if (!n) {
          // the blank sticky at the end of the tickets column: write a new one
          blit(["..k..", ".kkk.", "..k..", "....."], sx, sy, { k: ROLE.key })
          hits.push({ x: ox + sx * S, y: sy * S, w: 5 * S, h: 4 * S, tip: "new ticket", act: { kind: "pen" } })
          return
        }
        px(sx, sy, 5, 4, n.blink && f % 2 ? ROLE.attention : n.colour)
        px(sx + 1, sy + 2, 3, 1, ROLE.fieldInk)
        if (n.mark) px(sx + 4, sy, 1, 1, n.mark)
        hits.push({ x: ox + sx * S, y: sy * S, w: 5 * S, h: 4 * S, tip: n.tip, act: n.act })
      })
      if (list.length > shown.filter(Boolean).length) text(`+${list.length - shown.filter(Boolean).length}`, ox + (x0 + 20) * S, 31 * S + 8, ROLE.key, 10)
    })
    hits.push({ x: ox + 100 * S, y: 29 * S, w: 8 * S, h: 3 * S, tip: "new ticket", act: { kind: "pen" } })

    // your office: glass on the lounge side, a door where the queue forms
    for (const [y0, y1] of [[BAND, DOOR_Y[0]], [DOOR_Y[1], 104]]) { px(70, y0, 1, y1 - y0, ROLE.edge); px(71, y0, 1, y1 - y0, ROLE.key) }
    px(0, 103, 72, 1, ROLE.structure)

    // the lounge: the couch's back and seat (its arms go in front of whoever sits)
    px(74, 84, 34, 6, ROLE.structure)
    px(76, 90, 30, 6, ROLE.borderInactive)
    px(76, 96, 2, 3, ROLE.structure); px(104, 96, 2, 3, ROLE.structure)

    // everything with a footprint, back to front
    type Item = { base: number; draw: () => void }
    const items: Item[] = []
    const overhead: (() => void)[] = []
    items.push({ base: 98, draw: () => {
      blit(COOLER, 120, 82, { k: ROLE.key, m: ROLE.prose, a: ROLE.alarm, o: ROLE.inactive })
      if ([...this.actors.values()].some((x) => x.spot.kind === "cooler" && !x.moving) && f % 3 === 0) px(122 + (f % 2) * 2, 83, 1, 1, ROLE.ground)
    } })
    items.push({ base: 99.5, draw: () => { px(73, 87, 3, 11, ROLE.structure); px(106, 87, 3, 11, ROLE.structure) } })
    items.push({ base: 101, draw: () => blit(BIG_PLANT, 58, 90, { l: ROLE.live, o: ROLE.structure }) })

    const actorAt = (d: Desk) => (d.seat ? this.actors.get(keyOf(d.seat)) : undefined)
    for (const d of desks) {
      if (d.kind === "hire") {
        // the empty desk at the end of the floor: a sign, and a click hires
        items.push({ base: d.y + 30, draw: () => {
          px(d.x, d.y + 19, d.w, 2, ROLE.structure)
          px(d.x + 1, d.y + 21, d.w - 2, 10, ROLE.borderInactive)
          px(d.x + 12, d.y + 8, 18, 9, ROLE.key)
          px(d.x + 13, d.y + 9, 16, 7, ROLE.ground)
          blit(["..k..", ".kkk.", "..k.."], d.x + 19, d.y + 10 + (f % 2), { k: ROLE.key })
          px(d.x + 20, d.y + 17, 2, 2, ROLE.inactive)
          text("help wanted", ox + (d.x + d.w / 2) * S, (d.y + 38) * S - 2, ROLE.key)
          hits.push({ x: ox + d.x * S, y: d.y * S, w: d.w * S, h: (ROW_H - 1) * S, tip: "hire a coworker", act: { kind: "hire" } })
        } })
        continue
      }
      const owner = actorAt(d)
      const seated = d.kind === "boss" || (owner && owner.spot.kind === "desk" && !owner.path.length)
      const asks = !!d.seat && needsYou(threadOf(d.seat.thread_id))
      const sx = seatX(d)
      if (d.kind === "boss") {
        items.push({ base: d.y + 25, draw: () => {
          blit(figure(BOSS_LOOK, null, false, true, "down", "sit", 0, (t + BOSS_LOOK.blink) % 50 < 2), sx - 6, d.y + 5, this.paints(ROLE.attention, BOSS_LOOK))
          const up = f % 3 === 0
          px(sx - 5, d.y + 18 - (up ? 1 : 0), 2, 1, ROLE.prose); px(sx + 3, d.y + 18, 2, 1, ROLE.prose)
        } })
      }
      items.push({ base: d.y + 30, draw: () => {
        if (!seated) { px(sx - 4, d.y + 11, 8, 8, ROLE.inactive); px(sx - 3, d.y + 12, 6, 6, ROLE.edge) }
        const mx = d.x + 3, my = d.y + 10
        blit(MONITOR, mx, my, { o: ROLE.inactive })
        if (asks) px(mx + 1, my + 1, 8, 5, f % 2 ? ROLE.attention : ROLE.raised)
        else if (seated) {
          px(mx + 1, my + 1, 8, 5, ROLE.ground)
          for (let l = 0; l < 3; l++) px(mx + 2, my + 1 + l * 2, 1 + ((f + l * 3 + (d.seat?.thread_id ?? 0)) % 6), 1, ROLE.live)
        } else {
          px(mx + 1, my + 1, 8, 5, ROLE.ground)
          const bx = Math.abs(((t >> 1) + d.x) % 14 - 7), by = Math.abs(((t >> 1) + d.y) % 8 - 4)
          px(mx + 1 + bx, my + 1 + by, 1, 1, ROLE.key)
        }
        px(d.x, d.y + 19, d.w, 2, ROLE.structure)
        px(d.x + 1, d.y + 21, d.w - 2, 10, ROLE.borderInactive)
        px(d.x + d.w - 12, d.y + 24, 8, 1, ROLE.structure)
        const look = d.kind === "boss" ? BOSS_LOOK : owner?.look
        if (look) {
          const dec = DECOR[look.decor]
          const dx = d.x + d.w - 4 - dec[0].length
          blit(dec, dx, d.y + 19 - dec.length, { l: ROLE.live, o: ROLE.structure, m: ROLE.prose, y: ROLE.body, a: ROLE.attention, k: ROLE.key })
          if (look.decor === 1) blit(f % 2 ? ["v.v.", ".v.."] : [".v.v", "..v."], dx, d.y + 13, { v: ROLE.inactive })
        }
        const name = d.kind === "boss" ? "you" : `${d.seat!.agent} #${d.seat!.thread_id}`
        text(name, ox + (d.x + d.w / 2) * S, (d.y + 38) * S - 2, d.kind === "boss" || asks ? ROLE.attention : seated ? shirtOf(d.seat) : ROLE.inactive)
        const hx = ox + d.x * S - 2, hy = d.y * S, hw = d.w * S + 4, hh = (ROW_H - 1) * S
        const where = !owner ? "" : owner.spot.kind === "desk" ? (owner.path.length ? "headed to the desk" : "working") : owner.spot.kind === "queue" ? "in your queue" : owner.leaving ? "leaving" : `idle, at the ${owner.spot.kind}`
        if (d.kind !== "boss") hits.push({ x: hx, y: hy, w: hw, h: hh, tip: this.tip(d.seat!, threadOf(d.seat!.thread_id), where), act: { kind: "thread", tid: d.seat!.thread_id } })
        if (d.kind !== "boss" && d.seat!.thread_id === picked) {
          paint(ROLE.body); cr.setLineWidth(2)
          for (const [x0, y0, gx, gy] of [[hx, hy, 1, 1], [hx + hw, hy, -1, 1], [hx, hy + hh, 1, -1], [hx + hw, hy + hh, -1, -1]]) {
            cr.moveTo(x0 + gx * 10, y0); cr.lineTo(x0, y0); cr.lineTo(x0, y0 + gy * 10); cr.stroke()
          }
        }
      } })
    }

    const queued = [...this.actors.values()].filter((x) => x.spot.kind === "queue")
    for (const actor of this.actors.values()) {
      const seat = actor.seat
      const sitting = actor.pose === "sit" && !actor.moving
      const couch = actor.pose === "couch" && !actor.moving
      const step = actor.moving ? 1 + (Math.floor(t / 2) % 2) : 0
      const shut = couch || (t + actor.look.blink) % 50 < 2
      const rows = figure(actor.look, seat.archetype, !!seat.lead, false, sitting || couch ? "down" : actor.face, sitting ? "sit" : couch ? "couch" : "stand", step, shut)
      const top = sitting ? actor.y - 20 : actor.y - 20 + (actor.moving && step === 2 ? -1 : 0)
      const left = actor.x - 6
      const th = threadOf(seat.thread_id)
      items.push({ base: sitting ? actor.y : actor.y + 0.5, draw: () => {
        blit(rows, left, top, this.paints(shirtOf(seat), actor.look))
        if (sitting && seat.warm) {
          const up = (f + actor.x) % 2 === 0
          px(left + 1, top + 13 - (up ? 1 : 0), 2, 1, ROLE.prose)
          px(left + 9, top + 13 - (up ? 0 : 1), 2, 1, ROLE.prose)
        }
      } })
      const agentId = a.bench.find((c) => c.name === seat.agent)?.agent_id ?? null
      people.push({ x: ox + left * S, y: top * S, w: 12 * S, h: (sitting ? 14 : 20) * S, tip: this.tip(seat, th, actor.spot.kind === "queue" ? "in your queue" : actor.moving ? "walking" : `at the ${actor.spot.kind}`), act: { kind: "person", agentId, name: seat.agent, tid: seat.thread_id > 0 ? seat.thread_id : null } })
      overhead.push(() => {
        let above = top - 9
        const bob = f % 2
        if (actor.spot.kind === "queue" && !actor.moving) {
          blit(BUBBLE, left + 3, above + bob, { a: ROLE.attention })
          blit(GLYPH["!"], left + 4, above + 1 + bob, { k: ROLE.fieldInk })
        } else if (couch) blit(ZED, left + 9, top - 4 - (f % 3), { z: ROLE.inactive })
        else if (actor.emote) {
          blit(BUBBLE, left + 3, above, { a: ROLE.prose })
          blit(GLYPH[actor.emote] ?? GLYPH["…"], left + 4, above + 1, { k: ROLE.fieldInk })
        } else above = top - 1
        if (seat.thread_id === picked) blit(ARROW, left + 4, above - 4 - bob, { v: ROLE.body })
      })
    }
    if (queued.length > QUEUE.length) overhead.push(() => text(`+${queued.length - QUEUE.length + 1}`, ox + 124 * S, 72 * S, ROLE.attention))

    items.sort((p, q) => p.base - q.base).forEach((x) => x.draw())
    overhead.forEach((d) => d())
    if (!a.ok || (a.roster.length === 0 && a.bench.length === 0)) text(a.ok ? "nobody on the clock" : (a.note ?? "channel down"), ox + (W * S) / 2, (FLOOR + 20) * S, a.ok ? ROLE.inactive : ROLE.alarm)
    // a click lands on a person before the desk behind them
    return { hits: [...people.reverse(), ...hits], height }
  }

  private paints(shirt: string, look: Look): Record<string, string> {
    return { h: ROLE[look.hairRole], f: ROLE.prose, k: ROLE.fieldInk, s: shirt, p: ROLE.meta, b: ROLE.structure, y: ROLE.body, c: ROLE.structure, g: ROLE.key, e: ROLE.key, w: ROLE.prose, r: ROLE.alarm }
  }

  private tip(r: Seat, th: Thread | undefined, where: string) {
    const ask = th?.prompt ? `\nasks: ${th.prompt.summary}` : th?.awaiting ? `\nawaits ${th.awaiting}` : ""
    const on = r.thread_id > 0 ? ` · #${r.thread_id} ${th?.title ?? r.title}` : " · on the bench"
    return `${r.agent}${r.archetype ? ` (${r.archetype}${r.lead ? ", lead" : ""})` : ""}${on}${ask}\n${where}`
  }
}
