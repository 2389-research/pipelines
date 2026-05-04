# Local Code Generation Pipeline

End-to-end pipeline for taking a product `spec.md` and producing a working codebase using a local LLM (qwen3.6:35b-a3b) for the bulk of generation, with cloud agents (Opus + Sonnet) for architectural design and surgical fix-up. Cloud handles the parts that benefit from frontier reasoning (cross-sprint architecture, audit, dependency resolution); local handles the parts that benefit from cheap throughput (per-file code generation, in-loop test/fix iteration).

> **Why this exists vs. the root [`spec_to_sprints.dip`](../spec_to_sprints.dip):** Harper's pipeline at the repo root is the generic spec-to-sprints workflow, designed for cloud-only code generation downstream. This variant is tuned for *local* code generation — sprint specs need to be more rigorous (the local model is a transcriber, not a designer), the file ownership model is different (front-loaded foundation + auto-discovery to avoid cross-sprint patches), and the runner has its own SR-block-based fix loop. The two pipelines share the upstream decomposition tournament; only the architect step + downstream runner differ.

## Quick start

### Prereqs (one-time)

```fish
# 1. Ollama running with qwen pulled
ollama serve &   # or run as a service
ollama pull qwen3.6:35b-a3b-q8_0

# 2. Tracker built (this repo's tracker, with our extensions)
cd /path/to/tracker
go install ./cmd/tracker
~/go/bin/tracker version   # confirm

# 3. API keys configured for tracker (Anthropic for architect/audit, OpenAI for CloudFix)
~/go/bin/tracker setup
```

### From `spec.md` to working code (full pipeline, ~2-4 hrs)

```fish
# Workdir layout
mkdir -p $WORKDIR/.ai/sprints
echo "<your product spec>" > $WORKDIR/spec.md
cd $WORKDIR

# Architect-side env
set -gx TRACKER_SPRINT_WRITER_MODEL claude-sonnet-4-6
set -gx PIPELINES_REPO /path/to/pipelines

# Step 1: Decompose spec into sprints (Harper's tournament + our architect)
#   Cloud cost: ~$5-10 for a 16-sprint project; ~30-50 min
~/go/bin/tracker --no-tui --autopilot lax $PIPELINES_REPO/local_code_gen/spec_to_sprints.dip

# Step 2: Generate code (qwen + LocalFix + CloudFix on test failures)
#   Cost: $0 for local-only path, ~$5-30 if CloudFix kicks in; 1-3 hrs
~/go/bin/tracker --no-tui --autopilot lax $PIPELINES_REPO/local_code_gen/sprint_runner.dip
```

### Iterating on the architect prompt (architect-only, fast)

If you already have `.ai/spec_analysis.md` + `.ai/sprint_plan.md` (output of decomposition) and want to re-run only the architect step:

```fish
~/go/bin/tracker --no-tui --autopilot lax $PIPELINES_REPO/local_code_gen/architect_only.dip
```

This skips the 3-model decomposition tournament + 6-way critique tournament + merge (~10 min, ~$3 of cloud) and just re-runs the architect step (~5-50 min depending on project size, ~$1-5).

Useful when iterating on the Opus prompt body in `architect_only.dip` or when validating that a prompt change behaves on a fixed input.

## Architecture

```
┌────────────────────── ARCHITECT SIDE (cloud) ──────────────────────┐
│                                                                     │
│  spec.md → analyze_spec → 3-model decomposition tournament →       │
│   (Harper's)              critique tournament → merge_decomposition │
│                                                                     │
│   produces:  .ai/spec_analysis.md  +  .ai/sprint_plan.md            │
│                                                                     │
│   ▼                                                                 │
│                                                                     │
│  write_sprint_docs (Opus)                                           │
│    1. write .ai/contract.md            (cross-sprint architectural  │
│                                          map; pinned ONCE)          │
│    2. write .ai/sprint_descriptions.jsonl  (one record per sprint)  │
│    3. call dispatch_sprints once        (terminal tool — agent ends │
│                                          on success)                │
│                                                                     │
│  dispatch_sprints (deterministic loop, in tracker)                  │
│    For each JSONL line:                                             │
│      Sonnet author pass — produces draft SPRINT-NNN.md              │
│      Sonnet audit pass  — emits SR/REPLACE patches if needed        │
│      4-strategy SR matcher applies patches (exact/indent/ws/fuzzy)  │
│      Partial-apply: ships whatever blocks succeeded                  │
│                                                                     │
│   produces:  .ai/sprints/SPRINT-NNN.md (one per sprint)             │
│              .ai/contract.md (kept on disk for the runner to read)  │
│              .ai/ledger.tsv  (NNN  title  status  ...)              │
│                                                                     │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
                                  │ bridge: workdir/.ai/sprints/
                                  ▼
┌─────────────────────── RUNNER SIDE (local + cloud-handoff) ────────┐
│                                                                     │
│  For each sprint in ledger:                                         │
│    Generate (qwen):    parse `## New files`, gen_file each         │
│      ↳ syntax check + retry per file                                │
│    RunTests:           uv run pytest / go test / npm test          │
│    LocalFix (qwen):    SR-block surgical edits on failing tests    │
│      ↳ retry up to 10 LocalFix rounds                               │
│    CloudFix (gpt-5.4): cloud agent if local exhausts                │
│    Audit:              artifact + test-count gates                  │
│    Commit:             git commit per sprint                        │
│                                                                     │
│   produces: backend/<all the files>, all tests passing              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

