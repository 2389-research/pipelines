# Sprint Pipeline v2 — Managed Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three manager agents (PlanManager, ReviewManager, RecoveryManager) to the sprint execution pipeline, enhance the decomposition pipeline with a quality gate and re-decomposition mode, and wire the runner to handle mid-execution re-decomposition via sidecar subgraph.

**Architecture:** Three independent `.dip` files forked from v1 — `sprint_exec_yaml_v2.dip` (exec with managers), `spec_to_sprints_yaml_v2.dip` (decomposition with DecompositionManager + redecompose mode), `sprint_runner_yaml_v2.dip` (runner with re-decomposition sidecar). Managers use cross-provider model assignments and write to dedicated markdown journals with selective cross-reading.

**Tech Stack:** DIP pipeline format, tracker CLI (validate/simulate), yq for YAML manipulation, bash for tool nodes.

**Spec:** `docs/superpowers/specs/2026-04-23-sprint-pipeline-v2-managed-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `sprint_exec_yaml_v2.dip` | Create (fork from `sprint_exec_yaml.dip`) | Single-sprint execution with PlanManager, ReviewManager, RecoveryManager |
| `spec_to_sprints_yaml_v2.dip` | Create (fork from `spec_to_sprints_yaml.dip`) | Spec decomposition with DecompositionManager + redecompose mode |
| `sprint_runner_yaml_v2.dip` | Create (fork from `sprint_runner_yaml.dip`) | Runner loop with re-decomposition sidecar |

All three files live at the repo root: `/Users/harper/Public/src/2389/pipelines/`.

---

### Task 1: Fork and validate the v1 exec pipeline as v2

**Files:**
- Create: `sprint_exec_yaml_v2.dip`
- Reference: `sprint_exec_yaml.dip`

- [ ] **Step 1: Copy v1 to v2**

```bash
cp sprint_exec_yaml.dip sprint_exec_yaml_v2.dip
```

- [ ] **Step 2: Update the ABOUTME comments and workflow name**

Replace the first 4 lines of `sprint_exec_yaml_v2.dip`:

```
# ABOUTME: Sprint execution pipeline v2 with three manager agents (PlanManager, ReviewManager, RecoveryManager).
# ABOUTME: Fork of sprint_exec_yaml.dip — adds pre-execution planning, evidence synthesis, and failure recovery management.
workflow SprintExecYamlV2
  goal: "Execute the next incomplete sprint from .ai/ledger.yaml through implementation, validation, multi-model review, and completion. v2 adds PlanManager (pre-execution gate), ReviewManager (evidence synthesis), and RecoveryManager (failure triage) with dedicated journals and selective cross-reading."
  start: Start
  exit: Exit
```

- [ ] **Step 3: Validate the fork compiles**

Run: `tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -5`
Expected: `sprint_exec_yaml_v2.dip: valid with NN warning(s) (37 nodes, 73 edges)` — same count as v1.

- [ ] **Step 4: Simulate the fork**

Run: `tracker simulate sprint_exec_yaml_v2.dip 2>&1 | tail -5`
Expected: same simulation output as v1, confirming the fork is a clean copy.

- [ ] **Step 5: Commit**

```bash
git add sprint_exec_yaml_v2.dip
git commit -m "chore: fork sprint_exec_yaml.dip as v2 baseline"
```

---

### Task 2: Add EnsureManagerJournals tool to exec v2

**Files:**
- Modify: `sprint_exec_yaml_v2.dip`

- [ ] **Step 1: Add the EnsureManagerJournals tool node**

Add this node after the `EnsureLedger` tool definition (after line ~36 in the fork):

```
  tool EnsureManagerJournals
    label: "Ensure Manager Journals"
    timeout: 10s
    command:
      set -eu
      mkdir -p .ai/managers
      for journal in plan-journal.md review-journal.md recovery-journal.md; do
        if [ ! -f ".ai/managers/$journal" ]; then
          name=$(printf '%s' "$journal" | sed 's/-journal.md//' | sed 's/./\U&/')
          printf '# %s Journal\n' "$name" > ".ai/managers/$journal"
        fi
      done
      printf 'journals-ready'
```

- [ ] **Step 2: Update the edge from EnsureLedger**

Change:
```
    EnsureLedger -> CheckYq
```
To:
```
    EnsureLedger -> EnsureManagerJournals
    EnsureManagerJournals -> CheckYq
