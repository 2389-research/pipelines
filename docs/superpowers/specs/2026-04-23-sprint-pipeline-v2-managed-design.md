# Sprint Pipeline v2 — Managed Execution with Three Manager Agents

## Summary

v2 of the sprint-based code generation pipeline adds three manager agents to the execution loop, enhances the decomposition pipeline with a quality gate, and enables mid-execution re-decomposition of mis-scoped sprints. The system is three `.dip` files with clear responsibilities.

### What changes from v1

| Pipeline | v1 | v2 delta |
|---|---|---|
| `spec_to_sprints_yaml` | Tournament → merge → human gate → write docs | + DecompositionManager after merge. + Redecompose mode for sidecar invocation. |
| `sprint_exec_yaml` | Linear setup → implement → review tribunal → commit | + PlanManager (pre-execution). + ReviewManager (pre-verdict). + RecoveryManager (post-failure). Each with own journal. |
| `sprint_runner_yaml` | Loop: check_ledger → exec → report/handle_failure | + Redecompose flow when RecoveryManager signals mis-scoped sprint. + Sidecar ID generation. + Dependency rewriting. |

---

## Architecture

```
spec_to_sprints_yaml_v2.dip          sprint_exec_yaml_v2.dip          sprint_runner_yaml_v2.dip
─────────────────────────────        ───────────────────────          ─────────────────────────
Spec → Analysis → Tournament         Single sprint lifecycle          Loop orchestrator
  → DecompositionManager              with 3 manager agents           + re-decomposition sidecar
  → YAML/MD generation                at strategic points             + failure budget
```

### Manager Agents

Three distinct agents, each with a cross-provider model assignment and a dedicated markdown journal.

| Manager | Model | Provider | Insertion Point | Journal | Reads Journal Of |
|---|---|---|---|---|---|
| PlanManager | claude-opus-4-6 | Anthropic | ReadSprint → **here** → CheckBootstrap | `.ai/managers/plan-journal.md` | RecoveryManager |
| ReviewManager | gpt-5.4 | OpenAI | CritiquesJoin → **here** → ReviewAnalysis | `.ai/managers/review-journal.md` | PlanManager |
| RecoveryManager | gemini-3-flash-preview | Gemini | MarkFailed → **here** → FailureSummary | `.ai/managers/recovery-journal.md` | PlanManager |

### Selective Cross-Reading Flow

```
RecoveryManager → recovery-journal.md → PlanManager reads
PlanManager     → plan-journal.md     → ReviewManager reads
ReviewManager   → review-journal.md   → (standalone record)
```

The cycle is self-reinforcing: failures inform future planning, planning flags inform review focus.

---

## Pipeline 1: `sprint_exec_yaml_v2.dip`

### PlanManager

**Position:** Between ReadSprint and CheckBootstrap.

```
ReadSprint -> PlanManager -> CheckBootstrap
```

**Properties:**
- model: claude-opus-4-6
- provider: anthropic
- reasoning_effort: high
- auto_status: true

**Behavior:**
1. Reads the sprint YAML contract + markdown narrative (already summarized by ReadSprint)
2. Reads `.ai/managers/recovery-journal.md` — checks if prior sprints flagged risks relevant to this one
3. Reads the current codebase state (key files from `entry_preconditions.files_must_exist`)
4. Reads `.ai/ledger.yaml` for recent sprint history (last 3-5 outcomes)
5. Writes a plan brief to `.ai/sprints/SPRINT-<id>-plan-brief.md`
6. Appends a sprint section to `.ai/managers/plan-journal.md`

**Outputs:**
- `STATUS: success` → proceed (go)
- `STATUS: fail` → route to MarkFailed (hold — sprint deferred, not attempted)

**Journal entry format:**
```markdown
## Sprint NNN — Title
**Date:** ISO timestamp
**Recommendation:** GO | HOLD
**Risk flags:** List of specific risks or "None"
**Dependency check:** Which entry_preconditions were verified
**Recovery context:** What RecoveryManager flagged for related sprints (if any)
**Notes:** Free-form observations for future reference
```

### ReviewManager

**Position:** Between CritiquesJoin and ReviewAnalysis.

```
CritiquesJoin -> ReviewManager -> ReviewAnalysis
```

**Properties:**
- model: gpt-5.4
- provider: openai
- reasoning_effort: high

**Behavior:**
1. Reads all 3 reviews + 6 cross-critiques (available via pipeline context)
2. Reads `.ai/managers/plan-journal.md` — checks PlanManager's risk flags for this sprint
3. Synthesizes a structured evidence brief:
   - Agreements across reviewers
   - Disagreements and which side has stronger evidence
   - Scope fence violations detected by any reviewer
   - PlanManager risks that materialized vs. risks that didn't
