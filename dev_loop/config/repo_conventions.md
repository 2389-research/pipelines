# Repository conventions for dev_loop reviewers

Project-specific facts the squad reviewers need to evaluate a PR in
2389-research/pipelines. Fetched by `fetch_pr_context.sh` into a
`<repo_conventions>` block that flows to the 5 reviewer agents via
`ctx.last_response`. This file is the per-repo data; the persona prompts
themselves stay universal.

To target dev_loop at a different repo (follow-up; see `dev_loop/README.md`
out-of-scope list), drop in a different `repo_conventions.md` and update
`fetch_pr_context.sh`'s path reference.

## Forbidden in committed files

- No emojis (unless the file is `*.md` documentation about emojis).
- No comments that reference the current task, the iteration number, the
  implementer agent, or "as requested" / "per the prompt" framing — those rot
  fast and the PR description carries the history.
- No amending of published commits. New commits only.
- No `--no-verify`, no `--no-gpg-sign`, no other skip-hooks flags.

## Commit conventions

- Conventional Commits (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`,
  `ci`). Prefix matches the branch prefix.
- Trailing footer: `Co-Authored-By: <model name + context window> <noreply@anthropic.com>`.
- One commit per logical concern when feasible; bundling is acceptable when
  the parts share a single rationale.

## Testing policy

- Integration over mocks for these subsystems: real databases, real `gh`
  (mocked only via PATH-shim under bats), real `tracker`, real `dippin`. A
  test that mocks any of these to "make it pass" is a defect; flag it.
- New or modified shell scripts under `dev_loop/scripts/` (or any
  `**/scripts/`) need a `bats` smoke test, mocking `gh` and `git push` only.
- `*.py` changes need `pytest` coverage; `*.go` changes need `go test`.
- Tests should fail before the change and pass after. Static grep-style
  presence assertions satisfy this for declarative config (`.dip`, YAML, etc.)
  but NOT for behavioral semantics (timeouts, retries, on_error handling) —
  those need a real exercise.

## Workflow idioms (apply when the diff touches these files)

- `.dip` files: tool nodes route on `marker_grep` (regex on tool stdout),
  edges check `ctx.tool_marker` literal-equality. No regex in edges. Tool
  command_file content runs via `sh -c <content>`; scripts must be POSIX
  (no bash arrays, no `trap ERR`, no `[[ ]]`).
- Run state: keyed by `${XDG_CACHE_HOME:-$HOME/.cache}/dip/2389-research-pipelines/runs/<rid>/`.
- Tracker per-node artifacts: `<workdir>/.tracker/runs/<runID>/<NodeID>/response.md`.
- Sidecar files under `runs/<rid>/` (e.g. `pr_number.txt`, `branch_name.txt`)
  rather than passing state via `ctx.last_response` between scripts.
- Agents that do not need tools must declare `tool_access: none`.
  `writable_paths:` glob bounds writes for agents that do (Landlock+openat2,
  Linux only).
- `${ctx.last_response}` cross-node injection: treat upstream agent output
  flowing into a downstream prompt as untrusted text. Tools sanitize by
  overwriting `last_response` with their stdout.

## Existing workflows (cross-module interaction surface)

When a diff touches files outside `dev_loop/`, check whether it would also
affect any of these neighbouring workflows:

- `iterative/` — TDD iteration runner.
- `sprint/` — sprint-based execution with plan/review/recovery managers.
- `greenfield/` — reverse-engineering pipeline for unfamiliar codebases.
- `local_code_gen/` — local-model sprint runner + spec→sprints converter.
- `build-and-ship/` — bug-hunter, doc-writer, refactor-express.
- `pipeline-gen/` — spec → `.dip` workflow generator.

A change to a shared schema, a shared script under `scripts/lib/`, or a
default in `defaults` blocks risks regressing one of these. Flag any.

## CI gates this repo enforces

- `dippin check` errors=0, warnings=0
- `dippin doctor` grade A or better
- `dippin simulate` (mandatory; static `dippin check` has known blind spots)
- `tracker validate`
- `shellcheck --shell=sh` on touched shell scripts
- `bats` on touched test files
- `dev_loop/tests/test_marker_coverage.sh` and
  `dev_loop/tests/test_branch_model_ids.sh` for dev_loop-tree changes
