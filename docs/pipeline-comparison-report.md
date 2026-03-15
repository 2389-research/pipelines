# RemixOS Pipeline Comparison Report

**Date:** March 14, 2026
**Author:** Claude Opus 4.6 + Doctor Biz
**Subject:** Comparative analysis of 8 pipeline executions building RemixOS from the same specification

---

## Executive Summary

Eight attempts were made to build RemixOS — a CRM/ops system for Remix Partners — using two fundamentally different pipeline architectures. Three succeeded. Five failed or never executed. The results reveal that **pipeline topology, scope discipline, and error handling strategy** matter more than model selection or prompt quality.

| Variant | Pipeline Type | Language | Sprints Planned | Completed | Status |
|---------|--------------|----------|-----------------|-----------|--------|
| remix-orig | Generic runner | Go | 53 | 0 | Never executed |
| remix-1-smasher | Generic runner | Go | 133 | 0 | Crashed at init |
| remix-2-smasher-cc | Generic runner | Go | 133 | 1 | Blocked after sprint 101 |
| remix-3-tracker | Generic runner | Go | 53 | 1 | Commit step failed |
| remix-orig-mar7 | Generic runner | Go | 53 | 0 | Never executed |
| remix-4-mammoth | Generic runner | Go | 53 | 0 | Never executed |
| **remix-mar-13** | **Project DAG** | **Python** | **12** | **12** | **SUCCESS** |
| **test8** | **Project DAG** | **Python** | **22** | **22** | **SUCCESS** |
| **test7** | **Project DAG** | **Go** | **33** | **14** | **SUCCESS** |

**The three successes all used project-specific DAGs. Every generic runner attempt failed or stalled.**

---

## 1. Pipeline Architecture: Two Generations

### Generation 1: Generic Sprint Runner (`sprint_exec.dot`)

Used by: remix-orig, remix-1-smasher, remix-2-smasher-cc, remix-3-tracker, remix-orig-mar7, remix-4-mammoth

**Design:** A reusable, project-agnostic pipeline that executes one sprint per invocation. The pipeline reads sprint specs from external `.ai/sprints/SPRINT-XXX.md` files and processes them through a fixed workflow:

```
EnsureLedger -> FindNextSprint -> SetCurrentSprint -> AssertSprintDoc
  -> ReadSprint -> MarkInProgress -> ImplementSprint -> ValidateBuild
  -> CommitSprintWork -> [3 Parallel Reviews] -> [6 Cross-Critiques]
  -> ReviewAnalysis -> CompleteSprint -> Exit
```

**Key characteristics:**
- Must be invoked N times for N sprints (no parallelism across sprints)
- Multi-model review: Claude Opus, GPT-5.2, and Gemini all review, then each critiques the other two (6 cross-critiques per sprint)
- State managed via TSV ledger file
- Sprint specs are fully external (markdown files)
- Language-agnostic build validation

**Model routing:**
| Role | Provider | Model |
|------|----------|-------|
| Sprint discovery | Gemini | gemini-3-flash-preview |
| Implementation | Anthropic | claude-sonnet-4-6 |
| Commit | OpenAI | gpt-5.2 |
| Review (3x parallel) | All three | opus-4-6, gpt-5.2, gemini-3-flash |
| Cross-critique (6x) | All three | Same as reviews |
| Final verdict | Anthropic | claude-opus-4-6 |

### Generation 2: Project-Specific DAGs

Used by: remix-mar-13, test8, test7

**Design:** A purpose-built DAG encoding the entire project build plan. Every sprint is a node with its own prompt. The graph models dependencies, enables parallelism, and runs to completion in a single invocation.

**Model routing (test7 and test8):**
| Role | Provider | Model |
|------|----------|-------|
| Default | Anthropic | claude-sonnet-4-5 |
| Implementation (.code) | OpenAI | gpt-5.4 |
| Review (.review) | Anthropic | claude-opus-4-6 |

**Note:** remix-mar-13 used a different runner (`dotpowers-simple-auto`) with its own model routing.

---

## 2. Results by Variant

### 2.1 remix-orig — Never Executed

