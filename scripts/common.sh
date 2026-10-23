#!/bin/bash
# Shared by the hooks: finding the project and the devbox scripts it defines.

# project_root dir: the nearest directory at or above dir holding a devbox.json, or nothing.
project_root() {
    dir=$1
    while [ -n "$dir" ] && [ "$dir" != / ]; do
        if [ -f "$dir/devbox.json" ]; then
            printf '%s\n' "$dir"
            return
        fi
        dir=$(dirname "$dir")
    done
}

# has_script root name: whether root's devbox.json defines the script. devbox.json may hold comments, which jq
# can't read, so a file jq rejects counts as having no scripts.
has_script() {
    jq -e --arg s "$2" '.shell.scripts[$s] != null' "$1/devbox.json" >/dev/null 2>&1
}

# run_script root name args...: runs a devbox script from the project root, dropping devbox's own "Info:" lines.
run_script() {
    root=$1
    shift
    (cd "$root" && devbox run "$@" 2>&1) | grep -v '^Info: '
    return "${PIPESTATUS[0]}"
}

require_tools() {
    for tool in jq devbox git; do
        if ! command -v "$tool" >/dev/null; then
            echo "static-checks: $tool not found, so $1 is not running" >&2
            exit 1
        fi
    done
}
