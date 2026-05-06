# YAML Sprint Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create three new dip files (`sprint_exec_yaml.dip`, `sprint_runner_yaml.dip`, `spec_to_sprints_yaml.dip`) that replace TSV-based sprint tracking with YAML-based structured metadata, adding bootstrap sprint routing with human gates.

**Architecture:** Each new file is forked from its original (`sprint_exec.dip`, `sprint_runner.dip`, `spec_to_sprints.dip`). Tool nodes switch from `awk`-on-TSV to `yq`-on-YAML. A `CheckBootstrap` node branches execution: bootstrap sprints skip the review tournament and get human gates on failure. `spec_to_sprints_yaml.dip` auto-generates bootstrap sprints (000–002) and writes dual YAML+md output.

**Tech Stack:** Dip DSL (tracker pipeline format), `yq` (Go-based YAML processor), POSIX shell for tool nodes

**Spec:** `docs/superpowers/specs/2026-04-16-yaml-sprint-pipeline-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `sprint_exec_yaml.dip` | Create (based on `sprint_exec.dip`) | Execute one sprint: YAML reading, bootstrap detection, bootstrap vs normal routing |
| `sprint_runner_yaml.dip` | Create (based on `sprint_runner.dip`) | Loop through all sprints: YAML ledger reading, subgraph to sprint_exec_yaml.dip |
| `spec_to_sprints_yaml.dip` | Create (based on `spec_to_sprints.dip`) | Decompose spec into sprints: bootstrap generation, dual YAML+md output, YAML ledger |

No existing files are modified.

---

### Task 1: sprint_exec_yaml.dip — Scaffold and YAML preamble nodes

**Files:**
- Create: `sprint_exec_yaml.dip`
- Reference: `sprint_exec.dip` (original to fork from)

This task creates the file with the workflow header, Start/Exit agents, and all tool nodes up through CheckBootstrap. Later tasks add the implementation nodes, review tournament, and edge routing.

- [ ] **Step 1: Create the file with workflow header, defaults, Start, Exit**

```dip
workflow SprintExecYaml
  goal: "Execute the next incomplete sprint from .ai/ledger.yaml through implementation, validation, multi-model review, and completion. Uses per-sprint YAML contracts for structured metadata."
  start: Start
  exit: Exit

  defaults
    fidelity: summary:medium

  agent Start
    label: Start
    prompt:
      Acknowledge that the sprint execution pipeline is starting. Report ready status.

      HARD CONSTRAINT: Do NOT read project files. Do NOT write code. Do NOT create, modify, or delete any files. Your ONLY job is to acknowledge the pipeline start. If you do anything else, the pipeline fails.

  agent Exit
    label: Exit
    prompt:
      The sprint execution pipeline is complete. Report final status.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete any files. Do NOT run tests. Do NOT debug anything. Your ONLY job is to acknowledge completion. If prior nodes left work undone, that is not your problem — the pipeline will handle retries.
```

- [ ] **Step 2: Add EnsureLedger tool node (YAML version)**

This replaces the TSV EnsureLedger. It creates `.ai/ledger.yaml` with a bootstrap sprint if no ledger exists.

```dip
  tool EnsureLedger
    label: "Ensure Ledger"
    timeout: 30s
    command:
      set -eu
      mkdir -p .ai .ai/drafts .ai/sprints
      if [ ! -f .ai/ledger.yaml ]; then
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        cat > .ai/ledger.yaml <<LEDGER
project:
  name: "Unknown"
  stack:
    lang: null
    runner: null
    test: null
    lint: null
    build: null
  created_at: "$now"

sprints:
  - id: "000"
    title: "Bootstrap sprint"
    status: planned
    bootstrap: true
    depends_on: []
    complexity: low
    created_at: "$now"
    updated_at: "$now"
    attempts: 0
    total_cost: "0.00"
LEDGER
      fi
      printf 'ledger-ready'
```

- [ ] **Step 3: Add CheckYq tool node**

```dip
  tool CheckYq
    label: "Check yq"
    timeout: 5s
    command:
      set -eu
      if ! command -v yq >/dev/null 2>&1; then
        printf 'yq-not-found'
        exit 0
      fi
      printf 'yq-ok'
```

- [ ] **Step 4: Add YqMissing agent node (install instructions)**

```dip
  agent YqMissing
    label: "yq Not Found"
    prompt:
      The yq YAML processor is required but not installed.

      Install it:
        macOS:  brew install yq
        Linux:  snap install yq  OR  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq

      After installing, re-run the pipeline.
```

- [ ] **Step 5: Add FindNextSprint agent node (YAML-aware)**

```dip
  agent FindNextSprint
    label: "Find Next Sprint"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Read .ai/ledger.yaml. Find the first sprint entry where status is NOT "completed" or "skipped". Report that sprint ID and its title. That is the next sprint.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete any files other than reading .ai/ledger.yaml. Do NOT implement anything. Do NOT install dependencies. Your ONLY job is to identify and report which sprint is next.
```

- [ ] **Step 6: Add SetCurrentSprint tool node (yq version)**

```dip
  tool SetCurrentSprint
    label: "Set Current Sprint"
    timeout: 30s
    command:
      set -eu
      target=$(yq '.sprints[] | select(.status != "completed" and .status != "skipped") | .id' .ai/ledger.yaml | head -1)
      if [ -z "$target" ]; then
        target=$(yq '.sprints[-1].id' .ai/ledger.yaml)
      fi
      printf '%s' "$target" > .ai/current_sprint_id.txt
      printf 'current-%s' "$target"
```

- [ ] **Step 7: Add ReadSprint agent node (reads YAML + md)**

```dip
  agent ReadSprint
    label: "Read Sprint"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Read .ai/current_sprint_id.txt to get the sprint ID. Then read BOTH:
      1. .ai/sprints/SPRINT-<id>.yaml — the structured contract (scope fence, validation commands, artifacts, dependencies, failure history)
      2. .ai/sprints/SPRINT-<id>.md — the narrative description

      Summarize: (1) what the sprint requires, (2) which DoD checklist items are done vs pending, (3) expected artifacts, (4) any prior failure history from the YAML.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete any files. Do NOT implement anything. Do NOT install dependencies. Your ONLY job is to read and summarize the sprint documents.
```

- [ ] **Step 8: Add CheckBootstrap tool node**

```dip
  tool CheckBootstrap
    label: "Check Bootstrap"
    timeout: 5s
    command:
      set -eu
      target=$(cat .ai/current_sprint_id.txt)
      sprint_yaml=".ai/sprints/SPRINT-${target}.yaml"
      if [ ! -f "$sprint_yaml" ]; then
        printf 'bootstrap-false'
        exit 0
      fi
      is_bootstrap=$(yq '.bootstrap // false' "$sprint_yaml")
      if [ "$is_bootstrap" = "true" ]; then
        printf 'bootstrap-true'
      else
        printf 'bootstrap-false'
      fi
```

- [ ] **Step 9: Add MarkInProgress tool node (yq version)**

```dip
  tool MarkInProgress
    label: "Mark In Progress"
    timeout: 30s
    command:
      set -eu
      target=$(cat .ai/current_sprint_id.txt)
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      yq -i "(.sprints[] | select(.id == \"$target\")).status = \"in_progress\" | (.sprints[] | select(.id == \"$target\")).updated_at = \"$now\"" .ai/ledger.yaml
      if [ -f ".ai/sprints/SPRINT-${target}.yaml" ]; then
        yq -i ".status = \"in_progress\"" ".ai/sprints/SPRINT-${target}.yaml"
      fi
      printf 'in_progress-%s' "$target"
