# Sprint Runner Subgraph Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace sprint_runner.dip's ~400 lines of duplicated sprint execution nodes with a single `subgraph` reference to sprint_exec.dip.

**Architecture:** Delete all duplicated nodes from sprint_runner.dip, add a `subgraph execute_sprint` node referencing sprint_exec.dip, rewire edges to route through it. One file changes, one file stays untouched.

**Tech Stack:** Dip pipeline definitions, dippin CLI for validation

**Spec:** `docs/superpowers/specs/2026-04-16-sprint-runner-subgraph-composition-design.md`

---

### Task 1: Replace sprint_runner.dip with subgraph version

**Files:**
- Modify: `sprint_runner.dip` (full rewrite — ~480 lines → ~80 lines)

- [ ] **Step 1: Read the current file to confirm starting state**

Read `sprint_runner.dip` and confirm it still has the duplicated nodes from the tech decoupling work (implement_sprint, validate_build, commit_work, 3 reviews, 6 critiques, review_analysis, etc.).

- [ ] **Step 2: Write the new sprint_runner.dip**

Replace the entire file with this content:

```
workflow SprintRunner
  goal: "Execute all sprints from .ai/ledger.tsv in sequence, looping until every sprint is completed or one fails."
  start: Start
  exit: Exit

  defaults
    max_retries: 3
    max_restarts: 50
    fidelity: summary:medium

  agent Start
    label: Start
    prompt:
      Begin sprint runner pipeline. Will loop through all incomplete sprints in the ledger.

  agent Exit
    label: Exit
    prompt:
      Sprint runner pipeline complete.

  tool check_ledger
    label: "Check Ledger"
    timeout: 10s
    command:
      set -eu
      if [ ! -f .ai/ledger.tsv ]; then
        printf 'no_ledger'
        exit 0
      fi
      target=$(awk -F '\t' 'NR>1 && $3!~/^completed$/ && $3!~/^skipped$/{print $1; exit}' .ai/ledger.tsv)
      if [ -z "$target" ]; then
        printf 'all_done'
        exit 0
      fi
      printf '%s' "$target" > .ai/current_sprint_id.txt
      printf 'next-%s' "$target"

  agent no_ledger_exit
    label: "No Ledger Found"
    prompt:
      No .ai/ledger.tsv found. The sprint runner requires an existing ledger with planned sprints.

      To create one, run spec_to_sprints.dip with a spec file, or megaplan.dip to plan incrementally.

  subgraph execute_sprint
    ref: sprint_exec.dip

  tool report_progress
    label: "Report Progress"
    timeout: 10s
    command:
      set -eu
      total=$(awk -F '\t' 'NR>1' .ai/ledger.tsv | wc -l | tr -d ' ')
      done=$(awk -F '\t' 'NR>1 && ($3=="completed" || $3=="skipped")' .ai/ledger.tsv | wc -l | tr -d ' ')
      if [ "$total" -gt 0 ]; then
        pct=$((done * 100 / total))
      else
        pct=0
      fi
      printf 'progress-%s-of-%s-%spct' "$done" "$total" "$pct"

  human sprint_gate
    label: "Continue to Next Sprint?"
    mode: choice

  tool skip_gate
    label: "Skip Gate"
    timeout: 5s
    command:
      set -eu
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      target=$(cat .ai/current_sprint_id.txt 2>/dev/null || echo "unknown")
      printf 'continue\t%s\t%s\n' "$target" "$now"

  agent failure_summary
    label: "Failure Summary"
    model: claude-sonnet-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Sprint execution failed. The subgraph sprint_exec.dip has already diagnosed the failure in detail.

      Read .ai/current_sprint_id.txt and .ai/ledger.tsv. Report which sprint failed and whether downstream sprints are affected. Keep it brief — the detailed diagnosis already happened inside sprint_exec.

  edges
    Start -> check_ledger
    check_ledger -> Exit             when ctx.tool_stdout = all_done    label: all_done
    check_ledger -> no_ledger_exit   when ctx.tool_stdout = no_ledger   label: no_ledger
    check_ledger -> execute_sprint   when ctx.tool_stdout != all_done   label: next_sprint
    no_ledger_exit -> Exit
    execute_sprint -> report_progress  when ctx.outcome = success  label: sprint_done
    execute_sprint -> failure_summary  when ctx.outcome = fail     label: sprint_failed
    execute_sprint -> failure_summary
    report_progress -> sprint_gate
    sprint_gate -> skip_gate  label: "[S] Continue"
    sprint_gate -> Exit       label: "[A] Pause"
    skip_gate -> check_ledger  restart: true
    failure_summary -> Exit
```

- [ ] **Step 3: Validate with dippin**

Run:
```bash
dippin validate sprint_runner.dip
```
Expected: `validation passed`

Run:
```bash
dippin lint sprint_runner.dip
```
Expected: no errors. Possible DIP126 warning if sprint_exec.dip isn't in the same directory (it is — both are in the repo root).

- [ ] **Step 4: Simulate**

Run:
```bash
dippin simulate sprint_runner.dip
```
Expected: path includes `execute_sprint` as a subgraph node.

- [ ] **Step 5: Confirm line count reduction**

Run:
```bash
wc -l sprint_runner.dip
```
Expected: ~80 lines (was ~483).

- [ ] **Step 6: Commit**

```bash
git add sprint_runner.dip
git commit -m "refactor(sprint-runner): replace duplicated nodes with subgraph ref to sprint_exec.dip"
```

---

### Task 2: Verify sprint_exec.dip is untouched and post to BBS

- [ ] **Step 1: Confirm sprint_exec.dip has no changes**

Run:
```bash
git diff sprint_exec.dip
```
Expected: no output (file unchanged).

- [ ] **Step 2: Post summary to mammoth BBS**

Post to the existing thread "Resolved: Sprint dips decoupled from language-specific guidance" with a follow-up message summarizing the subgraph composition change.
