# Spec-to-Dip Compiler

**Date:** 2026-04-06

## Problem

Generating high-quality `.dip` pipeline files from specs is manual and error-prone. Each pipeline needs correct graph topology, exhaustive edge conditions, robust retry/fallback patterns, proper prompt engineering, and adherence to 39 dippin validation rules. LLMs can do this, but a single model often misses edge cases, skips validation, or drifts from the spec.

## Solution

A `.dip` pipeline (`spec_to_dip.dip`) that reads a spec (required) and optional superpowers plan, then uses a multi-model tournament with domain-specific review panels to generate a production-quality `.dip` file. The pipeline incorporates patterns from the 2389 ecosystem:

- **Jam:** Domain-specific perspective panels, active synthesis of loser insights into the winner
- **Deliberation:** Tensions surfaced not papered over, structured discernment at decision points
- **Test Kitchen:** Parallel generation, objective tests (dippin toolchain) determine quality
- **Review Squad:** Multi-perspective review dispatch with specialized reviewers
- **Simmer:** Iterative refinement with investigation-first judge board — the final .dip goes through simmer-style refinement loops where judges investigate the artifact before scoring
- **Scenario Testing:** Generated pipelines enforce the Iron Law: "NO FEATURE IS VALIDATED UNTIL A SCENARIO PASSES WITH REAL DEPENDENCIES" — no mocks allowed, real systems exercised

The `dippin check` toolchain serves as the objective quality gate throughout.

## Inputs

| Input | Required | Location |
|-------|----------|----------|
| Spec file | Yes | `spec.md`, `design.md`, `SPEC.md`, or first `*.md` in working dir |
| Superpowers plan | No | `docs/superpowers/plans/*.md` |
| Superpowers spec | No | `docs/superpowers/specs/*.md` |

When a superpowers plan is available, the generation agents use its task breakdown and ordering to inform pipeline structure. Without a plan, the analysis phase derives structure from the spec alone.

## Output

A validated `.dip` file in the working directory with:
- Zero `dippin check` errors
- Zero `dippin lint` warnings (or documented justifications)
- A spec compliance matrix proving every requirement is addressed
- A `dippin doctor` grade of A or B

## Pipeline Architecture

### Workflow header

```
workflow SpecToDip
  goal: "Generate a validated, production-quality .dip pipeline from a spec using multi-model tournament with domain-specific review panels and spec compliance verification"
  start: Start
  exit: Done
```

### Defaults

```
defaults
  model: claude-sonnet-4-6
  provider: anthropic
  max_retries: 3
  max_restarts: 15
```

---

## Phase 1: Discovery

### Nodes

**`Start`** (agent) — Lifecycle entry node.

**`find_spec`** (tool, timeout: 30s) — Searches for spec files in priority order: `spec.md`, `SPEC.md`, `design.md`, `design-doc.md`, `specification.md`, `requirements.md`, `prompt_plan.md`. Falls back to first `*.md` not in `.git/` or `docs/plans/`. Outputs: the filename, or `no_spec_found`.

**`find_plan`** (tool, timeout: 30s) — Checks `docs/superpowers/plans/*.md` and `docs/superpowers/specs/*.md` for superpowers artifacts. Outputs: `plan_found` or `no_plan`. Non-blocking — pipeline continues either way.

### Edges

```
Start -> find_spec
find_spec -> find_plan          when ctx.tool_stdout != no_spec_found
find_spec -> no_spec_exit       when ctx.tool_stdout = no_spec_found
find_plan -> analyze_spec
```

**`no_spec_exit`** (agent) — Reports error: no spec found. Routes to Done.

---

## Phase 2: Spec Analysis

### Nodes

**`analyze_spec`** (agent, Opus, reasoning_effort: high, goal_gate: true) — Deep-reads the spec and optional plan. Produces `docs/plans/dip_analysis.md` containing:

