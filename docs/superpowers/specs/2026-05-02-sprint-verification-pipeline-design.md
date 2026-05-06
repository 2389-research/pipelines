# Sprint Verification Pipeline Design

## Overview

Two pipelines that verify completed sprints still satisfy their contracts and generate remediation sprints when they don't.

- **`verify_sprint.dip`** — verifies a single sprint across six dimensions: artifacts exist, validation commands pass, build compiles, no regressions, DoD semantic alignment, spec-to-code alignment.
- **`verify_sprints_runner.dip`** — batch runner that iterates through all completed sprints and calls `verify_sprint.dip` as a subgraph.

When verification fails, the verifier writes narrowly-scoped remediation sprints into the ledger. The existing `sprint_runner_yaml_v2.dip` then executes those remediation sprints like any other sprint — no special handling needed.

## Architecture

### Pipeline Relationship

```
verify_sprints_runner.dip
  └── verify_sprint.dip (subgraph, called per sprint)

sprint_runner_yaml_v2.dip (existing — executes remediation sprints)
  └── sprint_exec_yaml_v2.dip (existing)
```

### verify_sprint.dip — Single Sprint Verifier

**Goal:** Verify a completed sprint's implementation still matches its contract. Produce a verification report. Generate remediation sprints if problems are found.

**Flow:** Sequential — mechanical checks first (fast, cheap), then semantic review (Opus). Mechanical results feed into the semantic review as context.

```
Start → ReadSprint → CheckArtifacts → RunValidation → CheckBuild
  → RunRegressions → SemanticReview → GenerateReport
  → CreateRemediationSprints → Exit
```

#### Node Specifications

| Node | Type | Model | Timeout | Purpose |
|------|------|-------|---------|---------|
| `Start` | tool | — | 5s | Read `.ai/current_verify_id.txt`, confirm sprint YAML exists |
| `ReadSprint` | tool | — | 10s | Load `SPRINT-{id}.yaml`, `SPRINT-{id}.md`, and committed diff via `git log --format= -p --follow` for the sprint's commit hash |
| `CheckArtifacts` | tool | — | 10s | Verify every path in `artifacts.creates` exists on disk. Output: list of present/missing paths |
| `RunValidation` | tool | — | 300s | Re-run all `validation.commands` from sprint YAML. Support both `{cmd, expect}` objects and plain strings. Support `exit_0`, `coverage >= N%`, and output-substring expectations. Output: per-command pass/fail with stdout/stderr |
| `CheckBuild` | tool | — | 120s | Run language-appropriate build command from `stack.build` (fallback: detect from go.mod/package.json/Cargo.toml/etc). Output: pass/fail with error output |
| `RunRegressions` | tool | — | 300s | Run tests scoped to directories from `scope_fence.touch_only` and paths from `artifacts.creates`/`artifacts.modifies`. Output: per-package pass/fail with failure details |
| `SemanticReview` | agent | claude-opus-4-7 | — | Read DoD items + sprint MD + actual code. Grade each DoD item as met/partially-met/not-met with citations. Check spec-to-code alignment. Receives all mechanical results as context |
| `GenerateReport` | agent | claude-opus-4-7 | — | Compile mechanical + semantic results into `SPRINT-{id}-verification.md`. Set verdict: `verified` / `verified-with-concerns` / `failed-verification` |
| `CreateRemediationSprints` | agent | claude-opus-4-7 | — | If `failed-verification`: write remediation sprint YAMLs + MDs, add to ledger. If `verified` or `verified-with-concerns`: set `verified: true` + timestamp on sprint YAML |
| `Exit` | tool | — | 5s | Output verdict for the runner |

#### Edge Logic

All mechanical checks (CheckArtifacts, RunValidation, CheckBuild, RunRegressions) pass results forward regardless of pass/fail. No short-circuiting — the Opus reviewer needs the full picture to write good remediation sprint specs.

Exception: if `ReadSprint` can't find the sprint YAML, exit immediately with `sprint-not-found`.

