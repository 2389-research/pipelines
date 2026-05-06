# Sprint Authoring Principles

**Source-of-truth doc for how the sprint-spec architect (Opus) and the per-sprint writer (Sonnet) should think.** Principles validated through the v3→v7 NIFB iteration on Apr 30, 2026 — pipeline-validated to 47/47 cumulative tests passing on first generation pass + one LocalFix round.

## Runtime data flow (read this first)

```
                ┌─ inline prompt embeds                               ┌─ inline prompt embeds
                │   the cross-sprint patterns                          │   the within-sprint patterns
                │   + meta-rules                                       │   + speedrun format
                ▼                                                      ▼
   spec_to_sprints.dip:537                          tracker repo: write_enriched_sprint tool
     ┌─────────────────────┐                          ┌─────────────────────────┐
     │  Opus               │                          │  Sonnet                 │
     │  (write_sprint_docs)│  ── per-sprint call ──▶  │  (per-sprint expander)  │
     └──────────┬──────────┘                          └────────────┬────────────┘
                │                                                  │
                │ writes once per project                          │ reads on every call
                ▼                                                  ▼
            .ai/contract.md ◀────────────────────────── .ai/contract.md
            (cross-sprint pins for THIS project)
                                                                   │
                                                                   │ writes
                                                                   ▼
                                                         .ai/sprints/SPRINT-NNN.md
                                                                   │
                                                                   │ qwen reads
                                                                   ▼
                                                              backend/<files>
```

**The principle docs in this dir are NOT read by the models at runtime.** They're human maintenance material:

