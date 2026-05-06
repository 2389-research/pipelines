# Iterative Development Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 5 modular `.dip` pipeline files that replicate the iterative-development autonomous lifecycle with PAR review gates, TDD discipline, and behavior evidence tracking.

**Architecture:** Five `.dip` files composed via `subgraph ref:` — leaf modules first (extract, scope, audit), then the complex iteration runner, then the orchestrator. Each file is independently runnable and validates with `tracker validate`.

**Tech Stack:** Dippin pipeline language (.dip), tracker runtime, shell scripts in tool nodes, multi-provider LLM orchestration (Anthropic/OpenAI/Google).

**Spec:** `docs/superpowers/specs/2026-04-25-iterative-development-pipeline-design.md`

**Reference files for Dippin syntax:**
- `sprint_runner_yaml_v2.dip` — loop pattern via `restart: true`, subgraph composition
- `spec_to_sprints_yaml_v2.dip` — parallel fan-out/fan-in, multi-model tournament, tool nodes with shell scripts
- `sprint_exec_yaml_v2.dip` — manager agents, mechanical safety gates, conditional edges

---

## File Structure

| File | Create/Modify | Responsibility |
|------|--------------|----------------|
| `iter_extract.dip` | Create | Requirements extraction: chunk spec → parallel extract → PAR omission review → aggregate → corpus |
| `iter_scope.dip` | Create | Walking skeleton + roadmap: define ITER-0000 → order iterations → PAR scope review |
| `iter_audit.dip` | Create | Three-tier PAR audit: deep evidence → impacted behavior → sentinel regression |
| `iter_run.dip` | Create | Single iteration execution: sentinel baseline → scope review → TDD tasks with 2-stage PAR review → wrap-up |
| `iter_dev.dip` | Create | Orchestrator: bootstrap → main loop → final behavior-evidence audit |

Build order: Tasks 1-3 are independent leaf modules (can be parallelized). Task 4 depends on understanding the PAR pattern established in 1-3. Task 5 depends on all others existing (subgraph refs). Task 6 validates the composed system.

---

### Task 1: Create `iter_extract.dip`

**Files:**
- Create: `iter_extract.dip`

**Context:** This pipeline reads a spec file, chunks it by markdown headings, dispatches parallel extraction agents in waves of 3, runs PAR omission review on the extractions, then aggregates into per-epic requirement files + behavior scenarios + corpus index. All artifacts go to `docs/superpowers/iterations/`.

Study `spec_to_sprints_yaml_v2.dip` for: parallel fan-out/fan-in syntax, tool nodes with shell scripts, conditional edges with `when ctx.tool_stdout`, `restart: true` for loops, `goal_gate: true` for agent quality gates.

- [ ] **Step 1: Write iter_extract.dip**

Write the complete pipeline file. The workflow structure:

```
workflow IterExtract
  goal: "Extract requirements with proof obligations and behavior scenarios from a spec using chunked parallel extraction with PAR omission review, producing per-epic story files, behavior-scenarios.md, and behavior-corpus.md"
  start: Start
  exit: Exit

  defaults
    model: claude-sonnet-4-6
    provider: anthropic
    max_retries: 3
    max_restarts: 30
```

**Nodes to implement (in this order in the file):**

1. `agent Start` — Acknowledge pipeline start. HARD CONSTRAINT: do not read/write files.
2. `agent Exit` — Acknowledge completion.
3. `agent no_spec_exit` — Report no spec found, list searched filenames.
4. `tool find_spec` — Shell: search for spec.md, SPEC.md, design.md, design-doc.md, specification.md, requirements.md, prompt_plan.md, then `find . -maxdepth 2 -name '*.md'`. Print filename or `no_spec_found`. Timeout 30s.
5. `tool check_extract_resume` — Shell: check if `docs/superpowers/iterations/requirements/` has `.md` files AND `behavior-scenarios.md` exists. Print `resume-validate` if both exist, `resume-aggregate` if temp extractions exist in `.ai/iter-extract-temp/`, `fresh-start` otherwise. Timeout 10s.
6. `agent validate_existing` — Read and validate existing extraction artifacts. Report whether they're complete or need re-extraction. End with `STATUS: success` or `STATUS: fail`.
7. `tool chunk_spec` — Shell: read the spec file found by find_spec. Split by `##` headings. For each section, output a line: `CHUNK|<source_file>|<heading>|<start_line>|<end_line>`. Count total chunks and write to `.ai/iter-extract-temp/chunk_manifest.txt`. Print `chunks-<count>`. Timeout 60s. Create `.ai/iter-extract-temp/` dir. Also write each chunk's content to `.ai/iter-extract-temp/chunk_NNN.md`.

```bash
#!/bin/sh
set -eu
spec_file="$1"
mkdir -p .ai/iter-extract-temp
# Split spec by ## headings, write individual chunk files
awk '
  /^## / {
    if (chunk_num > 0) {
      close(outfile)
    }
    chunk_num++
    outfile = sprintf(".ai/iter-extract-temp/chunk_%03d.md", chunk_num)
    heading = $0
    sub(/^## */, "", heading)
    printf "CHUNK|%s|%s|%d\n", FILENAME, heading, NR > ".ai/iter-extract-temp/chunk_manifest.txt"
  }
  chunk_num > 0 { print > outfile }
  END {
    if (chunk_num == 0) {
      # No ## headings — treat whole file as one chunk
      system("cp " FILENAME " .ai/iter-extract-temp/chunk_001.md")
      printf "CHUNK|%s|whole-file|1\n", FILENAME > ".ai/iter-extract-temp/chunk_manifest.txt"
      chunk_num = 1
    }
    printf "chunks-%d", chunk_num
  }
' "$spec_file"
```

8. `tool count_remaining_chunks` — Shell: count chunk files in `.ai/iter-extract-temp/` that don't have a corresponding `extraction_NNN.json`. Print `remaining-<N>` or `all-extracted`. Timeout 10s.

9. `tool pick_next_wave` — Shell: find the next 3 unprocessed chunk files (no corresponding extraction JSON). Write their paths to `.ai/iter-extract-temp/current_wave.txt`. Print `wave-<start>-<end>` or `no-more`. Timeout 10s.

10. `parallel extract_wave -> extract_agent_1, extract_agent_2, extract_agent_3`

11-13. `agent extract_agent_1`, `extract_agent_2`, `extract_agent_3` — Each reads its assigned chunk from `.ai/iter-extract-temp/current_wave.txt` (agent 1 reads line 1, agent 2 line 2, agent 3 line 3). Model: `claude-sonnet-4-6`. Each agent's prompt:

```
You are extracting testable requirements and behavior scenarios from spec documentation.

Read your assigned chunk file from .ai/iter-extract-temp/current_wave.txt (you are agent [1|2|3], read line [1|2|3] to get your chunk path). Then read that chunk file.

## Your Job

Produce TWO outputs: story cards and scenario cards, as a JSON object.

### Output Format

Write a JSON file to .ai/iter-extract-temp/extraction_<chunk_number>.json with this structure:

{
  "stories": [
    {
      "title": "Short imperative title",
      "epic_theme": "Domain grouping theme",
      "as_a": "actor role",
      "i_want": "capability",
      "so_that": "benefit",
      "acceptance_criteria": [
        {
          "id": "AC-1",
          "text": "Specific testable criterion",
          "behavioral_impact": "none|local|cross-surface|journey",
          "proof_seam": "unit|integration|app-level|process-level|e2e"
        }
      ],
      "sources": [{"file": "source.md", "lines": "10-25"}]
    }
  ],
  "scenarios": [
    {
      "title": "Descriptive scenario title",
      "kind": "surface|journey|failure-recovery|contract",
      "proof_seam": "unit|integration|app-level|process-level|e2e",
      "preconditions": ["precondition"],
      "steps": [{"action": "what happens", "expected": ["observable"]}],
      "final_observables": ["end state"],
      "owning_story_titles": ["title of related story"],
      "sources": [{"file": "source.md", "lines": "10-25"}]
    }
  ]
}

### Rules
- Every AC with behavioral_impact other than "none" MUST have a corresponding scenario
- Journey spec chunks → produce journey scenario chains preserving complete step sequence
- Do NOT assign STORY-NNNN or SCENARIO-NNNN IDs — the aggregator does that
- Do NOT invent requirements not in the spec
- proof_seam: cheapest test level that falsifies the behavior

After writing the JSON file, report what you extracted.

HARD CONSTRAINT: Write ONLY the extraction JSON file. Do NOT modify any other files.
```