1. **Project Summary** — Name, purpose, one-paragraph description
2. **Tech Stack** — Language, framework, database, test framework, linter, package manager
3. **Components** — Numbered list with name, description, dependencies
4. **Dependency Graph** — Which components are parallel vs sequential
5. **Recommended Topology** — LINEAR (1-3 components), FAN_OUT (4-8, shared foundation), DAG (8+ with cross-deps)
6. **Architectural Slots** — Key design decisions where multiple valid approaches exist (Jam pattern). Examples: "parallel vs serial build phases," "single reviewer vs cross-review," "human gates: where and how many"
7. **Pipeline Node Inventory** — Recommended node types: which components need agent nodes, which need tool nodes, where human gates belong
8. **Edge Pattern Recommendations** — Where to use conditional routing, retry loops, fallback paths
9. **Spec Requirements Checklist** — Every discrete requirement extracted from the spec, numbered for compliance tracing

**`check_analysis`** (tool, timeout: 30s) — Validates `docs/plans/dip_analysis.md` exists and contains all required sections.

### Edges

```
analyze_spec -> check_analysis
check_analysis -> identify_perspectives    when ctx.tool_stdout = analysis_ok
check_analysis -> analyze_spec             when ctx.tool_stdout = analysis_missing  restart: true
```

---

## Phase 3: Perspective Generation (Jam Pattern)

### Nodes

**`identify_perspectives`** (agent, Opus, reasoning_effort: high) — Reads the analysis and identifies 3-5 domain-specific perspectives relevant to this spec's pipeline design. NOT hardcoded personas — generated fresh based on the problem domain. Example outputs:

For a web app spec:
- "Full-stack architect focused on deployment reliability"
- "QA engineer focused on test coverage and edge cases"  
- "DevOps engineer focused on CI/CD pipeline efficiency"

For a data pipeline spec:
- "Data engineer focused on throughput and backpressure"
- "ML engineer focused on model validation gates"
- "SRE focused on observability and failure recovery"

Writes perspective descriptions to `.ai/perspectives.md`.

### Edges

```
identify_perspectives -> gen_parallel
```

---

## Phase 4: Generation Tournament (Parallel)

### Nodes

**`gen_parallel`** (parallel) -> `gen_claude`, `gen_gpt`, `gen_gemini`

Each generation agent receives:
1. The spec analysis (`docs/plans/dip_analysis.md`)
2. The perspectives (`.ai/perspectives.md`)
3. The dippin LLM reference card (embedded in prompt)
4. The original spec file
5. The superpowers plan (if found)
6. Instructions to address ALL numbered spec requirements

**`gen_claude`** (agent, claude-opus-4-6, reasoning_effort: high) — Generates `.ai/candidates/claude.dip`. Prompt emphasizes thoroughness, exhaustive edge conditions, and spec compliance.

**`gen_gpt`** (agent, gpt-5.4, provider: openai, reasoning_effort: high) — Generates `.ai/candidates/gpt.dip`. Prompt emphasizes structural clarity and clean topology.

**`gen_gemini`** (agent, gemini-2.5-pro, provider: gemini, reasoning_effort: high) — Generates `.ai/candidates/gemini.dip`. Prompt emphasizes robustness, error handling, and edge case coverage.

**`gen_join`** (fan_in) <- `gen_claude`, `gen_gpt`, `gen_gemini`

### Edges

```
gen_parallel -> gen_claude
gen_parallel -> gen_gpt
gen_parallel -> gen_gemini
gen_claude -> gen_join
gen_gpt -> gen_join
gen_gemini -> gen_join
gen_join -> validate_parallel
```

---

## Phase 5: Validation + Fix Loop (Sequential per Candidate)

Each candidate is validated and fixed sequentially. Dippin's parallel/fan_in semantics require all branches to complete before the join, so fix loops inside parallel branches would deadlock the fan_in. Instead, we validate each candidate in sequence after the generation join.

### Nodes

**`validate_all`** (tool, timeout: 60s) — Runs `dippin check --format json` on all three candidates. Writes per-candidate results to `.ai/candidates/{name}_check.json`. Outputs: `all_valid`, `claude_errors`, `gpt_errors`, `gemini_errors`, or `multiple_errors`.

