#!/usr/bin/env bash
# Run every headless test suite. Usage: GODOT=/path/to/godot-4.4.1 tools/run_tests.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
for suite in smoke_test platform_tests ar_tests surface_tests field_tests box_tests touch_tests fit_tests anchor_tests ttt_tests stack_tests view_tests recovery_tests orientation_tests swipe_tests mage_run_tests; do
	out="$("$GODOT" --headless --path . "res://tests/$suite.tscn" 2>&1)"
	code=$?
	echo "$out" | grep -E "^FAIL" || true
	echo "$out" | grep -E "passed, [0-9]+ failed" || echo "$suite: no result (exit $code)"
	[ $code -eq 0 ] || status=1
done
exit $status