```
Start → ReadSprint
ReadSprint → CheckArtifacts          when ctx.outcome = success
ReadSprint → Exit                    when ctx.outcome = fail        label: sprint_not_found

CheckArtifacts → RunValidation
RunValidation → CheckBuild
CheckBuild → RunRegressions
RunRegressions → SemanticReview
SemanticReview → GenerateReport
GenerateReport → CreateRemediationSprints
CreateRemediationSprints → Exit
```

#### SemanticReview Output Format

Structured findings, not prose:

```
DOD_CHECK: 1 | met | "Provider implements the Router interface" | internal/provider/anthropic/anthropic.go:45
DOD_CHECK: 2 | not-met | "Cost tracking per request" | RecordCost is defined but never called in production path
SPEC_CHECK: non-goals-respected | pass
SPEC_CHECK: requirements-coverage | partial | "retry logic described in requirements but not implemented"
```

The `GenerateReport` agent consumes these structured findings and produces both a human-readable report and the overall verdict.

### verify_sprints_runner.dip — Batch Runner

**Goal:** Iterate through all completed sprints, run verification, track results, produce a summary.

**Flow:**

```
Start → CheckYq → FindCompletedSprints → PickNext → verify_sprint(subgraph)
  → RecordResult → PickNext(restart) ...
  → AllDone → FinalReport → Exit
```

#### Node Specifications

| Node | Type | Model | Purpose |
|------|------|-------|---------|
| `Start` | tool | — | Acknowledge, check prerequisites |
| `CheckYq` | tool | — | Gate: verify `yq` is installed |
| `FindCompletedSprints` | tool | — | Read ledger, collect all sprint IDs with `status: completed` and without `verified: true`. Write to `.ai/verify-queue.txt` |
| `PickNext` | tool | — | Pop next ID from `.ai/verify-queue.txt`, write to `.ai/current_verify_id.txt`. If queue empty, output `all-done` |
| `verify_sprint` | subgraph | — | Run single-sprint verifier |
| `RecordResult` | tool | — | Append sprint ID + verdict to `.ai/verification-results.txt`. Loop back to `PickNext` |
| `AllDone` | agent | claude-sonnet-4-6 | Transition node |
| `FinalReport` | agent | claude-opus-4-7 | Read all verification results, produce `VERIFICATION-SUMMARY.md` — table of verdicts, list of remediation sprints created, overall health assessment |
| `Exit` | tool | — | Done |

#### Edge Logic

```
Start → CheckYq
CheckYq → FindCompletedSprints       when ctx.outcome = success
CheckYq → Exit                       when ctx.outcome = fail

FindCompletedSprints → PickNext
PickNext → verify_sprint              when ctx.outcome startswith next-
PickNext → AllDone                    when ctx.outcome = all-done
PickNext → Exit

verify_sprint → RecordResult          when ctx.outcome = success
verify_sprint → RecordResult          when ctx.outcome = fail
verify_sprint → RecordResult

RecordResult → PickNext               restart: true

AllDone → FinalReport
FinalReport → Exit
```

**Key design decisions:**
- **No failure budget** — verification is diagnostic. A sprint failing verification doesn't stop the sweep. Record and move on.
- **Queue file** — avoids re-verifying sprints already verified in this run.
- **Skip already-verified** — `FindCompletedSprints` filters out sprints with `verified: true` so re-runs only check newly completed sprints.
- **Dependency order not required** — unlike execution, verification order doesn't matter.

## Remediation Sprint Design

When `CreateRemediationSprints` fires (verdict = `failed-verification`), it generates new sprint YAMLs following these rules:

### Naming Convention

`{original_id}r` — e.g., Sprint 012 gets `012r`. If `012r` exists, increment: `012r2`, `012r3`.

### Sprint YAML Structure

Standard sprint contract — the regular sprint runner can execute it without special handling:

```yaml
id: "012r"
title: "Remediation: Fix regression in session persistence tests"
status: planned
bootstrap: false
complexity: low
depends_on: ["012"]
remediation_for: "012"
remediation_reason: "validation command 'go test ./internal/store/...' fails: TestSessionPersist/concurrent_writes"
scope_fence:
  off_limits:
    - "do not modify .ai/ledger.yaml"
  touch_only:
    - "internal/store/"
artifacts:
  modifies:
    - path: "internal/store/sessions.go"
      type: module
validation:
  commands:
    - cmd: "go test ./internal/store/... -v -run TestSessionPersist"
      expect: exit_0
dod:
  - "TestSessionPersist/concurrent_writes passes"
  - "No regressions in ./internal/store/... test suite"
```

