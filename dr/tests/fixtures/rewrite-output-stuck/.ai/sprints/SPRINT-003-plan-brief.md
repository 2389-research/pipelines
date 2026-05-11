# Sprint 003 — Plan Brief (Retry Assessment)

**Date:** 2026-05-11T19:45:00Z
**Recommendation:** GO (with caveats)

---

## Executive Summary

Sprint 003 is ready for a retry. All entry preconditions are met, all dependency sprints are healthy, and the RecoveryManager has provided a clear diagnosis of the prior failure. The Sprint 003 source artifacts already exist on disk and pass lint/test, but `make build` fails due to Makefile pollution from Sprint 004/005 residue. The retry must fix the Makefile and clean up out-of-scope artifacts.

---

## 1. Entry Precondition Verification

| Precondition | Status |
|---|---|
| `src/api/hello.*` must exist | ✅ `src/api/hello.js` (1,886 bytes) |
| Sprint 002 must be complete | ✅ `status: completed` in both ledger and SPRINT-002.yaml |

**Result:** All preconditions PASS.

---

## 2. Dependency Health Assessment

| Sprint | Status | Attempts | Notes |
|---|---|---|---|
| 000 — Project Scaffold | completed | 1 | Clean |
| 001 — External Services | completed | 1 | Clean |
| 002 — Hello World E2E | completed | 1 | Clean |

**Full dependency chain 000→001→002 is healthy.** All completed on first attempt with zero failures. No instability in the foundation.

---

## 3. Recovery Context

The RecoveryManager journal (entry dated 2026-05-11T19:33:59Z) documents:

- **Root cause:** `implementation` — Scope fence breach
- **Failure detail:** The implementer pulled in artifacts from Sprints 004 and 005 (auth, registration, SMS, conversational UI, etc.). A subsequent attempt to delete them left the Makefile in a broken state, checking for files that no longer exist.
- **Recommendation:** RETRY — clean-room implementation with explicit purge of Sprint 004/005 residue.

This is **not** a dependency failure — it's a self-inflicted scope creep. The recovery path is clear and bounded.

---

## 4. Current State Analysis

### What works:
- **`make lint`** — passes (exit 0, 0 warnings)
- **`make test`** — passes (10 suites, 76 tests, 0 failures)
- **All 13 Sprint 003 artifacts exist on disk** and are syntactically valid

### What's broken:
- **`make build`** — FAILS with `Cannot find module 'src/services/sms.js'`

### Root cause of build failure:
The Makefile contains `node --check` entries for **10 files outside Sprint 003's scope**:

| File | Sprint | Status |
|---|---|---|
| `src/services/sms.js` | 009 (SMS) | MISSING |
| `src/auth/phone_verification.js` | 004 (Auth) | MISSING |
| `src/auth/social_auth.js` | 004 (Auth) | MISSING |
| `src/auth/email_password.js` | 004 (Auth) | MISSING |
| `src/auth/returning_user.js` | 004 (Auth) | MISSING |
| `src/auth/roles.js` | 004 (Auth) | MISSING |
| `src/middleware/auth.js` | 004 (Auth) | MISSING |
| `src/api/registration.js` | 005 (Reg) | MISSING |
| `src/api/profile.js` | 005 (Profile) | MISSING |
| `src/services/profile_completion.js` | 005 (Profile) | MISSING |

Additionally, **5 files from Sprint 005** exist on disk but should not:

| File | Sprint | Status |
|---|---|---|
| `src/ui/conversational/ChatShell.js` | 005 | EXISTS (out of scope) |
| `src/ui/conversational/MessageBubble.js` | 005 | EXISTS (out of scope) |
| `src/ui/conversational/InputArea.js` | 005 | EXISTS (out of scope) |
| `src/ui/conversational/ModeToggle.js` | 005 | EXISTS (out of scope) |
| `src/ui/navigation/AppNav.js` | 005 | EXISTS (out of scope) |

---

## 5. Risk Flags

1. **🔴 CRITICAL — Makefile pollution (Sprint 004/005 residue):** The `build` target references 10 files that don't exist and 5 files that shouldn't exist. The implementer MUST revert the Makefile `build` target to only include Sprint 003 and earlier artifacts. Specifically, the `build` target should check: `src/server.js`, `src/health.js`, `src/db/connection.js`, `src/api/hello.js`, `src/api/opportunities.js`, `src/models/location.js`, `src/models/shift.js`, `src/models/volunteer.js`, `src/services/urgency.js`, `src/ui/discovery/ShiftCard.js`, `src/ui/discovery/ShiftCalendar.js`.

2. **🟡 MEDIUM — Orphaned Sprint 005 files in repo:** The `src/ui/conversational/` and `src/ui/navigation/` directories contain Sprint 005 artifacts that were committed in `e9fc58e`. These should be removed or at minimum excluded from the build target. They represent scope fence leakage from the prior attempt.

3. **🟡 MEDIUM — Sprint 003 YAML vs Ledger status mismatch:** SPRINT-003.yaml says `status: failed` while ledger.yaml says `status: planned`. The implementer should be aware this is attempt #2 (not a fresh sprint).

4. **🟢 LOW — Test suite includes out-of-scope test file:** `tests/ui/conversational/components.test.js` (from Sprint 005) is in the test suite. It passes, but it's out of scope. Consider removing or ensuring it doesn't interfere.

5. **🟢 LOW — High artifact count (12 creates):** This is the most complex sprint so far. RecoveryManager's prior PlanManager entry flagged this same risk. The implementer should focus on getting the Makefile right and not over-engineer.

---

## 6. Hints for ImplementSprint

1. **Fix the Makefile FIRST.** Strip all Sprint 004+ file checks from the `build` target. The `build` target should only verify files through Sprint 003.

2. **Remove or ignore Sprint 005 residue.** Delete `src/ui/conversational/`, `src/ui/navigation/`, and `tests/ui/conversational/` if they aren't needed by Sprint 003. If removing them breaks tests, investigate and fix.

3. **Sprint 003 artifacts already exist and pass lint+test.** The implementation may already be complete — the fix may be purely the Makefile. Verify each DoD item against the existing code before writing new code.

4. **Scope fence is strict:** No auth, no registration, no SMS, no conversational flows. Don't add anything from Sprint 004+.

5. **Validation must pass:** `make build && make lint && make test` — all three, exit 0.

6. **Don't modify `.ai/ledger.yaml`** — scope fence explicitly prohibits this.

---

## 7. Go/Hold Decision

**GO** — All entry preconditions are satisfied. The dependency chain is healthy. The failure root cause is well-understood (Makefile pollution from scope breach). The fix is bounded and clear. The Sprint 003 source artifacts already exist and are functional. This is a recovery retry, not a fresh implementation.