**`fix_claude`** (agent, claude-sonnet-4-6) — Reads `dippin check` JSON diagnostics for the Claude candidate, fixes the .dip file. Has access to `dippin explain DIPxxx` for understanding diagnostic codes.

**`fix_gpt`** (agent, claude-sonnet-4-6) — Same for GPT candidate.

**`fix_gemini`** (agent, claude-sonnet-4-6) — Same for Gemini candidate.

**`fix_all`** (agent, claude-sonnet-4-6) — When multiple candidates have errors, fixes all of them in sequence.

### Edges

```
gen_join -> validate_all
validate_all -> compliance_parallel       when ctx.tool_stdout = all_valid
validate_all -> fix_claude                when ctx.tool_stdout = claude_errors
validate_all -> fix_gpt                   when ctx.tool_stdout = gpt_errors
validate_all -> fix_gemini                when ctx.tool_stdout = gemini_errors
validate_all -> fix_all                   when ctx.tool_stdout = multiple_errors
fix_claude -> validate_all                restart: true
fix_gpt -> validate_all                   restart: true
fix_gemini -> validate_all                restart: true
fix_all -> validate_all                   restart: true
```

---

## Phase 6: Spec Compliance Check (Parallel)

Each validated candidate is checked against the spec requirements checklist.

### Nodes

**`compliance_parallel`** (parallel) -> `compliance_claude`, `compliance_gpt`, `compliance_gemini`

**`compliance_claude`** (agent, claude-sonnet-4-6) — Reads the spec requirements checklist from `dip_analysis.md` and traces each requirement to specific nodes/edges in `.ai/candidates/claude.dip`. Produces a compliance matrix:

```markdown
| # | Requirement | Node(s) | Coverage | Gap |
|---|------------|---------|----------|-----|
| 1 | User auth  | auth_setup, validate_auth | Full | — |
| 2 | Rate limit | — | MISSING | No rate limiting node |
```

Writes to `.ai/candidates/claude_compliance.md`. Outputs `compliant` or `gaps_found`.

**`compliance_gpt`** / **`compliance_gemini`** — Same for other candidates.

**`compliance_join`** (fan_in) <- `compliance_claude`, `compliance_gpt`, `compliance_gemini`

### Edges

```
compliance_parallel -> compliance_claude
compliance_parallel -> compliance_gpt
compliance_parallel -> compliance_gemini
compliance_claude -> compliance_join
compliance_gpt -> compliance_join
compliance_gemini -> compliance_join
compliance_join -> review_parallel
```

---

## Phase 7: Review Panel (Review Squad + Deliberation Patterns)

Domain-specific review panel evaluates all candidates. Each reviewer examines ALL three candidates and scores them.

### Nodes

**`review_parallel`** (parallel) -> `review_structure`, `review_compliance`, `review_robustness`, `review_efficiency`, `review_prompts`

**`review_structure`** (agent, claude-opus-4-6, reasoning_effort: high) — Evaluates graph structure: Are edges exhaustive? Are conditions correct? Are parallel/fan_in matched? Does topology match the recommended architecture? Scores each candidate 1-10.

**`review_compliance`** (agent, gpt-5.4, provider: openai, reasoning_effort: high) — Cross-checks compliance matrices against the spec. Verifies traceability. Checks for requirements that are superficially addressed but not actually implemented. Scores each candidate 1-10.

**`review_robustness`** (agent, gemini-2.5-pro, provider: gemini, reasoning_effort: high) — Evaluates retry loops, fallback paths, timeout coverage, error handling, max_restarts settings, goal gates. Scores each candidate 1-10.

**`review_efficiency`** (agent, claude-sonnet-4-6) — Checks for unnecessary serial bottlenecks, opportunities for parallelism, model cost optimization, appropriate reasoning_effort levels. Scores each candidate 1-10.

