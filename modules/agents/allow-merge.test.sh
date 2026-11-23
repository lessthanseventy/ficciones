#!/usr/bin/env bash
# allow-merge.jq drops the rules the install wrote before, keeps hand-added ones and adds the current set
filter="$(cd "$(dirname "$0")" && pwd)/allow-merge.jq"
settings='{"permissions":{"allow":["stale","hand","kept","dead"]},"env":{"A":"1"}}'
got=$(jq -c --argjson prev '["stale","kept"]' --argjson dead '["dead"]' --argjson allow '["kept","new"]' \
	-f "$filter" <<<"$settings")
want='{"permissions":{"allow":["hand","kept","new"]},"env":{"A":"1"}}'
if [ "$got" = "$want" ]; then echo "ok    stale and dead dropped, hand kept, current present"; else
	echo "WRONG: $got"
	exit 1
fi
got=$(jq -c --argjson prev '[]' --argjson dead '[]' --argjson allow '["new"]' -f "$filter" <<<'{}')
if [ "$got" = '{"permissions":{"allow":["new"]}}' ]; then echo "ok    empty settings"; else
	echo "WRONG: $got"
	exit 1
fi
