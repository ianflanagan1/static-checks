# static-checks

A Claude Code plugin that runs a project's own static checks while Claude works, so a problem comes back to Claude one edit after it's made rather than in review, and a rule enforced by a tool doesn't also need spelling out in Claude's instructions.

It runs only what the project defines, as [Task](https://taskfile.dev) tasks in the `Taskfile.yml` beside its `devbox.json`, run through [devbox](https://www.jetify.com/devbox), so it works for any language:

| Hook | When | What |
|---|---|---|
| `PostToolUse` | after each Edit, Write, MultiEdit or NotebookEdit | Runs `devbox run -- task lint-file -- <file>` in the project holding the file. On failure, Claude is shown the output (exit 2) and fixes it before going on. |
| `Stop` | when Claude is about to finish a turn | Runs `devbox run -- task check`. On failure, Claude is sent back with the last 80 lines of output. |
| `SessionStart` | at the start of a session | Tells Claude when the project is missing the shared baseline ([`@ianflanagan1/ts-baseline`](https://github.com/ianflanagan1/ts-baseline) for TypeScript), so it can offer to add it. It never changes the project. |

A project without a `lint-file` or `check` task is left alone by that hook. Until every project has moved to a Taskfile, a project without one still has its `lint-file` and `check` devbox scripts run instead.

## The tasks a project defines

- `lint-file`: formats, fixes and lints the files given after `--`, exiting non-zero on what it couldn't fix. Task passes them as `CLI_ARGS_LIST`; quote each one, since a path can hold spaces. Keep it fast, since it runs on every edit. For TypeScript:

  ```yaml
  lint-file:
    vars:
      FILES: '{{range .CLI_ARGS_LIST}}{{shellQuote .}} {{end}}'
    cmds:
      - pnpm exec prettier --write --ignore-unknown --log-level warn {{.FILES}}
      - pnpm exec eslint --fix --max-warnings 0 --no-warn-ignored {{.FILES}}
  ```

- `check`: everything: formatting, type checks, linters, tests. The same task CI runs.

## Not checking twice

The `Stop` hook skips the check when the working tree, untracked files included, matches `HEAD` or the last tree that passed, so a turn that changed nothing costs nothing. It works this out with a scratch git index, leaving the real one alone; outside a git repo it doesn't run.

It blocks at most three times in a row. A failure Claude can't fix, such as a stopped database, then ends the turn with a warning to you instead of a loop.

## Install

Point hooks in `~/.claude/settings.json` at the scripts in a clone, as the hooks table above lists them: `bash "$HOME/projects/claude/static-checks/scripts/lint-edited-file.sh"` for `PostToolUse` (matcher `Edit|Write|MultiEdit|NotebookEdit`, timeout 120), `check-before-stop.sh` for `Stop` (timeout 900) and `baseline-reminder.sh` for `SessionStart`. Changes to the scripts then apply at once.

Or install it as a plugin:

```
/plugin marketplace add ~/projects/claude/static-checks
/plugin install static-checks@static-checks
```

Claude Code runs a cached copy, so after changing a hook bump `version` in `.claude-plugin/plugin.json`, then run `/plugin marketplace update static-checks` and `/plugin update static-checks@static-checks`.

It needs `jq`, `git` and `devbox` on `PATH`. Without them the hooks report an error rather than silently not checking.

## Development

```sh
devbox run -- task check   # shellcheck, then the shunit2 tests against throwaway projects
```
