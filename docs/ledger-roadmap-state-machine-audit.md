# Ledger/Roadmap State-Machine Reconciliation (issue #109)

Scope: the ledger/roadmap state-machine shell logic that issue #109 flagged as
copy-pasted ~22× across 12 `.dip` workflows — (a) the `awk` scanner over
`.ai/ledger.tsv` that picks the next non-completed sprint plus the row-status
update logic in the sprint family, and (b) the roadmap status-counting /
scanning blocks in the iterative orchestrators. Audit run against the
repo-pinned toolchain (tracker `v0.35.1` / dippin `v0.35.0`, the lockstep pin
in `.github/workflows/dev_loop_smoke.yml`).

## TL;DR

No `.dip` workflow logic was changed. The duplicated blocks were checked
byte-for-byte and fall into two buckets: blocks that are **already byte-identical
and meant to stay so**, and blocks the issue called "duplication" that are
actually **per-node-intent variation** (or were over-counted in the issue). True
single-source sharing is not viable under the distribution model (same gate as
issue #108 / #107), so the applied change is:

1. A drift-prevention gate — `dev_loop/tests/test_ledger_roadmap_identical.sh` —
   asserting the six genuinely-identical clusters stay identical, mirroring the
   `test_bootstrap_identical.sh` / `test_persist_verdict_identical.sh` precedent.
2. This audit, documenting the reconcile/waive decision per block.

There is no behavior change to any pipeline.

## Why no shared helper / subgraph (the design gate)

The issue suggested extracting the scanner / counter / row-update into one
shared shell helper (`dev_loop/scripts/lib`-style) or a shared subgraph node.
Neither survives how these pipelines actually run:

- **Packed distribution inlines shell.** These workflows are distributed via
  `dippin pack` → `.dipx` (a zip) to run against arbitrary target repos. tracker
  invokes a tool node's `command:` as inlined shell, and a packed bundle does
  **not** ship `dev_loop/scripts/lib/`. A sourced lib helper would simply not be
  on disk at the target. This is the exact constraint that reshaped issue #107
  (`command_file:` is path-only; the bundle inlines content), whose resolution
  was "keep the inline copies, enforce with a byte-identity test."
- **Subgraphs compose whole workflows, not snippets.** `dippin pack` *does*
  bundle a referenced subgraph workflow into the `.dipx` (verified: packing
  `sprint/sprint_runner.dip`, whose `execute_sprint` subgraph has
  `ref: sprint_exec.dip`, produces a bundle carrying `workflows/sprint_exec.dip`
  with a manifest + sha). So a subgraph **file** survives distribution. But a
  `subgraph` references an *entire* `.dip` workflow and executes as a unit
  between two edges. The duplicated blocks here are individual tool nodes
  interleaved with agent nodes and conditional edges, that read/write files like
  `.ai/current_sprint_id.txt` and emit routing markers (`current-<id>`,
  `next-<id>`, `all_done`, `in_progress-<id>`, `progress-…`) the parent's edges
  match on. Extracting each into a single-node subgraph would force an edge and
  marker-contract rewrite across all 12 files, would have to round-trip the
  marker back to the parent for routing, and would *increase* file count — the
  opposite of a surgical cleanup, and a behavior-risk on every pipeline.
  (DIP143's reusable-subgraph advisory is a dippin v0.36 concern; chasing it is
  out of scope under the current pin, per `docs/dip143-subgraph-audit.md`.)

So true single-source sharing is infeasible without an invasive rewrite. Per
the #107/#108 precedent, the acceptable outcome is "keep the inline copies,
enforce the meant-to-be-identical ones with a gate, document the rest."

## The drift-prevention gate

`dev_loop/tests/test_ledger_roadmap_identical.sh` extracts each of the following
clusters by content anchors (no markers are added to the `.dip` files, so
tracker's shell/coverage parsing is untouched) and `cmp`s every member of a
cluster against the first. It is shellcheck-clean (`--shell=sh`) and wired into
`dev_loop_smoke.yml` next to the other identity gates. A member whose start/end
anchor is missing, duplicated, or out of order is a hard fail (non-zero exit
with a per-cluster message), so the gate cannot be silently defeated by renaming
an anchor or deleting a node. Its invariant is that a cluster's copies stay
byte-identical to *each other*: any member that diverges from the rest fails the
`cmp`. An edit applied uniformly to every member is intentionally allowed — that
keeps the copies in sync, which is exactly the property being protected.

| Cluster | Members | What stays identical |
| --- | --- | --- |
| `scanner-A` | `sprint_exec.dip`, `sprint_exec-cheap.dip` | 3-tier next-sprint scanner that writes `.ai/current_sprint_id.txt` and emits `current-<id>` (`SetCurrentSprint`) |
| `scanner-B` | `sprint_runner.dip`, `sprint_runner-cheap.dip`, `local_code_gen/sprint_runner_qwen.dip` | guarded single-tier scanner with `no_ledger`/`all_done` sentinels, emits `next-<id>` (`check_ledger`) |
| `row-in_progress` | `sprint_exec.dip`, `sprint_exec-cheap.dip`, `sprint_runner-cheap.dip`, `local_code_gen/sprint_runner_qwen.dip` | row-status `in_progress` update (`awk` rewrite of `$3`/`$5` + `mv .tmp`) |
| `row-completed` | `sprint_exec.dip`, `sprint_exec-cheap.dip`, `sprint_runner-cheap.dip`, `local_code_gen/sprint_runner_qwen.dip` | row-status `completed` update (`awk` rewrite of `$3`/`$5` + `mv .tmp`) |
| `progress-counter` | `sprint_runner.dip`, `sprint_runner-cheap.dip`, `local_code_gen/sprint_runner_qwen.dip` | total + `completed\|\|skipped` progress tally (`report_progress`) |
| `validate-jsonl` | `local_code_gen/spec_to_sprints.dip`, `local_code_gen/spec_to_sprints_lowreason.dip`, `local_code_gen/architect_only.dip` | `validate_output` ledger/JSONL three-way consistency sub-block |

The gate intentionally does **not** assert identity across the per-node-intent
variations below — forcing those to converge would be a behavior change, not a
cleanup (the #108 lesson on golden tests over legitimately-divergent blocks).

## What the issue called "duplication," checked against current `main`

| Claim | Reality | Action |
| --- | --- | --- |
| Next-sprint scanner copied across the sprint family | Two **non-interchangeable** wrapper variants. Group A (3-tier fallback → `current-<id>`, writes the id file) is for the single-sprint executors; Group B (`no_ledger`/`all_done` guards → `next-<id>`) is for the looping runners. Within each group the bodies are byte-identical. | Group A + Group B each gated (`scanner-A`, `scanner-B`); the A↔B difference is per-node intent and **waived** |
| Row-status update copied across the sprint family | Byte-identical bodies; the only differences are the status literal written to `$3` (`in_progress` / `completed` / `failed`) and the trailing `printf` marker — per-node intent. | `in_progress` and `completed` families each gated (`row-in_progress`, `row-completed`); the `failed` variant exists only in `sprint_exec.dip` (no cross-family duplicate), so there is nothing to gate there |
| Progress counter copied across the runners | Byte-identical across all three runners. | gated (`progress-counter`) |
| `megaplan.dip` ledger blocks are the same scanner / row-update | Different operations. `DetermineSprintId` computes the next **new** id (`max + 1`), not the next *incomplete* sprint; `SyncLedger` rewrites `$2` + sets status `planned` with an append-if-absent fallback. Neither matches the sprint-family shapes. | **waived** (distinct intent) |
| `iter_dev.dip` reuses one `grep -c Status` trio across 4 nodes | The full pending/in_progress/done trio appears in `check_resume` (45–47) and `report_loop_progress` (112–114); these differ only in the path *variable* (`$iter_dir/roadmap.md` vs `$roadmap`) which resolves to the same path — local-variable naming, not behavior drift. `check_termination` (81–82) is a 2-line subset (no `done` line, computed downstream) and `update_final_progress` (208–209) is a distinct done+bare-total pair. Each reflects its node's job. | **waived** (per-node intent; no behavior difference) |
| `iter_run.dip` reimplements the same state-machine block | Lines 64 and 527 are an `awk` next-pending scanner and an `awk` pending→in_progress mutator — not the `grep -c` trio. They are different operations from the sprint-family `ledger.tsv` blocks (they target `docs/iterations/roadmap.md` markdown, not a TSV). | **waived** (different data model + operation); see heading-match note below |
| `iter_audit.dip` / `iter_scope.dip` reimplement the counter | Over-counted: neither contains the pending/in_progress/done counting trio. `iter_scope.dip` has `grep -c '^### ITER-'` (counts headings) and a `grep -q '\*\*Status:\*\*'` existence check — different shapes. | **waived** (no matching block exists) |
| A `done` row status is part of the ledger state machine | No `.dip` writes `$3="done"` to `.ai/ledger.tsv`; the statuses written are `in_progress`, `completed`, `failed` (and `planned` in megaplan). The `done` token only appears as a shell tally variable for `completed\|\|skipped` rows and in roadmap-side markdown. | n/a (clarification) |
| `validate_output` ledger block copied across spec_to_sprints + architect_only | `sprint/spec_to_sprints.dip` is the legacy two-way (ledger-vs-files) check with no JSONL branch. The JSONL three-way sub-block is byte-identical across `local_code_gen/spec_to_sprints.dip`, `…_lowreason.dip`, and `architect_only.dip`. The architect_only *enclosing node* genuinely differs (label `Validate Sprint Files`, 10s timeout, no `marker_grep`, no empty-ledger/bad-cols checks, `validate-pass`/`validate-fail` exit contract). | shared sub-block gated (`validate-jsonl`); the legacy two-way variant and the architect_only node envelope are **waived** |

## Files the detection command surfaces but that carry no executable block

`find . -name '*.dip' … | xargs grep -l 'ledger.tsv'` also matches the five
`local_code_gen/research/reasoning-tiers/dips/upto_architect_*.dip` files. These
reference `ledger.tsv` only in header comments and the `goal:` prose (describing
what the pipeline produces) — they contain no scanner, counter, or row-update
shell. Like the agent-prompt mentions waived in #108, prose is an interface, not
the executable smell, so they are not gated. (The issue's roadmap detection
command, `grep -ln 'Status:** pending'`, likewise surfaces
`iter_audit`/`iter_extract`/`iter_scope` — which use a different,
non-status-counting `grep` shape — while *not* matching `iter_dev`, whose trio
uses the escaped `'^\*\*Status:\*\* pending'` form; the command is a locator, not
an exact-match census.)

## The `iter_run.dip` heading-match difference (examined, waived)

The next-pending scanner (`find_next_iteration`, line 64) matches iteration
headings with `/^##+ /` (any heading level ≥ 2), while the pending→in_progress
mutator (`mark_iteration_in_progress`, line 527) matches `/^### /` (exactly h3).
This is **not** treated as a bug to "fix" by homogenizing:

- The canonical roadmap card format written by `iter_scope.dip` is `### ITER-NNNN`
  (h3), and `iter_run.dip` itself normalizes a legacy `## Walking skeleton (…)`
  (h2) heading into `### ITER-…` earlier in the same run (lines 173–174).
- The scanner is deliberately tolerant (locate the next pending iteration even
  if a heading level was not yet normalized); the mutator deliberately targets
  the canonical h3 card it is about to edit in place.
- Narrowing the scanner to `^### ` could drop detection of a not-yet-normalized
  legacy heading; widening the mutator to `^##+ ` could let it rewrite the wrong
  heading. Either edit is a behavior change on real roadmaps, not a cleanup.

So the asymmetry is recorded here as intentional and left unchanged, consistent
with the #108 rule that detection/match *breadth* is behavior, not drift.

## Acceptance criteria

- **Remediation applied so the pattern no longer recurs** — the six
  meant-to-be-identical clusters are now gated; future drift fails CI.
- **All instances resolved or waived with rationale** — see the table above;
  every cited instance is either gated or waived with a reason.
- **Re-run the detection command** — the blocks still exist by design (the
  distribution model forecloses single-sourcing them); the gate + this audit
  are the documented remediation, mirroring issues #107 and #108.
