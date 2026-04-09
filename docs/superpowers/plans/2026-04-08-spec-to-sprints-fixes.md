# Spec-to-Sprints Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all critical and important findings from the 6-expert review panel of `spec_to_sprints.dip`.

**Architecture:** All changes are edits to a single file (`spec_to_sprints.dip`). Tasks are ordered: critical edge/tool fixes first, then data flow fixes, then prompt enrichment, then minor cleanup.

**Tech Stack:** DIP pipeline format, validated by `dippin validate` and `dippin lint`.

**Review report:** See consolidated expert panel report in conversation. Key themes: (1) broken edge routing on validate_output, (2) missing data flow contracts, (3) shell script crash scenarios, (4) prompt gaps.

---

## File Structure

- **Modify:** `spec_to_sprints.dip` — all changes are to this single file

---

### Task 1: Fix validate_output edge routing (Critical #1)

The edges use `ctx.outcome` (agent pattern) but `validate_output` is a tool node. Must use `ctx.tool_stdout`. Also need an unconditional fallback to `validation_failed` for retry exhaustion.

**Files:**
- Modify: `spec_to_sprints.dip:515-517`

- [ ] **Step 1: Fix the three validate_output edges**

Replace the three edges at lines 515-517:

```
    validate_output -> commit_output  when ctx.outcome = success  label: valid
    validate_output -> write_sprint_docs  when ctx.outcome = fail  label: fix_validation  restart: true
    validate_output -> validation_failed  when ctx.outcome = exhausted  label: give_up
```

With:

```
    validate_output -> commit_output  when ctx.tool_stdout = valid  label: valid
    validate_output -> write_sprint_docs  when ctx.tool_stdout != valid  label: fix_validation  restart: true
    validation_failed -> Exit
```

Remove the `validate_output -> validation_failed` conditional edge. The `validation_failed` node is reached when `max_retries` is exhausted on the `write_sprint_docs -> write_ledger -> validate_output` retry loop — the DIP runtime routes to the fallback automatically. Keep the existing `validation_failed -> Exit` edge.

- [ ] **Step 2: Validate**

Run: `dippin validate spec_to_sprints.dip`
Expected: `validation passed`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "fix(spec-to-sprints): use ctx.tool_stdout for validate_output edges"
```

---

### Task 2: Fix commit_output crash scenarios (Critical #3)

The tool crashes if agent-written files don't exist or if there are no staged changes.

**Files:**
- Modify: `spec_to_sprints.dip:466-478`

- [ ] **Step 1: Rewrite the commit_output command**

Replace the entire `commit_output` tool command (lines 469-478):

```
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

With:

```
    command:
      set -eu
      if [ ! -d .git ]; then
        printf 'no-git-skipped'
        exit 0
      fi
      for f in .ai/ledger.tsv .ai/sprints .ai/spec_analysis.md .ai/sprint_plan.md; do
        [ -e "$f" ] && git add "$f"
      done
      if git diff --cached --quiet; then
        printf 'no-changes-skipped'
        exit 0
      fi
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
git commit -m "fix(spec-to-sprints): harden commit_output for missing files and no-op re-runs"
```

---

### Task 3: Fix write_ledger to preserve existing state and handle dash variants (Critical #4, Important #13)

The tool overwrites the entire ledger (design spec says append). Also, the title extraction regex assumes em-dash but LLMs may produce ASCII dashes. Also sanitize tabs from titles.

**Files:**
- Modify: `spec_to_sprints.dip:416-430`

- [ ] **Step 1: Rewrite the write_ledger command**

Replace the entire `write_ledger` tool command (lines 419-430):

```
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
```

With:

```
    command:
      set -eu
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      if [ ! -f .ai/ledger.tsv ]; then
        printf 'sprint_id\ttitle\tstatus\tcreated_at\tupdated_at\n' > .ai/ledger.tsv
      fi
      for f in .ai/sprints/SPRINT-*.md; do
        [ -f "$f" ] || continue
        id=$(basename "$f" .md | sed 's/SPRINT-//')
        if awk -F '\t' -v target="$id" 'NR>1 && $1==target {found=1} END{exit found?0:1}' .ai/ledger.tsv; then
          continue
        fi
        title=$(head -1 "$f" | sed 's/^# Sprint [0-9]* *[-—–]* *//' | sed 's/^# //' | tr -d '\t')
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "planned" "$now" "$now" >> .ai/ledger.tsv
      done
      count=$(awk 'NR>1' .ai/ledger.tsv | wc -l | tr -d ' ')
      printf 'wrote-%s-sprints' "$count"
```

