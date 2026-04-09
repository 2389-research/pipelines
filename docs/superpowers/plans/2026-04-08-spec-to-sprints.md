# Spec-to-Sprints Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write `spec_to_sprints.dip` — a pipeline that decomposes a spec into `.ai/ledger.tsv` + `SPRINT-*.md` files ready for `sprint_exec.dip`.

**Architecture:** Single .dip file with four sections: spec discovery, multi-model decomposition tournament (3 drafts + 6 cross-critiques + merge), human approval gate, and sprint doc generation with ledger sync. Follows the same DIP syntax patterns as `sprint_exec.dip` and `megaplan.dip`.

**Tech Stack:** DIP pipeline format, validated by `dippin validate` and `dippin lint`.

**Spec:** `docs/superpowers/specs/2026-04-08-spec-to-sprints-design.md`

**Reference files:**
- `sprint_exec.dip` — target consumer of this pipeline's output; shows ledger/sprint doc conventions
- `megaplan.dip` — shows parallel/fan_in/human gate patterns and ledger tool scripts
- `spec_to_dip.dip` — shows find_spec tool, analyze_spec prompt structure, tournament pattern

---

## File Structure

- **Create:** `spec_to_sprints.dip` — the complete pipeline definition

That's it. One file.

---

### Task 1: Scaffold — workflow header, defaults, Start/Exit, find_spec, no_spec_exit

**Files:**
- Create: `spec_to_sprints.dip`

- [ ] **Step 1: Write the pipeline scaffold with Section 1 nodes**

Write `spec_to_sprints.dip` with the workflow header, defaults, Start/Exit agents, `find_spec` tool, and `no_spec_exit` agent. The `find_spec` tool reuses the same logic from `spec_to_dip.dip` (search known filenames, fall back to first .md within 2 levels).

```dip
workflow SpecToSprints
  goal: "Decompose a specification into .ai/ledger.tsv and SPRINT-*.md files ready for sprint_exec.dip execution, using multi-model tournament decomposition with human approval."
  start: Start
  exit: Exit

  defaults
    max_retries: 3
    max_restarts: 10
    fidelity: summary:medium

  agent Start
    label: Start

  agent Exit
    label: Exit

  tool find_spec
    label: "Find Spec File"
    timeout: 30s
    command:
      set -eu
      for f in spec.md SPEC.md design.md design-doc.md specification.md requirements.md prompt_plan.md; do
        if [ -f "$f" ]; then
          printf '%s' "$f"
          exit 0
        fi
      done
      first=$(find . -maxdepth 2 -name '*.md' -not -path './.git/*' -not -path './docs/plans/*' -not -path './docs/superpowers/*' -not -path './.ai/*' | head -1)
      if [ -n "$first" ]; then
        printf '%s' "$first"
        exit 0
      fi
      printf 'no_spec_found'

  agent no_spec_exit
    label: "No Spec Found"
    prompt:
      No spec file was found in the working directory. The pipeline cannot proceed without a spec.

      Searched for: spec.md, SPEC.md, design.md, design-doc.md, specification.md, requirements.md, prompt_plan.md, and any .md file within 2 directory levels.

      To use this pipeline, place a spec file in the working directory and re-run.
```

- [ ] **Step 2: Validate the scaffold**

Run: `dippin validate spec_to_sprints.dip`
Expected: `validation passed` (will warn about unreachable nodes since edges aren't written yet — that's fine, we add edges in Task 7)

