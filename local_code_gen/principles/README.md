# Sprint Authoring Principles

**Source-of-truth doc for how the sprint-spec architect (Opus) and the per-sprint writer (Sonnet) should think.** Principles validated through the v3→v7 NIFB iteration on Apr 30, 2026 — pipeline-validated to 47/47 cumulative tests passing on first generation pass + one LocalFix round.

## Runtime data flow (read this first)

```text
                ┌─ inline prompt embeds                               ┌─ inline prompt embeds
                │   the cross-sprint patterns                          │   the within-sprint patterns
                │   + meta-rules                                       │   + speedrun format
                ▼                                                      ▼
   spec_to_sprints.dip                              tracker repo: write_enriched_sprint tool
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

- The **patterns + meta-rules** are embedded inline into the Opus prompt in `local_code_gen/spec_to_sprints.dip` and the Sonnet system prompt in the tracker tool's Go source (`tracker/agent/tools/write_enriched_sprint.go`).
- `.ai/contract.md` is the runtime bridge between Opus and Sonnet (Opus writes it; Sonnet reads it on every call).
- The **exemplars** (`exemplars/SPRINT-NNN.md`) are reference material for engineers maintaining the system, not embedded in any prompt.

## Maintenance workflow

When we learn a new pattern:

1. Append the empirical evidence to [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) (record).
2. Decide: cross-sprint (Opus) or within-sprint (Sonnet)?
3. Fold into an existing pattern in [`PATTERNS.md`](PATTERNS.md), or add a new pattern category if none fits.
4. Apply the change to the live prompt:
   - Opus → edit the `write_sprint_docs` agent body in `local_code_gen/spec_to_sprints.dip` (and `local_code_gen/architect_only.dip` for the path-B variant).
   - Sonnet → edit the system prompt in `tracker/agent/tools/write_enriched_sprint.go` (separate-repo work).
5. Validate by re-running [`../architect_only.dip`](../architect_only.dip) against the [`synthetic_fixtures/`](synthetic_fixtures/) and confirming the new pattern lands in the generated contract.md / SPRINT-*.md.

## Quick navigation

| Doc | Purpose |
|---|---|
| [`PATTERNS.md`](PATTERNS.md) | The 7 pattern categories consolidated — split by Opus (cross-sprint) vs Sonnet (within-sprint). Short, high-level. |
| [`ARCHITECT-V2-DESIGN.md`](ARCHITECT-V2-DESIGN.md) | All-front-loaded pattern: foundation + auto-discovery + FROZEN-files. Default for small-to-medium projects (≤7 entities, ≤4 sprints). |
| [`SUBSYSTEM-FRONT-LOADED.md`](SUBSYSTEM-FRONT-LOADED.md) | Sibling pattern for larger projects: each sprint front-loads its OWN subsystem's modules; auto-discovery for both routers AND models means later sprints don't modify any earlier-sprint file. Use when ≥8 entities or ≥5 sprints. The architect picks per-project; both patterns documented in the Opus prompt. |
| [`SCAFFOLDING-ARCHITECTURE.md`](SCAFFOLDING-ARCHITECTURE.md) | Why and how the architect's scaffolding pre-pass works — Haiku transcribes pinned-bytes files (configs, frozen utilities, conftest) once before per-sprint enrichment, freeing Sonnet to focus on behavior-bearing files. |
| [`SPEEDRUN-SPEC-FORMAT.md`](SPEEDRUN-SPEC-FORMAT.md) | Detailed section structure of a SPRINT-NNN.md spec. Full reference; the prompt patches summarize. |
| [`TWO-PASS-REVIEW.md`](TWO-PASS-REVIEW.md) | The architect's review process — Pass 1 produces; Pass 2 scrutinizes. The full Pass 2 checklist. |
| [`DEFECT-CLASSES.md`](DEFECT-CLASSES.md) | Empirical record of the 14 defect classes we hit. Appendix to `PATTERNS.md` — useful when debugging "have we seen this before?" |
| [`QWEN-HYPERPARAMETERS.md`](QWEN-HYPERPARAMETERS.md) | Qwen3.6:35b-a3b sampling settings. For the runner dip, not the architect. |
| [`STRUCTURAL-FIX-RESULTS.md`](STRUCTURAL-FIX-RESULTS.md) | Smoke-test progression v1→v4 (2026-04-30 → 2026-05-01) for the deterministic-dispatch rewrite. Final state: clean end-to-end run, Opus drives architect, TerminalTool primitive landed, dip cleaned up, spec format byte-for-byte matches NIFB exemplars. |
| [`RUNNER-INTEGRATION.md`](RUNNER-INTEGRATION.md) | Runner-side integration: section-name alignment between v4 architect output and the SR runner; 4-strategy SR-block matcher port from `../merge_sr.py` to the auditor; end-to-end Notebook run produces 34/34 passing tests for ~$2.30; defect-class observation (dependency errors vs logic errors) and proposed early-escalation heuristic. |
| [`GENERALIZABILITY-BACKLOG.md`](GENERALIZABILITY-BACKLOG.md) | Python-bias gaps — leaves to fix when the runner is exercised on Rust/Ruby/Java/.NET. Each gap is mechanical, not load-bearing. |
| [`synthetic_fixtures/`](synthetic_fixtures/) | 3-sprint Notebook API spec_analysis + sprint_plan used as the synthetic test fixture for end-to-end validation runs. Cheap to iterate on, exercises the front-loaded foundation pattern + auto-discovery. |
| [`exemplars/`](exemplars/) | Three known-good SPRINT-NNN.md files (sprints 001-003 from NIFB v7) plus the matching `notebook_spec_analysis.md` + `notebook_sprint_plan.md` inputs. What "right" looks like in practice. |

## Why these patterns aren't an exhaustive list

Frontier models (Opus + Sonnet) work better given a small set of well-described pattern categories with examples, plus the meta-pattern statement, than a long checklist. The 14 defect classes are 14 *instances* of ~7 *patterns*. New stacks will surface new instances; the patterns extrapolate.

The runtime prompts (in `spec_to_sprints.dip` for Opus, `write_enriched_sprint.go` for Sonnet) communicate "here's the kind of work you're doing, here's what failures look like, here's what success looks like" — not "follow these 14 rules to the letter."

## Validating the architect prompts

The natural test: regenerate a known project's sprint specs and verify the outputs match the speedrun format + pass through the qwen runner pipeline. Use the synthetic fixture for cheap iteration:

```fish
set WORKDIR ~/scratch/principles_validation
mkdir -p $WORKDIR/.ai
cp local_code_gen/principles/synthetic_fixtures/notebook_spec_analysis.md $WORKDIR/.ai/
cp local_code_gen/principles/synthetic_fixtures/notebook_sprint_plan.md  $WORKDIR/.ai/
cd $WORKDIR && git init -q

