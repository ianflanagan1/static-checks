#!/bin/bash
# Shared by the hooks: finding the project and the tasks it defines.

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

# taskfile root: root's own Taskfile, or nothing. Left to itself, Task would also take one from a parent directory,
# which belongs to some other project.
taskfile() {
    for name in Taskfile.yml taskfile.yml Taskfile.yaml taskfile.yaml Taskfile.dist.yml taskfile.dist.yml \
        Taskfile.dist.yaml taskfile.dist.yaml; do
        if [ -f "$1/$name" ]; then
            printf '%s\n' "$1/$name"
            return
        fi
    done
}

# task_kind root name: how root defines the task: "task" in its Taskfile, "script" as a devbox script, or nothing.
# Devbox scripts are read only until every project has moved to a Taskfile. devbox.json may hold comments, which jq
# can't read, so a file jq rejects counts as having no scripts.
task_kind() {
    file=$(taskfile "$1")
    if [ -n "$file" ]; then
        if (cd "$1" && devbox run -- task --taskfile "$file" --list-all --json 2>/dev/null) |
            jq --exit-status --arg t "$2" 'any(.tasks[]; .name == $t)' >/dev/null 2>&1; then
            echo task
        fi
    elif jq --exit-status --arg s "$2" '.shell.scripts[$s] != null' "$1/devbox.json" >/dev/null 2>&1; then
        echo script
    fi
}

# run_task root kind name args...: runs a task, of the kind task_kind found, from the project root through devbox,
# dropping devbox's own "Info:" lines and the error line it adds when the task fails.
run_task() {
    root=$1
    kind=$2
    name=$3
    shift 3
    case $kind in
        task) (cd "$root" && devbox run -- task --taskfile "$(taskfile "$root")" --silent "$name" -- "$@" 2>&1) ;;
        script) (cd "$root" && devbox run "$name" "$@" 2>&1) ;;
    esac | grep --invert-match --regexp '^Info: ' --regexp '^Error: error running script .* in Devbox: '
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
