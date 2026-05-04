# Structural fix: deterministic sprint dispatch (Opus designs, tracker iterates)

**Status: PROPOSAL (historical, May 1 2026).** Original proposal for the architectural cleanup that removed Opus's agency over the per-sprint dispatch loop. Captures the reasoning behind the now-landed design.

> **Note on paths in this document:** this proposal was written before the May 4 reorganization that moved the dips into `local_code_gen/`. References to `architect_only_test.dip`, `sprint_runner_local_gen_qwen_sr.dip`, `experiments/sprint_authoring_principles/` etc. are accurate to the file layout at the time of writing. Current paths: `local_code_gen/architect_only.dip`, `local_code_gen/sprint_runner.dip`, `local_code_gen/principles/`. See [`STRUCTURAL-FIX-RESULTS.md`](STRUCTURAL-FIX-RESULTS.md) for the post-implementation file map.

## The principle

> **Opus is the architect, not the project manager.** Its job is design — author the cross-sprint contract and decide what each sprint should contain. Once that decision is made, dispatching the per-sprint writes should be a deterministic loop, not an LLM agent loop.

Today, Opus has tool access (`read`, `write`, `write_enriched_sprint`) and runs as an agent until it stops emitting tool calls. The "natural stop" is supposed to be: after dispatching N `write_enriched_sprint` calls (one per sprint in the plan), Opus has nothing left to do and stops. This relies on **Opus choosing to stop**.

That's fragile. Frontier models, when given any signal that something might be off (a non-trivial tool result, a length cap, a slightly-imperfect output), will often invoke `read` to verify and `write` to revise. We saw this on Apr 30, 2026 — Opus dispatched `write_enriched_sprint` for SPRINT-001, saw an `audit=PASS-FALLBACK-NOMATCH` in the tool return, and went into a self-review loop that destroyed `contract.md` (overwrote with 0 bytes), then tried to recover. Single-sprint test that should have completed in 2 minutes consumed 3+ extra minutes of Opus tokens before we killed it.

The problem is not Opus's stop discretion specifically — it's that the architecture **gives Opus discretion at all** for a step that should be mechanical.

## The structural fix in one paragraph

Split `write_sprint_docs` into two stages:

1. **Stage 1 — `design_phase` (Opus, agent):** Reads inputs, authors `.ai/contract.md`, AND emits `.ai/sprint_descriptions.jsonl` (one JSON record per sprint, ordered). After both files exist, Opus has no more tools available; the agent terminates.

2. **Stage 2 — `dispatch_sprints` (tracker tool, deterministic):** Reads `.ai/sprint_descriptions.jsonl` line by line. For each line: parses the JSON, calls `write_enriched_sprint` with the embedded path/description. Logs progress. Returns a summary. Pure for-loop semantics.

Pipeline becomes:

```
Start → setup_workspace → design_phase (Opus) → dispatch_sprints (tool) → write_ledger → validate_output → Exit
```

Opus has no opportunity to second-guess — once it writes the descriptions JSONL, it has no remaining capability. The dispatch is mechanical and observable.

## What changes in concrete terms

### `spec_to_sprints.dip` (and `architect_only_test.dip`)

The `write_sprint_docs` agent's tools list shrinks:

```
Before: tools available to agent = read, write, write_enriched_sprint
After:  tools available to agent = read, write (only)
```

Stripping `write_enriched_sprint` from the agent's tool whitelist is the **structural enforcement**. Even if Opus *wants* to dispatch, it can't. After writing the contract + descriptions, its remaining work is zero — the only tools it has produce side effects on those two specific files.

The agent prompt body becomes simpler too:

- Old: "Iterate over every sprint, calling `write_enriched_sprint` once per sprint, then stop."
- New: "Author `.ai/contract.md`. Then author `.ai/sprint_descriptions.jsonl` with one JSON record per sprint in `.ai/sprint_plan.md`. Each record has fields `{path: str, description: str}`. After both files exist, your task is complete; stop."

The behavioral risk that produced today's failure goes away because the prompt's "iteration" phase no longer exists at the agent level.

### New tracker tool: `dispatch_sprints`

A small Go tool in the tracker repo that:

1. Reads `.ai/sprint_descriptions.jsonl` (path optional via arg, defaults to `.ai/sprint_descriptions.jsonl`)
2. For each line: parses `{path, description}`, calls the existing `write_enriched_sprint` tool internally with `path`, `description`, and `output_dir` (defaults to `.ai/sprints`)
3. Each call goes through the existing author + audit two-pass pipeline we already built
4. Logs progress per sprint to the activity stream (`Wrote 001 ✓ audit=PASS, Wrote 002 ✓ audit=PATCHED, ...`)
5. Returns a summary: `dispatched N sprints, K with audit patches applied, M fallbacks`

