# Sprint 003 Recovery Analysis — Shared Backend, Data Model & Anonymous Opportunity Browsing

## Root Cause Category
**Implementation failure** (specifically, a major Scope Fence Breach followed by an incomplete cleanup).

## Specific Failure Detail
The implementer (Agent) exceeded the sprint's scope by implementing artifacts and features designated for Sprint 004 (Authentication) and Sprint 005 (Registration/Profile). Although the agent subsequently tried to delete these files, the repository was left in a "polluted" state:
1. **Broken Build:** The `Makefile`'s `build` target still contains hardcoded checks for the deleted Sprint 004/005 files (e.g., `src/services/sms.js`, `src/auth/*`), causing `make build` to fail.
2. **Scope Contamination:** Out-of-scope commits and "deleted-but-tracked" files remain in the `git` index/history, violating the explicit `scope_fence.off_limits` constraint.
3. **Integration Risk:** Concerns were raised regarding the robustness of the `app.html` integration with the `ShiftCalendar` component, suggesting a need for better smoke testing of the UI.

The core deliverables for Sprint 003 (Core Schema, Models, Opportunities API, Urgency Service, and Discovery UI) were actually implemented and their tests pass, but the sprint failed due to these structural and procedural violations.

## PlanManager Alignment
**Yes**, PlanManager's risk flags predicted this failure.
Specifically, **Risk #2**: "`Makefile` build target hardcodes file checks and must be updated" materialized as the primary reason `make build` failed in the final state.
**Risk #4**: "12 artifacts to create — highest artifact count so far" likely contributed to the agent's loss of focus on the scope fence.

## Recommendation: RETRY
The sprint scope itself is sound and the deliverables are largely complete. A REDECOMPOSE is not strictly required as the 8 DoD items and 3 subsystems (DB, API, UI) are within manageable limits. However, the next attempt must be a "Clean Up & Solidify" run.

**Instructions for RETRY:**
1. **Purge Residue:** Remove all references to Sprint 004/005 in the `Makefile`, `package.json`, and any other config files. Ensure `git status` is clean of out-of-scope tracked files.
2. **Validation:** Ensure `make build`, `make lint`, and `make test` all pass with *only* the Sprint 000-003 code present.
3. **UI Robustness:** Verify that `src/ui/app.html` correctly integrates `ShiftCalendar.js` and `ShiftCard.js` using the provided guards for CommonJS/Browser compatibility.
4. **Adherence:** Strictly respect the `scope_fence.off_limits`. Do not create any file that isn't required for Sprint 003.