```

- [ ] **Step 10: Add SnapshotLedger tool node (YAML version)**

```dip
  tool SnapshotLedger
    label: "Snapshot Ledger"
    timeout: 5s
    command:
      set -eu
      cp .ai/ledger.yaml .ai/ledger-snapshot.yaml
      printf 'snapshot-saved'
```

- [ ] **Step 11: Commit**

```bash
git add sprint_exec_yaml.dip
git commit -m "feat(sprint-exec-yaml): scaffold with YAML preamble and bootstrap detection nodes"
```

---

### Task 2: sprint_exec_yaml.dip — Implementation, integrity, and validation nodes

**Files:**
- Modify: `sprint_exec_yaml.dip`

This task adds ImplementSprint (with YAML-enhanced prompt), CheckLedgerIntegrity, ResumeCheck, ValidateBuild, CommitSprintWork, CompleteSprint, HumanBootstrapGate, and FailureSummary.

- [ ] **Step 1: Add ImplementSprint agent node (YAML-enhanced prompt)**

```dip
  agent ImplementSprint
    label: "Implement Sprint"
    model: claude-sonnet-4-6
    provider: anthropic
    reasoning_effort: high
    fidelity: summary:high
    prompt:
      Read .ai/current_sprint_id.txt to identify the target sprint.

      Then read BOTH sprint documents:
      1. .ai/sprints/SPRINT-<id>.yaml — structured contract
      2. .ai/sprints/SPRINT-<id>.md — narrative description

      Also read .ai/ledger.yaml for the project tech stack under `project.stack`.

      ## Before writing any code

      1. Check `entry_preconditions.files_must_exist` from the YAML — verify each file exists. If any are missing, something is wrong with prior sprints.
      2. Check `history.attempts` from the YAML — if prior attempts failed, read the failure reasons and avoid repeating the same mistakes.
      3. Check what already exists on disk. If prior implementation work is present from a previous attempt, continue from where it left off — do NOT start over or rewrite existing files that already work.

      ## During implementation

      4. Follow the `dod` checklist items from the YAML as your task list.
      5. Use `validation.commands` from the YAML to self-test as you go.
      6. Respect `scope_fence.off_limits` — do NOT do anything listed there.
      7. If `scope_fence.touch_only` is present, only modify files in that list (plus new files in `artifacts.creates`).

      ## After implementation

      8. Run each command in `validation.commands`. All must pass.
      9. Update the sprint .md checklist with completed items.
      10. Provide a concrete summary of changes and validation evidence.

      HARD CONSTRAINT: Implement ONLY the current sprint. Do NOT implement future sprints. Do NOT modify .ai/ledger.yaml. Do NOT mark sprints as completed — that is handled by a separate pipeline node. If you finish early, stop and report what you did.
```

- [ ] **Step 2: Add CheckLedgerIntegrity tool node (YAML version)**

```dip
  tool CheckLedgerIntegrity
    label: "Check Ledger Integrity"
    timeout: 10s
    command:
      set -eu
      if [ ! -f .ai/ledger-snapshot.yaml ]; then
        printf 'no-snapshot-skipping'
        exit 0
      fi
      target=$(cat .ai/current_sprint_id.txt)
      before=$(yq ".sprints[] | select(.id != \"$target\") | .id + \"=\" + .status" .ai/ledger-snapshot.yaml | sort)
      after=$(yq ".sprints[] | select(.id != \"$target\") | .id + \"=\" + .status" .ai/ledger.yaml | sort)
      if [ "$before" != "$after" ]; then
        printf 'LEDGER_TAMPERED — agent modified non-target sprints:\n'
        printf 'before:\n%s\n' "$before"
        printf 'after:\n%s\n' "$after"
        cp .ai/ledger-snapshot.yaml .ai/ledger.yaml
        printf 'Ledger restored from snapshot.\n'
        rm -f .ai/ledger-snapshot.yaml
        exit 1
      fi
      rm -f .ai/ledger-snapshot.yaml .ai/implement-resume-count.txt
      printf 'ledger-ok'
```

- [ ] **Step 3: Add ResumeCheck tool node (YAML version)**

```dip
  tool ResumeCheck
    label: "Resume Check"
    timeout: 10s
    command:
      set -eu
      if [ -f .ai/ledger-snapshot.yaml ]; then
        target=$(cat .ai/current_sprint_id.txt)
        before=$(yq ".sprints[] | select(.id != \"$target\") | .id + \"=\" + .status" .ai/ledger-snapshot.yaml | sort)
        after=$(yq ".sprints[] | select(.id != \"$target\") | .id + \"=\" + .status" .ai/ledger.yaml | sort)
        if [ "$before" != "$after" ]; then
          cp .ai/ledger-snapshot.yaml .ai/ledger.yaml
          rm -f .ai/ledger-snapshot.yaml .ai/implement-resume-count.txt
          printf 'ledger-tampered'
          exit 1
        fi
      fi
      count=0
      if [ -f .ai/implement-resume-count.txt ]; then
        count=$(cat .ai/implement-resume-count.txt)
      fi
      count=$((count + 1))
      printf '%s' "$count" > .ai/implement-resume-count.txt
      if [ "$count" -ge 3 ]; then
        rm -f .ai/implement-resume-count.txt .ai/ledger-snapshot.yaml
        printf 'max-resumes-reached-%s' "$count"
        exit 1
      fi
      cp .ai/ledger.yaml .ai/ledger-snapshot.yaml
      printf 'resume-%s' "$count"
```

- [ ] **Step 4: Add ValidateBuild tool node (YAML-driven)**

This reads `validation.commands` from the sprint YAML and executes each one. Falls back to the original stack-detection approach if no YAML commands exist.

```dip
  tool ValidateBuild
    label: "Validate Build and Tests"
    timeout: 300s
    command:
      set -eu
      target=$(cat .ai/current_sprint_id.txt)
      sprint_yaml=".ai/sprints/SPRINT-${target}.yaml"
      if [ -f "$sprint_yaml" ] && yq -e '.validation.commands' "$sprint_yaml" >/dev/null 2>&1; then
        count=$(yq '.validation.commands | length' "$sprint_yaml")
        i=0
        while [ "$i" -lt "$count" ]; do
          cmd=$(yq ".validation.commands[$i].cmd" "$sprint_yaml")
          expect=$(yq ".validation.commands[$i].expect" "$sprint_yaml")
          printf '=== Validation %s/%s ===\n' "$((i+1))" "$count"
          printf 'cmd: %s\n' "$cmd"
          if [ "$expect" = "exit_0" ]; then
            eval "$cmd" > /tmp/sprint-validate.log 2>&1 || { cat /tmp/sprint-validate.log; exit 1; }
          else
            eval "$cmd" > /tmp/sprint-validate.log 2>&1 || { cat /tmp/sprint-validate.log; exit 1; }
            if ! grep -q "$expect" /tmp/sprint-validate.log; then
              printf 'Expected output containing: %s\n' "$expect"
              printf 'Got:\n'
              cat /tmp/sprint-validate.log
              exit 1
            fi
          fi
          printf 'PASS\n'
          i=$((i+1))
        done
        printf 'validation-pass-yaml'
        exit 0
      fi
      if [ -f pyproject.toml ]; then
        uv run pytest -v >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        uv run ruff check . >/tmp/sprint-lint.log 2>&1 || { cat /tmp/sprint-lint.log; exit 1; }
        printf 'validation-pass-python'
        exit 0
      fi
      if [ -f package.json ]; then
        npm test >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        printf 'validation-pass-node'
        exit 0
      fi
      if [ -f Package.swift ]; then
        swift build >/tmp/sprint-build.log 2>&1 || { cat /tmp/sprint-build.log; exit 1; }
        swift test >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        printf 'validation-pass-swift'
        exit 0
      fi
      if [ -f Cargo.toml ]; then
        cargo build >/tmp/sprint-build.log 2>&1 || { cat /tmp/sprint-build.log; exit 1; }
        cargo test >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        printf 'validation-pass-rust'
        exit 0
      fi
      if [ -f go.mod ]; then
        go build ./... >/tmp/sprint-build.log 2>&1 || { cat /tmp/sprint-build.log; exit 1; }
        go test ./... >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        printf 'validation-pass-go'
        exit 0
      fi
      printf 'validation-pass-no-known-build-system'
