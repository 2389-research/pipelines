# Sprint 023 — Integration Verification & Launch Readiness

## Scope
Full integration test covering the Section 12 "Big Test" scenario with all 9 volunteer profiles through the complete pipeline. End-to-end smoke test of every major flow. Build verification, lint, and full test suite. No new features — this sprint validates that the entire system works together and is ready for single-location pilot deployment.

## Non-goals
- No new features. No multi-location expansion (that follows pilot validation).

## Requirements
- All functional requirements (FR1–FR83) — integration verification across the complete system.

## Dependencies
- Sprint 000 — Project Scaffold & Toolchain
- Sprint 001 — External Services & Dev Environment
- Sprint 002 — Hello World End-to-End Proof
- Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing
- Sprint 004 — Authentication & Returning User Detection
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell
- Sprint 007 — Digital Waiver Management
- Sprint 008 — Orientation Tracking
- Sprint 009 — SMS Orchestration Core (Transactional)
- Sprint 010 — Check-In & QR Code System (Individual)
- Sprint 011 — Group Volunteer Registration & Waiver Management
- Sprint 012 — Group Check-In, On-Site Member Capture & Donor Flags
- Sprint 013 — Location & Station Configuration
- Sprint 014 — Individual Volunteer End-to-End Flow
- Sprint 015 — Auto-Assignment Engine
- Sprint 016 — Staff Assignment Review & Override
- Sprint 017 — Staff Operations Dashboard (Run of Show & Weekly Planning)
- Sprint 018 — RE NXT Integration & Donor Matching
- Sprint 019 — RE NXT Activity Sync & Batch Export Fallback
- Sprint 020 — Skills-Based Volunteer Intake
- Sprint 021 — Court-Required & SNAP Volunteer Programs
- Sprint 022 — Volunteer Dashboard, Post-Shift SMS & Engagement
- Sprint 024 — Core Conversational Engine & API
- Sprint 025 — Recommendation Engine, Personalisation & UI
- Sprint 026 — Nonlinear & Adaptive Conversational Logic

## Expected Artifacts
- `tests/e2e/big_test.test.*` — Section 12.1 Big Test scenario (9 volunteer profiles)
- `tests/e2e/smoke.test.*` — Full system smoke test
- `tests/e2e/sms_sequence.test.*` — Complete SMS sequence test (confirmation → reminder → post-shift → next-commitment)
- `docs/pilot_readiness.md` — Pilot deployment checklist

## DoD
- [ ] Big Test scenario passes: 9 volunteer profiles (new individual, returning individual, group leader with 15 members, accessibility-needs volunteer, court-required volunteer, SNAP volunteer, skills-based applicant, RE NXT donor match, RE NXT low-confidence match) complete full pipeline
- [ ] Assignment test: mixed-constraint volunteer set produces valid auto-assignment plan; staff override does not break constraints
- [ ] SMS sequence test: full text sequence fires correctly (confirmation → reminder → post-shift impact → next-commitment prompt)
- [ ] `make build` succeeds
- [ ] `make lint` passes with zero warnings
- [ ] `make test` passes with zero failures
- [ ] `make e2e` passes with zero failures
- [ ] Application starts and serves traffic (health check returns 200, UI loads, API responds)
- [ ] System is validated at single pilot location (all flows tested against one location's data)
- [ ] No regressions from any prior sprint

## Validation
```bash
make build && make lint && make test && make e2e
curl http://localhost:$PORT/health
```