14. `fan_in extract_join <- extract_agent_1, extract_agent_2, extract_agent_3`

15. `tool persist_wave` — Shell: verify extraction JSON files were written for current wave chunks. Print `wave-persisted` or `wave-incomplete-<missing>`. Timeout 10s.

16. `parallel par_omission_dispatch -> par_omission_reviewer_a, par_omission_reviewer_b`

17-18. `agent par_omission_reviewer_a`, `par_omission_reviewer_b` — Model: `claude-sonnet-4-6`. Prompt (with PAR competitive wrapper):

```
## Competitive Context

You are Reviewer [A|B]. A parallel reviewer is evaluating the same work right now. You will NOT see each other's findings.

Scoring: whoever finds the greatest number of serious or critical issues wins 5 points.

Rules:
- Findings must be real and justified with file:line references
- Nitpicks don't count toward scoring
- False positives are worse than missing things
- Be thorough — your competitor is being thorough too

---

You are reviewing extraction completeness. Your job is to find requirements and scenarios that the extraction agents DROPPED.

Read the original spec file (find it from .ai/iter-extract-temp/chunk_manifest.txt) and ALL extraction JSON files in .ai/iter-extract-temp/extraction_*.json.

For EACH chunk of the spec, compare the source text against the extracted stories and scenarios. Find every:
- Requirement in the source NOT represented by any extracted story
- Acceptance criterion missing a proof obligation
- Observable behavior with no corresponding scenario
- Journey steps that were summarized or skipped
- Behavioral constraints mentioned but not captured

Score 5 points for each omission found.

## Report Format

**Critical:** (requirements dropped entirely)
- [omission with source file:line reference]

**Serious:** (observable behavior without scenario coverage)
- [omission with source file:line reference]

**Minor:** (proof seam could be stronger)
- [item]

If you found omissions, write patches to .ai/iter-extract-temp/omission_patches_[a|b].json using the same extraction JSON format.

If you found no omissions, say so explicitly.
```

19. `fan_in par_omission_join <- par_omission_reviewer_a, par_omission_reviewer_b`

20. `agent par_omission_aggregate` — Model: `gemini-3-flash-preview`. Provider: gemini. Prompt: Read both PAR reviewer outputs. Aggregate: same omission from both = high confidence, unique = still actionable, severity disagreement = take worst. If patches exist in `omission_patches_a.json` or `omission_patches_b.json`, merge them into the extraction results. End with `STATUS: pass` (no critical omissions) or `STATUS: fail` (critical omissions need re-extraction).

21. `agent aggregate_results` — Model: `claude-sonnet-4-6`. Reasoning effort: high. Goal gate: true. Prompt:

```
Read ALL extraction JSON files in .ai/iter-extract-temp/extraction_*.json (and any omission patch files).

Aggregate into the iterative-development artifact format:

1. STORIES: Combine all stories. Deduplicate by title similarity. Group into epics by epic_theme. Assign stable IDs:
   - EPIC-001, EPIC-002, etc.
   - STORY-0001, STORY-0002, etc. (global, not per-epic)
   Write per-epic files to docs/superpowers/iterations/requirements/EPIC-NNN-<theme>.md

   Each epic file format:
   # EPIC-NNN — <Theme>
   Progress: 0/<total> stories done

   ## STORY-NNNN — <Title>
   **As a** <role>, **I want** <capability>, **so that** <benefit>
   **Acceptance criteria:**
   - AC-1: <text> · impact:<impact> · seam:<seam>
   - AC-2: <text> · impact:<impact> · seam:<seam>
   **Sources:** <file:lines>
   **Status:** pending

2. SCENARIOS: Combine all scenarios. Deduplicate by title. Assign stable IDs:
   - SCENARIO-0001 for surface/contract/failure-recovery
   - JOURNEY-0001 for journey scenarios
   Resolve owning_story_titles to STORY-NNNN IDs.
   Write to docs/superpowers/iterations/behavior-scenarios.md

3. CORPUS: Build behavior-corpus.md table from scenario list.
   Journey scenarios → sentinel cadence. Surface scenarios → iteration cadence.
   Set command to TBD.
   Write to docs/superpowers/iterations/behavior-corpus.md

4. Back-link scenarios to story ACs by appending scenario:<ID> to AC lines.

Create the docs/superpowers/iterations/ and docs/superpowers/iterations/requirements/ directories.

After writing all files, verify:
- Every story has at least one AC
- Every AC with behavioral_impact != "none" has a scenario ref
- Every scenario has owning_stories resolved to STORY IDs
- Behavior corpus has an entry for every scenario

HARD CONSTRAINT: Only write to docs/superpowers/iterations/. Do NOT modify the original spec.
```

22. `tool validate_extraction` — Shell: check that `docs/superpowers/iterations/requirements/` has at least one `.md` file, `behavior-scenarios.md` exists, `behavior-corpus.md` exists. Grep for `STORY-` in requirements dir, `SCENARIO-` or `JOURNEY-` in scenarios file. Print `validation-pass` or `validation-fail-<reason>`. Timeout 15s.

23. `tool commit_extraction` — Shell: `git add docs/superpowers/iterations/ && git commit -m "docs: extract requirements with proof obligations, scenarios, and corpus index"`. Print `committed` or error. Timeout 30s.

**Edges:**

```
edges
  Start -> find_spec
  find_spec -> no_spec_exit             when ctx.tool_stdout = no_spec_found    label: no_spec
  find_spec -> check_extract_resume     when ctx.tool_stdout != no_spec_found   label: spec_found
  find_spec -> check_extract_resume
  no_spec_exit -> Exit
  check_extract_resume -> validate_existing   when ctx.tool_stdout startswith resume-validate  label: resume_validate
  check_extract_resume -> count_remaining_chunks  when ctx.tool_stdout startswith resume-aggregate  label: resume_aggregate
  check_extract_resume -> chunk_spec          when ctx.tool_stdout = fresh-start               label: fresh
  check_extract_resume -> chunk_spec
  validate_existing -> Exit                   when ctx.outcome = success   label: valid
  validate_existing -> chunk_spec             when ctx.outcome = fail      label: invalid
  chunk_spec -> pick_next_wave
  pick_next_wave -> extract_wave              when ctx.tool_stdout startswith wave-   label: has_wave
  pick_next_wave -> par_omission_dispatch     when ctx.tool_stdout = no-more         label: all_extracted
  extract_wave -> extract_agent_1
  extract_wave -> extract_agent_2
  extract_wave -> extract_agent_3
  extract_agent_1 -> extract_join
  extract_agent_2 -> extract_join
  extract_agent_3 -> extract_join
  extract_join -> persist_wave
  persist_wave -> count_remaining_chunks
  count_remaining_chunks -> pick_next_wave       when ctx.tool_stdout startswith remaining-  label: more_chunks    restart: true
  count_remaining_chunks -> par_omission_dispatch  when ctx.tool_stdout = all-extracted      label: done_extracting
  par_omission_dispatch -> par_omission_reviewer_a
  par_omission_dispatch -> par_omission_reviewer_b
  par_omission_reviewer_a -> par_omission_join
  par_omission_reviewer_b -> par_omission_join
  par_omission_join -> par_omission_aggregate
  par_omission_aggregate -> aggregate_results
  aggregate_results -> validate_extraction       when ctx.outcome = success   label: aggregated
  aggregate_results -> Exit                      when ctx.outcome = fail      label: aggregate_failed
  validate_extraction -> commit_extraction       when ctx.tool_stdout = validation-pass    label: valid
  validate_extraction -> aggregate_results       when ctx.tool_stdout startswith validation-fail  label: retry  restart: true
  commit_extraction -> Exit
```

- [ ] **Step 2: Validate the pipeline**

Run: `tracker validate iter_extract.dip`
Expected: validation passes with no errors.

If validation fails, read the error output and fix the syntax issues. Re-validate until clean.

- [ ] **Step 3: Commit**

```bash
git add iter_extract.dip
git commit -m "feat: add iter_extract.dip — requirements extraction with PAR omission review"
```

---

### Task 2: Create `iter_scope.dip`

**Files:**
- Create: `iter_scope.dip`