```

- [ ] **Step 5: Add CommitSprintWork agent node**

Copy unchanged from `sprint_exec.dip:229-235`.

```dip
  agent CommitSprintWork
    label: "Commit Sprint Work"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      Prepare and execute a clean commit for sprint implementation changes if there are staged/unstaged changes. If no changes are present, report that no commit was needed. Include commit hash in your summary.
```

- [ ] **Step 6: Add CompleteSprint tool node (yq version)**

```dip
  tool CompleteSprint
    label: "Complete Sprint"
    timeout: 30s
    command:
      set -eu
      target=$(cat .ai/current_sprint_id.txt)
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      yq -i "(.sprints[] | select(.id == \"$target\")).status = \"completed\" | (.sprints[] | select(.id == \"$target\")).updated_at = \"$now\"" .ai/ledger.yaml
      if [ -f ".ai/sprints/SPRINT-${target}.yaml" ]; then
        yq -i ".status = \"completed\"" ".ai/sprints/SPRINT-${target}.yaml"
      fi
      printf 'completed-%s' "$target"
```

- [ ] **Step 7: Add HumanBootstrapGate and FailureSummary**

```dip
  human HumanBootstrapGate
    label: "Bootstrap Failed — Human Intervention"
    mode: choice

  agent FailureSummary
    label: "Failure Summary"
    model: claude-sonnet-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Summarize why sprint execution failed, what remains unresolved, and concrete next steps for recovery.
```

- [ ] **Step 8: Commit**

```bash
git add sprint_exec_yaml.dip
git commit -m "feat(sprint-exec-yaml): add implementation, integrity, and validation nodes"
```

---

### Task 3: sprint_exec_yaml.dip — Review tournament and edge routing

**Files:**
- Modify: `sprint_exec_yaml.dip`

This task adds the multi-model review tournament (copied from original) and the complete edge routing section with bootstrap branching.

- [ ] **Step 1: Add review tournament nodes**

Copy the following nodes unchanged from `sprint_exec.dip:237-315`:

```dip
  parallel ReviewParallel -> ReviewClaude, ReviewCodex, ReviewGemini

  agent ReviewClaude
    label: "Claude Review"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Review sprint execution thoroughly: sprint doc checklist completion, implementation correctness, and validation evidence. Return clear PASS/FAIL reasoning and required fixes.

  agent ReviewCodex
    label: "Codex Review"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      Review sprint execution for implementation quality, regression risk, and checklist completeness. Return clear PASS/FAIL reasoning and required fixes.

  agent ReviewGemini
    label: "Gemini Review"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Review sprint execution for delivery robustness, test coverage, and checklist completeness. Return clear PASS/FAIL reasoning and required fixes.

  fan_in ReviewsJoin <- ReviewClaude, ReviewCodex, ReviewGemini

  parallel CritiquesParallel -> CritiqueClaudeOnCodex, CritiqueClaudeOnGemini, CritiqueCodexOnClaude, CritiqueCodexOnGemini, CritiqueGeminiOnClaude, CritiqueGeminiOnCodex

  agent CritiqueClaudeOnCodex
    label: "Claude Critique of Codex Review"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Critique the Codex review for missing checks, weak evidence, or mistaken conclusions.

  agent CritiqueClaudeOnGemini
    label: "Claude Critique of Gemini Review"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      Critique the Gemini review for missing checks, weak evidence, or mistaken conclusions.

  agent CritiqueCodexOnClaude
    label: "Codex Critique of Claude Review"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      Critique the Claude review for missing checks, weak evidence, or mistaken conclusions.

  agent CritiqueCodexOnGemini
    label: "Codex Critique of Gemini Review"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      Critique the Gemini review for missing checks, weak evidence, or mistaken conclusions.

  agent CritiqueGeminiOnClaude
    label: "Gemini Critique of Claude Review"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Critique the Claude review for missing checks, weak evidence, or mistaken conclusions.

  agent CritiqueGeminiOnCodex
    label: "Gemini Critique of Codex Review"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    prompt:
      Critique the Codex review for missing checks, weak evidence, or mistaken conclusions.

  fan_in CritiquesJoin <- CritiqueClaudeOnCodex, CritiqueClaudeOnGemini, CritiqueCodexOnClaude, CritiqueCodexOnGemini, CritiqueGeminiOnClaude, CritiqueGeminiOnCodex

  agent ReviewAnalysis
    label: "Review Analysis"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    goal_gate: true
    max_retries: 3
    retry_target: ImplementSprint
    prompt:
      Synthesize all reviews and critiques into one verdict.

      After your analysis, you MUST end your response with exactly one of these lines (no other text after it):
        OUTCOME:SUCCESS
        OUTCOME:RETRY
        OUTCOME:FAIL

      Return SUCCESS only if the sprint is truly complete — code committed, tests passing, checklist satisfied.
      Return RETRY if rework is needed (uncommitted fixes, failing tests, missing DoD items).
      Return FAIL if the sprint is blocked and cannot proceed.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete project files. Do NOT implement fixes. Your ONLY job is to analyze and render a verdict.
