# Sprint 004 Review Brief

**Sprint:** 004 — Authentication & Returning User Detection  
**Prepared by:** Review Manager  
**Date:** 2026-05-11T19:50:08Z

> This brief synthesizes the currently retrievable review and critique evidence. It does **not** render a sprint-completion verdict.

## Agreements

- The available review material agrees that Sprint 004 is the **authentication/security layer** following Sprint 003, with medium complexity and a broad scope: phone OTP, Google, Apple, email/password fallback, returning-user detection, deferred auth after shift selection, SMS consent gating, and staff RBAC (`.ai/sprints/SPRINT-004.md`, `.ai/sprints/SPRINT-004.yaml`).
- The available plan-level evidence consistently treats the main risks as: implementing four auth flows in raw `http`, session design, mocked OAuth testing, SMS-consent storage/gating, and deferred-auth client flow (`.ai/managers/plan-journal.md`, Sprint 004 entry; echoed in `ReviewGemini/response.md`).
- The critiques agree that **evidence quality is insufficient for an implementation judgment**. Most Sprint 004 discussion is plan-level or derived from stale snapshots rather than from current code/tests.
- The strongest present-state repository evidence is that Sprint 004 artifacts are **not currently on disk**: there are no matches for `src/auth/**/*.js`, `src/middleware/**/*.js`, `tests/auth/**/*.js`, or `db/migrations/*004*`. The current tree still consists of Sprint 003-era backend/UI files plus Sprint 002 assets.
- The handoff from Sprint 003 into Sprint 004 remains visibly pending: `src/ui/discovery/index.html:313-317` still wires sign-up clicks to an alert stating that registration/authentication follows in Sprint 004, so the deferred-auth flow has not yet been exercised in current code.

## Disagreements

### 1. Whether there is any Sprint 004 implementation evidence to review

- **Some critique text treats Sprint 004 as already implemented**, citing artifacts such as `phone_verification.js`, `social_auth.js`, `returning_user.js`, `src/middleware/auth.js`, `src/ui/auth/signup.html`, `/api/staff/test`, and `004_auth_schema.sql`.
- **Stronger evidence:** current repository inspection. There are no files matching those expected Sprint 004 artifacts, and `find src tests db -maxdepth 3 -type f` shows only Sprint 000-003 files plus `src/ui/HelloPage.html`/`src/ui/app.html`.
- **Assessment:** current-tree evidence outweighs speculative or stale references. The present review base does not contain reliable implementation proof for Sprint 004.

### 2. Whether mocked OAuth testing is an adequate DoD item

- **Gemini plan review position:** mocked-provider-only OAuth validation is weak and could miss configuration problems.
- **Claude-on-Gemini / Codex-on-Gemini critique position:** requiring real provider sandbox flows in sprint validation is impractical; mocked integration tests are a reasonable CI-level acceptance criterion.
- **Stronger evidence:** the adopted Sprint 004 spec itself explicitly chooses mocked-provider integration tests for Google and Apple (`.ai/sprints/SPRINT-004.md`, DoD items 2-3). With no implementation present, this remains a **plan adequacy disagreement**, not a confirmed delivery defect.

### 3. Whether Sprint 004 should be criticized for conversational/nonlinear behavior

- **Gemini decomposition review:** criticized “Sprint 004” for lacking nonlinear/adaptive conversation DoD.
- **Critiques of that review:** noted this criticism applies to an alternate decomposition, not the adopted sprint.
- **Stronger evidence:** adopted Sprint 004 non-goals explicitly say **“No conversational UI”** (`.ai/sprints/SPRINT-004.md`). The adopted sprint is auth-focused, so conversational-engine objections are misapplied to the current sprint definition.

### 4. Whether staff auth/RBAC is unscoped vs explicitly included

- **GPT/Gemini plan-level criticism in critiques:** staff auth/RBAC can be missing or under-scoped in the broader plan.
- **Adopted sprint evidence:** Sprint 004 explicitly includes `src/auth/roles.*`, `src/middleware/auth.*`, and a DoD item for protecting a test staff route with RBAC (`.ai/sprints/SPRINT-004.md`, Expected Artifacts + DoD item 7).
- **Assessment:** the spec addresses staff RBAC at scope-definition level, but there is no present implementation evidence to confirm delivery. So the stronger synthesis is: **scoped in plan, unverified in code**.

## Scope fence violations

- **None confirmed for current Sprint 004 implementation state**, because no Sprint 004 source artifacts are currently present in the workspace.
- However, the evidence base is affected by **snapshot drift and stale references**: several critique passages discuss Sprint 004 files/routes that are absent now. That weakens those review claims, but it is not itself proof of a current Sprint 004 scope-fence breach.
- The only directly observable boundary signal is the inherited Sprint 003 placeholder handoff (`src/ui/discovery/index.html:313-317`), which stays within Sprint 003 scope by deferring auth to Sprint 004 rather than implementing it early.

## PlanManager risk check

PlanManager flagged five Sprint 004 risks. Based on currently retrievable evidence:

1. **Four auth flows in raw `http`**
   - **Status:** Not yet confirmable.
   - **Evidence:** no Sprint 004 auth modules are present to inspect or test.

2. **Session-management design (JWT vs cookie/session)**
   - **Status:** Not yet confirmable.
   - **Evidence:** no migration/module/middleware implementation is present in the current tree.

3. **Mocking OAuth flows for automated tests**
   - **Status:** Open design risk, not confirmed as a failure.
   - **Evidence:** Sprint 004 DoD explicitly expects mocked-provider integration tests, but no tests/artifacts exist yet.

4. **Consent gating for SMS must be robustly stored**
   - **Status:** Not yet confirmable.
   - **Evidence:** no auth migration, no consent storage code, and no Sprint 004 test files are present.

5. **Auth entry delayed until after shift selection complicates client state**
   - **Status:** Still open / pending implementation.
   - **Evidence:** current discovery UI still ends at a placeholder alert (`src/ui/discovery/index.html:313-317`) rather than a real auth handoff, so the risk has not been retired by implementation.

## Evidence quality

- **Overall:** Mixed, but weak for execution-level confidence.
- **Strongest evidence:**
  - the Sprint 004 spec/DoD itself (`.ai/sprints/SPRINT-004.md`, `.ai/sprints/SPRINT-004.yaml`)
  - the PlanManager Sprint 004 risk entry (`.ai/managers/plan-journal.md`)
  - current repository absence checks showing no Sprint 004 artifacts on disk
  - the Sprint 003 placeholder handoff in `src/ui/discovery/index.html`
- **Weakest evidence:**
  - critique passages that discuss concrete Sprint 004 modules/routes/files not present in the current workspace
  - decomposition-level arguments that are valid for alternate plans but not for the adopted Sprint 004 spec
- **Net assessment:** the review set is useful for identifying **open risks and weak assumptions**, but it is not a reliable basis for determining Sprint 004 completion or runtime correctness. Current evidence supports a planning/verification brief, not an implementation judgment.