Key changes:
- Only creates header if ledger doesn't exist (preserves existing rows)
- Skips sprint IDs already in the ledger (append-only)
- Sed pattern handles em-dash, en-dash, and hyphen-minus variants
- `tr -d '\t'` strips tabs from titles to prevent TSV corruption

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "fix(spec-to-sprints): preserve existing ledger rows, handle dash variants"
```

---

### Task 4: Add writes/reads annotations and make decompose agents write to disk (Critical #2)

Decompose agents must write their output to `.ai/drafts/` so critique and merge agents can read specific files. Add `writes:` and `reads:` annotations throughout.

**Files:**
- Modify: `spec_to_sprints.dip` — multiple agent nodes

- [ ] **Step 1: Add writes: to analyze_spec**

After `reasoning_effort: high` on `analyze_spec` (line 48), add:

```
    writes: spec_analysis
```

- [ ] **Step 2: Add file-write instruction and writes: to each decompose agent**

For `decompose_claude` (line 100), add after `reasoning_effort: high`:
```
    writes: decomposition_claude
```
And append to the end of its prompt (after the Constraints section):
```

      ## Output
      Write your complete decomposition to .ai/drafts/decomposition_claude.md.
      Create the .ai/drafts directory if it does not exist.
```

For `decompose_gpt` (line 133), add after `reasoning_effort: high`:
```
    writes: decomposition_gpt
```
And append to prompt:
```

      ## Output
      Write your complete decomposition to .ai/drafts/decomposition_gpt.md.
      Create the .ai/drafts directory if it does not exist.
```

For `decompose_gemini` (line 166), add after `reasoning_effort: high`:
```
    writes: decomposition_gemini
```
And append to prompt:
```

      ## Output
      Write your complete decomposition to .ai/drafts/decomposition_gemini.md.
      Create the .ai/drafts directory if it does not exist.
```

- [ ] **Step 3: Add reads: to critique agents and enrich prompts with file references**

For each of the 6 critique agents, add `reads:` and rewrite the prompt to reference specific files. Example for `critique_claude_on_gpt` (line 203):

Add after `reasoning_effort: high`:
```
    reads: decomposition_gpt, spec_analysis
```

Replace the prompt with:
```
    prompt:
      You are working in `run.working_dir`.

      Read .ai/drafts/decomposition_gpt.md (the GPT decomposition) and .ai/spec_analysis.md (the spec analysis with FR IDs).

      Review the GPT decomposition for:
      1. Missed functional requirements — check every FR in spec_analysis against the decomposition
      2. Dependency ordering errors — can each sprint actually be built after its listed dependencies?
      3. Sprints that are too large (should be split) or too small (should be merged)
      4. Unclear or unverifiable DoD items
      5. Missing validation criteria
      6. Coverage gaps against the spec acceptance criteria

      ## Output Format
      For each issue found:
      - Sprint number affected
      - Issue type (missed-req / ordering / sizing / dod / validation / coverage)
      - Severity (critical / important / minor)
      - Specific description citing FR IDs and sprint numbers

      Be specific. Vague critiques like "could be better" are not useful.
```

Apply the same pattern to all 6 critique agents, changing the file reference and model name:
- `critique_claude_on_gemini`: reads `decomposition_gemini`, reviews "the Gemini decomposition"
- `critique_gpt_on_claude`: reads `decomposition_claude`, reviews "the Claude decomposition"
- `critique_gpt_on_gemini`: reads `decomposition_gemini`, reviews "the Gemini decomposition"
- `critique_gemini_on_claude`: reads `decomposition_claude`, reviews "the Claude decomposition"
- `critique_gemini_on_gpt`: reads `decomposition_gpt`, reviews "the GPT decomposition"

- [ ] **Step 4: Add reads: to merge_decomposition**

After `reasoning_effort: high` on `merge_decomposition` (line 269), add:
```
    reads: decomposition_claude, decomposition_gpt, decomposition_gemini, spec_analysis
    writes: sprint_plan
```

Add to the beginning of its prompt Process section, before "1. Compare the three decompositions":
```
      Read the three decomposition files:
      - .ai/drafts/decomposition_claude.md
      - .ai/drafts/decomposition_gpt.md
      - .ai/drafts/decomposition_gemini.md
      And the spec analysis: .ai/spec_analysis.md
