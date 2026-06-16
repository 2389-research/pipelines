# DIP143 Subgraph Containment Audit

Scope: every subgraph call site in the repo flagged by issue #34 as needing
explicit `tool_access:` consideration under dippin v0.36.0's DIP143 advisory
lint. Audit was run on commit `b627b43` against tracker `v0.35.1` / dippin
`v0.35.0` (the lockstep pin recorded in `.github/workflows/dev_loop_smoke.yml`).
dippin doctor against these files reports `DIP143: 0` (no firings on the
currently pinned lint scope); the audit covers the boundaries the issue
enumerated regardless.

## TL;DR

Zero LEAKs across all 15 subgraph call sites — 7 SOUND and 8
INTENTIONAL_OPEN per the summary table. No parent sets `tool_access:` at the
subgraph node, so DIP143's "restrictive parent intent silently dropped at the
child boundary" scenario does not exist in this repo. SOUND sites are those
where the child locks its entry/exit; INTENTIONAL_OPEN sites are those whose
child is an implementer/worker that needs tools by design. No `.dip` code
changes are required.

Two adjacent observations are out of scope but worth filing separately:

- **Prompt-only Start/Exit**: `iter_run.dip`, `iter_audit.dip`, and
  `spec_to_sprints_yaml_v2.dip` rely on prompt instructions instead of
  `tool_access: none` to keep their Start/Exit agents tool-free. This is a
  weaker form of containment than the rest of the repo uses, but it is a
  child-internal concern, not a DIP143 subgraph-boundary leak.
- **No Start/Exit at all**: `iter_extract.dip` and `iter_scope.dip` enter
  straight into worker agents. By design — these workflows are themselves the
  workers — but worth tracking as a separate hardening question.

`${ctx.last_response}` remains a cross-node prompt-injection vector across
every subgraph boundary in the repo; `tool_access: none` does not sanitize it.
Tightening that vector is **out of scope** for this audit (see
`docs/agent-node-safety.md`).

## Method

Three questions per site:

1. Does the parent set `tool_access:` on the subgraph node?
2. Are the child workflow's agents independently constrained?
3. Where there's a mismatch, what's the intent — and is it a leak?

A "leak" = parent intends restrictive containment AND child agents are not
independently constrained AND no `tool_access:` is set at the call site.

Verdicts:

- **SOUND** — no parent intent at the call site, child manages its own
  containment appropriately (worker agents intentionally open because they need
  tools; entry/exit locked down where applicable).
- **LEAK** — parent intent exists but is silently dropped at the child
  boundary. Requires a fix.
- **INTENTIONAL_OPEN** — parent deliberately invokes the subgraph without
  containment because the child is an implementer that needs tools.

Threat-model reminder: `${ctx.last_response}` is a cross-node prompt-injection
vector that `tool_access: none` on downstream nodes does NOT sanitize. Sites
where containment matters because of `last_response` flow are called out
explicitly.

Baseline `dippin doctor` per audited file (pre-audit):

| File | Errors | Warnings | Hints | DIP143 |
| --- | --- | --- | --- | --- |
| `greenfield/greenfield.dip` | 0 | 2 | 4 | 0 |
| `iterative/iter_dev.dip` | 0 | 1 | 0 | 0 |
| `sprint/spec_to_ship_yaml.dip` | 0 | 6 | 0 | 0 |
| `sprint/sprint_runner.dip` | 0 | 1 | 0 | 0 |
| `sprint/sprint_runner_yaml.dip` | 0 | 5 | 1 | 0 |
| `sprint/sprint_runner_yaml_v2.dip` | 0 | 5 | 2 | 0 |
| `sprint/verify_sprints_runner.dip` | 0 | 2 | 1 | 0 |

## Site-by-site

### `greenfield/greenfield.dip:140` — `L1_Discovery` invoking `greenfield_discovery.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `Start` and `Exit` both
  `tool_access: none`. Worker analyzers (`SourceAnalyzer`, `DocResearcher`,
  `SdkAnalyzer`, etc.) are intentionally open because they read source trees
  and external docs.
