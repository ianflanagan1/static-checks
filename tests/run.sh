#!/bin/sh
# Run every tests/*_test.sh with shunit2.
#
# Usage: tests/run.sh [test file...]
#
# shunit2 comes from $SHUNIT2 or PATH: `devbox run test`, or install it (`brew install shunit2`,
# `apt install shunit2`) and run this directly.
#
# Exit status: 0 all passed, 1 any failed, 2 shunit2 not found.

set -o nounset

dir=$(cd "$(dirname "$0")" && pwd)
SHUNIT2=${SHUNIT2:-$(command -v shunit2 || true)}
[ -n "$SHUNIT2" ] || { echo 'shunit2 not found: run "devbox run test", or install shunit2' >&2; exit 2; }
export SHUNIT2

[ $# -gt 0 ] || set -- "$dir"/*_test.sh
failed=0
for t in "$@"; do
    echo "== $(basename "$t")"
    sh "$t" || failed=1
done
exit "$failed"
