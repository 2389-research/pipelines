# Sprint 003 Review Brief

**Sprint:** 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing  
**Prepared by:** Review Manager  
**Date:** 2026-05-11T19:26:18Z

## Agreements

- All three reviewers agree the **core Sprint 003 deliverables are substantially present**: the schema migration, models, opportunities API, urgency service, discovery UI, and associated tests. Claude lists the artifact set explicitly; Codex says the DoD is "mostly satisfied"; Gemini says the core backend logic and schema are well-implemented.
- All three reviewers acknowledge **meaningful automated coverage** in the snapshot each reviewed. Claude and Codex reported green validation in their examined state; Gemini also described the backend/tests as passing. Current rerun still shows `make test` passing (`10` suites, `76` tests), so the project retains substantial test coverage even though the exact suite count changed across workspace states.
- No reviewer argues that the sprint failed because the **main anonymous browsing/API work is missing**. Disputes are concentrated on **scope hygiene, validation integrity, and UI integration robustness**, not on absence of the intended Sprint 003 center of gravity.

## Disagreements

### 1. Whether Sprint 003 validation is actually green

- **Claude / early Codex snapshot:** reported `make build`, `make lint`, and `make test` all passing.
- **Stronger current evidence:** direct rerun now shows:
  - `make lint` ✅
  - `make test` ✅ (`10` suites / `76` tests)
  - `make build` ❌
- **Why current evidence is stronger:** the failure directly targets Sprint 003 `validation.commands`. The current `Makefile` still syntax-checks removed future-sprint modules such as `src/services/sms.js`, `src/auth/*`, `src/middleware/auth.js`, `src/api/registration.js`, `src/api/profile.js`, and `src/services/profile_completion.js`. The present failure message is `Cannot find module '/Users/dylanr/work/clients/nifb-dr/src/services/sms.js'`.
- **Assessment:** current command output outweighs older "all green" claims because the workspace changed during review/critique activity.

### 2. Whether future-sprint work is an active scope-fence breach or only cleanup debt

- **Gemini / Codex-side critiques:** treat Sprint 004/005 contamination as real and material.
- **Claude / Claude-on-Gemini side:** tends to treat later-sprint bleed as non-blocking or merely unstaged cleanup.
- **Stronger evidence:** favors the contamination concern.
  - `git status --short` currently shows deleted-but-tracked future-sprint artifacts including:
    - `db/migrations/004_auth_schema.sql`
    - `db/migrations/005_profile_schema.sql`
    - `src/api/profile.js`
    - `src/api/registration.js`
    - `src/auth/*`
    - `src/middleware/auth.js`
    - `src/services/profile_completion.js`
    - `src/services/sms.js`
    - `tests/api/registration.test.js`
    - `tests/auth/auth.test.js`
  - `git log --oneline` includes out-of-scope commits: `5771f3c feat: implement sprint 004 authentication & returning user detection` and `e9fc58e feat: add registration and conversational UI`.
  - The contamination is not purely historical because `make build` still depends on these removed files.
- **Nuance:** current `src/server.js` is now clean of `/api/registration`, `/api/profile`, and auth imports, so the contamination is concentrated in repo/build state rather than the current runtime route table.

### 3. Whether `src/ui/app.html` is a proven current blocker

- **Codex / Gemini reviews:** treated the app-shell browse flow as broken enough to block sign-off.
- **Several critiques:** argued those reviews over-read older code, especially around `ShiftCalendar(...)`, `data.map(...)`, and browser/CommonJS assumptions.
- **Stronger current evidence:** does **not** prove the exact runtime bug described in the original FAIL reviews.
  - Current `src/ui/app.html` uses `const shifts = data.items || [];` and calls `renderCalendarView(shifts)`.
  - Current `src/ui/discovery/ShiftCalendar.js` uses a guarded import path:
    - `typeof require !== 'undefined' ? require('./ShiftCard') : { renderCard: typeof renderCard !== 'undefined' ? renderCard : null }`
  - Current `ShiftCalendar.js` and `ShiftCard.js` guard `module.exports` with `if (typeof module !== 'undefined')`.
- **Assessment:** the older claims about `ShiftCalendar(...)`, raw `data.map(...)`, and guaranteed browser `ReferenceError` are weaker against the current tree. What remains well-supported is **test-gap / regression-risk evidence**, not a currently reproduced crash. Codex’s “unsafe to ship without an app-shell smoke test” position is therefore stronger than Gemini’s stronger claim of a presently demonstrated app-shell failure.

