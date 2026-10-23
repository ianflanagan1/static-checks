#!/bin/sh
# Behaviour of the three hooks, against throwaway projects using real devbox and git. Run with tests/run.sh.

root=$(cd "$(dirname "$0")/.." && pwd)
lint_hook=$root/scripts/lint-edited-file.sh
stop_hook=$root/scripts/check-before-stop.sh
start_hook=$root/scripts/baseline-reminder.sh

setUp() {
    work=$(mktemp -d)
    export STATIC_CHECKS_STATE_DIR="$work/state"
    project=$work/project
    mkdir -p "$project/src"
    log=$work/log
}

tearDown() {
    rm -rf "$work"
}

# devbox_scripts json: a devbox.json in the project with these scripts.
devbox_scripts() {
    printf '{"packages":[],"shell":{"scripts":%s}}\n' "$1" >"$project/devbox.json"
}

# committed: makes the project a git repo with everything committed, devbox's lockfile included, as in a real project.
committed() {
    echo .devbox/ >"$project/.gitignore"
    (cd "$project" && devbox install >/dev/null 2>&1)
    git -C "$project" init -q
    git -C "$project" add -A
    git -C "$project" -c user.name=t -c user.email=t@t commit -qm init
}

edit() {
    jq -n --arg f "$1" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$f}}' | bash "$lint_hook"
}

stop() {
    jq -n --arg d "$project" --argjson a "${1:-false}" '{hook_event_name:"Stop",cwd:$d,stop_hook_active:$a}' | bash "$stop_hook"
}

start() {
    jq -n --arg d "$project" '{hook_event_name:"SessionStart",cwd:$d}' | bash "$start_hook"
}

# --- lint on edit

test_an_edited_file_is_passed_to_the_projects_lint_file_script() {
    devbox_scripts "{\"lint-file\":\"echo \\\"\$@\\\" >> $log\"}"
    echo x >"$project/src/a.ts"
    edit "$project/src/a.ts" 2>/dev/null
    assertEquals 0 $?
    assertEquals "$project/src/a.ts" "$(cat "$log")"
}

test_lint_problems_are_shown_to_claude_with_the_file_named() {
    devbox_scripts '{"lint-file":"echo \"1:1 error Use a union\"; exit 1"}'
    echo x >"$project/src/a.ts"
    reason=$(edit "$project/src/a.ts" 2>&1 >/dev/null)
    assertEquals 2 "$(edit "$project/src/a.ts" >/dev/null 2>&1; echo $?)"
    assertContains "$reason" "problems in $project/src/a.ts"
    assertContains "$reason" '1:1 error Use a union'
    assertNotContains "$reason" 'Info: '
}

test_a_project_without_a_lint_file_script_is_left_alone() {
    devbox_scripts '{"check":"exit 1"}'
    echo x >"$project/src/a.ts"
    edit "$project/src/a.ts" 2>/dev/null
    assertEquals 0 $?
}

test_a_file_outside_any_devbox_project_is_left_alone() {
    echo x >"$work/loose.ts"
    edit "$work/loose.ts" 2>/dev/null
    assertEquals 0 $?
}

# --- check before stopping

test_a_failing_check_sends_claude_back_with_its_output() {
    devbox_scripts '{"check":"echo \"3 tests failed\"; exit 1"}'
    committed
    echo change >"$project/src/new.ts"
    out=$(stop)
    assertEquals block "$(printf '%s' "$out" | jq -r .decision)"
    assertContains "$(printf '%s' "$out" | jq -r .reason)" '3 tests failed'
}

test_a_passing_check_lets_claude_finish() {
    devbox_scripts '{"check":"true"}'
    committed
    echo change >"$project/src/new.ts"
    assertEquals '' "$(stop)"
}

test_an_unchanged_working_tree_is_not_checked() {
    devbox_scripts "{\"check\":\"echo ran >> $log\"}"
    committed
    stop >/dev/null
    assertFalse 'check ran on a clean tree' "[ -f '$log' ]"
}

test_a_tree_that_already_passed_is_not_checked_again() {
    devbox_scripts "{\"check\":\"echo ran >> $log\"}"
    committed
    echo change >"$project/src/new.ts"
    stop >/dev/null
    stop >/dev/null
    assertEquals 1 "$(wc -l <"$log" | tr -d ' ')"
    echo more >>"$project/src/new.ts"
    stop >/dev/null
    assertEquals 2 "$(wc -l <"$log" | tr -d ' ')"
}

test_checking_leaves_the_real_index_untouched() {
    devbox_scripts '{"check":"true"}'
    committed
    echo change >"$project/src/new.ts"
    stop >/dev/null
    assertEquals '?? src/new.ts' "$(git -C "$project" status --porcelain --untracked-files=all)"
}

test_a_check_claude_cannot_fix_stops_blocking_and_warns_the_user() {
    devbox_scripts '{"check":"exit 1"}'
    committed
    echo change >"$project/src/new.ts"
    stop >/dev/null
    stop true >/dev/null
    stop true >/dev/null
    out=$(stop true)
    assertEquals null "$(printf '%s' "$out" | jq -r .decision)"
    assertContains "$(printf '%s' "$out" | jq -r .systemMessage)" 'still fails after 3 attempts'
}

test_a_new_turn_resets_the_attempts() {
    devbox_scripts '{"check":"exit 1"}'
    committed
    echo change >"$project/src/new.ts"
    stop >/dev/null
    stop true >/dev/null
    stop true >/dev/null
    stop true >/dev/null
    assertEquals block "$(stop | jq -r .decision)"
}

test_a_project_without_a_check_script_is_left_alone() {
    devbox_scripts '{"lint-file":"true"}'
    committed
    echo change >"$project/src/new.ts"
    assertEquals '' "$(stop)"
}

# --- reminder at session start

test_a_typescript_project_without_the_baseline_is_pointed_at_it() {
    echo '{"name":"x","devDependencies":{"eslint":"^10"}}' >"$project/package.json"
    echo '{}' >"$project/tsconfig.json"
    out=$(start)
    assertContains "$out" '@ianflanagan1/ts-baseline'
    # shellcheck disable=SC2016 # the backticks are literal
    assertContains "$out" 'no `lint-file` devbox script'
    assertContains "$out" 'do not add them unasked'
}

test_a_typescript_project_on_the_baseline_gets_no_reminder() {
    echo '{"name":"x","devDependencies":{"@ianflanagan1/ts-baseline":"^0.1.0"}}' >"$project/package.json"
    echo '{}' >"$project/tsconfig.json"
    assertEquals '' "$(start)"
}

test_the_baseline_package_itself_gets_no_reminder() {
    echo '{"name":"@ianflanagan1/ts-baseline"}' >"$project/package.json"
    echo '{}' >"$project/tsconfig.json"
    assertEquals '' "$(start)"
}

test_a_project_in_another_language_gets_no_reminder() {
    echo '{}' >"$project/composer.json"
    assertEquals '' "$(start)"
}

# shellcheck disable=SC1090
. "${SHUNIT2:-$(command -v shunit2)}"