**Context:** This pipeline reads the extracted requirements and scenarios from `docs/superpowers/iterations/`, defines the walking skeleton (ITER-0000) that closes at least one journey scenario, orders remaining stories into follow-on iterations with story splitting for heterogeneous-dependency ACs, runs PAR scope review, and writes `roadmap.md`.

Study `spec_to_sprints_yaml_v2.dip` for the multi-model decomposition + critique pattern. Study `sprint_runner_yaml_v2.dip` for the subgraph composition and edge conditions.

- [ ] **Step 1: Write iter_scope.dip**

Write the complete pipeline file:

```
workflow IterScope
  goal: "Define walking skeleton (ITER-0000) and ordered iteration roadmap from extracted requirements, with PAR scope review and story splitting for heterogeneous-dependency ACs"
  start: Start
  exit: Exit

  defaults
    model: claude-sonnet-4-6
    provider: anthropic
    max_retries: 3
    max_restarts: 20
```

**Nodes to implement:**

1. `agent Start` — Acknowledge pipeline start.
2. `agent Exit` — Acknowledge completion.
3. `tool check_scope_resume` — Shell: check if `docs/superpowers/iterations/roadmap.md` exists and has `## Walking skeleton` section. Print `has-roadmap` or `no-roadmap`. Also check if requirements dir exists with `.md` files — print `no-requirements` if missing. Timeout 10s.
4. `agent no_requirements_exit` — Report that requirements must be extracted first (run iter_extract.dip).
5. `agent validate_existing_roadmap` — Read existing roadmap.md, check citations against requirements dir, verify format. End with STATUS: success/fail.

6. `agent read_backlog` — Model: `gemini-3-flash-preview`. Provider: gemini. Prompt: Read all epic files in `docs/superpowers/iterations/requirements/` — scan epic headers, story titles, status fields, and AC proof obligations. Also read `docs/superpowers/iterations/behavior-scenarios.md` for scenario coverage. Write a backlog summary to `.ai/iter-scope-temp/backlog_summary.md` listing: total epics, total stories (pending vs done), total scenarios (surface vs journey), and a matrix of which stories have scenario coverage vs which don't. HARD CONSTRAINT: Do NOT modify any files in `docs/superpowers/iterations/`.

7. `agent define_skeleton` — Model: `claude-opus-4-6`. Reasoning effort: high. Goal gate: true. Prompt:

```
You are defining the Walking Skeleton — ITER-0000 — for an iterative development project.

Read:
1. .ai/iter-scope-temp/backlog_summary.md
2. All epic files in docs/superpowers/iterations/requirements/
3. docs/superpowers/iterations/behavior-scenarios.md

## Walking Skeleton Requirements

Select a SMALL cohesive set of stories from as many distinct epics as possible. The skeleton proves the end-to-end shape of the product works.

MANDATORY:
- ITER-0000 MUST include stories that close at least ONE journey scenario chain (JOURNEY-NNNN)
- Prefer the core product journey over edge cases
- The skeleton's FIRST task must be designing and building the E2E test harness
- The skeleton must produce the first sentinel corpus entries

Selection rule: "if someone ran just these stories, they should see a demo that proves the product exists AND have at least one passing journey scenario."

## Output

Write your walking skeleton definition to .ai/iter-scope-temp/skeleton.md:

## Walking Skeleton (ITER-0000)
**Intent:** <one-line description>
**Design rationale:** <why these stories>
**Journey scenario:** <JOURNEY-NNNN that must pass>
**Stories committed:**
- STORY-NNNN (EPIC-NNN) — <title>
**Harness-first task:** Design and build E2E test harness before product features
**Sentinel corpus seeds:** <which scenarios become sentinels>
```

8. `agent order_iterations` — Model: `claude-opus-4-6`. Reasoning effort: high. Goal gate: true. Prompt:

```
You are ordering the remaining stories (not in the walking skeleton) into follow-on iterations.

Read:
1. .ai/iter-scope-temp/skeleton.md (walking skeleton definition)
2. All epic files in docs/superpowers/iterations/requirements/
3. docs/superpowers/iterations/behavior-scenarios.md

## Rules

- Each iteration = a sprint's worth of cohesive work. Granularity is judgment-based.
- STORY SPLITTING: Check each story's ACs for dependency profiles. If some ACs can be satisfied in iteration N but others require subsystems from iteration N+M, SPLIT the story:
  1. Create version with satisfiable ACs for iteration N
  2. Create version with remaining ACs for iteration N+M
  3. Append a/b to the STORY-ID (e.g., STORY-0005a, STORY-0005b)
- Each iteration lists impacted scenarios from behavior-scenarios.md
- Look-ahead: does this iteration block or get blocked by neighbors?

## Output

Write to .ai/iter-scope-temp/iterations.md — one section per iteration:

### ITER-NNNN — <name>
**Stories:** STORY-NNNN, STORY-NNNN
**Rationale:** <why together>
**Impacted scenarios:** SCENARIO-NNNN, JOURNEY-NNNN
**Look-ahead:** <blocks/blocked-by analysis>
**Story splits:** <any stories split, with AC breakdown> or "None"
```

9. `tool check_citations` — Shell: extract all `STORY-NNNN` references from `.ai/iter-scope-temp/skeleton.md` and `.ai/iter-scope-temp/iterations.md`. For each, grep in `docs/superpowers/iterations/requirements/` to verify the ID exists. Print `citations-ok` or `citations-fail-<missing IDs>`. Timeout 15s.

10. `agent fix_citations` — Read citation errors, find the correct story IDs, update skeleton.md and iterations.md.

11. `parallel par_scope_dispatch -> par_scope_reviewer_a, par_scope_reviewer_b`

12-13. `agent par_scope_reviewer_a`, `par_scope_reviewer_b` — Model: `claude-sonnet-4-6`. Prompt (PAR wrapper + scope review):

```
## Competitive Context

You are Reviewer [A|B]. A parallel reviewer is evaluating the same work right now. You will NOT see each other's findings. Score 5 points per serious/critical finding.

---

You are reviewing the scope of the walking skeleton and iteration roadmap BEFORE any code is written.

Read:
1. .ai/iter-scope-temp/skeleton.md
2. .ai/iter-scope-temp/iterations.md
3. docs/superpowers/iterations/requirements/ (all epic files)
4. docs/superpowers/iterations/behavior-scenarios.md

## Your Five Checks

### 1. Citation Integrity
Every committed story cites a valid STORY-NNNN from the requirements directory. Do the stories actually mean what the spec says? (Semantic check, not just ID existence.)

### 2. Scope Creep
Is ITER-0000 trying to do too much? Could any story be deferred without breaking the skeleton? Are follow-on iterations well-bounded?

### 3. Boxing-In Look-Ahead
Would ITER-0000's design approach block ITER-0001, 0002, or 0003? Does any iteration introduce hard coupling, premature abstraction, or structural commitments that would need undoing?

### 4. Scenario Coverage
Does any iteration leave externally observable behavior without planned scenario coverage? Does ITER-0000 close at least one JOURNEY scenario?

### 5. Story Splitting
Are there stories with heterogeneous-dependency ACs scoped whole into one iteration? If ACs have different dependency profiles, they should be split.

## Report Format
- **Citation Integrity:** PASS | issues
- **Scope Creep:** PASS | recommendations
- **Boxing-In:** PASS | risks with specific downstream iterations
- **Scenario Coverage:** PASS | observable behavior without scenarios
- **Story Splitting:** PASS | stories to split with AC breakdown

Overall: APPROVE | REVISE — with specific changes needed
```

14. `fan_in par_scope_join <- par_scope_reviewer_a, par_scope_reviewer_b`

15. `agent par_scope_aggregate` — Model: `gemini-3-flash-preview`. Provider: gemini. Aggregate PAR findings. End with `STATUS: pass` (APPROVE) or `STATUS: fail` (REVISE with specifics).

16. `agent adjust_scope` — Read scope review findings. Adjust skeleton.md and iterations.md to address issues. Apply any recommended story splits by updating requirements/ files too.

17. `agent write_roadmap` — Model: `claude-sonnet-4-6`. Goal gate: true. Prompt: Read `.ai/iter-scope-temp/skeleton.md` and `.ai/iter-scope-temp/iterations.md`. Write `docs/superpowers/iterations/roadmap.md` in this format:

