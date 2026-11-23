# shellcheck shell=bash
"$ASTERION_SEED"
cd "$ASTERION_REPO" || {
	echo "asterion: repo not found at $ASTERION_REPO" >&2
	exit 1
}
case "${1:-}" in
widget | demo)
	task="house:$1"
	shift
	;;
dev)
	task=house:run
	shift
	;;
*) task=house:app ;;
esac
exec mise --cd "$ASTERION_REPO" run "$task" -- "$@"
