# Sprint 024 — Core Conversational Engine & API

## Context
This sprint is the first of three sub-sprints replacing the failed Sprint 006 (Conversational Matching & Recommendation Engine). Sprint 006 failed due to scope overload — it bundled a linear state machine, a recommendation engine with personalisation, and nonlinear adaptive parsing into a single unit. This sprint focuses exclusively on the deterministic linear conversational state machine and its REST API.

## Scope
Implement the core conversational preference-capture engine as a linear state machine and expose it via REST API endpoints. The engine asks volunteers four preference questions in a fixed order (activity type, preferred time, location, group size), records answers, and produces a structured preference object when all slots are filled.

## Non-goals
- No recommendation/ranking logic. No shift matching.
- No nonlinear or adaptive input parsing (e.g., multi-slot utterances).
- No authenticated personalisation or volunteer history integration.
- No UI components beyond what Sprint 005 already provides.

## Requirements
- **FR17 (partial)**: Ask volunteer preference questions conversationally via a linear question flow.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell (provides ChatShell)

## Expected Artifacts
- `src/services/conversation_engine.js` — Linear state machine for preference-slot capture
- `src/api/conversation.js` — REST API endpoints for conversation sessions
- `tests/services/conversation_engine.test.js` — Unit tests for linear conversation flows

## DoD
- [ ] Conversation engine implements a linear state machine that captures four preference slots: activity type, preferred time, location, and group size
- [ ] State machine transitions through slots in order, asking one question per step and recording the volunteer's answer
- [ ] Engine exposes a `startSession()` function that returns a session object with a greeting and the first question
- [ ] Engine exposes a `respond(sessionId, answer)` function that records the answer, advances state, and returns the next question or a completion signal
- [ ] REST API endpoint `POST /conversation/start` creates a new session and returns the first question
- [ ] REST API endpoint `POST /conversation/respond` accepts a session ID and answer, returns the next question or a structured preference object on completion
- [ ] Unit tests cover at least 3 linear flow variants (e.g., complete flow, partial flow, restart)
- [ ] `make test` passes

## Validation
```bash
make test
```