4. Writes the brief to `.ai/sprints/SPRINT-<id>-review-brief.md`
5. Appends a sprint section to `.ai/managers/review-journal.md`

**Note:** ReviewManager does NOT render a verdict. It prepares organized evidence for ReviewAnalysis, which retains its existing auto_status/retry authority.

**Journal entry format:**
```markdown
## Sprint NNN — Title
**Date:** ISO timestamp
**Reviewer consensus:** PASS | MIXED | FAIL
**Key agreements:** Bullet list
**Key disagreements:** Bullet list with evidence assessment
**PlanManager risk check:** Which flagged risks materialized
**Scope fence violations:** Any detected, or "None"
**Evidence quality:** Assessment of review thoroughness
```

### RecoveryManager

**Position:** Between MarkFailed and FailureSummary.

```
MarkFailed -> RecoveryManager -> FailureSummary | (redecompose signal)
```

**Properties:**
- model: gemini-3-flash-preview
- provider: gemini
- reasoning_effort: high
- auto_status: true

**Behavior:**
1. Reads the sprint YAML including `history.attempts`
2. Reads `.ai/managers/plan-journal.md` — were the risks PlanManager flagged the actual cause of failure?
3. Reads the failure evidence from the current pipeline run
4. Performs root-cause analysis:
   - **Implementation failure** — bad code, fixable with retry
   - **Scope failure** — sprint too large or too vague, needs re-decomposition
   - **Dependency failure** — prior sprint left gaps, this sprint can't succeed as-is
5. Writes a recovery analysis to `.ai/sprints/SPRINT-<id>-recovery-analysis.md`
6. Appends a sprint section to `.ai/managers/recovery-journal.md`

**Outputs:**
- `STATUS: success` with stdout containing `retry` → simple retry (FailureSummary then exit, runner handles retry)
- `STATUS: success` with stdout containing `redecompose` → writes `.ai/redecompose-request.yaml`, proceeds to FailureSummary then exit (runner handles re-decomposition)
- `STATUS: success` with stdout containing `abandon` → proceed to FailureSummary then exit (runner skips this sprint)

**Redecompose request format:**
```yaml
mode: redecompose
failed_sprint_id: "023"
failed_sprint_title: "Claude & Gemini Provider Adapters"
scope: "original scope description from the sprint YAML"
failure_reason: "from RecoveryManager's root-cause analysis"
recovery_recommendation: "split into per-provider sprints"
existing_sprint_count: 30
next_available_id: "030"
depends_on_from_original: ["006", "019"]
original_dependents: ["029"]
```

**Journal entry format:**
```markdown
## Sprint NNN — Title
**Date:** ISO timestamp
**Root cause:** implementation | scope | dependency
**Failure detail:** Specific description
**PlanManager alignment:** Did PlanManager's risk flags predict this failure?
**Recommendation:** RETRY | REDECOMPOSE | ABANDON
**Recovery notes:** What should change on retry or re-decomposition
```

### Updated Edge Map (exec pipeline)

Changes from v1 marked with `# NEW`:

