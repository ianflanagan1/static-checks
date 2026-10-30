#!/bin/bash
# Stop hook: runs the project's `check` task before Claude finishes a turn that changed files, and sends
# Claude back to fix what fails. A project without a `check` task is left alone.
#
# It skips the check when the working tree, untracked files included, matches HEAD or the last tree that passed, so
# a turn that changed nothing costs nothing. It blocks at most $max_attempts times in a row, so a failure Claude
# can't fix (a stopped database, say) ends with a warning to the user instead of a loop.

# shellcheck source=SCRIPTDIR/common.sh
. "$(dirname "$0")/common.sh"
require_tools "the check before stopping"

max_attempts=3
state_dir=${STATIC_CHECKS_STATE_DIR:-${TMPDIR:-/tmp}/static-checks}

input=$(cat)
cwd=$(printf '%s' "$input" | jq --raw-output '.cwd // empty')
continuing=$(printf '%s' "$input" | jq --raw-output '.stop_hook_active // false')

root=$(project_root "${cwd:-$PWD}")
[ -n "$root" ] || exit 0
kind=$(task_kind "$root" check)
[ -n "$kind" ] || exit 0
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# The working tree as a tree object, staged through a scratch index so the real one is untouched.
working_tree() {
    index=$(mktemp)
    cp "$(git -C "$root" rev-parse --absolute-git-dir)/index" "$index" 2>/dev/null
    GIT_INDEX_FILE=$index git -C "$root" add --all >/dev/null 2>&1
    GIT_INDEX_FILE=$index git -C "$root" write-tree
    rm -f "$index"
}

mkdir -p "$state_dir"
key=$(printf '%s' "$root" | cksum | cut -d' ' -f1)
passed_file=$state_dir/$key.passed
attempts_file=$state_dir/$key.attempts

tree=$(working_tree)
head_tree=$(git -C "$root" rev-parse --quiet --verify 'HEAD^{tree}' 2>/dev/null)
if [ "$tree" = "$head_tree" ] || [ "$tree" = "$(cat "$passed_file" 2>/dev/null)" ]; then
    exit 0
fi

[ "$continuing" = true ] || echo 0 >"$attempts_file"
attempts=$(cat "$attempts_file" 2>/dev/null || echo 0)

if output=$(run_task "$root" "$kind" check); then
    # Taken again, since a check may itself write files, such as a lockfile or generated code.
    working_tree >"$passed_file"
    echo 0 >"$attempts_file"
    exit 0
fi

if [ "$attempts" -ge "$max_attempts" ]; then
    jq --null-input --arg m "static-checks: check still fails after $max_attempts attempts to fix it." '{systemMessage: $m}'
    exit 0
fi
echo $((attempts + 1)) >"$attempts_file"

reason=$(printf 'check failed. Fix what it reports, then finish:\n%s' "$(printf '%s\n' "$output" | tail --lines 80)")
jq --null-input --arg r "$reason" '{decision: "block", reason: $r}'
