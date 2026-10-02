// The office scene for the right rail (surfaces/Office.tsx). A three-quarter top-down room on a
// W×H grid of logical pixels, blown up S times: the whiteboard on the back wall (the open
// worklines by stage), your glass office with the lounge beside it, the leads' rug, the floor.
// Working sessions sit at their desks; idle ones wander the lounge; one waiting on you queues at
// your door. Every walk goes through the corridor down the right edge, so nobody needs a path
// finder. Looks and habits come from a hash of the agent's name, gear from its archetype; every
// colour is a theme ROLE read at draw time.
import Cairo from "cairo"
import GLib from "gi://GLib?version=2.0"
import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import { ROLE, type Role } from "./palette"
import type { Agents, Seat, Thread, Ticket } from "./agents"

export const S = 3
export const W = 144
const CX = 137 // the corridor
const BAND = 34 // the back wall ends here
const DOOR_Y = [80, 103] // the gap in your office's glass wall, low, where the queue walks in
const FLOOR = 108 // the desks start here
const DESK_W = 42, LEAD_W = 56, BOSS_W = 58, ROW_H = 40

/** what a click on the scene means: a thread to show, a ticket to hand out, a person, or a tool */
export type Act =
  | { kind: "thread"; tid: number }
  | { kind: "ticket"; id: number }
  | { kind: "person"; agentId: number | null; name: string; tid: number | null }
  | { kind: "hire" }
  | { kind: "pen" }
  | { kind: "column"; col: number }
  | { kind: "notes" }
  | { kind: "boss" }
export type Hit = { x: number; y: number; w: number; h: number; tip: string; act: Act }
type Dir = "down" | "up" | "left" | "right"
type Pose = "stand" | "sit" | "couch"
type Kind = "desk" | "queue" | "board" | "couch" | "cooler" | "coffee" | "roam" | "exit" | "visit" | "note"
type Spot = { x: number; y: number; aisle: number; pose: Pose; face: Dir; kind: Kind }
type Desk = { x: number; y: number; w: number; kind: "boss" | "manager" | "lead" | "worker"; seat?: Seat }
type Look = { hair: Hair; hairRole: Role; decor: number; fav: Kind; emote: string; slow: boolean; blink: number }
type Actor = {
  seat: Seat; look: Look; x: number; y: number; path: { x: number; y: number }[]
  spot: Spot; spotKey: string; pose: Pose; face: Dir; moving: boolean
  until: number; emote: string | null; emoteUntil: number; leaving: boolean
}

// a theme switch brings new hex strings, so the cache keys on the string itself
const rgbs = new Map<string, number[]>()
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
  "✎": ["....k", "...k.", "..k..", ".k...", "kk..."],
  "♪": ["..kk.", "..k.k", "..k..", "kkk..", "kk..."],
  "~": [".....", ".k...", "k.k.k", "...k.", "....."],
  "*": ["k.k.k", ".kkk.", "kkkkk", ".kkk.", "k.k.k"],
  "♥": [".k.k.", "kkkkk", "kkkkk", ".kkk.", "..k.."],
}
const SIGNATURES = ["♪", "♥", "*", "…"]
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
    fav: (["board", "couch", "cooler", "coffee"] as Kind[])[(h >>> 12) % 4],
    emote: SIGNATURES[(h >>> 16) % SIGNATURES.length],
    slow: ((h >>> 20) & 1) === 1,
    blink: (h >>> 22) % 50,
  }
}
const BOSS_LOOK: Look = { hair: "mop", hairRole: "structure", decor: 1, fav: "board", emote: "…", slow: false, blink: 7 }

// ── the room ──────────────────────────────────────────────────────────────────────────────
function layout(a: Agents) {
  const desks: Desk[] = [{ x: 6, y: 42, w: BOSS_W, kind: "boss" }]
  // the manager (a meta coworker) stands at the front of the leads' rug, the leads beside them
  const managers = a.roster.filter((r) => isManager(a, r))
  const leads = [...managers, ...a.roster.filter((r) => r.lead && !isManager(a, r))]
  const floor = a.roster.filter((r) => !r.lead && !isManager(a, r))
  let y = FLOOR
  leads.forEach((r, i) => {
    const n = Math.min(2, leads.length - Math.floor(i / 2) * 2)
    const gap = (130 - n * LEAD_W) / (n + 1)
    desks.push({ x: Math.round(gap + (i % 2) * (LEAD_W + gap)), y: y + Math.floor(i / 2) * ROW_H, w: LEAD_W, kind: isManager(a, r) ? "manager" : "lead", seat: r })
  })
  const leadRows = Math.ceil(leads.length / 2)
  y += leadRows * ROW_H + (leadRows ? 4 : 0)
  floor.forEach((r, i) => desks.push({ x: 2 + (i % 3) * 43, y: y + Math.floor(i / 3) * ROW_H, w: DESK_W, kind: "worker", seat: r }))
  const height = y + Math.max(1, Math.ceil(floor.length / 3)) * ROW_H + 10
  return { desks, leadRows, height }
}
/** a meta coworker — the one who routes the work and never works a thread */
const isManager = (a: Agents, r: { archetype?: string | null }) => !!a.archetypes.find((x) => x.name === r.archetype)?.meta
const seatX = (d: Desk) => d.x + Math.round(d.w / 2)
// a worker sits on the room side of their desk, back to you, the monitor across the desk facing
// them (and you); they come and go along the aisle below the row
const deskSpot = (d: Desk): Spot =>
  d.kind === "manager"
    ? { x: seatX(d), y: d.y + 19, aisle: d.y + 34, pose: "sit", face: "down", kind: "desk" } // behind their desk, facing the floor
    : { x: seatX(d), y: d.y + 26, aisle: d.y + 34, pose: "sit", face: "up", kind: "desk" }
