// Windows with video playing are opaque under glass (Andrew, 2026-09-06). Hyprland has no
// "playing video" state, so it is inferred every 2 s: an idle inhibitor (players ask for one),
// a running PipeWire stream from the window's process (matched by pid; a multi-window app like
// the browser also needs a video-ish title, or every window of it would go opaque), a player
// class, or fullscreen. `setprop opaque` per window; `unset` when it stops.
import Wp from "gi://AstalWp"
import { L, dispatch } from "./hyprlua"
import { interval } from "ags/time"
import { query } from "./hyprsock"

type Client = { address: string; pid: number; class: string; title: string; mapped: boolean; inhibitingIdle?: boolean; fullscreen: number }

const PLAYERS = /^(mpv|vlc|io\.github\.celluloid|com\.github\.rafostar\.Clapper|org\.gnome\.Totem|haruna|jellyfinmediaplayer|plex)/i
const VIDEO_TITLE = /youtube|cineby|netflix|plex|jellyfin|twitch|vimeo|hulu|disney|prime video|crunchyroll|watch|video|stream|episode|\bS\d+ ?E\d+\b|dropout|max\b|peacock|paramount/i

const opaque = new Set<string>()

function playingPids(): Set<number> {
  const out = new Set<number>()
  const audio = Wp.get_default()?.audio
  if (!audio) return out
  for (const st of audio.get_streams()) {
    if (st.state !== Wp.NodeState.RUNNING) continue
    const pid = Number(st.get_pw_property("application.process.id") ?? 0)
    if (pid) out.add(pid)
  }
  return out
}

function tick() {
  let clients: Client[]
  try { clients = JSON.parse(query("j/clients")) } catch { return }
  const pids = playingPids()
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
  if (cmds.length) dispatch(...cmds)
}

interval(2000, tick)
