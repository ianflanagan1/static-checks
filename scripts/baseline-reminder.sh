#!/bin/bash
# SessionStart hook: tells Claude when the project in the session's directory is missing the shared static checks,
# so it can offer to add them. What it prints is added to Claude's context; it never changes the project.

# shellcheck source=SCRIPTDIR/common.sh
. "$(dirname "$0")/common.sh"
command -v jq >/dev/null || exit 0

cwd=$(jq -r '.cwd // empty')
dir=${cwd:-$PWD}
notes=()

# A TypeScript project uses @ianflanagan1/ts-baseline unless it is that package.
if [ -f "$dir/package.json" ] && [ -f "$dir/tsconfig.json" ]; then
    if ! jq -e '.name == "@ianflanagan1/ts-baseline" or (.devDependencies // {} | has("@ianflanagan1/ts-baseline"))' \
        "$dir/package.json" >/dev/null 2>&1; then
        notes+=("It is a TypeScript project without @ianflanagan1/ts-baseline, the shared ESLint, tsconfig and Prettier settings whose \`ts-baseline verify\` keeps it from drifting (https://github.com/ianflanagan1/ts-baseline).")
    fi
fi

if [ ${#notes[@]} -gt 0 ]; then
    root=$(project_root "$dir")
    if [ -z "$root" ] || ! has_script "$root" lint-file; then
        notes+=("It has no \`lint-file\` devbox script, so files are not linted as they are edited.")
    fi
    printf 'static-checks: this project is missing the shared static checks.\n'
    printf -- '- %s\n' "${notes[@]}"
    printf 'Mention this to the user once, and offer to add them; do not add them unasked.\n'
fi
