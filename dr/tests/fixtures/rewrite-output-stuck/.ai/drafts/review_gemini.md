# Gemini Decomposition Review

## Review Methodology
Every FR (FR1–FR83) from `.ai/spec_analysis.md` was cross-referenced against sprint coverage. Dependency ordering was checked against the spec analysis dependency graph. Sprint sizing was validated against the ≤10 DoD / ≤3 subsystem constraints. DoD items were evaluated for machine-verifiability.

---

## Issues Found

### 1. MISSED-REQ | FR8 — Delay login until after shift selection | Critical
- **Sprints affected:** 002, 003
- **Description:** FR8 requires that login/account creation is deferred until *after* a visitor selects a shift of interest. Sprint 002 builds registration as a standalone flow, and Sprint 003 builds the opportunity catalog, but no sprint's DoD verifies the *sequencing* — that opportunities are browsable anonymously and authentication is triggered only upon shift selection. This is a core UX principle of the spec ("Opportunities First") and currently falls through the cracks between Sprint 002 and Sprint 003. A DoD item like "Unauthenticated user can browse opportunities and is prompted to register only after selecting a specific shift" must exist somewhere.

### 2. MISSED-REQ | FR7 — Dynamic urgency signals on opportunity browse view | Important
- **Sprints affected:** 003, 004
- **Description:** FR7 requires urgency signals (e.g., "Volunteers urgently needed — spots going fast!") on the opportunity browsing surface. Sprint 003 builds the calendar/list view but has no DoD item for urgency indicators. Sprint 004 adds urgency badges but only in the *chat UI* context. The visual browse fallback (calendar/list) also needs urgency signals per the spec. This is a gap — urgency needs to appear on both surfaces.

### 3. MISSED-REQ | FR22 — Proactive SMS push of open opportunities | Important
- **Sprints affected:** 007, 017
- **Description:** FR22 requires proactively pushing open opportunities or pop-up events by SMS to opted-in volunteers. Sprint 007's non-goals explicitly exclude "Engagement SMS." Sprint 017 covers post-shift engagement (impact cards, next-commitment, milestones) but never mentions *proactive open-opportunity alerts* — the "automatic texts sharing open opportunities or pop-up events" that Colleen specifically requested. This FR is entirely uncovered. It should be added to Sprint 017 or a new sprint.

### 4. MISSED-REQ | FR27 — Track waiver status for groups / require waivers before work | Important
- **Sprints affected:** 008, 010
- **Description:** FR27 requires tracking waiver status for groups and requiring signed waivers before group members work. Sprint 008 has a DoD item for the group leader signing a waiver, but Sprint 010 (Group Check-In) has no DoD item verifying that group member waiver status is checked at arrival or that individual members are prompted to sign waivers on-site. The spec (Section 5) explicitly says "individual members sign at arrival if not completed in advance." This gap means group members could work without signed waivers.

### 5. MISSED-REQ | FR36 — Individual group member waiver signing at arrival | Important
- **Sprints affected:** 010
- **Description:** FR36 says "individual members sign at arrival if not completed in advance." Sprint 010's on-site capture form collects name/phone/email for anonymous group members, but there is no DoD item for presenting and collecting waiver signatures from individual group members at check-in. This is related to but distinct from Issue #4.

### 6. MISSED-REQ | FR38 — Support complementary staff-led in-person orientation | Minor
- **Sprints affected:** 006
- **Description:** FR38 requires the system to support (not replace) a complementary staff-led in-person orientation. Sprint 006 covers the digital video orientation but has no DoD item acknowledging or supporting the in-person mode — e.g., a flag/checklist for "in-person orientation completed" or a staff-facing toggle. While this is lower complexity, the spec explicitly says the system should support both modes.

### 7. MISSED-REQ | FR41 — Day-of arrival information SMS | Minor
- **Sprints affected:** 007
- **Description:** FR41 specifies an optional day-of SMS with directions, door entry, and contact info. Sprint 007 covers confirmation and 48-hour reminder but has no DoD item for this third pre-shift SMS touchpoint. While the spec marks it "optional," it is a named FR that should at least be acknowledged.

