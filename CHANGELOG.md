# Changelog

All notable changes to `2389-research/pipelines` are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
as defined in [`RELEASING.md#versioning`](./RELEASING.md#versioning) (the
policy applies from `v0.2.0` forward; `v0.1.x` is not retroactively re-versioned).
A custom `### Deferred` section type is used where in-flight scope was
reclassified rather than landed (see v0.1.3); other sections follow the KAC
1.1.0 enumeration. Long-form release notes are published on the
[GitHub releases page](https://github.com/2389-research/pipelines/releases);
maintainers: see [`RELEASING.md`](./RELEASING.md) for the release-cut convention.

## [Unreleased]

### Added

- `dev_loop/tests/test_ledger_roadmap_identical.sh` +
  `docs/ledger-roadmap-state-machine-audit.md`: a drift-prevention gate and
  audit for the ledger/roadmap state-machine shell logic issue #109 flagged as
  duplicated across the sprint pipeline family. The gate asserts the six
  blocks that are byte-identical *and meant to stay so* (the Group-A and
  Group-B next-sprint scanners, the `in_progress` and `completed` row-status
  updates, the progress counter, and the `validate_output` ledger/JSONL
  sub-block) stay
  identical via content-anchored `cmp` — no markers are added to the `.dip`
  files, so tracker's shell/coverage parsing is untouched. It is shellcheck-clean
  and wired into `dev_loop_smoke.yml` next to the bootstrap and persist-verdict
  identity gates. The audit records why a single shared helper/subgraph is not
  viable under the `dippin pack` → `.dipx` distribution model (the #107/#108
  precedent) and waives the per-node-intent variation the issue over-counted
  (Group-A vs Group-B wrappers, status-literal differences, megaplan's distinct
  ops, the `iter_dev` path-variable/subset differences, the `iter_run`
  heading-match asymmetry, the `architect_only` node envelope). No `.dip`
  workflow logic changed; no behavior change
  ([#109](https://github.com/2389-research/pipelines/issues/109)).
- `tests/track_b_smoke/smoke.sh`: per-family auto-runnable smoke probes for
  the sprint-exec, sprint-runner, and greenfield families
  (`verify-sprint-exec`, `verify-sprint-runner`, `verify-greenfield`). Each
  fail-fasts past a short-circuit edge so the converted `tool_access: none`
  Start + Exit agents are exercised under a realistic catalog without
  entering the implementation lane. Observed per-family cost bands:
  `verify-sprint-exec` $0.0024-$0.0052, `verify-greenfield` $0.0030-$0.0050,
  `verify-sprint-runner` ~$0.07 (the no_ledger_exit agent on the
  short-circuit path is tool-enabled and dominates the cost; Start + Exit
  themselves stay in the cheap band). Sprint families now preflight `yq`
  on `PATH` and fail-fast if absent, so the probe can't silently pass via
  the `CheckYq → YqMissing → Exit` short-circuit instead of the intended
  converged-end-state path
  ([#106](https://github.com/2389-research/pipelines/pull/106),
  closes [#76](https://github.com/2389-research/pipelines/issues/76)).
- `docs/migrations/0.32-tool-access-none.md` +
  `docs/migrations/0.32-to-current.md`: toolchain migration guides for
  downstream template users. The first covers the `tool_access: none` agent
  field (dippin v0.32.0) and the tool-access-vs-policy distinction; the second
  gives version-by-version notes from v0.32 through the current pins
  (`command_file` v0.33, `prompt_file`/`system_prompt_file` v0.34,
  `writable_paths` + DIP140 + per-branch overrides v0.35, DIP143 subgraph
  containment v0.36). `docs/agent-node-safety.md` gains a "Structural bound
  tiers" section noting the v0.28.2 runaway-agent vector is now structurally
  bounded on an enforcing runtime (top-level `tool_access` needs tracker
  ≥ v0.39.0, the repo's floor) and explaining when to reach for
  `tool_access: none` vs. `writable_paths` vs. the read-bounded waiver.
  Docs-only; no `.dip` change
  ([#20](https://github.com/2389-research/pipelines/issues/20),
  [#38](https://github.com/2389-research/pipelines/issues/38)).

### Changed

- Toolchain pin bumped to the latest lockstep pair: tracker `v0.35.1` → `v0.40.2`,
  dippin `v0.35.0` → `v0.43.0` (`dev_loop_smoke.yml`), and the README/`dev_loop`
  requirement floor raised tracker `≥ v0.35.0` → `≥ v0.39.0`. The repo now tracks
  the most recent release (production runs `@latest`). The floor matters: tracker's
  adapter only propagates the **top-level** `tool_access` spelling — the form every
  Track B `.dip` uses — from v0.39.0 ([tracker#366](https://github.com/2389-research/tracker/issues/366));
  on v0.35–v0.38 the `Start`/`Exit` bounds parsed but silently no-op'd at runtime.
  `dev_loop.dip` stays Grade A under dippin v0.43.0. The Track B runtime-smoke
  regression that #366 caused is correspondingly marked resolved in
  `tests/track_b_smoke/README.md` (re-wiring those probes in CI remains tracked by
  [#19](https://github.com/2389-research/pipelines/issues/19)).
- `dev_loop/config/repo_conventions.md` "Testing policy" category bullet now
  names the second axis (auto-runnable harness vs. operator runbook) and
  states the template's default — runbooks that depend on in-tree assertion
  helpers colocate with auto-runners under the same `tests/<name>/`, with
  each entry-point labeled `auto` or `manual` in the suite README
  ([#83](https://github.com/2389-research/pipelines/issues/83)).
- Renamed root `CONTRIBUTING.md` → `RELEASING.md` to match its scope: the file
  is a maintainer release-cut + SemVer playbook with no external-contributor
  content. README and CHANGELOG anchors updated; `.github/PULL_REQUEST_TEMPLATE.md`
  and `.github/workflows/changelog_check.yml` comments repointed at the new path.
  Operator-visible doc rename; not a SemVer-surface change
  ([#104](https://github.com/2389-research/pipelines/pull/104),
  closes [#86](https://github.com/2389-research/pipelines/issues/86)).
- `dev_loop/scripts/persist_*_verdict.sh`: deduplicated the five byte-identical
  squad-verdict persisters. The shared body is now interpolated from two
  per-squad declarations (`squad`/`squad_node`) and bracketed by
  `# ---begin/end-persist-verdict-reference---` markers; the only other
  per-squad line is the literal success marker `printf 'persisted-<slug>'`,
  kept a static literal (not `printf 'persisted-%s'`) so `dippin coverage`/
  `doctor` still see a routable tool output. The duplication is enforced
  against the new `dev_loop/tests/persist_verdict.ref` by
  `dev_loop/tests/test_persist_verdict_identical.sh` (mirroring the existing
  bootstrap-preamble gate). Runtime behavior and tool markers are unchanged —
  the scripts stay self-contained because tracker inlines each `command_file:`
  body into the `.dipx` bundle, which does not ship `scripts/lib/`. The smoke
  workflow runs the new identity gate
  ([#107](https://github.com/2389-research/pipelines/issues/107)).
- Audited the 10 read-bounded agent nodes flagged by
  [#110](https://github.com/2389-research/pipelines/issues/110) as
  "prose-guarded read-only reporters." All 10 (`already_complete_exit`,
  `FindNextSprint`, `ReadSprint`, `deps_blocked_exit`, `SemanticReview` across
  `iterative/iter_dev.dip` and the `sprint/` workflows) read files via the
  native `Read` tool, so `tool_access: none` — which is all-or-nothing on the
  native backend — would strip the read access they need and break them. Each
  is now tagged with an inline `# CAT-C READ-BOUNDED (issue #110)` marker, and
  `docs/agent-node-safety.md` gains a section documenting the waiver so future
  audits recognize these as reviewed exceptions rather than missed instances.
  No `.dip` behavior change (comment-only); the write-bounding prose stays as
  the only available guard until a scoped read-only primitive lands upstream.

### Fixed

- `sprint/sprint_exec_yaml.dip`, `sprint/sprint_exec_yaml_v2.dip`: the
  `ValidateBuild` toolchain-fallback ladder detected `pyproject.toml` /
  `package.json` before `Package.swift`, so a Swift repo carrying an
  incidental Python/Node manifest would have run `pytest`/`npm test` instead
  of `swift build`/`swift test`. `Package.swift` is now detected first, matching
  the swift-first order the rest of the sprint family
  (`sprint_exec.dip`, `*-cheap.dip`) already uses. New
  `docs/build-system-detection-audit.md` records why the broader build-system
  detection duplication (issue #108) is reconciled-and-documented rather than
  extracted into a shared helper (no lib/subgraph survives `dippin pack`
  inlining under the tracker/dippin pin) and why the remaining order
  differences are waived as behavior contracts rather than reordered
  ([closes #108](https://github.com/2389-research/pipelines/issues/108)).

### Security

- `greenfield/greenfield.dip`: the orchestrator-level failure-breadcrumb
  reporters `DiscoveryFailed` and `L1Failed` write only `workspace/.l1-failed`
  but ran with full default tool access. Both now carry
  `writable_paths: workspace/.l1-failed`, structurally bounding their write
  scope to the single path their prompts touch — matching the sibling
  breadcrumb-writers in the review/synthesis/validation subgraphs
  ([#32](https://github.com/2389-research/pipelines/issues/32)).
- Greenfield subgraph write-scope sweep: added `writable_paths: workspace/**` to
  the 42 worker agents across `greenfield/greenfield_discovery.dip` (9),
  `greenfield_synthesis.dip` (13), `greenfield_review.dip` (11), and
  `greenfield_validation.dip` (9) whose prompts already declare the uniform
  "WRITE BOUNDARY: ONLY ... under workspace/" contract but ran unbounded. The
  glob is the faithful structural translation of that existing prose; Start/Exit
  (`tool_access: none`) and the `*Failed` breadcrumb-writers (narrower scope)
  are unchanged. `dippin check` clean (0 errors) on all four files. Enforced by
  tracker's Linux fs-jail; a runtime smoke (#19) should confirm the
  multi-provider agents still start under the jail
  ([#32](https://github.com/2389-research/pipelines/issues/32)).
- Iterative pipeline write-scope sweep: added `writable_paths:` to the
  bounded-write agents across `iterative/iter_scope.dip` (6),
  `iter_extract.dip` (9), `iter_dev.dip` (2), `iter_audit.dip` (4), and
  `iter_run.dip` (10) whose prompts already declare a single bounded write
  target. Temp-only writers are bound to their per-stage scratch tree
  (`.ai/iter-scope-temp/**`, `.ai/iter-extract-temp/**`,
  `.ai/iter-audit-temp/**`, `.ai/iter-run-temp/**`); artifact writers that the
  prompts confine to docs are bound to `docs/iterations/**` (with
  `.ai/iter-audit-result.txt` / `.ai/iter-loop-context.txt` added where the
  prompt also writes those sentinels). The three broad task-implementer agents
  that write arbitrary source by design (`implement_task`, `fix_spec_issues`,
  `fix_quality_issues` in `iter_run.dip`) are deliberately left unbounded.
  All five files stay grade A (`dippin doctor`) and pass `tracker validate`
  ([#32](https://github.com/2389-research/pipelines/issues/32)).

## [0.3.0] - 2026-06-17

Second minor release under the `CONTRIBUTING.md#versioning` SemVer policy.
Bundles the `iter_run.dip` grade-A restoration (with operator-visible marker
rename), the `dev_loop/` `runtime_state_root` resolution unification, the
`persist_*.sh` fail-class sidecar surface, and `[Unreleased]` enforcement on
the SemVer surface. Tests-only ([#99](https://github.com/2389-research/pipelines/pull/99))
and README structural pass ([#98](https://github.com/2389-research/pipelines/pull/98),
which subsumed [#84](https://github.com/2389-research/pipelines/issues/84))
also landed in this window but carry no SemVer-surface entry.

### Changed

- `iterative/iter_run.dip` restored to grade A (90/100, was F/30) — closed DIP115
  goal-gate gaps on `decompose_tasks` and `wrap_up` (added `retry_target` +
  `fallback_target`), removed the DIP125 `:` false-positive, and replaced 5
  dynamic-suffix tool markers (`task-%s`, `todos-unresolved-%d`,
  `sentinel-regression-%s`, `inconsistent-no-stories-found-for-%s`,
  `inconsistent-%s`) with fixed routing tokens (`task-found`,
  `todos-unresolved`, `sentinel-regression`, `inconsistent-no-stories`,
  `inconsistent-stories`) plus sidecar files in `.ai/iter-run-temp/` carrying
  the dynamic detail. Operator-visible marker rename
  ([#101](https://github.com/2389-research/pipelines/pull/101),
  closes [#27](https://github.com/2389-research/pipelines/issues/27)).

### Fixed

- `dev_loop/`: unify YAML `runtime_state_root` resolution end-to-end.
  `setup_run.sh` now publishes the resolved `DIP_ROOT` to a sentinel at the
  built-in default location
  (`${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/.last_dip_root`); every
  downstream script's bootstrap preamble consults the sentinel before falling
  through to the default. The sentinel is published before any `emit_failure`
  / EXIT-trap path so the `setup-failed → CleanupWorktree` route also
  resolves the same `DIP_ROOT` (otherwise cleanup would miss the YAML-
  redirected `runs/<rid>/`). The write is best-effort — an unwritable or
  not-searchable `XDG_CACHE_HOME` no longer turns an otherwise-OK YAML-
  redirected run into `setup-failed` (pre-flight `-w` and `-x` guards skip
  the write before dash can emit a "Permission denied" stderr line that
  would pollute tracker's captured stream) — and the bootstrap refuses to
  follow a symlinked sentinel
  (parity with the per-run env-file hardening), falling back to the default
  when the sentinel points at a now-missing directory. The bootstrap also
  requires the sentinel to be a regular file (`-f`) before reading, so a
  tampered FIFO/device at the sentinel path cannot block downstream
  `cat`; the byte-identical preamble is propagated across all 22 reader
  scripts and `tests/bootstrap.ref`. Closes the silent-halt where setting
  YAML-only `runtime_state_root` caused downstream nodes to look under
  the default path while `.current_rid` landed under the YAML path
  ([#100](https://github.com/2389-research/pipelines/pull/100), closes
  [#53](https://github.com/2389-research/pipelines/issues/53)).

### Added

- `dev_loop/scripts/persist_*.sh` write a `persist_<flavor>_fail_class.txt`
  sidecar (`unset | stale | response-missing | jq-parse | validation`)
  before each `exit 1` site; `ratchet_log.sh` surfaces the class as
  `persist-failed-<class>` so RatchetLog and downstream dashboarding can
  distinguish failure modes at the marker layer
  ([#97](https://github.com/2389-research/pipelines/pull/97),
  closes [#90](https://github.com/2389-research/pipelines/issues/90)).
- `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/changelog_check.yml`
  enforce `[Unreleased]` updates on PRs that touch the SemVer surface
  (`*.dip`, operator-facing `dev_loop/`), with a `skip-changelog` label
  escape hatch for SemVer-surface PRs that legitimately need no entry
  (refactor-only / formatting / comment-only)
  ([#96](https://github.com/2389-research/pipelines/pull/96),
  closes [#68](https://github.com/2389-research/pipelines/issues/68)).

## [0.2.0] - 2026-06-16

First minor release under the `CONTRIBUTING.md#versioning` SemVer policy
(introduced by [#92](https://github.com/2389-research/pipelines/pull/92)).
Bundles the `dev_loop/` subsystem launch, `writable_paths` fs-jail adoption,
three `iter_*` lint cleanups, and the DIP143 subgraph audit.

### Added

- `writable_paths` 5-site adoption across `sprint_exec*` agents, with the
  minimum tracker pin bumped to `v0.35.0` (which vendors dippin-lang
  ≥ `v0.35.0`); enforces Landlock + openat2 fs-jail bounds on Linux and
  refuses to start on macOS/Windows when the field is set
  ([#41](https://github.com/2389-research/pipelines/pull/41)).
- `dev_loop/` subsystem — autonomous issue-driven dev loop (v6 design from
  [#40](https://github.com/2389-research/pipelines/issues/40)): multi-round
  scope → implement → verify loop with breadcrumb persistence, executor
  decoupling, and reusable setup_run sub-pipeline
  ([#42](https://github.com/2389-research/pipelines/pull/42)).
- `.dipx` packable-workaround machinery for Phase 0.5 dev_loop runs from any
  cwd ([#54](https://github.com/2389-research/pipelines/pull/54)).
- Low-reasoning tournament variant of `spec_to_sprints` for `local_code_gen/`
  ([#55](https://github.com/2389-research/pipelines/pull/55)).
- `CHANGELOG.md` at repo root, backfilled with entries for v0.1.0 → v0.1.3
  ([#37](https://github.com/2389-research/pipelines/issues/37),
  [#62](https://github.com/2389-research/pipelines/pull/62)).
- `CONTRIBUTING.md` at repo root with a `Releases` section that now owns the
  release-cut convention; `README.md` and `CHANGELOG.md` headers point to it
  instead of duplicating the prose
  ([#69](https://github.com/2389-research/pipelines/issues/69),
  [#79](https://github.com/2389-research/pipelines/pull/79)).
- `docs/research/` reasoning-tier study + cross-module-test panel notes for
  the `spec→sprints` upstream
  ([#59](https://github.com/2389-research/pipelines/pull/59)).
- `dev_loop` executor-compatibility contract + porting guide for running the
  workflow under a second executor
  ([#63](https://github.com/2389-research/pipelines/pull/63),
  closes [#45](https://github.com/2389-research/pipelines/issues/45)).
- `track_b` runtime smoke harness for the `tool_access: none` sweep
  ([#66](https://github.com/2389-research/pipelines/pull/66),
  closes [#19](https://github.com/2389-research/pipelines/issues/19)).
- `track_b` repo-wide vs `dev_loop/`-scoped test-tree convention documented
  ([#77](https://github.com/2389-research/pipelines/pull/77),
  closes [#75](https://github.com/2389-research/pipelines/issues/75)).
- `dev_loop` porting-contract smoke — bi-directional literal lock + stub
  second-executor run-through + failure-path neutrality assertions
  ([#81](https://github.com/2389-research/pipelines/pull/81),
  closes [#71](https://github.com/2389-research/pipelines/issues/71)).
- `dev_loop` Phase 1 any-cwd UX: auto-detect `GH_REPO` from `git remote`,
  `dev_loop/` YAML cascade with operator-curated overrides, and a conventions
  cascade so the Implementer prompt is portable across repos
  ([#91](https://github.com/2389-research/pipelines/pull/91),
  closes [#47](https://github.com/2389-research/pipelines/issues/47)).
- `docs/dip143-subgraph-audit.md` — per-site audit of the 15 subgraph
  `tool_access` boundaries flagged by dippin v0.36.0's DIP143 advisory lint,
  with verdicts (SOUND / LEAK / INTENTIONAL_OPEN), rationale, and a
  highest-stakes paragraph on the `sprint_runner_yaml_v2.dip` boundaries
  ([#34](https://github.com/2389-research/pipelines/issues/34)).

### Changed

- `dev_loop` setup_run sub-pipeline centralizes dip-executor coupling
  (refactor surface for [#44](https://github.com/2389-research/pipelines/issues/44))
  ([#60](https://github.com/2389-research/pipelines/pull/60)).
- `dev_loop` README `## Anti-patterns` split into imperative don'ts plus a
  descriptive `## Invariants` section
  ([#78](https://github.com/2389-research/pipelines/pull/78),
  closes [#72](https://github.com/2389-research/pipelines/issues/72) and
  [#74](https://github.com/2389-research/pipelines/issues/74)).
- `dev_loop` universal repo conventions (Conventional Commits, hook discipline,
  etc.) moved from `repo_conventions.md` into `prompts/squad/task.md` and
  `prompts/implementer.system.md`; the shipped `repo_conventions.md` shrinks to
  a short operator-facing template
  ([#91](https://github.com/2389-research/pipelines/pull/91)).
- `dev_loop` Implementer prompt no longer hardcodes
  `dippin check && tracker validate && bats`; defers to the plan's
  `test_strategy` field
  ([#91](https://github.com/2389-research/pipelines/pull/91)).
- `dev_loop` YAML `repo:` field commented out by default — auto-detection via
  `git remote` now wins unless the operator opts back in
  ([#91](https://github.com/2389-research/pipelines/pull/91)).

### Fixed

- `dev_loop` setup_run failure-path safety hardening
  ([#56](https://github.com/2389-research/pipelines/pull/56),
  closes [#51](https://github.com/2389-research/pipelines/issues/51) and
  [#52](https://github.com/2389-research/pipelines/issues/52)).
- `dev_loop` persist scripts now emit failure markers instead of halting the
  pipeline ([#57](https://github.com/2389-research/pipelines/pull/57),
  closes [#48](https://github.com/2389-research/pipelines/issues/48)).
- `dev_loop` `pre_filter` strips issue body to avoid prompt-injection surface
  via untrusted GitHub content
  ([#58](https://github.com/2389-research/pipelines/pull/58),
  closes [#50](https://github.com/2389-research/pipelines/issues/50)).
- `iter_scope` DIP101/DIP102 lint warnings cleared via `marker_grep` on the
  four validate/count nodes
  ([#64](https://github.com/2389-research/pipelines/pull/64),
  closes [#29](https://github.com/2389-research/pipelines/issues/29)).
- `iter_extract` DIP101/DIP102 lint warnings cleared via `marker_grep` on the
  three count/pick/validate tool nodes
  ([#94](https://github.com/2389-research/pipelines/pull/94),
  closes [#28](https://github.com/2389-research/pipelines/issues/28)).
- `iter_run` DIP101/DIP102 lint warnings cleared via `marker_grep` on the
  10 count/audit/validate tool nodes
  ([#95](https://github.com/2389-research/pipelines/pull/95),
  refs [#27](https://github.com/2389-research/pipelines/issues/27)).
- `dev_loop` `persist_*.sh` no longer write the legacy `.tracker/runs`
  breadcrumb path
  ([#65](https://github.com/2389-research/pipelines/pull/65),
  closes [#61](https://github.com/2389-research/pipelines/issues/61)).
- `dev_loop` persist breadcrumb now distinguishes `unset` vs `stale`
  `DIP_ARTIFACT_DIR` arms instead of conflating them
  ([#80](https://github.com/2389-research/pipelines/pull/80),
  closes [#73](https://github.com/2389-research/pipelines/issues/73)).

## [0.1.3] - 2026-05-27

Track B Phase 2 verdict synthesizers + sprint runner redecompose hardening.

### Added

- `commit_after_splice` tool node in `sprint_runner_yaml_v2.dip` — splits the
  ledger commit out of `commit_output` so redecompose only commits after
  `splice_ledger` has settled state, with an allowlisted git-staging set
  (ledger + new sprint files + rewritten dependents only)
  ([#25](https://github.com/2389-research/pipelines/pull/25)).

### Changed

- 4 Category B verdict synthesizers converted from prompt-level "HARD
  CONSTRAINT" tool-access copy to dippin-lang v0.32.0's `tool_access: none`
  structural primitive: `sprint_exec.dip:347` (`ReviewAnalysis`),
  `sprint_exec-cheap.dip:326` (`GateCheap`),
  `sprint_exec_yaml.dip:553` (`ReviewAnalysis`),
  `sprint_exec_yaml_v2.dip:874` (`ReviewAnalysis`)
  ([#23](https://github.com/2389-research/pipelines/pull/23)).
- `splice_ledger` now idempotently inserts new sub-sprint entries from disk
  (was: assumed regenerator had already appended them)
  ([#25](https://github.com/2389-research/pipelines/pull/25)).
- `commit_output` made redecompose-aware — commits only new `SPRINT-*.md`
  files on the redecompose path and refuses on partial state, so a corrupted
  ledger can no longer poison git HEAD
  ([#25](https://github.com/2389-research/pipelines/pull/25)).
- `redecompose_single` agent hardened with `auto_status: true`, inverted
  STATUS contract, and an explicit PROHIBITED ACTIONS checklist, after a real
  run wrote source files and fabricated YAML status fields
  ([#25](https://github.com/2389-research/pipelines/pull/25)).

### Fixed

- `validate_ledger_after_redecompose` no longer wholesale-restores from
  snapshot when `completed_count` drops, which had been erasing newly-appended
  sub-sprint entries ([#25](https://github.com/2389-research/pipelines/pull/25)).
- `splice_ledger` dependents are normalized with `|= unique` for retry safety
  ([#25](https://github.com/2389-research/pipelines/pull/25)).

### Deferred

- 6 of the originally-listed [#18](https://github.com/2389-research/pipelines/issues/18)
  Phase 2 sites reclassified to Category C/D — they need a write-allowlist
  primitive (e.g., `tool_access: workspace_only`) that does not exist in
  dippin-lang v0.32.0. Issue #18 closed with the reclassification table as
  final disposition.

## [0.1.2] - 2026-05-27

Track B Phase 1: `tool_access: none` on acknowledge-only agents.

### Changed

- 22 Category A agent Start/Exit/single-Exit sites across 12 files in
  `greenfield/` and `sprint/` converted from prompt-level "HARD CONSTRAINT"
  tool-access copy to dippin-lang v0.32.0's `tool_access: none` structural
  primitive ([#21](https://github.com/2389-research/pipelines/pull/21)).
  Acknowledge-only agents that only need to emit text can no longer call tools
  that are not in the registry — the v0.28.2 single-agent multi-tool-call
  vector is now bounded structurally, not by prompt copy.
- Minimum tracker bumped to `v0.32.0` (clean dippin-lang v0.32.0 vendor pin),
  closing the pre-release vendor-lag risk that #21 was developed against
  ([#22](https://github.com/2389-research/pipelines/pull/22)).
- `docs/agent-node-safety.md` TL;DR rewritten to lead with `tool_access: none`;
  deeper analysis sections retained as background.
- `max_turns: 1` added to 6 `sprint_exec_*` Start/Exit agents that lacked it.

### Removed

- Tool-access HARD CONSTRAINT clauses ("Do NOT read project files / write code
  / create-modify-delete / run tests / install dependencies / debug") from the
  22 converted sites. Output-policy clauses ("Your ONLY job is to acknowledge
  X") are preserved as plain instructions.

## [0.1.1] - 2026-05-26

Bench refactor + `local_code_gen/` hardening.

### Changed

- `local_code_gen/bench_local_fix_sr.dip` refactored to source
  `lib/lang_profile.sh` and dispatch through the same per-language entry points
  as `sprint_runner_qwen.dip` — bench is now a faithful test of production's
  LocalFix shape, not a parallel implementation. C/70 (4 warnings) → A/90 (0
  warnings). Closes [#5](https://github.com/2389-research/pipelines/issues/5).
  Repo-wide lint: 67 → 63 warnings ([#17](https://github.com/2389-research/pipelines/pull/17)).
- `restore_state` in both production runners now deletes-then-restores
  `ROOT_FILES` (previously, a root manifest created mid-round would persist
  past rollback).
- `uv.lock` added to `ROOT_FILES` snapshot/restore surface (was the only major
  lockfile missing alongside `package-lock.json`, `go.sum`, `Cargo.lock`,
  `Gemfile.lock`).
- LocalFix scratch files (`lf_*.txt`) moved from `/tmp` to `$WORKDIR_ABS/.ai/`
  to eliminate symlink-clobber surface and concurrent-run collisions.
- `marker_grep` declarations added to bench RunTests and LocalFix, replacing
  substring-vulnerable `ctx.tool_stdout contains X` routing with exact-match
  `ctx.tool_marker = X`.

### Fixed

- `set -f` / `set +f` wrap around the LocalFix `find` loop so glob patterns in
  `$lf_prune` (`*/__pycache__/*`, `*/node_modules/*`) aren't expanded against
  CWD before reaching `find`.
- `FAIL_COUNT` double-zero bug — `grep -c . || echo 0` emitted `"0\n0"` on
  empty input, injecting a literal newline into the qwen prompt template.
  Switched to `|| true`.
- Bench `snapshot_state` / `restore_state` now normalize `$snap_dir` to an
  absolute path (silently broke rollback for the documented `backend/`-shaped
  fixtures).
- Bench `proj_root` pinned from Setup's persisted value (production needs
  re-detection because of mid-workflow `Generate`; bench does not).
- Bench `lang` fallback now triggers on empty file contents, not just non-zero
  exit, matching RunTests' `[ -z ]` + persist pattern.
- Bench `local-fix-applied` → `local-fixed` marker typo that dead-ended the
  empty-Ollama-response guard.

## [0.1.0] - 2026-05-26

First formal release. Tags the state of `main` after the tracker
v0.29–v0.30 era quality work.

### Added

- 43 `.dip` workflows across seven buckets: `build-and-ship/` (5),
  `sprint/` (15), `iterative/` (5), `greenfield/` (5), `interactive/` (3),
  `local_code_gen/` (6), `pipeline-gen/` (4). See [README.md](./README.md)
  for the full catalog.
- Local-model code generation pipelines (qwen + gemma) and the
  `local_code_gen/` bucket including `lib/lang_profile.sh` shared per-language
  dispatch (PRs [#1](https://github.com/2389-research/pipelines/pull/1),
  [#2](https://github.com/2389-research/pipelines/pull/2),
  [#4](https://github.com/2389-research/pipelines/pull/4)).
- Cross-module integration-test mandate in the architect's dependency-edge
  contract authoring, validated end-to-end on `experiments/rust_calc_v2`
  ([#7](https://github.com/2389-research/pipelines/pull/7)).
- `docs/agent-node-safety.md` (158 lines) — design note on agent-node
  tool-access semantics, `max_turns` bounding behavior, and the
  `${ctx.last_response}` cross-node prompt-injection vector.
- README Requirements callout for the tracker version dependency, introduced
  alongside the first `marker_grep` adoption
  ([#14](https://github.com/2389-research/pipelines/pull/14)).

### Changed

- Spec-to-sprints hardening — removed fragile writes, added verification gates
  ([#3](https://github.com/2389-research/pipelines/pull/3)).
- `iter_run` + iter family contract gap closures, reviewer model selection,
  cycle fix (PRs [#9](https://github.com/2389-research/pipelines/pull/9),
  [#10](https://github.com/2389-research/pipelines/pull/10),
  [#11](https://github.com/2389-research/pipelines/pull/11)).
- Quality pass against tracker v0.29.2 / dippin v0.27.0: 16 files, agent
  Start/Exit conversions, `goal_gate` recovery wiring, `max_turns` budget
  normalization ([#13](https://github.com/2389-research/pipelines/pull/13)).
- `marker_grep` extended to `iter_dev.dip` and three `spec_to_sprints`
  variants, clearing 8 lint warnings via
  [dippin-lang#42](https://github.com/2389-research/dippin-lang/issues/42)'s
  suppression ([#16](https://github.com/2389-research/pipelines/pull/16)).

[Unreleased]: https://github.com/2389-research/pipelines/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/2389-research/pipelines/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/2389-research/pipelines/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/2389-research/pipelines/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/2389-research/pipelines/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/2389-research/pipelines/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/2389-research/pipelines/releases/tag/v0.1.0
