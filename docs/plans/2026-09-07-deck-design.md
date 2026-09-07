# The deck — the bottom of the screen (2026-09-07)

Built the same day; this is the record of what was decided.

**The row.** One line, bar-height, on every monitor, after the rail (the rail keeps the full
height; volume sits in the bottom-left corner). Left to right: pinned attention in inverse
video — critical notices (× to clear, "+N clear all" past three) and "N agents await you" —
then the command log's tail, newest on the right, then the ambient cells: now-playing, the
timer (always present: idle it opens presets + an entry, running it counts), the agents
count. Critical notices pin here instead of sticking as toasts; normal toasts stay at the top
right and also land in the log. No row on a monitor showing a fullscreen window.

**The log** (`lib/log.ts`): shell actions, notices, agent changes (diffs of the Tlön poll),
Hyprland events, journal lines at warning and above. Source colours: shell amber, notice
green, agent pink, hypr cyan, journal red. Bounded at 400.

**The drawer** (Super+C, bottom hot edge, a click on the log): one wide sheet — LOG with
source-filter chips over a virtualised list; MEDIA with transport and a picture (a live
capture of the player's window every 2 s while it is on screen, else the cover art); AGENTS;
TIMER. Media left the bar's popover and the dashboard; agents left the dashboard.

**The timer** (`lib/timer.ts`): countdown ("25m", "1h10"), alarm at a clock time ("14:30",
"9pm"), pomodoro (25/5 with a 15 every fourth, or "pomo 50/10"). Typed into the launcher or
the timer cell. The end is a critical notice.

Not done: a nav focus model for the drawer's panes (Tab cycling), keyboard on the log.