### 8. MISSED-REQ | FR44 partial — Open-opportunity alerts and deeper engagement SMS | Important
- **Sprints affected:** 017
- **Description:** FR44 covers three distinct SMS categories: (a) deeper-engagement follow-up, (b) open-opportunity alerts, and (c) milestone celebrations. Sprint 017 covers milestones (DoD item 4) and impact cards, but omits open-opportunity alerts (overlaps with FR22 gap above) and the "Serving Hope monthly giving" integration explicitly mentioned in Section 6. The Serving Hope opt-in prompt is a named engagement touchpoint in the spec.

### 9. MISSED-REQ | FR2 — Conversational UI for staff operations | Minor
- **Sprints affected:** 013, 014
- **Description:** FR2 says the web conversational UI handles "staff operations" among other things. The staff dashboard (Sprints 013-014) is built as a traditional dashboard, which is likely correct, but the spec's framing suggests the conversational UI might also be used for some staff interactions. This is likely an over-reading of the spec, but worth flagging for clarification.

### 10. ORDERING | Sprint 003 depends on 002, but should depend on 001 | Important
- **Sprints affected:** 003
- **Description:** Sprint 003 (Opportunity Catalog) depends on Sprint 002 (Registration & Website Integration). But the spec requires opportunities to be browsable *without* registration (FR6, FR8). The opportunity catalog and calendar are independent of registration — they need the backend (Sprint 001) but not the registration flow (Sprint 002). Making Sprint 003 depend on Sprint 002 is incorrect and creates an artificial bottleneck. Sprint 003 should depend on Sprint 001, and Sprint 002 and 003 should be parallelizable.

### 11. ORDERING | Sprint 006 depends on 004 and 005, but 004 is not required | Minor
- **Sprints affected:** 006
- **Description:** Sprint 006 (Orientation & Profile Maturity) lists Sprint 004 (Conversational Discovery) as a dependency. The returning-user personalization ("Suggested for You") depends on having volunteer records and shift history, not on the conversational engine. The real dependency is on the opportunity catalog (Sprint 003) and the volunteer record (Sprint 001/002). This dependency is overstated and could delay orientation work unnecessarily.

### 12. ORDERING | Sprint 012 depends on 010, but only needs 008 + 011 | Important
- **Sprints affected:** 012
- **Description:** Sprint 012 (Auto-Assignment Engine) lists dependency on Sprint 010 (Group Check-In). But the assignment algorithm needs *registered* volunteers and station configs — not check-in data. It needs group identity (Sprint 008) and station config (Sprint 011). Depending on Sprint 010 (check-in) means the assignment engine can't be built until the full check-in stack is done, which is unnecessary. The spec says assignments are generated from "registered volunteers for a shift and the station configuration" (Section 8), not from checked-in volunteers.

### 13. ORDERING | Sprint 015 depends on 009, but only needs 001 | Important
- **Sprints affected:** 015
- **Description:** Sprint 015 (RE NXT Discovery & Matching) depends on Sprint 009 (QR & Check-In). The RE NXT matching happens "on signup or login" (Section 9) — it needs the volunteer record and auth (Sprint 001), not check-in. The check-in donor flag surfacing is a *consumer* of RE NXT data, not a prerequisite for building the integration. Sprint 015 should depend on Sprint 001 only, allowing it to be built much earlier in the timeline.

### 14. SIZING | Sprint 015 — 6 FRs (FR64-FR69) is borderline | Minor
- **Sprints affected:** 015
- **Description:** Sprint 015 covers FR64–FR69 (6 FRs) and is rated High complexity. It includes: API connection, identity matching algorithm with confidence scoring, record tagging, conversational personalization for donors, AND check-in donor flag surfacing. The conversational personalization (FR69) touches a completely different subsystem (the conversational UI from Sprint 004) than the matching engine. Consider splitting FR69 into a separate sprint or into Sprint 004/006's scope, since it requires modifying the conversational flow.

