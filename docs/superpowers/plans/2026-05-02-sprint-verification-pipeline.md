# Sprint Verification Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two .dip pipelines — `verify_sprint.dip` (single-sprint verifier) and `verify_sprints_runner.dip` (batch runner) — that verify completed sprints still satisfy their contracts and generate remediation sprints when they don't.

**Architecture:** Sequential verification pipeline: mechanical tool-node checks (artifacts, validation, build, regressions) feed results into a single Opus semantic reviewer that checks DoD and spec-to-code alignment. Failures generate narrowly-scoped remediation sprints in the ledger for the existing sprint runner to execute.

**Tech Stack:** .dip pipeline DSL, yq, shell, git

**Spec:** `docs/superpowers/specs/2026-05-02-sprint-verification-pipeline-design.md`

**Reference pipelines:** `sprint/sprint_exec_yaml_v2.dip` (node patterns), `sprint/sprint_runner_yaml_v2.dip` (runner loop pattern)

---

### File Structure

| File | Purpose |
|------|---------|
| `sprint/verify_sprint.dip` | Single-sprint verification subgraph |
| `sprint/verify_sprints_runner.dip` | Batch runner that iterates completed sprints |

---

### Task 1: Create verify_sprint.dip — Scaffold and Tool Nodes

**Files:**
- Create: `sprint/verify_sprint.dip`

- [ ] **Step 1: Create the workflow header, Start, and Exit nodes**

```
# ABOUTME: Single-sprint verification pipeline — checks a completed sprint still satisfies its contract.
# ABOUTME: Runs mechanical checks (artifacts, validation, build, regressions) then Opus semantic review, generates remediation sprints on failure.
workflow VerifySprint
  goal: "Verify a completed sprint's implementation still matches its YAML contract and markdown spec. Produce a verification report. Generate remediation sprints if problems are found."
  start: Start
  exit: Exit

  defaults
    max_restarts: 5
    fidelity: summary:medium

  tool Start
    label: "Start Verification"
    timeout: 5s
    command:
      set -eu
      if [ ! -f .ai/current_verify_id.txt ]; then
        printf 'no-verify-id'
        exit 1
      fi
      target=$(cat .ai/current_verify_id.txt)
      sf=".ai/sprints/SPRINT-${target}.yaml"
      if [ ! -f "$sf" ]; then
        printf 'sprint-not-found-%s' "$target"
        exit 1
      fi
      printf 'verify-%s' "$target"

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      Sprint verification pipeline complete. Report final status.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete any files. Your ONLY job is to acknowledge completion.
```

- [ ] **Step 2: Add the ReadSprint tool node**

This node loads the sprint YAML, MD, and committed diff into context for downstream nodes.

```
  tool ReadSprint
    label: "Read Sprint Data"
    timeout: 15s
    command:
      set -eu
      target=$(cat .ai/current_verify_id.txt)
      sf=".ai/sprints/SPRINT-${target}.yaml"
      md=".ai/sprints/SPRINT-${target}.md"
      printf '=== SPRINT YAML ===\n'
      cat "$sf"
      printf '\n=== SPRINT NARRATIVE ===\n'
      if [ -f "$md" ]; then
        cat "$md"
      else
        printf '(no narrative file found)\n'
      fi
      # Find the commit hash for this sprint
      commit=$(yq '.history.attempts[] | select(.outcome == "success") | .run_id' "$sf" 2>/dev/null | tail -1)
      sprint_commit=$(yq ".commit // \"\"" "$sf" 2>/dev/null)
      if [ -n "$sprint_commit" ] && [ "$sprint_commit" != "null" ]; then
        printf '\n=== COMMITTED DIFF ===\n'
        git show --stat "$sprint_commit" 2>/dev/null || printf '(commit %s not found)\n' "$sprint_commit"
      fi
      printf '\nread-ok'
```

- [ ] **Step 3: Add the CheckArtifacts tool node**

