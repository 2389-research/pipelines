# Spec-to-Sprints Pipeline Design

**Date:** 2026-04-08
**Status:** Approved design
**Author:** Doctor Biz + Claude Opus 4.6

---

## Summary

A DIP pipeline that takes a specification document and decomposes it into a complete `.ai/` workspace ready for `sprint_exec.dip` execution. Uses multi-model tournament decomposition with cross-critique, human approval gate, and full sprint doc generation.

**Input:** A spec file (e.g., `spec.md`) in the working directory.

**Output:**
- `.ai/ledger.tsv` — header + N rows, all status `planned`
- `.ai/sprints/SPRINT-001.md` through `SPRINT-N.md` — full sprint docs with requirements, DoD checklist, expected artifacts
- `.ai/spec_analysis.md` — structured spec analysis (audit trail)
- `.ai/sprint_plan.md` — merged decomposition plan (audit trail)
- Git commit of all generated files (skipped gracefully if no git repo)

---

## Motivation

The existing pipeline pair — `megaplan.dip` (plans one sprint per invocation) and `sprint_exec.dip` (executes one sprint per invocation) — both consume a shared `.ai/ledger.tsv` and `.ai/sprints/SPRINT-<id>.md` convention. But nothing produces the full ledger + sprint docs from a spec in one shot.

Megaplan plans incrementally (one sprint at a time, orienting from codebase state). Sprint_exec assumes the sprint docs already exist. The gap: upfront decomposition of a spec into an executable sprint backlog.

This pipeline fills that gap.

---

## Ledger Contract

Both `megaplan.dip` and `sprint_exec.dip` expect this exact TSV schema:

```
sprint_id\ttitle\tstatus\tcreated_at\tupdated_at
```

- `sprint_id`: zero-padded 3-digit string (`001`, `002`, ...)
- `title`: human-readable sprint title
- `status`: one of `planned`, `in_progress`, `completed`, `skipped`
- `created_at`: ISO 8601 UTC timestamp
- `updated_at`: ISO 8601 UTC timestamp

Sprint docs live at `.ai/sprints/SPRINT-<id>.md` where `<id>` matches `sprint_id`.

This pipeline writes all rows with status `planned`. Sprint_exec handles the `planned` → `in_progress` → `completed` lifecycle.

---

## Sprint Doc Contract

Each `SPRINT-<id>.md` must contain the following sections to satisfy `sprint_exec.dip`'s `ReadSprint` agent, `ImplementSprint` agent, and review agents:

### Required sections

- **Title and scope**: what this sprint delivers and what is explicitly excluded
- **Requirements**: concrete requirements traced to spec sections
- **Dependencies**: which prior sprints must be completed first
- **Expected artifacts**: files, modules, tests, or configurations this sprint produces
- **DoD checklist**: checkable items (`- [ ]`) that the implementing agent marks off and reviewers validate against
- **Validation plan**: how to verify the sprint is complete (build commands, test commands, manual checks)

### Example structure

```markdown
# Sprint 003 — Audio Capture Layer

## Scope
Implement microphone and system audio capture with source labeling.

## Non-goals
- ASR integration (Sprint 005)
- UI rendering (Sprint 007)

## Requirements
- FR2: Support mic-only, system-only, and dual capture modes
- FR2: Continue operating if one source becomes unavailable
- FR2: Surface permission failures clearly

## Dependencies
- Sprint 001 (project scaffold)
- Sprint 002 (data models)

## Expected Artifacts
- `Core/AudioCapture/MicrophoneCapture.swift`
- `Core/AudioCapture/SystemAudioCapture.swift`
- `Core/AudioNormalization/AudioNormalizer.swift`
- `Tests/Unit/AudioCaptureTests.swift`

## DoD
- [ ] Microphone capture produces timestamped AudioFrame structs
- [ ] System audio capture produces timestamped AudioFrame structs
- [ ] Both sources carry correct source labels
- [ ] Single-source failure does not crash the other source
- [ ] Permission denial surfaces a recoverable error
- [ ] Unit tests cover all three capture modes
- [ ] Unit tests cover single-source failure

## Validation
- `swift build` succeeds with no errors
- `swift test --filter AudioCaptureTests` passes
```

---

## Pipeline Architecture

### Section 1: Spec Discovery & Analysis

| Node | Type | Model | Provider | Purpose |
|------|------|-------|----------|---------|
| `find_spec` | tool | — | — | Search for `spec.md` and known variants (`SPEC.md`, `design.md`, `specification.md`, `requirements.md`, `prompt_plan.md`). Falls back to first `.md` within 2 directory levels. |
| `no_spec_exit` | agent | — | — | Exit message explaining no spec was found and how to provide one. |
| `analyze_spec` | agent | gpt-5.4 | openai | Deep structured analysis of the spec. Extracts: all functional requirements with IDs, architectural layers, feature dependencies, complexity signals, acceptance criteria, rollout phases, open questions. Writes `.ai/spec_analysis.md`. |

