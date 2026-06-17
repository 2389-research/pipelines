# dev_loop

dev_loop is an autonomous, issue-driven PR loop you can point at any GitHub
repository (any language). It picks the highest-priority open issue, plans a
minimal PR, implements it in a git worktree, runs a 5-persona squad review
against the diff, and merges or iterates under deterministic gates — no human
approval per iteration. Configured today for `tracker` as the executor; see
[Executor compatibility](#executor-compatibility) below for the dev_loop ↔
executor contract and porting recipe.

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

```sh
# 1. Install prerequisites (see Prerequisites below). The right `yq`
#    matters: dev_loop needs mikefarah/yq v4+; the apt-shipped kislyuk/yq
#    has different syntax and will trip setup-failed.

# 2. (Optional) Drop conventions in your target repo. The cascade prefers,
#    in order: $DEV_LOOP_CONVENTIONS_FILE > ./.dev_loop/conventions.md >
#    ./AGENTS.md > ./CLAUDE.md > ./CONVENTIONS.md > shipped template.
#    If you already have AGENTS.md or CLAUDE.md, dev_loop uses it for free.

# 3. From any git repo cwd, run:
dippin pack -o ~/dl.dipx /path/to/pipelines/dev_loop/dev_loop.dip
tracker ~/dl.dipx
```

GH_REPO auto-detects from `git remote get-url origin` (HTTPS, ssh://,
git@ SSH, GHE host variants all parsed) — no YAML edit needed for the
common case. Pin a different target with `export GH_REPO=owner/name`.
After setup-ok, inspect the resolved config:

```sh
RID=$(cat "${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/.current_rid")
cat "${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/runs/${RID}/config_resolution.txt"
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

†  YAML `runtime_state_root` is now honored end-to-end (issue #53). `setup_run.sh`
publishes the resolved `DIP_ROOT` to a sentinel file at the built-in default
location (`${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/.last_dip_root`); every
downstream script's bootstrap preamble reads that sentinel before falling
through to the default. Resolution precedence stays `DEV_LOOP_STATE_ROOT` env >
YAML `runtime_state_root` > built-in default. The sentinel is "last writer
wins" — concurrent `setup_run` invocations under different `DIP_ROOT`s would
race on it, the same constraint the `${DIP_ROOT}/.dev_loop.lock` already
imposes for two runs sharing one root.

The sentinel is published **before any `emit_failure` or EXIT-trap path** so
the `setup-failed → CleanupWorktree` route also resolves the same `DIP_ROOT`
that `setup_run` picked (otherwise downstream cleanup would look under the
built-in default and miss the YAML-redirected `runs/<rid>/`). The write is
best-effort: an unwritable `XDG_CACHE_HOME` does not turn an otherwise-OK
YAML-redirected run into `setup-failed`; bootstraps without an env override
simply fall back to the built-in default (the pre-#53 behavior). The bootstrap
refuses to follow a symlinked sentinel (parity with the per-run `env` file
hardening) and falls back to the default when the sentinel-pointed root no
longer exists on disk.

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

## Executor compatibility

dev_loop is dip-executor-agnostic in principle. v1 ships configured for
[`tracker`](https://github.com/2389-research/tracker) as the executor, but
the workflow shape (pick → plan → implement → squad-review → merge) does
not depend on any tracker-specific feature. Porting to another dip
executor is a localized change to `setup_run.sh`; the persist scripts and
PR-ops scripts already read `${DIP_ARTIFACT_DIR}` from the per-run env
file and need no edits.

### The dev_loop ↔ executor contract

dev_loop scripts assume the executor provides:

- **Tool-node invocation per the dip language spec** — the executor reads
  the `.dip` file, dispatches tool nodes (POSIX `sh` scripts under
  `dev_loop/scripts/`), and routes on `ctx.tool_marker` from each tool's
  stdout against the node's `marker_grep` regex set.
- **A per-run, per-node artifact directory** — each agent node's response
  is written to `<DIP_ARTIFACT_DIR>/<NodeID>/response.md` so the
  `persist_*.sh` tools can read the prior node's output.
- **Environment variables published before any persist script runs.**
  `setup_run.sh` is the adapter: it discovers / synthesizes these and
  writes them to `${DEV_LOOP_RUN_DIR}/env`, which every downstream
  script's bootstrap preamble sources. The required contract keys are:
  - `DIP_ARTIFACT_DIR` — absolute path to the per-run artifact root for
    the executor. Agent responses live at
    `<DIP_ARTIFACT_DIR>/<NodeID>/response.md`. **This is the only
    executor-layout-coupled key** — its value comes from the discovery
    block in `setup_run.sh` and is what porters must re-source for a
    new executor.
  - `DEV_LOOP_RUN_DIR` — absolute path to dev_loop's per-run state dir
    (see Configuration: env `DEV_LOOP_STATE_ROOT` > YAML
    `runtime_state_root` > default). Dev_loop-internal; not coupled to
    the executor's on-disk layout.
  - `DEV_LOOP_RUN_ID` — opaque run id (treat as a string).
    Dev_loop-internal.
  - `GH_REPO` — target GitHub repo as `owner/name` for `gh` operations.
    Sourced from env > YAML config; not coupled to the executor.

  The env file also carries `BASE_BRANCH` and `ALLOW_NO_CI` (resolved
  config that downstream scripts read), and the canonical allow-list of
  emitted keys lives in the `# Allow-list` comment block in
  `dev_loop/scripts/setup_run.sh` (kept in sync with
  `tests/test_helpers.bash`'s unset list).
  When porting, preserve the structural-hygiene invariants `setup_run.sh`
  applies to every value: NL/CR rejection via `reject_special`,
  single-quote escaping via `emit_env`, mode-600 on the env file, atomic
  publication via `mv -f`, and rejection of a pre-existing symlink at the
  destination. Downstream scripts source the env file under `set -a` and
  trust it.

`setup_run.sh` is the ONLY place that knows how the executor's on-disk
layout is shaped; everywhere else reads `${DIP_ARTIFACT_DIR}` from the env
file. See the `--- begin dip-executor discovery (PORTING NOTE) ---` block
in `dev_loop/scripts/setup_run.sh` for the in-code implementation of this
contract.

### Porting to a different dip executor

1. **Rewrite the discovery block in `setup_run.sh`.** Replace the
   `DIP_ARTIFACT_ROOT="$(pwd)/.tracker/runs"` + `ls -dt` heuristic with
   whatever the new executor exposes — an env var it sets on tool
   subprocesses, a sentinel file, or its own discovery routine. The block
   must populate `dip_artifact_dir` with the executor's per-run artifact
   root for the current invocation; `emit_env DIP_ARTIFACT_DIR` does the
   rest. The populated value must be an existing directory — `setup_run.sh`
   enforces existence (`[ ! -d "${dip_artifact_dir}" ]` → `setup-failed`)
   and `reject_special` blocks NL/CR before `emit_env` writes it.
   Downstream scripts treat the value as an absolute path; the existing
   tracker discovery derives it from `$(pwd)` so absoluteness is
   incidental, not enforced — keep your replacement absolute by
   convention.
2. **Update the prereq command check.** In the `for cmd in gh jq git
   tracker yq timeout;` loop near the top of `setup_run.sh`, swap
   `tracker` for the new executor's CLI name (and drop tracker if it's no
   longer needed).
3. **Persist scripts (8 verdict-/plan-/synthesis-side), PR-ops scripts
   (push/fetch-context/recheck/poll/comment/merge), the iter counters,
   the worktree manager, and the ratchet log need no changes.** They
   read `${DIP_ARTIFACT_DIR}` from the per-run env file and talk to
   `git` / `gh` directly. They also assume the executor honors the
   marker-routing model in the Tool-node invocation bullet above
   (`ctx.tool_marker` from stdout against each node's `marker_grep`); a
   different executor that routes differently would invalidate the
   persist scripts' fail-closed `persist-failed` pattern.
4. **Carry-overs.** `local_gates.sh` runs `dippin check` — a
   *language*-level validator, not an executor-coupling point — so a
   dip-compliant executor doesn't need it changed. The persist scripts
   are already executor-neutral (#61, landed): they read
   `${DIP_ARTIFACT_DIR}` from the env file, and their `persist-failed`
   error breadcrumbs deliberately avoid naming any executor-specific
   on-disk path so a porter sees the same actionable message regardless
   of executor.

### Resume contract

dev_loop does NOT auto-resume. `setup_run.sh` detects a prior run's
worktree on disk and emits the `setup-resume-required` marker, which the
`.dip` routes straight to Exit without cleanup. The operator then
re-invokes the executor's own resume mechanism (today: `tracker --resume
<run-id>`); a different executor would use whatever its equivalent is.
If the target executor has no resume mechanism, an operator hitting the
`setup-resume-required` path would need to manually `rm -rf` the prior
run's worktree before re-invoking — a porting target without resume
support is usable, just less forgiving of process kills.

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

Imperative don'ts for operators and reviewers. (Descriptive truths the
workflow upholds live under [Invariants](#invariants) below.)

- **Don't commit secrets to `dev_loop/config/repo_conventions.md`.** The
  file content flows into agent prompts via `ctx.last_response` — anything
  there ends up in the LLM context for every PR review.
- **Don't accept PRs that edit `repo_conventions.md` without review.**
  `${ctx.last_response}` is a known cross-node prompt-injection vector; a
  malicious convention edit could steer the Implementer or reviewers. This is
  a separate threat from accidental secret-leak (which is item 1).
- **Don't set `allow_no_ci: true` on a repo with branch protection.**
  The combo means dev_loop will try to merge with no CI signal and get
  blocked by branch protection late in the pipeline.
- **Don't run dev_loop on a repo with auto-merge enabled.** Squad-merge
  and auto-merge race; the squad result may be stale by the time auto-merge
  fires.
- **Don't set `DEV_LOOP_STATE_ROOT` to a network mount.** Atomic rename
  guarantees (used for `.current_rid` and `env` publication) are weaker on
  NFS/SMB; lost writes can corrupt the run.

## Invariants

Descriptive single-source-of-truth rules the workflow upholds. Where to
look when something seems duplicated, and what NOT to let drift.

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
- **The dip executor's on-disk convention is discovered in exactly one
  place: the `--- begin dip-executor discovery (PORTING NOTE) ---` block
  in `dev_loop/scripts/setup_run.sh`.** Everywhere else in `dev_loop/`
  reads `${DIP_ARTIFACT_DIR}` from the per-run env file. Persist scripts
  speak in env-var terms only — their error breadcrumb names
  `DIP_ARTIFACT_DIR` (the actionable knob), never the executor's
  on-disk layout (#61). To port dev_loop to a different dip executor,
  replace the discovery block + the prereq tool list above it — no
  other LocalGates / persist logic needs to change. See
  [Executor compatibility](#executor-compatibility) above for the full
  contract + porting recipe. (Note: the
  Implementer agent's pre-push gates at
  `dev_loop/prompts/implementer.system.md` still include `tracker
  validate` by design — that's a separate scope from LocalGates and
  outside the executor-decoupling refactor.)

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
