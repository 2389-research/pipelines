# Build-System Detection Reconciliation (issue #108)

Scope: the toolchain-detection if/elif ladder
(`pyproject.toml` / `package.json` / `go.mod` / `Cargo.toml`, sprint family
also `Package.swift`) that issue #108 flagged as copy-pasted ~21× across the
`.dip` workflows. Audit run against the repo-pinned toolchain
(tracker `v0.35.1` / dippin `v0.35.0`, the lockstep pin in
`.github/workflows/dev_loop_smoke.yml`).

## TL;DR

The single applied change is a one-place, sprint-family-contract-faithful
drift fix (a behavior change only on the pathological Swift+Python/Node
polyglot, where it fixes a latent misdetection):
`Package.swift` was moved to the front of the toolchain-fallback ladder in
the two YAML sprint executors (`sprint_exec_yaml.dip`,
`sprint_exec_yaml_v2.dip`) so all swift-supporting sprint nodes share the
family's swift-first order. Everything else the issue enumerated is
**explicitly waived** with rationale below: the suggested shared-helper
mechanism is not viable under the distribution model, the remaining "drift"
is either stale or per-node intent, and harmonizing detection *order* across
the rest of the ladders would be a silent behavior change on polyglot repos,
not a cleanup.

## Why no shared helper / subgraph (the design gate)

The issue suggested extracting one helper (a sourced shell function under
`dev_loop/scripts/lib`, or a reusable subgraph) and calling it everywhere.
Neither survives how these pipelines actually run:

- **Packed distribution inlines shell.** These workflows are distributed via
  `dippin pack` → `.dipx` to run against arbitrary target repos. tracker
  invokes a tool node's `command:` as inlined shell, and a packed bundle does
  **not** ship `dev_loop/scripts/lib/`. A sourced lib helper would simply not
  be on disk at the target. This is the exact constraint that reshaped issue
  #107 (`command_file:` is path-only; the bundle inlines content), whose
  resolution was "keep the inline copies, enforce with a byte-identity test."
- **Subgraphs compose whole workflows, not snippets.** Under the pinned
  dippin, a `subgraph` references an entire `.dip` workflow file. It cannot
  inline a shell snippet into a *sibling* tool node's `command:` block, which
  is where every one of these ladders lives. (DIP143's reusable-subgraph lint
  is a v0.36+ concern; chasing the pin is out of scope per the DIP143 audit.)

So true single-source sharing is infeasible. Per the #107 precedent, the
acceptable outcome is "reconcile real drift, document the rest."

## Why no golden / identity gate

The #107 byte-identity test (`test_bootstrap_identical.sh`) works because
those inline copies are *meant to be identical*. These ladders are not: only
a decision skeleton is shared. Each node legitimately differs in intent and
output —

- `VerifySetup` (speedrun) co-runs tests and emits `ready-<stack>`.
- `ValidateBuild` (sprint) builds+tests and emits `validation-pass-<stack>`.
- baseline-capture (refactor-express) tees full output to a file + sets RESULT.
- final-verification exits 1 on failure.
- per-stack commands differ (build vs test vs `--co` vs lint), as do the
  `tail -40`/`-5`/`-1` log-shaping choices (verbose log vs summary vs
  single-line result — per-node intent, not drift).

A byte-identity gate would create false pressure to homogenize things that
*should* differ, so none was added. The lightweight alternative — a comment
above the reconciled ladders documenting that order is behavior — was added
instead.

## What the issue called "drift," checked against current `main`

| Claimed drift | Reality | Action |
| --- | --- | --- |
| `uv` vs `pip` | Stale. Every Python branch in the `.dip` toolchain-detection ladders already uses `uv run`; no `pip` in these ladders. (A separate `pip install` fallback lives in `local_code_gen/lib/lang_profile.sh`, outside the audited ladders.) | none |
| `tail -40` vs `tail -5` | Not drift. Per-node intent (verbose log vs short summary vs single-line result) inside one file. | none |
| `Package.swift` inclusion | Real, but scoped: swift is the sprint family's contract, absent by design elsewhere. Two YAML execs had swift at branch position 3 instead of 1. | **fixed** (see below) |
| detection **order** across families | Real, but order is behavior. Reordering flips the winner on polyglot repos. | waived (see below) |

## The one applied fix

`sprint_exec_yaml.dip` and `sprint_exec_yaml_v2.dip` `ValidateBuild` nodes
detected `pyproject.toml` / `package.json` *before* `Package.swift`, while the
rest of the sprint family (`sprint_exec.dip`, `sprint_exec-cheap.dip`,
`sprint_runner-cheap.dip`) detect swift first. Within a family whose scope
already includes swift, the positional inconsistency is genuine drift, and it
was a latent bug: a Swift repo carrying an incidental `pyproject.toml` would
have run `pytest` instead of `swift test`. `Package.swift` was moved to the
front in both nodes to match the family's swift-first order. The branch bodies
and emitted markers are unchanged.

## What is waived, and why

- **Detection order outside the swift fix.** `verify_sprint.dip` (go-first,
  python-last) and `pipeline_from_spec.dip` (`py → go → node`) differ from the
  build-and-ship python-first order, and the sprint `CrossValidation` node is
  go-first by design. These pipelines are packed and run against arbitrary,
  often polyglot, target repos (Go service + Python tooling, Node frontend +
  Go backend). First-match-wins ordering *is* the de-facto behavior contract;
  reordering would silently change which toolchain wins. That is a
  behavior-change PR, not a cleanup, and is out of scope for #108.
- **Adding swift to the non-sprint ladders** (build-and-ship, pipeline-gen).
  That is a *new* supported-ecosystem expansion (and a precedence change for
  swift+X polyglots), reasonable as its own feature request but not "reconcile
  drift."
- **Agent-prompt mentions and git-stash `ROOT_FILES` lists.** Several of the
  21 "instances" are natural-language prompt text telling an LLM which
  manifests to read, or stash file-lists in `local_code_gen/`. Those are
  interfaces, not the executable detection smell, and intentionally enumerate
  multiple ecosystems regardless of precedence. Left untouched.