```
# Roadmap

## Walking skeleton (ITER-0000)

**Intent:** <one-line>
**Design rationale:** <why>
**Journey scenario:** JOURNEY-NNNN
**Stories committed:**
- STORY-NNNN (EPIC-NNN)
**Status:** pending

## Iteration list

### ITER-0001 — <name>
**Stories:** STORY-NNNN, STORY-NNNN
**Rationale:** <why together>
**Status:** pending
**Impacted scenarios:** SCENARIO-NNNN, JOURNEY-NNNN
**Look-ahead check:** <blocks/blocked-by>
```

If story splits were applied, also update the affected epic files in requirements/ to reflect the split stories.

18. `tool validate_roadmap` — Shell: check roadmap.md has `## Walking skeleton`, at least one `### ITER-` section, every section has `**Status:**`. Grep for `STORY-` references. Print `roadmap-valid` or `roadmap-invalid-<reason>`. Timeout 10s.

19. `tool commit_roadmap` — Shell: `git add docs/superpowers/iterations/ && git commit -m "docs: add roadmap — walking skeleton with journey scenario + iteration plan"`. Timeout 30s.

**Edges:**

```
edges
  Start -> check_scope_resume
  check_scope_resume -> no_requirements_exit    when ctx.tool_stdout = no-requirements     label: no_reqs
  check_scope_resume -> validate_existing_roadmap  when ctx.tool_stdout = has-roadmap      label: has_roadmap
  check_scope_resume -> read_backlog            when ctx.tool_stdout = no-roadmap          label: fresh
  check_scope_resume -> read_backlog
  no_requirements_exit -> Exit
  validate_existing_roadmap -> Exit             when ctx.outcome = success   label: valid
  validate_existing_roadmap -> read_backlog     when ctx.outcome = fail      label: invalid
  read_backlog -> define_skeleton
  define_skeleton -> order_iterations           when ctx.outcome = success   label: skeleton_defined
  define_skeleton -> Exit                       when ctx.outcome = fail      label: skeleton_failed
  order_iterations -> check_citations           when ctx.outcome = success   label: ordered
  order_iterations -> Exit                      when ctx.outcome = fail      label: ordering_failed
  check_citations -> par_scope_dispatch         when ctx.tool_stdout = citations-ok         label: citations_ok
  check_citations -> fix_citations              when ctx.tool_stdout startswith citations-fail  label: citations_bad
  fix_citations -> check_citations              restart: true
  par_scope_dispatch -> par_scope_reviewer_a
  par_scope_dispatch -> par_scope_reviewer_b
  par_scope_reviewer_a -> par_scope_join
  par_scope_reviewer_b -> par_scope_join
  par_scope_join -> par_scope_aggregate
  par_scope_aggregate -> write_roadmap          when ctx.outcome = success   label: approved
  par_scope_aggregate -> adjust_scope           when ctx.outcome = fail      label: revise
  adjust_scope -> check_citations               restart: true
  write_roadmap -> validate_roadmap             when ctx.outcome = success   label: written
  write_roadmap -> Exit                         when ctx.outcome = fail      label: write_failed
  validate_roadmap -> commit_roadmap            when ctx.tool_stdout = roadmap-valid        label: valid
  validate_roadmap -> write_roadmap             when ctx.tool_stdout startswith roadmap-invalid  label: invalid  restart: true
  commit_roadmap -> Exit
```

- [ ] **Step 2: Validate the pipeline**

Run: `tracker validate iter_scope.dip`
Expected: validation passes.

- [ ] **Step 3: Commit**

```bash
git add iter_scope.dip
git commit -m "feat: add iter_scope.dip — walking skeleton + roadmap with PAR scope review"
```

---

### Task 3: Create `iter_audit.dip`

**Files:**
- Create: `iter_audit.dip`

**Context:** This pipeline runs after each iteration. It performs a three-tier PAR audit: (1) deep evidence for current iteration's stories, (2) impacted behavior for all scenarios whose stories had code changes, (3) sentinel corpus regression check. Outputs either "clean" or "gaps" to stdout for the orchestrator to read.

- [ ] **Step 1: Write iter_audit.dip**

```
workflow IterAudit
  goal: "Three-tier PAR audit verifying behavior evidence quality: deep evidence for current iteration, impacted behavior for touched scenarios, sentinel corpus regression check"
  start: Start
  exit: Exit

  defaults
    model: claude-sonnet-4-6
    provider: anthropic
    max_retries: 3
    max_restarts: 20
```

**Nodes to implement:**

1. `agent Start` — Acknowledge audit start.
2. `agent Exit` — Acknowledge audit completion.

3. `tool read_iteration_state` — Shell: read `.ai/iter-current-iteration.txt` for the current iteration ID. Read `docs/superpowers/iterations/roadmap.md` to find stories committed to this iteration. Check that `docs/superpowers/iterations/requirements/` and `behavior-scenarios.md` exist. Check for `.ai/iter-sentinel-baseline.txt` (pre-iteration baseline). Print `state-ready-ITER-<id>` or `state-missing-<what>`. Timeout 15s.

4. `agent no_state_exit` — Report missing state: what files are needed and how to produce them.

5. `parallel par_tier1_dispatch -> par_tier1_auditor_a, par_tier1_auditor_b`

6-7. `agent par_tier1_auditor_a`, `par_tier1_auditor_b` — Model: `claude-sonnet-4-6`. Reasoning effort: high. Prompt (PAR wrapper + tier 1 deep evidence):

```
## Competitive Context

You are Reviewer [A|B]. Score 5 points per serious/critical finding.

---

## Tier 1: Deep Evidence Audit

Read .ai/iter-current-iteration.txt to get the current iteration ID.

Read the roadmap to identify stories marked done:ITER-<current>. For each story, read its full story card from the requirements directory.

Read docs/superpowers/iterations/behavior-scenarios.md for scenarios added or updated this iteration.

For EACH story marked done in this iteration:
1. Read every acceptance criterion and its proof obligation
2. Find the tests and code that claim to implement each AC
3. Run the test commands if available
4. Verify each AC is actually met — not just that tests pass, but that tests actually TEST what the AC requires
5. For each AC with behavioral_impact != "none":
   - Verify a scenario exists at the declared proof seam
   - Verify the scenario test proves observable behavior
   - Verify evidence is at the correct seam (not weaker)
   - REJECT: unit-only evidence for app-level behavior
   - REJECT: code inspection without test evidence
6. Check behavior-corpus.md has entries for new scenarios

Also scan git diff for: unrequested features, commented-out code, observable behavior without corpus update.

## Report Format

### Tier 1: Deep Evidence
For each story:
- STORY-NNNN: PASS | FAIL
  - AC-1: PASS | FAIL — explanation
  - Evidence: ADEQUATE | WEAK — seam analysis

Unrequested features: list or "none"
Observable behavior without corpus: list or "none"
```

8. `fan_in par_tier1_join <- par_tier1_auditor_a, par_tier1_auditor_b`

9. `agent par_tier1_aggregate` — Model: `gemini-3-flash-preview`. Provider: gemini. Aggregate tier 1 PAR findings. Write to `.ai/iter-audit-temp/tier1_findings.md`. End with `STATUS: pass` or `STATUS: fail`.

10. `parallel par_tier2_dispatch -> par_tier2_auditor_a, par_tier2_auditor_b`

11-12. `agent par_tier2_auditor_a`, `par_tier2_auditor_b` — Model: `claude-sonnet-4-6`. Prompt (PAR wrapper + tier 2 impacted behavior): read behavior-scenarios.md, identify scenarios whose owning stories had code changes this iteration. Verify scenario tests still pass, check if scenarios need updating.

13. `fan_in par_tier2_join <- par_tier2_auditor_a, par_tier2_auditor_b`

14. `agent par_tier2_aggregate` — Gemini flash. Aggregate tier 2. Write to `.ai/iter-audit-temp/tier2_findings.md`. STATUS: pass/fail.

15. `parallel par_tier3_dispatch -> par_tier3_auditor_a, par_tier3_auditor_b`

16-17. `agent par_tier3_auditor_a`, `par_tier3_auditor_b` — Model: `claude-sonnet-4-6`. Prompt (PAR wrapper + tier 3 sentinel): read `.ai/iter-sentinel-baseline.txt` for pre-iteration results. Run all sentinel scenario commands from behavior-corpus.md. Compare. Regression (passed before, fails now) = CRITICAL.