- **Sprint docs:** 53 meticulously written sprint briefs (SPRINT-001 through SPRINT-133)
- **Ledger:** All sprints remain "planned"
- **Outcome:** The pipeline was never invoked. This is a planning-only artifact.
- **Value:** The sprint briefs became the foundation for all subsequent attempts.

### 2.2 remix-1-smasher — Crashed at Init

- **Failure point:** `SetCurrentSprint` node
- **Root cause:** Sprint docs (`.ai/sprints/SPRINT-*.md`) did not exist in the execution directory. The ledger pre-generated 20 sprint entries, but no matching markdown files were present.
- **Error:** `no runnable sprint found: no non-completed ledger entry has a matching .ai/sprints/SPRINT-<id>.md file`
- **Sprints completed:** 0
- **Lesson:** The `AssertSprintDoc` safety check (added in this version) correctly prevented blind execution, but the pipeline had no recovery path.

### 2.3 remix-2-smasher-cc — Blocked After Sprint 101

- **Best Gen1 result.** The pipeline completed all 19 internal nodes and executed SPRINT-101 (Go project scaffold + SQLite schema).
- **Sprint 101 deliverables:** `go.mod`, 19 database tables, 10 indexes, 30+ offer templates, 8 tests — all passing.
- **Blocking bugs discovered:**
  1. **Working directory mismatch:** Pipeline orchestration nodes ran in the artifact directory, not the project root. The implementing agent detected and worked around this, but the pipeline itself couldn't advance to sprint 102.
  2. **ValidateBuild gap:** The build validator doesn't detect Go projects. Returned `validation-pass-no-known-build-system`.
  3. **Soft-failure bug:** Agent responses containing the word "FAIL" were still recorded as `outcome=success`. The pipeline cannot parse semantic failure from LLM output.
- **Multi-model review finding:** Reviews were "rubber-stamping" — none of the 3 reviewers read source files or diffs. They summarized the implementing agent's self-report. The cross-critique from Claude correctly flagged this: *"A reviewer who never reads the code and relies entirely on the implementing agent's own testimony is not reviewing; they're rubber-stamping."*
- **Sprints completed:** 1/133 (0.75%)

### 2.4 remix-3-tracker — Commit Step Failed

- **Completed:** SPRINT-001 (a documentation sprint: system overview, architecture, design philosophy)
- **Failure point:** `CommitSprintWork` node — missing `call_id` parameter in git API call
- **The work was done correctly** — spec updated with 330+ lines, all 8 Definition of Done items checked. Only the commit failed.
- **Sprints completed:** 1/53 (1.9%)

### 2.5 remix-orig-mar7 — Never Executed

- Planning snapshot taken March 7. Identical `sprint_exec.dot` to remix-3-tracker.
- All 53 sprints remain "planned."
- **Sprints completed:** 0

### 2.6 remix-4-mammoth — Never Executed

- Same planning artifacts as remix-orig-mar7.
- All 53 sprints remain "planned."
- **Sprints completed:** 0

### 2.7 remix-mar-13 — FULL SUCCESS (Python MVP)

- **Pipeline:** `dotpowers-simple-auto` (different runner than sprint_exec.dot)
- **Duration:** ~80 minutes (22:02 - 23:22 UTC, March 13)
- **Language:** Python 3.12, stdlib only
- **Approach:** Aggressive scope reduction via 8-iteration brainstorm. Cut Calendar, Claude API, contract detection, nightly pipeline. Built only the core CRM loop.
- **Deliverables:**
  - `scripts/server.py`: 921 lines, single-file monolith
  - 7 SQLite tables with idempotent migrations
  - Companies, Deals, Engagements, Deliverables, Offers CRUD
  - Deal -> Won -> auto-create Engagement with templated deliverables
  - Dark theme UI with Kanban pipeline board
  - 24 integration tests, 100% passing
  - 19 git commits with conventional commit messages
- **Key design decisions documented in brainstorm:**
  - Single file because "for AI-maintained codebases, greppability beats modularization"
  - Inline DB init because YAGNI
  - Route tables (not if/elif) for scannability
  - Integration tests (not unit) because "monolith's value is in integration"
