# dev_loop

dev_loop is an autonomous, issue-driven PR loop you can point at any GitHub
repository (any language). It picks the highest-priority open issue, plans a
minimal PR, implements it in a git worktree, runs a 5-persona squad review
against the diff, and merges or iterates under deterministic gates — no human
approval per iteration. Configured today for `tracker` as the executor;
engine-pluggability deferred to pipelines#44.

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

## Quick start — run against your repo

> **Step 0:** make sure Prerequisites below are installed first — especially
> the right `yq`. Pasting steps 1–6 will fail with `setup-failed (missing
> required commands)` otherwise.

### Option A — edit YAML (persistent)

```sh
# 1. From your target repo's ROOT (NOT a subdirectory — see "What dev_loop
#    does NOT do" below for why):
cd ~/code/acme/widget-service

# 2. Drop dev_loop/ into the repo root. The dev_loop/ tree ships from the
#    pipelines repo (owner: 2389-research, repo: pipelines):
DEV_LOOP_OWNER=2389-research
DEV_LOOP_REPO=pipelines
git clone --depth=1 "https://github.com/${DEV_LOOP_OWNER}/${DEV_LOOP_REPO}.git" /tmp/dl-src
cp -r /tmp/dl-src/dev_loop ./dev_loop
rm -rf /tmp/dl-src

# 3. REPLACE dev_loop/config/repo_conventions.md with your project's facts
#    (commit style, test commands, forbidden patterns, idioms). The shipped
#    file documents the upstream dev_loop repo's conventions — leaving it
#    in place will steer the 5-persona squad reviewers against the wrong
#    rules, because they read this file via `ctx.last_response` as project
#    context.

# 4. Edit dev_loop/config/dev_loop.config.yaml:
#    repo: acme/widget-service
#    base_branch: main         # or omit to auto-detect via gh (works for
#                              # main, master, develop, etc.)
#    allow_no_ci: false

# 5. Run from the target repo root. This is the actual workflow run and may
#    take a while (multiple LLM calls per iteration):
tracker dev_loop/dev_loop.dip

# 6. After setup-ok, verify the resolved config (one line per knob with
#    source attribution: env, yaml, default, autodetect):
RID=$(cat "${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/.current_rid")
cat "${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/runs/${RID}/config_resolution.txt"
```

> **Silent override warning:** env vars beat YAML without complaint. If
> `config_resolution.txt` shows `(source=env)` on a knob you only set in
> YAML, an earlier `export GH_REPO=...` (or other `DEV_LOOP_*`) is still
> in your shell. Check `env | grep -E 'GH_REPO|DEV_LOOP_'`.

### Option B — environment variables (per-run override)