```
  tool CheckArtifacts
    label: "Check Artifacts Exist"
    timeout: 10s
    command:
      set -eu
      target=$(cat .ai/current_verify_id.txt)
      sf=".ai/sprints/SPRINT-${target}.yaml"
      creates_count=$(yq '.artifacts.creates | length' "$sf" 2>/dev/null || echo 0)
      missing=""
      present=""
      i=0
      while [ "$i" -lt "$creates_count" ]; do
        path=$(yq ".artifacts.creates[$i].path" "$sf")
        if [ -f "$path" ]; then
          present="${present}\nPRESENT: ${path}"
        else
          missing="${missing}\nMISSING: ${path}"
        fi
        i=$((i + 1))
      done
      printf 'ARTIFACT_CHECK_TOTAL: %s' "$creates_count"
      if [ -n "$present" ]; then
        printf '%b' "$present"
      fi
      if [ -n "$missing" ]; then
        printf '%b' "$missing"
        printf '\nartifacts-missing'
        exit 0
      fi
      printf '\nartifacts-ok'
```

- [ ] **Step 4: Add the RunValidation tool node**

Reuses the same format-flexible parsing from ValidateBuild in sprint_exec_yaml_v2.dip.

```
  tool RunValidation
    label: "Run Validation Commands"
    timeout: 300s
    command:
      set -eu
      target=$(cat .ai/current_verify_id.txt)
      sf=".ai/sprints/SPRINT-${target}.yaml"
      if ! yq -e '.validation.commands' "$sf" >/dev/null 2>&1; then
        printf 'no-validation-commands\nvalidation-skip'
        exit 0
      fi
      count=$(yq '.validation.commands | length' "$sf")
      failures=0
      i=0
      while [ "$i" -lt "$count" ]; do
        cmd_field=$(yq ".validation.commands[$i].cmd // \"\"" "$sf" 2>/dev/null)
        if [ -n "$cmd_field" ] && [ "$cmd_field" != "null" ]; then
          cmd="$cmd_field"
          expect=$(yq ".validation.commands[$i].expect // \"exit_0\"" "$sf")
        else
          cmd=$(yq ".validation.commands[$i]" "$sf")
          expect="exit_0"
        fi
        printf '=== Validation %s/%s ===\n' "$((i+1))" "$count"
        printf 'cmd: %s\n' "$cmd"
        if [ "$expect" = "exit_0" ]; then
          if sh -c "$cmd" > /tmp/verify-validate.log 2>&1; then
            printf 'RESULT: PASS\n'
          else
            printf 'RESULT: FAIL\n'
            cat /tmp/verify-validate.log
            failures=$((failures + 1))
          fi
        elif printf '%s' "$expect" | grep -qE '^coverage >= [0-9]+%$'; then
          threshold=$(printf '%s' "$expect" | sed 's/coverage >= //;s/%//')
          sh -c "$cmd" > /tmp/verify-validate.log 2>&1 || true
          actual=$(grep -oE 'coverage: [0-9]+\.[0-9]+%' /tmp/verify-validate.log | tail -1 | sed 's/coverage: //;s/%//')
          if [ -z "$actual" ]; then
            printf 'RESULT: FAIL (could not parse coverage)\n'
            failures=$((failures + 1))
          else
            passes=$(awk "BEGIN {print ($actual >= $threshold) ? 1 : 0}")
            if [ "$passes" -eq 1 ]; then
              printf 'RESULT: PASS (coverage %s%% >= %s%%)\n' "$actual" "$threshold"
            else
              printf 'RESULT: FAIL (coverage %s%% < %s%%)\n' "$actual" "$threshold"
              failures=$((failures + 1))
            fi
          fi
        else
          sh -c "$cmd" > /tmp/verify-validate.log 2>&1 || true
          if grep -q "$expect" /tmp/verify-validate.log; then
            printf 'RESULT: PASS\n'
          else
            printf 'RESULT: FAIL (expected output containing: %s)\n' "$expect"
            cat /tmp/verify-validate.log
            failures=$((failures + 1))
          fi
        fi
        i=$((i + 1))
      done
      if [ "$failures" -gt 0 ]; then
        printf 'validation-failed-%s-of-%s' "$failures" "$count"
      else
        printf 'validation-ok'
      fi
```

- [ ] **Step 5: Add the CheckBuild tool node**