```

- [ ] **Step 2: Write the complete edges section**

This is the critical routing logic. `CheckBootstrap` branches into bootstrap vs normal paths. Bootstrap sprints skip the review tournament and get a human gate on failure.

```dip
  edges
    Start -> EnsureLedger
    EnsureLedger -> CheckYq
    CheckYq -> FindNextSprint          when ctx.tool_stdout = yq-ok         label: yq_ok
    CheckYq -> YqMissing               when ctx.tool_stdout = yq-not-found  label: yq_missing
    YqMissing -> Exit
    FindNextSprint -> SetCurrentSprint
    SetCurrentSprint -> ReadSprint
    ReadSprint -> CheckBootstrap

    # --- Bootstrap branch ---
    CheckBootstrap -> MarkInProgress

    # --- Shared: MarkInProgress through ImplementSprint ---
    MarkInProgress -> SnapshotLedger
    SnapshotLedger -> ImplementSprint

    # --- ImplementSprint success: ledger integrity check ---
    ImplementSprint -> CheckLedgerIntegrity  when ctx.outcome = success  label: impl_done
    ImplementSprint -> ResumeCheck           when ctx.outcome = fail     label: impl_interrupted
    ImplementSprint -> FailureSummary

    CheckLedgerIntegrity -> ValidateBuild   when ctx.outcome = success  label: ledger_ok
    CheckLedgerIntegrity -> FailureSummary  when ctx.outcome = fail     label: ledger_tampered
    CheckLedgerIntegrity -> FailureSummary

    # --- ResumeCheck: bootstrap gets human gate, normal gets failure ---
    ResumeCheck -> ImplementSprint       when ctx.tool_stdout matches resume     label: resume          restart: true
    ResumeCheck -> HumanBootstrapGate    when ctx.tool_stdout matches max-resumes  label: bootstrap_exhausted
    ResumeCheck -> FailureSummary        when ctx.outcome = fail                 label: resume_failed
    ResumeCheck -> FailureSummary

    # --- HumanBootstrapGate: retry or abort ---
    HumanBootstrapGate -> SnapshotLedger  label: "[S] Retry"  restart: true
    HumanBootstrapGate -> FailureSummary  label: "[A] Abort"

    # --- ValidateBuild ---
    ValidateBuild -> CommitSprintWork  when ctx.outcome = success  label: validated
    ValidateBuild -> ImplementSprint   when ctx.outcome = fail     label: fix_validation  restart: true
    ValidateBuild -> FailureSummary

    # --- CommitSprintWork: bootstrap skips reviews ---
    CommitSprintWork -> CompleteSprint   when ctx.tool_stdout = bootstrap-true   label: bootstrap_done
    CommitSprintWork -> ReviewParallel   label: normal_review

    # --- Review tournament (normal sprints only) ---
    ReviewParallel -> ReviewClaude
    ReviewParallel -> ReviewCodex
    ReviewParallel -> ReviewGemini
    ReviewClaude -> ReviewsJoin
    ReviewCodex -> ReviewsJoin
    ReviewGemini -> ReviewsJoin
    ReviewsJoin -> CritiquesParallel
    CritiquesParallel -> CritiqueClaudeOnCodex
    CritiquesParallel -> CritiqueClaudeOnGemini
    CritiquesParallel -> CritiqueCodexOnClaude
    CritiquesParallel -> CritiqueCodexOnGemini
    CritiquesParallel -> CritiqueGeminiOnClaude
    CritiquesParallel -> CritiqueGeminiOnCodex
    CritiqueClaudeOnCodex -> CritiquesJoin
    CritiqueClaudeOnGemini -> CritiquesJoin
    CritiqueCodexOnClaude -> CritiquesJoin
    CritiqueCodexOnGemini -> CritiquesJoin
    CritiqueGeminiOnClaude -> CritiquesJoin
    CritiqueGeminiOnCodex -> CritiquesJoin
    CritiquesJoin -> ReviewAnalysis
    ReviewAnalysis -> CompleteSprint    when ctx.outcome = success  label: pass
    ReviewAnalysis -> ImplementSprint   when ctx.outcome = retry    label: rework  restart: true
    ReviewAnalysis -> FailureSummary    when ctx.outcome = fail     label: fail
    ReviewAnalysis -> FailureSummary

    # --- Terminal nodes ---
    CompleteSprint -> Exit
    FailureSummary -> Exit
```

**Note on bootstrap skip:** The `CommitSprintWork -> CompleteSprint when ctx.tool_stdout = bootstrap-true` edge requires the bootstrap flag to be available in context at CommitSprintWork. To make this work, add a `StashBootstrapFlag` tool node after `CheckBootstrap` that writes the flag to `.ai/current_bootstrap_flag.txt`, and have `CommitSprintWork` be followed by a `CheckBootstrapSkip` tool node instead:

Replace the `CommitSprintWork` edges with:

```dip
    CommitSprintWork -> CheckBootstrapSkip
```

And add a new tool node:

```dip
  tool CheckBootstrapSkip
    label: "Check Bootstrap Skip"
    timeout: 5s
    command:
      set -eu
      target=$(cat .ai/current_sprint_id.txt)
      sprint_yaml=".ai/sprints/SPRINT-${target}.yaml"
      if [ -f "$sprint_yaml" ]; then
        is_bootstrap=$(yq '.bootstrap // false' "$sprint_yaml")
        if [ "$is_bootstrap" = "true" ]; then
          printf 'bootstrap-skip-reviews'
          exit 0
        fi
      fi
      printf 'normal-reviews'
```

And update the edges:

```dip
    CommitSprintWork -> CheckBootstrapSkip
    CheckBootstrapSkip -> CompleteSprint   when ctx.tool_stdout = bootstrap-skip-reviews  label: bootstrap_done
    CheckBootstrapSkip -> ReviewParallel   when ctx.tool_stdout = normal-reviews          label: normal_review
    CheckBootstrapSkip -> ReviewParallel
```

- [ ] **Step 3: Validate with dippin**

```bash
dippin validate sprint_exec_yaml.dip
```

Expected: `validation passed`

- [ ] **Step 4: Lint with dippin**

```bash
dippin lint sprint_exec_yaml.dip
```

Expected: warnings about conditional-only edges (DIP101/DIP102) are acceptable — the routing is intentionally conditional.

- [ ] **Step 5: Validate with tracker**

```bash
tracker validate sprint_exec_yaml.dip
```

Expected: valid with node/edge counts matching.

- [ ] **Step 6: Commit**

```bash
git add sprint_exec_yaml.dip
git commit -m "feat(sprint-exec-yaml): add review tournament and edge routing with bootstrap branching"
```

---

### Task 4: sprint_runner_yaml.dip

**Files:**
- Create: `sprint_runner_yaml.dip`
- Reference: `sprint_runner.dip` (original to fork from)

- [ ] **Step 1: Create the complete file**

```dip
workflow SprintRunnerYaml
  goal: "Execute all sprints from .ai/ledger.yaml in sequence, looping until every sprint is completed or one fails."
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

  tool check_yq
    label: "Check yq"
    timeout: 5s
    command:
      set -eu
      if ! command -v yq >/dev/null 2>&1; then
        printf 'yq-not-found'
        exit 0
      fi
      printf 'yq-ok'

  agent yq_missing
    label: "yq Not Found"
    prompt:
      The yq YAML processor is required but not installed.

      Install it:
        macOS:  brew install yq
        Linux:  snap install yq  OR  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq

      After installing, re-run the pipeline.

  tool check_ledger
    label: "Check Ledger"
    timeout: 10s
    command:
      set -eu
      if [ ! -f .ai/ledger.yaml ]; then
        printf 'no_ledger'
        exit 0
      fi
      target=$(yq '.sprints[] | select(.status != "completed" and .status != "skipped") | .id' .ai/ledger.yaml | head -1)
      if [ -z "$target" ]; then
        printf 'all_done'
        exit 0
      fi
      printf '%s' "$target" > .ai/current_sprint_id.txt
      printf 'next-%s' "$target"

  agent no_ledger_exit
    label: "No Ledger Found"
    prompt:
      No .ai/ledger.yaml found. The sprint runner requires an existing ledger with planned sprints.

      To create one, run spec_to_sprints_yaml.dip with a spec file.

  subgraph execute_sprint
    ref: sprint_exec_yaml.dip

  tool report_progress
    label: "Report Progress"
    timeout: 10s
    command:
      set -eu
      total=$(yq '.sprints | length' .ai/ledger.yaml)
      done=$(yq '[.sprints[] | select(.status == "completed" or .status == "skipped")] | length' .ai/ledger.yaml)
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
      Sprint execution failed. The subgraph sprint_exec_yaml.dip has already diagnosed the failure in detail.

      Read .ai/current_sprint_id.txt and .ai/ledger.yaml. Report which sprint failed and whether downstream sprints are affected. Keep it brief — the detailed diagnosis already happened inside sprint_exec_yaml.

  edges
    Start -> check_yq
    check_yq -> check_ledger           when ctx.tool_stdout = yq-ok         label: yq_ok
    check_yq -> yq_missing             when ctx.tool_stdout = yq-not-found  label: yq_missing
    yq_missing -> Exit
    check_ledger -> Exit               when ctx.tool_stdout = all_done      label: all_done
    check_ledger -> no_ledger_exit     when ctx.tool_stdout = no_ledger     label: no_ledger
    check_ledger -> execute_sprint     when ctx.tool_stdout != all_done     label: next_sprint
    no_ledger_exit -> Exit
    execute_sprint -> report_progress  when ctx.outcome = success           label: sprint_done
    execute_sprint -> failure_summary  when ctx.outcome = fail              label: sprint_failed
    execute_sprint -> failure_summary
    report_progress -> sprint_gate
    sprint_gate -> skip_gate           label: "[S] Continue"
    sprint_gate -> Exit                label: "[A] Pause"
    skip_gate -> check_ledger          restart: true
    failure_summary -> Exit
