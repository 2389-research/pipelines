# Sprint Runner Pipeline Design

**Date:** 2026-04-09
**Status:** Approved design
**Author:** Doctor Biz + Claude Opus 4.6

---

## Overview

A DIP pipeline that loops `sprint_exec` logic until every sprint in `.ai/ledger.tsv` is `completed` or one fails. Inlines the full sprint execution flow (implement, validate, review tournament, verdict) with a loop controller that checks the ledger between sprints, reports progress, and offers a human approval gate (auto-skippable for CLI autonomous mode).

**Input:** An existing `.ai/ledger.tsv` with one or more `planned` sprints and corresponding `.ai/sprints/SPRINT-*.md` docs (produced by `spec_to_sprints.dip` or `megaplan.dip`).

**Output:** All sprints executed to `completed` status, or a failure summary identifying which sprint failed and why.

---

## Motivation

The existing pipeline ecosystem has a gap:

- `spec_to_sprints.dip` — decomposes a spec into N sprints + ledger (batch planning)
- `megaplan.dip` — plans ONE sprint at a time (incremental planning)
- `sprint_exec.dip` — executes ONE sprint from the ledger

Nothing loops sprint execution until the entire backlog is done. Running `sprint_exec.dip` manually N times is tedious and loses cross-sprint context. This pipeline fills that gap.

---

## Architecture

```
check_ledger → [all_done?]
  yes → Exit
  no  → read_sprint → mark_in_progress → implement_sprint → validate_build
        → commit_work → review tournament (3 reviews + 6 critiques)
        → review_analysis → [verdict?]
            pass  → mark_complete → report_progress → sprint_gate → skip_gate → check_ledger (loop)
            retry → implement_sprint (rework)
            fail  → failure_summary → Exit
```

The loop terminates in two ways:
1. **Happy path:** `check_ledger` finds no remaining incomplete sprints → exit
2. **Failure:** a sprint fails after retry exhaustion → `failure_summary` → exit

---

## Ledger Contract

Same contract as `sprint_exec.dip` and `spec_to_sprints.dip`:

```
sprint_id\ttitle\tstatus\tcreated_at\tupdated_at
```

- `sprint_id`: zero-padded 3-digit string (`001`, `002`, ...)
- `status`: one of `planned`, `in_progress`, `completed`, `skipped`

The runner processes sprints in ledger order. It picks the first row where status is not `completed` and not `skipped`.

---

## Failure Behavior

**Stop on failure.** When a sprint fails after retry exhaustion, the pipeline exits with a failure summary. It does NOT skip failed sprints or continue to the next one.

Rationale: sprints typically have dependencies. A failed Sprint 003 likely means Sprint 004+ cannot succeed. Continuing would waste compute on doomed sprints.

---

## Node Inventory

### Loop Controller (new nodes)

| Node | Type | Model | Purpose |
|------|------|-------|---------|
| `check_ledger` | tool | — | Find next incomplete sprint. Print `all_done` or sprint ID. |
| `report_progress` | tool | — | Print `completed N/M sprints (X%)` after each sprint. |
| `sprint_gate` | human | — | Human approval between sprints. `[S]` to auto-skip. |
| `skip_gate` | tool | — | Log auto-skip with timestamp for audit trail. |

### Sprint Execution (inlined from sprint_exec.dip)

| Node | Type | Model | Purpose |
|------|------|-------|---------|
| `read_sprint` | agent | gemini-3-flash-preview | Read sprint doc, summarize requirements and DoD. |
| `mark_in_progress` | tool | — | Set sprint status to `in_progress` in ledger. |
| `implement_sprint` | agent | claude-sonnet-4-6 | Implement sprint requirements end-to-end. |
| `validate_build` | tool | — | Run build/test commands, auto-detect build system. |
| `commit_work` | agent | gpt-5.4 | Stage and commit implementation changes. |
| `review_claude` | agent | claude-opus-4-6 | Review: correctness, checklist completion. |
| `review_codex` | agent | gpt-5.4 | Review: quality, regression risk. |
| `review_gemini` | agent | gemini-3-flash-preview | Review: robustness, test coverage. |
| 6 critique agents | agent | cross-model | Each model critiques the other two reviews. |
| `review_analysis` | agent | claude-opus-4-6 | Synthesize reviews + critiques into pass/retry/fail. |
| `mark_complete` | tool | — | Set sprint status to `completed` in ledger. |
| `failure_summary` | agent | claude-sonnet-4-6 | Diagnose failure, report what remains. |

