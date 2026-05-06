# Structural fix: smoke-test progression (v1 → v4, 2026-04-30 → 2026-05-01)

End-to-end smoke testing of the structural fix (Opus designs the contract; the dispatch tool iterates mechanically over sprints rather than the LLM looping its own dispatch) on the Notebook API synthetic fixture (3 sprints, ~$2/run, ~7 min). Each version isolates a separate failure mode discovered during the prior run.

The architect side is now fully wired: Opus writes contract.md + sprint_descriptions.jsonl, calls dispatch_sprints once, and the agent terminates immediately. Sprint files match the validated NIFB speedrun-exemplar shape. Hand-off to the local runner ([RUNNER-INTEGRATION.md](RUNNER-INTEGRATION.md)) produces working code that passes 34/34 tests.

## Build status (final)

| Component | State | Location |
|---|---|---|
| `dispatch_sprints` tracker tool (deterministic per-sprint loop) | landed + 4 unit tests | `tracker/agent/tools/dispatch_sprints.go` |
| `write_enriched_sprint` refactor (RunOne helper) | landed | `tracker/agent/tools/write_enriched_sprint.go` |
| Sonnet writer prompt — speedrun shape | landed | same file, `sprintSystemPromptHeader` |
| Embedded few-shot example (NIFB SPRINT-001 + SPRINT-002) | landed | `tracker/agent/tools/write_enriched_sprint_example.md` |
| TerminalTool runtime primitive | landed | `tracker/agent/tools/registry.go`, `tracker/agent/session.go` |
| 4-strategy SR-block matcher (exact / indent / whitespace / fuzzy) | landed + 12 unit tests | `tracker/agent/tools/write_enriched_sprint.go`, `_test.go` |
| Architect dip Start/Exit cleanup (tools, not agents) | landed | `local_code_gen/architect_only.dip` |
| Notebook API synthetic fixtures | landed | `local_code_gen/principles/synthetic_fixtures/` |

All cleanly build; full test suite (`go test ./agent/... ./pipeline/handlers/`) green.

## Smoke runs at a glance

| Run | Date | Cost | Wall time | Status | Key learning |
|---|---|---|---|---|---|
| v1 (`notebook_smoke_v1/`) | 2026-04-30 19:55 | ~$2 | ~6 min | partial | Pipeline plumbing works; sprint format diverges from NIFB exemplars; agent doesn't stop after dispatch returns |
| v2 (`notebook_smoke_v2/`) | 2026-04-30 20:30 | ~$2 | ~6 min | partial | New writer prompt produces speedrun-aligned specs (audit verdicts went 3/3 PATCHED → 3/3 PASS); agent still doesn't stop |
| v3 (`notebook_smoke_v3/`) | 2026-05-01 10:23 | aborted mid-run | partial | partial | TerminalTool runtime feature works (agent stops on dispatch success); dip-level Start/Exit pseudo-agents inheriting global tool registry → entry-point agent does the architect work, then write_sprint_docs runs it again |
| v4 (`notebook_smoke_v4/`) | 2026-05-01 10:39 | ~$2 | ~9 min | clean ✅ | Full pipeline: Opus drives architect, dispatch_sprints fans out 3 Sonnet calls, all auditing PASS or fallback, ledger populated, validate_output passes, pipeline_completed event fires |

## v1 — Pipeline plumbing works; format and stop-behavior bugs surface

**What we tested:** the structural fix's first end-to-end run. New `dispatch_sprints` tool fans out 3 Sonnet calls; architect prompt asks Opus to write `contract.md` + `sprint_descriptions.jsonl` then dispatch.