```
# Setup chain (unchanged)
Start -> EnsureLedger
EnsureLedger -> CheckYq
CheckYq -> FindNextSprint          when ctx.tool_stdout = yq-ok
CheckYq -> YqMissing               when ctx.tool_stdout = yq-not-found
YqMissing -> Exit
FindNextSprint -> SetCurrentSprint  when ctx.tool_stdout startswith found-
FindNextSprint -> Exit              when ctx.tool_stdout = all-done
FindNextSprint -> Exit              when ctx.tool_stdout = deps-blocked
SetCurrentSprint -> ReadSprint      when ctx.tool_stdout startswith current-
SetCurrentSprint -> Exit            when ctx.tool_stdout = all-done

# PlanManager gate (NEW)
ReadSprint -> PlanManager                                                    # NEW
PlanManager -> CheckBootstrap       when ctx.outcome = success  label: go    # NEW
PlanManager -> MarkFailed           when ctx.outcome = fail     label: hold  # NEW

# Implementation chain (unchanged)
CheckBootstrap -> MarkInProgress
MarkInProgress -> Exit              when ctx.tool_stdout startswith already-completed
MarkInProgress -> SnapshotLedger
SnapshotLedger -> ImplementSprint
ImplementSprint -> CheckLedgerIntegrity  when ctx.outcome = success
ImplementSprint -> ResumeCheck           when ctx.outcome = fail
ImplementSprint -> MarkFailed
CheckLedgerIntegrity -> ValidateBuild    when ctx.outcome = success
CheckLedgerIntegrity -> MarkFailed       when ctx.outcome = fail
ResumeCheck -> ImplementSprint           when ctx.tool_stdout startswith resume-    restart: true
ResumeCheck -> CheckBootstrapOnFailure   when ctx.tool_stdout startswith max-resumes-
ResumeCheck -> MarkFailed                when ctx.outcome = fail
CheckBootstrapOnFailure -> HumanBootstrapGate  when ctx.tool_stdout = bootstrap-failed
CheckBootstrapOnFailure -> MarkFailed          when ctx.tool_stdout = normal-failed
HumanBootstrapGate -> SnapshotLedger     label: "[S] Retry"  restart: true
HumanBootstrapGate -> MarkFailed         label: "[A] Abort"
ValidateBuild -> CommitSprintWork        when ctx.outcome = success
ValidateBuild -> ImplementSprint         when ctx.outcome = fail    restart: true
ValidateBuild -> MarkFailed
CommitSprintWork -> CheckBootstrapSkip

# Review chain with ReviewManager (MODIFIED)
CheckBootstrapSkip -> ValidateDoD        when ctx.tool_stdout = bootstrap-skip-reviews
CheckBootstrapSkip -> ReviewParallel     when ctx.tool_stdout = normal-reviews
ReviewParallel -> ReviewClaude, ReviewCodex, ReviewGemini
ReviewClaude, ReviewCodex, ReviewGemini -> ReviewsJoin
ReviewsJoin -> CritiquesParallel
CritiquesParallel -> [6 critique agents]
[6 critique agents] -> CritiquesJoin
CritiquesJoin -> ReviewManager                                               # NEW (was -> ReviewAnalysis)
ReviewManager -> ReviewAnalysis                                              # NEW
ReviewAnalysis -> ValidateDoD            when ctx.outcome = success
ReviewAnalysis -> MarkFailed             when ctx.outcome = fail

# Completion (unchanged)
ValidateDoD -> CompleteSprint            when ctx.tool_stdout = dod-pass
ValidateDoD -> ImplementSprint           when ctx.tool_stdout startswith dod-fail  restart: true
CompleteSprint -> Exit                   when ctx.outcome = success
CompleteSprint -> MarkFailed             when ctx.outcome = fail

# Failure chain with RecoveryManager (MODIFIED)
MarkFailed -> RecoveryManager                                                # NEW (was -> FailureSummary)
RecoveryManager -> FailureSummary                                            # NEW
FailureSummary -> Exit
```

### EnsureManagerJournals tool (new)

Added to the setup chain after EnsureLedger:

```
EnsureLedger -> EnsureManagerJournals -> CheckYq
```

Creates `.ai/managers/` directory and initializes empty journal files if they don't exist:
- `.ai/managers/plan-journal.md` with header `# Plan Journal`
- `.ai/managers/review-journal.md` with header `# Review Journal`
- `.ai/managers/recovery-journal.md` with header `# Recovery Journal`

---

## Pipeline 2: `spec_to_sprints_yaml_v2.dip`

### DecompositionManager (between merge_decomposition and present_plan)

**Position:**
```
merge_decomposition -> DecompositionManager -> present_plan
```

**Properties:**
- model: claude-opus-4-6
- provider: anthropic
- reasoning_effort: high
- auto_status: true

**Checks:**
1. Sizing audit — any sprint with >10 DoD items or >3 subsystems
2. Dependency cycle detection — verify graph is a DAG
3. FR coverage matrix — every FR from spec_analysis.md assigned to at least one sprint
4. Scope fence quality — every sprint has meaningful `off_limits`
5. Validation command quality — commands are runnable, not pseudocode
6. Risk sequencing — high-complexity sprints have their dependencies in place
7. Capstone sprint dependency completeness — last sprint depends on all others

**Behavior:**
1. Reads `.ai/sprint_plan.md` and `.ai/spec_analysis.md`
2. Performs all checks above
3. Writes findings to `.ai/drafts/decomposition_review.md`
4. If issues found: rewrites `sprint_plan.md` with fixes applied
5. Outputs `STATUS: success` (always proceeds to present_plan — the human gate is the final decision)

### Redecompose Mode

When `.ai/redecompose-request.yaml` exists, the pipeline operates in single-sprint re-decomposition mode.