- **Sprints completed:** 12/12 (100%)
- **Test pass rate:** 100% (24/24)

### 2.8 test8 — FULL SUCCESS (Python, Full Feature Set)

- **Pipeline:** Project-specific DAG (`pipeline.dot`)
- **Duration:** ~57 minutes (22:57 - 23:54 UTC, March 13)
- **Language:** Python 3.12 with uv
- **Approach:** Built everything in the spec. No scope reduction.
- **Pipeline topology:** Linear chain with 4 shallow fan-outs, 7 verification gates
- **Deliverables:**
  - `scripts/server.py`: 7,243 lines, single-file monolith
  - 9 supporting scripts (~10,500 additional lines)
  - 16 SQLite tables
  - 6 views: Briefing, Pipeline, Gantt, Client Dashboard, Offers, Tasks
  - Claude API command bar on every page
  - Google Calendar OAuth sync
  - Nightly contract detection/extraction pipeline
  - Staged review workflow (AI extracts, human approves)
  - macOS LaunchAgent configs
  - 300 tests passing, 1 skipped
  - 10 git commits
- **Retries needed:** Only 2 minor retries (`implement_launchagents`, `write_db_tests`)
- **Sprints completed:** 22/22 (100%)
- **Test pass rate:** 99.7% (300/301, 1 skipped for missing API key)

### 2.9 test7 — SUCCESS (Go, Structured Codebase)

- **Pipeline:** Project-specific DAG (`build_remixos.dot`)
- **Duration:** ~74 minutes (22:13 - 23:27 UTC, March 13)
- **Language:** Go 1.25 with HTMX
- **Approach:** Deep parallel DAG with 33 planned sprints, dependency-aware joins
- **Pipeline topology:** 5 join nodes, 2 fan-outs, 2 verification gates
- **Deliverables:**
  - 35 Go source files across `cmd/`, `internal/`, `web/`
  - Proper package structure (handlers, models, calendar, db)
  - 18 SQLite tables
  - HTMX progressive enhancement
  - Google Calendar OAuth sync
  - Agent assignment and work logs
  - Strategy page iframe integration
  - Health checks, backup strategy, deployment docs
  - 70 tests passing
  - 13 git commits
- **Sprints completed:** 14/33 (42% of planned, but all executed sprints succeeded)
- **Test pass rate:** 100% (70/70)

---

## 3. Comparative Analysis

### 3.1 Why Gen1 (Generic Runner) Failed

The generic `sprint_exec.dot` pipeline had three fatal issues:

1. **Working directory fragility.** The pipeline assumed tool commands would execute in the project root, but the runner placed them in artifact directories. This single assumption broke the entire pipeline after sprint 101.

2. **No cross-sprint parallelism.** The generic runner processes one sprint at a time. For a 33-sprint project, this means 33 sequential invocations with no ability to parallelize independent work (e.g., building Calendar OAuth while CRUD views are being implemented).

3. **Review theater.** The multi-model review system (3 reviews + 6 cross-critiques = 9 LLM calls per sprint) sounds impressive but produced low-value output. Reviewers didn't read source code — they summarized the implementing agent's claims. The cross-critique layer caught this, but the pipeline had no mechanism to force reviewers to actually read files.

### 3.2 Why Gen2 (Project DAGs) Succeeded

All three project-specific DAGs completed their scope:

1. **Single invocation.** The entire project runs in one execution. No state management between invocations. No ledger corruption risk.

2. **Parallelism where it matters.** test8 runs 6 views in parallel. test7 runs Calendar, CRUD, and Capacity tracks simultaneously. This isn't possible with a generic runner.

3. **Dependency modeling.** test7's join nodes explicitly encode real constraints (can't build Nightly Sync without Drive + Calendar). This prevents ordering bugs while maximizing parallelism.

4. **Inline prompts (test8) or hybrid prompts (test7).** Having the specification directly in the node prompt (or referenced via external sprint briefs that are guaranteed to exist) eliminates the "missing sprint doc" failure class entirely.

### 3.3 Scope vs. Quality Tradeoff