**Analysis output contract** (`.ai/spec_analysis.md`):
- Numbered requirement list with spec section references
- Dependency graph between features/subsystems
- Complexity assessment per feature area
- Rollout phase mapping (if spec defines phases)
- Flagged ambiguities or open questions

**Edges:**
```
Start → find_spec
find_spec → analyze_spec       when tool_stdout != "no_spec_found"
find_spec → no_spec_exit       when tool_stdout = "no_spec_found"
no_spec_exit → Exit
```

### Section 2: Multi-Model Decomposition Tournament

Three models independently decompose the analyzed spec into sprint lists.

**Decomposition agents (parallel):**

| Node | Model | Provider | Emphasis |
|------|-------|----------|----------|
| `decompose_claude` | claude-opus-4-6 | anthropic | Thoroughness — dependency ordering, risk sequencing, DoD traceability back to spec requirement IDs |
| `decompose_gpt` | gpt-5.2 | openai | Implementation pragmatism — execution order, parallelization opportunities, build/test feasibility per sprint |
| `decompose_gemini` | gemini-3-flash-preview | gemini | Delivery robustness — scope discipline, sprint size consistency, validation checkpoints, risk mitigation |

All three have `reasoning_effort: high`.

Each decomposition agent produces a numbered sprint list where each sprint has:
- Sprint number and title
- Scope description
- Spec requirement IDs covered
- Dependencies (by sprint number)
- Expected artifacts
- DoD items
- Estimated complexity (low/medium/high)

**Cross-critique agents (6, parallel):**

| Node | Model | Provider | Reviews |
|------|-------|----------|---------|
| `critique_claude_on_gpt` | claude-opus-4-6 | anthropic | GPT's decomposition |
| `critique_claude_on_gemini` | claude-opus-4-6 | anthropic | Gemini's decomposition |
| `critique_gpt_on_claude` | gpt-5.2 | openai | Claude's decomposition |
| `critique_gpt_on_gemini` | gpt-5.2 | openai | Gemini's decomposition |
| `critique_gemini_on_claude` | gemini-3-flash-preview | gemini | Claude's decomposition |
| `critique_gemini_on_gpt` | gemini-3-flash-preview | gemini | GPT's decomposition |

All have `reasoning_effort: high`.

Each critique evaluates: missed requirements, ordering errors, scope gaps, sprints that are too large or too small, dependency cycles, coverage of spec acceptance criteria.

**Merge agent:**

| Node | Model | Provider | Purpose |
|------|-------|----------|---------|
| `merge_decomposition` | claude-opus-4-6 | anthropic | Synthesize three decompositions + six critiques into one final ordered sprint list. Writes `.ai/sprint_plan.md`. |

Has `reasoning_effort: high`.

**Edges:**
```
analyze_spec → DecomposeParallel
DecomposeParallel → decompose_claude
DecomposeParallel → decompose_gpt
DecomposeParallel → decompose_gemini
decompose_claude → DecomposeJoin
decompose_gpt → DecomposeJoin
decompose_gemini → DecomposeJoin
DecomposeJoin → CritiqueParallel
CritiqueParallel → critique_claude_on_gpt
CritiqueParallel → critique_claude_on_gemini
CritiqueParallel → critique_gpt_on_claude
CritiqueParallel → critique_gpt_on_gemini
CritiqueParallel → critique_gemini_on_claude
CritiqueParallel → critique_gemini_on_gpt
critique_claude_on_gpt → CritiqueJoin
critique_claude_on_gemini → CritiqueJoin
critique_gpt_on_claude → CritiqueJoin
critique_gpt_on_gemini → CritiqueJoin
critique_gemini_on_claude → CritiqueJoin
critique_gemini_on_gpt → CritiqueJoin
CritiqueJoin → merge_decomposition
```

### Section 3: Human Approval Gate

| Node | Type | Model | Provider | Purpose |
|------|------|-------|----------|---------|
| `present_plan` | agent | claude-sonnet-4-6 | anthropic | Formats `.ai/sprint_plan.md` into a concise review summary: sprint count, titles, dependency graph, spec coverage |
| `approval_gate` | human | — | — | Human reviews sprint list |
| `apply_feedback` | agent | claude-opus-4-6 | anthropic | Incorporates human feedback, rewrites `.ai/sprint_plan.md` |
| `skip_approval` | agent | gemini-3-flash-preview | gemini | Documents skip assumptions for audit trail. `reasoning_effort: low`. |