### 15. SIZING | Sprint 018 mixes two unrelated pathways | Minor
- **Sprints affected:** 018
- **Description:** Sprint 018 combines Skills-Based Volunteers (FR28-FR29) and Court-Required Volunteers (FR30) into one sprint. These are entirely different pathways with different forms, different staff routing, and different downstream data. While each is individually small, combining them means the sprint touches: the registration/intake subsystem, the staff dashboard (queue visibility), AND file storage (resume upload). That's 3 subsystems, which is at the limit. Not a blocker, but worth noting.

### 16. DOD | Sprint 001 — OAuth DoD uses "mocked provider responses" only | Important
- **Sprints affected:** 001
- **Description:** Sprint 001's DoD for Google/Apple OAuth says "Unit tests for Google/Apple OAuth callback logic pass with mocked provider responses." This is a unit test, not an integration verification. There is no DoD item that verifies the OAuth flow actually works end-to-end with real provider endpoints (even in a dev/sandbox environment). A mocked test will pass even if the OAuth configuration is wrong. At minimum, add a DoD item for sandbox-environment OAuth flow completion.

### 17. DOD | Sprint 002 — "CSS variables/theme match NIFB brand guidelines" is not machine-verifiable | Minor
- **Sprints affected:** 002
- **Description:** The DoD item "CSS variables/theme match NIFB brand guidelines (colors, typography)" is subjective and not machine-checkable. Rephrase to something verifiable: "CSS variables for primary, secondary, accent colors and font-family match values specified in the brand guide" or "Visual regression snapshot matches approved mockup with <X% pixel difference."

### 18. DOD | Sprint 004 — No DoD for nonlinear/adaptive conversation (FR17) | Important
- **Sprints affected:** 004
- **Description:** FR17 requires "nonlinear/adaptive conversations based on volunteer input" — e.g., a volunteer leading with "I have a group of 20 on Saturday" and the system adapting. Sprint 004's DoD says "Conversation engine supports branching logic based on user input" which is vague. There's no test case for the nonlinear case. Add a DoD item like: "Integration test: conversation handles out-of-order input (e.g., group size before location preference) and still produces valid recommendations."

### 19. DOD | Sprint 012 — Performance DoD is good but missing constraint validation test | Minor
- **Sprints affected:** 012
- **Description:** Sprint 012 has a performance DoD (100+ volunteers in <2 seconds), which is good. But there's no DoD item that verifies the algorithm *fails gracefully* when constraints are unsatisfiable (e.g., more volunteers than total station capacity, or a group larger than any single station's max capacity). The spec says the algorithm produces a "draft plan" — it should still produce *something* and flag violations rather than crashing.

### 20. DOD | Sprint 014 — "Real-time check-in counts" implies websocket/polling not built elsewhere | Minor
- **Sprints affected:** 014
- **Description:** Sprint 014's DoD says "Run of show displays real-time check-in counts vs expected registrations." The word "real-time" implies a live-updating mechanism (websocket, SSE, or polling). No prior sprint builds this infrastructure. If this is just "refresh to see current data," the DoD should say "current" not "real-time." If it truly means live updates, the infrastructure needs to be scoped.

