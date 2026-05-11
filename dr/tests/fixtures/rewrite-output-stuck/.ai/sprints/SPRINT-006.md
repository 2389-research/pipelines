# Sprint 006 — Conversational Matching & Recommendation Engine

## Scope
Implement the conversational preference capture and shift recommendation logic. Support adaptive, nonlinear conversations where volunteers can lead with any preference (e.g., "I have a group of 20 on Saturday"). Map volunteer responses to matching shifts and return ranked recommendations. Returning volunteers see personalized suggestions based on history.

**STATUS: FAILED — Redecomposed into Sprints 024, 025, 026.**

## Non-goals
- No SMS. No waiver or orientation. No group registration.

## Requirements
- **FR15**: Show returning volunteers personalized suggested opportunities based on history, preferred locations, and past shift types.
- **FR17**: Ask volunteer preference questions conversationally and support nonlinear/adaptive conversations based on volunteer input.
- **FR18**: Recommend matching shifts based on the volunteer's responses.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell

## Expected Artifacts
- `src/services/conversation_engine.*` — Conversation state machine and adaptive logic
- `src/services/recommendation.*` — Shift matching and ranking algorithm
- `src/api/conversation.*` — Conversation API
- `src/ui/conversational/RecommendationCards.*` — Recommended shift display
- `tests/services/conversation_engine.test.*`
- `tests/services/recommendation.test.*`

## DoD
- [ ] Conversation engine asks preference questions (activity type, time, location, solo/group) and maps answers to matching shifts
- [ ] Conversation handles nonlinear input (integration test: "I have a group of 20 on Saturday" triggers appropriate follow-up without requiring ordered questions)
- [ ] Recommendation engine returns matching shifts ranked by relevance to stated preferences
- [ ] Returning volunteer with history receives personalized suggestions (preferred locations/shift types) when authenticated
- [ ] User can switch to browse view at any point during conversation and return without losing answers
- [ ] Unit tests for recommendation matching cover at least 5 distinct preference scenarios
- [ ] Integration test: full conversation flow from first question to shift recommendation completes successfully
- [ ] `make test` passes

## Validation
```bash
make test
```