Note: `dippin validate` will fail until edges are added in Task 7 because nodes won't be connected. That's expected. We validate structurally as we go and do a full validate+lint at the end.

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): scaffold workflow with spec discovery"
```

---

### Task 2: analyze_spec agent

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the analyze_spec agent**

Append after the `no_spec_exit` agent. Uses gpt-5.4 with high reasoning effort. The prompt instructs it to read the spec and write a structured analysis to `.ai/spec_analysis.md`.

```dip
  agent analyze_spec
    label: "Analyze Spec"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read the spec file found by the previous step and produce a structured analysis for sprint decomposition.

      ## Process
      1. Read the spec file thoroughly
      2. Write .ai/spec_analysis.md with ALL of the following sections:

      ### Project Summary
      Name, purpose, one-paragraph description.

      ### Tech Stack
      Language, framework, database, test framework, linter, package manager — extracted from the spec or inferred from its requirements.

      ### Functional Requirements (numbered)
      Every discrete functional requirement extracted from the spec, numbered FR1-FRn. Each entry:
      - ID (e.g., FR1)
      - Spec section reference (e.g., "Section 5, FR1")
      - One-line description
      - Acceptance criteria if specified

      ### Architectural Layers / Components (numbered)
      For each component or layer the spec defines:
      - Name
      - Description (1 line)
      - Dependencies (which other components it needs)

      ### Dependency Graph
      Which components can be built in parallel, which must be sequential, and why.

      ### Complexity Assessment
      For each component: low / medium / high complexity with one-line justification.

      ### Rollout Phases
      If the spec defines phases (v0, v1, v2), list what belongs in each. If not, note "no phases defined."

      ### Open Questions
      Ambiguities, unresolved decisions, or contradictions found in the spec.

      ## Output
      Write the analysis to .ai/spec_analysis.md. Create the .ai directory if it does not exist.

      ## Success Criteria
      - .ai/spec_analysis.md exists with ALL sections filled in
      - Every functional requirement is numbered
      - Every component dependency is mapped
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip | python3 -m json.tool | head -5`
Expected: valid JSON output (confirms the file parses without syntax errors)

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add analyze_spec agent (gpt-5.4)"
```

---

### Task 3: Decomposition tournament — three parallel decompose agents

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the parallel declaration and three decompose agents**

Append after `analyze_spec`. Each agent reads `.ai/spec_analysis.md` and proposes a sprint breakdown with a different emphasis.

```dip
  parallel DecomposeParallel -> decompose_claude, decompose_gpt, decompose_gemini

  agent decompose_claude
    label: "Claude Decomposition"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read .ai/spec_analysis.md and decompose the project into an ordered list of implementation sprints.

      ## Your Emphasis: Thoroughness
      Focus on dependency ordering, risk sequencing, and DoD traceability. Every functional requirement (FR1-FRn) must be covered by at least one sprint. No requirement should be orphaned.

      ## Output Format
      For each sprint, provide:
      - Sprint number (sequential, starting at 001)
      - Title (short, descriptive)
      - Scope: what this sprint delivers (2-3 sentences)
      - Non-goals: what is explicitly excluded
      - Requirements covered: list FR IDs from the spec analysis
      - Dependencies: which sprint numbers must complete first (empty for first sprint)
      - Expected artifacts: specific files, modules, or configurations produced
      - DoD items: 5-10 checkable items that prove the sprint is complete
      - Complexity: low / medium / high

      ## Constraints
      - Sprints should be roughly equal in effort where possible
      - Earlier sprints should establish foundations that later sprints build on
      - Every sprint must be independently verifiable (has its own validation)
      - Prefer fewer, well-scoped sprints over many tiny ones
      - Target 8-20 sprints for a typical project

  agent decompose_gpt
    label: "GPT Decomposition"
    model: gpt-5.2
    provider: openai
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read .ai/spec_analysis.md and decompose the project into an ordered list of implementation sprints.

      ## Your Emphasis: Implementation Pragmatism
      Focus on execution order, what can be parallelized, and build/test feasibility. Think about what a developer actually needs working first before the next piece can start.

      ## Output Format
      For each sprint, provide:
      - Sprint number (sequential, starting at 001)
      - Title (short, descriptive)
      - Scope: what this sprint delivers (2-3 sentences)
      - Non-goals: what is explicitly excluded
      - Requirements covered: list FR IDs from the spec analysis
      - Dependencies: which sprint numbers must complete first (empty for first sprint)
      - Expected artifacts: specific files, modules, or configurations produced
      - DoD items: 5-10 checkable items that prove the sprint is complete
      - Complexity: low / medium / high

      ## Constraints
      - Sprints should be roughly equal in effort where possible
      - Earlier sprints should establish foundations that later sprints build on
      - Every sprint must be independently verifiable (has its own validation)
      - Prefer fewer, well-scoped sprints over many tiny ones
      - Target 8-20 sprints for a typical project

  agent decompose_gemini
    label: "Gemini Decomposition"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read .ai/spec_analysis.md and decompose the project into an ordered list of implementation sprints.

      ## Your Emphasis: Delivery Robustness
      Focus on scope discipline, sprint size consistency, validation checkpoints, and risk mitigation. Flag any sprint that seems too large or has unclear validation criteria.

      ## Output Format
      For each sprint, provide:
      - Sprint number (sequential, starting at 001)
      - Title (short, descriptive)
      - Scope: what this sprint delivers (2-3 sentences)
      - Non-goals: what is explicitly excluded
      - Requirements covered: list FR IDs from the spec analysis
      - Dependencies: which sprint numbers must complete first (empty for first sprint)
      - Expected artifacts: specific files, modules, or configurations produced
      - DoD items: 5-10 checkable items that prove the sprint is complete
      - Complexity: low / medium / high

      ## Constraints
      - Sprints should be roughly equal in effort where possible
      - Earlier sprints should establish foundations that later sprints build on
      - Every sprint must be independently verifiable (has its own validation)
      - Prefer fewer, well-scoped sprints over many tiny ones
      - Target 8-20 sprints for a typical project

  fan_in DecomposeJoin <- decompose_claude, decompose_gpt, decompose_gemini
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add 3-model parallel decomposition"
```

