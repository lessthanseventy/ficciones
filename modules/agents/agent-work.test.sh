#!/usr/bin/env bash
# agent-work.sh runs Claude Code's command string, shell syntax intact, on the E-cores only
wrap="$(cd "$(dirname "$0")" && pwd)/agent-work.sh"
ecores=$(cat /sys/devices/cpu_atom/cpus 2>/dev/null)
bad=0
is() {
	if [ "$2" = "$3" ]; then echo "ok    $1"; else
		echo "WRONG $1: got '$2', want '$3'"
		bad=1
	fi
}
is "shell syntax survives" "$(bash "$wrap" 'x=7; set -- a b; echo "$x ${x} $2 $?"')" "7 7 b 0"
is "exit status passes through" "$(
	bash "$wrap" 'exit 3'
	echo $?
)" "3"
is "stderr passes through" "$(bash "$wrap" 'echo e >&2' 2>&1)" "e"
got=$(bash "$wrap" 'grep Cpus_allowed_list /proc/self/status' | awk '{print $2}')
if [ -n "$ecores" ]; then
	is "pinned to the E-cores" "$got" "$ecores"
else
	is "no E-cores: left unpinned" "$got" "$(grep Cpus_allowed_list /proc/self/status | awk '{print $2}')"
fi
exit $bad