```

- [ ] **Step 3: Validate**

Run: `tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -5`
Expected: `valid with NN warning(s) (38 nodes, 74 edges)` — one more node and edge than v1.

- [ ] **Step 4: Commit**

```bash
git add sprint_exec_yaml_v2.dip
git commit -m "feat(sprint-exec-v2): add EnsureManagerJournals tool node"
```

---

### Task 3: Add PlanManager agent to exec v2

**Files:**
- Modify: `sprint_exec_yaml_v2.dip`

- [ ] **Step 1: Add the PlanManager agent node**

Add this node after the `ReadSprint` agent definition:

```
  agent PlanManager
    label: "Plan Manager"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    auto_status: true
    prompt:
      You are the Plan Manager for sprint execution. Your job is to assess whether the current sprint is ready to execute and flag risks for the implementation agent.

      Read .ai/current_sprint_id.txt to get the sprint ID. Then read:
      1. .ai/sprints/SPRINT-<id>.yaml — the structured contract
      2. .ai/sprints/SPRINT-<id>.md — the narrative description
      3. .ai/managers/recovery-journal.md — check if RecoveryManager flagged risks for sprints related to this one (scan dependency chain)
      4. .ai/ledger.yaml — check the last 3-5 sprint outcomes for patterns (repeated failures, skipped deps)

      ## Assessment

      For each item in entry_preconditions.files_must_exist, verify the file actually exists on disk. If any are missing, this is a HOLD.

      Check if any sprint in depends_on has status "failed" or "skipped" in the ledger — if so, this sprint may be building on an unstable foundation. Flag it.

      Check RecoveryManager's journal for entries on dependency sprints — did any of them fail with "dependency failure" root cause? If so, the gaps may cascade into this sprint.

      ## Output

      Write a plan brief to .ai/sprints/SPRINT-<id>-plan-brief.md with:
      - Go/Hold recommendation
      - Risk flags (specific, citing sprint IDs and file paths)
      - Dependency health assessment
      - Hints for ImplementSprint (what to watch out for)

      Then append a section to .ai/managers/plan-journal.md using this format:

      ## Sprint <id> — <title>
      **Date:** <current ISO timestamp>
      **Recommendation:** GO | HOLD
      **Risk flags:** <list or "None">
      **Dependency check:** <which preconditions verified>
      **Recovery context:** <relevant RecoveryManager findings or "None">
      **Notes:** <free-form observations>

      After your analysis, end your response with exactly one of:
        STATUS: success
        STATUS: fail

      Return STATUS: success if the sprint should proceed (GO).
      Return STATUS: fail if the sprint should be deferred (HOLD).

      HARD CONSTRAINT: Do NOT write code. Do NOT implement anything. Do NOT modify the sprint YAML, ledger, or any source files. Your ONLY job is to assess readiness and write the brief and journal entry.
```

- [ ] **Step 2: Update edges — insert PlanManager between ReadSprint and CheckBootstrap**

Change:
```
    ReadSprint -> CheckBootstrap
```
To:
```
    ReadSprint -> PlanManager
    PlanManager -> CheckBootstrap  when ctx.outcome = success  label: go
    PlanManager -> MarkFailed      when ctx.outcome = fail     label: hold
    PlanManager -> MarkFailed
```

- [ ] **Step 3: Validate**

Run: `tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -5`
Expected: `valid with NN warning(s) (39 nodes, 77 edges)` — one more node, three more edges.

- [ ] **Step 4: Simulate and verify PlanManager appears in the flow**

Run: `tracker simulate sprint_exec_yaml_v2.dip 2>&1 | grep -A2 "Plan Manager"`
Expected: Shows PlanManager after ReadSprint with edges to CheckBootstrap and MarkFailed.

- [ ] **Step 5: Commit**

```bash
git add sprint_exec_yaml_v2.dip
git commit -m "feat(sprint-exec-v2): add PlanManager agent between ReadSprint and CheckBootstrap"
```

---

### Task 4: Add ReviewManager agent to exec v2

**Files:**
- Modify: `sprint_exec_yaml_v2.dip`

- [ ] **Step 1: Add the ReviewManager agent node**

Add this node after the `CritiquesJoin` fan_in definition:

```
  agent ReviewManager
    label: "Review Manager"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Review Manager for sprint execution. Your job is to synthesize the 3 independent reviews and 6 cross-critiques into a structured evidence brief for the final verdict agent.

      Read .ai/current_sprint_id.txt to get the sprint ID. Then read:
      1. .ai/managers/plan-journal.md — find the entry for this sprint to see what PlanManager flagged as risks
      2. The review and critique outputs from the current pipeline run (available in your context)

      ## Synthesis

      Organize the evidence into:
      - **Agreements:** What all 3 reviewers agree on (pass or fail items)
      - **Disagreements:** Where reviewers diverge, and which side has stronger evidence (cite specific code, test output, or DoD items)
      - **Scope fence violations:** Did any reviewer flag work outside scope_fence.off_limits?
      - **PlanManager risk check:** Did any risks flagged by PlanManager actually materialize? List each flagged risk and whether it was confirmed or not.
      - **Evidence quality:** Are the reviews thorough or superficial? Did critiques add substance or just agree?

      ## Output

      Write a review brief to .ai/sprints/SPRINT-<id>-review-brief.md with the synthesis above.

      Then append a section to .ai/managers/review-journal.md using this format:

      ## Sprint <id> — <title>
      **Date:** <current ISO timestamp>
      **Reviewer consensus:** PASS | MIXED | FAIL
      **Key agreements:** <bullet list>
      **Key disagreements:** <bullet list with evidence assessment>
      **PlanManager risk check:** <which flagged risks materialized>
      **Scope fence violations:** <any detected, or "None">
      **Evidence quality:** <assessment>

      HARD CONSTRAINT: Do NOT render a verdict. Do NOT write STATUS: success or STATUS: fail. Do NOT write code. Do NOT modify any source files. Your ONLY job is to organize evidence for the ReviewAnalysis agent.
