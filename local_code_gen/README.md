# Local Code Generation Pipeline

End-to-end pipeline for taking a product `spec.md` and producing a working codebase using a local LLM (qwen3.6:35b-a3b) for the bulk of generation, with cloud agents (Opus + Sonnet) for architectural design and surgical fix-up. Cloud handles the parts that benefit from frontier reasoning (cross-sprint architecture, audit, dependency resolution); local handles the parts that benefit from cheap throughput (per-file code generation, in-loop test/fix iteration).

> **Why this exists vs. the root [`spec_to_sprints.dip`](../spec_to_sprints.dip):** Harper's pipeline at the repo root is the generic spec-to-sprints workflow, designed for cloud-only code generation downstream. This variant is tuned for *local* code generation — sprint specs need to be more rigorous (the local model is a transcriber, not a designer), the file ownership model is different (front-loaded foundation + auto-discovery to avoid cross-sprint patches), and the runner has its own SR-block-based fix loop. The two pipelines share the upstream decomposition tournament; only the architect step + downstream runner differ.

## Quick start

### Prereqs (one-time)

```fish
# 1. Ollama running with qwen pulled
ollama serve &   # or run as a service
ollama pull qwen3.6:35b-a3b-q8_0

# 2. Tracker built (with the dispatch_sprints + dispatch_scaffolding tools)
cd /path/to/tracker
go install ./cmd/tracker
~/go/bin/tracker version   # confirm

# 3. API keys configured for tracker
#    - ANTHROPIC_API_KEY  — required for architect (Opus + Sonnet + Haiku)
#    - OPENAI_API_KEY     — required for CloudFix fallback (gpt-5.4)
#    - GEMINI_API_KEY     — only needed if you run the full spec_to_sprints
#                           pipeline (Path A below) which has Gemini in the
#                           decomposition tournament
~/go/bin/tracker setup

# 4. Env vars for the architect tools (set per shell session)
set -gx TRACKER_SPRINT_WRITER_MODEL claude-sonnet-4-6
set -gx TRACKER_SPRINT_WRITER_PROVIDER anthropic
set -gx TRACKER_SCAFFOLDING_WRITER_MODEL claude-haiku-4-5
set -gx TRACKER_SCAFFOLDING_WRITER_PROVIDER anthropic
set -gx PIPELINES_REPO /path/to/pipelines   # used by sprint_runner_qwen.dip
                                              # to locate lib/merge_sr.py
```

### Three entry-point patterns

There are three ways to drive the pipeline depending on what you already have on disk and which cloud creds are available.

#### Path A — From `spec.md` cold (full pipeline, all creds required)

Use when you have only a prose spec and want the whole flow: decomposition tournament + critique + merge + architect + scaffolding pre-pass + sprint enrichment + per-sprint code gen.

```fish
mkdir -p $WORKDIR/.ai/sprints
echo "<your product spec>" > $WORKDIR/spec.md
cd $WORKDIR

# Step 1: spec.md → .ai/contract.md + sprint specs + scaffolding files
#   Models: Claude/GPT/Gemini decomposition tournament,
#           Opus architect, Sonnet enrichment, Haiku scaffolding
#   Cloud cost: ~$5-10 for a 16-sprint project; ~30-50 min
~/go/bin/tracker --no-tui --auto-approve -w . \
    $PIPELINES_REPO/local_code_gen/spec_to_sprints.dip

# Step 2: sprint specs → working code (looped through ledger)
#   Models: qwen3.6:35b (local), gpt-5.4 (CloudFix fallback only)
#   Cost: $0 for local-only path, ~$0.20-1.00 if CloudFix fires; 15-60 min
~/go/bin/tracker --no-tui --auto-approve -w . \
    $PIPELINES_REPO/local_code_gen/sprint_runner_qwen.dip
```

Requires Anthropic + OpenAI + Gemini creds.

#### Path B — Architect-only + runner (most common; needs Anthropic + OpenAI)

Use when the architect's inputs are already on disk and you just need the architect → scaffolding → sprint enrichment → code gen path. Skips the 3-model decomposition tournament entirely.

`architect_only.dip` consumes two files and produces everything downstream:

| Input file | What it is | Where it normally comes from |
|---|---|---|
| `.ai/spec_analysis.md` | Project summary, functional requirements (FRs), components, entities, route table — the architect's read of the prose `spec.md` | The `analyze_spec` agent in `spec_to_sprints.dip` (line ~62). It's the *first* output of the upstream pipeline. |
| `.ai/sprint_plan.md` | Sprint-level decomposition — how the FRs split across sprints, FR coverage matrix, per-sprint scope summaries, file ownership across sprints | The `merge_decomposition` agent in `spec_to_sprints.dip` (line ~432). It's the *final* output of the decomposition tournament + critique + merge phase, and the *last* thing produced before the architect step. |