Estimated implementation: ~50-80 lines of Go in `agent/tools/dispatch_sprints.go`. Reuses `WriteEnrichedSprintTool::Execute` internally.

### Format of `sprint_descriptions.jsonl`

One JSON object per line, ordered by sprint number:

```json
{"path": "SPRINT-001.md", "description": "Sprint 001 — Core Backend Foundation & Authentication\n\n## Scope\n...\n\n## File breakdown\n...\n## Validation\n..."}
{"path": "SPRINT-002.md", "description": "Sprint 002 — ...\n..."}
{"path": "SPRINT-003.md", "description": "..."}
```

The `description` field is the per-sprint slice the architect already produces today — title, scope, FR coverage, file breakdown (new vs modified), types/functions (names; fields are pinned in contract.md), cross-sprint dependencies, validation commands, infrastructure specifics for foundation sprints, etc. Same content as today's per-call argument; just persisted to disk first instead of streamed as a tool-call argument.

### Edge changes in the dip

```
Old:
  setup_workspace -> write_sprint_docs -> write_ledger -> validate_output -> Exit

New:
  setup_workspace -> design_phase -> dispatch_sprints -> write_ledger -> validate_output -> Exit
```

The agent rename (`write_sprint_docs` → `design_phase`) is cosmetic but communicates the new role: Opus designs; the tool dispatches.

## What this buys us

### 1. Determinism

Opus's behavior doesn't depend on its momentary discretion to stop. Once it produces the two artifacts, its job is enforced-complete because the agent has no more tools to call. No re-entry. No second-guessing.

### 2. Inspectability

`.ai/sprint_descriptions.jsonl` is **inspectable before any Sonnet calls fire**. We can read it and verify Opus's per-sprint planning is sound — does the sprint 001 description name all 18 entities? Does each sprint 002+ description say "Modified files: (none)"? — without paying for the Sonnet expansion. If Opus's plan is bad, we catch it before the expensive step.

### 3. Failure isolation

If `write_enriched_sprint` fails on sprint 005, the tracker tool can: (a) log the failure, (b) continue to sprints 006–016, OR (c) abort, depending on policy. With Opus driving the loop, retry policy is implicit and tied to model judgment. With a deterministic tool, retry policy is code we can read and reason about.

### 4. Resumability

A failure midway through dispatch can be resumed by re-running just the tool. The JSONL plan is the input; we know exactly which sprints completed (those have files in `.ai/sprints/`) and which didn't. Today, resuming requires re-running Opus, which may re-author the contract and re-decide descriptions.

### 5. Parallelizability

`write_enriched_sprint` calls have no inter-sprint dependencies (each call is a self-contained Sonnet generation). The dispatch tool could run them in parallel, cutting wall time from 16 sequential Sonnet calls (~30 min) to a parallel batch (~3-5 min, limited by Anthropic rate limits). Would require concurrent execution support in Go but is straightforward — `errgroup` over goroutines, per-sprint outputs collected. Not strictly necessary for v1; future cost/time win.

### 6. Cost transparency per stage

Today, all of Opus + 16× Sonnet calls happen inside one agent loop. Cost attribution requires digging through activity logs. With two stages, we get clean cost breakdown: `design_phase` cost (Opus) + `dispatch_sprints` cost (16× Sonnet × 2 passes). Easier to reason about and optimize.

## What it does NOT change

- The `write_enriched_sprint` tool itself (already correctly implements two-pass author + audit).
- The Sonnet system prompt (already updated with within-sprint patterns + meta-rules + two-pass audit + SR-block surgical patches).
- The contract.md content (Opus still produces it during `design_phase`).
- The runner-side dip (`sprint_runner_local_gen_qwen_sr.dip`) — completely unaffected.
- Per-sprint description content — same shape as today, just emitted to JSONL instead of streamed as a tool-call argument.

## Implementation plan

Roughly 60-90 minutes of work end-to-end, split across the tracker repo and the pipelines repo:

### Tracker repo (`feat/write-enriched-sprint-tool` branch)

1. Add `agent/tools/dispatch_sprints.go` (~80 lines):
   - Tool signature accepts optional `descriptions_file` arg (default `.ai/sprint_descriptions.jsonl`) and `output_dir` (default `.ai/sprints`).
   - Reads the file line-by-line, parses each as `{path, description}`.
   - For each: invokes `WriteEnrichedSprintTool.Execute()` with the per-sprint inputs (reusing existing two-pass logic).
   - Aggregates results: count of dispatched, count of audit-patched, count of fallbacks, list of failures.
   - Returns a summary string.