**`review_prompts`** (agent, claude-opus-4-6, reasoning_effort: high) — Evaluates prompt quality: Are they specific enough? Do they include success criteria? Do they reference context variables correctly? Do they avoid vague instructions? Scores each candidate 1-10.

**`review_join`** (fan_in) <- `review_structure`, `review_compliance`, `review_robustness`, `review_efficiency`, `review_prompts`

### Edges

```
review_parallel -> review_structure
review_parallel -> review_compliance
review_parallel -> review_robustness
review_parallel -> review_efficiency
review_parallel -> review_prompts
review_structure -> review_join
review_compliance -> review_join
review_robustness -> review_join
review_efficiency -> review_join
review_prompts -> review_join
review_join -> synthesize_scores
```

---

## Phase 8: Scoring & Recommendation (Deliberation Pattern)

### Nodes

**`synthesize_scores`** (agent, claude-opus-4-6, reasoning_effort: high) — Reads all review panel findings and compliance matrices. Produces `.ai/candidates/tournament_results.md`:

1. **Score Summary** — Aggregate scores per candidate across all review dimensions
2. **Ranking** — Clear 1st/2nd/3rd with reasoning
3. **Tensions** — Where reviewers disagreed, surface the tension explicitly (Deliberation pattern: tensions surfaced, not papered over)
4. **Synthesis Opportunities** — Specific elements from non-winning candidates worth incorporating (Jam pattern: active synthesis)
5. **Compliance Status** — Which candidates are fully compliant, which have gaps
6. **Recommendation** — Pick winner, merge, or note if rework is needed

Outputs: `clear_winner`, `merge_recommended`, or `rework_needed`.

### Edges

```
synthesize_scores -> human_select
```

---

## Phase 9: Human Decision Gate

### Nodes

**`human_select`** (human, mode: choice, default: "pick") — Presented with:
- Tournament results summary
- Compliance matrices for all candidates
- Synthesis opportunities
- Three choices:

### Edges

```
human_select -> copy_winner        label: "[P] Pick winner"
human_select -> merge_candidates   label: "[M] Merge best elements"
human_select -> rework_feedback    label: "[R] Rework with feedback"
```

---

## Phase 10a: Pick Winner Path

### Nodes

**`copy_winner`** (agent, claude-sonnet-4-6) — Copies the winning candidate to `.ai/candidates/final.dip`. Applies any trivial fixes noted by reviewers (lint warnings, missing labels).

### Edges

```
copy_winner -> final_validate
```

---

## Phase 10b: Merge Path (Jam Active Synthesis)

### Nodes

**`merge_candidates`** (agent, claude-opus-4-6, reasoning_effort: high) — Active synthesis, not passive selection. Takes the winning candidate as the base and actively incorporates the best elements from the other candidates:
- Better prompts from candidate A
- Stronger routing/edge patterns from candidate B  
- More thorough error handling from candidate C

Writes `.ai/candidates/final.dip`. Must preserve structural validity throughout.

**`validate_merge`** (tool, timeout: 30s) — `dippin check --format json .ai/candidates/final.dip`.

**`fix_merge`** (agent, claude-sonnet-4-6) — If merge introduced validation errors, fix them.

### Edges

```
merge_candidates -> validate_merge
validate_merge -> fix_merge        when ctx.tool_stdout = errors
fix_merge -> validate_merge        restart: true
validate_merge -> final_validate   when ctx.tool_stdout = valid
```

---

## Phase 10c: Rework Path

### Nodes

**`rework_feedback`** (human, mode: freeform) — Human provides specific feedback on what needs to change.

**`rework_analysis`** (agent, claude-opus-4-6, reasoning_effort: high) — Incorporates human feedback into the analysis, updates `dip_analysis.md` with revised requirements.

### Edges

```
rework_feedback -> rework_analysis
rework_analysis -> gen_parallel     restart: true
```

---

## Phase 11: Final Validation

### Nodes

