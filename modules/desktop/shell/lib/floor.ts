// The office as a still floor plan for the rail: the whiteboard, the plan's meters and the machine's
// queues, a desk for each live session (its screen and its line say what they are on), everyone else
// small in the lounge. Built from the kit's parts with no Sim: nobody walks, and a frame depends only
// on the snapshot, so nothing changes between polls.
import { fit, type Frame, type Measure } from "../office/kit/canvas"
import { boardColumns, crewOf, statusWord, tipOf, weekTrend, type Act, type Crew } from "../office/kit/crew"
import { Scene } from "../office/kit/draw"
import { overrideFor } from "../office/kit/looks"
import { ROLE, tint } from "../office/kit/palette"
import { ACTIVITY, figure, lookOf, paints, shirtOf } from "../office/kit/sprites"
import type { Agents, UsageWindow } from "../office/kit/types"
import { BOARD_H, DESK_H, DESKS_PER_ROW, HEAD_H, LOUNGE_H, LOUNGE_PER_ROW, STRIP_ROW, floorHeight, tiers } from "./floor-core"

export const W = 144
const COL_W = 23, STICKIES = 6

const lookFor = (name: string) => ({ ...lookOf(name), ...overrideFor(name) })
/** a window past its reset says nothing about now: its figure was for the window before */
const liveWindow = (w: UsageWindow | undefined, now: number) => (w && (!w.resets_at || Date.parse(w.resets_at) > now) ? w : undefined)

function meters(a: Agents, now: number) {
  const c = a.usage?.claude
  return ([["5h", liveWindow(c?.five_hour, now)], ["7d", liveWindow(c?.seven_day, now)]] as const).filter(([, w]) => w)
}
/** the one line of what the crew's work is up against, each fact only when it says something */
function facts(a: Agents, ws: string) {
  const open = a.ticket_open?.[ws]?.total, trend = weekTrend(a), triage = a.triage[ws] ?? 0, h = a.health
  const landing = h?.merge_queue?.length ?? 0, waits = h?.checks?.waiting.length ?? 0
  return [
    a.pause && a.pause !== "working" ? a.pause.replace("_", " ") : "",
    open ? `${open} open${trend ? ` ${trend}` : ""}` : "",
    triage ? `${triage} stuck` : "",
    h?.checks?.running ? `checking${waits ? ` +${waits}` : ""}` : "",
    landing ? `landing ${landing}` : "",
    h?.state === "warn" ? `${h.problems.length} warn` : "",
  ].filter(Boolean).join(" | ")
}

/** a coworker's tool as its still glyph: the frame of each that reads best when it holds */
const toolGlyph = (doing: string) => { const f = ACTIVITY[doing] ?? ACTIVITY.think!; return doing === "bash" ? f[0]! : f[f.length - 1]! }