```

- [ ] **Step 5: Add reads: to remaining agents**

For `present_plan` (line 316), add: `reads: sprint_plan`
For `apply_feedback` (line 335), add: `reads: sprint_plan` and `writes: sprint_plan`
For `write_sprint_docs` (line 366), add: `reads: sprint_plan, spec_analysis`
For `validation_failed` (line 459), add `You are working in \`run.working_dir\`.` at the start of its prompt.

- [ ] **Step 6: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 7: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add reads/writes annotations, decompose agents write to disk"
```

---

### Task 5: Add goal_gate and fallback_target on key agents (Important #6)

**Files:**
- Modify: `spec_to_sprints.dip` — multiple agent nodes

- [ ] **Step 1: Add goal_gate to analyze_spec**

After `writes: spec_analysis` on `analyze_spec`, add:
```
    goal_gate: true
    retry_target: analyze_spec
```

- [ ] **Step 2: Add goal_gate to merge_decomposition**

After `writes: sprint_plan` on `merge_decomposition`, add:
```
    goal_gate: true
    retry_target: merge_decomposition
```

- [ ] **Step 3: Add fallback_target to decompose agents**

For each of `decompose_claude`, `decompose_gpt`, `decompose_gemini`, add after `writes:`:
```
    fallback_target: DecomposeJoin
```

This ensures if one decomposition agent fails, the other two results still flow through to the fan_in.

- [ ] **Step 4: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add goal_gate and fallback_target for robustness"
```

---

### Task 6: Expand validate_output section checks (Important #7)

**Files:**
- Modify: `spec_to_sprints.dip:432-457`

- [ ] **Step 1: Add required section checks to validate_output**

Replace the DoD-only check loop (lines 443-448):

```
      for f in .ai/sprints/SPRINT-*.md; do
        [ -f "$f" ] || continue
        if ! grep -q '## DoD' "$f"; then
          base=$(basename "$f")
          errors="${errors}missing-dod-${base} "
        fi
      done
```

With:

```
      for f in .ai/sprints/SPRINT-*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        for section in "## Scope" "## Requirements" "## Dependencies" "## Expected Artifacts" "## DoD" "## Validation"; do
          if ! grep -q "$section" "$f"; then
            tag=$(printf '%s' "$section" | sed 's/## //' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
            errors="${errors}missing-${tag}-${base} "
          fi
        done
      done
```

- [ ] **Step 2: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "fix(spec-to-sprints): validate all required sprint doc sections, not just DoD"
```

---

### Task 7: Add TDD and hallucination guardrails to prompts (Important #8, #9, #25)

**Files:**
- Modify: `spec_to_sprints.dip` — analyze_spec, decompose agents, write_sprint_docs prompts

- [ ] **Step 1: Add hallucination guardrail to analyze_spec**

Add to the analyze_spec prompt, before the "## Success Criteria" section:

```
      ## Critical Rules
      - Only extract requirements explicitly stated in the spec. Do not invent, infer, or add requirements.
      - If the spec is ambiguous, note the ambiguity in Open Questions rather than guessing.
      - Every FR must have a direct spec section reference.
```

- [ ] **Step 2: Add TDD and DoD specificity guidance to decompose agent prompts**

Add to the Constraints section of ALL THREE decompose agents (after "Target 8-20 sprints"):

```
      - DoD items must be concrete and machine-verifiable, not vague. Good: "Unit tests for AudioCapture pass". Bad: "Audio capture works correctly"
      - Every sprint's DoD should include at least one test-related item (write tests, run tests, tests pass)
      - Sprint validation should specify exact commands (e.g., "swift test --filter X passes")
      - HARD CAP: Do not produce more than 20 sprints. If the project seems to need more, consolidate.
```

- [ ] **Step 3: Add TDD instruction to write_sprint_docs prompt**

Add to the Rules section of `write_sprint_docs` (after "If .ai/sprints/ already contains files, overwrite them"):

```
      - Every sprint DoD MUST include at least one test item: "Write tests for X" or "Tests for X pass"
      - DoD items must be concrete and machine-verifiable. Good: "pytest tests/test_capture.py passes". Bad: "Capture works correctly"
      - The first DoD item for each sprint should be writing a failing test for the sprint's core deliverable
```

- [ ] **Step 4: Verify parse**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "feat(spec-to-sprints): add TDD guidance, hallucination guardrails, sprint cap"
```

---