The split is intentional: **frontier models design the architecture**, **the local model writes the code under tight constraints**, **frontier handles failure modes the local model can't fix** (e.g., dependency resolution, version pinning, infrastructure decisions).

## File index

| File | Role |
|---|---|
| [`spec_to_sprints.dip`](spec_to_sprints.dip) | Full pipeline: spec discovery → decomposition tournament → critique → merge → architect → dispatch_sprints → ledger → validate. 28 nodes / ~860 lines. Use this for cold runs from a `spec.md`. |
| [`architect_only.dip`](architect_only.dip) | Architect step in isolation: skips the decomposition tournament. Reads pre-existing `.ai/spec_analysis.md` + `.ai/sprint_plan.md` and produces sprint specs. 6 nodes / ~270 lines. Use this for fast iteration on the architect prompt. |
| [`sprint_runner.dip`](sprint_runner.dip) | Code-generation runner: qwen Generate → RunTests → SR-block LocalFix → cloud CloudFix → Audit → Commit. Loops over each sprint in the ledger. 17 nodes / ~750 lines. |
| [`principles/`](principles/) | Architecture documentation, pattern references, exemplars, structural-fix journey docs. The `principles/README.md` is the index. None of these are loaded at runtime — they're human maintenance material. |
| `../lib/merge_sr.py` | Aider-style SEARCH/REPLACE block merger with 4 fallback strategies (exact / indent-preserving / whitespace-insensitive / fuzzy). Used by `sprint_runner.dip`'s LocalFix step. The same matching strategies are mirrored in tracker's `applySRBlocks` (Go) for the architect-side audit pass. |

## Configuration

### Required env vars

| Variable | What it does | Where set |
|---|---|---|
| `ANTHROPIC_API_KEY` | Architect (Opus) + writer/audit (Sonnet) calls | `tracker setup` or shell univar |
| `OPENAI_API_KEY` | CloudFix (gpt-5.4) when LocalFix exhausts | same |
| `TRACKER_SPRINT_WRITER_MODEL` | Model for the per-sprint writer (default `claude-sonnet-4-6`). Required for `dispatch_sprints` to register. | `set -gx` before the run |
| `PIPELINES_REPO` | Path to this pipelines repo. `sprint_runner.dip` uses it to locate `lib/merge_sr.py`. | `set -gx` before the runner run |

### Optional env vars

| Variable | Default | Notes |
|---|---|---|
| `TRACKER_SPRINT_WRITER_PROVIDER` | `anthropic` | Override only for testing alternate providers |
| `TRACKER_CODEGEN_MODEL` | unset | If set, registers a `generate_code` cheap-model tool — separate from the runner pipeline; not used by this pipeline |

### Architectural pattern (chosen by Opus per project)

The architect picks between two architectures based on project size. Both produce sprints the runner can consume:

- **Pattern A — All-front-loaded** (default for ≤7 entities, ≤4 sprints): sprint 001 declares ALL ORM models, schemas, fixtures; sprints 002+ are purely additive routers.
- **Pattern B — Subsystem-front-loaded** (default for ≥8 entities, ≥5 sprints): each sprint front-loads its own subsystem (its own models module, schemas module, router module); auto-discovery for both routers AND models means later sprints don't modify any earlier-sprint file.

The chosen pattern is declared in `.ai/contract.md`'s opening "Architectural Pattern" section with rationale. See [`principles/ARCHITECT-V2-DESIGN.md`](principles/ARCHITECT-V2-DESIGN.md) (Pattern A) and [`principles/SUBSYSTEM-FRONT-LOADED.md`](principles/SUBSYSTEM-FRONT-LOADED.md) (Pattern B).

## Troubleshooting

### `dispatch_sprints` fails with "no entries in ..."
Architect didn't write `.ai/sprint_descriptions.jsonl`. Check the run log for the JSONL write step. If Opus gave up early or hit a parse error in its output, re-run the architect (`architect_only.dip`).

