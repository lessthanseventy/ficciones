#!/usr/bin/env bash
# Claude Code's CLAUDE_CODE_SHELL_PREFIX: runs the command string it is handed on the E-cores,
# so a session's suites never queue the desktop behind them. No E-cores: runs it as is.
# AGENT_WORK marks what it runs: hyprland.lua keeps a marked process's windows off the screen.
export AGENT_WORK=1
ecores=$(cat /sys/devices/cpu_atom/cpus 2>/dev/null)
[ -n "$ecores" ] || exec "$SHELL" -c "$1"
exec taskset -c "$ecores" "$SHELL" -c "$1"
