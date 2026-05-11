# GPT Decomposition Review

## Methodology

Every FR (FR1–FR83) in `spec_analysis.md` was checked against the GPT decomposition's "Requirements covered" lists. Dependency ordering was verified against the spec_analysis dependency graph. Sprint sizing was checked against the ≤10 DoD / ≤3 subsystem constraints. DoD items were evaluated for machine-verifiability.

---

## Issues Found

### 1. SPRINT-002 — Conversational Matching before Authentication
- **Type:** ordering
- **Severity:** important
- **Description:** SPRINT-002 covers FR15 (returning volunteer personalization) and DoD item 4 says "Returning volunteer heuristic applied when an authenticated volunteer is present." However, SPRINT-002 depends only on SPRINT-001; authentication is not delivered until SPRINT-003. The personalization-for-returning-users feature cannot be tested against real authenticated volunteers. Either SPRINT-002 must depend on SPRINT-003, or the returning-volunteer personalization (FR15) must move to a later sprint.

### 2. SPRINT-005 — FR23 (full individual flow) claimed prematurely
- **Type:** coverage
- **Severity:** important
- **Description:** SPRINT-005 lists FR23 ("Support the standard individual volunteer flow: select shift, register, complete digital waiver, complete orientation, receive confirmation, and check in on shift day"). FR23 describes the *entire* end-to-end pipeline, but SPRINT-005 only delivers registration. Waiver (SPRINT-006), orientation (SPRINT-007), confirmation SMS (SPRINT-008), and check-in (SPRINT-009) are all future sprints. FR23 should not be marked as covered until the last sprint that completes the pipeline (SPRINT-009), or it should be explicitly split across sprints with a note.

### 3. SPRINT-012 — FR56 partially claimed but accessibility constraint not addressed
- **Type:** missed-req
- **Severity:** critical
- **Description:** FR56 requires "group cohesion, accessibility compatibility, capacity limits, minimum staffing priority, and balancing constraints." SPRINT-012's DoD tests capacity and minimum staffing only. There is no DoD item verifying **accessibility compatibility** (volunteers with sitting-only/accessibility needs assigned to compatible stations). SPRINT-013 also does not add accessibility tests — it focuses on drag/drop overrides. Accessibility constraint enforcement has no DoD item in any sprint.