---

### Task 4: Cross-critique — six parallel critique agents

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the parallel declaration and six critique agents**

Append after `DecomposeJoin`. Each model critiques the other two models' decompositions.

```dip
  parallel CritiqueParallel -> critique_claude_on_gpt, critique_claude_on_gemini, critique_gpt_on_claude, critique_gpt_on_gemini, critique_gemini_on_claude, critique_gemini_on_gpt

  agent critique_claude_on_gpt
    label: "Claude Critique of GPT"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Review the GPT decomposition for: missed functional requirements, dependency ordering errors, sprints that are too large or too small, unclear DoD items, missing validation criteria, and coverage gaps against the spec analysis.

      Be specific. Cite sprint numbers and FR IDs when identifying issues.

  agent critique_claude_on_gemini
    label: "Claude Critique of Gemini"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Review the Gemini decomposition for: missed functional requirements, dependency ordering errors, sprints that are too large or too small, unclear DoD items, missing validation criteria, and coverage gaps against the spec analysis.

      Be specific. Cite sprint numbers and FR IDs when identifying issues.

  agent critique_gpt_on_claude
    label: "GPT Critique of Claude"
    model: gpt-5.2
    provider: openai
    reasoning_effort: high
    prompt:
      Review the Claude decomposition for: missed functional requirements, dependency ordering errors, sprints that are too large or too small, unclear DoD items, missing validation criteria, and coverage gaps against the spec analysis.

      Be specific. Cite sprint numbers and FR IDs when identifying issues.

  agent critique_gpt_on_gemini
    label: "GPT Critique of Gemini"
    model: gpt-5.2
    provider: openai
    reasoning_effort: high
    prompt:
      Review the Gemini decomposition for: missed functional requirements, dependency ordering errors, sprints that are too large or too small, unclear DoD items, missing validation criteria, and coverage gaps against the spec analysis.

      Be specific. Cite sprint numbers and FR IDs when identifying issues.

  agent critique_gemini_on_claude
    label: "Gemini Critique of Claude"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Review the Claude decomposition for: missed functional requirements, dependency ordering errors, sprints that are too large or too small, unclear DoD items, missing validation criteria, and coverage gaps against the spec analysis.

      Be specific. Cite sprint numbers and FR IDs when identifying issues.

  agent critique_gemini_on_gpt
    label: "Gemini Critique of GPT"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Review the GPT decomposition for: missed functional requirements, dependency ordering errors, sprints that are too large or too small, unclear DoD items, missing validation criteria, and coverage gaps against the spec analysis.

      Be specific. Cite sprint numbers and FR IDs when identifying issues.

  fan_in CritiqueJoin <- critique_claude_on_gpt, critique_claude_on_gemini, critique_gpt_on_claude, critique_gpt_on_gemini, critique_gemini_on_claude, critique_gemini_on_gpt
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add 6-way cross-critique"
```

---

### Task 5: Merge decomposition agent

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the merge_decomposition agent**

Append after `CritiqueJoin`.