```
  tool CheckBuild
    label: "Check Build"
    timeout: 120s
    command:
      set -eu
      target=$(cat .ai/current_verify_id.txt)
      sf=".ai/sprints/SPRINT-${target}.yaml"
      build_cmd=$(yq '.stack.build // ""' "$sf" 2>/dev/null)
      if [ -z "$build_cmd" ] || [ "$build_cmd" = "null" ]; then
        if [ -f go.mod ]; then build_cmd="go build ./..."
        elif [ -f package.json ]; then build_cmd="npm run build"
        elif [ -f Cargo.toml ]; then build_cmd="cargo build"
        elif [ -f pyproject.toml ]; then build_cmd="uv run python -m py_compile"
        else
          printf 'no-build-system-detected\nbuild-skip'
          exit 0
        fi
      fi
      printf 'build-cmd: %s\n' "$build_cmd"
      if sh -c "$build_cmd" > /tmp/verify-build.log 2>&1; then
        printf 'build-ok'
      else
        printf 'BUILD FAILED:\n'
        cat /tmp/verify-build.log
        printf '\nbuild-failed'
      fi
```

- [ ] **Step 6: Add the RunRegressions tool node**

```
  tool RunRegressions
    label: "Run Regression Tests"
    timeout: 300s
    command:
      set -eu
      target=$(cat .ai/current_verify_id.txt)
      sf=".ai/sprints/SPRINT-${target}.yaml"
      # Collect directories to test from touch_only and artifact paths
      dirs=""
      touch_count=$(yq '.scope_fence.touch_only | length' "$sf" 2>/dev/null || echo 0)
      i=0
      while [ "$i" -lt "$touch_count" ]; do
        d=$(yq ".scope_fence.touch_only[$i]" "$sf")
        if [ -d "$d" ]; then
          dirs="${dirs} ./${d}..."
        fi
        i=$((i + 1))
      done
      creates_count=$(yq '.artifacts.creates | length' "$sf" 2>/dev/null || echo 0)
      i=0
      while [ "$i" -lt "$creates_count" ]; do
        p=$(yq ".artifacts.creates[$i].path" "$sf")
        d=$(dirname "$p")
        if [ -d "$d" ]; then
          dirs="${dirs} ./${d}/..."
        fi
        i=$((i + 1))
      done
      modifies_count=$(yq '.artifacts.modifies | length' "$sf" 2>/dev/null || echo 0)
      i=0
      while [ "$i" -lt "$modifies_count" ]; do
        p=$(yq ".artifacts.modifies[$i].path" "$sf")
        d=$(dirname "$p")
        if [ -d "$d" ]; then
          dirs="${dirs} ./${d}/..."
        fi
        i=$((i + 1))
      done
      if [ -z "$dirs" ]; then
        printf 'no-regression-scope\nregressions-skip'
        exit 0
      fi
      # Deduplicate
      dirs=$(printf '%s\n' $dirs | sort -u | tr '\n' ' ')
      printf 'regression-scope: %s\n' "$dirs"
      lang=$(yq '.stack.lang // ""' "$sf" 2>/dev/null)
      case "$lang" in
        go)
          if go test $dirs > /tmp/verify-regression.log 2>&1; then
            printf 'regressions-ok'
          else
            printf 'REGRESSION FAILURES:\n'
            cat /tmp/verify-regression.log
            printf '\nregressions-failed'
          fi
          ;;
        *)
          printf 'unsupported-lang-%s\nregressions-skip' "$lang"
          ;;
      esac
```

- [ ] **Step 7: Verify the file parses correctly**

Run: `cd /Users/harper/Public/src/2389/pipelines && tracker validate sprint/verify_sprint.dip`

If `tracker validate` is not available, manually review the .dip file for syntax issues (indentation, missing fields).

- [ ] **Step 8: Commit**

```bash
git add sprint/verify_sprint.dip
git commit -m "feat: add verify_sprint.dip scaffold with mechanical check tool nodes"
```

---

### Task 2: Add Semantic Review and Report Generation Agents to verify_sprint.dip

**Files:**
- Modify: `sprint/verify_sprint.dip`

- [ ] **Step 1: Add the SemanticReview agent node**

Append after the RunRegressions tool node:

```
  agent SemanticReview
    label: "Semantic Review"
    model: claude-opus-4-7
    provider: anthropic
    reasoning_effort: high
    auto_status: true
    prompt:
      You are the semantic verifier for a completed sprint. Your job is to check whether the implementation genuinely satisfies the Definition of Done and matches the sprint narrative spec.

      You receive mechanical check results from prior pipeline nodes as context. Use them — do not re-run commands.

      ## Your Inputs

      1. Read the sprint YAML at `.ai/sprints/SPRINT-{id}.yaml` (the ID is in `.ai/current_verify_id.txt`)
      2. Read the sprint narrative at `.ai/sprints/SPRINT-{id}.md`
      3. Read the actual source code files listed in `artifacts.creates` and `artifacts.modifies`
      4. Review the mechanical check results passed to you as context

      ## DoD Alignment Check

      For EACH item in the `dod` array:
      1. Read the DoD item literally
      2. Find the code, test, or configuration that satisfies it
      3. Grade it: `met`, `partially-met`, or `not-met`
      4. Cite evidence with file:line references

      Output format (one line per DoD item):
      ```
      DOD_CHECK: {number} | {met|partially-met|not-met} | "{DoD text}" | {file:line evidence or gap description}
      ```

      ## Spec-to-Code Alignment Check

      Compare the SPRINT-{id}.md narrative against the implementation:
      1. Are non-goals respected? (nothing built that's listed under non-goals)
      2. Do the requirements in the MD match what was built?
      3. Are there implementation gaps the tests don't cover?

      Output format:
      ```
      SPEC_CHECK: non-goals-respected | {pass|fail} | {details if fail}
      SPEC_CHECK: requirements-coverage | {full|partial} | {gap description if partial}
      SPEC_CHECK: test-coverage-gaps | {none|found} | {uncovered areas if found}
      ```

      ## Rules
      - Do NOT modify any files
      - Do NOT run any commands
      - Be strict — "partially-met" means the intent is there but implementation is incomplete
      - Cite specific file paths and line numbers for every finding
      - If mechanical checks already found failures, factor those into your assessment

      End your response with STATUS: success
```

- [ ] **Step 2: Add the GenerateReport agent node**

```
  agent GenerateReport
    label: "Generate Verification Report"
    model: claude-opus-4-7
    provider: anthropic
    reasoning_effort: high
    auto_status: true
    prompt:
      You are the report generator for sprint verification. Compile all mechanical check results and semantic review findings into a structured verification report.

      ## Your Inputs

      1. Read `.ai/current_verify_id.txt` for the sprint ID
      2. Read the sprint YAML at `.ai/sprints/SPRINT-{id}.yaml`
      3. Review all prior node outputs (mechanical checks + SemanticReview findings)

      ## Output

      Write a file at `.ai/sprints/SPRINT-{id}-verification.md` with this exact structure:

      ```markdown
      # Verification Report: Sprint {id} — {title}

      **Verdict:** {verified | verified-with-concerns | failed-verification}
      **Verified at:** {current UTC timestamp}
      **Commit:** {sprint commit hash from YAML, or "N/A"}

      ## Mechanical Checks

      | Check | Result | Details |
      |-------|--------|---------|
      | Artifacts exist | PASS/FAIL | {details} |
      | Validation commands | PASS/FAIL | {per-command summary} |
      | Build compiles | PASS/FAIL | {details} |
      | Regression tests | PASS/FAIL | {details} |

      ## DoD Alignment

      | # | Item | Status | Evidence |
      |---|------|--------|----------|
      | {from SemanticReview DOD_CHECK lines} |

      ## Spec-to-Code Alignment

      {from SemanticReview SPEC_CHECK lines}

      ## Remediation

      {if failed-verification: "Remediation sprints recommended — see CreateRemediationSprints output"}
      {if verified or verified-with-concerns: "None required"}
      ```

      ## Verdict Logic

      - **verified**: All mechanical checks pass AND all DoD items are `met` AND spec alignment is `full`
      - **verified-with-concerns**: All mechanical checks pass but some DoD items are `partially-met` OR spec has minor gaps
      - **failed-verification**: Any mechanical check fails OR any DoD item is `not-met` OR spec alignment has major gaps

      ## Rules
      - Write ONLY the verification report file — no other files
      - Do NOT modify the sprint YAML or ledger
      - End with STATUS: success if verdict is `verified` or `verified-with-concerns`
      - End with STATUS: fail if verdict is `failed-verification`
```

- [ ] **Step 3: Add the CreateRemediationSprints agent node**