**Edges:**
```
merge_decomposition → present_plan → approval_gate
approval_gate → apply_feedback    label: "[A] Revise plan"
approval_gate → skip_approval     label: "[S] Approve / Skip"
apply_feedback → approval_gate
skip_approval → setup_workspace
```

The `apply_feedback → approval_gate` loop allows iterating until the human is satisfied. CLI autonomous mode sends `[S]` automatically.

### Section 4: Sprint Doc Generation & Ledger

| Node | Type | Model | Provider | Purpose |
|------|------|-------|----------|---------|
| `setup_workspace` | tool | — | — | `mkdir -p .ai/sprints .ai/drafts`. Create `ledger.tsv` with header if it does not exist. |
| `write_sprint_docs` | agent | claude-opus-4-6 | anthropic | Reads `.ai/sprint_plan.md` and `.ai/spec_analysis.md`. Writes each `SPRINT-<id>.md` following the sprint doc contract. Single agent for cross-sprint consistency. `reasoning_effort: high`. |
| `write_ledger` | tool | — | — | Shell: reads all `SPRINT-*.md` filenames from `.ai/sprints/`, generates a ledger row per file with status `planned` and current UTC timestamp. Appends to existing ledger (does not overwrite prior rows). |
| `validate_output` | tool | — | — | Shell: verify every ledger row has a matching `SPRINT-<id>.md`, every sprint doc contains a `## DoD` section, no orphan files, no orphan ledger rows. Outputs `valid` or `invalid-<reason>`. |
| `validation_failed` | agent | claude-sonnet-4-6 | anthropic | Diagnoses validation failure and reports what is missing or malformed. |
| `commit_output` | tool | — | — | Shell: if `.git` directory exists, `git add .ai/ledger.tsv .ai/sprints/ .ai/spec_analysis.md .ai/sprint_plan.md` and commit with conventional commit message. If no git repo, print `no-git-skipped` and exit 0. |

**Edges:**
```
skip_approval → setup_workspace
setup_workspace → write_sprint_docs
write_sprint_docs → write_ledger
write_ledger → validate_output
validate_output → commit_output         when tool_stdout = "valid"
validate_output → write_sprint_docs     when tool_stdout != "valid"  label: fix_validation
commit_output → Exit
validation_failed → Exit
```

The `validate_output → write_sprint_docs` retry loop uses `max_retries` from defaults. After exhausting retries, the edge to `validation_failed` fires.

---

## Pipeline Defaults

```
max_retries: 3
max_restarts: 10
fidelity: summary:medium
```

---

## Model Routing Summary

| Role | Model | Provider | Reasoning |
|------|-------|----------|-----------|
| Spec analysis | gpt-5.4 | openai | Fresh perspective before tournament; high reasoning for deep extraction |
| Decomposition (thoroughness) | claude-opus-4-6 | anthropic | Strong at dependency tracing and requirement coverage |
| Decomposition (pragmatism) | gpt-5.2 | openai | Strong at implementation sequencing |
| Decomposition (robustness) | gemini-3-flash-preview | gemini | Strong at scope discipline and risk |
| Cross-critique | same 3 models | all | Each critiques the other two |
| Merge | claude-opus-4-6 | anthropic | Synthesis and final arbitration |
| Plan presentation | claude-sonnet-4-6 | anthropic | Formatting, lighter task |
| Feedback incorporation | claude-opus-4-6 | anthropic | Needs full context to revise well |
| Skip documentation | gemini-3-flash-preview | gemini | Trivial task, low effort |
| Sprint doc writing | claude-opus-4-6 | anthropic | Needs full spec + plan context, cross-sprint consistency |
| Validation failure diagnosis | claude-sonnet-4-6 | anthropic | Diagnostic, lighter task |

---

## Relationship to Other Pipelines

```
spec.md
  → spec_to_sprints.dip (this pipeline)
    → .ai/ledger.tsv + .ai/sprints/SPRINT-*.md
      → sprint_exec.dip (execute each sprint)

Alternative incremental path:
  → megaplan.dip (plan one sprint at a time from codebase state)
    → .ai/ledger.tsv + .ai/sprints/SPRINT-<next>.md
      → sprint_exec.dip
```

`spec_to_sprints.dip` is for upfront decomposition when you have a complete spec.
`megaplan.dip` is for incremental planning when you are discovering scope as you go.
Both produce the same output format. `sprint_exec.dip` consumes either.

---

## Open Questions (Resolved)

1. **Sprint granularity** — Pipeline proposes, human approves via gate. CLI can auto-skip.
2. **Sprint doc depth** — Full-fat, ready for sprint_exec. No stub/skeleton mode.
3. **Multi-model pattern** — Full tournament on decomposition. Single-author (Opus) for sprint docs.
4. **Git behavior** — Commit if repo exists, skip gracefully if not.
