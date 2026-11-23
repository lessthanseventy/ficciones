#!/usr/bin/env bash
# Seed Asterion's own files from the machine's agenix secrets, once: the calendar feed address and
# its own Telegram bot's token. A file is written only when absent, so what Asterion's settings
# screen changes later is never overwritten; mode 0600, as Asterion keeps them.
# File names and keys are Asterion's `user://` stores: tlon/house/calendar_feed.gd (`house_calendar.json`
# {"url"}) and tlon/house/telegram.gd (`house_telegram.json` {"token", ...}).
# Plaid needs nothing here: Asterion reads $XDG_RUNTIME_DIR/agenix/plaid-* itself.
# The login entry stays Asterion's own (its Background setting writes ~/.config/autostart/asterion.desktop).
set -euo pipefail

agenix="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agenix"
data="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Asterion"

seed() {
	local file=$1 key=$2 secret=$3
	[ -s "$agenix/$secret" ] || return 0
	[ -e "$data/$file" ] && return 0
	mkdir -p "$data"
	(umask 077 && jq -n --arg v "$(tr -d '\n' <"$agenix/$secret")" "{\"$key\": \$v}" >"$data/$file")
	echo "asterion-seed: $file from $secret"
}

seed house_calendar.json url calendar-work
seed house_telegram.json token asterion-telegram-token