Both files are produced by `spec_to_sprints.dip` *before* the architect's `write_sprint_docs` step. `architect_only.dip` is exactly that architect step in isolation — same prompt, same outputs, just without the upstream tournament.

**Three ways to obtain the inputs:**

1. **Run `spec_to_sprints.dip` and stop after `merge_decomposition`.** The simplest if you have the cloud creds for the tournament (Anthropic + OpenAI + Gemini). Run normally; once `.ai/sprint_plan.md` exists, hit Ctrl-C, then re-run with `architect_only.dip` to do the architect+scaffolding+sprints flow. Useful when you want to inspect or hand-tune the decomposition before the architect commits.
2. **Hand-write them.** See the committed exemplars in [`principles/exemplars/notebook_spec_analysis.md`](principles/exemplars/notebook_spec_analysis.md) and [`principles/exemplars/notebook_sprint_plan.md`](principles/exemplars/notebook_sprint_plan.md) for the shape — these are the actual files that produced the v11 validated run. Copy the structure (Project Summary, FR table, Components, Entities, Routes for analysis; Summary, FR Coverage Matrix, per-sprint scope+files for plan) and fill in your project's specifics.
3. **Copy from a similar prior project.** If you've run the pipeline on a similar service before, just copy that project's `.ai/spec_analysis.md` + `.ai/sprint_plan.md` into the new workdir and edit. The shape doesn't change project-to-project; only the FRs/entities/routes do.

```fish
# Place the inputs in $WORKDIR/.ai/
mkdir -p $WORKDIR/.ai
cp <your spec_analysis.md> $WORKDIR/.ai/spec_analysis.md
cp <your sprint_plan.md>   $WORKDIR/.ai/sprint_plan.md
cd $WORKDIR

# Step 1: architect → contract + sprint specs + scaffolding pre-pass
#   Models: Opus 4.6 (architect) + Sonnet 4.6 (sprint enrichment) + Haiku 4.5 (scaffolding)
#   Cost: ~$0.40 for a 3-sprint project; ~5-50 min depending on project size
~/go/bin/tracker --no-tui --auto-approve -w . \
    $PIPELINES_REPO/local_code_gen/architect_only.dip

# After step 1, .ai/ contains: contract.md, sprint_descriptions.jsonl,
# scaffolding_plan.jsonl, scaffolding_manifest.txt, sprints/SPRINT-NNN.md,
# ledger.tsv, plus the scaffolding files written to disk under the project root.

# Step 2: code gen (loops the ledger)
#   Same as Path A Step 2
~/go/bin/tracker --no-tui --auto-approve -w . \
    $PIPELINES_REPO/local_code_gen/sprint_runner_qwen.dip
```

Total per-project: ~$0.50-$1.00 for a 3-sprint project, ~20-25 min wall.

#### Path C — Single-sprint execution (debug / iterate)

Use when you want to execute exactly one sprint at a time — for debugging a specific sprint, A/B testing prompt changes, or piping into a CI job that runs one sprint per invocation. Requires the architect step (Path A or B) to have already produced `.ai/sprints/SPRINT-NNN.md` and `.ai/contract.md`.

```fish
# After running architect (Path B step 1), before / instead of running runner:
echo "001" > .ai/current_sprint_id.txt   # caller's responsibility

~/go/bin/tracker --no-tui --auto-approve -w . \
    $PIPELINES_REPO/local_code_gen/sprint_exec_qwen.dip

# When done, advance the ledger and commit manually:
git add -A && git commit -m "feat(sprint-001): <title>"
# update .ai/ledger.tsv to mark sprint 001 'completed' if you want to track
```

Same shared core (Setup/Generate/RunTests/LocalFix/CloudFix/Audit) as the runner — same SR + manifest gate + single-session CloudFix improvements. Just no ledger loop, no auto-commit, no sprint_gate.

### Which path do I want?

