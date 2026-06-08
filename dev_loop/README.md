# dev_loop

Autonomous issue-driven PR-review squad loop for `2389-research/pipelines`. One
`.dip` workflow picks the highest-priority open issue, plans a minimal PR,
implements it in a git worktree, runs a 5-persona squad review against the
diff, synthesises verdicts, and routes the result to merge / iterate / abandon
under deterministic mechanical gates.

## What it does

```
SetupRun → FetchOpenIssues → PreFilter
        → SelectNextIssue (agent: claude-opus-4-6)
        → PersistSelectedIssue
        → PlanMinimalPRs (agent: claude-opus-4-6)
        → PersistPlan → CreateWorktree → InitIterCounter
        → Implementer (agent: gpt-5.3-codex, writable_paths: .dev_loop_worktree/**)
        → PushAndOpenPR → FetchPRContext
        → parallel SquadFanout → 5 reviewer agents in parallel
              → 5 Persist*Verdict tools persist each verdict to disk
              → fan_in SquadJoin → SquadSynthesizer (agent)
              → PersistSynthesis emits synthesized-{approved | changes_requested | abandoned}
        synthesized-approved → RecheckPRSHA → LocalGates → PollCI → MergePR
        synthesized-changes_requested → PostSquadComment → IncIterCounter → Implementer (restart)
        synthesized-abandoned → CleanupWorktree
        (any gate-fail / ci-fail) → PostSquadComment → next iter
        max_iters (5) reached → CleanupWorktree → RatchetLog → Exit
```

## Prerequisites

- **Linux.** `writable_paths` enforcement uses Landlock + openat2, which are
  Linux-only. tracker refuses to start when `writable_paths` is set on
  macOS/Windows.
- `tracker` >= v0.35.0 (this is the version that ships
  `writable_paths`/`tool_access: none`/`marker_grep` together — earlier
  versions reject these as unknown fields).
- `dippin` is bundled inside `tracker`'s release; `dippin check` and
  `dippin doctor` are both used in CI.
- `gh` (authenticated against `2389-research/pipelines`).
- `jq`.
- `git`.

For developing the workflow itself you also need `bats`, `shellcheck`, and
`ajv-cli` — see the `dev_loop_smoke.yml` CI workflow for the exact apt/npm
commands.

## How to run

From the repo root:

```sh
tracker dev_loop/dev_loop.dip
```

State for the run lives under
`${XDG_CACHE_HOME:-$HOME/.cache}/dip/2389-research-pipelines/runs/<rid>/`. The
git worktree the implementer writes to is symlinked at
`./.dev_loop_worktree` so the `writable_paths: .dev_loop_worktree/**` glob
resolves correctly. tracker's per-node artifacts (the LLM responses each agent
produced) live under `./.tracker/runs/<tracker-run-id>/`.

To resume a run after a process kill, re-invoke `tracker --resume <run-id>`.
`setup_run.sh` will route to `setup-resume-required` when it detects a prior
worktree, signaling the operator to use the resume flow rather than starting
fresh.

## Config

`config/dev_loop.config.yaml` is the **reference document** for the knobs the
workflow uses (repo lock, branch base, max_iters, allow_no_ci, model
assignments, issue-filter rules). v1 does not load the YAML at runtime — the
same values are duplicated into the shell scripts (filter knobs, GH_REPO),
the `.dip` (model IDs, `defaults max_restarts`), and `init_iter_counter.sh`
(`max_iters`). The contract is: when you change a value in the YAML, also
update its mirror in the script/`.dip` it travels with. Wiring runtime YAML
loading is a follow-up.