```

- [ ] **Step 2: Validate with dippin**

```bash
dippin validate sprint_runner_yaml.dip
```

Expected: `validation passed`

- [ ] **Step 3: Lint with dippin**

```bash
dippin lint sprint_runner_yaml.dip
```

Expected: DIP101 warnings about conditional-only reachability — acceptable.

- [ ] **Step 4: Validate with tracker**

```bash
tracker validate sprint_runner_yaml.dip
```

Expected: valid.

- [ ] **Step 5: Simulate with tracker**

```bash
tracker simulate sprint_runner_yaml.dip
```

Expected: simulation shows the graph structure with `execute_sprint` as a subgraph node.

- [ ] **Step 6: Commit**

```bash
git add sprint_runner_yaml.dip
git commit -m "feat(sprint-runner-yaml): YAML ledger loop controller with yq preflight"
```

---

### Task 5: spec_to_sprints_yaml.dip — Tournament and bootstrap generation

**Files:**
- Create: `spec_to_sprints_yaml.dip`
- Reference: `spec_to_sprints.dip` (original to fork from)

This task creates the file with the tournament decomposition section (mostly copied from original) plus the modified merge_decomposition prompt that generates bootstrap sprints.

- [ ] **Step 1: Create the file with workflow header, Start, Exit, find_spec, no_spec_exit, and analyze_spec**

Copy from `spec_to_sprints.dip:1-108` with these changes:
- Line 1: `workflow SpecToSprintsYaml`
- Line 2: goal updated to mention YAML

```dip
workflow SpecToSprintsYaml
  goal: "Decompose a specification into .ai/ledger.yaml and SPRINT-*.md + SPRINT-*.yaml files ready for sprint_exec_yaml.dip execution, using multi-model tournament decomposition with human approval."
  start: Start
  exit: Exit

  defaults
    max_retries: 3
    max_restarts: 10
    fidelity: summary:medium

  agent Start
    label: Start
    prompt:
      Begin spec-to-sprints decomposition pipeline.

  agent Exit
    label: Exit
    prompt:
      Spec-to-sprints pipeline complete.

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
      first=$(find . -maxdepth 2 -name '*.md' -not -path './.git/*' -not -path './docs/plans/*' -not -path './docs/superpowers/*' -not -path './.ai/*' | sort | head -1)
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

  agent analyze_spec
    label: "Analyze Spec"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    writes: spec_analysis
    goal_gate: true
    retry_target: analyze_spec
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

      ## Critical Rules
      - Only extract requirements explicitly stated in the spec. Do not invent, infer, or add requirements.
      - If the spec is ambiguous, note the ambiguity in Open Questions rather than guessing.
      - Every FR must have a direct spec section reference.

      ## Success Criteria
      - .ai/spec_analysis.md exists with ALL sections filled in
      - Every functional requirement is numbered
      - Every component dependency is mapped
```

- [ ] **Step 2: Add the three decomposition agents and fan_in**

Copy from `spec_to_sprints.dip:110-243` unchanged. These are `decompose_parallel`, `decompose_claude`, `decompose_gpt`, `decompose_gemini`, `decompose_join`.

```dip
  parallel decompose_parallel -> decompose_claude, decompose_gpt, decompose_gemini

  agent decompose_claude
    label: "Claude Decomposition"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    reads: spec_analysis
    writes: decomposition_claude
    fallback_target: decompose_join
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
      - HARD CAP: Do not produce more than 20 sprints. If the project seems to need more, consolidate.
      - DoD items must be concrete and machine-verifiable. Good: "Unit tests for AudioCapture pass". Bad: "Audio capture works correctly"
      - Every sprint's DoD should include at least one test-related item (write tests, run tests, tests pass)
      - Sprint validation should specify exact commands (e.g., "swift test --filter X passes")
      - Do NOT include bootstrap/scaffold sprints — those are generated separately. Start numbering at 001 for the first FEATURE sprint.

      ## Output
      Write your complete decomposition to .ai/drafts/decomposition_claude.md.
      Create the .ai/drafts directory if it does not exist.

  agent decompose_gpt
    label: "GPT Decomposition"
    model: gpt-5.2
    provider: openai
    reasoning_effort: high
    reads: spec_analysis
    writes: decomposition_gpt
    fallback_target: decompose_join
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
      - HARD CAP: Do not produce more than 20 sprints. If the project seems to need more, consolidate.
      - DoD items must be concrete and machine-verifiable. Good: "Unit tests for AudioCapture pass". Bad: "Audio capture works correctly"
      - Every sprint's DoD should include at least one test-related item (write tests, run tests, tests pass)
      - Sprint validation should specify exact commands (e.g., "swift test --filter X passes")
      - Do NOT include bootstrap/scaffold sprints — those are generated separately. Start numbering at 001 for the first FEATURE sprint.

      ## Output
      Write your complete decomposition to .ai/drafts/decomposition_gpt.md.
      Create the .ai/drafts directory if it does not exist.

  agent decompose_gemini
    label: "Gemini Decomposition"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    reads: spec_analysis
    writes: decomposition_gemini
    fallback_target: decompose_join
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
      - HARD CAP: Do not produce more than 20 sprints. If the project seems to need more, consolidate.
      - DoD items must be concrete and machine-verifiable. Good: "Unit tests for AudioCapture pass". Bad: "Audio capture works correctly"
      - Every sprint's DoD should include at least one test-related item (write tests, run tests, tests pass)
      - Sprint validation should specify exact commands (e.g., "swift test --filter X passes")
      - Do NOT include bootstrap/scaffold sprints — those are generated separately. Start numbering at 001 for the first FEATURE sprint.

      ## Output
      Write your complete decomposition to .ai/drafts/decomposition_gemini.md.
      Create the .ai/drafts directory if it does not exist.

  fan_in decompose_join <- decompose_claude, decompose_gpt, decompose_gemini