**`final_validate`** (tool, timeout: 60s) — Runs the full dippin validation suite:
```sh
dippin check --format json .ai/candidates/final.dip
dippin lint .ai/candidates/final.dip
dippin doctor .ai/candidates/final.dip
dippin coverage .ai/candidates/final.dip
```
Outputs: `grade_A`, `grade_B`, `grade_C`, or `grade_F`.

**`final_fix`** (agent, claude-sonnet-4-6) — Addresses any remaining lint warnings or doctor suggestions.

**`publish_output`** (agent, claude-sonnet-4-6) — Copies final .dip to working directory root with spec-derived name. Writes a summary including:
- Final dippin doctor grade
- Compliance matrix summary
- Tournament results summary
- Generation provenance (which model contributed what)

Commits everything.

### Edges

```
final_validate -> final_fix           when ctx.tool_stdout = grade_C
final_validate -> final_fix           when ctx.tool_stdout = grade_F
final_fix -> final_validate           restart: true
final_validate -> simmer_judge        when ctx.tool_stdout = grade_A
final_validate -> simmer_judge        when ctx.tool_stdout = grade_B
```

---

## Phase 12: Simmer Refinement (Simmer Pattern)

After the .dip passes validation, it goes through a simmer-style refinement loop. The judge board investigates the artifact before scoring — reading the spec, the analysis, the compliance matrix, and the .dip itself to understand the problem before proposing improvements.

### Nodes

**`simmer_judge`** (agent, claude-opus-4-6, reasoning_effort: high, auto_status: true) — Investigation-first judge. Before scoring, reads:
1. The original spec
2. The dip_analysis.md
3. The compliance matrix
4. The candidate .dip file
5. The tournament results (what reviewers said)

Scores the .dip 1-10 on each criterion:
- Spec fidelity (does the pipeline do what the spec says?)
- Prompt specificity (are prompts actionable, not vague?)
- Edge exhaustiveness (can execution get stuck?)
- Error recovery (retry loops, fallbacks, goal gates)
- TDD pattern quality (is the test-first loop real or perfunctory?)
- Security review depth (tech-stack-specific or generic?)
- Scenario testing (real dependencies or mock-friendly?)

Produces **ASI (Actionable Side Information)**: the single highest-leverage improvement for the next iteration.

Outputs: `STATUS: success` (score >= 8 on all criteria) or `STATUS: fail` (improvement needed).

**`simmer_refine`** (agent, claude-opus-4-6, reasoning_effort: high) — Receives the ASI and improves the .dip file. Makes the minimum change to address the judge's highest-leverage suggestion. Does NOT see scores (Simmer context discipline: generator doesn't see scores to avoid optimizing for numbers).

**`simmer_revalidate`** (tool, timeout: 30s) — `dippin check --format json` on the refined .dip. Ensures the refinement didn't break structural validity.

### Edges

```
simmer_judge -> publish_output        when ctx.outcome = success
simmer_judge -> simmer_refine         when ctx.outcome = fail
simmer_refine -> simmer_revalidate
simmer_revalidate -> simmer_judge     when ctx.tool_stdout = valid    restart: true
simmer_revalidate -> simmer_refine    when ctx.tool_stdout = errors   restart: true
```

The simmer loop runs up to 3 iterations (bounded by max_restarts). If the judge can't get all criteria to 8+, the pipeline proceeds with the best iteration.

---

## Phase 13: Publish

### Nodes

**`publish_output`** (agent, claude-sonnet-4-6) — Copies final .dip to working directory root with spec-derived name. Writes a summary including:
- Final dippin doctor grade
- Simmer judge scores (final iteration)
- Compliance matrix summary
- Tournament results summary
- Generation provenance (which model contributed what)

Commits everything.

### Edges

```
publish_output -> Done
no_spec_exit -> Done
```

---

## Node Inventory Summary

