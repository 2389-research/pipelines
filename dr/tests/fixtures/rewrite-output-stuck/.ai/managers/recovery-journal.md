# Urecovery Journal

## Sprint 006 — Conversational Matching & Recommendation Engine
**Date:** 2026-05-11T18:44:39Z
**Root cause:** scope
**Attempt count:** 1
**Outcome observed:** pipeline_failed — zero implementation artifacts produced

### Failure detail
Sprint 006 attempted to implement three distinct subsystems in a single
execution cycle:

1. **Linear conversational state machine + REST API** — preference-slot capture
   (activity, time, location, group-size) and question routing.
2. **Recommendation / ranking engine + UI** — shift matching, relevance
   scoring, authenticated personalisation from volunteer history (FR15), and
   the `RecommendationCards` component.
3. **Nonlinear / adaptive parsing** — free-text slot-filling ("I have a group
   of 20 on Saturday") with adaptive follow-up that skips already-answered
   questions.

All six expected artifacts (`conversation_engine.*`, `recommendation.*`,
`api/conversation.*`, `RecommendationCards.*`, and both test files) are absent
from the repository. The upstream precondition file (`ChatShell.js`, Sprint
005) is present and clean — the failure is entirely internal to Sprint 006.

The nonlinear-parsing requirement (item 3) carries a qualitatively higher
implementation risk than the other two items because it requires NLP-adjacent
slot-filling heuristics with no prior art in the codebase. Bundling it with
items 1 and 2 meant a single failure point could — and did — block delivery of
all three subsystems.

### Planning gap
No entry for Sprint 006 exists in `.ai/managers/plan-journal.md`. The
PlanManager risk-assessment step was skipped, so the complexity of the
nonlinear-parsing requirement was never flagged before execution. This
contributed directly to the failure.

### PlanManager alignment
No — PlanManager entry for Sprint 006 was absent from plan-journal.md.

### Scope fence violations
None detected. off_limits constraints were not breached (no ledger writes, no
downstream sprint implementation). The failure was execution volume, not a
boundary violation.

### Recommendation
REDECOMPOSE — split into three sequentially dependent sub-sprints:

| Sprint | Title | Key deliverable |
|--------|-------|-----------------|
| 006A | Core Conversational Engine & API | Linear state machine + REST API |
| 006B | Recommendation Engine, Personalisation & UI | Ranking algorithm + RecommendationCards |
| 006C | Nonlinear & Adaptive Conversational Logic | Slot-filling parser + adaptive follow-up |

Full decomposition rationale and proposed DoD per sub-sprint recorded in
`.ai/sprints/SPRINT-006-recovery-analysis.md`.
Redecompose request written to `.ai/redecompose-request.yaml`.

### Unresolved items (blocked until 006C completes)
- Downstream sprints 014, 018, 023 — all declare `006` as a dependency.
- `depends_on` for those sprints must be updated to reference `006C` once the
  redecomposition is accepted.

### Required next action before 006A executes
PlanManager must write a journal entry covering the risk profile of 006A–006C,
with explicit attention to the slot-filling complexity isolated in 006C.

## Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing
**Date:** 2026-05-11T19:33:59Z
**Root cause:** implementation
**Failure detail:** Scope fence breach. The implementer pulled in artifacts from Sprints 004 and 005. A subsequent attempt to delete them left the Makefile in a broken state (checking for non-existent files), causing 'make build' to fail.
**PlanManager alignment:** Yes. Risk #2 (Makefile hardcoding) and Risk #4 (High artifact count) predicted the validation failure and complexity-related drift.
**Recommendation:** RETRY
**Recovery notes:** Perform a clean-room implementation of Sprint 003. Explicitly purge all Sprint 004/005 residue from the Makefile and git index. Ensure the UI shell (app.html) is robustly integrated with the discovery components.

## Sprint 004 — Authentication & Returning User Detection
**Date:** 2026-05-11T20:20:00Z
**Root cause:** scope
**Failure detail:** The sprint scope was too broad, encompassing four authentication providers, session management, RBAC, and SMS consent gating. This complexity resulted in a scope breach during Sprint 003 and a complete failure (zero artifacts) in the current attempt.
**PlanManager alignment:** Yes. PlanManager correctly flagged the complexity of multiple auth flows and session management as high risks.
**Recommendation:** REDECOMPOSE
**Recovery notes:** Split the requirements into three smaller sprints: 004A (Primary Auth & Sessions), 004B (Social/Fallback Auth), and 004C (Returning User Detection & RBAC).