```

- [ ] **Step 2: Update edges — insert ReviewManager between CritiquesJoin and ReviewAnalysis**

Change:
```
    CritiquesJoin -> ReviewAnalysis
```
To:
```
    CritiquesJoin -> ReviewManager
    ReviewManager -> ReviewAnalysis
```

- [ ] **Step 3: Validate**

Run: `tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -5`
Expected: `valid with NN warning(s) (40 nodes, 78 edges)` — one more node, net one more edge (removed one, added two).

- [ ] **Step 4: Simulate and verify ReviewManager appears between CritiquesJoin and ReviewAnalysis**

Run: `tracker simulate sprint_exec_yaml_v2.dip 2>&1 | grep -A2 "Review Manager"`
Expected: Shows ReviewManager after CritiquesJoin with edge to ReviewAnalysis.

- [ ] **Step 5: Commit**

```bash
git add sprint_exec_yaml_v2.dip
git commit -m "feat(sprint-exec-v2): add ReviewManager agent between CritiquesJoin and ReviewAnalysis"
```

---

### Task 5: Add RecoveryManager agent to exec v2

**Files:**
- Modify: `sprint_exec_yaml_v2.dip`

- [ ] **Step 1: Add the RecoveryManager agent node**

Add this node after the `MarkFailed` tool definition:

```
  agent RecoveryManager
    label: "Recovery Manager"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      You are the Recovery Manager for sprint execution. Your job is to perform root-cause analysis on a failed sprint and recommend a recovery strategy.

      Read .ai/current_sprint_id.txt to get the sprint ID. Then read:
      1. .ai/sprints/SPRINT-<id>.yaml — check history.attempts for prior failure patterns
      2. .ai/sprints/SPRINT-<id>.md — the narrative description
      3. .ai/managers/plan-journal.md — find PlanManager's entry for this sprint. Were its risk flags the cause?
      4. .ai/ledger.yaml — check this sprint's attempt count and dependency sprint outcomes

      ## Root Cause Analysis

      Classify the failure into one of three categories:
      - **Implementation failure:** The code was wrong but the sprint scope is sound. A retry with better implementation guidance could succeed.
      - **Scope failure:** The sprint is too large, too vague, or mixes unrelated concerns. It needs to be broken into smaller sub-sprints via re-decomposition.
      - **Dependency failure:** A prior sprint left gaps (missing APIs, incomplete types, broken tests) that make this sprint impossible as-written.

      ## Signals for REDECOMPOSE

      Recommend redecomposition when:
      - The sprint has failed 2+ attempts with different root causes each time (scope is too broad)
      - The sprint touches more than 3 subsystems
      - The sprint DoD has more than 10 items
      - Multiple reviewers flagged "sprint is too large" or "mixed concerns"

      ## Output

      Write a recovery analysis to .ai/sprints/SPRINT-<id>-recovery-analysis.md with:
      - Root cause category (implementation / scope / dependency)
      - Specific failure detail
      - Whether PlanManager's risk flags predicted this
      - Recommendation: RETRY, REDECOMPOSE, or ABANDON
      - If REDECOMPOSE: write .ai/redecompose-request.yaml with this format:
        mode: redecompose
        failed_sprint_id: "<id>"
        failed_sprint_title: "<title>"
        scope: "<original scope from sprint YAML>"
        failure_reason: "<your root cause analysis>"
        recovery_recommendation: "<how to split>"
        depends_on_from_original: [<dep list from sprint YAML>]
        original_dependents: [<dependents list from sprint YAML>]

      Then append a section to .ai/managers/recovery-journal.md using this format:

      ## Sprint <id> — <title>
      **Date:** <current ISO timestamp>
      **Root cause:** implementation | scope | dependency
      **Failure detail:** <specific description>
      **PlanManager alignment:** <did risk flags predict this?>
      **Recommendation:** RETRY | REDECOMPOSE | ABANDON
      **Recovery notes:** <what should change>

      HARD CONSTRAINT: Do NOT write code. Do NOT fix the implementation. Do NOT modify the sprint YAML status or ledger. Your ONLY job is to analyze and recommend. The runner pipeline handles the actual retry/redecompose/abandon decision.
