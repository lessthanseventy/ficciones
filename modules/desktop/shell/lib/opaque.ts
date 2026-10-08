// Windows with video playing are opaque under glass (Andrew, 2026-09-06). Hyprland has no
// "playing video" state, so it is inferred every 2 s: an idle inhibitor (players ask for one),
// a process making sound (lib/sound, matched by pid; a multi-window app like
// the browser also needs a video-ish title, or every window of it would go opaque), a player
// class, or fullscreen. `setprop opaque` per window; `unset` when it stops. Any one playing turns
// glass off for every window but the terminals (lib/glass.ts), which this keeps glass while it is on.
import { soundPids } from "./sound"
import { L, dispatch } from "./hyprlua"
import { interval } from "ags/time"
import { query } from "./hyprsock"
import { glass, setVideoPlaying, glassOpacity } from "./glass"

type Client = { address: string; pid: number; class: string; title: string; mapped: boolean; inhibitingIdle?: boolean; fullscreen: number }

const PLAYERS = /^(mpv|vlc|io\.github\.celluloid|com\.github\.rafostar\.Clapper|org\.gnome\.Totem|haruna|jellyfinmediaplayer|plex)/i
const VIDEO_TITLE = /youtube|cineby|netflix|plex|jellyfin|twitch|vimeo|hulu|disney|prime video|crunchyroll|watch|video|stream|episode|\bS\d+ ?E\d+\b|dropout|max\b|peacock|paramount/i

const opaque = new Set<string>()
// a terminal is glass whenever glass is on, whatever the global opacity: its own value, absolute
const TERMINAL = /^com\.mitchellh\.ghostty$/
const termGlass = new Map<string, boolean>() // address → what was last set

// Which processes are making sound: PipeWire's running output streams (lib/sound) — Mpris
// said Paused for a streaming site with the audio live, and the video window stayed glass
// (2026-09-07).
function tick() {
  let clients: Client[]
  try { clients = JSON.parse(query("j/clients")) } catch { return }
  const pids = soundPids.peek()
  const perPid = new Map<number, number>()
  for (const c of clients) if (c.mapped) perPid.set(c.pid, (perPid.get(c.pid) ?? 0) + 1)
  const want = new Set<string>()
  for (const c of clients) {
    if (!c.mapped) continue
    const sound = pids.has(c.pid) && ((perPid.get(c.pid) ?? 0) === 1 || VIDEO_TITLE.test(c.title))
    if (c.inhibitingIdle || c.fullscreen > 0 || PLAYERS.test(c.class) || sound) want.add(c.address)
  }
  const cmds: string[] = []
  for (const a of want) if (!opaque.has(a)) { opaque.add(a); cmds.push(L.setProp(`address:${a}`, "opaque", "1")) }
  for (const a of [...opaque]) if (!want.has(a)) {
    opaque.delete(a)
    if (clients.some((c) => c.address === a)) cmds.push(L.setProp(`address:${a}`, "opaque", "unset"))
  }
  if (playingChanged(want)) setVideoPlaying(want.size > 0)
  const on = glass.peek()
  for (const c of clients) {
    if (!c.mapped || !TERMINAL.test(c.class) || c.title.endsWith("tlon office") || termGlass.get(c.address) === on) continue
    termGlass.set(c.address, on)
    const w = `address:${c.address}`
    cmds.push(...(on ? [L.setProp(w, "opacity_override", "1"), L.setProp(w, "opacity", glassOpacity())] : [L.setProp(w, "opacity", "1"), L.setProp(w, "opacity_override", "unset")]))
  }
  for (const a of [...termGlass.keys()]) if (!clients.some((c) => c.address === a)) termGlass.delete(a)
  if (cmds.length) dispatch(...cmds)
}

let wasPlaying = false
const playingChanged = (want: Set<string>) => { const now = want.size > 0, changed = now !== wasPlaying; wasPlaying = now; return changed }
glass.subscribe(tick)

interval(2000, tick)