```

- [ ] **Step 3: Add the six critique agents and fan_in**

Copy from `spec_to_sprints.dip:246-416` unchanged. These are the six cross-critique agents and `critique_join`.

```dip
  parallel critique_parallel -> critique_claude_on_gpt, critique_claude_on_gemini, critique_gpt_on_claude, critique_gpt_on_gemini, critique_gemini_on_claude, critique_gemini_on_gpt

  agent critique_claude_on_gpt
    label: "Claude Critique of GPT"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    reads: decomposition_gpt, spec_analysis
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

  agent critique_claude_on_gemini
    label: "Claude Critique of Gemini"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    reads: decomposition_gemini, spec_analysis
    prompt:
      You are working in `run.working_dir`.

      Read .ai/drafts/decomposition_gemini.md (the Gemini decomposition) and .ai/spec_analysis.md (the spec analysis with FR IDs).

      Review the Gemini decomposition for:
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

  agent critique_gpt_on_claude
    label: "GPT Critique of Claude"
    model: gpt-5.2
    provider: openai
    reasoning_effort: high
    reads: decomposition_claude, spec_analysis
    prompt:
      You are working in `run.working_dir`.

      Read .ai/drafts/decomposition_claude.md (the Claude decomposition) and .ai/spec_analysis.md (the spec analysis with FR IDs).

      Review the Claude decomposition for:
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

  agent critique_gpt_on_gemini
    label: "GPT Critique of Gemini"
    model: gpt-5.2
    provider: openai
    reasoning_effort: high
    reads: decomposition_gemini, spec_analysis
    prompt:
      You are working in `run.working_dir`.

      Read .ai/drafts/decomposition_gemini.md (the Gemini decomposition) and .ai/spec_analysis.md (the spec analysis with FR IDs).

      Review the Gemini decomposition for:
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

  agent critique_gemini_on_claude
    label: "Gemini Critique of Claude"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    reads: decomposition_claude, spec_analysis
    prompt:
      You are working in `run.working_dir`.

      Read .ai/drafts/decomposition_claude.md (the Claude decomposition) and .ai/spec_analysis.md (the spec analysis with FR IDs).

      Review the Claude decomposition for:
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

  agent critique_gemini_on_gpt
    label: "Gemini Critique of GPT"
    model: gemini-3-flash-preview
    provider: gemini
    reasoning_effort: high
    reads: decomposition_gpt, spec_analysis
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

  fan_in critique_join <- critique_claude_on_gpt, critique_claude_on_gemini, critique_gpt_on_claude, critique_gpt_on_gemini, critique_gemini_on_claude, critique_gemini_on_gpt
```

- [ ] **Step 4: Add merge_decomposition with bootstrap sprint generation**

This is the key change from the original. The prompt now instructs the agent to prepend bootstrap sprints.

```dip
  agent merge_decomposition
    label: "Merge Decomposition"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    reads: decomposition_claude, decomposition_gpt, decomposition_gemini, spec_analysis
    writes: sprint_plan
    goal_gate: true
    retry_target: merge_decomposition
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Synthesize the three decompositions and six cross-critiques into one final sprint plan, with bootstrap sprints prepended.

      ## Process
      Read the three decomposition files:
      - .ai/drafts/decomposition_claude.md
      - .ai/drafts/decomposition_gpt.md
      - .ai/drafts/decomposition_gemini.md
      And the spec analysis: .ai/spec_analysis.md

      1. Compare the three decompositions side by side
      2. Incorporate valid critique findings — fix ordering errors, fill coverage gaps, adjust sprint sizes
      3. Produce a single merged sprint list

      ## Bootstrap Sprint Generation

      BEFORE the feature sprints, you MUST prepend bootstrap sprints:

      ### Sprint 000 — Project Scaffold & Toolchain (ALWAYS)
      - bootstrap: true, complexity: low
      - Scope: Initialize repo, package manager, test harness, linter config, CI skeleton
      - Derive specifics from the Tech Stack section of .ai/spec_analysis.md
      - DoD: project builds, linter passes, test harness runs (even with zero tests), CI config exists

      ### Sprint 001 — External Services & Dev Environment (IF services detected)
      - bootstrap: true, complexity: low
      - Only include this sprint if the spec analysis mentions databases, message brokers, caches, or other external services
      - Scope: docker-compose, database migrations, service health checks, env var documentation
      - DoD: services start, health checks pass, connection from app code works

      ### Sprint 002 — Hello World End-to-End Proof (ALWAYS)
      - bootstrap: true, complexity: low
      - Scope: One endpoint/function, one test, full stack round-trip proving the scaffold works
      - DoD: one passing integration test that exercises the full stack
      - depends_on: ["000"] or ["001"] if Sprint 001 exists

      Then renumber feature sprints starting at 003 (or 002 if Sprint 001 was skipped). All feature sprints must depends_on at minimum the last bootstrap sprint.

      ## Output Format (.ai/sprint_plan.md)
      Start with a summary: total sprint count, overall approach, key decisions made during merge.

      Then for each sprint:
      ### Sprint NNN — Title

      **Scope:** What this sprint delivers (2-3 sentences)

      **Non-goals:** What is explicitly excluded

      **Requirements:** FR IDs covered (e.g., FR1, FR3, FR7)

      **Dependencies:** Sprint numbers that must complete first

      **Bootstrap:** true/false

      **Expected Artifacts:**
      - file/module paths this sprint produces

      **DoD:**
      - [ ] Checkable item 1
      - [ ] Checkable item 2
      ...

      **Validation:**
      - Exact build/test commands to verify completion

      **Complexity:** low / medium / high

      ## Rules
      - Every FR from .ai/spec_analysis.md must appear in at least one sprint
      - No dependency cycles
      - Sprint IDs are sequential zero-padded 3-digit (000, 001, ...)
      - Bootstrap sprints come first, feature sprints follow
      - Create .ai directory if it does not exist
```

- [ ] **Step 5: Commit**

```bash
git add spec_to_sprints_yaml.dip
git commit -m "feat(spec-to-sprints-yaml): tournament decomposition with bootstrap sprint generation"
```

---

### Task 6: spec_to_sprints_yaml.dip — Output stage and edges

**Files:**
- Modify: `spec_to_sprints_yaml.dip`

This task adds the approval gate, output nodes (write_sprint_docs with dual YAML+md, YAML ledger writer, YAML validator), and the complete edges section.

- [ ] **Step 1: Add present_plan, approval_gate, apply_feedback, skip_approval**

Copy from `spec_to_sprints.dip:479-524` with minor text updates.

```dip
  agent present_plan
    label: "Present Sprint Plan"
    model: claude-sonnet-4-6
    provider: anthropic
    reads: sprint_plan
    reasoning_effort: medium
    prompt:
      You are working in `run.working_dir`.

      Read .ai/sprint_plan.md and present a concise review summary for human approval:

      1. Total sprint count (noting how many are bootstrap vs feature)
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
    reads: sprint_plan
    writes: sprint_plan
    prompt:
      You are working in `run.working_dir`.

      The human has provided feedback on the sprint plan. Read .ai/sprint_plan.md, incorporate the feedback, and rewrite .ai/sprint_plan.md with the changes applied.

      Preserve the same format. Update sprint numbers if sprints are added, removed, or reordered. Ensure dependency references remain consistent after renumbering. Bootstrap sprints (000-002) should generally not be removed unless explicitly requested.

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

- [ ] **Step 2: Add setup_workspace with yq check**

