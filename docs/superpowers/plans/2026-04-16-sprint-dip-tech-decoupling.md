# Sprint Dip Tech Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove language-specific prompt guidance from sprint dip agent nodes and standardize ValidateBuild across all three sprint dips.

**Architecture:** Two changes per file — strip tech hand-holding from agent prompts, replace ValidateBuild with the canonical auto-detect version. Agent prompts get one generic line instead. Tool nodes keep deterministic validation (agents lie about tests) but with all five languages in every copy.

**Tech Stack:** Dip pipeline definitions (no code — just .dip file edits)

**Spec:** `docs/superpowers/specs/2026-04-16-sprint-dip-tech-decoupling-design.md`

---

## Important: Edge Routing Conventions

The three dips use two different routing conventions for ValidateBuild results:

- **sprint_exec.dip** and **sprint_exec-cheap.dip**: Route on `ctx.outcome = success/fail` (derived from exit code)
- **sprint_runner.dip**: Routes on `ctx.tool_stdout startswith "validation-pass"` / `= validation-fail`

The canonical ValidateBuild must respect each file's convention. The language detection blocks are identical; only the error-handling wrapper differs.

---

### Task 1: sprint_exec.dip — Strip prompts, update ValidateBuild

**Files:**
- Modify: `sprint_exec.dip:105-163`

- [ ] **Step 1: Strip Environment Rules and Test Infrastructure from ImplementSprint**

Replace lines 112-123 of `sprint_exec.dip`. The current prompt has two sections ("Environment Rules" and "Test Infrastructure") after the main instruction. Replace the entire prompt with:

```
    prompt:
      Implement the sprint requirements end-to-end. Read the PreFlight output for environment context — follow standard practices for the detected stack. If prior review/critique context exists, treat those findings as required fixes. Update the sprint doc checklist as work is completed, and provide a concrete summary of changes and validation evidence.
```

This collapses 12 lines of language-specific guidance into one generic sentence.

- [ ] **Step 2: Replace ValidateBuild with canonical version**

Replace lines 125-162 of `sprint_exec.dip` with the canonical version. This file routes on `ctx.outcome` (exit code), so use `set -eu` with `exit 1` on failure:

```
  tool ValidateBuild
    label: "Validate Build and Tests"
    timeout: 300s
    command:
      set -eu
      if [ -f Package.swift ]; then
        swift build >/tmp/sprint-build.log 2>&1 || { cat /tmp/sprint-build.log; exit 1; }
        swift test >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        printf 'validation-pass-swift'
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

Key changes from current version:
- Swift block: removed `|| true` hack and `rg` grepping, uses consistent `|| { cat; exit 1; }` pattern
- Python block: added `ruff check` (linting was missing)
- Rust and Go blocks: already present, kept as-is
- All blocks use consistent error handling

- [ ] **Step 3: Verify edges are unchanged**

Confirm these edges in the `edges` section still work with the new output:
```
ValidateBuild -> CommitSprintWork  when ctx.outcome = success  label: validated
ValidateBuild -> ImplementSprint  when ctx.outcome = fail  label: fix_validation  restart: true
ValidateBuild -> FailureSummary
```
No edge changes needed — exit 0 maps to `success`, exit 1 maps to `fail`.

- [ ] **Step 4: Commit**

```bash
git add sprint_exec.dip
git commit -m "refactor(sprint-exec): strip tech-specific prompt guidance, standardize ValidateBuild"
```

---

### Task 2: sprint_exec-cheap.dip — Strip prompts, update ValidateBuild and ValidateRescue

**Files:**
- Modify: `sprint_exec-cheap.dip:109-154,258-297`

- [ ] **Step 1: Strip Environment Rules and Test Infrastructure from ImplementCheap**

Replace lines 115-127 of `sprint_exec-cheap.dip`. Replace the entire prompt with:

```
    prompt:
      Implement the sprint requirements end-to-end using minimal, focused changes. Read the PreFlight output for environment context — follow standard practices for the detected stack. If prior review/critique/squad context exists, treat those findings as required fixes. Update the sprint doc checklist as work is completed, and provide a concrete summary of changes and validation evidence.
```

- [ ] **Step 2: Replace ValidateBuild with canonical version**

Replace lines 129-154 of `sprint_exec-cheap.dip`. Use the same canonical version from Task 1, Step 2 (same `set -eu` / `exit 1` convention — this file also routes on `ctx.outcome`).

This is the copy that was missing Rust and Go — the canonical version adds them.

- [ ] **Step 3: Strip Environment Rules from ImplementRescue**

Replace lines 264-270 of `sprint_exec-cheap.dip`. Replace the entire prompt with:

```
    prompt:
      ESCALATION: Cheap implementation failed after multiple attempts. You have all prior context — squad findings, review critiques, gate verdicts, and implementation history. Read the PreFlight output for environment context — follow standard practices for the detected stack. Fix the remaining issues definitively. This is the last attempt before failure.
```

- [ ] **Step 4: Replace ValidateRescue with canonical version**

Replace lines 272-297 of `sprint_exec-cheap.dip`. Same canonical script as ValidateBuild but with the node name `ValidateRescue`:

```
  tool ValidateRescue
    label: "Validate Rescue Build"
    timeout: 300s
    command:
      set -eu
      if [ -f Package.swift ]; then
        swift build >/tmp/sprint-build.log 2>&1 || { cat /tmp/sprint-build.log; exit 1; }
        swift test >/tmp/sprint-test.log 2>&1 || { cat /tmp/sprint-test.log; exit 1; }
        printf 'validation-pass-swift'
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

This was also missing Rust and Go.

- [ ] **Step 5: Verify edges are unchanged**

