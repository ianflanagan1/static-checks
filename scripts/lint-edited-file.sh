#!/bin/bash
# PostToolUse hook for Edit, Write, MultiEdit and NotebookEdit: runs the project's `lint-file` task on the file just
# changed, so Claude sees a problem one edit after making it rather than at the end. Exit 2 shows stderr
# to Claude. A project without a `lint-file` task is left alone.

# shellcheck source=SCRIPTDIR/common.sh
. "$(dirname "$0")/common.sh"
require_tools "lint on edit"

file=$(jq --raw-output '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0

root=$(project_root "$(dirname "$file")")
[ -n "$root" ] || exit 0
kind=$(task_kind "$root" lint-file)
[ -n "$kind" ] || exit 0

if ! output=$(run_task "$root" "$kind" lint-file "$file"); then
    printf 'lint-file found problems in %s. Fix them before going on:\n%s\n' "$file" "$output" >&2
    exit 2
fi