```dip
  agent merge_decomposition
    label: "Merge Decomposition"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Synthesize the three decompositions and six cross-critiques into one final sprint plan.

      ## Process
      1. Compare the three decompositions side by side
      2. Incorporate valid critique findings — fix ordering errors, fill coverage gaps, adjust sprint sizes
      3. Produce a single merged sprint list that takes the best from each decomposition
      4. Write the result to .ai/sprint_plan.md

      ## Output Format (.ai/sprint_plan.md)
      Start with a summary: total sprint count, overall approach, key decisions made during merge.

      Then for each sprint:
      ### Sprint NNN — Title

      **Scope:** What this sprint delivers (2-3 sentences)

      **Non-goals:** What is explicitly excluded

      **Requirements:** FR IDs covered (e.g., FR1, FR3, FR7)

      **Dependencies:** Sprint numbers that must complete first

      **Expected Artifacts:**
      - file/module paths this sprint produces

      **DoD:**
      - [ ] Checkable item 1
      - [ ] Checkable item 2
      ...

      **Validation:**
      - Build/test commands to verify completion

      **Complexity:** low / medium / high

      ## Rules
      - Every FR from .ai/spec_analysis.md must appear in at least one sprint
      - No dependency cycles
      - Sprint IDs are sequential zero-padded 3-digit (001, 002, ...)
      - First sprint should be project scaffold / foundation
      - Create .ai directory if it does not exist
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add merge_decomposition agent"
```

---

### Task 6: Human approval gate — present_plan, approval_gate, apply_feedback, skip_approval

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the four approval gate nodes**

Append after `merge_decomposition`.

```dip
  agent present_plan
    label: "Present Sprint Plan"
    model: claude-sonnet-4-6
    provider: anthropic
    prompt:
      You are working in `run.working_dir`.

      Read .ai/sprint_plan.md and present a concise review summary for human approval:

      1. Total sprint count
      2. Sprint titles listed in order with dependencies noted
      3. Requirement coverage: any FRs not covered?
      4. Risk flags: any sprints that seem too large, too vague, or have unclear validation?

      Keep the summary scannable. The human needs to decide: approve as-is, or request changes.

  human approval_gate
    label: "Approve Sprint Plan"

  agent apply_feedback
    label: "Apply Feedback"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      The human has provided feedback on the sprint plan. Read .ai/sprint_plan.md, incorporate the feedback, and rewrite .ai/sprint_plan.md with the changes applied.

      Preserve the same format. Update sprint numbers if sprints are added, removed, or reordered. Ensure dependency references remain consistent after renumbering.

  agent skip_approval
    label: "Skip Approval"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: low
    prompt:
      The sprint plan was approved or approval was skipped for autonomous execution. Document this decision for the audit trail by noting: sprint count, timestamp, and approval mode (human-approved or auto-skipped).
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add human approval gate"
```

---

### Task 7: Sprint doc generation — setup_workspace, write_sprint_docs, write_ledger, validate_output, validation_failed, commit_output

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the six Section 4 nodes**

Append after `skip_approval`.

