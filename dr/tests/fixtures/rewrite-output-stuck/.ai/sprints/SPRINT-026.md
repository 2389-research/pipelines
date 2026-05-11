# Sprint 026 — Nonlinear & Adaptive Conversational Logic

## Context
This sprint is the third and final sub-sprint replacing the failed Sprint 006. With the linear conversational engine (Sprint 024) and recommendation engine with personalisation (Sprint 025) complete, this sprint adds the most complex piece: nonlinear/adaptive conversation handling where volunteers can provide multiple preference values in a single utterance.

## Scope
Extend the conversation engine with a slot-filling parser that detects when a single user input satisfies multiple preference slots simultaneously. The engine should skip already-answered questions and only ask about remaining unfilled slots. This completes the original Sprint 006 contract's adaptive conversation requirement (FR17).

## Non-goals
- No changes to recommendation ranking logic.
- No changes to RecommendationCards UI.
- No NLP library integration — use heuristic pattern matching for slot detection.
- No SMS, waiver, orientation, or group registration features.

## Requirements
- **FR17 (completion)**: Support nonlinear/adaptive conversations based on volunteer input where volunteers can lead with any preference.

## Dependencies
- Sprint 025 — Recommendation Engine, Personalisation & UI (ensures full linear pipeline is working before adding nonlinear complexity)

## Expected Artifacts
- `src/services/conversation_engine.js` — Extended with slot-filling parser and adaptive follow-up logic
- `tests/services/conversation_engine.test.js` — Extended with nonlinear/adaptive test scenarios

## DoD
- [ ] Slot-filling parser in conversation_engine.js detects when a single user utterance contains information for multiple preference slots
- [ ] When multiple slots are filled by one utterance, the engine skips already-answered questions and advances to the next unfilled slot
- [ ] Engine handles any combination of slot mentions in a single utterance (e.g., time + group size, activity + location)
- [ ] Integration test: input "I have a group of 20 on Saturday" correctly fills group_size and preferred_day slots and triggers appropriate follow-up without re-asking those questions
- [ ] Adaptive follow-up: engine produces contextually appropriate next question based on which slots remain unfilled
- [ ] Existing linear flow behaviour is preserved — linear conversations continue to work identically after nonlinear logic is added
- [ ] Unit tests for nonlinear scenarios cover at least 3 multi-slot utterance patterns
- [ ] `make test` passes

## Validation
```bash
make test
```