Model IDs must appear in tracker's embedded catalog (`tracker validate <file>`
prints the allowlist as "known models for <provider>"). The
`tests/test_branch_model_ids.sh` smoke check enforces this on the per-branch
overrides too (dippin's lint does not catch per-branch typos).

## Failure modes

- **`setup-failed`** → cleanup, exit. See `runs/<rid>/setup_error.txt`.
- **`fetch-failed`** / **`filter-empty`** / **`filter-failed`** → cleanup, exit.
- **`worktree-failed`** → cleanup, exit. See `runs/<rid>/worktree_error.txt`.
- **`pr-push-failed`** → cleanup, exit. See `runs/<rid>/push_error.txt`.
- **`pr-closed`** / **`pr-merged-externally`** → cleanup, exit (someone else
  beat us to it).
- **`sha-drifted`** → cleanup, exit (force-push between squad review and
  merge gate; safer to drop than to merge an unreviewed SHA).
- **`gates-fail`** / **`ci-failed`** / **`ci-timeout`** → comment, next iter.
- **`ci-no-checks`** → cleanup, exit (configurable via `allow_no_ci: true`).
- **`merge-blocked`** → cleanup, exit. The class
  (`protected | conflicts | missing-reviews | unknown`) is in
  `runs/<rid>/merge_block_reason.txt` and on the ratchet line.
- **`synthesized-abandoned`** → cleanup, exit. See `runs/<rid>/synthesis.json`'s
  `abandon_reason`.
- **`iter-exhausted`** (max_iters reached without merging) → cleanup, exit.

`CleanupWorktree` is idempotent and runs from every exit path *and* from each
agent's `fallback_target`. `RatchetLog` appends one TSV line per run to
`$DIP_ROOT/ratchet.tsv`.

## Notable design choices vs issue #40 v6

- `fan_in SquadJoin` sources match the `SquadFanout` parallel target set
  (the 5 reviewer agents). Each `Persist*Verdict` runs on the explicit edge
  between its agent and `SquadJoin`. dippin requires the source/target sets
  to match (DIP007); the docs' "persist tools as fan_in inputs" phrasing is
  not realisable in the installed dippin.
- `PersistSynthesis` branches on the synthesis outcome rather than routing
  every `synthesized-*` marker through `RecheckPRSHA` (v6 §4's edge would
  have auto-merged green-CI PRs that the squad asked to revise).
- `merge-blocked-*` collapsed to a single `merge-blocked` marker; the class
  goes to `merge_block_reason.txt`. dippin's coverage analyser cannot prove
  `startswith merge-blocked-` covers a regex with `[a-z_]+`.
- Per-agent `fallback_target: CleanupWorktree` rather than
  `defaults on_failure:` — the latter is not in the installed dippin (the
  feature exists on dippin-lang main but is not in any tagged release we
  have).
- Scripts are POSIX `sh` not bash. tracker invokes tool command_file content
  via `sh -c <content>` and Ubuntu's `/bin/sh` is dash.
- Markers with numeric suffixes (`fetched-N`, `pr-ready-N`, `iter-N-of-M`)
  were simplified to literals (`fetched-ok`, `pr-ready`, `iter-next`); the
  counts live in sidecar files under `runs/<rid>/`. dippin's coverage
  analyser cannot match `[0-9]+` capture groups against `startswith` edges.

## Layout

```
dev_loop/
  README.md                        — this file
  dev_loop.dip                     — the workflow (36 nodes, 70 edges)
  config/dev_loop.config.yaml      — config (single source of truth)
  prompts/
    select_next_issue.{system,task}.md
    plan_minimal_prs.{system,task}.md
    implementer.{system,task}.md
    squad_synthesizer.{system,task}.md
    squad/
      pragmatism.system.md
      yagni.system.md
      testability.system.md
      holistic.system.md
      blocker.system.md
      task.md                      — shared per-invocation body
  scripts/
    *.sh                           — POSIX-sh tool commands
    markers.txt                    — every marker literal any script emits
  schemas/
    selected_issue.schema.json
    plan.schema.json
    verdict.schema.json
    synthesis.schema.json
  tests/
    *.bats                         — per-script bats tests
    test_marker_coverage.sh        — bijective check (regexes <-> literals)
    test_branch_model_ids.sh       — per-branch model-ID allowlist enforcement
    fixtures/                      — JSON fixtures for schemas + scripts
.github/workflows/
  dev_loop_smoke.yml               — gates the dev_loop tree
```