```

- [ ] **Step 2: Update edges — insert RecoveryManager between MarkFailed and FailureSummary**

Change:
```
    MarkFailed -> FailureSummary
```
To:
```
    MarkFailed -> RecoveryManager
    RecoveryManager -> FailureSummary
```

- [ ] **Step 3: Validate**

Run: `tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -5`
Expected: `valid with NN warning(s) (41 nodes, 79 edges)` — one more node, net one more edge.

- [ ] **Step 4: Simulate and verify RecoveryManager appears between MarkFailed and FailureSummary**

Run: `tracker simulate sprint_exec_yaml_v2.dip 2>&1 | grep -A2 "Recovery Manager"`
Expected: Shows RecoveryManager after MarkFailed with edge to FailureSummary.

- [ ] **Step 5: Full validate + simulate of complete exec v2**

Run: `tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s) (41 nodes, ~79 edges)`

Run: `tracker simulate sprint_exec_yaml_v2.dip 2>&1 | head -50`
Expected: Full flow shows Start → EnsureLedger → EnsureManagerJournals → CheckYq → ... → PlanManager → ... → ReviewManager → ReviewAnalysis → ... → MarkFailed → RecoveryManager → FailureSummary → Exit.

- [ ] **Step 6: Commit**

```bash
git add sprint_exec_yaml_v2.dip
git commit -m "feat(sprint-exec-v2): add RecoveryManager agent between MarkFailed and FailureSummary"
```

---

### Task 6: Fork and validate the v1 decomposition pipeline as v2

**Files:**
- Create: `spec_to_sprints_yaml_v2.dip`
- Reference: `spec_to_sprints_yaml.dip`

- [ ] **Step 1: Copy v1 to v2**

```bash
cp spec_to_sprints_yaml.dip spec_to_sprints_yaml_v2.dip
```

- [ ] **Step 2: Update the ABOUTME comments and workflow name**

Replace the first 4 lines of `spec_to_sprints_yaml_v2.dip`:

```
# ABOUTME: Spec-to-sprints decomposition pipeline v2 with DecompositionManager quality gate and redecompose mode.
# ABOUTME: Fork of spec_to_sprints_yaml.dip — adds plan quality review and single-sprint re-decomposition for mid-execution sidecar.
workflow SpecToSprintsYamlV2
  goal: "Decompose a specification into .ai/ledger.yaml and SPRINT-*.md + SPRINT-*.yaml files ready for sprint_exec_yaml_v2.dip execution, using multi-model tournament decomposition with DecompositionManager quality gate, human approval, and optional single-sprint re-decomposition mode."
  start: Start
  exit: Exit
```

- [ ] **Step 3: Validate the fork compiles**

Run: `tracker validate spec_to_sprints_yaml_v2.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s)` — same counts as v1.

- [ ] **Step 4: Commit**

```bash
git add spec_to_sprints_yaml_v2.dip
git commit -m "chore: fork spec_to_sprints_yaml.dip as v2 baseline"
```

---

### Task 7: Add DecompositionManager to decomposition v2

**Files:**
- Modify: `spec_to_sprints_yaml_v2.dip`

- [ ] **Step 1: Add the DecompositionManager agent node**

Add this node after the `merge_decomposition` agent definition:

```
  agent DecompositionManager
    label: "Decomposition Manager"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    reads: sprint_plan, spec_analysis
    auto_status: true
    prompt:
      You are the Decomposition Manager. Your job is to review the merged sprint plan for quality issues before it goes to human approval.

      Read .ai/sprint_plan.md and .ai/spec_analysis.md.

      ## Checks

      Perform ALL of the following checks:

      1. **Sizing audit:** Any sprint with >10 DoD items or referencing >3 subsystems? List each violation and how to split.
      2. **Dependency cycle detection:** Trace the depends_on graph. If any cycle exists, list the cycle.
      3. **FR coverage matrix:** For every FR in spec_analysis.md, find which sprint covers it. List any orphaned FRs.
      4. **Scope fence quality:** Each sprint should have meaningful off_limits constraints, not just boilerplate. Flag sprints with vague or missing scope fences.
      5. **Validation command quality:** Are all validation commands concrete and runnable? Flag any pseudocode or "verify manually" items.
      6. **Risk sequencing:** Are high-complexity sprints placed after their required foundations? Flag any that front-load risk without dependencies.
      7. **Capstone check:** The last sprint must depend on ALL other sprint IDs. Flag if any are missing.

      ## Output

      Write findings to .ai/drafts/decomposition_review.md with:
      - Pass/fail per check
      - Specific violations with sprint IDs
      - Recommended fixes

      If ANY check fails, rewrite .ai/sprint_plan.md with fixes applied:
      - Split oversized sprints (assign new sequential IDs)
      - Fix dependency ordering
      - Add missing FR coverage
      - Improve scope fences
      - Fix validation commands
      - Update capstone dependencies

      After fixes, end with STATUS: success. The human gate is the final decision point.

      If ALL checks pass with no issues, end with STATUS: success and note "No issues found" in the review.

      HARD CONSTRAINT: Do NOT write sprint YAML or MD files — that is handled by write_sprint_docs. Only modify sprint_plan.md if fixes are needed.
