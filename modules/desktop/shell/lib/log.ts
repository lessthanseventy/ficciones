// The command log: what just happened, one line each, the way lazygit's log shows the git it
// ran. Sources colour the line (design: the bottom deck) — the shell's own actions, notices,
// agent events, Hyprland's events, journal warnings. Bounded; the deck's row shows the tail,
// its drawer the lot with source filters.
import { createState } from "ags"
import { execAsync } from "ags/process"
import Notifd from "gi://AstalNotifd"
import Battery from "gi://AstalBattery"
import Network from "gi://AstalNetwork"
import Bluetooth from "gi://AstalBluetooth"
import { hypr } from "./hypr"

export type Src = "shell" | "notice" | "agent" | "hypr" | "journal" | "sys"
export type Level = "dim" | "normal" | "warn" | "crit"
export type Entry = { id: number; t: number; src: Src; text: string; level: Level; count: number }

const CAP = 400
let seq = 0
export const [log, setLog] = createState<Entry[]>([])

export function logEvent(src: Src, text: string, level: Level = "normal") {
  logAt(Date.now(), src, text, level)
}
/** A line with its own time — the backfill at start puts the past in order. */
export function logAt(t: number, src: Src, text: string, level: Level = "normal") {
  text = text.replace(/\s+/g, " ").trim()
  setLog((l) => {
    let i = l.length
    while (i > 0 && l[i - 1].t > t) i--
    // the same line again, right after: one entry, ×N (a unit repeating itself in the journal)
    const prev = l[i - 1]
    if (prev && prev.src === src && prev.text === text) {
      const n = [...l]; n[i - 1] = { ...prev, t, count: prev.count + 1 }
      return n
    }
    const e: Entry = { id: ++seq, t, src, text, level, count: 1 }
    const n = [...l.slice(0, i), e, ...l.slice(i)]
    return n.length > CAP ? n.slice(n.length - CAP) : n
  })
}
/** journal identifiers can be paths (/usr/lib/xdg-desktop-portal-…): the last segment */
export const unitName = (u: string) => u.replace(/\.service$/, "").split("/").pop() || u

export const hhmm = (t: number) => {
  const d = new Date(t)
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
}

// ── Hyprland: only what is rare and worth a line — monitors and config. Workspace switches
// and window open/close were tried and drowned the row (2026-09-07).
hypr.connect("event", (_, ev: string, args: string) => {
  switch (ev) {
    case "monitoradded": logEvent("hypr", `monitor ${args} plugged`); break
    case "monitorremoved": logEvent("hypr", `monitor ${args} gone`, "warn"); break
    case "configreloaded": logEvent("hypr", "config reloaded"); break
    case "screencast": { const [st, owner] = args.split(","); logEvent("hypr", `screen capture ${st === "1" ? "started" : "stopped"} (${owner === "1" ? "a window" : "a monitor"})`, st === "1" ? "warn" : "dim"); break }
  }
})

// ── the past, at start: the log is a viewer, not just a ticker ────────────────────────────
// notices still up, the journal at warning and above, pacman's last upgrades (Arch)
function backfill() {
  for (const n of Notifd.get_default().get_notifications()) {
    const u = n.urgency === Notifd.Urgency.CRITICAL ? "crit" : n.urgency === Notifd.Urgency.LOW ? "dim" : "normal"
    logAt(n.time * 1000, "notice", `${n.appName || "notice"}: ${n.summary}`, u)
  }
  const journal = (args: string[]) => execAsync(["journalctl", ...args, "-p", "4", "-n", "80", "-o", "json", "-q", "--no-pager"]).then((out) => {
    for (const l of out.trim().split("\n")) {
      try {
        const j = JSON.parse(l)
        const msg = typeof j.MESSAGE === "string" ? j.MESSAGE : "(binary)"
        const unit = unitName(String(j.SYSLOG_IDENTIFIER ?? j._SYSTEMD_UNIT ?? "?"))
        logAt(Number(j.__REALTIME_TIMESTAMP ?? 0) / 1000, "journal", `${unit}: ${msg}`, Number(j.PRIORITY ?? 4) <= 3 ? "crit" : "dim")
      } catch { /* not json */ }
    }
  }).catch(() => {})
  journal([]); journal(["--user"])
  execAsync(["tail", "-n", "600", "/var/log/pacman.log"]).then((out) => {
    const lines = out.split("\n").filter((l) => /\[ALPM\] (upgraded|installed|removed) /.test(l)).slice(-30)
    for (const l of lines) {
      const m = l.match(/^\[([^\]]+)\] \[ALPM\] (.*)$/)
      if (m) logAt(Date.parse(m[1]) || Date.now(), "sys", `pacman: ${m[2]}`, "dim")
    }
  }).catch(() => {})
}
backfill()

// ── sys: power, network, bluetooth — transitions only ─────────────────────────────────────
const bat = Battery.get_default()
let lowSaid = false
bat.connect("notify::charging", () => logEvent("sys", bat.charging ? "charging" : "on battery", "dim"))
bat.connect("notify::percentage", () => {
  const p = bat.percentage
  if (!bat.charging && p <= 0.1 && !lowSaid) { lowSaid = true; logEvent("sys", `battery ${Math.round(p * 100)}%`, "warn") }
  if (p > 0.15) lowSaid = false
})
const net = Network.get_default()
let ssid = net.wifi?.ssid ?? null
const netTick = () => {
  const now = net.wifi?.ssid ?? null
  if (now !== ssid) { logEvent("sys", now ? `wifi ${now}` : "wifi down", now ? "normal" : "warn"); ssid = now }
}
net.connect("notify::wifi", netTick)
net.wifi?.connect("notify::ssid", netTick)
const bt = Bluetooth.get_default()
const btHook = (d: Bluetooth.Device) => d.connect("notify::connected", () => logEvent("sys", `${d.alias || d.name} ${d.connected ? "connected" : "disconnected"}`, "dim"))
for (const d of bt.get_devices()) btHook(d)
bt.connect("device-added", (_, d: Bluetooth.Device) => btHook(d))