~/go/bin/tracker --no-tui --auto-approve -w . \
    $PIPELINES_REPO/local_code_gen/architect_only.dip
```

Validate the output:

- **`.ai/contract.md`** should contain: build-system block requirements, error/handler shape, async loading strategy, test infrastructure (StaticPool + closure pattern), Settings semantics, FROZEN files list, cross-sprint type/symbol map with `lazy="selectin"` annotations.
- **`.ai/sprints/SPRINT-001.md`** should be ~600-1000 lines (front-loaded foundation), contain a verbatim `app/main.py` with pkgutil auto-discovery, declare the project's entities with relationships, and have all 14 defect-class rules pre-applied.
- **`.ai/sprints/SPRINT-002.md`** should be ~150-300 lines (additive), contain `## Modified files: (none)`, declare 1 router + 1 test file per feature.

Compare to [`exemplars/SPRINT-001.md`](exemplars/SPRINT-001.md), [`exemplars/SPRINT-002.md`](exemplars/SPRINT-002.md), [`exemplars/SPRINT-003.md`](exemplars/SPRINT-003.md) for shape.

End-to-end: feed the generated specs into [`../sprint_runner_qwen.dip`](../sprint_runner_qwen.dip). If the architect prompts are correct, sprint 001 generates the foundation files and pytest passes 20+ tests on the first try (or with at most one LocalFix round).

### What "passing" looks like

The architect prompts are working when:

1. The generated `.ai/contract.md` contains all 7 pattern categories pinned explicitly.
2. Sprint 001 (front-loaded foundation) generates 20+ files via the runner with 20+ tests passing on the first generation pass — same result as our v7 manual hand-write produced.
3. Sprint 002 (additive) declares zero modifications, contains one router file per feature with the within-sprint patterns applied, and runs through the runner with at most one LocalFix round.

If any of these fail, the failure mode tells us which pattern wasn't sufficiently encoded — refine the relevant doc here, then sync the change into the live prompt per the [Maintenance workflow](#maintenance-workflow).