### 4. SPRINT-012 — FR56 group cohesion listed as "placeholder hooks" only
- **Type:** missed-req
- **Severity:** important
- **Description:** FR56 explicitly requires group cohesion in auto-assignment. SPRINT-012 scope says "group cohesion placeholder hooks" and no DoD item tests that groups are kept together. This is a core spec requirement (Section 8 constraint #1, Section 12 Big Test pass criteria: "Station assignments respect all constraints (groups together, accessibility, capacity)"). A DoD item must verify group cohesion in the auto-assignment output.

### 5. FR56 — Balancing constraint missing from all sprints
- **Type:** missed-req
- **Severity:** important
- **Description:** FR56 includes a balancing constraint ("Distribute volunteers as evenly as practical across stations after constraints are satisfied"). No sprint DoD item tests for balanced distribution. This should be a verifiable DoD item in SPRINT-012 or SPRINT-013.

### 6. SPRINT-020 — Depends on SPRINT-002 but not SPRINT-005/006/007/012
- **Type:** ordering
- **Severity:** important
- **Description:** SPRINT-020 delivers the volunteer dashboard showing "upcoming shifts, shift history, hours, impact stats." This requires registration data (SPRINT-005), check-in data (SPRINT-009), and potentially assignment data. Dependencies listed are "002, 008, 009" — missing SPRINT-005 (registration model). While SPRINT-009 transitively depends on SPRINT-005, the dependency should be explicit or the sprint will fail if dependency resolution doesn't do transitive closure.

### 7. FR69 — Donor acknowledgement in conversational flow not covered
- **Type:** missed-req
- **Severity:** important
- **Description:** FR69 ("Personalize the conversational flow with donor acknowledgement when an early RE NXT match is found") is listed in SPRINT-015's requirements but SPRINT-015's DoD items only cover matching/linking and storing donor flags. There is no DoD item verifying that the conversational UI actually displays a donor acknowledgement message. This is a distinct UX requirement from the spec (Section 9: "We're so grateful you've been supporting us as a donor. It's wonderful to see you volunteering too!").

### 8. FR76 — Navigation coherence not explicitly covered
- **Type:** missed-req
- **Severity:** minor
- **Description:** FR76 ("Integrate navigation so the main Volunteer entry point and returning-user dashboard/upcoming/history are part of the same experience") is listed in SPRINT-001's requirements but has no DoD item. SPRINT-001 DoD focuses on opportunity browsing. The navigation integration (main Volunteer nav → discovery, dashboard, history all in one experience) is not verified anywhere.

### 9. FR77 — No "return to website" pattern not verified
- **Type:** missed-req
- **Severity:** minor
- **Description:** FR77 ("Avoid any 'return to our website' pattern") is listed in SPRINT-001 but has no corresponding DoD item. SPRINT-001 DoD item 5 ("No cross-domain redirect") partially covers FR75 but not FR77's specific constraint about link patterns within the app.

### 10. FR4 — Staff dashboard access/auth never established
- **Type:** missed-req
- **Severity:** important
- **Description:** FR4 ("Provide a web-based staff operations dashboard for station planning, auto-assignment, run-of-show, and RE NXT exception reports") requires a staff authentication and authorization layer. SPRINT-011 DoD item 3 says "Staff routes are access-controlled (authorization test)" but no sprint establishes the staff auth system itself. Staff roles, login, and RBAC are never explicitly built. This is a prerequisite for SPRINT-011 and every subsequent staff sprint.

### 11. FR22 — Proactive SMS for open opportunities partially covered
- **Type:** coverage
- **Severity:** minor
- **Description:** FR22 ("Proactively push open opportunities or pop-up events by SMS to volunteers who have opted in") is listed in SPRINT-020's requirements. SPRINT-020 DoD item 6 mentions "open-opportunity alerts/milestones send only to opted-in volunteers" but there is no DoD item verifying the *trigger* mechanism (detecting open spots or new pop-up events and initiating the SMS). The opt-in gating is tested but the proactive detection/push logic is not.

### 12. FR62 — Role-based operational slice tested but not fully specified
- **Type:** dod
- **Severity:** minor
- **Description:** SPRINT-014 DoD item 3 says "Role-based filtering works (test: restricted staff sees subset)" but FR62 specifies that "each staff member sees their relevant operational slice while allowing operations staff to see the full picture." The DoD should verify both directions: (a) operations staff sees all locations/shifts and (b) location staff sees only their location. The current DoD is vague about what "subset" means.

### 13. SPRINT-010 — 6 DoD items but covers 7 FRs across 3+ subsystems
- **Type:** sizing
- **Severity:** important
- **Description:** SPRINT-010 covers FR24, FR25, FR26, FR27, FR36, FR48, FR49 — spanning group registration (backend + UI), group check-in (kiosk), group waiver handling, and on-site member capture. This touches at least 4 subsystems: Volunteer Registration, Group Management, Waiver Management, and Check-In & QR Intake. The ≤3 subsystem constraint is violated. Consider splitting group registration (FR24–FR27, FR36) from group check-in (FR48, FR49) into two sprints.

### 14. SPRINT-019 — 6 DoD items but covers skills + court + SNAP across many subsystems
- **Type:** sizing
- **Severity:** important
- **Description:** SPRINT-019 covers FR28, FR29, FR30, FR31, FR83 — combining skills-based intake (application, resume upload, staff queue) with court-required and SNAP programs (flagging, hours tracking, documentation). These are three distinct volunteer pathways with different data models and staff workflows. This touches Skills-Based Intake, Special Program Routing, Reporting/Exports, and Staff Dashboard — 4+ subsystems. Should be split into at least two sprints: one for skills-based intake and one for court/SNAP programs.

### 15. SPRINT-014 — Depends on SPRINT-013 (overrides) but weekly planning doesn't require overrides
- **Type:** ordering
- **Severity:** minor
- **Description:** SPRINT-014 (Run-of-Show + Weekly Planning) depends on SPRINT-013 (Assignment Overrides). The weekly planning view (FR63) and run-of-show (FR61) only need registration data, check-in data, and draft assignment data — not override/drag-drop capability. SPRINT-014 could depend on SPRINT-012 instead, allowing parallel development with SPRINT-013.

### 16. FR74 — NIFB brand matching has no acceptance test
- **Type:** validation
- **Severity:** minor
- **Description:** FR74 ("Match NIFB brand, typography, and color scheme") is listed in SPRINT-001 and DoD item 6 says "UI matches configured theme tokens (snapshot/UI test verifying key typography/colors)." This is the only visual/brand test in the entire decomposition. There is no validation that subsequent sprints (002–020) maintain brand consistency as new UI components are added. Consider a cross-cutting DoD item or a shared visual regression test.

### 17. Section 12 Big Test — No sprint covers the end-to-end integration test
- **Type:** coverage
- **Severity:** critical
- **Description:** The spec's Section 12 "Big Test" defines a comprehensive end-to-end scenario with 9 volunteer profiles that must pass through the complete pipeline. No sprint includes a DoD item for this integration test. SPRINT-020 has a partial e2e test for post-shift engagement only. There should be a final integration sprint (or DoD items in the last sprint) that runs the Big Test scenario and validates the complete system against all 9 profiles and pass criteria.

### 18. Section 12 Intermediate Milestone Tests — Not all mapped to sprints
- **Type:** coverage
- **Severity:** important
- **Description:** Section 12 defines 8 intermediate milestone tests. Most map to sprint DoD items, but the mapping is implicit. Specifically:
  - Milestone test 8 ("SMS test: full text sequence fires correctly: confirmation → reminder → post-shift impact → next commitment prompt") requires end-to-end SMS flow across SPRINT-008 and SPRINT-020. No single sprint validates the complete sequence.
  - Milestone test 6 ("Assignment test: Given a set of volunteers with mixed constraints, the auto-assignment algorithm produces a valid plan. Staff can override without breaking constraints") spans SPRINT-012 and SPRINT-013 with no combined validation.

### 19. FR50 — Donor recognition at check-in timing issue
- **Type:** ordering
- **Severity:** minor
- **Description:** SPRINT-016 covers FR50 (donor recognition at check-in) and depends on SPRINT-015 + SPRINT-009. However, FR50 and FR67 state matching happens "on signup or login," meaning the RE NXT match should already exist by check-in time. SPRINT-015 depends only on "003, 005" but the matching should trigger during registration flows. The dependency chain is correct, but the DoD should clarify that by check-in time the match was already performed (at registration), not that matching happens at check-in.

### 20. FR1 — Shared backend/volunteer record never explicitly verified
- **Type:** validation
- **Severity:** important
- **Description:** FR1 ("The web and SMS interaction surfaces must share a single backend and volunteer record") is listed in multiple sprints (003, 008, 020) but no DoD item in any sprint explicitly verifies that web-created and SMS-referenced volunteer records are the same record. This is an architectural invariant that should have at least one integration test (e.g., "volunteer registered via web can receive SMS using the same record ID").

### 21. FR65 — "Recognize known donors during the volunteer flow" split across sprints without integration test
- **Type:** coverage
- **Severity:** minor
- **Description:** FR65 is partially covered in SPRINT-015 (matching) and SPRINT-016 (check-in recognition). The "during the volunteer flow" part (signup-time recognition with conversational personalization, FR69) has no integration test combining matching + UI acknowledgement.

### 22. SPRINT-001 — FR74, FR75, FR76, FR77 are all website integration requirements lumped into sprint 001
- **Type:** sizing
- **Severity:** minor
- **Description:** SPRINT-001 lists 11 FRs. While the DoD has only 7 items (within limit), the breadth of requirements is wide: opportunity API, urgency computation, calendar/list UI, brand theming, URL continuity, navigation coherence, and no-redirect behavior. This is manageable but several FRs (FR74, FR76, FR77) have no corresponding DoD items, meaning they are claimed but not verified.

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 2 |
| Important | 10 |
| Minor | 10 |
| **Total** | **22** |

### Critical Issues (must fix before approval)

1. **Issue #3:** Accessibility constraint in auto-assignment (FR56) has no DoD item in any sprint.
2. **Issue #17:** Section 12 "Big Test" end-to-end integration scenario is not covered by any sprint.

### Top Important Issues

1. **Issue #1:** SPRINT-002 ordering — personalization depends on auth not yet built.
2. **Issue #4:** Group cohesion in auto-assignment left as "placeholder" — must be a real DoD.
3. **Issue #5:** Balancing constraint (FR56) missing from all DoD items.
4. **Issue #10:** Staff authentication/RBAC never explicitly built.
5. **Issue #13:** SPRINT-010 exceeds 3-subsystem limit (group reg + group check-in + waivers + kiosk).
6. **Issue #14:** SPRINT-019 exceeds 3-subsystem limit (skills + court + SNAP + reporting).
7. **Issue #18:** Spec milestone tests not fully mapped to sprint DoD items.
8. **Issue #2:** FR23 claimed complete in SPRINT-005 but pipeline isn't done until SPRINT-009.
9. **Issue #7:** FR69 donor acknowledgement in conversation has no verifiable DoD.
10. **Issue #20:** FR1 shared backend invariant never integration-tested.