- **Stakes**: child analyzers could call file/shell tools if unrestricted —
  expected, since discovery requires it.
- **Verdict**: SOUND
- **Rationale**: Parent has no intent to restrict; child's `tool_access: none`
  on its boundary agents is the correct shape.
- **Action**: NONE

### `greenfield/greenfield.dip:165` — `L2L3_Synthesis` invoking `greenfield_synthesis.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `Start`/`Exit`
  `tool_access: none`; synthesis workers (`FeatureDiscoverer`, `Synthesizer`,
  …) open by design.
- **Stakes**: synthesis agents need read access to the raw discovery output.
- **Verdict**: SOUND
- **Rationale**: Same pattern as L1; child boundary locked, workers open.
- **Action**: NONE

### `greenfield/greenfield.dip:193` — `L4L5_Validation` invoking `greenfield_validation.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `Start`/`Exit`
  `tool_access: none`; validation/test-vector workers open by design.
- **Stakes**: validation needs to read specs and write test vectors.
- **Verdict**: SOUND
- **Rationale**: Same pattern.
- **Action**: NONE

### `greenfield/greenfield.dip:214` — `L6L7_Review` invoking `greenfield_review.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `Start`/`Exit`
  `tool_access: none`; review/auditor agents open by design.
- **Stakes**: review reads finished spec artifacts.
- **Verdict**: SOUND
- **Rationale**: Same pattern.
- **Action**: NONE

### `iterative/iter_dev.dip:58` — `bootstrap_extract` invoking `iter_extract.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: no `tool_access:` on any agent.
  Child enters directly into worker agents (`validate_existing`,
  `extract_agent_*`, parallel reviewers).
- **Stakes**: extraction agents need broad tool access to scan source.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: The child IS the extractor; restricting it would defeat its
  purpose. There is no parent intent at the call site to silently drop, so
  this is not a DIP143 leak. The lack of a guarded entry node is an
  iter-workflow-internal concern, separate from subgraph containment.
- **Action**: NONE

### `iterative/iter_dev.dip:61` — `bootstrap_scope` invoking `iter_scope.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: no `tool_access:` on any agent.
  Child enters directly into `validate_existing_roadmap`.
- **Stakes**: scoping agents need broad tool access to read backlog and
  roadmap files.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Same shape as `bootstrap_extract`.
- **Action**: NONE

### `iterative/iter_dev.dip:64` — `run_iteration` invoking `iter_run.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: partial — `Start` and `Exit`
  exist with prompt-only "do not read or write any files" instructions, but
  no `tool_access: none`. Worker agents (`implement_task`, `decompose_tasks`,
  reviewers) are intentionally open.
- **Stakes**: `implement_task` is the implementer; broad tool access is the
  point.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Parent has no intent to restrict; child workers must be open.
  Prompt-only Start/Exit is a weaker shape than `tool_access: none` elsewhere
  in the repo, but that is an iter-workflow-internal hardening concern, not a
  DIP143 subgraph-boundary leak.
- **Action**: NONE

### `iterative/iter_dev.dip:67` — `audit_iteration` invoking `iter_audit.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: partial — `Start`/`Exit` use
  prompt-only constraints; tier auditor workers are intentionally open.
- **Stakes**: auditors read artifacts and grade them.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Same shape as `run_iteration`.
- **Action**: NONE

### `sprint/spec_to_ship_yaml.dip:45` — `decompose` invoking `spec_to_sprints_yaml.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: child's `Start`/`Exit` are
  deterministic **tools** (no LLM) — automatic containment at the boundary.
  Decomposition agents (`analyze_spec`, `decompose_*`, `critique_*`, etc.) are
  intentionally open: they read the spec and emit ledger/sprint files.
- **Stakes**: decomposition writes `.ai/ledger.yaml` and `SPRINT-*.{md,yaml}`
  — needs tools.
