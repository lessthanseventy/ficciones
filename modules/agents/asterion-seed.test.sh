#!/usr/bin/env bash
# asterion-seed.sh seeds each file once, from its own secret, at 0600
seed="$(cd "$(dirname "$0")" && pwd)/asterion-seed.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/run/agenix"
export XDG_RUNTIME_DIR="$work/run" XDG_DATA_HOME="$work/data"
d="$work/data/godot/app_userdata/Asterion"
bad=0
check() {
	if "$@"; then echo "ok    $*"; else
		echo "WRONG $*"
		bad=1
	fi
}
printf 'https://cal.example/x.ics\n' >"$work/run/agenix/calendar-work"

bash "$seed"
check test "$(jq -r .url "$d/house_calendar.json")" = "https://cal.example/x.ics"
check test "$(stat -c %a "$d/house_calendar.json")" = 600
check test ! -e "$d/house_telegram.json"

printf '222:asterion-bot\n' >"$work/run/agenix/asterion-telegram-token"
echo '{"url":"https://changed.example/y.ics"}' >"$d/house_calendar.json"
bash "$seed"
check test "$(jq -r .token "$d/house_telegram.json")" = "222:asterion-bot"
check test "$(stat -c %a "$d/house_telegram.json")" = 600
check test "$(jq -r .url "$d/house_calendar.json")" = "https://changed.example/y.ics"
exit $bad