| Phase | Nodes | Type |
|-------|-------|------|
| Discovery | Start, find_spec, find_plan, no_spec_exit | 1 agent, 2 tool, 1 agent |
| Analysis | analyze_spec, check_analysis | 1 agent, 1 tool |
| Perspectives | identify_perspectives | 1 agent |
| Generation | gen_parallel, gen_claude, gen_gpt, gen_gemini, gen_join | 1 parallel, 3 agent, 1 fan_in |
| Validation | validate_parallel, validate_claude/gpt/gemini, fix_claude/gpt/gemini, validate_join | 1 parallel, 3 tool, 3 agent, 1 fan_in |
| Compliance | compliance_parallel, compliance_claude/gpt/gemini, compliance_join | 1 parallel, 3 agent, 1 fan_in |
| Review | review_parallel, review_structure/compliance/robustness/efficiency/prompts, review_join | 1 parallel, 5 agent, 1 fan_in |
| Scoring | synthesize_scores | 1 agent |
| Human | human_select | 1 human |
| Pick | copy_winner | 1 agent |
| Merge | merge_candidates, validate_merge, fix_merge | 2 agent, 1 tool |
| Rework | rework_feedback, rework_analysis | 1 human, 1 agent |
| Final Validation | final_validate, final_fix | 1 tool, 1 agent |
| Simmer | simmer_judge, simmer_refine, simmer_revalidate | 2 agent, 1 tool |
| Publish | publish_output, Done | 2 agent |

**Total:** ~45 nodes

---

## Prompt Strategy

### Generation Prompts

Every generation agent receives this structure:

1. **Dippin LLM Reference Card** — Full syntax reference, common mistakes, exhaustive condition rules
2. **Spec Analysis** — From Phase 2
3. **Perspectives** — Domain-specific viewpoints to consider
4. **Original Spec** — Full text
5. **Superpowers Plan** — If available, use task ordering and structure
6. **Generation Rules:**
   - Every spec requirement MUST map to at least one node
   - Every agent node MUST have a substantive prompt
   - Every tool node MUST have a timeout
   - All conditional edges MUST be exhaustive or have fallbacks
   - Back-edges MUST have `restart: true`
   - Use `auto_status: true` + conditional routing for decision points
   - Use `goal_gate: true` for critical quality checks
   - Include `reads:` and `writes:` for data flow clarity

### Fix Agent Prompts

Fix agents receive:
1. The `dippin check` JSON output
2. The specific diagnostic code explanations
3. The current .dip file content
4. Instructions: fix the minimum necessary, do not rewrite

### Review Panel Prompts

Each reviewer receives:
1. ALL three candidate .dip files
2. The spec analysis
3. The compliance matrices
4. Their specific review dimension and scoring criteria (1-10)
5. Instructions to score each candidate independently, justify scores with evidence

---

## Error Handling & Robustness

| Scenario | Handling |
|----------|----------|
| No spec found | Early exit via `no_spec_exit` → Done |
| Analysis incomplete | Restart loop to `analyze_spec` (max 3) |
| Generation produces invalid .dip | Per-candidate fix loop (max 3 per candidate) |
| All candidates fail validation | Human gets notified in scoring phase |
| Merge introduces errors | Fix loop on merge output (max 3) |
| Final grade C/F | Fix loop to `final_fix` (max 3) |
| Human chooses rework | Full restart from generation with feedback |

Global `max_restarts: 15` prevents infinite loops (accounts for validation fix loops + simmer refinement iterations).

---

## Generated Pipeline Quality Requirements

The `.dip` files produced by this compiler MUST embed the following patterns. These are not optional — the generation prompts enforce them, the review panel checks them, and the compliance matrix tracks them.

### Test-Driven Development Pattern

Every generated pipeline MUST include a TDD loop where tests are written before implementation:

1. A **write tests** agent node that produces test files based on the spec requirements
2. A **run tests** tool node that executes the test suite (with timeout)
3. An **implement** agent node that writes code to make failing tests pass
4. A **verify tests** tool node that re-runs tests to confirm they pass
5. A restart edge from verify back to implement on failure

The generated pipeline should structure this as:
```
write_tests -> run_tests_initial (expect fail) -> implement -> run_tests_verify -> 
  [pass: continue] / [fail: implement (restart)]
```

This pattern applies per-component when the spec has multiple components.