```
  agent CreateRemediationSprints
    label: "Create Remediation Sprints"
    model: claude-opus-4-7
    provider: anthropic
    reasoning_effort: high
    auto_status: true
    prompt:
      You create remediation sprints when verification fails, or mark sprints as verified when they pass.

      ## Your Inputs

      1. Read `.ai/current_verify_id.txt` for the sprint ID
      2. Read the verification report at `.ai/sprints/SPRINT-{id}-verification.md`
      3. Read the original sprint YAML at `.ai/sprints/SPRINT-{id}.yaml`

      ## If verdict is `verified` or `verified-with-concerns`

      Update the sprint YAML to add:
      ```yaml
      verified: true
      verified_at: "{current UTC timestamp}"
      ```

      Then end with: STATUS: success

      ## If verdict is `failed-verification`

      For each distinct failure found in the verification report, create a remediation sprint:

      ### Naming Convention
      - First remediation: `{original_id}r` (e.g., `012r`)
      - If that ID exists in `.ai/sprints/`: use `{original_id}r2`, `{original_id}r3`, etc.

      ### For each remediation sprint, create TWO files:

      **1. `.ai/sprints/SPRINT-{rem_id}.yaml`:**
      ```yaml
      id: "{rem_id}"
      title: "Remediation: {concise description of what to fix}"
      status: planned
      bootstrap: false
      complexity: low
      depends_on: ["{original_id}"]
      dependents: []
      remediation_for: "{original_id}"
      remediation_reason: "{from verification findings}"
      stack: {copy from original sprint}
      scope_fence:
        off_limits:
          - "do not modify .ai/ledger.yaml"
        touch_only:
          - "{only directories related to the failure}"
      artifacts:
        creates: []
        modifies:
          - path: "{file that needs fixing}"
            type: module
      validation:
        commands:
          - cmd: "{test command that currently fails}"
            expect: exit_0
      dod:
        - "{specific fix derived from verification finding}"
        - "No regressions in affected test suite"
      history:
        attempts: []
      ```

      **2. `.ai/sprints/SPRINT-{rem_id}.md`:**
      Brief narrative with: Scope, Requirements, Expected fix, DoD checklist.

      ### Add to ledger
      Append each remediation sprint to `.ai/ledger.yaml` under the `sprints` array:
      ```yaml
        - id: "{rem_id}"
          title: "Remediation: {description}"
          status: planned
          bootstrap: false
          depends_on: ["{original_id}"]
          complexity: low
          created_at: "{timestamp}"
          updated_at: "{timestamp}"
          attempts: 0
          total_cost: "0.00"
      ```

      ### Update original sprint
      Add `verified: false` to the original sprint YAML (do NOT change its status — it stays `completed`).

      ### Scoping Rules
      - ONE remediation sprint per distinct failure — do not bundle
      - Always `complexity: low` — if the fix is complex, flag it in the report instead
      - Narrow `touch_only` — only directories/files related to the failure
      - DoD items come directly from the verification findings

      End with: STATUS: success (even when creating remediation sprints — the verification pipeline itself succeeded)
```

- [ ] **Step 4: Add the edges section**

```
  edges
    Start -> ReadSprint                        when ctx.outcome = success   label: start_ok
    Start -> Exit                              when ctx.outcome = fail      label: no_sprint
    Start -> Exit

    ReadSprint -> CheckArtifacts

    CheckArtifacts -> RunValidation
    RunValidation -> CheckBuild
    CheckBuild -> RunRegressions
    RunRegressions -> SemanticReview
    SemanticReview -> GenerateReport
    GenerateReport -> CreateRemediationSprints  when ctx.outcome = success  label: verified
    GenerateReport -> CreateRemediationSprints  when ctx.outcome = fail     label: needs_remediation
    GenerateReport -> CreateRemediationSprints

    CreateRemediationSprints -> Exit
```

- [ ] **Step 5: Validate the complete pipeline**

Run: `cd /Users/harper/Public/src/2389/pipelines && tracker validate sprint/verify_sprint.dip`

- [ ] **Step 6: Commit**

```bash
git add sprint/verify_sprint.dip
git commit -m "feat: add semantic review, report generation, and remediation sprint agents to verify_sprint.dip"
```

---

### Task 3: Create verify_sprints_runner.dip — Batch Runner

**Files:**
- Create: `sprint/verify_sprints_runner.dip`

- [ ] **Step 1: Create the complete batch runner pipeline**