// whoever has a question for you stands at your desk; the rest line up behind them, out the door
const QUEUE: Spot[] = [38, 50, 61, 82, 94].map((x, i) => ({ x, y: 100, aisle: 100, pose: "stand", face: i === 0 ? "up" : "left", kind: "queue" }))
// the lounge: the board up front; the couch below the TV, its back to you; the kitchenette along
// the glass. The aisles keep every walk off the furniture
const LOUNGE: Spot[] = [
  { x: 78, y: 46, aisle: 50, pose: "stand", face: "up", kind: "board" },
  { x: 90, y: 46, aisle: 50, pose: "stand", face: "up", kind: "board" },
  { x: 104, y: 72, aisle: 80, pose: "couch", face: "up", kind: "couch" },
  { x: 118, y: 72, aisle: 80, pose: "couch", face: "up", kind: "couch" },
  { x: 88, y: 64, aisle: 86, pose: "stand", face: "left", kind: "cooler" },
  { x: 88, y: 80, aisle: 86, pose: "stand", face: "left", kind: "coffee" },
]
const COFFEE = ["mmmmmmm", "mlmmmmm", "mmmmmmm", "m.....m", "m..c..m", "m.ccc.m", "mmmmmmm"]
// TICKETS (unstarted) and DOING (a started plain thread — no workline stage) before the stages
/** beside whoever is visited: at their desk if they sit at one, else where they stand */
function visitSpot(h: Actor): Spot {
  const at = h.spot.kind === "desk" && !h.path.length ? h.spot : { x: h.x, y: h.y, aisle: h.y }
  return { x: Math.min(128, at.x + 12), y: at.y, aisle: at.aisle, pose: "stand", face: "left", kind: "visit" }
}
const BOARD_PEN: Spot = { x: 84, y: 44, aisle: 44, pose: "stand", face: "up", kind: "note" }
const STAGE_COL: Record<string, number> = { intent: 2, spec: 2, plan: 3, build: 4, verify: 4, review: 5 }
const COLS = ["TICKETS", "DOING", "SPEC", "PLAN", "BUILD", "REVIEW"]
const COL_W = 22, PER_ROW = 3, PER_COL = 6
// a note on the board's strip: a squiggle in its author's colour, one of these by its id
const SCRIBBLES = [["k.kk.k.kk", ".k..k.k..", "kk.k.kk.k"], ["kk.k.kk.k", "k.k..k.k.", ".kk.kk.kk"], [".k.kk.k.k", "kk.k..kk.", "k..kk.k.k"]]
const VISIT_MS = 60_000, NOTE_MS = 45_000

/** one note on the whiteboard: what a click on it does, and what its sticky and its list row say */
export type BoardItem = { act: Act; title: string; who: string | null; stage: string; asks: boolean; archetype: string | null; high: boolean; routed?: boolean }
/** the whiteboard's columns — the board draws them as stickies, the office's column card as rows */
export function boardColumns(a: Agents): { name: string; items: BoardItem[] }[] {
  const cols: BoardItem[][] = COLS.map(() => [])
  for (const tk of a.tickets as Ticket[])
    cols[0].push({ act: { kind: "ticket", id: tk.id }, title: tk.title, who: null, stage: tk.routed ? "with the manager" : "ticket", asks: false, archetype: null, high: tk.priority === "high", routed: !!tk.routed })
  for (const th of a.threads) {
    const c = th.stage ? STAGE_COL[th.stage] : th.lead && !th.standing ? 1 : undefined
    if (c === undefined) continue
    const r = a.roster.find((x) => x.thread_id === th.id)
    cols[c].push({ act: { kind: "thread", tid: th.id }, title: th.title, who: r?.agent ?? th.lead ?? null, stage: th.stage ?? "doing", asks: needsYou(th), archetype: r?.archetype ?? null, high: false })
  }
  return COLS.map((name, i) => ({ name, items: cols[i] }))
}
/** a coworker on the bench with no thread: a person without a desk (thread_id is minus the agent id) */
const benchOnly = (a: Agents): Seat[] =>
  a.bench.filter((c) => !a.roster.some((r) => r.agent === c.name)).map((c) => ({ agent: c.name, thread_id: -c.agent_id, title: "", warm: false, archetype: c.archetype, lead: c.lead }))

