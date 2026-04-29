# Findings — sprint enrichment + local-LLM execution (Apr 2026)

End-of-session retrospective on what we tested, what worked, and what's still unsolved. Pick up here next session.

## Pipeline structure (built and validated)

**Generation side (architect → Sonnet) — works well.**

- `spec_to_sprints.dip` patched: `write_sprint_docs` agent uses Opus as architect; iterates sprint-by-sprint calling `write_enriched_sprint` (per-file mode); tool reads `.ai/contract.md` from disk
- Tool `write_enriched_sprint` (in tracker repo): single-sprint per call, Sonnet as generator, system prompt embeds reference example + verbatim-content rule for non-code files
- Architect prompt enforces: cross-sprint type/symbol ownership map with exact field names; per-sprint New/Modified file split; verbatim infrastructure config (pyproject.toml, build-system, tsconfig, etc.)
- Cost ~$3.30 / 30 min for 16-sprint NIFB run
- Cross-sprint coherence: validated — exception hierarchy, import paths, type names all consistent across sprints

**Execution side (qwen runner) — partially works, not reliable end-to-end.**

- `sprint_runner_test.dip` patched: proj_root detection, `uv sync --all-extras`, `uv run pytest > file 2>&1; code=$?` (no PIPESTATUS), bumped timeouts (Generate 3600s, LocalFix 900s)
- `patch_file` upgraded with validation guards (line-count floor, pre-symbol preservation, syntax check), in-memory rollback on validation failure, retry-with-feedback up to 10 attempts, escalation to CloudFix on exhaustion
- Standalone test (`test_patch_flow.sh`) confirms validation + retry-with-feedback works in isolation when context is tight (~1KB)

## Sprint-design patterns explored

### V1: Incremental APPEND (current production shape)

Sprints 002+ patch sprint 001's `models.py`, `schemas.py`, `main.py`. Catastrophic failure: qwen wrote the file *path* as the file's full content during patch_file → wiped sprint 001's models. Even after validation guards prevented the silent overwrite, qwen retries on the same blind spot didn't recover; CloudFix could only partially reconstruct from a broken baseline.

Empirical result against runner_test (5 sprints): all marked completed, but actual pytest at end showed 22 failed / 48 errors / 19 passed. The runner's prior "tests-pass" detection bug (PIPESTATUS) masked failures.

### V2: Front-loaded foundation (this session's primary design proposal)

Sprint 001 carries the FULL data model, all Pydantic schemas, all test fixtures, all error codes, plus auth feature. Sprints 002+ are pure additive — only new router/service/test files. `main.py` uses `pkgutil.iter_modules` to auto-discover routers; never modified. Zero `## Modified files` entries across all 5 sprints.

**Designed**: 5 NIFB sprints in `architect_v2/.ai/sprints/` (~2350 lines total vs ~5K+ for v1).

**Empirical result against runner_test_v2**:
- Sprint 001: completed after 4 LocalFix + 5 CloudFix (~25 min, all green at end)
- Sprint 002: **failed — exhausted max_restarts (50)**. Hit ~30+ consecutive CloudFix calls that each completed but RunTests immediately failed again
- Total cost: ~$0.50 OpenAI for cloud fix loops (1M input / 129K output)

**What worked**: Sprint 001 produced cleanly via gen_file (no patches). Foundation files all written.