### 21. VALIDATION | No sprint validates the end-to-end "Big Test" from Section 12.1 | Critical
- **Sprints affected:** All (missing sprint)
- **Description:** Section 12.1 of the spec defines "The Big Test" — a comprehensive end-to-end simulation with 9 specific volunteer profiles that must pass through the complete pipeline. No sprint in the decomposition includes this integration test as a DoD item. The individual sprints test their own slices, but the full-pipeline validation (which is the spec's primary acceptance criterion) is never explicitly scheduled. There should be a final integration/validation sprint (Sprint 021) or the Big Test should be added to Sprint 020's DoD.

### 22. VALIDATION | Section 12.3 Pilot Scope — single-location validation not in any DoD | Important
- **Sprints affected:** 020 or missing sprint
- **Description:** The spec requires starting with one location and validating the full loop before expanding. No sprint DoD includes "System is validated at a single pilot location" or "Multi-location expansion is gated on pilot success." This operational validation criterion is untracked.

### 23. COVERAGE | Shift selection → registration flow integration gap | Important
- **Sprints affected:** 002, 003, 004
- **Description:** The spec defines a specific flow: browse opportunities → select shift → prompted to register → waiver → orientation → confirmation. Sprint 002 builds registration. Sprint 003 builds the catalog. Sprint 004 builds conversational discovery. But no sprint's DoD verifies the *integrated flow* of "user selects a shift from the catalog and is then prompted to register." This is the critical user journey linkage between browsing and registration. Each sprint tests its own piece but the handoff is never verified.

### 24. COVERAGE | No sprint covers the "shift registration/confirmation" step | Important
- **Sprints affected:** 002, 003
- **Description:** After a volunteer registers and signs a waiver, they should receive a *confirmation* that they are registered for a specific shift. The spec says "Confirmation" is a step in the individual flow (Section 4.1). Sprint 002 registers a volunteer (creates account) but doesn't link them to a shift. Sprint 003 displays shifts but doesn't handle registration-for-a-shift. No sprint DoD says "Volunteer can register for a specific shift and receive confirmation." This is the binding step between the volunteer record and an opportunity.

### 25. COVERAGE | FR50 — Donor recognition at check-in is in Sprint 015 but check-in is Sprint 009 | Minor
- **Sprints affected:** 009, 015
- **Description:** Sprint 015 lists a DoD item "Check-in logic detects donor flag and surfaces it for staff-only visibility." But Sprint 009 (which builds check-in) was completed 6 sprints earlier. This means Sprint 015 must retroactively modify Sprint 009's check-in UI to add donor flag display. This is fine architecturally but should be noted as a cross-cutting concern — Sprint 015 modifies the check-in subsystem built in Sprint 009.

### 26. COVERAGE | Volunteer-to-shift checkout / departure tracking | Minor
- **Sprints affected:** 017
- **Description:** Sprint 017 triggers post-shift SMS "15 minutes after shift end/checkout." This implies a checkout mechanism or shift-end detection exists. No sprint builds a checkout flow or shift-end time trigger. The decomposition should clarify whether this is clock-based (shift scheduled end time) or event-based (volunteer checks out). If event-based, a checkout mechanism needs to be scoped.

### 27. ORDERING | Sprint 007 depends on Sprint 006, but SMS should be earlier | Important
- **Sprints affected:** 007
- **Description:** Sprint 007 (SMS Orchestration) depends on Sprint 001 and Sprint 006. The dependency on Sprint 006 (Orientation & Profile Maturity) is questionable — SMS confirmations and reminders (FR39, FR40) don't require orientation to be built. The orientation link *in* the reminder SMS is a nice-to-have inclusion but not a prerequisite for the SMS infrastructure. This dependency delays SMS unnecessarily. Sprint 007 should depend on Sprint 001 and Sprint 002 at most.

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 2 |
| Important | 12 |
| Minor | 13 |
| **Total** | **27** |

### Critical Issues Requiring Resolution
1. **FR8 (delay login until shift selection)** — Core UX principle is unverified in any sprint DoD.
2. **No end-to-end "Big Test" sprint** — The spec's primary acceptance criterion (Section 12.1) has no corresponding sprint.

### Top Ordering Fixes
- Sprint 003 should depend on 001 (not 002) — opportunities must be browsable without registration.
- Sprint 012 should depend on 008 + 011 (not 010) — assignment uses registered volunteers, not checked-in.
- Sprint 015 should depend on 001 (not 009) — RE NXT matching happens at signup, not check-in.
- Sprint 007 should depend on 001 + 002 (not 006) — SMS doesn't need orientation.

### Top Missing Requirements
- FR22 (proactive open-opportunity SMS alerts) — entirely uncovered.
- FR27/FR36 (group member waiver enforcement at arrival) — partially covered.
- FR8 (login deferral after shift selection) — unverified.
- Shift registration/confirmation step — the binding between volunteer and opportunity is never built.