- The **patterns + meta-rules** get embedded inline into the Opus prompt (in `spec_to_sprints.dip`) and the Sonnet system prompt (in the tracker tool's Go source).
- `.ai/contract.md` is the runtime bridge between Opus and Sonnet (Opus writes it; Sonnet reads it on every call).
- The **exemplars** (`exemplars/SPRINT-NNN.md`) are reference material for engineers maintaining the system, not embedded in any prompt.

## Maintenance workflow

When we learn a new pattern:

1. Append the empirical evidence to [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) (record).
2. Decide: cross-sprint (Opus) or within-sprint (Sonnet)?
3. Fold into an existing pattern in [`PATTERNS.md`](PATTERNS.md), or add a new pattern category if none fits.
4. Update [`CANDIDATE-OPUS-PROMPT-PATCH.md`](CANDIDATE-OPUS-PROMPT-PATCH.md) or [`CANDIDATE-SONNET-PROMPT-PATCH.md`](CANDIDATE-SONNET-PROMPT-PATCH.md) — these are the **diff staging surface** between the principles dir and the production prompts.
5. Apply the patches:
   - Opus → edit `pipelines/spec_to_sprints.dip:537` `write_sprint_docs` agent body
   - Sonnet → edit the tracker tool's system prompt in the tracker repo's Go source (separate-repo work)

The two CANDIDATE-*-PATCH docs make the human-to-prompt sync step explicit. They are the only files that have a 1:1 correspondence with production prompt content.

## Quick navigation

### Active material (synced into runtime prompts)

| Doc | Purpose |
|---|---|
| [`PATTERNS.md`](PATTERNS.md) | The 7 pattern categories consolidated — split by Opus (cross-sprint) vs Sonnet (within-sprint). Short, high-level. |
| [`CANDIDATE-OPUS-PROMPT-PATCH.md`](CANDIDATE-OPUS-PROMPT-PATCH.md) | Drop-in text for `spec_to_sprints.dip:537`'s `write_sprint_docs` agent. Cross-sprint patterns + architect_v2 design + meta-rules. **Status: candidate (not yet applied to dip).** |
| [`CANDIDATE-SONNET-PROMPT-PATCH.md`](CANDIDATE-SONNET-PROMPT-PATCH.md) | Drop-in text for the tracker tool's `write_enriched_sprint` Sonnet system prompt. Speedrun format + within-sprint patterns + two-pass review. **Status: APPLIED + EXTENDED.** Behavioral patterns (P-1..P-7, M-1..M-4, two-pass review) landed Apr 30, 2026 (`ff7e297`). Section-list rewrite to speedrun shape + few-shot example replaced with NIFB SPRINT-001 + SPRINT-002 landed May 1, 2026 (see [`STRUCTURAL-FIX-RESULTS.md`](STRUCTURAL-FIX-RESULTS.md) v2). |

### Reference material (humans only)

| Doc | Purpose |
|---|---|
| [`ARCHITECT-V2-DESIGN.md`](ARCHITECT-V2-DESIGN.md) | All-front-loaded pattern: foundation + auto-discovery + FROZEN-files. Default for small-to-medium projects (≤7 entities, ≤4 sprints). |
| [`SUBSYSTEM-FRONT-LOADED.md`](SUBSYSTEM-FRONT-LOADED.md) | Sibling pattern for larger projects: each sprint front-loads its OWN subsystem's modules; auto-discovery for both routers AND models means later sprints don't modify any earlier-sprint file. Use when ≥8 entities or ≥5 sprints. The architect picks per-project; both patterns documented in the Opus prompt. |
| [`SPEEDRUN-SPEC-FORMAT.md`](SPEEDRUN-SPEC-FORMAT.md) | Detailed section structure of a SPRINT-NNN.md spec. Full reference; the prompt patches summarize. |
| [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) | Empirical record of the 14 defect classes we hit. Appendix to `PATTERNS.md` — useful when debugging "have we seen this before?" |
| [`QWEN-HYPERPARAMETERS.md`](QWEN-HYPERPARAMETERS.md) | Qwen3.6:35b-a3b sampling settings. For the runner dip, not the architect. |
| [`STRUCTURAL-FIX-PROPOSAL.md`](STRUCTURAL-FIX-PROPOSAL.md) | Design for the deterministic dispatch architecture (Opus designs, tool dispatches mechanically). |
| [`STRUCTURAL-FIX-TEST-PLAN.md`](STRUCTURAL-FIX-TEST-PLAN.md) | Test strategy for validating the structural fix piece-by-piece on a synthetic Notebook API fixture. |
| [`STRUCTURAL-FIX-RESULTS.md`](STRUCTURAL-FIX-RESULTS.md) | Smoke-test progression v1→v4 (2026-04-30 → 2026-05-01). Final state: clean end-to-end run, Opus drives architect, TerminalTool primitive landed, dip cleaned up, spec format byte-for-byte matches NIFB exemplars. |
| [`RUNNER-INTEGRATION.md`](RUNNER-INTEGRATION.md) | Runner-side integration: section-name alignment between v4 architect output and the SR runner; 4-strategy SR-block matcher port from `../merge_sr.py` to the auditor; end-to-end Notebook run produces 34/34 passing tests for ~$2.30; defect-class observation (dependency errors vs logic errors) and proposed early-escalation heuristic. |
| [`synthetic_fixtures/`](synthetic_fixtures/) | 3-sprint Notebook API spec_analysis + sprint_plan used as the synthetic test fixture for STRUCTURAL-FIX runs. Cheap to iterate on, exercises the front-loaded foundation pattern + auto-discovery. |
| [`TWO-PASS-REVIEW.md`](TWO-PASS-REVIEW.md) | The architect's review process — Pass 1 produces; Pass 2 scrutinizes. The full Pass 2 checklist. |
| [`exemplars/`](exemplars/) | Three known-good SPRINT-NNN.md files (sprints 001-003 from NIFB v7). What "right" looks like in practice. |

## Why these patterns aren't an exhaustive list

Frontier models (Opus + Sonnet) work better given a small set of well-described pattern categories with examples, plus the meta-pattern statement, than a long checklist. The 14 defect classes are 14 *instances* of ~7 *patterns*. New stacks will surface new instances; the patterns extrapolate.

The prompts ([`CANDIDATE-OPUS-PROMPT-PATCH.md`](CANDIDATE-OPUS-PROMPT-PATCH.md), [`CANDIDATE-SONNET-PROMPT-PATCH.md`](CANDIDATE-SONNET-PROMPT-PATCH.md)) communicate "here's the kind of work you're doing, here's what failures look like, here's what success looks like" — not "follow these 14 rules to the letter."

## How to test the Opus + Sonnet flow end-to-end

The natural test: regenerate a known project's sprint specs through the updated prompts and verify the outputs match the speedrun format + pass through the qwen runner pipeline.

### Test 1: Regenerate NIFB sprints from the updated Opus prompt

1. Apply [`CANDIDATE-OPUS-PROMPT-PATCH.md`](CANDIDATE-OPUS-PROMPT-PATCH.md) to `pipelines/spec_to_sprints.dip:537`.
2. (Optional, for a clean test) Apply [`CANDIDATE-SONNET-PROMPT-PATCH.md`](CANDIDATE-SONNET-PROMPT-PATCH.md) to the tracker tool. If the tracker isn't updated, Sonnet uses the old prompt — partial test.
3. Set up a fresh workdir based on `experiments/NIFB/.ai/`:
   ```fish
   set WORKDIR /Users/michaelsugimura/Documents/GitHub/pipelines/experiments/sprint_pipeline_test_v8
   rm -rf $WORKDIR
   mkdir -p $WORKDIR/.ai
   cp /Users/michaelsugimura/Documents/GitHub/pipelines/experiments/NIFB/.ai/spec_analysis.md $WORKDIR/.ai/
   cp /Users/michaelsugimura/Documents/GitHub/pipelines/experiments/NIFB/.ai/sprint_plan.md $WORKDIR/.ai/
   cd $WORKDIR && git init -q
   ```
4. Run the architect pipeline:
   ```fish
   ~/go/bin/tracker --no-tui --autopilot lax /Users/michaelsugimura/Documents/GitHub/pipelines/spec_to_sprints.dip
   ```
5. Validate the output against the patterns:
   - **`.ai/contract.md`** should contain: build-system block requirements, error/handler shape, async loading strategy, test infrastructure (StaticPool + closure pattern), Settings semantics, FROZEN files list, cross-sprint type/symbol map with `lazy="selectin"` annotations.
   - **`.ai/sprints/SPRINT-001.md`** should be ~600-1000 lines (front-loaded foundation), contain a verbatim `app/main.py` with pkgutil auto-discovery, declare 18+ entities with relationships, and have all 14 defect-class rules pre-applied.
   - **`.ai/sprints/SPRINT-002.md`** should be ~150-300 lines (additive), contain `## Modified files: (none)`, declare 1 router + 1 test file per feature.

   Compare to [`exemplars/SPRINT-001.md`](exemplars/SPRINT-001.md), [`exemplars/SPRINT-002.md`](exemplars/SPRINT-002.md), [`exemplars/SPRINT-003.md`](exemplars/SPRINT-003.md) for shape.

6. End-to-end: run the generated sprint 001 through `local_code_gen/sprint_runner.dip`. If the architect prompts are correct, sprint 001 generates 20+ files and pytest passes 21+ tests on the first try (or with at most one LocalFix round).

### Test 2: Spot-check the cross-sprint contract

A correct `.ai/contract.md` from the updated Opus prompt should:

- [ ] Declare the front-loaded foundation pattern explicitly
- [ ] List FROZEN files (`app/main.py`, `app/models.py`, `app/schemas.py`, `app/exceptions.py`, `app/database.py`, `app/config.py`)
- [ ] Pin the error response shape (flat `{"detail": str, "error_code": str}`)
- [ ] Pin async loading strategy (`lazy="selectin"` on collection sides)
- [ ] Pin the StaticPool + connect_args requirement for in-memory SQLite tests
- [ ] Pin the closure-vs-module-level rule for fixture-dependent helpers
- [ ] Pin the build-system block requirement (hatchling wheel.packages or equivalent)
- [ ] Cross-sprint type/symbol map shows full ORM signatures with relationship annotations

### Test 3: Spot-check a single sprint's spec

A correct SPRINT-002.md from the updated Sonnet prompt (additive sprint) should:

- [ ] Be ~150-300 lines
- [ ] Have `## Modified files: (none — Sprint 001's main.py auto-discovers)`
- [ ] Have explicit Path/query parameter type annotations in the API contract (not in route patterns alone)
- [ ] Order static routes before parameterized routes that share a prefix — IN BOTH the rule AND the API contract table
- [ ] Have per-file imports as full Python statements (`from datetime import datetime`, not bare `datetime`)
- [ ] Use `body["error_code"]` (matching the cross-sprint error shape) in test assertions, not `body["detail"]["error_code"]`
- [ ] Specify EXACT values for second-instance test data (e.g., `Volunteer(email="other@example.com", phone="+15559999999", ...)`)
- [ ] List the EXACT field set when constructing a Read schema explicitly

### Test 4: Cost/time benchmark

The original NIFB run cost ~$3.30 / 30 min for 16 sprints with the prior architect prompt. The updated prompts will produce richer specs (more pinned cross-sprint conventions, more thorough within-sprint sections). Expected cost: $4-5 / 35-40 min. Worth measuring.

### What "passing" looks like

The architect prompts are working when:

1. The generated `.ai/contract.md` contains all 7 pattern categories pinned explicitly.
2. Sprint 001 (front-loaded foundation) generates 20+ files via the runner with 21+ tests passing on the first generation pass — same result as our v7 manual hand-write produced.
3. Sprint 002 (additive) declares zero modifications, contains one router file per feature with the within-sprint patterns applied, and runs through the runner with at most one LocalFix round.
4. The full 16-sprint NIFB run completes through the architect pipeline in <40 min and <$5 (validating Sonnet's per-sprint expansion is consistent under the new prompt).

If any of these fail, the failure mode tells us which pattern wasn't sufficiently encoded — and the fix is to refine the relevant CANDIDATE-*-PATCH doc, then re-apply.
