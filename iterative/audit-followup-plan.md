# iter Pipeline Audit Follow-Up Plan

**Source:** 8-lane review-squad audit, 2026-05-09
**Scope:** 31 CRITICAL findings → 7 PR-shippable phases
**Sequencing:** safest first, design-heavy last. One phase = one branch, one PR.

> Pre-implementation rule: at branch time, re-pull file:line refs from the .dip files. Audit refs may have drifted between audit and implementation.

## TL;DR

| # | Phase | Items | Risk | Pattern |
|---|---|---|---|---|
| 8 | Bash pipefail traps | 5 | low | mirror Phase 7 (add `\|\| echo`) |
| 9 | Unrouted fail outcomes | 6 | low | mirror Phases 1-6 (tolerated fail-edge) |
| 10 | Cost & loop budgets | 5 | medium | round counters per `bootstrap_scope` |
| 11 | State-file lifecycle | 5 | medium | atomic writes + cleanup |
| 12 | Architectural contracts | 3 | high | semantics changes — design first |
| 13 | PAR redesign | 2 | high | provider diversity + tier3 dedup |
| 14 | Production hardening | 5 | high | runtime + recovery + STATUS integrity |

**Total:** 31 findings closed. Phases 8-9 ship fast (mirror prior playbooks). Phases 12-14 require design discussion before coding.

---

## Phase 8 — Bash pipefail traps

**Findings (5):** `check_scope_resume`, `check_extract_resume`, `validate_extraction`, `check_citations`, `report_clean`.

**Pattern:** `set -euo pipefail` + `grep`/`ls`/`wc` pipelines that exit-1 on legitimate "no matches" → downstream routing-on-stdout sees no token → silent halt.

**Approach:** Append `|| echo "<expected default>"` to each failing pipeline so the empty case still emits a routing token. Mirrors `iter_run.dip:1102` (Phase 7).

**Files:** `iter_run.dip`, `iter_audit.dip`, `iter_extract.dip`.

**Verify:** Run each tool against an empty-match fixture; expect `STATUS: success` and the routing token in stdout.

---

## Phase 9 — Unrouted fail outcomes

**Findings (6):** `par_omission` reviewers, `extract_agents`, `mark_task_in_progress`, `mark_task_done`, `create_fix_task`, `run_impacted_scenarios`.

**Pattern:** Node missing `when ctx.outcome = fail` edge → silent halt on tool/agent failure. Same class as Phases 1-6.

**Approach:** Add `<node> -> <recovery> when ctx.outcome = fail label: tolerated` to each, routing to the natural recovery node (next in lane, or `wrap_up`).

**Files:** `iter_run.dip`, `iter_extract.dip`.

**Verify:** Force-fail each node (inject `exit 1` or fake-fail the agent); confirm pipeline routes through fail-edge to expected recovery, not silent halt.

---

## Phase 10 — Cost & loop budgets

**Findings (5):** `adjust_run_scope`, `fix_spec_issues`, `fix_quality_issues`, `validate_wrap_up`, `final_audit` outer loop.

**Pattern:** `restart: true` edges with no per-loop round counter — pathological agent can spin until workflow-level `max_restarts`. Cost runaway risk.

**Approach:** Add inline counter pattern matching `bootstrap_scope`; route to graceful give-up after N rounds.

**Suggested N (review before coding):**
- `adjust_run_scope`: 3
- `fix_spec_issues`: 4
- `fix_quality_issues`: 4
- `validate_wrap_up`: 2
- `final_audit` outer: 2

**Files:** `iter_run.dip`, `iter_audit.dip`.

**Verify:** Force the loop's exit condition to never resolve; confirm graceful exit after N rounds with appropriate STATUS.

---

## Phase 11 — State-file lifecycle

**Findings (5):**
- `task_status.txt`: `in_progress` not reset on resume
- `scope.md`: implicit handoff between bootstrap and run
- `impl_status.txt`: not cleaned on lane success
- `iter-audit-result.txt`: non-atomic write
- `tier_findings.md`: not truncated before tier write

