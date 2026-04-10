# Sprint Exec Cheap — Design Spec

**Date:** 2026-04-10
**Status:** Approved
**Based on:** `sprint_exec.dip` (original full-cost pipeline)

## Goal

A cost-minimized variant of the sprint execution pipeline that uses the cheapest available models (Haiku 4.5, GPT-5.4 Nano, Gemini 3.1 Flash-Lite) with retry loops and tiered escalation to Sonnet only when cheap models fail. The experiment answers: "how far can cheap models + smart structure get you?"

## Design Decisions

1. **All cheap, all the way down** — including the gate agent
2. **Retry loops with escalation** — 3 cheap retries, then 1 Sonnet rescue attempt
3. **Dual-lane pipeline** — separate cheap and rescue implementation paths for clean cost attribution
4. **2 reviewers + mutual cross-critique** — Haiku and Nano review each other (2 cross-critiques, not 6)
5. **Review squads post-implementation** — 3 persona agents generate usage signal that feeds into reviewers
6. **Cheap gate** — Haiku decides pass/retry/fail; valuable data even if judgment is imperfect

## Model Tiers

### Cheap Tier (default)

| Model | Provider | Cost Tier | Role |
|---|---|---|---|
| `claude-haiku-4-5` | anthropic | $1/$5 per M tokens | Implementation, reviews, gate, squads |
| `gpt-5.4-nano` | openai | Cheapest OpenAI | Commits, cross-critique, squads |
| `gemini-3.1-flash-lite-preview` | gemini | Cheapest Gemini | Discovery reads, squads |

### Rescue Tier (escalation only)

| Model | Provider | Role |
|---|---|---|
| `claude-sonnet-4-6` | anthropic | Rescue implementation (1 attempt) |

## Pipeline Topology

### Phase 1 — Sprint Discovery

Identical to original, with cheaper models for read operations.

```
Start → EnsureLedger(tool) → FindNextSprint(Flash-Lite) → SetCurrentSprint(tool) → ReadSprint(Flash-Lite) → MarkInProgress(tool)
```

### Phase 2 — Cheap Implementation Lane

```
ImplementCheap(Haiku) → ValidateBuild(tool)
  ├─ success → CommitCheap(Nano)
  └─ fail → restart ImplementCheap
```

### Phase 3 — Review Squads (fan-out)

Three persona agents run in parallel post-commit:

- **PracticalDev** (Haiku) — pragmatic developer, checks if it works as specified
- **Nitpicker** (Nano) — detail-oriented, finds edge cases and code smells
- **FreshEyes** (Flash-Lite) — new to codebase, reports confusion and missing docs

### Phase 4 — Reviews + Cross-Critique

Two reviewers with squad context, then mutual cross-critique:

```
ReviewHaiku + ReviewNano (parallel)
  → HaikuCritiqueNano + NanoCritiqueHaiku (parallel)
```

### Phase 5 — Cheap Gate

```
GateCheap(Haiku, max_retries: 3, retry_target: ImplementCheap)
  ├─ pass → CompleteSprint
  ├─ retry → ImplementCheap (up to 3x)
  └─ exhausted/fail → ImplementRescue
```

### Phase 6 — Rescue Lane

```
ImplementRescue(Sonnet) → ValidateRescue(tool)
  ├─ success → CommitRescue(Nano) → RescueReview(Haiku) → CompleteSprint
  └─ fail → FailureSummary(Nano)
```

No review squads or cross-critique in rescue — Sonnet gets all prior context, and a quick Haiku sanity check suffices.

## Retry & Escalation Mechanics

- **Validation retry (tight):** ImplementCheap ↔ ValidateBuild, restarts on failure
- **Gate retry (wide):** GateCheap retries full implement→validate→commit→squad→review cycle, max 3
- **Escalation:** Gate exhaustion or fail routes to ImplementRescue (Sonnet, 1 shot)
- **Rescue failure:** ValidateRescue fail → FailureSummary → Exit (no more retries)
- **Validation retries reset** on each gate-level iteration

## Reasoning Effort & Fidelity

| Category | Reasoning Effort | Fidelity |
|---|---|---|
| Discovery agents | medium | summary:low |
| Implementation (cheap) | high | summary:medium |
| Implementation (rescue) | high | summary:high |
| Squad agents | medium | summary:medium |
| Reviewers | medium | summary:medium |
| Cross-critiques | medium | summary:low |
| Gate | high | (inherits default) |
| Commits | medium | summary:low |
| Failure summary | medium | summary:low |

## Cost Comparison

**Original pipeline per run (happy path):**
- 1x Sonnet implementation
- 3x Opus reviews + 6x cross-critiques (2 Opus, 2 GPT-5.4, 2 Flash)
- 1x Opus gate
- 1x GPT-5.4 commit
- ~12 LLM calls, heavy models

**Cheap pipeline per run (happy path):**
- 1x Haiku implementation
- 3x squad (Haiku + Nano + Flash-Lite)
- 2x reviews (Haiku + Nano)
- 2x cross-critiques (Haiku + Nano)
- 1x Haiku gate
- 1x Nano commit
- ~12 LLM calls, all cheap models
- Estimated 10-20x cheaper per run

**Worst case (3 gate retries + rescue):**
- ~40 cheap LLM calls + 1 Sonnet call
- Still cheaper than a single run of the original pipeline
