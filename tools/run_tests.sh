#!/usr/bin/env bash
# Run every headless test suite. Usage: GODOT=/path/to/godot-4.4.1 tools/run_tests.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
suites=()
for suite in smoke_test platform_tests ar_tests surface_tests field_tests box_tests touch_tests fit_tests anchor_tests ttt_tests stack_tests view_tests recovery_tests tattoo_tests orientation_tests swipe_tests mage_run_tests lg_systems_tests; do
	suites+=("res://tests/$suite.tscn")
done
# Each game's own suites: games/<id>/tests/*_tests.tscn
for scene in games/*/tests/*_tests.tscn; do
	[ -e "$scene" ] && suites+=("res://$scene")
done
for path in "${suites[@]}"; do
	suite="$(basename "$path" .tscn)"
	out="$("$GODOT" --headless --path . "$path" 2>&1)"
	code=$?
	echo "$out" | grep -E "^FAIL" || true
	echo "$out" | grep -E "passed, [0-9]+ failed" || echo "$suite: no result (exit $code)"
	[ $code -eq 0 ] || status=1
done
exit $status
