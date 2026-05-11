# Sprint 014 — Individual Volunteer End-to-End Flow

## Scope
Wire together the complete individual volunteer journey: browse opportunities → select shift → authenticate → register (minimal fields) → sign waiver → complete orientation → receive confirmation SMS → receive QR code. This sprint produces no new subsystems but validates the integrated pipeline and fills any gaps between previously-built components. Represents the FR23 end-to-end flow.

## Non-goals
- No group flow integration. No staff operations. No station assignment.

## Requirements
- **FR23**: Support the standard individual volunteer flow: select shift, register, complete digital waiver, complete orientation, receive confirmation, and check in on shift day.

## Dependencies
- Sprint 026 — Nonlinear & Adaptive Conversational Logic (replaces Sprint 006)
- Sprint 007 — Digital Waiver Management
- Sprint 008 — Orientation Tracking
- Sprint 009 — SMS Orchestration Core (Transactional)
- Sprint 010 — Check-In & QR Code System (Individual)

## Expected Artifacts
- `tests/e2e/individual_volunteer_flow.test.*` — End-to-end integration test
- `src/services/registration_pipeline.*` — Pipeline orchestrator connecting all flow steps

## DoD
- [ ] End-to-end test: anonymous user browses opportunities → selects shift → is prompted to authenticate → registers with name/phone/email → signs waiver → completes orientation → receives confirmation SMS → receives QR code
- [ ] Returning volunteer path: recognized by phone → not asked to re-register → skips completed waiver → sees personalized suggestions
- [ ] All flow steps render within the conversational UI framework
- [ ] Flow gracefully handles partial completion (e.g., user drops off after registration, returns later to complete waiver)
- [ ] `make test` and `make e2e` pass

## Validation
```bash
make test && make e2e
```