| You have | You want | Use |
|---|---|---|
| Just a `spec.md` and full cloud creds (Anthropic + OpenAI + Gemini) | One-shot from spec to working code | Path A: `spec_to_sprints.dip` → `sprint_runner_qwen.dip` |
| `.ai/spec_analysis.md` + `.ai/sprint_plan.md` already on disk (or you'll hand-write them); only Anthropic + OpenAI creds | Skip the upstream tournament; go straight to architect → code | Path B: `architect_only.dip` → `sprint_runner_qwen.dip` |
| Architect already done; want to run sprints one at a time (debugging, A/B testing, CI) | Execute exactly one sprint per invocation | Path C: `sprint_exec_qwen.dip` |
| Want to A/B-test the LocalFix prompt or rollback layers without spending sprint-runner cost | Bench harness against deterministic pre-broken fixtures | `../bench_local_fix_sr.dip` |

The most common colleague-facing path is **B** — pre-build the decomposition inputs (or copy them from a similar prior project) and run `architect_only.dip → sprint_runner_qwen.dip`. Only ~$0.50-$1.00 per project, ~20-25 min wall, doesn't need the Gemini cred that Path A's tournament step requires.

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
│  write_sprint_docs (Opus, 5-step deterministic flow)                │
│    1. write .ai/contract.md            (cross-sprint architectural  │
│                                          map; pinned ONCE)          │
│    2. write .ai/sprint_descriptions.jsonl  (one record per sprint)  │
│    3. write .ai/scaffolding_plan.jsonl  (which files Haiku pre-writes) │
│    4. call dispatch_scaffolding once    (Haiku transcribes pinned-  │
│                                          bytes files; emits manifest) │
│    5. call dispatch_sprints once        (terminal — agent ends on   │
│                                          success)                   │
│                                                                     │
│  dispatch_scaffolding (deterministic loop, in tracker)              │
│    For each scaffolding_plan.jsonl line:                            │
│      Haiku transcription pass — one fenced block from contract → file│
│      required_lines pre-write validation                            │
│    emits: .ai/scaffolding_manifest.txt (one path per line)          │
│                                                                     │
│  dispatch_sprints (deterministic loop, in tracker)                  │
│    For each sprint_descriptions.jsonl line:                         │
│      Sonnet author pass — produces draft SPRINT-NNN.md              │
│        (sees the manifest; marks pinned files as "already on disk") │
│      Sonnet audit pass  — emits SR/REPLACE patches if needed        │
│      4-strategy SR matcher applies patches (exact/indent/ws/fuzzy)  │
│      Partial-apply: ships whatever blocks succeeded                  │
│                                                                     │
│   produces:  .ai/sprints/SPRINT-NNN.md (one per sprint)             │
│              .ai/contract.md (kept on disk for the runner to read)  │
│              .ai/scaffolding_manifest.txt (architect-pinned files)  │
│              backend/<scaffolding files> already on disk            │
│              .ai/ledger.tsv  (NNN  title  status  ...)              │
│                                                                     │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
                                  │ bridge: workdir/.ai/sprints/
                                  ▼
┌─────────────────────── RUNNER SIDE (local + cloud-handoff) ────────┐
│                                                                     │
│  sprint_runner_qwen.dip (looped) | sprint_exec_qwen.dip (one shot)  │
│    Setup:              detect proj_root, install deps, stage merge_sr.py│
│    Generate (qwen):    parse `## New files`, gen_file each         │
│      ↳ syntax check + retry per file                                │
│    RunTests:           uv run pytest / go test / npm test          │
│    LocalFix (qwen):    SR-block surgical edits, max 8 rounds       │
│      ↳ Layer-1: per-round set-based regression rollback             │
│      ↳ Layer-2: pre-local snapshot for cloud handoff                │
│      ↳ manifest gate: post-merge violation check refuses scaffolding edits│
│    CloudFix (gpt-5.4): single-session iterative — runs pytest itself, │
│                         iterates until green or max_turns; once only │
│    Audit:              artifact + test-count gates                  │
│    Commit:             git commit per sprint (runner only)         │
│                                                                     │
│   produces: backend/<all the files>, all tests passing              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

The split is intentional: **frontier models design the architecture**, **the local model writes the code under tight constraints**, **frontier handles failure modes the local model can't fix** (e.g., dependency resolution, version pinning, infrastructure decisions).

## File index

| File | Role | Models | Edit strategy |
|---|---|---|---|
| [`spec_to_sprints.dip`](spec_to_sprints.dip) | **Path A** — Full pipeline: spec discovery → 3-model decomposition tournament → 6-way critique → merge → architect (5-step) → dispatch_scaffolding → dispatch_sprints → ledger → validate. Use for cold runs from a `spec.md`. Requires Anthropic + OpenAI + Gemini creds. | Claude/GPT/Gemini (decomp) + Opus 4.6 (architect) + Sonnet 4.6 (enrichment) + Haiku 4.5 (scaffolding) | n/a |
| [`architect_only.dip`](architect_only.dip) | **Path B step 1** — Architect step in isolation: skips the decomposition tournament. Reads pre-built `.ai/spec_analysis.md` + `.ai/sprint_plan.md` and produces `.ai/contract.md` + sprint specs + `.ai/scaffolding_manifest.txt`. The fastest path when you can hand-build the decomposition inputs. | Opus 4.6 + Sonnet 4.6 + Haiku 4.5 | n/a |
| [`sprint_runner_qwen.dip`](sprint_runner_qwen.dip) | **Path B step 2 / Path A step 2** — Code-gen runner: loops the ledger, executes Setup → Generate → RunTests → SR LocalFix (with rollback + manifest gate) → single-session CloudFix → Audit → Commit per sprint. | qwen3.6:35b-a3b-q8_0 (Generate + LocalFix) + gpt-5.4 (CloudFix fallback) | SEARCH/REPLACE blocks via `../lib/merge_sr.py`, 4-strategy fuzzy merge, set-based per-round rollback, pre-cloud snapshot, manifest-aware refusal of scaffolding paths |
| [`sprint_exec_qwen.dip`](sprint_exec_qwen.dip) | **Path C** — Single-sprint executor: same shared Setup/Generate/RunTests/LocalFix/CloudFix/Audit core as the runner but no ledger loop, no auto-commit, no sprint_gate. Caller writes `.ai/current_sprint_id.txt` first. | Same as runner | Same as runner |
| [`smoke_scaffolding/`](smoke_scaffolding/) | Tiny smoke test for `dispatch_scaffolding` (Haiku per-file scaffolding writer). | Haiku 4.5 | n/a |
| [`principles/`](principles/) | Architecture documentation, pattern references, exemplars, structural-fix journey docs. The `principles/README.md` is the index. None of these are loaded at runtime — they're human maintenance material. | — | — |
| `../lib/merge_sr.py` | Aider-style SEARCH/REPLACE block merger with 4 fallback strategies (exact / indent-preserving / whitespace-insensitive / fuzzy). Used by `sprint_runner_qwen.dip` and `sprint_exec_qwen.dip`'s LocalFix step. Same matching strategies mirrored in tracker's `applySRBlocks` (Go) for the architect-side audit pass. | — | — |
| `../bench_local_fix_sr.dip` | Bench harness — exercises the SR LocalFix tool body in isolation against deterministic pre-broken fixtures from `DS-scratch/local_llm_patch_bench/`. No Generate, no ledger, no Audit. The bench's purpose is to A/B prompt designs and validate rollback layers without spending the cost of a full sprint run. | qwen3.6:35b-a3b-q8_0 only | Same as `sprint_runner_qwen.dip` |

## Configuration

### Required env vars

| Variable | What it does | Used by |
|---|---|---|
| `ANTHROPIC_API_KEY` | Architect (Opus) + per-sprint writer/audit (Sonnet) + scaffolding transcription (Haiku) | `spec_to_sprints.dip`, `architect_only.dip` |
| `OPENAI_API_KEY` | CloudFix (gpt-5.4) when LocalFix exhausts | `sprint_runner_qwen.dip`, `sprint_exec_qwen.dip` |
| `GEMINI_API_KEY` | Gemini decomposition agent in the upstream tournament | `spec_to_sprints.dip` (Path A only — not needed for Path B/C) |
| `TRACKER_SPRINT_WRITER_MODEL` | Model for per-sprint writer. Required for `dispatch_sprints` and `dispatch_scaffolding` tools to register. Recommended: `claude-sonnet-4-6` | architect-side dips |
| `TRACKER_SPRINT_WRITER_PROVIDER` | Provider for the writer model. Recommended: `anthropic` | architect-side dips |
| `TRACKER_SCAFFOLDING_WRITER_MODEL` | Model for per-file Haiku scaffolding worker. Defaults to writer model if unset, but Haiku is ~3-4× cheaper. Recommended: `claude-haiku-4-5` | architect-side dips (`dispatch_scaffolding` step) |
| `TRACKER_SCAFFOLDING_WRITER_PROVIDER` | Provider for scaffolding model. Recommended: `anthropic` | architect-side dips |
| `PIPELINES_REPO` | Path to this pipelines repo. Runner/exec use it to locate `lib/merge_sr.py`. (Setup also tries common default paths so this is technically optional but explicit is clearer.) | runner/exec dips |

### Optional env vars

| Variable | Default | Notes |
|---|---|---|
| `TRACKER_CODEGEN_MODEL` | unset | If set, registers a `generate_code` cheap-model tool — separate from the runner pipeline; not used by these dips |

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

### Sprint 001 takes forever in the runner (8 LocalFix rounds + escalates to CloudFix)
Likely an architectural-mismatch case — qwen genuinely can't fix it. Common cause: a dependency is broken in the runtime (e.g. `passlib + bcrypt` on Python 3.14), and the fix requires either changing the hashing scheme (architect-level decision) or pinning specific versions in `pyproject.toml` (manifest-frozen, qwen blocked). LocalFix burns its 8-round budget patching code endlessly; CloudFix takes over and converges in one session. This is the *correct* escalation path — local should not be trusted to make architectural choices. Wall-time penalty is ~12 min. Future improvement: fixed-point detection (escalate when 2+ rounds produce identical SR output).

### "MANIFEST VIOLATION" lines in LocalFix log
qwen tried to write to a scaffolding file. The manifest gate caught it, restored from snapshot_round_pre, counted it as a consecutive_rollback. After 3 consecutive rollbacks (default) the runner escalates to CloudFix. This is healthy — manifest-frozen files should not be edited by local. If you see this on every round, the architect's contract may be over-pinning files that need sprint-level changes; revisit the scaffolding_plan.jsonl decisions in `architect_only.dip`.

### "REGRESSION: N previously-passing tests now fail" then rollback
Layer-1 rollback fired. qwen's SR block introduced a regression. Round is rolled back to pre-round state; consecutive_rollbacks increments. This is healthy — the alternative is the v9 sprint 3 silent-broken-commit failure mode. After 3 consecutive rollbacks the runner escalates.

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

| Project | Date | Pipeline shape | Sprints | Cost | Time | Outcome |
|---|---|---|---|---|---|---|
| Notebook (synthetic) | 2026-05-01 | spec_to_sprints + earlier full-rewrite runner | 3 | ~$2.30 | 17 min | 34/34 pytest passing end-to-end |
| NIFB (architect-only) | 2026-05-01 | architect_only (16 sprints generated, runner not exercised) | 16 | ~$5 | 47 min | All 16 sprints generated; Pattern B chosen autonomously; validate_output green |
| Notebook v6 (synthetic) | 2026-05-06 | architect_only | 3 | $0.39 | 8m39s | 11-file scaffolding manifest, 3 sprint specs, valid contract |
| Notebook v8 (synthetic) | 2026-05-06 | sprint_runner (medium reasoning, full-rewrite LocalFix, single-session CloudFix) | 3 | $0.54 | 18m | 42/42 passing, drift-clean |
| Notebook v10 (synthetic) | 2026-05-06 | sprint_runner (low reasoning, full-rewrite LocalFix, truncation fix) | 3 | $0.36 | 19m | 42/42 passing, drift-clean |
| Notebook v11 (synthetic) | 2026-05-06 | sprint_runner_qwen (SR LocalFix + manifest gate + Layer-1+2 rollback) | 3 | $0.45 | 16m29s | 42/42 passing, drift-clean. Sprint 2 converged locally with one SR round (no CloudFix); sprint 1's bcrypt issue routed through CloudFix cleanly. |

The v11 run is the canonical baseline for the current toolchain (post the SR + manifest-gate + single-session CloudFix consolidation). See [`principles/STRUCTURAL-FIX-RESULTS.md`](principles/STRUCTURAL-FIX-RESULTS.md) and [`principles/RUNNER-INTEGRATION.md`](principles/RUNNER-INTEGRATION.md) for older run telemetry, defect-class observations, and cost breakdowns.

## See also

- [`principles/README.md`](principles/README.md) — index of all design docs and patterns
- [`principles/SPEEDRUN-SPEC-FORMAT.md`](principles/SPEEDRUN-SPEC-FORMAT.md) — what a "good" sprint spec looks like for local-LLM consumption
- [`principles/exemplars/`](principles/exemplars/) — reference shapes for the architect's inputs (`notebook_spec_analysis.md`, `notebook_sprint_plan.md`) and outputs (three validated `SPRINT-NNN.md` specs from a successful NIFB v7 run, 61 cumulative tests passing)
- [`../spec_to_sprints.dip`](../spec_to_sprints.dip) — Harper's original cloud-only pipeline (the source we forked from)