2. Register the tool in `pipeline/handlers/backend_native.go` next to `write_enriched_sprint`.
3. Add unit tests for the JSONL parser + the loop behavior (mock the inner tool).

### Pipelines repo

4. Update `spec_to_sprints.dip`'s `write_sprint_docs` agent:
   - Rename to `design_phase` (cosmetic).
   - Drop `write_enriched_sprint` from the tools list.
   - Replace the per-sprint iteration prompt section with a "produce sprint_descriptions.jsonl" instruction.
5. Add a new `dispatch_sprints` tool node that calls the new tracker tool.
6. Update edges: `setup_workspace → design_phase → dispatch_sprints → write_ledger → validate_output → Exit`.
7. Same updates to `architect_only_test.dip` and any other spec-to-sprints variant dips.
8. Update `experiments/sprint_authoring_principles/CANDIDATE-OPUS-PROMPT-PATCH.md` to reflect the new design-only Opus role.

### Validation

9. Run `architect_only_test.dip` end-to-end against `.ai/sprint_plan.md` (the trimmed-to-1-sprint plan we already have).
10. Verify:
    - `contract.md` exists and has all 9+ sections.
    - `sprint_descriptions.jsonl` exists with N lines (N = sprint count).
    - `.ai/sprints/SPRINT-001.md` exists at expected size.
    - Activity stream shows `design_phase` finished cleanly (no late `read`/`write` calls), `dispatch_sprints` ran, and N tool calls completed.
    - No file gets overwritten after its initial successful write.

## Migration safety

The change is non-breaking for downstream consumers:

- `.ai/contract.md` and `.ai/sprints/SPRINT-NNN.md` outputs are byte-identical to today's pipeline (Sonnet expansion logic unchanged).
- The new `.ai/sprint_descriptions.jsonl` is added; nothing reads it except `dispatch_sprints`. Old code that doesn't know about it ignores it.
- The runner dip (`sprint_runner_local_gen_qwen_sr.dip`) reads only `contract.md` and `sprints/`, so it's unaffected.

If the structural fix has issues, reverting is just: revert the dip changes (one commit) and the tool changes (one commit on the tracker side). No data migration. No client-facing surface change.

## Why we didn't do this earlier

The Apr-2026 architect-Sonnet migration was incremental — kept the agent-driven iterate-per-sprint pattern intentionally to minimize change-surface against the working `spec_to_sprints.dip`. The natural-stop signal was load-bearing then, and at the time the prompt was thin enough that the natural stop reliably fired.

Today's session added meta-rules + cross-section consistency content + a verbose tool-result string that surfaces audit verdict to Opus. Each of those nudges Opus toward verification mode. The natural-stop pattern that worked under the simpler prompt no longer works reliably under the richer prompt. **The fix is to remove the dependence on natural stop entirely** — give Opus a finite design task with no dispatch capability, and put the loop in code.

## Open questions

- **Should `dispatch_sprints` halt on first failure, or continue and report?** Default: continue and report. Failures get rolled into a final summary; a `--strict` mode could halt instead. Probably worth implementing both modes from the start.
- **Should the JSONL be schema-validated by tracker before dispatch?** Probably yes — verify each line parses to `{path, description}` and the path looks like `SPRINT-NNN.md`. Catches Opus producing malformed JSON without paying for failed Sonnet calls.
- **Should the dispatch tool prompt-cache the contract once and pass cached-token-id to write_enriched_sprint?** Anthropic's prompt caching could give a 90% cost reduction on the contract content (which is identical across all 16 calls). Worth investigating once the basic structural fix lands.
- **Parallel vs sequential dispatch?** v1: sequential (matches today's behavior). v2: optional `--parallel N` for concurrent calls limited by rate. Defer.

## Decision criteria for greenlight

Land this if any of the following keep happening after the tactical fix (terse tool returns + tighter stop rule):

- Opus making `write` calls after its last `write_enriched_sprint`
- Opus making `read` calls after its last `write_enriched_sprint`
- Multiple `contract.md` write events per run
- Multiple `SPRINT-NNN.md` write events per sprint per run

Each of those is a symptom of agency-where-it-shouldn't-exist. The structural fix removes the agency. The tactical fix discourages it but doesn't remove it.

If the tactical fix is enough (Opus stops cleanly after N tool calls and doesn't re-enter), the structural fix is still worthwhile for the inspectability + resumability + parallelism wins, but not urgent.