- **Verdict**: SOUND
- **Rationale**: Tool-node entry/exit is the strongest possible boundary
  containment; workers open by design.
- **Action**: NONE

### `sprint/spec_to_ship_yaml.dip:93` — `run_sprints` invoking `sprint_runner_yaml.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `sprint_runner_yaml.dip`
  `Start`/`Exit` are agents with `tool_access: none`. Internally it invokes
  `sprint_exec_yaml.dip` (audited separately at
  `sprint_runner_yaml.dip:132`).
- **Stakes**: the runner itself only orchestrates; the underlying executor is
  where tool access matters.
- **Verdict**: SOUND
- **Rationale**: Two-hop boundary; each hop locks its own entry/exit.
- **Action**: NONE

### `sprint/sprint_runner.dip:47` — `execute_sprint` invoking `sprint_exec.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: partial — only the
  `ReviewAnalysis` verdict-synthesis agent at line 341
  (`tool_access: none` at line 347) is locked down; there is no
  `Start`/`Exit` constraint at the boundary. The implementer
  (`ImplementSprint`), reviewers, and critique agents are open by design.
- **Stakes**: implementer writes code; this is the bug-4 vector class but at
  the older TSV-ledger runner.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Sprint execution requires tools; restricting the call site
  would defeat the workflow. No parent intent at the call site, no DIP143
  leak.
- **Action**: NONE

### `sprint/sprint_runner_yaml.dip:132` — `execute_sprint` invoking `sprint_exec_yaml.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `Start`/`Exit`
  `tool_access: none` (lines 15/23), plus the `ReviewAnalysis` verdict-
  synthesis agent at line 548 (`tool_access: none` at line 553).
  Implementer/reviewer/critique agents are open by design.
- **Stakes**: YAML-ledger executor; implementer writes code.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Boundary hardened where it can be; implementer must be open.
- **Action**: NONE

### `sprint/sprint_runner_yaml_v2.dip:132` — `execute_sprint` invoking `sprint_exec_yaml_v2.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — `Start`/`Exit`
  `tool_access: none` (lines 15/23), plus the `ReviewAnalysis` verdict-
  synthesis agent at line 870 (`tool_access: none` at line 875). Worker
  stack (`PlanManager`, `ImplementSprint`, `RecoveryManager`, reviewers,
  critique agents) intentionally open.
- **Stakes**: highest in the repo — this is the v2 sprint executor that ships
  real implementation. See the highest-stakes paragraph below.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Implementer must call tools; boundary agents are locked.
- **Action**: NONE

### `sprint/sprint_runner_yaml_v2.dip:226` — `redecompose_sprint` invoking `spec_to_sprints_yaml_v2.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: partial — child's
  `Start`/`Exit` are agents with prompt-only "Begin … / … complete."
  instructions; no `tool_access: none`. Workers (`analyze_spec`,
  `decompose_*`, `critique_*`, `merge_decomposition`, `present_plan`,
  `apply_feedback`, `write_sprint_docs`) intentionally open.
- **Stakes**: re-decomposition rewrites ledger entries mid-execution.
- **Verdict**: INTENTIONAL_OPEN
- **Rationale**: Re-decomposition needs tools to read/write the ledger and
  sprint files. The prompt-only boundary in the child is a separate
  hardening question (see Adjacent observations); it does not create a
  DIP143 leak because the parent does not set restrictive intent at the call
  site.
- **Action**: NONE

### `sprint/verify_sprints_runner.dip:97` — `verify_sprint` invoking `verify_sprint.dip`

- **Parent tool_access at call site**: no
- **Child agents independently constrained**: yes — child's `Start` is a
  deterministic tool, `Exit` is an agent with `tool_access: none` (line 32).
  Verification workers (mechanical checks plus Opus semantic review) open by
  design.
- **Stakes**: verifier reads artifacts and writes verification reports.
- **Verdict**: SOUND
- **Rationale**: Tool-node entry + locked Exit + worker-open shape is the
  correct pattern.