18. `fan_in par_tier3_join <- par_tier3_auditor_a, par_tier3_auditor_b`

19. `agent par_tier3_aggregate` — Gemini flash. Aggregate tier 3. Write to `.ai/iter-audit-temp/tier3_findings.md`. STATUS: pass/fail.

20. `agent synthesize_audit` — Model: `claude-opus-4-6`. Reasoning effort: high. Prompt: Read all three tier findings files. Determine overall verdict:
- ALL tiers pass → CLEAN
- ANY tier fails → GAPS FOUND
For gaps: specify what gap stories to create. End with exactly `STATUS: success` (clean) or `STATUS: fail` (gaps).

21. `agent write_gap_stories` — Model: `claude-sonnet-4-6`. Prompt: Read audit synthesis. For AC failures → append gap stories to requirements/ (status pending). For weak evidence → create evidence-improvement stories. For sentinel regressions → create CRITICAL regression-fix stories. Update roadmap.md to add a follow-up iteration. Write `.ai/iter-audit-result.txt` with `gaps`.

22. `tool commit_gaps` — Shell: `git add docs/superpowers/iterations/ && git commit -m "docs: add gap stories from iteration audit"`. Timeout 30s.

23. `tool report_gaps` — Shell: `printf 'gaps'`. Timeout 5s.

24. `tool report_clean` — Shell: `printf 'clean'`. Timeout 5s.

**Edges:**

```
edges
  Start -> read_iteration_state
  read_iteration_state -> no_state_exit          when ctx.tool_stdout startswith state-missing  label: no_state
  read_iteration_state -> par_tier1_dispatch     when ctx.tool_stdout startswith state-ready    label: ready
  read_iteration_state -> par_tier1_dispatch
  no_state_exit -> Exit
  par_tier1_dispatch -> par_tier1_auditor_a
  par_tier1_dispatch -> par_tier1_auditor_b
  par_tier1_auditor_a -> par_tier1_join
  par_tier1_auditor_b -> par_tier1_join
  par_tier1_join -> par_tier1_aggregate
  par_tier1_aggregate -> par_tier2_dispatch
  par_tier2_dispatch -> par_tier2_auditor_a
  par_tier2_dispatch -> par_tier2_auditor_b
  par_tier2_auditor_a -> par_tier2_join
  par_tier2_auditor_b -> par_tier2_join
  par_tier2_join -> par_tier2_aggregate
  par_tier2_aggregate -> par_tier3_dispatch
  par_tier3_dispatch -> par_tier3_auditor_a
  par_tier3_dispatch -> par_tier3_auditor_b
  par_tier3_auditor_a -> par_tier3_join
  par_tier3_auditor_b -> par_tier3_join
  par_tier3_join -> par_tier3_aggregate
  par_tier3_aggregate -> synthesize_audit
  synthesize_audit -> report_clean              when ctx.outcome = success   label: clean
  synthesize_audit -> write_gap_stories         when ctx.outcome = fail      label: gaps_found
  write_gap_stories -> commit_gaps
  commit_gaps -> report_gaps
  report_gaps -> Exit
  report_clean -> Exit
```

- [ ] **Step 2: Validate the pipeline**

Run: `tracker validate iter_audit.dip`
Expected: validation passes.

- [ ] **Step 3: Commit**

```bash
git add iter_audit.dip
git commit -m "feat: add iter_audit.dip — three-tier PAR audit with gap story generation"
```

---

### Task 4: Create `iter_run.dip`

**Files:**
- Create: `iter_run.dip`

**Context:** This is the most complex pipeline. It executes one iteration from the roadmap: find next pending iteration → sentinel baseline → consistency audit → PAR scope review → decompose into TDD tasks → per-task loop (implement → PAR spec-compliance → PAR code-quality → mark done) → post-iteration scenario runs → TODO resolution → wrap-up.

The per-task loop uses `restart: true` edges. The two-stage PAR review (spec-compliance MUST pass before code-quality) is enforced by graph topology.

Study `sprint_exec_yaml_v2.dip` for: the implementation agent pattern, ledger management via tool nodes, scope fence checking, commit workflow. Study `sprint_runner_yaml_v2.dip` for: the loop-back pattern via restart edges.

- [ ] **Step 1: Write iter_run.dip**

```
workflow IterRun
  goal: "Execute one iteration from the roadmap: sentinel baseline, PAR scope review, TDD task decomposition, per-task implementation with two-stage PAR review (spec-compliance then code-quality), post-iteration scenario runs, and artifact wrap-up"
  start: Start
  exit: Exit

  defaults
    model: claude-sonnet-4-6
    provider: anthropic
    max_retries: 3
    max_restarts: 50
    fidelity: summary:medium
```

**Nodes to implement (grouped by flow phase):**

**PHASE: Setup**

1. `agent Start` — Acknowledge pipeline start.
2. `agent Exit` — Acknowledge completion.
3. `tool find_next_iteration` — Shell: read `docs/superpowers/iterations/roadmap.md`. Find first iteration with `**Status:** pending`. Extract iteration ID (ITER-NNNN). Write to `.ai/iter-current-iteration.txt`. Print `next-ITER-<id>` or `all-done`. Timeout 15s.
4. `agent all_done_exit` — All iterations completed. Report status.

**PHASE: Pre-iteration**

5. `agent load_scope` — Model: `gemini-3-flash-preview`. Provider: gemini. Read the current iteration from roadmap, load committed stories from requirements/, load behavior-scenarios.md and behavior-corpus.md. Write a scope summary to `.ai/iter-run-temp/scope.md`. HARD CONSTRAINT: read-only, do not modify artifacts.

6. `tool run_sentinel_baseline` — Shell: read `docs/superpowers/iterations/behavior-corpus.md`, extract all rows with `sentinel` cadence. For each, if the Command column is not `TBD`, run it and record pass/fail. Write results to `.ai/iter-sentinel-baseline.txt`. Print `baseline-<pass>-of-<total>-sentinels`. Timeout 300s.

7. `tool consistency_audit` — Shell: extract all STORY-NNNN IDs from the current iteration in roadmap.md. For each, grep in requirements/ to verify it exists and is not already `done:ITER-<other>` (unless code actually exists). Print `consistent` or `inconsistent-<details>`. Timeout 15s.

8. `agent reconcile_state` — Fix inconsistencies found by consistency_audit. Update requirements/ or roadmap.md as needed.

**PHASE: PAR Scope Review**

9. `parallel par_run_scope_dispatch -> par_run_scope_reviewer_a, par_run_scope_reviewer_b`

10-11. `agent par_run_scope_reviewer_a`, `par_run_scope_reviewer_b` — Model: `claude-sonnet-4-6`. Same PAR scope review prompt as iter_scope (5 checks: citation integrity, scope creep, boxing-in, scenario coverage, story splitting) but scoped to THIS iteration specifically. Read `.ai/iter-run-temp/scope.md` for context.

12. `fan_in par_run_scope_join <- par_run_scope_reviewer_a, par_run_scope_reviewer_b`

13. `agent par_run_scope_aggregate` — Gemini flash. Aggregate. STATUS: pass (APPROVE) / fail (REVISE).

14. `agent adjust_run_scope` — Address scope review findings. Update iteration scope in roadmap if needed.

**PHASE: Task Decomposition**

15. `agent decompose_tasks` — Model: `claude-opus-4-6`. Reasoning effort: high. Goal gate: true. Prompt:

```
You are decomposing an iteration into TDD-sized tasks.

Read:
1. .ai/iter-run-temp/scope.md (iteration scope with committed stories)
2. The full story cards from docs/superpowers/iterations/requirements/
3. docs/superpowers/iterations/behavior-scenarios.md
4. docs/superpowers/iterations/behavior-corpus.md

## Decomposition Rules

Break the iteration into tasks. Each task = one TDD cycle: failing test → implementation → passing test → commit.

INTERLEAVE evidence tasks with code tasks: after implementing a feature, the next task should extend or add the scenario that proves it.

For cross-iteration dependencies: implement the thinnest abstraction boundary that satisfies the story's ACs without coupling to the future implementation. Add a TODO(ITER-NNNN) comment citing the future iteration.

## Output

Write the task list to .ai/iter-run-temp/tasks.md:

### TASK-01: <name>
**Story:** STORY-NNNN
**Type:** code | evidence
**ACs covered:** AC-1, AC-2
**Proof obligations:**
- AC-1: seam=<seam>, scenario=<SCENARIO-NNNN|new>
**Files to create/modify:** <list>
**TDD cycle:**
1. Write failing test: <what to test>
2. Implement: <what to build>
3. Verify: <command>
4. Scenario update: <what to add/change in behavior-scenarios.md>

Also write a task status tracker to .ai/iter-run-temp/task_status.txt with one line per task: `TASK-NN|pending`
```

