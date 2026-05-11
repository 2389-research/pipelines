# Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell

## Scope
Build the embeddable website UI shell (conversational container + browse mode toggle) and the minimal registration flow (name, phone, email only). Implement deferred profile completion for secondary fields. Establish the integrated navigation connecting the entry point, discovery, and (future) volunteer dashboard under a single experience. The registration flow is rendered within the conversational UI framework.

## Non-goals
- No conversational matching logic. No waiver, orientation, or SMS. No group registration.

## Requirements
- **FR2**: Provide a web conversational UI embedded in the NIFB website for signup, opportunity discovery, registration, waivers, orientation, group management, and staff operations.
- **FR13**: Collect only name, phone number, and email during initial registration.
- **FR14**: Defer collection of address, emergency contact, employer, demographic information, and other secondary data until later interactions or check-in.
- **FR76**: Integrate navigation so the main Volunteer entry point and returning-user dashboard/upcoming/history are part of the same experience.

## Dependencies
- Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing
- Sprint 004 — Authentication & Returning User Detection

## Expected Artifacts
- `src/ui/conversational/ChatShell.*` — Conversational UI container
- `src/ui/conversational/MessageBubble.*` — Message rendering
- `src/ui/conversational/InputArea.*` — User input component
- `src/ui/conversational/ModeToggle.*` — Conversation ↔ browse toggle
- `src/ui/navigation/AppNav.*` — Integrated navigation (discovery, dashboard, history)
- `src/api/registration.*` — Minimal registration endpoint
- `src/api/profile.*` — Profile completion endpoint (secondary fields)
- `src/services/profile_completion.*` — Profile completion tracking
- `tests/api/registration.test.*`
- `tests/ui/conversational/` — UI component tests

## DoD
- [ ] Conversational UI shell renders embedded in a host page with message bubbles, input area, and mode toggle
- [ ] Mode toggle switches between conversational view and calendar browse view without losing state
- [ ] Registration endpoint accepts only name, phone, email and creates a volunteer record (rejects if any missing)
- [ ] Profile completion endpoint accepts and stores secondary fields (address, emergency contact, employer, demographics) — all optional
- [ ] Registration flow is rendered within the conversational UI as a chat-style interaction, not a standalone form page
- [ ] Integrated navigation includes links to discovery, upcoming shifts, and history (dashboard placeholder)
- [ ] Profile completion status is tracked per-volunteer (which deferred fields remain uncollected)
- [ ] `make test` passes with registration, profile, and UI component tests

## Validation
```bash
make build && make lint && make test
```