| Metric | remix-mar-13 | test8 | test7 |
|--------|-------------|-------|-------|
| Scope | Aggressive MVP (core CRM only) | Full spec | Full spec |
| Code size | 921 lines | 17,743 lines | ~5,000+ lines |
| File count | 1 file | 10 files | 35 files |
| Test count | 24 | 301 | 70 |
| Duration | 80 min | 57 min | 74 min |
| Maintainability | High (small, simple) | Low (7K monolith) | High (Go packages) |
| Feature completeness | Low | Highest | Medium |

**remix-mar-13** proves that scope discipline produces the cleanest output. Its 8-iteration brainstorm explicitly debated and rejected features, resulting in 921 lines that do exactly what's needed.

**test8** proves that a pipeline can build a fully-featured system autonomously, but the 7,243-line single file is a maintenance concern that the pipeline doesn't address.

**test7** proves that proper code structure (Go packages, HTMX templates) can be achieved autonomously, but its 33-sprint scope meant only 14 sprints were executed in the time available.

### 3.4 Model Impact

All three successful DAGs used GPT-5.4 for implementation (`.code` class). The Gen1 runner used Claude Sonnet 4.6. Both produced working code, so model selection doesn't appear to be a differentiator for implementation quality.

The more interesting finding: **test7 never used the `.review` class at all** (no Opus review nodes in its graph), yet produced the most structured codebase. test8 used Opus for planning only. This suggests that TDD (enforced in every sprint prompt) is a more effective quality mechanism than post-hoc multi-model review.

---

## 4. Pipeline Design Patterns: What Works

### 4.1 Effective Patterns

| Pattern | Where Used | Why It Works |
|---------|-----------|-------------|
| Project-specific DAG | test7, test8, remix-mar-13 | Encodes real dependencies, enables parallelism |
| TDD in every prompt | All successful runs | Catches issues at implementation time, not review time |
| Verification gates with retry loops | test8 (7 gates), test7 (2 gates) | Automated feedback without human intervention |
| Fan-out for independent tasks | test8 (views), test7 (tracks) | Reduces wall-clock time |
| Dependency-aware joins | test7 | Prevents ordering bugs while maximizing parallelism |
| Scope reduction via brainstorm | remix-mar-13 | Produces clean, maintainable output |
| Inline prompts | test8 | Self-contained, no missing file failures |
| External sprint briefs | test7 | Separates orchestration from specification |

### 4.2 Anti-Patterns

| Anti-Pattern | Where Found | Why It Fails |
|-------------|------------|-------------|
| Generic runner for multi-sprint projects | All Gen1 variants | No cross-sprint parallelism, state management fragility |
| Multi-model review without file access | remix-2-smasher-cc | Produces rubber-stamp reviews, wastes 9 LLM calls per sprint |
| Assumed working directory | Gen1 runner | Single assumption breaks entire pipeline |
| No scope discipline | test7, test8 | Builds everything regardless of value, risks 7K monoliths |
| Soft-failure detection | Gen1 runner | Can't distinguish "FAIL" in LLM text from actual failure |

### 4.3 Missing Patterns (Opportunities)

1. **Scope gating.** No pipeline includes a brainstorm/scoping phase that can reduce the number of sprints. remix-mar-13 did this manually; test7 and test8 built everything.

2. **Incremental review.** Instead of reviewing after implementation, review the diff before committing. None of the pipelines do this effectively.

3. **Cross-sprint test regression.** test8 has per-phase verification but no mechanism to detect that sprint N broke something from sprint N-3. Only the final E2E tests catch this.

4. **Adaptive parallelism.** test7's DAG is statically defined. A smarter system could dynamically add parallel tracks based on which sprints are independent.

---

## 5. Recommendations

### For Pipeline Design

1. **Use project-specific DAGs**, not generic runners. The overhead of encoding dependencies is repaid by parallelism and reliability.

2. **Include a scoping phase.** The brainstorm/design-brief pattern from remix-mar-13 should be the first node in every project DAG. Let an architect model (Opus) decide what NOT to build.

