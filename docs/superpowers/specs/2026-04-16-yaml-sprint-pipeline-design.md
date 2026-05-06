# YAML Sprint Pipeline Design

## Summary

Replace the TSV-based sprint ledger and guesswork-driven execution pipeline with a YAML-based system that gives code agents structured metadata: tech stack, validation contracts, dependency graphs, scope fences, file manifests, and failure history. Add dedicated bootstrap sprints (000–002) with human-gate-on-failure behavior for infrastructure setup. Fork as new files alongside the originals.

## Motivation

The current pipeline has recurring problems:

1. **The ledger is too thin.** `ledger.tsv` has 5 columns (id, title, status, created_at, updated_at). No dependencies, no stack info, no failure history. Agents must read full markdown docs and guess at tech stack every run.

2. **Infrastructure bootstrapping fails frequently.** Sprint 1 is always scaffolding by convention, but nothing gives it special treatment. When Docker isn't running or an env var is missing, the agent burns 50 turns guessing instead of asking a human.

3. **Agents have no memory across runs.** When ImplementSprint resumes after a failure, it has zero context about what went wrong last time. It repeats the same mistakes.

4. **ValidateBuild guesses the stack.** It checks for `pyproject.toml`, `package.json`, `Package.swift` etc. in a waterfall. If the project uses a non-standard layout, validation silently passes or runs the wrong commands.

5. **Scope enforcement is prose-only.** "HARD CONSTRAINT: Do NOT implement future sprints" works ~80% of the time. Agents still drift.

## New Files

| File | Based on | Purpose |
|---|---|---|
| `sprint_exec_yaml.dip` | `sprint_exec.dip` | Sprint execution with YAML reading, bootstrap routing, human gate on bootstrap failure |
| `sprint_runner_yaml.dip` | `sprint_runner.dip` | Loop controller with YAML ledger reading, yq preflight, ref to sprint_exec_yaml.dip |
| `spec_to_sprints_yaml.dip` | `spec_to_sprints.dip` | Sprint decomposition with bootstrap generation, dual YAML+md output, YAML ledger |

Original files (`sprint_exec.dip`, `sprint_runner.dip`, `spec_to_sprints.dip`) are untouched.

## Runtime Dependency

`yq` (YAML processor) must be installed. All pipelines check for it at startup and fail with an install instruction if missing.

---

## YAML Ledger Format

Replaces `.ai/ledger.tsv`. Lives at `.ai/ledger.yaml`.

```yaml
project:
  name: "Project Name"
  stack:
    lang: python
    runner: uv
    test: pytest
    lint: ruff
    build: null
  created_at: 2026-04-15T01:26:43Z

sprints:
  - id: "000"
    title: "Project scaffold & toolchain"
    status: completed
    bootstrap: true
    depends_on: []
    complexity: low
    created_at: 2026-04-15T01:26:43Z
    updated_at: 2026-04-15T02:00:00Z
    attempts: 1
    total_cost: "0.12"
  - id: "001"
    title: "External services & dev environment"
    status: in_progress
    bootstrap: true
    depends_on: ["000"]
    complexity: low
    created_at: 2026-04-15T01:26:43Z
    updated_at: 2026-04-16T20:09:35Z
    attempts: 2
    total_cost: "0.87"
```

### Ledger fields

| Field | Type | Description |
|---|---|---|
| `project.name` | string | Project name from spec analysis |
| `project.stack` | object | Tech stack (lang, runner, test, lint, build) — single source of truth |
| `project.created_at` | datetime | When the ledger was created |
| `sprints[].id` | string | Zero-padded 3-digit ID |
| `sprints[].title` | string | Short descriptive title |
| `sprints[].status` | enum | planned, in_progress, completed, skipped, failed |
| `sprints[].bootstrap` | bool | Whether this is an infrastructure sprint |
| `sprints[].depends_on` | list[string] | Sprint IDs that must complete first |
| `sprints[].complexity` | enum | low, medium, high |
| `sprints[].created_at` | datetime | Creation timestamp |
| `sprints[].updated_at` | datetime | Last status change |
| `sprints[].attempts` | int | Number of execution attempts |
| `sprints[].total_cost` | string | Cumulative dollar cost across attempts |

---

## Per-Sprint YAML Format

Lives at `.ai/sprints/SPRINT-NNN.yaml` alongside `SPRINT-NNN.md`.

The .md is the human-readable narrative (unchanged format). The .yaml is the machine-readable contract.