export class OfficeSim {
  private actors = new Map<string, Actor>()
  private tick = 0
  private seeded = false

  /** who you are talking to, by agent name: `text` null while they think, then what they said */
  private talk = new Map<string, { text: string | null; until: number }>()
  /** someone was asked something (`text` null) or has answered; an answer shows for ~12 s */
  say(agent: string, text: string | null) { this.talk.set(agent, { text, until: text === null ? Infinity : this.tick + 120 }); this.changed = true }
  private changed = true

  /**
   * Advance one tick (100 ms): retarget everyone from the roster, then walk. True when the room
   * looks different — someone moved, or the 400 ms animation frame turned — so the caller redraws
   * only then: a full office repainted every tick cost a fifth of a core.
   */
  step(a: Agents): boolean {
    this.tick++
    let changed = this.changed || this.tick % 4 === 0
    this.changed = false
    for (const [k, v] of this.talk) if (this.tick > v.until) { this.talk.delete(k); changed = true }
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

    // a consult walks the asker over to whoever they asked; a note walks its author to the board
    const now = Date.now()
    const visiting = new Map(a.visits.filter((v) => now - Date.parse(v.at) < VISIT_MS).map((v) => [v.from, v.to]))
    const writing = new Set(a.notes.filter((n) => now - Date.parse(n.at) < NOTE_MS).map((n) => n.author))
    let host: Actor | undefined
    const held = new Set([...this.actors.values()].map((x) => x.spotKey))
    for (const [k, actor] of this.actors) {
      const slot = asks.findIndex((r) => keyOf(r) === k)
      const d = desks.find((x) => x.seat && keyOf(x.seat) === k)
      let goal: Spot
      if (actor.leaving) goal = exit
      else if (slot >= 0) goal = QUEUE[Math.min(slot, QUEUE.length - 1)]
      else if (visiting.has(actor.seat.agent) && (host = this.find(visiting.get(actor.seat.agent)!))) goal = visitSpot(host)
      else if (writing.has(actor.seat.agent)) goal = BOARD_PEN
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
      // someone you are talking to stops where they are and faces you until they have answered
      if (this.talk.get(actor.seat.agent)?.text === null) { actor.moving = false; if (actor.pose === "stand") actor.face = "down" }
      else this.walk(actor, goal.kind === "desk" || goal.kind === "queue" || !actor.look.slow ? 2 : 1)
      if (actor.moving) changed = true
      else if (goal.kind === "visit" || goal.kind === "note") {
        // arrived: the two of them talk, or the pen moves
        const e = goal.kind === "note" ? "✎" : "~"
        if (actor.emote !== e) { actor.emote = e; changed = true }
        actor.emoteUntil = this.tick + 5
        const h = goal.kind === "visit" ? this.find(visiting.get(actor.seat.agent)!) : undefined
        if (h && h.emote !== "~") { h.emote = "~"; h.emoteUntil = this.tick + 5; changed = true }
      }
      if (actor.leaving && !actor.moving && actor.path.length === 0) { this.actors.delete(k); changed = true; continue }
      if (actor.emote && this.tick > actor.emoteUntil) { actor.emote = null; changed = true }
      if (!actor.emote && !actor.moving && Math.random() < 0.006) {
        const e = { board: "?", cooler: "~", coffee: "♥" } as Record<string, string>
        actor.emote = e[actor.spot.kind] ?? actor.look.emote
        actor.emoteUntil = this.tick + 25
        changed = true
      }
    }
    return changed
  }

  /** where someone is now, by name — at their desk before anywhere else */
  private find(agent: string): Actor | undefined {
    const all = [...this.actors.values()].filter((x) => x.seat.agent === agent && !x.leaving)
    return all.find((x) => x.spot.kind === "desk") ?? all[0]
  }