16. `tool mark_iteration_in_progress` — Shell: update the current iteration's status in roadmap.md from `pending` to `in_progress` using sed. Timeout 10s.

17. `tool update_progress` — Shell: write `docs/superpowers/iterations/progress.md` with current phase, task count, iteration info. Timeout 5s.

**PHASE: Per-Task Loop**

18. `tool read_next_task` — Shell: read `.ai/iter-run-temp/task_status.txt`. Find first line with `|pending`. Print `task-TASK-<NN>` or `all-tasks-done`. Timeout 5s.

19. `tool mark_task_in_progress` — Shell: update the current task status to `in_progress` in task_status.txt. Timeout 5s.

20. `agent implement_task` — Model: `claude-sonnet-4-6`. Reasoning effort: high. Fidelity: summary:high. The core implementation agent. Prompt:

```
You are implementing a single task as part of an iterative development sprint.

Read .ai/iter-run-temp/task_status.txt to find the current in_progress task number.
Then read .ai/iter-run-temp/tasks.md and find that task's full description.
Also read the relevant story cards from docs/superpowers/iterations/requirements/.

## Engineering Principles

- Earn every abstraction. No wrappers just for testability.
- Work with the platform. Use native idioms.
- Navigability matters. Organize by domain.
- Decompose coordination. No god objects.

## Before You Begin — Pre-Flight Mapping

State:
1. Which ACs affect externally observable behavior
2. What proof seam each observable AC requires
3. Which existing scenario you will extend, OR what new scenario you will add
4. What test command will prove the behavior

If the task changes observable behavior and you cannot identify a scenario, STOP and report NEEDS_CONTEXT.

## Your Job

1. State pre-flight mapping
2. Follow TDD red-green-refactor:
   - NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
   - Write the failing test. Run it. Verify it fails for the RIGHT reason.
   - Write minimal code to pass. Run tests. All green.
   - Refactor while green.
3. If observable behavior changed: update behavior-scenarios.md and behavior-corpus.md
4. Commit with a clear message
5. Self-review:
   - Did I implement exactly what was specified?
   - Did I follow TDD? (test before implementation)
   - Do tests verify real behavior, not mock behavior?
   - Did I update the behavior corpus for every observable AC?
   - Is evidence at the correct proof seam?
   - Could any abstraction I added be removed without losing coverage?

After self-review, end with exactly one of:
  STATUS: success  (DONE — all ACs met, tests pass, evidence adequate)
  STATUS: fail     (BLOCKED or NEEDS_CONTEXT — explain what's missing)

HARD CONSTRAINT: Implement ONLY the current task. Do NOT implement future tasks. Do NOT modify .ai/ files other than task_status.txt updates. Do NOT read generated directories (node_modules, dist, build, .next).
```

21. `agent provide_context` — When implementer reports NEEDS_CONTEXT: read the request, find the missing info from requirements/scenarios/codebase, re-dispatch context.

22. `agent escalate_task` — When implementer is BLOCKED: assess whether to break the task smaller, try a more capable model, or flag for human review. Update tasks.md if splitting.

**PHASE: PAR Spec-Compliance Review (Stage 1)**

23. `parallel par_spec_dispatch -> par_spec_reviewer_a, par_spec_reviewer_b`

24-25. `agent par_spec_reviewer_a`, `par_spec_reviewer_b` — Model: `claude-sonnet-4-6`. Prompt (PAR wrapper + spec-compliance):

```
## Competitive Context

You are Reviewer [A|B]. Score 5 points per serious/critical finding.

---

You are reviewing whether an implementation matches its specification AND whether behavior evidence exists at the correct seam.

Read .ai/iter-run-temp/task_status.txt to find the current task. Read the task description from .ai/iter-run-temp/tasks.md. Read the relevant story cards from requirements/.

## CRITICAL: Do Not Trust the Implementer's Report

Verify everything by reading actual code:
- Everything requested actually implemented?
- Requirements skipped or misunderstood?
- Features built that weren't requested?
- Requirements interpreted differently than intended?

## Evidence Quality

For each AC with behavioral_impact != "none":
- Does a scenario exist covering this AC?
- Is evidence at the declared proof seam (not weaker)?
- Does the test prove observable behavior?
- REJECT: unit-only evidence for app-level behavior
- REJECT: no scenario for changed observable behavior

## Report Format

**Spec Compliance:** ✅ Compliant | ❌ Issues: [list with file:line]
**Evidence Quality:** ✅ Adequate | ❌ Weak: [list with seam analysis]

Overall: ✅ Spec compliant with adequate evidence | ❌ Issues found: [list]
```

26. `fan_in par_spec_join <- par_spec_reviewer_a, par_spec_reviewer_b`

27. `agent par_spec_aggregate` — Gemini flash. Aggregate. Write to `.ai/iter-run-temp/spec_review.md`. STATUS: pass/fail.

28. `agent fix_spec_issues` — Read aggregated spec review findings. Fix the issues — modify code, add tests, update scenarios. Commit fixes. End with STATUS: success/fail.

**PHASE: PAR Code-Quality Review (Stage 2)**

29. `parallel par_quality_dispatch -> par_quality_reviewer_a, par_quality_reviewer_b`

30-31. `agent par_quality_reviewer_a`, `par_quality_reviewer_b` — Model: `claude-sonnet-4-6`. Prompt (PAR wrapper + code-quality):

```
## Competitive Context

You are Reviewer [A|B]. Score 5 points per serious/critical finding.

---

You are reviewing code quality, architectural soundness, and behavior corpus contribution.

Read the current task from .ai/iter-run-temp/tasks.md. Read the code changes via git diff.

Also read the next 3 pending iterations from docs/superpowers/iterations/roadmap.md for boxing-in check.

### Code Quality
- Clean and maintainable? Clear domain-appropriate names?
- Dead code or unused imports? Tests testing real behavior?
- Each file one clear responsibility?

### Engineering Health
- Abstraction justification: Do abstractions serve the product or just the test harness? SERIOUS if unjustified.
- Platform fit: Working with native idioms or fighting them? SERIOUS if fighting.
- Navigability: Can someone unfamiliar find things by domain?
- Coordination creep: Single file accumulating knowledge of every subsystem? SERIOUS.

### Boxing-In Check
Given the next 3 pending iterations: does this code introduce hard coupling, hardcoded values, or interface commitments that would block downstream? CRITICAL if specific downstream iteration blocked.

### Corpus Contribution Quality
If scenarios were added/updated: clearly written? Reusable? Prove observable behavior? Correct proof seam? Could survive a refactor?

## Report Format

**Strengths:** [brief list]
**Issues:** Critical / Serious / Minor with file:line refs
**Boxing-In:** CLEAR | RISK with downstream iterations
**Corpus Quality:** GOOD | WEAK with issues

Overall: ✅ Approved | ❌ Changes needed
```

32. `fan_in par_quality_join <- par_quality_reviewer_a, par_quality_reviewer_b`

33. `agent par_quality_aggregate` — Gemini flash. Aggregate. Write to `.ai/iter-run-temp/quality_review.md`. STATUS: pass/fail.

34. `agent fix_quality_issues` — Read aggregated quality findings. Fix issues. Commit. STATUS: success/fail.

**PHASE: Task Completion**

35. `tool mark_task_done` — Shell: update current task status to `done` in task_status.txt. Print `task-done`. Timeout 5s.

36. `tool update_task_progress` — Shell: count done/total in task_status.txt. Write progress.md. Print `progress-<done>-of-<total>`. Timeout 5s.

**PHASE: Post-Iteration**

37. `tool run_impacted_scenarios` — Shell: identify scenarios whose owning stories were in this iteration. Run their execution commands from behavior-corpus.md. Print `impacted-<pass>-of-<total>` or `impacted-all-tbd` (if commands are TBD). Timeout 300s.