### Scoping Rules

- **One remediation sprint per distinct failure** — don't bundle multiple unrelated fixes
- **Always `complexity: low`** — if the fix is complex, that signals the original sprint needs redecomposition, not remediation
- **Narrow `touch_only`** — only directories/files related to the failure
- **DoD from findings** — items come directly from the verification report
- **`depends_on` includes original** — ensures ordering
- **Two new fields:** `remediation_for` (links back to original sprint ID) and `remediation_reason` (human-readable explanation from verification findings)

### Ledger Integration

- Remediation sprint is appended to `ledger.yaml` with proper `depends_on`
- Original sprint status stays `completed` — but gets `verified: false` added to its YAML
- After remediation sprint completes, re-running the verifier should flip to `verified: true`

## Verification Report Format

Each verified sprint gets `SPRINT-{id}-verification.md` in `.ai/sprints/`:

```markdown
# Verification Report: Sprint {id} — {title}

**Verdict:** verified | verified-with-concerns | failed-verification
**Verified at:** {timestamp}
**Commit:** {hash}

## Mechanical Checks

| Check | Result | Details |
|-------|--------|---------|
| Artifacts exist | PASS/FAIL | {missing paths if any} |
| Validation commands | PASS/FAIL | {per-command results} |
| Build compiles | PASS/FAIL | {error output if any} |
| Regression tests | PASS/FAIL | {failed tests if any} |

## DoD Alignment

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | {DoD text} | met/partially-met/not-met | {file:line citation} |
| 2 | ... | ... | ... |

## Spec-to-Code Alignment

- Non-goals respected: PASS/FAIL
- Requirements coverage: full/partial — {gaps if any}

## Remediation

{List of remediation sprints created, or "None required"}
```

## State Files

| File | Purpose | Lifecycle |
|------|---------|-----------|
| `.ai/current_verify_id.txt` | Current sprint being verified | Written by `PickNext`, read by `verify_sprint/Start` |
| `.ai/verify-queue.txt` | Queue of sprint IDs to verify | Written by `FindCompletedSprints`, consumed by `PickNext` |
| `.ai/verification-results.txt` | Running log of verdicts | Appended by `RecordResult`, read by `FinalReport` |
| `SPRINT-{id}-verification.md` | Per-sprint verification report | Written by `GenerateReport` |
| `VERIFICATION-SUMMARY.md` | Batch run summary | Written by `FinalReport` |

## Model Assignments

| Node | Model | Provider | Rationale |
|------|-------|----------|-----------|
| SemanticReview | claude-opus-4-7 | anthropic | Needs deep code comprehension for DoD/spec alignment |
| GenerateReport | claude-opus-4-7 | anthropic | Synthesizes mechanical + semantic findings into coherent report |
| CreateRemediationSprints | claude-opus-4-7 | anthropic | Must write well-scoped sprint contracts from verification findings |
| FinalReport | claude-opus-4-7 | anthropic | Cross-sprint health assessment |
| AllDone | claude-sonnet-4-6 | anthropic | Simple transition node |
| All tool nodes | — | — | No LLM needed |

## Integration with Existing Pipelines

The verification pipeline is fully decoupled from the sprint execution pipeline:

1. **Run verification** → `verify_sprints_runner.dip` sweeps completed sprints
2. **Remediation sprints appear in ledger** → standard `planned` status with `depends_on` wiring
3. **Run sprint runner** → `sprint_runner_yaml_v2.dip` picks up remediation sprints like any other
4. **Re-run verification** → confirms remediation sprints fixed the issues, marks `verified: true`

No changes to `sprint_exec_yaml_v2.dip` or `sprint_runner_yaml_v2.dip` are required. The only new field consumed by the verifier is `verified: true` on sprint YAMLs, which the existing pipelines can safely ignore.
