# Sprint Runner Subgraph Composition

**Date:** 2026-04-16
**Status:** Approved
**Scope:** `sprint_runner.dip`
**Depends on:** sprint dip tech decoupling (merged same day)

## Problem

`sprint_runner.dip` is ~480 lines. ~400 of those lines duplicate the entire sprint execution flow from `sprint_exec.dip` — implementation agent, validate_build, commit, 3 review agents, 6 cross-critique agents, review_analysis, and failure_summary. When sprint_exec gets patched, sprint_runner drifts. The tech decoupling work earlier today reduced the symptom (standardized ValidateBuild) but the root cause is structural duplication.

## Design

The dip format has a `subgraph` node type that references external `.dip` files:

```
subgraph execute_sprint
  ref: sprint_exec.dip
```

The runtime compiles the referenced dip into the parent graph with namespace prefixing (DIP109 handles collision detection). The subgraph node acts as a single unit in the parent's edge routing.

### sprint_runner.dip (new version, ~80 lines)

Keeps only the loop control and delegates sprint execution to sprint_exec.dip:

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

### Nodes deleted (~20)

All of these are now handled by the sprint_exec.dip subgraph:

- `read_sprint` — sprint_exec has `ReadSprint`
- `mark_in_progress` — sprint_exec has `MarkInProgress`
- `preflight` — sprint_exec has `PreFlight`
- `implement_sprint` — sprint_exec has `ImplementSprint`
- `validate_build` — sprint_exec has `ValidateBuild`
- `commit_work` — sprint_exec has `CommitSprintWork`
- `review_claude`, `review_codex`, `review_gemini` — sprint_exec has all three
- `critique_claude_on_codex`, `critique_claude_on_gemini`, `critique_codex_on_claude`, `critique_codex_on_gemini`, `critique_gemini_on_claude`, `critique_gemini_on_codex` — sprint_exec has all six
- `review_analysis` — sprint_exec has `ReviewAnalysis`
- `mark_complete` — sprint_exec has `CompleteSprint`

### Redundant-but-harmless steps

sprint_exec.dip will run its full preamble each iteration: `EnsureLedger` (idempotent), `FindNextSprint` + `SetCurrentSprint` (finds the same sprint that check_ledger already found), `ReadSprint`, `MarkInProgress` (already in_progress — idempotent). These are fast tool/agent nodes (~seconds each). The simplicity of not modifying sprint_exec.dip is worth the few seconds of redundancy.

### Edge routing

sprint_runner's edges route on `ctx.outcome` from the subgraph node. When sprint_exec reaches `CompleteSprint → Exit`, the subgraph reports success. When it reaches `FailureSummary → Exit`, it reports failure. The parent routes accordingly.

### What stays untouched

- `sprint_exec.dip` — no changes
- `sprint_exec-cheap.dip` — no changes (sprint_runner only refs the full-cost variant)

## Validation

After implementation:
1. `dippin validate sprint_runner.dip` — must pass
2. `dippin lint sprint_runner.dip` — must pass (DIP126 checks that ref file exists)
3. `dippin simulate sprint_runner.dip` — should show the subgraph node in the path
4. Confirm ~20 nodes removed by line count comparison