  private idleGoal(actor: Actor, held: Set<string>, desks: Desk[]): Spot {
    const cur = actor.spot
    const idle = cur.kind === "board" || cur.kind === "couch" || cur.kind === "cooler" || cur.kind === "coffee" || cur.kind === "roam"
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
  /** `focus`: the agent whose card is open — the arrow follows them as it follows the picked thread */
  draw(cr: Cairo.Context, areaW: number, a: Agents, picked: number | null, armed: number | null, focus: string | null = null): { hits: Hit[]; height: number } {
    const t = this.tick, f = Math.floor(t / 4)
    const { desks, leadRows, height } = layout(a)
    const ox = Math.floor((areaW - W * S) / 2)
    const threadOf = (id: number) => a.threads.find((x) => x.id === id)
    cr.setAntialias(Cairo.Antialias.NONE)
    const rgb = (c: string) => { let v = rgbs.get(c); if (!v) rgbs.set(c, (v = [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16)))); return v }
    const paint = (c: string) => { const [r, g, b] = rgb(c); cr.setSourceRGB(r / 255, g / 255, b / 255) }
    // the pixel art goes into a 1x buffer that Cairo paints once, scaled S times with no smoothing —
    // a Cairo rectangle per logical pixel cost a third of a core with a full office
    const buf = new Uint8Array(W * height * 4)
    const px = (x: number, y: number, pw: number, ph: number, c: string) => {
      const [r, g, b] = rgb(c)
      const x0 = Math.max(0, Math.floor(x)), x1 = Math.min(W, Math.floor(x + pw)), y1 = Math.min(height, Math.floor(y + ph))
      for (let j = Math.max(0, Math.floor(y)); j < y1; j++) for (let i = x0, o = (j * W + x0) * 4; i < x1; i++, o += 4) { buf[o] = r; buf[o + 1] = g; buf[o + 2] = b; buf[o + 3] = 255 }
    }
    const blit = (rows: string[], x: number, y: number, map: Record<string, string>) =>
      rows.forEach((row, j) => { for (let i = 0; i < row.length; i++) { const c = map[row[i]]; if (c) px(x + i, y + j, 1, 1, c) } })
    // text and the cursor go on top of the art, at the screen's own resolution
    const ink: (() => void)[] = []
    const text = (s: string, cx: number, baseline: number, c: string, size = 12) => ink.push(() => {
      cr.setFontSize(size); paint(c)
      const tw = cr.textExtents(s).width
      cr.moveTo(Math.round(cx - tw / 2), baseline); cr.showText(s)
    })
    /** `name #id` cut to `width` px: the name gives way, the number stays */
    const plate = (name: string, tail: string, width: number) => {
      cr.setFontSize(12)
      let n = name
      while (n.length > 2 && cr.textExtents(`${n} ${tail}`).width > width) n = n.slice(0, -1)
      return n === name ? `${name} ${tail}` : `${n.slice(0, -1)}.. ${tail}`
    }
    cr.selectFontFace("ComicShannsMono Nerd Font", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
    const hits: Hit[] = []
    const people: Hit[] = []
    const shirtOf = (r?: Seat) => ROLE[(r?.archetype ?? "") as Role] ?? ROLE.body

    // floors and walls
    for (let ty = BAND; ty < height; ty += 8) for (let tx = 0; tx < W; tx += 8) px(tx, ty, 8, 8, ((tx + ty) / 8) % 2 ? ROLE.panel : ROLE.ground)
    px(0, BAND, 71, 104 - BAND, ROLE.raised)
    // your rug: gold-bordered, under the desk
    px(3, 38, 64, 42, ROLE.body); px(4, 39, 62, 40, ROLE.panel)
    for (let i = 0; i < 7; i++) for (let j = 0; j < 4; j++) px(8 + i * 9, 44 + j * 10, 2, 2, ROLE.attention)
    // the lounge's floorboards: warmer than the office's tiles, the seams staggered row to row
    px(72, BAND, 59, 104 - BAND, ROLE.raised)
    for (let y = BAND + 3; y < 104; y += 4) { px(72, y, 59, 1, ROLE.edge); px(78 + ((y >> 2) % 3) * 19, y - 3, 1, 3, ROLE.edge) }
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
    const cols: Note[][] = boardColumns(a).map((col) => col.items.map((it): Note => {
      if (it.act.kind === "ticket")
        return { tip: `ticket #${it.act.id} ${it.title}\n${it.routed ? "with the manager to staff" : "click: send to the manager, or click a coworker to hand it over"}`, act: it.act, colour: it.routed ? ROLE.meta : ROLE.prose, mark: it.high ? ROLE.alarm : undefined, blink: it.act.id === armed }
      const id = it.act.kind === "thread" ? it.act.tid : 0
      return { tip: `#${id} ${it.title}\n${it.stage}${it.who ? ` · ${it.who}` : ""}${it.asks ? "\nwaiting on you" : ""}`, act: it.act, colour: it.who ? shirtOf({ archetype: it.archetype } as Seat) : ROLE.inactive, blink: it.asks }
    }))
    cols.forEach((list, c) => {
      const x0 = 5 + c * COL_W
      if (c) px(x0 - 2, 4, 1, 25, ROLE.edge)
      text(`${COLS[c]} ${list.length}`, ox + (x0 + 9) * S, 10 * S, ROLE.key, 9)
      // the header opens the column as a list under the scene, where the titles have room
      hits.push({ x: ox + (x0 - 1) * S, y: 3 * S, w: COL_W * S, h: 8 * S, tip: `${COLS[c].toLowerCase()}: open as a list`, act: { kind: "column", col: c } })
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
      if (list.length > shown.filter(Boolean).length) text(`+${list.length - shown.filter(Boolean).length}`, ox + (x0 + 16) * S, 23 * S, ROLE.key, 9)
    })
    hits.push({ x: ox + 100 * S, y: 29 * S, w: 8 * S, h: 3 * S, tip: "new ticket", act: { kind: "pen" } })
    // the notes strip along the bottom of the board: one squiggle per note, newest first
    px(4, 23, 136, 1, ROLE.edge)
    const shownNotes = a.notes.slice(0, 12)
    shownNotes.forEach((n, i) => {
      const sx = 6 + i * 11
      const c = a.bench.find((b) => b.name === n.author)
      blit(SCRIBBLES[n.id % SCRIBBLES.length], sx, 25, { k: c ? shirtOf({ archetype: c.archetype } as Seat) : ROLE.prose })
      hits.push({ x: ox + sx * S, y: 24 * S, w: 10 * S, h: 5 * S, tip: `${n.author}: ${n.body}`, act: { kind: "notes" } })
    })
    if (!shownNotes.length) text("notes land here", ox + 72 * S, 28 * S, ROLE.inactive, 9)
    hits.push({ x: ox + 4 * S, y: 24 * S, w: 136 * S, h: 5 * S, tip: `${a.notes.length} note(s): open as a list`, act: { kind: "notes" } })

    // your office: glass on the lounge side, a door where the queue forms
    for (const [y0, y1] of [[BAND, DOOR_Y[0]], [DOOR_Y[1], 104]]) { px(70, y0, 1, y1 - y0, ROLE.edge); px(71, y0, 1, y1 - y0, ROLE.key) }
    px(0, 103, 72, 1, ROLE.structure)

    // the lounge: a rug between the TV and the couch, and the couch's seat (its back, toward you,
    // goes in front of whoever sits there)
    px(98, 50, 30, 7, ROLE.structure)
    px(99, 51, 28, 5, ROLE.borderInactive)
    for (let i = 0; i < 6; i++) px(101 + i * 5, 52 + (i % 2), 2, 2, ROLE.meta)
    px(98, 62, 28, 4, ROLE.borderInactive)

    // everything with a footprint, back to front
    type Item = { base: number; draw: () => void }
    const items: Item[] = []
    const overhead: (() => void)[] = []
    const balloons: (() => void)[] = []
    // what someone said, over their head: a few lines, clamped inside the room. Cairo's toy text
    // has no font fallback, so typographic punctuation goes to ASCII here (the card has the rest)
    const balloon = (said: string, cx: number, top: number) => {
      const flat = said.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, "-").replace(/…/g, "...")
        .replace(/[^\x20-\x7e]/g, "").replace(/\s+/g, " ").trim()
      const lines: string[] = []
      let line = ""
      for (const w of flat.split(" ")) {
        if ((line + " " + w).trim().length > 26) { lines.push(line); line = w } else line = (line + " " + w).trim()
        if (lines.length === 3) break
      }
      if (lines.length < 3 && line) lines.push(line)
      if (lines.join(" ").length < flat.length) lines[lines.length - 1] = lines[lines.length - 1].slice(0, 23) + "..."
      cr.setFontSize(11)
      const lh = 14, bw = Math.max(...lines.map((l) => cr.textExtents(l).width)) + 14, bh = lines.length * lh + 8
      const bx = Math.min(Math.max(ox + cx * S - bw / 2, ox + 4), ox + W * S - bw - 4), by = Math.max(4, top * S - bh - 12)
      paint(ROLE.prose); cr.rectangle(bx, by, bw, bh); cr.fill()
      cr.rectangle(ox + cx * S - 3, by + bh, 6, 6); cr.fill()
      paint(ROLE.fieldInk)
      lines.forEach((l, i) => { cr.moveTo(bx + 7, by + 4 + (i + 1) * lh - 3); cr.showText(l) })
    }
    const using = (kind: Kind) => [...this.actors.values()].some((x) => x.spot.kind === kind && !x.moving)
    // the kitchenette along the glass: the water cooler, then the coffee machine on its cabinet
    items.push({ base: 66, draw: () => {
      blit(COOLER, 73, 50, { k: ROLE.key, m: ROLE.prose, a: ROLE.alarm, o: ROLE.inactive })
      if (using("cooler") && f % 3 === 0) px(75 + (f % 2) * 2, 51, 1, 1, ROLE.ground)
    } })
    items.push({ base: 82, draw: () => {
      px(72, 76, 9, 6, ROLE.structure); px(72, 76, 9, 1, ROLE.borderInactive)
      blit(COFFEE, 73, 69, { m: ROLE.inactive, l: ROLE.live, c: ROLE.prose })
      if (using("coffee")) blit(f % 2 ? ["v.v", ".v."] : [".v.", "v.v"], 75, 66, { v: ROLE.prose })
    } })
    // the TV against the front wall, facing the couch: a show while someone sits there, dark otherwise
    items.push({ base: 49, draw: () => {
      px(102, 44, 24, 3, ROLE.structure); px(103, 47, 2, 2, ROLE.structure); px(123, 47, 2, 2, ROLE.structure)
      px(105, 34, 18, 10, ROLE.inactive)
      if (using("couch")) {
        px(106, 35, 16, 4, ROLE.key); px(106, 39, 16, 4, ROLE.live)
        px(106 + ((f * 3) % 15), 37 - (f % 2), 2, 2, ROLE.body)
      } else { px(106, 35, 16, 8, ROLE.ground); px(119, 36, 2, 1, ROLE.edge) }
    } })
    // a floor lamp by the couch, its shade lit
    items.push({ base: 72, draw: () => {
      px(92, 56, 1, 16, ROLE.inactive); px(91, 72, 3, 1, ROLE.inactive)
      blit(["sssss", ".sss."], 90, 53, { s: ROLE.body })
    } })
    // the couch's back and arms, between you and whoever watches
    items.push({ base: 72.5, draw: () => {
      px(96, 66, 32, 7, ROLE.structure); px(97, 67, 30, 1, ROLE.borderInactive)
      px(95, 62, 3, 11, ROLE.structure); px(126, 62, 3, 11, ROLE.structure)
      px(98, 73, 2, 2, ROLE.structure); px(124, 73, 2, 2, ROLE.structure)
    } })
    items.push({ base: 101, draw: () => blit(BIG_PLANT, 2, 90, { l: ROLE.live, o: ROLE.structure }) })
    items.push({ base: 99, draw: () => blit(BIG_PLANT, 118, 88, { l: ROLE.live, o: ROLE.structure }) })
    items.push({ base: height - 2, draw: () => blit(BIG_PLANT, 2, height - 13, { l: ROLE.live, o: ROLE.structure }) })

    const actorAt = (d: Desk) => (d.seat ? this.actors.get(keyOf(d.seat)) : undefined)
    const screen = (mx: number, my: number, on: boolean, asks: boolean, seed: number) => {
      blit(MONITOR, mx, my, { o: ROLE.inactive })
      if (asks) px(mx + 1, my + 1, 8, 5, f % 2 ? ROLE.attention : ROLE.raised)
      else if (on) {
        px(mx + 1, my + 1, 8, 5, ROLE.ground)
        for (let l = 0; l < 3; l++) px(mx + 2, my + 1 + l * 2, 1 + ((f + l * 3 + seed) % 6), 1, ROLE.live)
      } else {
        px(mx + 1, my + 1, 8, 5, ROLE.ground)
        px(mx + 1 + Math.abs((f + seed) % 14 - 7), my + 1 + Math.abs((f + seed) % 8 - 4), 1, 1, ROLE.key)
      }
    }
    const decor = (look: Look, x: number, top: number) => {
      const dec = DECOR[look.decor]
      blit(dec, x - dec[0].length, top - dec.length, { l: ROLE.live, o: ROLE.structure, m: ROLE.prose, y: ROLE.body, a: ROLE.attention, k: ROLE.key })
      if (look.decor === 1) blit(f % 2 ? ["v.v.", ".v.."] : [".v.v", "..v."], x - 5, top - 6, { v: ROLE.inactive })
    }
    for (const d of desks) {
      const sx = seatX(d)
      if (d.kind === "boss") {
        // you: the corner office's big desk on its rug, a throne of a chair in your colour, three
        // screens (their backs to us) and a trophy — the one desk better than the manager's
        items.push({ base: d.y + 2, draw: () => {
          px(sx - 11, d.y - 2, 22, 20, ROLE.body); px(sx - 10, d.y - 1, 20, 18, ROLE.structure)
          for (let i = 0; i < 3; i++) px(sx - 7 + i * 6, d.y + 1, 2, 2, ROLE.body)
        } })
        items.push({ base: d.y + 25, draw: () => {
          blit(figure(BOSS_LOOK, null, false, true, "down", "sit", 0, (f + BOSS_LOOK.blink) % 13 === 0), sx - 6, d.y + 5, this.paints(ROLE.attention, BOSS_LOOK))
        } })
        items.push({ base: d.y + 30, draw: () => {
          for (const mx of [d.x + 2, sx - 26, d.x + d.w - 26]) { px(mx, d.y + 11, 10, 7, ROLE.inactive); px(mx + 1, d.y + 12, 8, 5, ROLE.edge); px(mx + 4, d.y + 18, 2, 1, ROLE.inactive) }
          px(d.x, d.y + 19, d.w, 2, ROLE.structure)
          px(d.x, d.y + 21, d.w, 1, ROLE.body)
          px(d.x + 1, d.y + 22, d.w - 2, 9, ROLE.borderInactive)
          px(d.x + 8, d.y + 24, d.w - 16, 5, ROLE.structure); px(d.x + 9, d.y + 25, d.w - 18, 3, ROLE.body)
          blit([".yyy.", "yyyyy", ".yyy.", "..y..", ".yyy."], d.x + d.w - 14, d.y + 14, { y: ROLE.body })
          decor(BOSS_LOOK, d.x + d.w - 2, d.y + 19)
          text(a.awaiting ? `you - ${a.awaiting} waiting` : "you", ox + (d.x + d.w / 2) * S, (d.y + 38) * S - 2, ROLE.attention)
          hits.push({ x: ox + d.x * S, y: (d.y + 4) * S, w: d.w * S, h: 30 * S, tip: "you: hire, file, workspaces, what waits on you", act: { kind: "boss" } })
        } })
        continue
      }
      if (d.kind === "manager") {
        // the manager's desk: a high-backed chair, a wide desk trimmed in gold, two screens and a
        // lamp; they sit behind it facing the floor, like you do in your office
        const owner = actorAt(d)
        const there = !!owner && owner.spot.kind === "desk" && !owner.path.length
        items.push({ base: d.y + 16, draw: () => {
          px(sx - 7, d.y + 1, 14, 16, ROLE.structure); px(sx - 6, d.y + 2, 12, 14, ROLE.borderInactive)
          px(sx - 7, d.y + 1, 14, 1, ROLE.body)
        } })
        items.push({ base: d.y + 31, draw: () => {
          for (const mx of [sx - 14, sx + 4]) { px(mx, d.y + 11, 10, 7, ROLE.inactive); px(mx + 1, d.y + 12, 8, 5, ROLE.edge); px(mx + 4, d.y + 18, 2, 1, ROLE.inactive) }
          px(d.x + 1, d.y + 19, d.w - 2, 2, ROLE.structure)
          px(d.x + 1, d.y + 21, d.w - 2, 1, ROLE.body)
          px(d.x + 2, d.y + 22, d.w - 4, 9, ROLE.borderInactive)
          px(d.x + 8, d.y + 25, 4, 1, ROLE.body); px(d.x + d.w - 12, d.y + 25, 4, 1, ROLE.body)
          blit(["sss.", ".s..", ".s..", "ooo."], d.x + d.w - 6, d.y + 15, { s: ROLE.body, o: ROLE.inactive })
        } })
        items.push({ base: d.y + 32, draw: () => {
          text(plate(d.seat!.agent, "(manager)", d.w * S - 6), ox + (d.x + d.w / 2) * S, (d.y + 38) * S - 2, there ? shirtOf(d.seat) : ROLE.inactive)
          hits.push({ x: ox + d.x * S, y: d.y * S, w: d.w * S, h: (ROW_H - 1) * S, tip: this.tip(d.seat!, threadOf(d.seat!.thread_id), there ? "at the manager's desk" : "about the office"), act: { kind: "thread", tid: d.seat!.thread_id } })
        } })
        continue
      }
      const owner = actorAt(d)
      const seated = !!owner && owner.spot.kind === "desk" && !owner.path.length
      const asks = !!d.seat && needsYou(threadOf(d.seat.thread_id))
      // the desk with its monitor across it facing the chair, then the chair (empty, it shows)
      items.push({ base: d.y + 22, draw: () => {
        screen(sx - 5, d.y + 3, seated, asks, d.seat?.thread_id ?? d.x)
        px(d.x, d.y + 12, d.w, 2, ROLE.structure)
        px(d.x + 1, d.y + 14, d.w - 2, 8, ROLE.borderInactive)
        px(d.x + d.w - 10, d.y + 17, 6, 1, ROLE.structure)
        if (owner) decor(owner.look, d.x + d.w - 3, d.y + 12)
      } })
      items.push({ base: d.y + 27, draw: () => { px(sx - 5, d.y + 24, 10, 5, ROLE.inactive); px(sx - 4, d.y + 25, 8, 3, ROLE.edge) } })
      items.push({ base: d.y + 30, draw: () => {
        const name = plate(d.seat!.agent, `#${d.seat!.thread_id}`, d.w * S - 6)
        text(name, ox + (d.x + d.w / 2) * S, (d.y + 38) * S - 2, asks ? ROLE.attention : seated ? shirtOf(d.seat) : ROLE.inactive)
        const hx = ox + d.x * S - 2, hy = d.y * S, hw = d.w * S + 4, hh = (ROW_H - 1) * S
        const where = !owner ? "" : owner.spot.kind === "desk" ? (owner.path.length ? "headed to the desk" : "working") : owner.spot.kind === "queue" ? "in your queue" : owner.leaving ? "leaving" : `idle, at the ${owner.spot.kind}`
        hits.push({ x: hx, y: hy, w: hw, h: hh, tip: this.tip(d.seat!, threadOf(d.seat!.thread_id), where), act: { kind: "thread", tid: d.seat!.thread_id } })
        if (d.seat!.thread_id === picked) {
          ink.push(() => {
            paint(ROLE.body); cr.setLineWidth(2)
            for (const [x0, y0, gx, gy] of [[hx, hy, 1, 1], [hx + hw, hy, -1, 1], [hx, hy + hh, 1, -1], [hx + hw, hy + hh, -1, -1]]) {
              cr.moveTo(x0 + gx * 10, y0); cr.lineTo(x0, y0); cr.lineTo(x0, y0 + gy * 10); cr.stroke()
            }
          })
        }
      } })
    }

    const queued = [...this.actors.values()].filter((x) => x.spot.kind === "queue")
    for (const actor of this.actors.values()) {
      const seat = actor.seat
      const sitting = actor.pose === "sit" && !actor.moving
      const couch = actor.pose === "couch" && !actor.moving
      const step = actor.moving ? 1 + (Math.floor(t / 2) % 2) : 0
      const shut = (f + actor.look.blink) % 13 === 0
      // seated, at a desk or on the couch, they face away from you — toward the screen, toward
      // the TV — and turn round only to talk with you
      const talking = this.talk.has(seat.agent)
      const working = sitting && seat.warm && !talking && actor.spot.face === "up"
      const rows = figure(actor.look, seat.archetype, !!seat.lead, false, sitting ? (talking || actor.spot.face === "down" ? "down" : "up") : couch ? "up" : actor.face, sitting || couch ? "sit" : "stand", step, shut)
      const top = sitting || couch ? actor.y - 14 : actor.y - 20 + (actor.moving && step === 2 ? -1 : 0)
      const left = actor.x - 6
      const th = threadOf(seat.thread_id)
      items.push({ base: sitting ? actor.y : actor.y + 0.5, draw: () => {
        blit(rows, left, top, this.paints(shirtOf(seat), actor.look))
        if (working) {
          // typing: their elbows, out past their shoulders, take turns
          const up = (f + actor.x) % 2 === 0
          px(left, top + 11 - (up ? 1 : 0), 1, 1, ROLE.prose)
          px(left + 11, top + 11 - (up ? 0 : 1), 1, 1, ROLE.prose)
        }
      } })
      const agentId = a.bench.find((c) => c.name === seat.agent)?.agent_id ?? null
      people.push({ x: ox + left * S, y: top * S, w: 12 * S, h: (sitting ? 14 : 20) * S, tip: this.tip(seat, th, actor.spot.kind === "queue" ? "in your queue" : actor.moving ? "walking" : `at the ${actor.spot.kind}`), act: { kind: "person", agentId, name: seat.agent, tid: seat.thread_id > 0 ? seat.thread_id : null } })
      const talk = this.talk.get(seat.agent)
      if (talk?.text) balloons.push(() => balloon(talk.text!, actor.x, top))
      overhead.push(() => {
        let above = top - 9
        const bob = f % 2
        if (talk && talk.text === null) {
          blit(BUBBLE, left + 3, above + bob, { a: ROLE.prose })
          blit(GLYPH["…"], left + 4, above + 1 + bob, { k: ROLE.fieldInk })
        } else if (actor.spot.kind === "queue" && !actor.moving) {
          blit(BUBBLE, left + 3, above + bob, { a: ROLE.attention })
          blit(GLYPH["!"], left + 4, above + 1 + bob, { k: ROLE.fieldInk })
        } else if (actor.emote) {
          blit(BUBBLE, left + 3, above, { a: ROLE.prose })
          blit(GLYPH[actor.emote] ?? GLYPH["…"], left + 4, above + 1, { k: ROLE.fieldInk })
        } else above = top - 1
        if (focus ? seat.agent === focus : seat.thread_id === picked) blit(ARROW, left + 4, above - 4 - bob, { v: ROLE.body })
      })
    }
    if (queued.length > QUEUE.length) overhead.push(() => text(`+${queued.length - QUEUE.length + 1}`, ox + 104 * S, 82 * S, ROLE.attention))

    items.sort((p, q) => p.base - q.base).forEach((x) => x.draw())
    overhead.forEach((d) => d())
    if (!a.ok || (a.roster.length === 0 && a.bench.length === 0)) text(a.ok ? "nobody on the clock" : (a.note ?? "channel down"), ox + (W * S) / 2, (FLOOR + 20) * S, a.ok ? ROLE.inactive : ROLE.alarm)
    const art = GdkPixbuf.Pixbuf.new_from_bytes(new GLib.Bytes(buf), GdkPixbuf.Colorspace.RGB, true, 8, W, height, W * 4)
    cr.save(); cr.translate(ox, 0); cr.scale(S, S)
    Gdk.cairo_set_source_pixbuf(cr, art, 0, 0)
    ;(cr.getSource() as Cairo.SurfacePattern).setFilter(Cairo.Filter.NEAREST)
    cr.paint(); cr.restore()
    cr.selectFontFace("ComicShannsMono Nerd Font", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
    ink.forEach((d) => d())
    balloons.forEach((d) => d())
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