```

- [ ] **Step 2: Update edges — insert DecompositionManager between merge_decomposition and present_plan**

Change:
```
    merge_decomposition -> present_plan
```
To:
```
    merge_decomposition -> DecompositionManager
    DecompositionManager -> present_plan
```

- [ ] **Step 3: Validate**

Run: `tracker validate spec_to_sprints_yaml_v2.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s)` — one more node, net one more edge.

- [ ] **Step 4: Simulate and verify DecompositionManager appears between merge and present**

Run: `tracker simulate spec_to_sprints_yaml_v2.dip 2>&1 | grep -A2 "Decomposition Manager"`
Expected: Shows DecompositionManager after merge_decomposition with edge to present_plan.

- [ ] **Step 5: Commit**

```bash
git add spec_to_sprints_yaml_v2.dip
git commit -m "feat(spec-to-sprints-v2): add DecompositionManager quality gate after merge"
```

---

### Task 8: Add redecompose mode to decomposition v2

**Files:**
- Modify: `spec_to_sprints_yaml_v2.dip`

- [ ] **Step 1: Update the check_resume tool to detect redecompose mode**

In the `check_resume` tool's command, add this block at the very top of the script (after `set -eu`, before `has_ledger=false`):

```bash
      # Redecompose mode — invoked as sidecar from runner
      if [ -f .ai/redecompose-request.yaml ]; then
        printf 'redecompose-mode'
        exit 0
      fi
```

- [ ] **Step 2: Add the redecompose_single agent node**

Add this node after the `DecompositionManager` agent definition:

```
  agent redecompose_single
    label: "Redecompose Single Sprint"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are re-decomposing a single failed sprint into smaller sub-sprints.

      Read .ai/redecompose-request.yaml for the context:
      - failed_sprint_id: which sprint failed
      - scope: the original scope
      - failure_reason: why it failed (from RecoveryManager)
      - recovery_recommendation: how to split
      - depends_on_from_original: dependencies to inherit
      - original_dependents: downstream sprints to note

      Also read:
      - .ai/sprints/SPRINT-<failed_id>.yaml — the original contract
      - .ai/sprints/SPRINT-<failed_id>-recovery-analysis.md — RecoveryManager's full analysis (if it exists)

      ## Task

      Split the failed sprint's scope into 2-4 focused sub-sprints. Each sub-sprint should:
      - Have ONE clear theme (not a kitchen-sink)
      - Have 5-8 DoD items (not more than 10)
      - Touch at most 2-3 subsystems
      - Be independently verifiable

      ## ID Assignment

      Read the `next_available_id` field from .ai/redecompose-request.yaml. This is the first ID to use. Assign sequential IDs from there (e.g., if next_available_id is "030", use 030, 031, 032).

      If `next_available_id` is not set, count existing SPRINT-*.yaml files in .ai/sprints/ and start from the next number.

      ## Output

      For each sub-sprint, write TWO files to .ai/sprints/:
      1. SPRINT-<new_id>.yaml — full YAML contract (same schema as other sprints)
         - depends_on: inherit from the original sprint's depends_on
         - dependents: leave empty (runner will rewrite)
         - scope_fence.off_limits: must include "do not modify .ai/ledger.yaml"
         - status: planned
         - bootstrap: false
         - stack: copy from any existing sprint YAML
      2. SPRINT-<new_id>.md — full narrative (same format as other sprints)

      Then write .ai/redecompose-result.yaml:
        original_sprint_id: "<failed_id>"
        new_sprint_ids: ["<id1>", "<id2>", ...]
        new_sprint_titles:
          "<id1>": "<title>"
          "<id2>": "<title>"
        dependents_to_rewrite:
          "<dependent_id>":
            old_dep: "<failed_id>"
            new_deps: ["<last_new_id>"]

      For dependents_to_rewrite: the original_dependents should now depend on the LAST new sub-sprint (the one that completes the original scope).

      HARD CONSTRAINT: Do NOT modify existing sprint files. Do NOT modify ledger.yaml. Only create new SPRINT files and the result manifest.
