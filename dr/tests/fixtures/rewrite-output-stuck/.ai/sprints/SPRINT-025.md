# Sprint 025 — Recommendation Engine, Personalisation & UI

## Context
This sprint is the second of three sub-sprints replacing the failed Sprint 006. With the linear conversational engine and API delivered in Sprint 024, this sprint adds the shift recommendation/ranking engine, authenticated personalisation for returning volunteers, and the RecommendationCards UI component.

## Scope
Implement the recommendation engine that scores and ranks available shifts against a volunteer's captured preferences. Add authenticated personalisation so returning volunteers receive suggestions influenced by their history (FR15). Build the RecommendationCards UI component to display results, including a browse-view handoff that preserves preference state.

## Non-goals
- No nonlinear or adaptive conversation parsing.
- No modifications to the conversation engine state machine.
- No SMS, waiver, orientation, or group registration features.

## Requirements
- **FR15**: Show returning volunteers personalized suggested opportunities based on history, preferred locations, and past shift types.
- **FR18**: Recommend matching shifts based on the volunteer's responses.

## Dependencies
- Sprint 024 — Core Conversational Engine & API (provides conversation_engine.js, conversation.js API)

## Expected Artifacts
- `src/services/recommendation.js` — Shift ranking algorithm with personalisation support
- `src/ui/conversational/RecommendationCards.js` — UI component for displaying ranked recommendations
- `tests/services/recommendation.test.js` — Unit and integration tests for recommendation logic

## DoD
- [ ] Recommendation module exposes a `rankShifts(preferences, shifts)` function that scores and returns shifts sorted by relevance to the preference object
- [ ] Ranking algorithm considers all four preference dimensions (activity type, time, location, group size) when scoring
- [ ] Authenticated path: when volunteer history is provided, `rankShifts` merges preferred locations and past shift types into scoring for personalised results (FR15)
- [ ] RecommendationCards UI component renders a ranked list of recommended shifts from the recommendation service output
- [ ] RecommendationCards includes a browse-view handoff affordance that preserves the current preference state when switching modes
- [ ] Unit tests cover at least 5 distinct preference scenarios including one authenticated-personalisation scenario
- [ ] Integration test: full linear conversation flow (via conversation engine) through to ranked shift recommendation completes successfully
- [ ] `make test` passes

## Validation
```bash
make test
```