```dip
  tool setup_workspace
    label: "Setup .ai Workspace"
    timeout: 10s
    command:
      set -eu
      if ! command -v yq >/dev/null 2>&1; then
        printf 'yq-not-found'
        exit 1
      fi
      mkdir -p .ai/sprints .ai/drafts
      printf 'ready'
```

- [ ] **Step 3: Add write_sprint_docs with dual YAML+md output**

```dip
  agent write_sprint_docs
    label: "Write Sprint Docs"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    reads: sprint_plan, spec_analysis
    fallback_target: Exit
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read .ai/sprint_plan.md and .ai/spec_analysis.md. For each sprint in the plan, write TWO files under .ai/sprints/:

      ### 1. SPRINT-<id>.md (narrative — same format as before)
      ```
      # Sprint NNN — Title

      ## Scope
      What this sprint delivers (2-3 sentences).

      ## Non-goals
      - What is explicitly excluded

      ## Requirements
      - FR IDs covered, with one-line descriptions

      ## Dependencies
      - Sprint numbers that must complete first (or "None")

      ## Expected Artifacts
      - Specific file paths

      ## DoD
      - [ ] Checkable item 1
      - [ ] Checkable item 2

      ## Validation
      - Exact commands
      ```

      ### 2. SPRINT-<id>.yaml (structured contract)
      ```yaml
      id: "NNN"
      title: "Sprint Title"
      status: planned
      bootstrap: true/false
      complexity: low/medium/high

      depends_on: ["000", "001"]
      dependents: ["004", "005"]

      stack:
        services: []

      scope_fence:
        off_limits:
          - "do not modify .ai/ledger.yaml"
          - "do not implement sprint NNN+1 or later"
          - "do not add features beyond scope"
        touch_only: []

      entry_preconditions:
        files_must_exist: []
        sprints_must_be_complete: ["000"]

      artifacts:
        creates:
          - path: "path/to/file"
            type: module
        modifies: []

      validation:
        commands:
          - cmd: "exact command here"
            expect: exit_0

      dod:
        - "First checkable item"
        - "Second checkable item"

      history:
        attempts: []
      ```

      ## Rules
      - CRITICAL: All files MUST be written to .ai/sprints/ — NEVER to the project root
      - File paths: .ai/sprints/SPRINT-000.md, .ai/sprints/SPRINT-000.yaml, etc.
      - IDs MUST be zero-padded 3-digit: 000, 001, ... 016
      - The YAML must have ALL fields shown above — no missing sections
      - `scope_fence.off_limits` must always include "do not modify .ai/ledger.yaml"
      - `entry_preconditions.sprints_must_be_complete` must match `depends_on`
      - `dependents` is the reverse index of `depends_on` — compute it from the full sprint list
      - `validation.commands` must have exact, runnable commands — not pseudocode
      - `stack.services` should list any external services this sprint introduces (database, message broker, etc.)
      - Bootstrap sprints (000-002) must have `bootstrap: true`
      - Write ALL sprint docs in one pass for cross-sprint consistency
      - Do NOT write or modify .ai/ledger.yaml — a separate tool handles that
```

- [ ] **Step 4: Add write_ledger (YAML version)**

```dip
  tool write_ledger
    label: "Write Ledger"
    timeout: 30s
    command:
      set -eu
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      stack_lang=$(yq '.stack.lang // "null"' .ai/sprints/SPRINT-000.yaml 2>/dev/null || echo "null")
      stack_runner=$(yq '.stack.runner // "null"' .ai/sprints/SPRINT-000.yaml 2>/dev/null || echo "null")
      stack_test=$(yq '.stack.test // "null"' .ai/sprints/SPRINT-000.yaml 2>/dev/null || echo "null")
      stack_lint=$(yq '.stack.lint // "null"' .ai/sprints/SPRINT-000.yaml 2>/dev/null || echo "null")
      stack_build=$(yq '.stack.build // "null"' .ai/sprints/SPRINT-000.yaml 2>/dev/null || echo "null")
      cat > .ai/ledger.yaml <<HEADER
project:
  name: "Unknown"
  stack:
    lang: $stack_lang
    runner: $stack_runner
    test: $stack_test
    lint: $stack_lint
    build: $stack_build
  created_at: "$now"

sprints:
HEADER
      for f in .ai/sprints/SPRINT-*.yaml; do
        [ -f "$f" ] || continue
        id=$(yq '.id' "$f")
        title=$(yq '.title' "$f")
        bootstrap=$(yq '.bootstrap // false' "$f")
        complexity=$(yq '.complexity // "medium"' "$f")
        deps=$(yq '.depends_on // []' "$f")
        cat >> .ai/ledger.yaml <<SPRINT
  - id: "$id"
    title: "$title"
    status: planned
    bootstrap: $bootstrap
    depends_on: $deps
    complexity: $complexity
    created_at: "$now"
    updated_at: "$now"
    attempts: 0
    total_cost: "0.00"
SPRINT
      done
      count=$(yq '.sprints | length' .ai/ledger.yaml)
      printf 'wrote-%s-sprints' "$count"
```

- [ ] **Step 5: Add validate_output (YAML version)**

```dip
  tool validate_output
    label: "Validate Output"
    timeout: 30s
    command:
      set -eu
      errors=""
      stray=$(ls SPRINT-*.md SPRINT-*.yaml 2>/dev/null | wc -l | tr -d ' ')
      if [ "$stray" -gt 0 ]; then
        errors="${errors}sprint-files-in-root "
      fi
      ledger_ids=$(yq '.sprints[].id' .ai/ledger.yaml | sort)
      yaml_ids=$(ls .ai/sprints/SPRINT-*.yaml 2>/dev/null | sed 's|.*/SPRINT-||;s|\.yaml||' | sort)
      md_ids=$(ls .ai/sprints/SPRINT-*.md 2>/dev/null | sed 's|.*/SPRINT-||;s|\.md||' | sort)
      if [ "$ledger_ids" != "$yaml_ids" ]; then
        errors="${errors}ledger-yaml-mismatch "
      fi
      if [ "$ledger_ids" != "$md_ids" ]; then
        errors="${errors}ledger-md-mismatch "
      fi
      for f in .ai/sprints/SPRINT-*.yaml; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        if ! yq -e '.id' "$f" >/dev/null 2>&1; then
          errors="${errors}missing-id-${base} "
        fi
        if ! yq -e '.validation.commands' "$f" >/dev/null 2>&1; then
          errors="${errors}missing-validation-${base} "
        fi
        if ! yq -e '.dod' "$f" >/dev/null 2>&1; then
          errors="${errors}missing-dod-${base} "
        fi
        if ! yq -e '.scope_fence' "$f" >/dev/null 2>&1; then
          errors="${errors}missing-scope-fence-${base} "
        fi
        if ! yq -e '.artifacts' "$f" >/dev/null 2>&1; then
          errors="${errors}missing-artifacts-${base} "
        fi
      done
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
      if [ -z "$(yq '.sprints[]' .ai/ledger.yaml 2>/dev/null)" ]; then
        errors="${errors}empty-ledger "
      fi
      bootstrap_count=$(yq '[.sprints[] | select(.bootstrap == true)] | length' .ai/ledger.yaml)
      if [ "$bootstrap_count" -lt 2 ]; then
        errors="${errors}insufficient-bootstrap-sprints "
      fi
      if [ -n "$errors" ]; then
        printf 'invalid-%s' "$errors"
        exit 0
      fi
      printf 'valid'
```