export function renderFloor(a: Agents, ws: number | null, focus: { picked: number | null; person: string | null }, measure: Measure, now = Date.now()): Frame {
  const crew = crewOf(a), { desks, lounge } = tiers(crew)
  const usage = meters(a, now), line = ws === null ? "" : facts(a, String(ws))
  const stripRows = (usage.length ? 1 : 0) + (line ? 1 : 0)
  const sc = new Scene(W, floorHeight(desks.length, lounge.length, stripRows), 0)
  const px = sc.px.bind(sc), text = sc.text.bind(sc)
  const target = (x: number, y: number, w: number, h: number, tip: string, act: Act) => sc.hits.push({ x, y, w, h, tip, act })

  px(0, 0, W, sc.height, ROLE.ground)

  // the whiteboard: each stage's count, and a sticky for each thing in it in its coworker's colour
  px(0, 0, W, BOARD_H, ROLE.edge)
  px(2, 1, W - 4, BOARD_H - 3, ROLE.structure); px(3, 2, W - 6, BOARD_H - 5, ROLE.ground)
  boardColumns(a).forEach((col, c) => {
    const x0 = 3 + c * COL_W, mid = x0 + COL_W / 2
    if (c) px(x0 - 1, 3, 1, BOARD_H - 7, ROLE.edge)
    text(col.name.toLowerCase(), mid, 7, ROLE.key, 12)
    text(String(col.items.length), mid, 13, col.items.length ? ROLE.prose : ROLE.inactive, 15)
    col.items.slice(0, STICKIES).forEach((it, i) => {
      const sx = x0 + 2 + (i % 3) * 6, sy = 15 + Math.floor(i / 3) * 5
      px(sx, sy, 5, 4, it.asks ? ROLE.attention : it.who ? shirtOf(it.archetype) : ROLE.inactive)
      px(sx + 1, sy + 2, 3, 1, ROLE.fieldInk)
      target(sx, sy, 5, 4, `${it.title}\n${it.stage}${it.who ? ` · ${it.who}` : ""}${it.state ? `\n${it.state.why}` : ""}`, it.act.kind === "epic" ? { kind: "column", col: c } : it.act)
    })
    target(x0, 2, COL_W, BOARD_H - 5, `${col.name.toLowerCase()}: open as a list`, { kind: "column", col: c })
  })

  let y = BOARD_H
  if (usage.length) {
    usage.forEach(([name, w], i) => {
      const x = 3 + i * 71, pct = Math.round(w!.percent), hot = pct >= 80
      text(name, x, y + 5, ROLE.prose, 12, "left")
      px(x + 9, y + 2, 34, 3, ROLE.edge); px(x + 9, y + 2, Math.round(34 * Math.min(pct, 100) / 100), 3, hot ? ROLE.attention : ROLE.live)
      text(`${pct}%`, x + 45, y + 5, hot ? ROLE.attention : ROLE.prose, 12, "left")
    })
    y += STRIP_ROW
  }
  if (line) { text(fit(measure, line, W - 6, 12), 3, y + 5, ROLE.prose, 12, "left"); y += STRIP_ROW }

  const person = (c: Crew): Act => ({ kind: "person", agentId: a.bench.find((b) => b.name === c.name)?.agent_id ?? null, name: c.name, tid: c.thread })
  const tip = (c: Crew) => {
    const th = a.threads.find((t) => t.id === c.thread)
    return tipOf({ agent: c.name, thread_id: c.thread ?? 0, title: c.title, warm: false, archetype: c.archetype, lead: c.lead }, th, statusWord(c.status))
  }
  const isFocus = (c: Crew) => (focus.person ? focus.person === c.name : c.thread !== null && c.thread === focus.picked)
  const brackets = (x: number, y: number, w: number, h: number) => sc.ink.push({ t: "brackets", x, y, w, h, color: ROLE.body })

  // the floor: tiles, and a desk for each live session
  const deskRows = Math.max(1, Math.ceil(desks.length / DESKS_PER_ROW))
  const tileA = tint(ROLE.prose, ROLE.ground, 0.1), tileB = tint(ROLE.prose, ROLE.ground, 0.07)
  for (let ty = y; ty < y + HEAD_H + deskRows * DESK_H; ty += 6) for (let tx = 0; tx < W; tx += 6) px(tx, ty, 6, 6, ((tx + (ty - y)) / 6) % 2 ? tileA : tileB)
  const working = desks.filter((c) => c.status === "working").length
  text(desks.length ? `at desks ${desks.length} | ${working} working` : "at desks 0", 3, y + 5, ROLE.prose, 12, "left")
  y += HEAD_H
  if (!desks.length) text(a.ok ? "nobody at a desk" : (a.note ?? "channel down"), W / 2, y + DESK_H / 2, a.ok ? ROLE.prose : ROLE.alarm, 13)
  desks.forEach((c, i) => {
    const x = (i % DESKS_PER_ROW) * (W / DESKS_PER_ROW), top = y + Math.floor(i / DESKS_PER_ROW) * DESK_H
    const asks = c.status === "waiting", seat = a.roster.find((r) => r.agent === c.name && r.doing)
    if (asks) px(x + 1, top, 70, DESK_H - 1, tint(ROLE.attention, ROLE.ground, 0.3))
    px(x + 2, top + 5, 2, 12, ROLE.structure)
    sc.figure(figure(lookFor(c.name), c.archetype, c.lead, false, "right", "sit", 0, false), x + 3, top + 3, paints(shirtOf(c.archetype), lookFor(c.name)))
    px(x + 15, top + 4, 13, 10, ROLE.inactive); px(x + 16, top + 5, 11, 8, ROLE.edge); px(x + 20, top + 14, 3, 2, ROLE.inactive)
    if (asks) sc.blit(["k", "k", "k", ".", "k"], x + 21, top + 6, { k: ROLE.attention })
    else if (c.status === "working") sc.blit(toolGlyph(seat?.doing ?? "think"), x + 19, top + 6, { k: ROLE.live })
    else px(x + 21, top + 8, 1, 1, ROLE.inactive)
    px(x + 2, top + 16, 28, 2, ROLE.borderInactive); px(x + 3, top + 18, 1, 5, ROLE.structure); px(x + 28, top + 18, 1, 5, ROLE.structure)
    text(fit(measure, c.name, 40, 14), x + 31, top + 9, ROLE.prose, 14, "left")
    const word = asks ? "asks you" : c.status === "working" ? seat?.doing ?? "thinking" : "idle"
    text(word, x + 31, top + 15, asks ? ROLE.attention : c.status === "working" ? ROLE.live : ROLE.inactive, 12, "left")
    text(fit(measure, c.thread ? `#${c.thread} ${c.title}` : "on the bench", 68, 12), x + 2, top + 28, ROLE.prose, 12, "left")
    target(x, top, W / DESKS_PER_ROW, DESK_H, tip(c), person(c))
    if (isFocus(c)) brackets(x + 1, top, 70, DESK_H - 1)
  })
  y += deskRows * DESK_H

  // the lounge: floorboards, and a head and a name for everyone not on a session
  if (lounge.length) {
    const board = tint(ROLE.structure, ROLE.ground, 0.35), seam = tint(ROLE.structure, ROLE.ground, 0.2)
    px(0, y, W, sc.height - y, board)
    for (let by = y + 3; by < sc.height; by += 5) px(0, by, W, 1, seam)
    text(`lounge ${lounge.length}`, 3, y + 5, ROLE.prose, 12, "left")
    y += HEAD_H
    lounge.forEach((c, i) => {
      const x = (i % LOUNGE_PER_ROW) * (W / LOUNGE_PER_ROW), top = y + Math.floor(i / LOUNGE_PER_ROW) * LOUNGE_H
      const look = lookFor(c.name), dim = Object.fromEntries(Object.entries(paints(shirtOf(c.archetype), look)).map(([k, v]) => [k, tint(v, board, c.status === "off" ? 0.45 : 0.75)]))
      sc.figure(figure(look, c.archetype, c.lead, false, "down", "sit", 0, false).slice(0, 12), x + 12, top, dim)
      text(fit(measure, c.name, 34, 12), x + 18, top + 17, ROLE.prose, 12)
      target(x, top, W / LOUNGE_PER_ROW, LOUNGE_H, tip(c), person(c))
      if (isFocus(c)) brackets(x + 1, top, 34, LOUNGE_H - 1)
    })
  }
  return sc.finish()
}

/** how tall the plan draws this snapshot, in logical pixels, for the widget to ask for */
export function floorSize(a: Agents, ws: number | null, now = Date.now()) {
  const { desks, lounge } = tiers(crewOf(a))
  return floorHeight(desks.length, lounge.length, (meters(a, now).length ? 1 : 0) + (ws !== null && facts(a, String(ws)) ? 1 : 0))
}