```yaml
id: "001"
title: "External services & dev environment"
status: in_progress
bootstrap: true
complexity: low

depends_on: ["000"]
dependents: ["002", "003"]

stack:
  services:
    - name: postgres
      compose: true
    - name: nats
      compose: true

scope_fence:
  off_limits:
    - "do not modify .ai/ledger.yaml"
    - "do not implement sprint 002 or later"
    - "do not add features beyond scope"
  touch_only:
    - "docker-compose.yml"
    - "backend/app/database.py"
    - ".env.example"

entry_preconditions:
  files_must_exist:
    - "pyproject.toml"
    - "backend/app/main.py"
  sprints_must_be_complete: ["000"]

artifacts:
  creates:
    - path: "docker-compose.yml"
      type: config
    - path: "backend/app/database.py"
      type: module
    - path: ".env.example"
      type: config
  modifies:
    - path: "backend/app/main.py"
      type: module

validation:
  commands:
    - cmd: "docker compose up -d && sleep 3 && docker compose ps --format json"
      expect: "running"
    - cmd: "cd backend && uv run pytest tests/test_database.py -v"
      expect: exit_0
    - cmd: "cd backend && uv run ruff check ."
      expect: exit_0

dod:
  - "docker compose up -d starts PostgreSQL and NATS; health checks pass"
  - "database.py async engine connects to PostgreSQL"
  - "pytest tests/test_database.py passes with ≥3 tests"
  - "ruff check reports zero errors"
  - ".env.example documents all required env vars"

history:
  attempts:
    - date: 2026-04-16T20:00:00Z
      run_id: "5d51c1f87319"
      outcome: fail
      reason: "POSIX shell syntax error in CheckLedgerIntegrity"
      cost: "0.33"
      turns: 14
    - date: 2026-04-16T21:00:00Z
      run_id: "c6fd269c61e1"
      outcome: success
      cost: "0.54"
      turns: 27
```

### Per-Sprint YAML fields

| Field | Purpose for code agent |
|---|---|
| `scope_fence.off_limits` | Injected into ImplementSprint prompt — machine-enforced boundaries |
| `scope_fence.touch_only` | Optional allowlist — agent can verify it's not modifying unexpected files |
| `entry_preconditions.files_must_exist` | Agent verifies starting state before doing work |
| `entry_preconditions.sprints_must_be_complete` | Cross-checked against ledger.yaml |
| `artifacts.creates / modifies` | Completion verification — do all expected files exist? |
| `validation.commands` | ValidateBuild executes these directly instead of guessing stack |
| `validation.commands[].expect` | `exit_0` means command must exit with code 0. Any other string means grep stdout for that string. |
| `dod` | Structured checklist for ReviewAnalysis |
| `history.attempts` | Agent reads prior failures to avoid repeating mistakes |
| `stack.services` | Agent knows what external services are available |

---

## Bootstrap Sprint Behavior

Any sprint with `bootstrap: true` in its YAML gets special treatment in `sprint_exec_yaml.dip`.

### What changes for bootstrap sprints

1. **Human gate on failure.** After max resumes (3), instead of `FailureSummary → Exit`, the pipeline routes to `HumanBootstrapGate`:
   - **[S] Retry** — human fixed something (env vars, Docker, etc.), agent tries again
   - **[A] Abort** — give up, pipeline exits

2. **Simplified review.** Bootstrap sprints skip the multi-model review tournament (3 reviews + 6 cross-critiques = 9 LLM calls). After `CommitSprintWork`, they go straight to `CompleteSprint`. The `ValidateBuild` step using the sprint YAML's `validation.commands` is sufficient for scaffolding.

3. **Auto-generation.** `spec_to_sprints_yaml.dip` always generates bootstrap sprints:
   - **Sprint 000** (always): Project scaffold — repo init, package manager, test harness, linter config, CI skeleton
   - **Sprint 001** (if services detected): External services — docker-compose, database, message broker, env vars
   - **Sprint 002** (always): Hello world proof — one endpoint/function, one test, full stack round-trip

Feature sprints start at 003+ and `depends_on` at minimum `["002"]` (or `["000"]` if Sprint 001 was not needed).

### Bootstrap detection

A `CheckBootstrap` tool node runs after `ReadSprint`. It reads the sprint YAML and emits `bootstrap-true` or `bootstrap-false` to stdout:

```shell
set -eu
target=$(cat .ai/current_sprint_id.txt)
is_bootstrap=$(yq ".bootstrap // false" ".ai/sprints/SPRINT-${target}.yaml")
if [ "$is_bootstrap" = "true" ]; then
  printf 'bootstrap-true'
else
  printf 'bootstrap-false'
fi
```

Edge routing branches on `ctx.tool_stdout`:
- `bootstrap-true` → bootstrap path (simplified review, human gate on failure)
- `bootstrap-false` → normal path (full review tournament)

---

## sprint_exec_yaml.dip Edge Routing

### Common preamble (both paths)

```
Start → EnsureLedger → CheckYq → FindNextSprint → SetCurrentSprint
→ ReadSprint → CheckBootstrap
```