```dip
  tool setup_workspace
    label: "Setup .ai Workspace"
    timeout: 10s
    command:
      set -eu
      mkdir -p .ai/sprints .ai/drafts
      if [ ! -f .ai/ledger.tsv ]; then
        printf 'sprint_id\ttitle\tstatus\tcreated_at\tupdated_at\n' > .ai/ledger.tsv
      fi
      printf 'ready'

  agent write_sprint_docs
    label: "Write Sprint Docs"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read .ai/sprint_plan.md and .ai/spec_analysis.md. Write a SPRINT-<id>.md file under .ai/sprints/ for each sprint in the plan.

      ## Sprint Doc Format
      Each file must follow this exact structure:

      ```
      # Sprint NNN — Title

      ## Scope
      What this sprint delivers (2-3 sentences).

      ## Non-goals
      - What is explicitly excluded (reference later sprints where applicable)

      ## Requirements
      - FR IDs covered, with one-line descriptions from spec analysis

      ## Dependencies
      - Sprint numbers that must complete first (or "None" for the first sprint)

      ## Expected Artifacts
      - Specific file paths, modules, configs, or test files this sprint produces

      ## DoD
      - [ ] Checkable item 1
      - [ ] Checkable item 2
      (5-10 items per sprint)

      ## Validation
      - Build commands, test commands, or manual verification steps
      ```

      ## Rules
      - File naming: .ai/sprints/SPRINT-001.md, SPRINT-002.md, etc.
      - Zero-padded 3-digit IDs matching the sprint plan
      - Every sprint doc must have all sections above
      - DoD items must be concrete and verifiable, not vague
      - Expected artifacts should use realistic file paths based on the tech stack from spec analysis
      - Write ALL sprint docs in one pass for cross-sprint consistency
      - If .ai/sprints/ already contains files, overwrite them

  tool write_ledger
    label: "Write Ledger"
    timeout: 10s
    command:
      set -eu
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf 'sprint_id\ttitle\tstatus\tcreated_at\tupdated_at\n' > .ai/ledger.tsv
      for f in .ai/sprints/SPRINT-*.md; do
        [ -f "$f" ] || continue
        id=$(basename "$f" .md | sed 's/SPRINT-//')
        title=$(head -1 "$f" | sed 's/^# Sprint [0-9]* — //' | sed 's/^# //')
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "planned" "$now" "$now" >> .ai/ledger.tsv
      done
      count=$(awk 'NR>1' .ai/ledger.tsv | wc -l | tr -d ' ')
      printf 'wrote-%s-sprints' "$count"

  tool validate_output
    label: "Validate Output"
    timeout: 15s
    command:
      set -eu
      errors=""
      ledger_ids=$(awk -F '\t' 'NR>1{print $1}' .ai/ledger.tsv | sort)
      file_ids=$(ls .ai/sprints/SPRINT-*.md 2>/dev/null | sed 's|.*/SPRINT-||;s|\.md||' | sort)
      if [ "$ledger_ids" != "$file_ids" ]; then
        errors="${errors}ledger-file-mismatch "
      fi
      for f in .ai/sprints/SPRINT-*.md; do
        [ -f "$f" ] || continue
        if ! grep -q '## DoD' "$f"; then
          base=$(basename "$f")
          errors="${errors}missing-dod-${base} "
        fi
      done
      if [ -z "$(awk 'NR>1' .ai/ledger.tsv)" ]; then
        errors="${errors}empty-ledger "
      fi
      if [ -n "$errors" ]; then
        printf 'invalid-%s' "$errors"
        exit 1
      fi
      printf 'valid'

  agent validation_failed
    label: "Validation Failed"
    model: claude-sonnet-4-6
    provider: anthropic
    prompt:
      The output validation failed after exhausting retries. Diagnose what went wrong by examining the .ai/sprints/ directory and .ai/ledger.tsv. Report what is missing or malformed so the issue can be addressed manually.

  tool commit_output
    label: "Commit Output"
    timeout: 30s
    command:
      set -eu
      if [ ! -d .git ]; then
        printf 'no-git-skipped'
        exit 0
      fi
      git add .ai/ledger.tsv .ai/sprints/ .ai/spec_analysis.md .ai/sprint_plan.md
      count=$(awk 'NR>1' .ai/ledger.tsv | wc -l | tr -d ' ')
      git commit -m "feat(sprints): decompose spec into ${count} sprints"
      printf 'committed-%s-sprints' "$count"
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add sprint doc generation and ledger sync"
```

---

### Task 8: Write all edges

**Files:**
- Modify: `spec_to_sprints.dip`

- [ ] **Step 1: Add the edges section**

Append at the end of the file.

```dip
  edges
    Start -> find_spec
    find_spec -> analyze_spec  when ctx.tool_stdout != no_spec_found  label: spec_found
    find_spec -> no_spec_exit  when ctx.tool_stdout = no_spec_found  label: no_spec
    no_spec_exit -> Exit
    analyze_spec -> DecomposeParallel
    DecomposeParallel -> decompose_claude
    DecomposeParallel -> decompose_gpt
    DecomposeParallel -> decompose_gemini
    decompose_claude -> DecomposeJoin
    decompose_gpt -> DecomposeJoin
    decompose_gemini -> DecomposeJoin
    DecomposeJoin -> CritiqueParallel
    CritiqueParallel -> critique_claude_on_gpt
    CritiqueParallel -> critique_claude_on_gemini
    CritiqueParallel -> critique_gpt_on_claude
    CritiqueParallel -> critique_gpt_on_gemini
    CritiqueParallel -> critique_gemini_on_claude
    CritiqueParallel -> critique_gemini_on_gpt
    critique_claude_on_gpt -> CritiqueJoin
    critique_claude_on_gemini -> CritiqueJoin
    critique_gpt_on_claude -> CritiqueJoin
    critique_gpt_on_gemini -> CritiqueJoin
    critique_gemini_on_claude -> CritiqueJoin
    critique_gemini_on_gpt -> CritiqueJoin
    CritiqueJoin -> merge_decomposition
    merge_decomposition -> present_plan
    present_plan -> approval_gate
    approval_gate -> apply_feedback  label: "[A] Revise plan"
    approval_gate -> skip_approval  label: "[S] Approve / Skip"
    apply_feedback -> approval_gate
    skip_approval -> setup_workspace
    setup_workspace -> write_sprint_docs
    write_sprint_docs -> write_ledger
    write_ledger -> validate_output
    validate_output -> commit_output  when ctx.outcome = success  label: valid
    validate_output -> write_sprint_docs  when ctx.outcome = fail  label: fix_validation
    commit_output -> Exit
    validation_failed -> Exit
```