### Total: 27 nodes (Start + Exit + 10 new/controller + 15 inlined from sprint_exec)

---

## Review Tournament

Same pattern as `sprint_exec.dip`:

1. **3 parallel reviews** — Claude (correctness), GPT/Codex (quality), Gemini (robustness)
2. **6 parallel critiques** — each model critiques the other two
3. **1 synthesis** — `review_analysis` (Opus) merges into pass/retry/fail verdict

The `review_analysis` node has `goal_gate: true` and `retry_target: implement_sprint` with `max_retries: 3`.

---

## Human Gate

Between sprints, `sprint_gate` pauses for human input:
- `[A]` — provide feedback or adjustments before next sprint
- `[S]` — approve and continue (auto-sent in CLI autonomous mode)

The `skip_gate` tool logs the decision for audit trail, same pattern as `spec_to_sprints.dip`.

---

## Edge Structure

```
Start → check_ledger
check_ledger → Exit                     when tool_stdout = all_done
check_ledger → read_sprint              when tool_stdout != all_done
read_sprint → mark_in_progress
mark_in_progress → implement_sprint
implement_sprint → validate_build
validate_build → commit_work            when ctx.outcome = success
validate_build → implement_sprint       when ctx.outcome = fail       restart: true
validate_build → failure_summary        (unconditional fallback)
commit_work → review_parallel
[review tournament edges]
review_analysis → mark_complete         when ctx.outcome = success
review_analysis → implement_sprint      when ctx.outcome = retry      restart: true
review_analysis → failure_summary       when ctx.outcome = fail
review_analysis → failure_summary       (unconditional fallback)
mark_complete → report_progress
report_progress → sprint_gate
sprint_gate → skip_gate                 label: "[S] Continue"
sprint_gate → failure_summary           label: "[A] Stop"
skip_gate → check_ledger               restart: true
failure_summary → Exit
```

The `skip_gate → check_ledger` edge with `restart: true` is the main loop mechanism. `max_restarts: 50` in defaults allows up to 50 sprint iterations.

---

## Pipeline Defaults

```
max_retries: 3
max_restarts: 50
fidelity: summary:medium
```

`max_restarts: 50` is generous — supports up to ~25 sprints with rework retries. A 20-sprint project with no rework uses 20 restarts.

---

## Pipeline Configuration

- **Phases:** check_ledger → read → implement → validate → commit → review tournament → verdict → complete → progress → gate → loop
- **Tech Stack:** Auto-detected by `validate_build` (Swift, Node, Python, or passthrough)
- **Testing:** `validate_build` tool runs build system tests
- **Quality Gates:** `review_analysis` with `goal_gate: true`, `retry_target: implement_sprint`
- **Human Gates:** `sprint_gate` between sprints, auto-skippable via `[S]`
- **Retry Strategy:** max_retries 3 on implement-validate loop, max_retries 3 on review-implement rework loop. Exhaustion → `failure_summary` → Exit.
- **Models:** Sonnet implements, Opus reviews/synthesizes, GPT-5.4 commits + reviews, Gemini reads + reviews
- **Parallelism:** 3-way review fan-out, 6-way critique fan-out. Sprint execution is sequential.
- **Naming:** All snake_case
- **Loop:** `restart: true` on `skip_gate → check_ledger` edge, bounded by `max_restarts: 50`

---

## Relationship to Other Pipelines

```
spec.md
  → spec_to_sprints.dip (batch decomposition)
    → .ai/ledger.tsv + .ai/sprints/SPRINT-*.md
      → sprint_runner.dip (THIS PIPELINE — loop until done)

Alternative paths:
  → megaplan.dip (plan one sprint) + sprint_exec.dip (execute one sprint)
    → manual iteration

  → sprint_runner.dip can also consume megaplan output
```

`sprint_runner.dip` is the "set it and forget it" executor. `sprint_exec.dip` remains useful for single-sprint runs or debugging.