```

- [ ] **Step 3: Add the write_ledger_redecompose tool node**

Add this node after `redecompose_single`:

```
  tool write_ledger_redecompose
    label: "Append Redecomposed Sprints to Ledger"
    timeout: 30s
    command:
      set -eu
      if [ ! -f .ai/redecompose-result.yaml ]; then
        printf 'no-result-file'
        exit 1
      fi
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      for new_id in $(yq '.new_sprint_ids[]' .ai/redecompose-result.yaml); do
        sf=".ai/sprints/SPRINT-${new_id}.yaml"
        if [ ! -f "$sf" ]; then
          printf 'missing-sprint-yaml-%s' "$new_id"
          exit 1
        fi
        title=$(yq '.title | @json' "$sf")
        complexity=$(yq '.complexity // "medium"' "$sf")
        deps=$(yq '.depends_on // [] | @json' "$sf")
        yq -i ".sprints += [{\"id\": \"$new_id\", \"title\": $title, \"status\": \"planned\", \"bootstrap\": false, \"depends_on\": $deps, \"complexity\": \"$complexity\", \"created_at\": \"$now\", \"updated_at\": \"$now\", \"attempts\": 0, \"total_cost\": \"0.00\"}]" .ai/ledger.yaml
      done
      count=$(yq '.new_sprint_ids | length' .ai/redecompose-result.yaml)
      printf 'appended-%s-sprints' "$count"
```

- [ ] **Step 4: Add edges for the redecompose flow**

Add these edges to the edges block:

```
    check_resume -> redecompose_single      when ctx.tool_stdout = redecompose-mode  label: redecompose
    redecompose_single -> DecompositionManager
    DecompositionManager -> write_ledger_redecompose  when ctx.outcome = success  label: redecompose_reviewed
    write_ledger_redecompose -> validate_output
```

Note: The existing edges `validate_output -> commit_output -> Exit` handle the rest of the flow.

- [ ] **Step 5: Validate**

Run: `tracker validate spec_to_sprints_yaml_v2.dip 2>&1 | tail -5`
Expected: `valid with NN warning(s)` — additional nodes and edges for the redecompose path.

- [ ] **Step 6: Simulate and verify both paths exist**

Run: `tracker simulate spec_to_sprints_yaml_v2.dip 2>&1 | grep -E "(Redecompose|Decomposition Manager|redecompose)"`
Expected: Shows both the normal path (through DecompositionManager to present_plan) and the redecompose path (check_resume to redecompose_single to DecompositionManager to write_ledger_redecompose).

- [ ] **Step 7: Commit**

```bash
git add spec_to_sprints_yaml_v2.dip
git commit -m "feat(spec-to-sprints-v2): add redecompose mode for mid-execution sprint splitting"
```

---

### Task 9: Fork and validate the v1 runner as v2

**Files:**
- Create: `sprint_runner_yaml_v2.dip`
- Reference: `sprint_runner_yaml.dip`

- [ ] **Step 1: Copy v1 to v2**

```bash
cp sprint_runner_yaml.dip sprint_runner_yaml_v2.dip
```

- [ ] **Step 2: Update the ABOUTME comments, workflow name, and subgraph reference**

Replace the first 4 lines:

```
# ABOUTME: Autonomous sprint runner v2 with re-decomposition sidecar for mis-scoped sprint recovery.
# ABOUTME: Fork of sprint_runner_yaml.dip — adds redecompose flow when RecoveryManager signals scope failure.
workflow SprintRunnerYamlV2
  goal: "Execute all sprints from .ai/ledger.yaml autonomously in sequence, retrying failed sprints once, re-decomposing mis-scoped sprints via sidecar, and skipping on repeated failure, until every sprint is completed/skipped/redecomposed or the failure budget is exhausted."
  start: Start
  exit: Exit
```

Update the subgraph reference from v1 to v2:

Change:
```
  subgraph execute_sprint
    ref: sprint_exec_yaml.dip
```
To:
```
  subgraph execute_sprint
    ref: sprint_exec_yaml_v2.dip
```

- [ ] **Step 3: Validate the fork compiles**

Run: `tracker validate sprint_runner_yaml_v2.dip 2>&1 | tail -3`
Expected: `valid with NN warning(s)` — same counts as v1.

- [ ] **Step 4: Commit**

```bash
git add sprint_runner_yaml_v2.dip
git commit -m "chore: fork sprint_runner_yaml.dip as v2 baseline with exec v2 subgraph ref"
```

---

### Task 10: Add re-decomposition flow to runner v2

**Files:**
- Modify: `sprint_runner_yaml_v2.dip`

- [ ] **Step 1: Update check_ledger tool to handle `redecomposed` status**

In the `check_ledger` tool's command, change the candidates line:

From:
```
      candidates=$(yq '.sprints[] | select(.status != "completed" and .status != "skipped" and .status != "failed") | .id' .ai/ledger.yaml)
```
To:
```
      candidates=$(yq '.sprints[] | select(.status != "completed" and .status != "skipped" and .status != "failed" and .status != "redecomposed") | .id' .ai/ledger.yaml)
```

- [ ] **Step 2: Update handle_failure tool to detect redecompose signal**

In the `handle_failure` tool's command, add redecompose detection at the top (after `set -eu` and the target/last_failed/total_failures reads, before the increment):

```bash
      # Check if RecoveryManager requested redecomposition
      if [ -f .ai/redecompose-request.yaml ]; then
        printf 'redecompose-%s' "$target"
        exit 0
      fi