### Security Review Pattern

Every generated pipeline MUST include security review nodes:

1. A **security scan** tool node that runs static analysis (language-appropriate: `bandit` for Python, `gosec` for Go, `eslint-plugin-security` for JS/TS, etc.)
2. A **security review** agent node (goal_gate: true) that reviews the scan results AND manually inspects for OWASP Top 10 vulnerabilities relevant to the tech stack
3. Conditional routing: pass → continue, fail → fix loop with restart

The security review agent prompt MUST be specific to the tech stack identified in the analysis phase. Generic "check for security issues" prompts are insufficient.

### Code Quality Gates

Generated pipelines MUST include:

1. **Linting** — A tool node running the language-appropriate linter (ruff for Python, golangci-lint for Go, eslint for JS/TS)
2. **Type checking** — If the tech stack supports it (mypy, tsc, go vet)
3. **Formatting** — A tool node running the language formatter
4. These gates should be tool nodes with timeouts, not embedded in agent prompts

### Integration Testing

When the spec describes interactions between components (API endpoints, database access, message queues), the generated pipeline MUST include:

1. An **integration test** tool node that tests component interactions
2. Infrastructure setup nodes if needed (start database, start emulator, etc.)
3. Teardown/cleanup as appropriate

### Scenario Testing Pattern (The Iron Law)

**"NO FEATURE IS VALIDATED UNTIL A SCENARIO PASSES WITH REAL DEPENDENCIES"**

Generated pipelines MUST include scenario testing that exercises real systems:

1. A **scenario setup** tool node that creates `.scratch/` directory and prepares test data against real dependencies (test database instances, sandbox API endpoints, local emulators — never mocks)
2. A **scenario run** tool node that executes scenario tests in `.scratch/` with real dependencies. Tests must be independent (each sets up own data, no ordering dependencies)
3. A **scenario extract** tool node that promotes recurring patterns to `scenarios.jsonl` (committed to git, while `.scratch/` stays gitignored)
4. Conditional routing: pass → continue, fail → fix loop with restart

The truth hierarchy for generated pipelines:
- Scenario tests (real system, real data) = **TRUTH**
- Unit tests (isolated) = useful but not sufficient
- Mocks = explicitly prohibited

When the spec involves external services, the generated pipeline MUST include infrastructure setup nodes (start emulators, create test instances) with health checks before scenario tests run.

### Simmer-Style Refinement Loop

Generated pipelines SHOULD include a simmer-style quality loop for their primary output artifact:

1. A **judge** agent node that evaluates the output against spec criteria (investigation-first — reads the artifact and context before scoring)
2. A **refine** agent node that addresses the judge's highest-leverage improvement (receives ASI, not scores)
3. A **revalidate** tool node that confirms the refinement didn't break anything
4. Restart edges bounded by max_restarts

This pattern is especially valuable for pipelines producing complex artifacts (generated code, documentation, configurations).

### Human Review Gates

Generated pipelines MUST include at least one human review gate at a meaningful decision point (not just at the end). The analysis phase determines where human input adds the most value — typically after initial implementation and before final shipping.

---

## Success Criteria

1. Generated `.dip` file passes `dippin check` with zero errors
2. Generated `.dip` file passes `dippin lint` with zero warnings (or documented justifications)
3. Every spec requirement traces to at least one node in the compliance matrix
4. `dippin doctor` grade is A or B
5. Human approved the output (pick or merge path)
6. Simmer judge scores >= 8 on all criteria (or best iteration after 3 rounds)
7. Generated pipeline includes TDD pattern (write tests → run → implement → verify loop)
8. Generated pipeline includes security review nodes with tech-stack-specific tooling
9. Generated pipeline includes code quality gates (lint, type check, format)
10. Generated pipeline includes scenario testing with real dependencies (no mocks)
11. Generated pipeline includes integration tests when spec describes component interactions
12. Generated pipeline includes at least one human review gate at a meaningful decision point
13. Generated pipeline includes simmer-style refinement for primary output artifacts (when applicable)