**Outcome:**
- ✅ `dispatch_sprints ok: dispatched=3 (PASS=0, PATCHED=3, fallbacks=0, failures=0)`
- ✅ Per-sprint files written: SPRINT-001 (32485 bytes), 002 (13996), 003 (16856)
- ❌ Section structure diverged from NIFB exemplars. Smoke output had `## Interface contract`, `## Imports per file`, `## Algorithm notes`, `## Test plan`, `## Expected Artifacts` — the OLD section list. Validated exemplars have `## Tricky semantics`, `## Data contract`, `## API contract`, `## Algorithm`, `## Test contract`, `## Verbatim files`. Missing `## Tricky semantics` is the most consequential gap (it's the single load-bearing "rule + WHY" list per [SPEEDRUN-SPEC-FORMAT.md](SPEEDRUN-SPEC-FORMAT.md)).
- ❌ Architect didn't stop. After `dispatch_sprints` returned, the agent burned ~5 extra turns writing `ARCHITECT_TEST_COMPLETE.md`, `architect_test_summary.md`, `architect_test_results.txt` — pure RLHF "wrap-up nicely" behavior. Cost ~$0.50 wasted; sprint files themselves were not corrupted.

**Root cause of (1):** `tracker/agent/tools/write_enriched_sprint.go`'s "REQUIRED SECTIONS" list and embedded `write_enriched_sprint_example.md` predate the v3→v7 NIFB iteration. An earlier behavioral patch (P-1..P-7, M-1..M-4, two-pass review, landed Apr 30 2026 in commit `ff7e297`) added the new rules but didn't update section names or the few-shot anchor. The fix in this v2 run was to rewrite the section list to the speedrun shape and replace the embedded example with NIFB SPRINT-001 + SPRINT-002.

**Root cause of (2):** the agent runtime relies on model discretion to stop (no tool calls in turn → terminate). Sonnet's RLHF biases toward post-task wrap-up; given spare turns and `write` tool access, it invents helpful artifacts.

## v2 — Writer prompt rewrite; format aligned

**What changed in tracker:**
1. Replaced the REQUIRED SECTIONS list in `sprintSystemPromptHeader` with the validated speedrun-exemplar list (Scope, Non-goals, Dependencies, Conventions, Tricky semantics, Data contract, API contract, Algorithm, Test contract, [Verbatim files], New files, Modified files, Rules, DoD, Validation).
2. Added a "SCOPE OF RESPONSIBILITY" preamble explaining what Opus's contract owns vs what Sonnet expands per-sprint (so additive sprints redirect to the contract for shared schemas/tricky semantics rather than re-inventing).
3. Replaced `write_enriched_sprint_example.md` with NIFB SPRINT-001 (foundation, 828 lines) + SPRINT-002 (additive, 222 lines) concatenated. Now Sonnet sees BOTH shapes as few-shot anchors.

**Outcome:**
- ✅ Section structure: byte-for-byte match with NIFB exemplars. Foundation sprint has 15 sections including `## Verbatim files`; additive sprints have 14 sections (no Verbatim files), with the exact header redirect notes ("inherited from Sprint 001 — listed here for tight feedback", "no new types — referenced from sprint 001", etc.).
- ✅ Density: SPRINT-002's `## Algorithm` has 5 per-route subsections with numbered prose steps naming exact symbols (`raise AppError(404, "Note not found", NOTE_NOT_FOUND)`, `req.model_dump(exclude_unset=True)`). Test contract has per-test-file tables with subtest counts and EXACT distinguishing values (P-6 pattern: `email="other@example.com"`).
- ✅ Audit verdicts: **3/3 PASS, zero patches.** v1 had 3/3 PATCHED — auditor finds the new specs clean as-is.
- ❌ Architect still didn't stop. Same wrap-up doc generation behavior.

## v3 — TerminalTool runtime feature; dip bug exposed

**What changed in tracker:**
1. Added `TerminalTool` interface in `tracker/agent/tools/registry.go`. Tools may opt in via `IsTerminal() bool`.
2. Modified `agent/session.go`'s loop: after `executeToolCalls`, if any executed tool is terminal AND its result is not an error, set `stoppedNaturally = true` and break. Tool errors keep the loop alive (so the agent can retry).
3. `DispatchSprintsTool` flagged terminal.
4. Added per-sprint transient-retry-with-backoff inside `dispatch_sprints` (uses tracker's existing `llm.ProviderErrorInterface.Retryable()`; Levenshtein-style backoff up to 3 attempts on 5xx/timeout/rate-limit).

**Outcome:**
- ✅ TerminalTool fires correctly. Activity log shows: `[10:23:05] dispatch_sprints ok: ...` immediately followed by `[10:23:05] node "Start" outcome: success` and `edge selected Start->setup_workspace` — same wall-clock second. No extra summary docs from that agent.
- ❌ A different bug surfaced: the dip's `agent Start` and `agent Exit` (intended as DAG entry/exit markers, prompts: "Begin architect-only test" / "Architect-only test complete") inherited the full global tool registry (read, write, dispatch_sprints). Sonnet — given the prompt and tools — interpreted "Begin architect-only test" as instruction and ran the FULL architect workflow inside the Start node. Then the pipeline correctly advanced through `setup_workspace` and re-ran the architect work in `write_sprint_docs` (Opus this time, per the dip's `model:` spec). Doubled the cost; explained why earlier runs (v1/v2) showed `claude-sonnet-4-5` running the architect when the dip specified `claude-opus-4-6`.

**Diagnosis:** the v3 fix exposed the v1/v2 bug because the Start agent now terminates cleanly on dispatch success — so the pipeline progresses to the next node, and we see that the next node is *also* doing the same work.

## v4 — Dip cleanup; full clean run

**What changed in pipelines:**
- `architect_only_test.dip`: replaced `agent Start` and `agent Exit` with `tool` nodes that just `printf` a marker. Removed all LLM cost from the entry/exit pseudo-nodes.

**Outcome (final, validated):**

```
[10:29:56] Start (tool, instant — no LLM)
[10:29:56] setup_workspace (tool, instant)
[10:29:56] write_sprint_docs starts
[10:29:58] llm start anthropic/claude-opus-4-6     ← finally the right model
[10:32]    contract.md written (27434 bytes)
[10:33]    sprint_descriptions.jsonl written (14463 bytes)
[10:33:31] Opus self-verifies the JSONL via bash python3 (sanity check)
[10:33:34] dispatch_sprints called
[10:36]    SPRINT-001.md written (audit applied patches)
[10:37]    SPRINT-002.md written (audit=PASS)
[10:39]    SPRINT-003.md written (audit=PASS)
[10:39:04] dispatch_sprints ok: dispatched=3 (PASS=2, PATCHED=0, fallbacks=1, failures=0)
[10:39:04] node "write_sprint_docs" outcome: success    ← terminal tool fired
[10:39:04] write_ledger
[10:39:05] validate_output (passed)
[10:39:05] Exit
[10:39:05] pipeline_completed
```

**Validated:**
- Opus actually drives the architect agent (model spec honored) — first run since structural fix landed.
- Opus does productive self-verification (`bash python3` sanity check on the JSONL) BEFORE dispatching, rather than wrapping up post-dispatch with summary docs. Useful behavior.
- `dispatch_sprints` makes ONE tool call from the agent's perspective; tool internally fans out 3 Sonnet calls + their audits.
- TerminalTool fires same wall-clock second as `dispatch_sprints` returns.
- No `QUICKREF.md` / `ARCHITECT_TEST_COMPLETE.md` / etc. in `.ai/` — only legitimate artifacts.
- Section structure matches validated exemplars (verified via `grep '^## '` diff against `exemplars/SPRINT-00{1,2,3}.md`).
- Pipeline progression: `Start → setup_workspace → write_sprint_docs → write_ledger → validate_output → Exit` all green.
- ledger.tsv populated with 3 rows, all `planned`.

**Total run cost:** ~$2 (1 Opus session ≈ 30K tokens + 3× Sonnet author + 3× Sonnet audit ≈ 90K tokens).

## Quick reference: where each fix lives

| Concern | Fix | Lives in |
|---|---|---|
| Per-sprint deterministic loop (no Opus self-revise) | `dispatch_sprints` tracker tool | `tracker/agent/tools/dispatch_sprints.go` |
| Section structure matches NIFB exemplars | `sprintSystemPromptHeader` REQUIRED SECTIONS list | `tracker/agent/tools/write_enriched_sprint.go` |
| Few-shot anchor on real foundation+additive examples | embedded `write_enriched_sprint_example.md` | same (binary embed via `//go:embed`) |
| Agent terminates on dispatch success | `TerminalTool` interface + session loop check | `tracker/agent/tools/registry.go` + `tracker/agent/session.go` |
| Per-sprint API errors retry transparently | `runOneWithRetry` | `tracker/agent/tools/dispatch_sprints.go` |
| Audit SR blocks tolerate whitespace drift | 4-strategy `applySRBlocks` | `tracker/agent/tools/write_enriched_sprint.go` |
| DAG entry/exit don't run the architect work | `tool` nodes (not `agent`) | `local_code_gen/architect_only.dip` and `local_code_gen/spec_to_sprints.dip` |
| Foundation sprint pattern (front-loaded + auto-discovery + FROZEN) | Opus prompt body | `local_code_gen/architect_only.dip` and `local_code_gen/spec_to_sprints.dip` (`write_sprint_docs` agent) |

## Acceptance gate status

| Test | Status |
|---|---|
| Test 1: design_phase isolation (contract.md + jsonl + clean stop) | **pass** (v4) |
| Test 2: dispatch_sprints unit-tested loop semantics | **pass** (4 unit tests) |
| Test 3: end-to-end synthetic — all artifacts + structural rules + speedrun shape | **pass** (v4) |
| Test 4: NIFB acceptance | **not yet run** (next step) |
| Test 5: qwen runner end-to-end | **pass on synthetic** (see [RUNNER-INTEGRATION.md](RUNNER-INTEGRATION.md): 34/34 tests on Notebook fixture) |

## What's still open

- **NIFB acceptance test** — validate the fix at production scale (16 sprints, ~$4-5, ~30 min). Synthetic is green; NIFB is the next gate.
- **Auditor SR-block fallback rate** — v4 hit `audit=PASS-FALLBACK-NOMATCH` once out of 3. The 4-strategy matcher should reduce these but it can still miss when SEARCH text differs by structural restructuring (not just whitespace). Worth tracking PASS-FALLBACK rate on NIFB.
- **Sprint 001 LocalFix oscillation** — runner side observed 11 LocalFix rounds before CloudFix took over. Most rounds were qwen patching code to work around dependency-resolution errors (`email-validator` was missing) that local model couldn't diagnose. See [RUNNER-INTEGRATION.md](RUNNER-INTEGRATION.md) for the proposed early-escalation heuristic for `ImportError` / `ModuleNotFoundError` failures.
- **`dispatch_sprints` parallel mode** — sprints have no inter-dependencies once the JSONL is on disk. Could go from sequential 3-sprint dispatch (~6 min) to concurrent (~2 min limited by Anthropic rate). Out of scope for v1; future cost/time win.

## Files to read for context

- `experiments/notebook_smoke_v4/.ai/contract.md` — the Opus-authored contract from a clean run (gitignored test workdir; recreate by running `local_code_gen/architect_only.dip` against the synthetic fixture)
- `experiments/notebook_smoke_v4/.ai/sprint_descriptions.jsonl` — the JSONL handoff between Opus and dispatch_sprints
- `experiments/notebook_smoke_v4/.ai/sprints/SPRINT-001.md` — foundation spec (33KB, all 15 speedrun sections)
- `local_code_gen/principles/exemplars/SPRINT-001.md` — the validated reference shape (NIFB v7)
- `experiments/notebook_smoke_v4/backend/` — the runner-generated working code (34 tests passing — see [RUNNER-INTEGRATION.md](RUNNER-INTEGRATION.md))
- `tracker/agent/tools/dispatch_sprints.go` — the deterministic dispatch loop
- `tracker/agent/tools/write_enriched_sprint.go` — the speedrun-aligned writer prompt + 4-strategy SR matcher
- `tracker/agent/session.go:240` — the TerminalTool short-circuit in the session loop