### Task 8: Convert skip_approval to tool, fix naming, minor cleanup (Important #14, #15, Minor #19, #20)

**Files:**
- Modify: `spec_to_sprints.dip` — multiple nodes

- [ ] **Step 1: Convert skip_approval from agent to tool**

Replace the entire `skip_approval` agent (lines 347-353):

```
  agent skip_approval
    label: "Skip Approval"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: low
    prompt:
      The sprint plan was approved or approval was skipped for autonomous execution. Document this decision for the audit trail by noting: sprint count, timestamp, and approval mode (human-approved or auto-skipped).
```

With:

```
  tool skip_approval
    label: "Skip Approval"
    timeout: 5s
    command:
      set -eu
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      count="unknown"
      if [ -f .ai/sprint_plan.md ]; then
        count=$(grep -c '^### Sprint' .ai/sprint_plan.md || true)
      fi
      printf 'approved\t%s\t%s\tauto-skipped\n' "$count" "$now"
```

- [ ] **Step 2: Normalize naming to snake_case**

Rename the PascalCase parallel/fan_in nodes to snake_case for consistency with `spec_to_dip.dip`:

- `DecomposeParallel` → `decompose_parallel`
- `DecomposeJoin` → `decompose_join`
- `CritiqueParallel` → `critique_parallel`
- `CritiqueJoin` → `critique_join`

Update ALL references in both the node declarations AND the edges section.

- [ ] **Step 3: Add minimal prompts to Start and Exit**

For `Start` (line 11), add:
```
    prompt:
      Begin spec-to-sprints decomposition pipeline.
```

For `Exit` (line 14), add:
```
    prompt:
      Spec-to-sprints pipeline complete.
```

- [ ] **Step 4: Add reasoning_effort to present_plan and validation_failed**

Add `reasoning_effort: medium` to `present_plan` (line 316).
Add `reasoning_effort: medium` to `validation_failed` (line 459).

- [ ] **Step 5: Fix find_spec nondeterminism**

In the `find_spec` command (line 28), change:

```
      first=$(find . -maxdepth 2 -name '*.md' -not -path './.git/*' -not -path './docs/plans/*' -not -path './docs/superpowers/*' -not -path './.ai/*' | head -1)
```

To:

```
      first=$(find . -maxdepth 2 -name '*.md' -not -path './.git/*' -not -path './docs/plans/*' -not -path './docs/superpowers/*' -not -path './.ai/*' | sort | head -1)
```

- [ ] **Step 6: Verify parse and validate**

Run: `dippin parse spec_to_sprints.dip > /dev/null && echo "ok"`
Run: `dippin validate spec_to_sprints.dip`
Expected: both pass. The naming changes are the riskiest part — verify all edge references match.

- [ ] **Step 7: Commit**

```bash
git add spec_to_sprints.dip
git commit -m "refactor(spec-to-sprints): normalize naming, convert skip_approval to tool, minor fixes"
```

---

### Task 9: Final validation and DOT re-export

**Files:**
- Modify: `spec_to_sprints.dot` (regenerated)

- [ ] **Step 1: Run full validation suite**

```bash
dippin validate spec_to_sprints.dip
dippin lint spec_to_sprints.dip
dippin simulate --all-paths spec_to_sprints.dip > /dev/null
```

Expected: validate passes, lint shows only DIP108 warnings (gemini provider, model list) and DIP101/102 for conditional branches.

- [ ] **Step 2: Re-export DOT**

```bash
dippin export-dot spec_to_sprints.dip > spec_to_sprints.dot
```

- [ ] **Step 3: Commit**

```bash
git add spec_to_sprints.dip spec_to_sprints.dot
git commit -m "docs(spec-to-sprints): re-export DOT after review fixes"
```

---

## Verification Summary

After all tasks, verify:

1. `dippin validate spec_to_sprints.dip` → `validation passed`
2. `dippin lint spec_to_sprints.dip` → no new warnings beyond known DIP108/DIP101/DIP102
3. `dippin simulate --all-paths spec_to_sprints.dip` → all paths reach Exit
4. Every decompose agent writes to `.ai/drafts/decomposition_<model>.md`
5. Every critique agent reads a specific decomposition file
6. `write_ledger` preserves existing ledger rows
7. `commit_output` handles missing files and no-op re-runs
8. `validate_output` checks all 6 required sprint doc sections
9. All node names are snake_case
10. `skip_approval` is a tool node, not an agent