Confirm these edges still work:
```
ValidateBuild -> CommitCheap  when ctx.outcome = success  label: validated
ValidateBuild -> ImplementCheap  when ctx.outcome = fail  label: fix_validation  restart: true
ValidateRescue -> CommitRescue  when ctx.outcome = success  label: rescue_validated
ValidateRescue -> FailureSummary  when ctx.outcome = fail  label: rescue_failed
```
No edge changes needed.

- [ ] **Step 6: Commit**

```bash
git add sprint_exec-cheap.dip
git commit -m "refactor(sprint-exec-cheap): strip tech-specific prompt guidance, standardize ValidateBuild and ValidateRescue"
```

---

### Task 3: sprint_runner.dip — Strip prompt, update validate_build

**Files:**
- Modify: `sprint_runner.dip:109-188`

- [ ] **Step 1: Strip Environment Rules and Test Infrastructure from implement_sprint**

Replace lines 118-151 of `sprint_runner.dip`. This agent has a richer prompt structure (Task, Process, Environment Rules, Test Infrastructure, If Prior Review, Success Criteria). Keep everything except Environment Rules and Test Infrastructure, and add the generic line. Replace the entire prompt with:

```
    prompt:
      You are working in `run.working_dir`.

      ## Task
      Read .ai/current_sprint_id.txt to get the sprint ID. Read the sprint doc at .ai/sprints/SPRINT-<id>.md. Implement all requirements end-to-end.

      ## Process
      1. Read the sprint doc thoroughly — understand scope, requirements, expected artifacts, DoD
      2. Read .ai/spec_analysis.md for broader context
      3. Review existing code to understand current state
      4. Write failing tests FIRST for each DoD item
      5. Implement minimum code to pass tests
      6. Run the project's test suite and linter — fix all issues
      7. Update the sprint doc checklist as work is completed

      Read the PreFlight output for environment context — follow standard practices for the detected stack.

      ## If Prior Review Feedback Exists
      If you have context from a prior review/critique cycle, treat those findings as required fixes. Address every finding before declaring done.

      ## Success Criteria
      - All DoD items checked off in the sprint doc
      - All tests pass
      - Linter passes
      - Expected artifacts exist
```

- [ ] **Step 2: Replace validate_build with canonical version (sprint_runner routing convention)**

Replace lines 153-188 of `sprint_runner.dip`. This file routes on `ctx.tool_stdout` not `ctx.outcome`, so use the `set +e` / fail-flag / explicit-printf convention:

```
  tool validate_build
    label: "Validate Build and Tests"
    timeout: 300s
    command:
      set +e
      fail=0
      if [ -f Package.swift ]; then
        swift build 2>&1 || fail=1
        swift test 2>&1 || fail=1
        if [ "$fail" -eq 0 ]; then printf 'validation-pass'; else printf 'validation-fail'; fi
        exit 0
      fi
      if [ -f pyproject.toml ]; then
        uv run pytest -v 2>&1 || fail=1
        uv run ruff check . 2>&1 || fail=1
        if [ "$fail" -eq 0 ]; then printf 'validation-pass'; else printf 'validation-fail'; fi
        exit 0
      fi
      if [ -f package.json ]; then
        npm test 2>&1 || fail=1
        if [ "$fail" -eq 0 ]; then printf 'validation-pass'; else printf 'validation-fail'; fi
        exit 0
      fi
      if [ -f Cargo.toml ]; then
        cargo build 2>&1 || fail=1
        cargo test 2>&1 || fail=1
        if [ "$fail" -eq 0 ]; then printf 'validation-pass'; else printf 'validation-fail'; fi
        exit 0
      fi
      if [ -f go.mod ]; then
        go build ./... 2>&1 || fail=1
        go test ./... 2>&1 || fail=1
        if [ "$fail" -eq 0 ]; then printf 'validation-pass'; else printf 'validation-fail'; fi
        exit 0
      fi
      printf 'validation-pass-no-known-build-system'
```

This already had all five languages — the change is just making the structure consistent. Added `ruff check` to the Python block (was missing linting).

- [ ] **Step 3: Verify edges are unchanged**

Confirm these edges still work:
```
validate_build -> commit_work  when ctx.tool_stdout startswith "validation-pass"  label: validated
validate_build -> implement_sprint  when ctx.tool_stdout = validation-fail  label: fix_validation  restart: true
validate_build -> failure_summary
```
No edge changes needed.

- [ ] **Step 4: Commit**

```bash
git add sprint_runner.dip
git commit -m "refactor(sprint-runner): strip tech-specific prompt guidance, standardize validate_build"
```

---

### Task 4: Final verification

- [ ] **Step 1: Diff all three files to confirm no unintended changes**

```bash
git diff HEAD~3 -- sprint_exec.dip sprint_exec-cheap.dip sprint_runner.dip
```

Verify:
- No edge definitions were changed
- No agent model/provider/reasoning_effort settings were changed
- Only prompt text and tool command blocks changed
- All five languages (Swift, Python, Node, Rust, Go) present in every ValidateBuild

- [ ] **Step 2: Run dippin-audit if available**

Use the `dippin-audit` skill on each file to verify structural validity:
- `sprint_exec.dip`
- `sprint_exec-cheap.dip`
- `sprint_runner.dip`

If dippin-audit is not available, manually verify: every node referenced in `edges` exists, every edge target exists, parallel/fan_in memberships match.

- [ ] **Step 3: Post summary to mammoth BBS**

Post a message to the mammoth topic summarizing the changes, referencing the NIFB Sprint 001 post-mortem that motivated them. Thread subject: "Resolved: Sprint dips decoupled from language-specific guidance"