```
# ABOUTME: Batch verification runner — iterates through all completed sprints and runs verify_sprint.dip on each.
# ABOUTME: Produces per-sprint verification reports and a final VERIFICATION-SUMMARY.md with overall project health.
workflow VerifySprintsRunner
  goal: "Iterate through all completed sprints in .ai/ledger.yaml, run verify_sprint.dip on each, track results, and produce a final verification summary."
  start: Start
  exit: Exit

  defaults
    max_restarts: 100
    fidelity: summary:medium

  tool Start
    label: "Start Verification Runner"
    timeout: 5s
    command:
      set -eu
      printf 'verification-runner-starting'

  agent Exit
    label: Exit
    max_turns: 1
    prompt:
      Verification runner pipeline complete. Report final status.

      HARD CONSTRAINT: Do NOT write code. Do NOT create, modify, or delete any files. Your ONLY job is to acknowledge completion.

  tool CheckYq
    label: "Check yq"
    timeout: 5s
    command:
      set -eu
      if ! command -v yq >/dev/null 2>&1; then
        printf 'yq-not-found'
        exit 1
      fi
      printf 'yq-ok'

  agent YqMissing
    label: "yq Not Found"
    max_turns: 1
    prompt:
      The yq YAML processor is required but not installed.

      Install it:
        macOS:  brew install yq
        Linux:  snap install yq

      After installing, re-run the pipeline.

  tool FindCompletedSprints
    label: "Find Completed Sprints"
    timeout: 15s
    command:
      set -eu
      if [ ! -f .ai/ledger.yaml ]; then
        printf 'no-ledger'
        exit 1
      fi
      # Collect completed sprints that are not yet verified
      queue=""
      for sid in $(yq '.sprints[] | select(.status == "completed") | .id' .ai/ledger.yaml); do
        sf=".ai/sprints/SPRINT-${sid}.yaml"
        if [ -f "$sf" ]; then
          verified=$(yq '.verified // false' "$sf")
          if [ "$verified" != "true" ]; then
            queue="${queue}${sid}\n"
          fi
        else
          queue="${queue}${sid}\n"
        fi
      done
      if [ -z "$queue" ]; then
        printf 'all-verified'
        exit 0
      fi
      printf '%b' "$queue" | sed '/^$/d' > .ai/verify-queue.txt
      count=$(wc -l < .ai/verify-queue.txt | tr -d ' ')
      printf 'found-%s-sprints-to-verify' "$count"

  tool PickNext
    label: "Pick Next Sprint"
    timeout: 5s
    command:
      set -eu
      if [ ! -f .ai/verify-queue.txt ] || [ ! -s .ai/verify-queue.txt ]; then
        rm -f .ai/verify-queue.txt
        printf 'all-done'
        exit 0
      fi
      next=$(head -1 .ai/verify-queue.txt)
      tail -n +2 .ai/verify-queue.txt > .ai/verify-queue-tmp.txt
      mv .ai/verify-queue-tmp.txt .ai/verify-queue.txt
      printf '%s' "$next" > .ai/current_verify_id.txt
      printf 'next-%s' "$next"

  subgraph verify_sprint
    ref: verify_sprint.dip

  tool RecordResult
    label: "Record Verification Result"
    timeout: 10s
    command:
      set -eu
      target=$(cat .ai/current_verify_id.txt 2>/dev/null || echo "unknown")
      report=".ai/sprints/SPRINT-${target}-verification.md"
      if [ -f "$report" ]; then
        verdict=$(grep '^**Verdict:**' "$report" | sed 's/.*\*\*Verdict:\*\* //')
      else
        verdict="no-report-generated"
      fi
      printf '%s | %s\n' "$target" "$verdict" >> .ai/verification-results.txt
      # Count progress
      total=$(wc -l < .ai/verification-results.txt 2>/dev/null | tr -d ' ')
      remaining=0
      if [ -f .ai/verify-queue.txt ]; then
        remaining=$(wc -l < .ai/verify-queue.txt | tr -d ' ')
      fi
      printf 'recorded-%s-%s-verified-%s-remaining' "$target" "$total" "$remaining"

  agent FinalReport
    label: "Final Verification Report"
    model: claude-opus-4-7
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the final report generator for the sprint verification sweep.

      ## Your Inputs

      1. Read `.ai/verification-results.txt` — contains one line per verified sprint: `{id} | {verdict}`
      2. Read `.ai/ledger.yaml` for overall project context
      3. Scan `.ai/sprints/SPRINT-*-verification.md` for detailed findings on any `failed-verification` sprints
      4. Check for any remediation sprints (sprints with `remediation_for` field in their YAML)

      ## Output

      Write `VERIFICATION-SUMMARY.md` in the project root with:

      ```markdown
      # Verification Summary

      **Run date:** {current UTC timestamp}
      **Sprints verified:** {count}
      **Verdicts:** {X verified, Y verified-with-concerns, Z failed-verification}

      ## Results

      | Sprint | Title | Verdict | Key Findings |
      |--------|-------|---------|--------------|
      | {per sprint from results file} |

      ## Remediation Sprints Created

      | ID | Remediates | Description |
      |----|-----------|-------------|
      | {list any remediation sprints found in the ledger} |

      ## Overall Health Assessment

      {2-3 paragraphs: project health, systemic patterns in failures, recommendations}
      ```

      ## Rules
      - Write ONLY the VERIFICATION-SUMMARY.md file
      - Do NOT modify sprint YAMLs, the ledger, or any source code

  edges
    Start -> CheckYq
    CheckYq -> FindCompletedSprints   when ctx.outcome = success      label: yq_ok
    CheckYq -> YqMissing              when ctx.outcome = fail         label: yq_missing
    CheckYq -> Exit

    YqMissing -> Exit

    FindCompletedSprints -> PickNext  when ctx.tool_stdout startswith found-  label: has_sprints
    FindCompletedSprints -> Exit      when ctx.tool_stdout = all-verified     label: nothing_to_verify
    FindCompletedSprints -> Exit      when ctx.outcome = fail                 label: no_ledger
    FindCompletedSprints -> Exit

    PickNext -> verify_sprint         when ctx.tool_stdout startswith next-   label: verify_next
    PickNext -> FinalReport           when ctx.tool_stdout = all-done         label: all_done
    PickNext -> FinalReport

    verify_sprint -> RecordResult     when ctx.outcome = success              label: verified
    verify_sprint -> RecordResult     when ctx.outcome = fail                 label: failed_verification
    verify_sprint -> RecordResult

    RecordResult -> PickNext          restart: true

    FinalReport -> Exit
```