**Pattern:** State files under `.ai/` are read by downstream tools but inconsistently cleaned, reset, or atomically written. Restart, crash, or disk-full leaks stale state into the next run.

**Approach:** Standardize atomic-write (`.tmp` + rename) + explicit cleanup hooks at lane boundaries. Bundle the 5 fixes so reviewers see the consistent pattern.

**Files:** `iter_run.dip`, `iter_dev.dip`, `iter_audit.dip`.

**Verify:** Inject `kill -9` between write and rename for each file; next run reads valid state, not partial.

---

## Phase 12 — Architectural contracts (design-first)

**Findings (3):**
1. Walking-skeleton heading mismatch — free-form heading hides spec drift.
2. Exit-always-success laundering — Exit nodes emit `STATUS: success` regardless of workflow outcome.
3. `in_progress` filter — failed `in_progress` tasks aren't surfaced.

**Pattern:** Not bugs; intentional contracts that hide failure signal. Changing them risks breaking downstream consumers (scripts that read STATUS lines, dashboards that read task status).

**Pre-implementation:** Doctor Biz reviews each contract-shift before code. Decisions needed:
1. Walking skeleton: enforce regex/enum on heading, or keep free-form?
2. Exit semantics: should Exit propagate workflow STATUS instead of always-success?
3. `in_progress`: should `mark_task_in_progress` fail-edge surface a visible failure signal?

**Files:** `iter_dev.dip` (Exit), `iter_run.dip` (heading, in_progress).

---

## Phase 13 — PAR redesign

**Findings (2):**
1. All 8 PAR blocks use the same model for both reviewers (no provider diversity → 2x cost for marginal additional signal).
2. `par_tier3` dispatches sentinel evaluation twice (intent unclear).

**Approach:**
1. Assign different `provider:model` pairs to `_a` and `_b`.
   **Proposed matrix (review):** `_a: claude-opus-4-7`, `_b: gemini-3-flash-preview` (cost-balanced adversarial diversity).
2. Investigate `par_tier3` — confirm intent, then keep+document or collapse to single execution.

**Files:** `iter_run.dip`, `iter_audit.dip`.

**Verify:** Run pipeline end-to-end on representative fixture; compare audit signal quality before/after.

**Pre-implementation:** Doctor Biz confirms model-pair matrix and `par_tier3` intent.

---

## Phase 14 — Production hardening

**Findings (5):**
- #20 `build_coverage_ledger` / `patch_extractions`: inline prose right before STATUS confuses parser
- #28 gpt-5.5: STATUS line sometimes truncated mid-response
- #29 sentinel: 300s timeout shared across all tools (slow tool starves fast tool)
- #30 `iteration_failure_handler`: can self-overflow `loop_context` if its own handler fails
- #31 disk-full: 0-byte file written, next read returns empty content → silent state corruption

**Approach:**
- #20 + #28: Tracker-level retry-on-no-STATUS shim, or `STATUS:` enforcement suffix in agent prompts.
- #29: Per-tool timeout config.
- #30: Depth cap on failure-handler invocations.
- #31: Size-check + retry on state read.

**Files:** `iter_dev.dip` + tracker runtime (some out of this repo).

**Pre-implementation:** Confirm in-scope (this repo) vs upstream (tracker runtime). #29 and #31 likely need a tracker-runtime PR coordinated with this work.

---

## Rules of Engagement

1. **One phase, one branch, one PR.** Branch name: `audit/phase-N-<slug>`.
2. **No scope creep.** Related issues found during implementation → log them, don't fix in-band.
3. **Re-read before edit.** Pull fresh file:line refs at branch time; audit refs may have drifted.
4. **Test each fix.** Use the Verify line per phase. Smallest fixture that proves the fix.
5. **Phases 12-14 blocked on design notes.** No branch until Doctor Biz reviews the open questions.

## Suggested Order

```
8 → 9 → 10 → 11        (low/medium-risk, mirrors prior playbooks)
                  ↓
              12, 13, 14   (high-risk, paced by design discussion)
```

**Estimate:** phases 8-11 → 1-2 days each. Phases 12-14 → paced by review.