### `audit=PASS-FALLBACK-NOMATCH` on multiple sprints
Sonnet auditor emitted SR blocks whose SEARCH text the 4-strategy matcher couldn't locate. With partial-apply (May 1 fix), this only fires when ZERO blocks could be applied — usually means the auditor is patching against text that was modified by an earlier block in the same set, OR the search context is genuinely missing. Look at `.ai/last_qwen_response.txt` (during runner) or stderr lines in the run log to see specific block-match failures. Fallback ships the unaudited draft, which is still valid; just missing audit improvements.

### Sprint 001 takes forever in the runner (10+ LocalFix rounds)
Likely a dependency-resolution issue, not a code logic issue. Look at `last_test_output.txt` for `ImportError`, `ModuleNotFoundError`, or "requires the X package" — the local model can't add deps to `pyproject.toml`, so it patches code endlessly. CloudFix usually fixes this in one shot (it sees the full project + tests + spec and identifies the missing dep). Workaround for now: let CloudFix run after the LocalFix budget exhausts. Future improvement (not yet built): early-escalation regex on `last_test_output.txt` that routes dep errors directly to CloudFix.

### Sprint 001 file truncated mid-section (missing `## DoD` / `## Validation`)
Sonnet hit MaxTokens on the author pass. Was a real failure mode in NIFB v1; fixed May 1 by setting MaxTokens=16384 explicitly + adding Pattern B which keeps each sprint smaller. If you're seeing this on an existing run, you can:
1. Re-run the architect (`architect_only.dip`) — Opus's output is usually similar but with different sampling, may not truncate this time
2. Force Pattern B by editing the sprint plan to be more clearly subsystem-decomposed
3. Manually patch the truncated sprint with placeholder DoD + Validation sections to unblock

### Pipeline hangs at `validate_output`
Restart loop ran out of attempts. Inspect `.ai/sprints/` for which sprint failed validation — usually it's missing a section (`## Scope`, `## Non-goals`, `## DoD`, `## Validation`). Manually patch the missing section, or re-run the architect for that sprint.

### Runner generates code but tests fail with mysterious imports
Often the Sonnet writer's per-file `Imports` block didn't include something the algorithm references. Look at the sprint spec's `## New files` section for that file — every symbol the algorithm uses MUST be in the imports list. If a symbol is missing, that's a writer-prompt issue worth filing. For the immediate run, manual patching the affected `.py` file and re-running tests works.

## How to contribute / extend

If you find a new defect class while running the pipeline:
1. Capture the symptom + minimal repro in [`principles/DEFECT-CLASSES.md`](principles/DEFECT-CLASSES.md).
2. Decide: cross-sprint (architect's contract.md should pin) or within-sprint (writer's per-sprint spec should pin)?
3. Fold into [`principles/PATTERNS.md`](principles/PATTERNS.md) under the appropriate Opus or Sonnet pattern category.
4. Update the prompt in `architect_only.dip` (Opus) or `tracker/agent/tools/write_enriched_sprint.go` (Sonnet writer system prompt).
5. Re-run on the [synthetic Notebook fixture](principles/synthetic_fixtures/) to validate.
6. Document the change in a follow-up to [`principles/STRUCTURAL-FIX-RESULTS.md`](principles/STRUCTURAL-FIX-RESULTS.md).

## Validated runs

| Project | Date | Sprints | Cost | Time | Outcome |
|---|---|---|---|---|---|
| Notebook (synthetic) | 2026-05-01 | 3 | ~$2.30 | 17 min | 34/34 pytest passing end-to-end |
| NIFB (architect-only) | 2026-05-01 | 16 | ~$5 | 47 min | All 16 sprints generated; Pattern B chosen autonomously; validate_output green |

See [`principles/STRUCTURAL-FIX-RESULTS.md`](principles/STRUCTURAL-FIX-RESULTS.md) and [`principles/RUNNER-INTEGRATION.md`](principles/RUNNER-INTEGRATION.md) for the full run telemetry, defect-class observations, and cost breakdowns.

## See also

- [`principles/README.md`](principles/README.md) — index of all design docs and patterns
- [`principles/SPEEDRUN-SPEC-FORMAT.md`](principles/SPEEDRUN-SPEC-FORMAT.md) — what a "good" sprint spec looks like for local-LLM consumption
- [`principles/exemplars/`](principles/exemplars/) — three validated sprint specs from a successful NIFB v7 run (61 cumulative tests passing)
- [`../spec_to_sprints.dip`](../spec_to_sprints.dip) — Harper's original cloud-only pipeline (the source we forked from)