- [ ] **Step 2: Validate the pipeline**

Run: `cd /Users/harper/Public/src/2389/pipelines && tracker validate sprint/verify_sprints_runner.dip`

- [ ] **Step 3: Commit**

```bash
git add sprint/verify_sprints_runner.dip
git commit -m "feat: add verify_sprints_runner.dip batch verification runner"
```

---

### Task 4: Validate Both Pipelines Together

**Files:**
- Verify: `sprint/verify_sprint.dip`, `sprint/verify_sprints_runner.dip`

- [ ] **Step 1: Validate the subgraph reference resolves**

Run: `cd /Users/harper/Public/src/2389/pipelines && tracker validate sprint/verify_sprints_runner.dip`

This should confirm that `verify_sprint.dip` is found and valid as a subgraph reference.

- [ ] **Step 2: Dry-run test with a known-good sprint**

Create a test verify-queue with one completed sprint:

```bash
cd /Users/harper/workspace/2389/codegen-tracks/sprint-based/code-agent
echo "003" > .ai/current_verify_id.txt
```

Run just the verifier subgraph:
```bash
tracker run /Users/harper/Public/src/2389/pipelines/sprint/verify_sprint.dip
```

Confirm:
- ReadSprint loads SPRINT-003.yaml
- CheckArtifacts finds all created files
- RunValidation runs the validation commands
- CheckBuild runs `go build ./...`
- SemanticReview produces DOD_CHECK and SPEC_CHECK lines
- GenerateReport writes `SPRINT-003-verification.md`
- CreateRemediationSprints marks `verified: true` (since 003 should be clean)

- [ ] **Step 3: Clean up test artifacts**

```bash
rm -f .ai/current_verify_id.txt
```

- [ ] **Step 4: Commit any fixes**

If validation or dry-run exposed issues, fix and commit:
```bash
git add sprint/verify_sprint.dip sprint/verify_sprints_runner.dip
git commit -m "fix: address validation issues in verification pipelines"
```