```

- [ ] **Step 3: Add prepare_redecompose tool node**

```
  tool prepare_redecompose
    label: "Prepare Redecompose"
    timeout: 15s
    command:
      set -eu
      if [ ! -f .ai/redecompose-request.yaml ]; then
        printf 'no-request'
        exit 1
      fi
      target=$(yq '.failed_sprint_id' .ai/redecompose-request.yaml)
      # Calculate next available ID
      max_id=$(yq '.sprints[-1].id' .ai/ledger.yaml)
      next_id=$(printf '%03d' $((10#$max_id + 1)))
      yq -i ".next_available_id = \"$next_id\"" .ai/redecompose-request.yaml
      # Calculate existing sprint count
      count=$(yq '.sprints | length' .ai/ledger.yaml)
      yq -i ".existing_sprint_count = $count" .ai/redecompose-request.yaml
      printf 'ready-to-redecompose-%s-next-%s' "$target" "$next_id"
```

- [ ] **Step 4: Add redecompose_sprint subgraph**

```
  subgraph redecompose_sprint
    ref: spec_to_sprints_yaml_v2.dip
```

- [ ] **Step 5: Add splice_ledger tool node**

```
  tool splice_ledger
    label: "Splice Redecomposed Sprints"
    timeout: 30s
    command:
      set -eu
      if [ ! -f .ai/redecompose-result.yaml ]; then
        printf 'no-result'
        exit 1
      fi
      original_id=$(yq '.original_sprint_id' .ai/redecompose-result.yaml)
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      # Mark original sprint as redecomposed
      yq -i "(.sprints[] | select(.id == \"$original_id\")).status = \"redecomposed\" | (.sprints[] | select(.id == \"$original_id\")).updated_at = \"$now\"" .ai/ledger.yaml
      # Rewrite dependents
      for dep_id in $(yq '.dependents_to_rewrite | keys | .[]' .ai/redecompose-result.yaml 2>/dev/null); do
        old_dep=$(yq ".dependents_to_rewrite.\"$dep_id\".old_dep" .ai/redecompose-result.yaml)
        new_deps=$(yq ".dependents_to_rewrite.\"$dep_id\".new_deps" .ai/redecompose-result.yaml)
        # Remove old dep and add new deps
        yq -i "(.sprints[] | select(.id == \"$dep_id\")).depends_on -= [\"$old_dep\"]" .ai/ledger.yaml
        for new_dep in $(yq ".dependents_to_rewrite.\"$dep_id\".new_deps[]" .ai/redecompose-result.yaml); do
          yq -i "(.sprints[] | select(.id == \"$dep_id\")).depends_on += [\"$new_dep\"]" .ai/ledger.yaml
        done
        # Also update the sprint YAML if it exists
        dep_yaml=".ai/sprints/SPRINT-${dep_id}.yaml"
        if [ -f "$dep_yaml" ]; then
          yq -i ".depends_on -= [\"$old_dep\"]" "$dep_yaml"
          for new_dep in $(yq ".dependents_to_rewrite.\"$dep_id\".new_deps[]" .ai/redecompose-result.yaml); do
            yq -i ".depends_on += [\"$new_dep\"]" "$dep_yaml"
          done
        fi
      done
      # Read count before cleanup
      new_count=$(yq '.new_sprint_ids | length' .ai/redecompose-result.yaml)
      # Clean up transient files
      rm -f .ai/redecompose-request.yaml .ai/redecompose-result.yaml
      printf 'spliced-%s-redecomposed-into-%s-sprints' "$original_id" "$new_count"
```

- [ ] **Step 6: Add report_redecompose tool node**

```
  tool report_redecompose
    label: "Report Redecomposition"
    timeout: 10s
    command:
      set -eu
      total=$(yq '.sprints | length' .ai/ledger.yaml)
      done=$(yq '[.sprints[] | select(.status == "completed")] | length' .ai/ledger.yaml)
      redecomposed=$(yq '[.sprints[] | select(.status == "redecomposed")] | length' .ai/ledger.yaml)
      remaining=$((total - done - redecomposed))
      printf 'redecompose-complete-total-%s-done-%s-remaining-%s' "$total" "$done" "$remaining"
```

- [ ] **Step 7: Add edges for the redecompose flow**

Add these edges:

```
    handle_failure -> prepare_redecompose    when ctx.tool_stdout startswith redecompose-  label: redecompose
    prepare_redecompose -> redecompose_sprint
    redecompose_sprint -> splice_ledger      when ctx.outcome = success  label: redecompose_done
    redecompose_sprint -> failure_summary    when ctx.outcome = fail     label: redecompose_failed
    splice_ledger -> report_redecompose
    report_redecompose -> check_ledger       restart: true
```

- [ ] **Step 8: Validate**

Run: `tracker validate sprint_runner_yaml_v2.dip 2>&1 | tail -5`
Expected: `valid with NN warning(s)` — additional nodes and edges for the redecompose path.

- [ ] **Step 9: Simulate and verify both success and redecompose paths**

Run: `tracker simulate sprint_runner_yaml_v2.dip 2>&1 | grep -E "(redecompose|splice|Prepare|Report Redecomposition)"`
Expected: Shows prepare_redecompose → redecompose_sprint → splice_ledger → report_redecompose → check_ledger chain.

- [ ] **Step 10: Commit**

```bash
git add sprint_runner_yaml_v2.dip
git commit -m "feat(sprint-runner-v2): add re-decomposition sidecar flow with ledger splicing"
```

---

### Task 11: Cross-pipeline validation

**Files:**
- Validate: `sprint_exec_yaml_v2.dip`, `spec_to_sprints_yaml_v2.dip`, `sprint_runner_yaml_v2.dip`

- [ ] **Step 1: Validate all three v2 pipelines**

```bash
tracker validate sprint_exec_yaml_v2.dip 2>&1 | tail -3
tracker validate spec_to_sprints_yaml_v2.dip 2>&1 | tail -3
tracker validate sprint_runner_yaml_v2.dip 2>&1 | tail -3
```

Expected: All three report `valid`.

- [ ] **Step 2: Simulate all three v2 pipelines**

```bash
tracker simulate sprint_exec_yaml_v2.dip 2>&1 | tail -10
tracker simulate spec_to_sprints_yaml_v2.dip 2>&1 | tail -10
tracker simulate sprint_runner_yaml_v2.dip 2>&1 | tail -10
```

Expected: All three produce complete simulation output with no errors.

- [ ] **Step 3: Verify subgraph references resolve**

The runner references `sprint_exec_yaml_v2.dip` and `spec_to_sprints_yaml_v2.dip`. Verify both exist:

```bash
ls -la sprint_exec_yaml_v2.dip spec_to_sprints_yaml_v2.dip sprint_runner_yaml_v2.dip
```

Expected: All three files exist.

- [ ] **Step 4: Verify v1 pipelines are untouched**

```bash
git diff sprint_exec_yaml.dip sprint_runner_yaml.dip spec_to_sprints_yaml.dip
```

Expected: No changes — v1 files remain as they were.

- [ ] **Step 5: Count nodes and edges for v2 vs v1**

```bash
echo "=== v1 ==="
tracker validate sprint_exec_yaml.dip 2>&1 | grep "valid"
tracker validate sprint_runner_yaml.dip 2>&1 | grep "valid"
tracker validate spec_to_sprints_yaml.dip 2>&1 | grep "valid"
echo "=== v2 ==="
tracker validate sprint_exec_yaml_v2.dip 2>&1 | grep "valid"
tracker validate sprint_runner_yaml_v2.dip 2>&1 | grep "valid"
tracker validate spec_to_sprints_yaml_v2.dip 2>&1 | grep "valid"
```

Expected: v2 pipelines have more nodes and edges than v1 (the delta from the managers and redecompose flow).

- [ ] **Step 6: Commit (if any fixes were needed)**

```bash
git add sprint_exec_yaml_v2.dip spec_to_sprints_yaml_v2.dip sprint_runner_yaml_v2.dip
git commit -m "fix(v2-pipelines): cross-pipeline validation fixes"
```

Only commit if changes were made during validation. If all passed clean, skip this step.

---

### Task 12: Final commit and summary

**Files:**
- All v2 `.dip` files

- [ ] **Step 1: Verify git status is clean**

```bash
git status
```

Expected: Clean working tree (all v2 files committed).

- [ ] **Step 2: Review the full diff from main**

```bash
git log --oneline main..HEAD
```

Expected: Shows the sequence of commits:
1. chore: fork sprint_exec_yaml.dip as v2 baseline
2. feat(sprint-exec-v2): add EnsureManagerJournals tool node
3. feat(sprint-exec-v2): add PlanManager agent
4. feat(sprint-exec-v2): add ReviewManager agent
5. feat(sprint-exec-v2): add RecoveryManager agent
6. chore: fork spec_to_sprints_yaml.dip as v2 baseline
7. feat(spec-to-sprints-v2): add DecompositionManager quality gate
8. feat(spec-to-sprints-v2): add redecompose mode
9. chore: fork sprint_runner_yaml.dip as v2 baseline
10. feat(sprint-runner-v2): add re-decomposition sidecar flow

- [ ] **Step 3: Run tracker doctor on all three v2 pipelines (if available)**

```bash
tracker doctor sprint_exec_yaml_v2.dip 2>&1 | tail -5
tracker doctor spec_to_sprints_yaml_v2.dip 2>&1 | tail -5
tracker doctor sprint_runner_yaml_v2.dip 2>&1 | tail -5
```

Expected: All pass or warn (exit 0 or 2), not fail (exit 1).