`CheckBootstrap` branches based on `ctx.tool_stdout`:

### Normal sprint path (bootstrap-false)

```
CheckBootstrap → MarkInProgress → SnapshotLedger → ImplementSprint
→ CheckLedgerIntegrity → ValidateBuild → CommitSprintWork
→ ReviewParallel → CritiquesParallel → ReviewAnalysis
→ CompleteSprint → Exit
```

Normal failure: `ImplementSprint fails → ResumeCheck (max 3) → FailureSummary → Exit`

### Bootstrap sprint path (bootstrap-true)

```
CheckBootstrap → MarkInProgress → SnapshotLedger → ImplementSprint
→ CheckLedgerIntegrity → ValidateBuild → CommitSprintWork
→ CompleteSprint → Exit
```

(Skips ReviewParallel, CritiquesParallel, ReviewAnalysis)

Bootstrap failure: `ImplementSprint fails → ResumeCheck (max 3) → HumanBootstrapGate`
- **[S] Retry** → SnapshotLedger → ImplementSprint (restart: true)
- **[A] Abort** → FailureSummary → Exit

---

## sprint_runner_yaml.dip Changes

Minimal changes from `sprint_runner.dip`:

1. **check_ledger** reads `.ai/ledger.yaml` via `yq` instead of `awk` on TSV
2. **report_progress** reads YAML for completed/total counts via `yq`
3. **Subgraph ref** points to `sprint_exec_yaml.dip`
4. **yq preflight** at pipeline start — checks `command -v yq`, fails with install instructions if missing

Loop structure, human gate, failure_summary, edge routing all unchanged.

---

## spec_to_sprints_yaml.dip Changes

The tournament decomposition (parallel agents + cross-critiques + merge) is unchanged. What changes:

### 1. merge_decomposition gains bootstrap sprint generation

The merge prompt instructs the agent to always prepend bootstrap sprints based on the detected tech stack from `spec_analysis.md`. Sprint 000 is always scaffold. Sprint 001 is services (if applicable). Sprint 002 is always hello-world proof. Feature sprints renumber from 003+.

### 2. write_sprint_docs generates dual output

For each sprint, the agent writes:
- `.ai/sprints/SPRINT-NNN.md` — narrative (existing format)
- `.ai/sprints/SPRINT-NNN.yaml` — structured contract (new format, full schema)

### 3. write_ledger generates YAML

Replaces the TSV writer. Assembles `.ai/ledger.yaml` from:
- `project.stack` extracted from spec_analysis.md
- Sprint entries built from each `SPRINT-NNN.yaml` file

### 4. validate_output checks YAML consistency

- Every sprint in `ledger.yaml` has matching `.yaml` + `.md` in `.ai/sprints/`
- Every YAML has required fields (id, title, status, validation.commands, dod, artifacts, scope_fence)
- Dependency graph has no cycles (topological sort check)
- Bootstrap sprints exist and are sequenced first
- `yq` validates YAML syntax on all files

### 5. setup_workspace checks for yq

Routes to a human gate with install instructions if `yq` is not found.

---

## .ai/ Directory Structure

```
.ai/
  ledger.yaml                 # replaces ledger.tsv
  current_sprint_id.txt       # unchanged
  spec_analysis.md            # unchanged
  sprint_plan.md              # unchanged
  ledger-snapshot.yaml        # snapshot for integrity check (runtime only)
  implement-resume-count.txt  # resume tracking (runtime only)
  drafts/                     # unchanged (decomposition drafts)
  sprints/
    SPRINT-000.md             # narrative
    SPRINT-000.yaml           # structured contract
    SPRINT-001.md
    SPRINT-001.yaml
    ...
```

---

## ImplementSprint Prompt Enhancement

The ImplementSprint agent node reads the per-sprint YAML and the agent prompt is dynamically augmented with:

1. **Stack context** from `project.stack` and sprint `stack.services`
2. **Scope fence** from `scope_fence.off_limits` and `scope_fence.touch_only`
3. **Entry check** — verify `entry_preconditions.files_must_exist` before starting work
4. **Failure context** from `history.attempts` — what went wrong last time
5. **Artifact checklist** from `artifacts.creates` and `artifacts.modifies`
6. **Validation commands** from `validation.commands` — agent can self-test during implementation

The agent reads the YAML itself (it's a code agent with file access). The prompt tells it which fields to check and how to use them.

---

## Migration Path

Projects currently using the TSV pipeline can continue using the original dip files. No migration is required. To adopt the YAML pipeline on an existing project:

1. Run `spec_to_sprints_yaml.dip` against the project spec (generates new .ai/ structure)
2. Or manually create `ledger.yaml` and per-sprint YAMLs from existing TSV + markdown

No automated migration tool is in scope for this design.