- [ ] **Step 6: Add commit_output**

```dip
  tool commit_output
    label: "Commit Output"
    timeout: 30s
    command:
      set -eu
      if [ ! -d .git ]; then
        printf 'no-git-skipped'
        exit 0
      fi
      for f in .ai/ledger.yaml .ai/sprints .ai/spec_analysis.md .ai/sprint_plan.md; do
        [ -e "$f" ] && git add "$f"
      done
      if git diff --cached --quiet; then
        printf 'no-changes-skipped'
        exit 0
      fi
      count=$(yq '.sprints | length' .ai/ledger.yaml)
      git commit -m "feat(sprints): decompose spec into ${count} sprints (YAML format)"
      printf 'committed-%s-sprints' "$count"
```

- [ ] **Step 7: Write the complete edges section**

```dip
  edges
    Start -> find_spec
    find_spec -> analyze_spec  when ctx.tool_stdout != no_spec_found  label: spec_found
    find_spec -> no_spec_exit  when ctx.tool_stdout = no_spec_found   label: no_spec
    no_spec_exit -> Exit
    analyze_spec -> decompose_parallel
    decompose_parallel -> decompose_claude
    decompose_parallel -> decompose_gpt
    decompose_parallel -> decompose_gemini
    decompose_claude -> decompose_join
    decompose_gpt -> decompose_join
    decompose_gemini -> decompose_join
    decompose_join -> critique_parallel
    critique_parallel -> critique_claude_on_gpt
    critique_parallel -> critique_claude_on_gemini
    critique_parallel -> critique_gpt_on_claude
    critique_parallel -> critique_gpt_on_gemini
    critique_parallel -> critique_gemini_on_claude
    critique_parallel -> critique_gemini_on_gpt
    critique_claude_on_gpt -> critique_join
    critique_claude_on_gemini -> critique_join
    critique_gpt_on_claude -> critique_join
    critique_gpt_on_gemini -> critique_join
    critique_gemini_on_claude -> critique_join
    critique_gemini_on_gpt -> critique_join
    critique_join -> merge_decomposition
    merge_decomposition -> present_plan
    present_plan -> approval_gate
    approval_gate -> apply_feedback  label: "[A] Revise plan"
    approval_gate -> skip_approval   label: "[S] Approve / Skip"
    apply_feedback -> approval_gate  restart: true
    skip_approval -> setup_workspace
    setup_workspace -> write_sprint_docs
    write_sprint_docs -> write_ledger
    write_ledger -> validate_output
    validate_output -> commit_output       when ctx.tool_stdout = valid     label: valid
    validate_output -> write_sprint_docs   when ctx.tool_stdout != valid    label: fix_validation  restart: true
    commit_output -> Exit
```

- [ ] **Step 8: Validate with dippin**

```bash
dippin validate spec_to_sprints_yaml.dip
```

Expected: `validation passed`

- [ ] **Step 9: Validate with tracker**

```bash
tracker validate spec_to_sprints_yaml.dip
```

Expected: valid with node/edge counts.

- [ ] **Step 10: Commit**

```bash
git add spec_to_sprints_yaml.dip
git commit -m "feat(spec-to-sprints-yaml): output stage with dual YAML+md and YAML ledger"
```

---

### Task 7: Integration validation

**Files:**
- Read-only: `sprint_exec_yaml.dip`, `sprint_runner_yaml.dip`, `spec_to_sprints_yaml.dip`

- [ ] **Step 1: Run tracker simulate on sprint_exec_yaml.dip**

```bash
tracker simulate sprint_exec_yaml.dip
```

Expected: Simulation shows the full graph with CheckBootstrap branching, bootstrap and normal paths visible.

- [ ] **Step 2: Run tracker simulate on sprint_runner_yaml.dip**

```bash
tracker simulate sprint_runner_yaml.dip
```

Expected: Simulation shows the loop structure with `execute_sprint` as a subgraph node referencing `sprint_exec_yaml.dip`.

- [ ] **Step 3: Run tracker simulate on spec_to_sprints_yaml.dip**

```bash
tracker simulate spec_to_sprints_yaml.dip
```

Expected: Simulation shows the tournament (parallel decomposition, cross-critiques, merge) through to output stage.

- [ ] **Step 4: Run a live composition test**

Test that sprint_runner_yaml.dip correctly composes sprint_exec_yaml.dip via subgraph:

```bash
tracker validate sprint_runner_yaml.dip
```

Expected: valid, with the subgraph reference resolved.

- [ ] **Step 5: Run tracker on sprint_runner_yaml.dip with --auto-approve against a test project**

Create a minimal test project with a pre-built `.ai/ledger.yaml` and one bootstrap sprint to verify the full pipeline works end-to-end:

```bash
mkdir -p /tmp/yaml-pipeline-test/.ai/sprints
cat > /tmp/yaml-pipeline-test/.ai/ledger.yaml <<'EOF'
project:
  name: "Test Project"
  stack:
    lang: null
    runner: null
    test: null
    lint: null
    build: null
  created_at: "2026-04-16T00:00:00Z"

sprints:
  - id: "000"
    title: "Test bootstrap"
    status: planned
    bootstrap: true
    depends_on: []
    complexity: low
    created_at: "2026-04-16T00:00:00Z"
    updated_at: "2026-04-16T00:00:00Z"
    attempts: 0
    total_cost: "0.00"
EOF

cat > /tmp/yaml-pipeline-test/.ai/sprints/SPRINT-000.yaml <<'EOF'
id: "000"
title: "Test bootstrap"
status: planned
bootstrap: true
complexity: low

depends_on: []
dependents: []

stack:
  services: []

scope_fence:
  off_limits:
    - "do not modify .ai/ledger.yaml"
  touch_only: []

entry_preconditions:
  files_must_exist: []
  sprints_must_be_complete: []

artifacts:
  creates:
    - path: "hello.txt"
      type: config
  modifies: []

validation:
  commands:
    - cmd: "test -f hello.txt"
      expect: exit_0

dod:
  - "hello.txt exists"

history:
  attempts: []
EOF

cat > /tmp/yaml-pipeline-test/.ai/sprints/SPRINT-000.md <<'EOF'
# Sprint 000 — Test Bootstrap

## Scope
Create a hello.txt file to prove the pipeline works.

## Non-goals
- Nothing else

## Requirements
- None

## Dependencies
- None

## Expected Artifacts
- `hello.txt`

## DoD
- [ ] hello.txt exists

## Validation
- `test -f hello.txt`
EOF

cd /tmp/yaml-pipeline-test && git init && git add -A && git commit -m "init test project"
```

Then run:

```bash
cd /tmp/yaml-pipeline-test && tracker --no-tui --auto-approve /path/to/dot-files/sprint_exec_yaml.dip
```

Expected: Pipeline executes the bootstrap sprint, creates hello.txt, validates, commits, skips review tournament (bootstrap), marks complete.

- [ ] **Step 6: Fix any issues found during integration testing**

If any validation, simulation, or live test fails, fix the dip file and re-validate.

- [ ] **Step 7: Final commit**

```bash
git add sprint_exec_yaml.dip sprint_runner_yaml.dip spec_to_sprints_yaml.dip
git commit -m "fix(yaml-pipeline): integration test fixes"
```

(Skip this commit if no fixes were needed.)