```sh
cd ~/code/acme/widget-service
# (still cp dev_loop/ into the repo as in Option A step 2)
# (still edit dev_loop/config/repo_conventions.md as in Option A step 3)

export GH_REPO=acme/widget-service
export DEV_LOOP_BASE_BRANCH=develop      # optional; auto-detected via gh if unset
export DEV_LOOP_STATE_ROOT=/tmp/dl       # optional; defaults to ${XDG_CACHE_HOME}/dip/dev_loop
tracker dev_loop/dev_loop.dip
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
- `gh` (authenticated against the target repo).
- `jq`.
- `yq` (see callout below).
- `git`.

> **yq variant matters**
>
> dev_loop requires `mikefarah/yq` v4+ (Go). Ubuntu/Debian's `apt install yq`
> ships the Python `kislyuk/yq` which uses a different query syntax and will
> cause setup_run to emit `setup-failed`. Install via:
> ```sh
> YQ_VER=v4.44.3
> curl -fsSL -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VER}/yq_linux_amd64"
> sudo mv /tmp/yq /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq
> yq --version | grep mikefarah    # verification
> ```

For developing the workflow itself you also need `bats`, `shellcheck`, and
`ajv-cli` — see the `dev_loop_smoke.yml` CI workflow for the exact apt/npm
commands.

## How to run

From the repo root:

```sh
tracker dev_loop/dev_loop.dip
```

State for the run lives under
`${XDG_CACHE_HOME:-$HOME/.cache}/dip/dev_loop/runs/<rid>/`. The
git worktree the implementer writes to is symlinked at
`./.dev_loop_worktree` so the `writable_paths: .dev_loop_worktree/**` glob
resolves correctly. tracker's per-node artifacts (the LLM responses each agent
produced) live under `./.tracker/runs/<tracker-run-id>/`.

To resume a run after a process kill, re-invoke `tracker --resume <run-id>`.
`setup_run.sh` will route to `setup-resume-required` when it detects a prior
worktree, signaling the operator to use the resume flow rather than starting
fresh.

## Configuration

Resolved at setup time from `dev_loop/config/dev_loop.config.yaml` with
env-var overrides. Precedence: **env > YAML > built-in default**. Verify
resolution via `runs/<rid>/config_resolution.txt`.

| Env var | YAML key | Default | What it does |
|---|---|---|---|
| `GH_REPO` | `repo` | — (setup-failed if absent) | Target GitHub repo as `owner/name`. |
| `DEV_LOOP_BASE_BRANCH` | `base_branch` | autodetect via `gh repo view` | Branch to base PRs from. |
| `DEV_LOOP_STATE_ROOT` | `runtime_state_root`†  | `${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop` | Per-run state dir. |
| `DEV_LOOP_ALLOW_NO_CI` | `allow_no_ci` | `false` | Merge when no CI is configured. |

†  YAML `runtime_state_root` is honored by `setup_run.sh`'s own resolution and
recorded in `config_resolution.txt` as `source=yaml`, BUT downstream scripts'
bootstrap preambles only honor the `DEV_LOOP_STATE_ROOT` env var or the
built-in default — they don't re-read YAML. For end-to-end consistency when
overriding the state dir, set the `DEV_LOOP_STATE_ROOT` env var instead. (See
the follow-up issue for sentinel-based unification of this knob.)

The YAML carries three additional keys that are NOT wired in v1:
`priority_label_order` (the jq priority function does its own normalize-and-rank
for P0..P3), `excluded_author_globs` (the filter hardcodes the `[bot]` check), and
`local_test_command` (reserved for a future repo-level smoke check the
Implementer must pass before pushing).

The Implementer's pre-push gate commands (`dippin check`, `tracker validate`,
`bats`) are currently pipelines-specific. Operators with non-shell-script
repos: expect these to be skipped or reported as mismatches; parameterization
via `repo_conventions.md` is deferred.

Model IDs must appear in tracker's embedded catalog (`tracker validate <file>`
prints the allowlist as "known models for <provider>"). The
`tests/test_branch_model_ids.sh` smoke check enforces this on the per-branch
overrides too.

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

`CleanupWorktree` is idempotent and runs from every cleanup-bearing exit
path *and* from each agent's `fallback_target`. `RatchetLog` runs immediately
after, appending one TSV line per run to `$DIP_ROOT/ratchet.tsv`.

There is one deliberate short-circuit exit that does NOT cleanup or
ratchet: `setup-resume-required`. setup_run.sh emits this when it detects
a prior run's worktree still on disk, so the operator can invoke
`tracker --resume <run-id>` to pick up where the prior run left off.
Deleting the worktree there would defeat the resume.

Setup failures write actionable reasons to `runs/<rid>/setup_error.txt`;
tail it. Common new categories: invalid YAML, missing yq, GH_REPO not
accessible, base-branch autodetect failure, no repo configured.

## What dev_loop does NOT do

- **Run from a repo subdirectory.** Paths are resolved from `$(pwd)`
  (`.tracker/runs`, `dev_loop/config/*`, `.dev_loop_worktree`); running from
  anywhere except the target repo root silently writes state to the wrong
  place. cd to the repo root first.
- **Run on macOS or Windows.** `writable_paths` enforcement uses Linux
  Landlock + openat2; tracker refuses to start otherwise.
- **Branch-protection bypass.** If your branch protection requires reviews,
  status checks, or signed commits, dev_loop respects them — and may emit
  `merge-blocked` if it can't merge.
- **CODEOWNERS approval.** dev_loop doesn't impersonate code owners; if your
  repo requires owner reviews, expect `merge-blocked`.
- **Self-review.** dev_loop refuses to review its own dev_loop changes via
  the issue filter's `excluded_title_regex`.
- **Test authoring beyond plan.** The Implementer writes only the tests the
  plan calls for. If your repo needs broader test coverage, file it as an
  issue.
- **Secret rotation, token management.** Out of scope.

## Anti-patterns

- **Don't commit secrets to `dev_loop/config/repo_conventions.md`.** The
  file content flows into agent prompts via `ctx.last_response` — anything
  there ends up in the LLM context for every PR review.
- **Don't accept PRs that edit `repo_conventions.md` without review.**
  `${ctx.last_response}` is a known cross-node prompt-injection vector; a
  malicious convention edit could steer the Implementer or reviewers. This is
  a separate threat from accidental secret-leak (which is item 1).
- **`pre_filter_issues` applies two defenses before feeding the filtered list
  into `SelectNextIssue` via `${ctx.last_response}`.** (1) It drops the
  GitHub issue `body` field entirely — body is the only unbounded
  free-form contributor field in the gh CLI shape, and SelectNextIssue's
  ranking rules don't need it. The surviving payload is `number`, `title`,
  `url`, `labels`, `author`, `createdAt` (of which `number`, `url`, and
  `createdAt` are structural GitHub-issued metadata; `title`, `labels`,
  and `author` are contributor-influenced). (2) It XML-escapes `<`, `>`,
  and `&` in every string value of the emitted JSON payload before
  embedding it in the `<filtered_issues>` block, so an attacker-crafted
  `title` (or any other string) containing `</filtered_issues>` cannot
  break out of the block and inject prose into the agent's prompt. The
  disk-side `filtered_issues.json` and `$RUN_DIR/issues.json` both keep
  the raw, unescaped form for forensics; only the stdout channel — the
  one that lands in agent prompts — is sanitized.
- **The dip executor's on-disk convention is named in exactly one place:
  the `--- begin dip-executor discovery ---` block in `setup_run.sh`.**
  Everywhere else in `dev_loop/` reads `${DIP_ARTIFACT_DIR}` from the
  per-run env file. To port dev_loop to a different dip executor, replace
  that one block (and the prereq tool list above it) — no other script
  needs to change. Today's executor is `tracker`; the discovery block
  resolves its `.tracker/runs/<runID>/` layout. The full porting guide is
  tracked in issue #45.
- **Don't set `allow_no_ci: true` on a repo with branch protection.**
  The combo means dev_loop will try to merge with no CI signal and get
  blocked by branch protection late in the pipeline.
- **Don't run dev_loop on a repo with auto-merge enabled.** Squad-merge
  and auto-merge race; the squad result may be stale by the time auto-merge
  fires.
- **Don't set `DEV_LOOP_STATE_ROOT` to a network mount.** Atomic rename
  guarantees (used for `.current_rid` and `env` publication) are weaker on
  NFS/SMB; lost writes can corrupt the run.

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

Per-run state (under `${DEV_LOOP_STATE_ROOT:-${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop}/runs/<rid>/`):

- `env` — per-run env file sourced by all scripts (atomic-rename published).
- `config_resolution.txt` — per-run resolved config log with source
  attribution (`env` / `yaml` / `default` / `autodetect`) for every knob.

## For workflow authors

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