38. `tool run_sentinel_scenarios` — Shell: run all sentinel scenarios from behavior-corpus.md. Compare with `.ai/iter-sentinel-baseline.txt`. Print `sentinel-pass` or `sentinel-regression-<IDs>`. Timeout 300s.

39. `agent create_fix_task` — When regression detected: create a fix task in tasks.md, reset task loop. End with STATUS: success.

40. `tool resolve_todos` — Shell: `grep -rn "TODO(ITER-$(cat .ai/iter-current-iteration.txt))" --include='*.py' --include='*.ts' --include='*.go' --include='*.rs' --include='*.swift' --include='*.js' . 2>/dev/null | grep -v node_modules | grep -v .ai/`. Print `todos-clean` or `todos-unresolved-<count>`. Timeout 15s.

**PHASE: Wrap-Up**

41. `agent wrap_up` — Model: `claude-sonnet-4-6`. Goal gate: true. Prompt: Read task results, update artifacts:
- Mark stories `done:ITER-<current>` in requirements/ epic files
- Update scenario status and commands in behavior-scenarios.md
- Update behavior-corpus.md execution commands
- Update iteration status to `done` in roadmap.md
- Append entry to docs/superpowers/iterations/iteration-log.md
- Write final progress.md snapshot
HARD CONSTRAINT: Only modify files in docs/superpowers/iterations/.

42. `tool validate_wrap_up` — Shell: verify iteration status is `done` in roadmap.md, iteration-log.md has an entry for current iteration. Print `wrapup-valid` or `wrapup-invalid-<reason>`. Timeout 10s.

43. `tool commit_iteration` — Shell: `git add docs/superpowers/iterations/ && git commit -m "docs: complete ITER-$(cat .ai/iter-current-iteration.txt) — update artifacts and iteration log"`. Timeout 30s.

**Edges (this is the most complex edge set):**

```
edges
  # Setup
  Start -> find_next_iteration
  find_next_iteration -> all_done_exit          when ctx.tool_stdout = all-done              label: all_done
  find_next_iteration -> load_scope             when ctx.tool_stdout startswith next-         label: found
  find_next_iteration -> load_scope
  all_done_exit -> Exit

  # Pre-iteration
  load_scope -> run_sentinel_baseline
  run_sentinel_baseline -> consistency_audit
  consistency_audit -> par_run_scope_dispatch    when ctx.tool_stdout = consistent            label: consistent
  consistency_audit -> reconcile_state           when ctx.tool_stdout startswith inconsistent  label: inconsistent
  reconcile_state -> consistency_audit           restart: true

  # PAR scope review
  par_run_scope_dispatch -> par_run_scope_reviewer_a
  par_run_scope_dispatch -> par_run_scope_reviewer_b
  par_run_scope_reviewer_a -> par_run_scope_join
  par_run_scope_reviewer_b -> par_run_scope_join
  par_run_scope_join -> par_run_scope_aggregate
  par_run_scope_aggregate -> decompose_tasks     when ctx.outcome = success   label: scope_approved
  par_run_scope_aggregate -> adjust_run_scope    when ctx.outcome = fail      label: scope_revise
  adjust_run_scope -> par_run_scope_dispatch     restart: true

  # Task decomposition
  decompose_tasks -> mark_iteration_in_progress  when ctx.outcome = success   label: decomposed
  decompose_tasks -> Exit                        when ctx.outcome = fail      label: decompose_failed
  mark_iteration_in_progress -> update_progress
  update_progress -> read_next_task

  # Per-task loop
  read_next_task -> mark_task_in_progress        when ctx.tool_stdout startswith task-        label: has_task
  read_next_task -> run_impacted_scenarios        when ctx.tool_stdout = all-tasks-done       label: tasks_done
  mark_task_in_progress -> implement_task
  implement_task -> par_spec_dispatch            when ctx.outcome = success   label: implemented
  implement_task -> provide_context              when ctx.outcome = fail      label: needs_help
  provide_context -> implement_task              restart: true
  escalate_task -> read_next_task                restart: true

  # PAR spec-compliance (Stage 1)
  par_spec_dispatch -> par_spec_reviewer_a
  par_spec_dispatch -> par_spec_reviewer_b
  par_spec_reviewer_a -> par_spec_join
  par_spec_reviewer_b -> par_spec_join
  par_spec_join -> par_spec_aggregate
  par_spec_aggregate -> par_quality_dispatch     when ctx.outcome = success   label: spec_pass
  par_spec_aggregate -> fix_spec_issues          when ctx.outcome = fail      label: spec_fail
  fix_spec_issues -> par_spec_dispatch           when ctx.outcome = success   restart: true  label: spec_fixed
  fix_spec_issues -> escalate_task               when ctx.outcome = fail      label: spec_stuck

  # PAR code-quality (Stage 2)
  par_quality_dispatch -> par_quality_reviewer_a
  par_quality_dispatch -> par_quality_reviewer_b
  par_quality_reviewer_a -> par_quality_join
  par_quality_reviewer_b -> par_quality_join
  par_quality_join -> par_quality_aggregate
  par_quality_aggregate -> mark_task_done        when ctx.outcome = success   label: quality_pass
  par_quality_aggregate -> fix_quality_issues    when ctx.outcome = fail      label: quality_fail
  fix_quality_issues -> par_quality_dispatch     when ctx.outcome = success   restart: true  label: quality_fixed
  fix_quality_issues -> escalate_task            when ctx.outcome = fail      label: quality_stuck

  # Task completion → loop
  mark_task_done -> update_task_progress
  update_task_progress -> read_next_task         restart: true

  # Post-iteration
  run_impacted_scenarios -> run_sentinel_scenarios
  run_sentinel_scenarios -> resolve_todos        when ctx.tool_stdout = sentinel-pass         label: sentinel_ok
  run_sentinel_scenarios -> create_fix_task      when ctx.tool_stdout startswith sentinel-regression  label: regression
  create_fix_task -> read_next_task              restart: true
  resolve_todos -> wrap_up                       when ctx.tool_stdout = todos-clean           label: todos_ok
  resolve_todos -> create_fix_task               when ctx.tool_stdout startswith todos-unresolved  label: todos_remain

  # Wrap-up
  wrap_up -> validate_wrap_up                    when ctx.outcome = success   label: wrapped
  wrap_up -> Exit                                when ctx.outcome = fail      label: wrapup_failed
  validate_wrap_up -> commit_iteration           when ctx.tool_stdout = wrapup-valid          label: valid
  validate_wrap_up -> wrap_up                    when ctx.tool_stdout startswith wrapup-invalid  label: invalid  restart: true
  commit_iteration -> Exit
```

- [ ] **Step 2: Validate the pipeline**

Run: `tracker validate iter_run.dip`
Expected: validation passes. This is the largest pipeline — pay attention to edge coverage (every node must be reachable, every edge target must exist).

- [ ] **Step 3: Commit**

```bash
git add iter_run.dip
git commit -m "feat: add iter_run.dip — iteration execution with TDD tasks and two-stage PAR review"
```

---

### Task 5: Create `iter_dev.dip`

**Files:**
- Create: `iter_dev.dip`

**Context:** This is the top-level orchestrator. It composes the other 4 pipelines via `subgraph ref:` and drives the bootstrap → main loop → final audit lifecycle. The loop uses `restart: true` edges.

Study `sprint_runner_yaml_v2.dip` for the exact `subgraph ref:` syntax and loop pattern.

- [ ] **Step 1: Write iter_dev.dip**

```
workflow IterDev
  goal: "Autonomous iterative development lifecycle: bootstrap (extract requirements + scope roadmap), then loop (run iteration + audit) until behavior evidence is clean for every externally observable requirement"
  start: Start
  exit: Exit

  defaults
    model: claude-sonnet-4-6
    provider: anthropic
    max_retries: 3
    max_restarts: 100
```

**Nodes to implement:**

1. `agent Start` — Acknowledge pipeline start. Report what iterative development does.
2. `agent Exit` — Report final status.

3. `tool check_resume` — Shell: comprehensive state check. Print one of: `fresh` (no artifacts), `resume-run` (has roadmap with pending iterations), `resume-final` (all iterations done), `resume-in-progress` (iteration in progress — treat as resume-run). Timeout 15s.