- [ ] **Step 2: Validate the complete pipeline**

Run: `dippin validate spec_to_sprints.dip`
Expected: `validation passed`

- [ ] **Step 3: Lint the complete pipeline**

Run: `dippin lint spec_to_sprints.dip`
Expected: Passes with at most DIP108 warnings (gemini provider not in linter's known list — this is a false positive, same as sprint_exec.dip). No structural errors.

- [ ] **Step 4: Fix any validation or lint issues**

If `dippin validate` fails, read the error output and fix the specific issue. Common problems:
- Typo in node name between definition and edge reference
- Missing fan_in/parallel matching
- Unreachable nodes

If `dippin lint` shows real warnings (not DIP108), fix those too.

- [ ] **Step 5: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add all edges, pipeline complete"
```

---

### Task 9: Full validation — simulate, export DOT, verify against spec

**Files:**
- No file changes (verification only)

- [ ] **Step 1: Run dippin simulate to trace all paths**

Run: `dippin simulate --all-paths spec_to_sprints.dip`
Expected: Shows at least these paths:
1. Happy path: Start → find_spec → analyze_spec → ... → commit_output → Exit
2. No-spec path: Start → find_spec → no_spec_exit → Exit
3. Approval loop path: ... → approval_gate → apply_feedback → approval_gate → skip_approval → ...
4. Validation retry path: ... → validate_output → write_sprint_docs → ... (retry loop)

- [ ] **Step 2: Export DOT for visual inspection**

Run: `dippin export-dot spec_to_sprints.dip > spec_to_sprints.dot`
Expected: Valid DOT file. Optionally render with `dot -Tpng spec_to_sprints.dot -o spec_to_sprints.png` if graphviz is installed.

- [ ] **Step 3: Verify spec coverage**

Check the design spec requirements against what the pipeline implements:

| Spec Requirement | Pipeline Node(s) |
|---|---|
| Find spec file | `find_spec` tool |
| Graceful no-spec exit | `no_spec_exit` agent |
| Structured spec analysis to .ai/spec_analysis.md | `analyze_spec` agent (gpt-5.4) |
| 3-model parallel decomposition | `decompose_claude`, `decompose_gpt`, `decompose_gemini` |
| 6-way cross-critique | 6 `critique_*` agents |
| Merge into .ai/sprint_plan.md | `merge_decomposition` agent |
| Human approval gate with skip | `approval_gate` human + `skip_approval` / `apply_feedback` |
| Setup .ai workspace | `setup_workspace` tool |
| Write full SPRINT-*.md docs | `write_sprint_docs` agent |
| Write ledger.tsv | `write_ledger` tool |
| Validate output | `validate_output` tool |
| Validation failure diagnosis | `validation_failed` agent |
| Git commit (graceful skip) | `commit_output` tool |

All requirements covered.

- [ ] **Step 4: Commit the DOT export**

```bash
git add spec_to_sprints.dot
git commit -m "docs(spec-to-sprints): add DOT export for visual reference"
```

---

## Verification Summary

After all tasks, the following must be true:

1. `dippin validate spec_to_sprints.dip` → `validation passed`
2. `dippin lint spec_to_sprints.dip` → no errors (DIP108 warnings acceptable)
3. `dippin simulate --all-paths spec_to_sprints.dip` → all expected paths traced
4. Every node in the design spec has a corresponding definition in the .dip file
5. Every edge in the design spec has a corresponding edge in the edges section
6. The output contract matches what `sprint_exec.dip` and `megaplan.dip` consume