- **Action**: NONE

## Summary table

| File:line | Node | Verdict | Action |
| --- | --- | --- | --- |
| `greenfield/greenfield.dip:140` | `L1_Discovery` | SOUND | NONE |
| `greenfield/greenfield.dip:165` | `L2L3_Synthesis` | SOUND | NONE |
| `greenfield/greenfield.dip:193` | `L4L5_Validation` | SOUND | NONE |
| `greenfield/greenfield.dip:214` | `L6L7_Review` | SOUND | NONE |
| `iterative/iter_dev.dip:58` | `bootstrap_extract` | INTENTIONAL_OPEN | NONE |
| `iterative/iter_dev.dip:61` | `bootstrap_scope` | INTENTIONAL_OPEN | NONE |
| `iterative/iter_dev.dip:64` | `run_iteration` | INTENTIONAL_OPEN | NONE |
| `iterative/iter_dev.dip:67` | `audit_iteration` | INTENTIONAL_OPEN | NONE |
| `sprint/spec_to_ship_yaml.dip:45` | `decompose` | SOUND | NONE |
| `sprint/spec_to_ship_yaml.dip:93` | `run_sprints` | SOUND | NONE |
| `sprint/sprint_runner.dip:47` | `execute_sprint` | INTENTIONAL_OPEN | NONE |
| `sprint/sprint_runner_yaml.dip:132` | `execute_sprint` | INTENTIONAL_OPEN | NONE |
| `sprint/sprint_runner_yaml_v2.dip:132` | `execute_sprint` | INTENTIONAL_OPEN | NONE |
| `sprint/sprint_runner_yaml_v2.dip:226` | `redecompose_sprint` | INTENTIONAL_OPEN | NONE |
| `sprint/verify_sprints_runner.dip:97` | `verify_sprint` | SOUND | NONE |

## Highest-stakes boundaries

Per issue #34 and `docs/agent-node-safety.md`, the sprint runners are the
highest-stakes containment boundaries in the repo: a leak here is the PR #25
bug-4 vector at the subgraph layer (an unconstrained executor that can shell
out, write files, and call MCP tools while acting on attacker-influenced
`${ctx.last_response}` from an upstream node).

For `sprint_runner_yaml_v2.dip`:

- `execute_sprint:132` invokes `sprint_exec_yaml_v2.dip`. The child locks
  `Start`/`Exit` with `tool_access: none` and locks the failure agent. The
  implementer (`ImplementSprint`), plan manager, reviewers, and critique
  agents are open by design — restricting them would defeat the workflow's
  purpose. The parent does not set `tool_access:` at the call site, so no
  DIP143 leak. Verdict: INTENTIONAL_OPEN.
- `redecompose_sprint:226` invokes `spec_to_sprints_yaml_v2.dip`. The child's
  `Start`/`Exit` are prompt-only-constrained agents, not `tool_access: none`.
  This is a weaker boundary than the executor's, but it is an internal
  hardening question (the child workflow can be tightened independently);
  the DIP143 question — does the parent silently override the child? — does
  not apply here, because the parent declares no intent at the call site.
  Verdict: INTENTIONAL_OPEN.

The remaining bug-4 vector at this layer is **not** containment but
`${ctx.last_response}` flow. `tool_access: none` does not sanitize that
input; adding it at the subgraph node would not close the attack surface
that PR #25's bug 4 identified. Tightening `${ctx.last_response}` is the
right follow-up.

## Out of scope

- Refactoring subgraph call structure.
- Upgrading the dippin/tracker pin to chase newer lint scope.
- Touching the `${ctx.last_response}` injection surface — separate hardening.
- Tightening child-internal Start/Exit agents (e.g., switching the
  `iter_run.dip` / `iter_audit.dip` / `spec_to_sprints_yaml_v2.dip` Start/Exit
  from prompt-only to `tool_access: none`). These are child-workflow
  hardening tasks orthogonal to DIP143.