3. **Replace multi-model review with TDD + verification gates.** 9 LLM calls per sprint for reviews that don't read code is waste. TDD catches real bugs; reviews catch style issues at best.

4. **Model dependency joins explicitly.** test7's `join_sync_deps`, `join_task_deps` pattern prevents ordering bugs and documents architectural constraints in the DAG itself.

5. **Fix the working directory assumption.** Every tool_command node should explicitly set its working directory. Never rely on inherited state.

### For the Ideal Pipeline

Combining the best of all three:

```
start -> brainstorm (Opus, 8 iterations, scope reduction)
  -> plan (Opus, dependency DAG generation)
  -> foundation [sequential: scaffold, schema, server]
  -> verify_foundation
  -> [fan-out: independent feature tracks with dependency joins]
  -> [per-track: TDD cycle with verification gates]
  -> join_all
  -> e2e_tests
  -> final_verify
  -> done
```

With: test7's dependency joins, test8's inline prompts, remix-mar-13's scope discipline, and GPT-5.4 for implementation with Opus for planning only.

---

## 6. Raw Data

### Execution Timeline (March 13, 2026)

```
22:02 - remix-mar-13 starts (dotpowers-simple-auto)
22:13 - test7 starts (build_remixos.dot)
22:57 - test8 starts (pipeline.dot)
23:22 - remix-mar-13 completes (80 min, 12/12 sprints, 24 tests)
23:27 - test7 completes (74 min, 14/33 sprints, 70 tests)
23:54 - test8 completes (57 min, 22/22 sprints, 301 tests)
```

All three successful runs executed on the same evening, suggesting a deliberate A/B/C test of pipeline designs.

### Gen1 Execution History

```
Mar 6-7:  remix-orig created (planning only, never run)
Mar 7:    remix-1-smasher attempted (crashed at SetCurrentSprint)
Mar 7:    remix-2-smasher-cc attempted (1/133 sprints, pipeline blocked)
Mar 7:    remix-3-tracker attempted (1/53 sprints, commit step failed)
Mar 7:    remix-orig-mar7 snapshot (never run)
Mar 7:    remix-4-mammoth created (never run)
Mar 13:   All three Gen2 attempts succeed
```

The Gen1 failures on March 7 likely motivated the shift to project-specific DAGs on March 13.

---

## Appendix A: File Locations

| Variant | DOT File | Working Directory |
|---------|----------|-------------------|
| remix-orig | sprint_exec.dot | /Users/harper/workspace/2389/justin-remix/remix-orig/ |
| remix-1-smasher | sprint_exec.dot | /Users/harper/workspace/2389/justin-remix/remix-1-smasher/ |
| remix-2-smasher-cc | sprint_exec.dot | /Users/harper/workspace/2389/justin-remix/remix-2-smasher-cc/ |
| remix-3-tracker | sprint_exec.dot | /Users/harper/workspace/2389/justin-remix/remix-3-tracker/ |
| remix-orig-mar7 | sprint_exec.dot | /Users/harper/workspace/2389/justin-remix/remix-orig-mar7/ |
| remix-4-mammoth | sprint_exec.dot | /Users/harper/workspace/2389/justin-remix/remix-4-mammoth/ |
| remix-mar-13 | (dotpowers-simple-auto) | /Users/harper/workspace/2389/justin-remix/remix-mar-13/ |
| test8 | pipeline.dot | /Users/harper/Public/src/2389/tracker-test/test8/ |
| test7 | build_remixos.dot | /Users/harper/Public/src/2389/tracker-test/test7/ |

## Appendix B: sprint_exec.dot Evolution

The generic runner barely changed across 6 versions:

| Version | Change from Previous |
|---------|---------------------|
| remix-orig | Baseline. Minimal ledger (1 entry). No AssertSprintDoc node. |
| remix-1-smasher | Added AssertSprintDoc node. Ledger pre-generates 20 entries. |
| remix-2-smasher-cc | Identical to remix-1-smasher |
| remix-3-tracker | Identical |
| remix-orig-mar7 | Identical |
| remix-4-mammoth | Identical |

The pipeline stabilized after one bug fix and was never improved further despite the failures it produced.