**Updated `check_resume` tool** adds a new check at the top:
```bash
if [ -f .ai/redecompose-request.yaml ]; then
  printf 'redecompose-mode'
  exit 0
fi
```

**New edge:**
```
check_resume -> redecompose_single  when ctx.tool_stdout = redecompose-mode  label: redecompose
```

**`redecompose_single` agent:**
- model: claude-opus-4-6
- provider: anthropic
- reasoning_effort: high

Behavior:
1. Reads `.ai/redecompose-request.yaml`
2. Reads the original failed sprint's YAML and RecoveryManager's analysis
3. Splits the scope into 2-4 sub-sprints
4. Assigns new IDs starting from `next_available_id`
5. Sets `depends_on` to the original sprint's dependencies
6. Writes new YAML+MD pairs to `.ai/sprints/`
7. Writes `.ai/redecompose-result.yaml`:

```yaml
original_sprint_id: "023"
new_sprint_ids: ["030", "031"]
new_sprint_titles:
  "030": "Anthropic Claude Provider Adapter"
  "031": "Google Gemini Provider Adapter"
dependents_to_rewrite:
  "029":
    old_dep: "023"
    new_deps: ["030", "031"]
```

**Flow after redecompose_single:**
```
redecompose_single -> DecompositionManager -> write_ledger_redecompose -> validate_output -> commit_output -> Exit
```

**`write_ledger_redecompose` (tool):**
Appends new sprints to the existing `ledger.yaml` (unlike the full `write_ledger` which overwrites). For each new YAML file written by `redecompose_single`, it appends a sprint entry with `status: planned`. It does NOT rewrite dependents or mark the original sprint — that's the runner's job via `splice_ledger`.

DecompositionManager reviews the sub-sprints for quality before they're committed. No human gate for re-decomposition — RecoveryManager already made the strategic decision, and the sub-sprints are scoped narrowly enough that automated review suffices.

---

## Pipeline 3: `sprint_runner_yaml_v2.dip`

### New nodes

**`prepare_redecompose` (tool):**
Reads `.ai/redecompose-request.yaml`, validates the request, calculates `next_available_id` from the current ledger, and writes the finalized request.

**`redecompose_sprint` (subgraph):**
```
ref: spec_to_sprints_yaml_v2.dip
```

Invokes the decomposition pipeline in redecompose mode.

**`splice_ledger` (tool):**
After redecomposition completes:
1. Reads `.ai/redecompose-result.yaml` for new sprint IDs
2. Rewrites `depends_on` for original dependents (e.g., capstone sprint)
3. Marks the original failed sprint as `redecomposed` in the ledger
4. Cleans up `.ai/redecompose-request.yaml` and `.ai/redecompose-result.yaml`

**`report_redecompose` (tool):**
Reports what happened: sprint count, new IDs, updated dependents.

### Updated handle_failure tool

Adds redecompose detection:
```bash
# Check if RecoveryManager requested redecomposition
if [ -f .ai/redecompose-request.yaml ]; then
  printf 'redecompose-%s' "$target"
  exit 0
fi
```

### Updated check_ledger tool

Treats `redecomposed` status like `skipped`:
```bash
candidates=$(yq '.sprints[] | select(.status != "completed" and .status != "skipped" and .status != "failed" and .status != "redecomposed") | .id' .ai/ledger.yaml)
```

### Updated edge map

Changes from v1 marked:

```
# Same setup as v1
Start -> check_yq
check_yq -> check_ledger           when ctx.tool_stdout = yq-ok
check_yq -> yq_missing             when ctx.tool_stdout = yq-not-found
yq_missing -> Exit
check_ledger -> Exit                when ctx.tool_stdout = all_done
check_ledger -> no_ledger_exit      when ctx.tool_stdout = no_ledger
check_ledger -> deps_blocked_exit   when ctx.tool_stdout = deps_blocked
check_ledger -> execute_sprint      when ctx.tool_stdout startswith next-
no_ledger_exit -> Exit
deps_blocked_exit -> Exit

# Execution and success (unchanged)
execute_sprint -> report_progress   when ctx.outcome = success
report_progress -> check_ledger     restart: true

# Failure handling (MODIFIED)
execute_sprint -> handle_failure    when ctx.outcome = fail
handle_failure -> check_ledger           when ctx.tool_stdout startswith retry-        restart: true
handle_failure -> check_ledger           when ctx.tool_stdout startswith skipped-      restart: true
handle_failure -> failure_summary        when ctx.tool_stdout startswith budget-
handle_failure -> prepare_redecompose    when ctx.tool_stdout startswith redecompose-  # NEW

# Redecomposition chain (NEW)
prepare_redecompose -> redecompose_sprint                                              # NEW
redecompose_sprint -> splice_ledger      when ctx.outcome = success                    # NEW
redecompose_sprint -> failure_summary    when ctx.outcome = fail                        # NEW
splice_ledger -> report_redecompose                                                    # NEW
report_redecompose -> check_ledger       restart: true                                 # NEW

failure_summary -> Exit
```

