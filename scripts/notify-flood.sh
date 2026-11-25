#!/usr/bin/env bash
# Sends N (default 1000) notifications to the live shell; then press the hub's "clear all" and time
# it to "all quiet".
set -euo pipefail
n=${1:-1000}
for i in $(seq "$n"); do notify-send -e -t 1 -a flood "flood $i" "body $i"; done
echo "sent $n; open the hub and press clear all, then time until it reads 'all quiet'"