### 4. Whether `index.html` has a blocking DRY / duplication defect

- **Gemini-side reasoning and some critiques:** pointed to heavy duplication between `index.html` and the shared rendering modules.
- **Other critiques:** noted this was either non-blocking or based on an older file snapshot.
- **Stronger evidence:** low confidence as present-state blocker.
  - Some critique outputs inspected an inline-script version of `index.html`.
  - The current file loads `/ui/discovery/ShiftCard.js` and `/ui/discovery/ShiftCalendar.js` and calls `renderView(...)`.
- **Assessment:** duplication may have existed in an earlier snapshot, but it is not stable enough across the review run to carry much weight in a final evidence brief.

### 5. Whether the fixed availability-checkbox bug should count against the sprint

- **Gemini review:** cited it as part of the failure reasoning.
- **Multiple critiques:** said it was already fixed and should count as recovery evidence, not current-state failure.
- **Stronger evidence:** critique side.
  - Current `src/ui/discovery/ShiftCalendar.js` renders the checkbox using `${filterAvailable ? 'checked' : ''}`.
- **Assessment:** this should be treated as a resolved issue, not a current blocker.

## Scope fence violations

- **Detected, with nuance.**
- The strongest evidence is not merely that future-sprint files once existed, but that the repository is still carrying their residue in a way that affects Sprint 003 validation:
  - deleted-but-tracked Sprint 004/005 files remain in `git status`
  - out-of-scope commits are visible in recent history
  - the current `Makefile` still references those files and therefore causes `make build` to fail
- Reviewers disagreed on attribution:
  - some treated this as an active scope-fence problem
  - others treated it as historical clutter / unstaged deletions
- **Evidence assessment:** the current build failure makes the scope contamination operational, not merely cosmetic.

## PlanManager risk check

PlanManager flagged these Sprint 003 risks:

1. **Raw `http` module routing complexity**
   - **Status:** Partially confirmed, but not as the primary blocker.
   - **Evidence:** routing remains hand-rolled and somewhat fragile; one critique also noted `src/server.js` hardcodes `application/javascript` for `/ui/*`. However, the opportunities API and current server route table function well enough for tests to pass.

2. **`Makefile` build target hardcodes file checks and must be updated**
   - **Status:** Confirmed.
   - **Evidence:** current `make build` fails because the build target still checks removed future-sprint files (`src/services/sms.js`, `src/auth/*`, `src/api/registration.js`, `src/api/profile.js`, `src/services/profile_completion.js`, `src/middleware/auth.js`). This is the clearest materialized risk.

3. **ESLint `sourceType: "module"` may conflict with CommonJS `require()` pattern**
   - **Status:** Not confirmed.
   - **Evidence:** `make lint` passes.

4. **12 artifacts to create — highest artifact count so far**
   - **Status:** Not confirmed as a failure source.
   - **Evidence:** no reviewer identified missing required Sprint 003 artifacts; the artifact set is broadly present.

5. **`spots_remaining` computation needs a design decision without registration flow**
   - **Status:** Confirmed as a design decision, not as a defect.
   - **Evidence:** the schema/API expose `spots_remaining`, and urgency logic/tests operate on it successfully.

## Evidence quality

- **Overall quality:** mixed-to-good, but unstable because the workspace changed during the review pipeline.
- **Strengths:**
  - the three primary reviews are substantive and file-aware rather than superficial
  - critiques often added real value by running concrete commands (`make build`, `make test`, `git status`) and by correcting code-reading mistakes
  - the best critique contributions were:
    - correcting `index.html` vs `app.html` confusion
    - separating resolved bugs from current issues
    - surfacing the stale-build-surface problem
- **Weaknesses:**
  - reviewers were not all looking at the same snapshot
  - at least one critique edited files during critique, which blurs review evidence with remediation and reduces reliability
  - several claims conflict because the underlying workspace moved (for example: whether `index.html` duplicates logic, whether `app.html` expects `ShiftCalendar`, and whether 004/005 files are present on disk)
- **Most reliable present-state evidence:**
  - current command reruns
  - current file contents in `Makefile`, `src/server.js`, `src/ui/app.html`, and `src/ui/discovery/ShiftCalendar.js`
- **Bottom-line evidence posture for ReviewAnalysis:**
  - strong evidence of **core Sprint 003 implementation**
  - strong evidence of **current validation/scope hygiene problems centered on the stale build surface**
  - weaker, now-mixed evidence on **current app-shell breakage**, which is best framed as a regression-safety gap unless reproduced again on the present tree
