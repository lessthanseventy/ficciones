#!/usr/bin/env bash
# Claude Code's CLAUDE_CODE_SHELL_PREFIX: runs the command string it is handed on the E-cores,
# so a session's suites never queue the desktop behind them. No E-cores: runs it as is.
# AGENT_WORK marks what it runs: hyprland.lua keeps a marked process's windows off the screen.
export AGENT_WORK=1
# nice ranks only inside a cgroup: this puts a session's commands below its own UI, and below
# the desktop wherever they share one. Work already lower stays where it is.
[ "$(nice)" -ge 10 ] || renice -n 10 -p $$ >/dev/null 2>&1
ionice -c 3 -p $$ 2>/dev/null
ecores=$(cat /sys/devices/cpu_atom/cpus 2>/dev/null)
[ -n "$ecores" ] || exec "$SHELL" -c "$1"
exec taskset -c "$ecores" "$SHELL" -c "$1"