**What didn't work**: Sprint 002, despite being pure-additive (no patches needed), entered an endless CloudFix loop. Cloud kept "fixing" something that immediately broke under retest. Likely cause: subtle issue in sprint 001's foundation (untested by sprint 001's own test suite that passed) propagated to sprint 002's tests, and CloudFix kept oscillating around the wrong target without seeing the spec.

So front-loading **eliminated patch fragility** but exposed a different fragility: when CloudFix can't see the spec, it diagnoses-by-inference and gets stuck.

## Design principles identified

1. **Local model is a transcriber, not a designer.** Every file in `## New files` MUST have its complete literal content somewhere in the spec — either in `## Interface contract` + `## Algorithm notes` for code, or in `## File contents` (verbatim fenced block) for trivial/config files.

2. **Validation + rollback beats retry.** The runner's `patch_file` validation guards (line count, symbol preservation, syntax check) catch bad qwen output reliably. In-memory rollback to pre-edit state is the foundation; retry-with-feedback is bonus.

3. **Front-loading kills patch fragility but introduces foundation fragility.** Models/schemas/conventions defined once at sprint 001 cannot regress, but bugs in the foundation cascade silently to all later sprints. Sprint 001 needs *more* test coverage than we gave it (we wrote 21 tests; should be 50+ covering every model's CRUD and FK behavior).

4. **Cloud fix needs the spec, not just the failing test.** Today the CloudFix prompt sees: current (broken) file + test output + 3-step rule. It does NOT see the sprint spec or the pre-edit baseline. Result: cloud reconstructs by inference and oscillates. Critical fix: feed CloudFix the relevant sprint spec section + the pre-validation file (rolled-back via git or in-memory snapshot).

5. **The sprint runner is the hardest part of the system, not the generator.** Architect+Sonnet produces high-quality specs reliably. Qwen produces correct code most of the time when context is tight. The orchestration layer (when to retry, what to feed cloud, when to escalate, when to halt) is where complexity and fragility live.

## What's still unsolved

| Issue | Status |
|---|---|
| Endless CloudFix loops (sprint 002 in v2 run) | Not yet root-caused — need single-sprint diagnostic test |
| Per-file context slicing (qwen sees full sprint instead of file-relevant sections) | Designed in PROPOSED-CHANGES.md, not built |
| CloudFix lacks spec context | Identified; runner prompt needs upgrade to inject sprint spec + pre-edit baseline |
| Sprint 001's foundation tests insufficient coverage | Need richer model unit tests, FK constraint tests, schema round-trip tests |
| Cross-sprint test regression detection | Audit currently only counts files + tests; doesn't run prior-sprint test suite to confirm no regressions |
| Pipeline halt on real test failure | RunTests `$?` fix is in; needs verification it propagates through Audit correctly |

## Next test plan: single-sprint isolation

Goal: diagnose where the fragility lives by reducing to one sprint at a time and observing outputs closely.

### Phase 1: Foundation sprint alone
- Use `architect_v2`'s sprint 001 spec
- Run runner against ONLY sprint 001 (003-016 marked skipped, 002 marked skipped initially)
- Goal: get sprint 001's pytest 100% green with zero CloudFix calls
- If it doesn't pass with zero cloud fix:
  - Inspect qwen's output for each file vs the spec
  - Identify which guards (validation/syntax/symbol) catch the issue or fail to
  - Iterate on sprint 001 spec until qwen produces clean code first try

### Phase 2: Additive sprint on a known-good base
- Foundation from Phase 1 committed
- Run sprint 002 alone, foundation from disk
- Goal: 4-8 new files from gen_file, all tests green
- If CloudFix fires:
  - Read CloudFix's actual fixes — what's it changing?
  - Identify whether the issue is qwen, cloud, spec under-specification, or something else

### Phase 3: Two-sprint chain
- Once 001 and 002 individually clean
- Run them as a pair, verify Sprint 002's tests don't break Sprint 001's
- If breaks: pin the regression to a specific qwen output

### Phase 4: Per-file context slicing
- Implement awk-based extraction in runner (proposed in PROPOSED-CHANGES.md)
- Re-run Phase 1 with sliced context, observe whether qwen first-try success rate improves
- Hypothesis: smaller context → fewer hallucinations

### Phase 5: CloudFix prompt upgrade
- Inject sprint spec + pre-edit baseline into CloudFix prompt
- Re-run Phase 2
- Hypothesis: cloud's "diagnose by inference" failure goes away

## What we have on disk

- **Pipelines repo branch `feat/enriched-sprints-test`** at commit `a32f553` — production patch + test pipelines + this notes file
- **Tracker repo branch `feat/write-enriched-sprint-tool`** at commit `b2bca6b` — `write_enriched_sprint` tool + registration
- `experiments/enrich_sprints_test/architect_v1/` — incremental-APPEND specs (v1 design)
- `experiments/enrich_sprints_test/architect_v2/` — front-loaded specs (v2 design)
- `experiments/enrich_sprints_test/runner_test/` — v1 runner test workdir, sprints 001-005 marked completed (22 fail / 48 errors at end)
- `experiments/enrich_sprints_test/runner_test_v2/` — v2 runner test workdir, sprint 001 completed; sprint 002 exhausted max_restarts
- `experiments/enrich_sprints_test/test_patch_flow.sh` — standalone validation+retry test (passing)
- `experiments/enrich_sprints_test/PROPOSED-CHANGES.md` — per-file context slicing design
- `MIGRATION-enriched-sprints.md` — production migration doc

## Quick dollar/time tally

| Phase | Run | Cost | Time |
|---|---|---|---|
| Architect+Sonnet generation | 16 sprints | ~$3.30 | 30 min |
| Opus-only enrichment (comparison) | 16 sprints | ~$5.84 | 18 min |
| V1 runner — 5 sprints | 5/5 marked complete (broken) | ~$0.30 | 56 min |
| V2 runner — 5 sprints | 1/5 complete, halt at sprint 002 | ~$0.50 | 70 min |

Total session burn: ~$10. Cheap relative to a single human-day on this work.