---

## Journal Lifecycle

### Initialization
`EnsureManagerJournals` tool in the exec pipeline creates `.ai/managers/` and empty journals on first run.

### Growth
Each manager appends one `## Sprint NNN` section per invocation. Over a 30-sprint run, each journal accumulates ~30 sections.

### Cross-reading
Managers read the relevant upstream journal before acting. They scan for the most recent 3-5 entries plus any entries tagged with the current sprint's dependencies.

### Persistence
Journals are committed alongside sprint artifacts by `CommitSprintWork`. They survive across runner restarts and pipeline re-invocations.

### Re-decomposition context
When a sprint is re-decomposed, RecoveryManager's journal entry for that sprint becomes the authoritative context for PlanManager when it encounters the replacement sub-sprints.

---

## New Ledger Status: `redecomposed`

A sprint marked `redecomposed` means it was replaced by sub-sprints via the sidecar re-decomposition flow. It is terminal — the runner never re-attempts it.

Valid status transitions:
```
planned -> in_progress -> completed
planned -> in_progress -> failed -> redecomposed
planned -> in_progress -> failed (terminal if no redecompose)
planned -> skipped (manual)
```

---

## File Layout

New files created by v2 (relative to project working directory):

```
.ai/
  managers/
    plan-journal.md
    review-journal.md
    recovery-journal.md
  sprints/
    SPRINT-<id>-plan-brief.md        (per sprint, written by PlanManager)
    SPRINT-<id>-review-brief.md      (per sprint, written by ReviewManager)
    SPRINT-<id>-recovery-analysis.md (per failed sprint, written by RecoveryManager)
  redecompose-request.yaml           (transient, written by RecoveryManager, consumed by runner)
  redecompose-result.yaml            (transient, written by decomposition pipeline, consumed by runner)
  drafts/
    decomposition_review.md          (written by DecompositionManager)
```

Pipeline files (in the pipelines repo):

```
spec_to_sprints_yaml_v2.dip
sprint_exec_yaml_v2.dip
sprint_runner_yaml_v2.dip
```

---

## Model Assignments (complete)

### Exec pipeline
| Node | Model | Provider | Role |
|---|---|---|---|
| ReadSprint | gemini-3-flash-preview | Gemini | Sprint summarization |
| **PlanManager** | **claude-opus-4-6** | **Anthropic** | **Pre-execution planning** |
| ImplementSprint | claude-sonnet-4-6 | Anthropic | Code generation |
| CommitSprintWork | gpt-5.4 | OpenAI | Git operations |
| ReviewClaude | claude-opus-4-6 | Anthropic | Review |
| ReviewCodex | gpt-5.4 | OpenAI | Review |
| ReviewGemini | gemini-3-flash-preview | Gemini | Review |
| 6x Critiques | (same as v1) | (mixed) | Cross-critique |
| **ReviewManager** | **gpt-5.4** | **OpenAI** | **Evidence synthesis** |
| ReviewAnalysis | claude-opus-4-6 | Anthropic | Verdict |
| **RecoveryManager** | **gemini-3-flash-preview** | **Gemini** | **Failure triage** |
| FailureSummary | claude-sonnet-4-6 | Anthropic | Failure report |

### Decomposition pipeline
| Node | Model | Provider | Role |
|---|---|---|---|
| analyze_spec | gpt-5.4 | OpenAI | Spec analysis |
| decompose_claude | claude-opus-4-6 | Anthropic | Tournament |
| decompose_gpt | gpt-5.2 | OpenAI | Tournament |
| decompose_gemini | gemini-3-flash-preview | Gemini | Tournament |
| 6x Critiques | (same as v1) | (mixed) | Cross-critique |
| merge_decomposition | claude-opus-4-6 | Anthropic | Synthesis |
| **DecompositionManager** | **claude-opus-4-6** | **Anthropic** | **Plan quality gate** |
| **redecompose_single** | **claude-opus-4-6** | **Anthropic** | **Single-sprint split** |
| present_plan | claude-sonnet-4-6 | Anthropic | Summary |
| apply_feedback | claude-opus-4-6 | Anthropic | Revision |