```bash
#!/bin/sh
set -eu
iter_dir="docs/superpowers/iterations"
if [ ! -d "$iter_dir" ]; then
  printf 'fresh'
  exit 0
fi
if [ ! -d "$iter_dir/requirements" ] || [ -z "$(ls $iter_dir/requirements/*.md 2>/dev/null)" ]; then
  printf 'fresh'
  exit 0
fi
if [ ! -f "$iter_dir/roadmap.md" ]; then
  printf 'needs-scope'
  exit 0
fi
pending=$(grep -c '^\*\*Status:\*\* pending' "$iter_dir/roadmap.md" 2>/dev/null || echo 0)
in_progress=$(grep -c '^\*\*Status:\*\* in_progress' "$iter_dir/roadmap.md" 2>/dev/null || echo 0)
done_count=$(grep -c '^\*\*Status:\*\* done' "$iter_dir/roadmap.md" 2>/dev/null || echo 0)
if [ "$pending" -gt 0 ] || [ "$in_progress" -gt 0 ]; then
  printf 'resume-run-pending-%s-inprogress-%s-done-%s' "$pending" "$in_progress" "$done_count"
  exit 0
fi
if [ -f "$iter_dir/.final-audit-clean" ]; then
  printf 'already-complete'
  exit 0
fi
printf 'resume-final-done-%s' "$done_count"
```

4. `subgraph bootstrap_extract` — `ref: iter_extract.dip`
5. `subgraph bootstrap_scope` — `ref: iter_scope.dip`
6. `subgraph run_iteration` — `ref: iter_run.dip`
7. `subgraph audit_iteration` — `ref: iter_audit.dip`

8. `tool check_termination` — Shell: read roadmap.md status counts. Check for `.ai/iter-audit-result.txt`. Print `more-iterations` (pending/in-progress exist), `ready-for-final` (all done, no final audit yet), `final-clean` (final audit passed), `final-gaps` (final audit found gaps). Timeout 10s.

9. `tool report_loop_progress` — Shell: count iterations by status in roadmap.md. Print progress summary. Timeout 10s.

10. `agent iteration_failure_handler` — Model: `claude-sonnet-4-6`. Assess iteration failure: task too large → recommend redecompose, model too weak → recommend escalation, plan wrong → recommend human review. End with STATUS: success (retry) or fail (stop).

11. `agent final_audit` — Model: `claude-opus-4-6`. Reasoning effort: high. Fidelity: full. Prompt:

```
You are performing the FINAL behavior-evidence audit before declaring the project complete.

Read:
1. The original spec (find via .ai/iter-extract-temp/chunk_manifest.txt or find *.md in project root)
2. docs/superpowers/iterations/requirements/ (all epic files)
3. docs/superpowers/iterations/behavior-scenarios.md
4. docs/superpowers/iterations/behavior-corpus.md
5. docs/superpowers/iterations/roadmap.md
6. docs/superpowers/iterations/iteration-log.md

## Your Job

The question is: "Can the system point to passing behavior evidence for every externally observable requirement the spec describes?"

1. List every major user-facing surface from the original spec
2. For each surface verify:
   - Corresponding stories exist AND are marked done
   - Corresponding scenarios exist AND have passing evidence at the correct seam
   - Journey scenarios crossing multiple surfaces pass E2E
3. Check behavior corpus completeness:
   - Every journey spec file has at least one JOURNEY-NNNN scenario
   - Every scenario has a non-TBD execution command
   - All sentinel scenarios pass (run the commands)
4. Flag surfaces with:
   - No corresponding story (extraction under-scoped)
   - No corresponding scenario (evidence gap)
   - Evidence at weaker seam than required
   - Manual-residual that could be automated

If ALL surfaces have adequate evidence: write "AUDIT_CLEAN" to .ai/iter-audit-result.txt and touch docs/superpowers/iterations/.final-audit-clean.

If gaps found: write gap descriptions to .ai/iter-audit-result.txt, create gap stories in requirements/, update roadmap with new iteration.

End with STATUS: success (clean) or STATUS: fail (gaps found).
```

12. `tool update_final_progress` — Shell: write final progress.md. Timeout 5s.

13. `agent already_complete_exit` — Report the project was already completed in a previous run.

**Edges:**

```
edges
  Start -> check_resume
  check_resume -> bootstrap_extract          when ctx.tool_stdout = fresh                     label: fresh_start
  check_resume -> bootstrap_scope            when ctx.tool_stdout = needs-scope                label: needs_scope
  check_resume -> run_iteration              when ctx.tool_stdout startswith resume-run        label: resume_run
  check_resume -> final_audit                when ctx.tool_stdout startswith resume-final      label: resume_final
  check_resume -> already_complete_exit      when ctx.tool_stdout = already-complete           label: done
  check_resume -> bootstrap_extract
  already_complete_exit -> Exit
  bootstrap_extract -> bootstrap_scope       when ctx.outcome = success   label: extracted
  bootstrap_extract -> Exit                  when ctx.outcome = fail      label: extract_failed
  bootstrap_scope -> run_iteration           when ctx.outcome = success   label: scoped
  bootstrap_scope -> Exit                    when ctx.outcome = fail      label: scope_failed

  # Main loop
  run_iteration -> audit_iteration           when ctx.outcome = success   label: iteration_done
  run_iteration -> iteration_failure_handler when ctx.outcome = fail      label: iteration_failed
  iteration_failure_handler -> run_iteration when ctx.outcome = success   restart: true  label: retry
  iteration_failure_handler -> Exit          when ctx.outcome = fail      label: give_up
  audit_iteration -> report_loop_progress
  report_loop_progress -> check_termination
  check_termination -> run_iteration         when ctx.tool_stdout = more-iterations           label: continue    restart: true
  check_termination -> final_audit           when ctx.tool_stdout startswith ready-for-final   label: final
  check_termination -> update_final_progress when ctx.tool_stdout = final-clean                label: all_clean
  check_termination -> run_iteration         when ctx.tool_stdout = final-gaps                 label: more_work   restart: true

  # Final audit
  final_audit -> update_final_progress       when ctx.outcome = success   label: final_clean
  final_audit -> run_iteration               when ctx.outcome = fail      label: final_gaps  restart: true
  update_final_progress -> Exit
```

- [ ] **Step 2: Validate the pipeline**

Run: `tracker validate iter_dev.dip`
Expected: validation passes. Verify subgraph refs point to existing files.

- [ ] **Step 3: Commit**

```bash
git add iter_dev.dip
git commit -m "feat: add iter_dev.dip — orchestrator with bootstrap, main loop, and final audit"
```

---

### Task 6: Integration Validation

**Files:**
- No new files. Validate the composed system.

**Context:** All 5 .dip files exist. Validate that: (1) each passes `tracker validate` individually, (2) the subgraph references resolve correctly, (3) the pipeline can be simulated.

- [ ] **Step 1: Validate all pipelines individually**

```bash
tracker validate iter_extract.dip
tracker validate iter_scope.dip
tracker validate iter_audit.dip
tracker validate iter_run.dip
tracker validate iter_dev.dip
```

All must pass.

- [ ] **Step 2: Verify subgraph references**

```bash
grep -n 'ref:' iter_dev.dip
# Verify each referenced file exists
ls iter_extract.dip iter_scope.dip iter_run.dip iter_audit.dip
```

- [ ] **Step 3: Structural spot-check**

Verify key patterns are present in each file:

```bash
# Every file has ABOUTME comments
head -2 iter_extract.dip iter_scope.dip iter_audit.dip iter_run.dip iter_dev.dip

# PAR pattern present in extraction, scope, run, and audit
grep -c 'parallel par_' iter_extract.dip iter_scope.dip iter_run.dip iter_audit.dip

# Loop pattern present in runner and orchestrator
grep -c 'restart: true' iter_run.dip iter_dev.dip

# Subgraph composition in orchestrator
grep -c 'subgraph' iter_dev.dip
```

- [ ] **Step 4: Simulate the orchestrator**

```bash
tracker simulate iter_dev.dip --no-tui 2>&1 | head -50
```

Verify simulation starts and shows expected node traversal.

- [ ] **Step 5: Final commit with all files**

If any fixes were needed during validation, commit them:

```bash
git add iter_*.dip
git commit -m "fix: address validation issues across iterative development pipelines"
```

If no fixes needed, skip this step.
