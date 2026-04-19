# Sprint Dip Tech Decoupling

**Date:** 2026-04-16
**Status:** Approved
**Scope:** `sprint_exec.dip`, `sprint_exec-cheap.dip`, `sprint_runner.dip`

## Problem

The three sprint execution dips hardcode language-specific guidance in two places:

1. **Tool nodes** (`PreFlight`, `ValidateBuild`) — if/else chains for Swift/Node/Python/Rust/Go that drift across files. The NIFB Sprint 001 post-mortem (2026-04-16) documented `ValidateBuild` in `sprint_exec.dip` missing Python detection while the cheap variant already had it. Classic copy-paste drift.

2. **Agent prompts** — "Environment Rules" and "Test Infrastructure" sections spoon-feed language-specific commands (`uv run`, `npm install`, SQLite fallback) to implementation agents. These models already know how Python/Go/Swift projects work. The prescriptive prompts were added after the NIFB failure, but the root cause was a missing preflight check, not the agent being ignorant of Python conventions.

## Design

### Principle: trust the agents, keep tool nodes deterministic

- **Agent nodes** are smart. They can read a `pyproject.toml` and know to use `uv`. Strip the hand-holding.
- **Tool nodes** must stay deterministic for trustless verification (per the mammoth "agents lie about tests" RFC). They auto-detect the stack inline.

### Change 1: Strip tech-specific guidance from agent prompts

Delete the "Environment Rules" and "Test Infrastructure" sections from every `Implement*` and `ImplementRescue` agent prompt across all three dips.

Replace with one generic line:

> Read the PreFlight output for environment context. Follow standard practices for the detected stack.

**Affected agents:**
- `sprint_exec.dip`: `ImplementSprint`
- `sprint_exec-cheap.dip`: `ImplementCheap`, `ImplementRescue`
- `sprint_runner.dip`: `implement_sprint`

### Change 2: One canonical ValidateBuild

Create one definitive auto-detection shell block that handles all supported languages. Apply it identically to all ValidateBuild tool nodes across the three dips (plus `ValidateRescue` in the cheap variant).

The canonical version:

```sh
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

**Key properties:**
- All five languages present in every copy (no drift)
- Consistent error handling: capture log, cat on failure, exit 1
- Lint included for languages that have standard linters (ruff for Python)
- `sprint_runner.dip` already had the most complete version; this standardizes from it

### Change 3: PreFlight stays as-is

The PreFlight tool already checks everything generically (docker, uv, node, swift, compose, project structure). It's the same across all three dips. No changes needed beyond keeping copies in sync when one is updated.

### What we're NOT doing

- **No toolchain profile file.** Over-engineered for the problem.
- **No external scripts.** The dips run against arbitrary repos; can't assume scripts exist.
- **No per-language dip variants.** Multiplies the drift problem.
- **No dip-level include/fragment system.** That's a mammoth engine feature, out of scope.

## Files to change

| File | Changes |
|---|---|
| `sprint_exec.dip` | Strip Environment Rules + Test Infrastructure from `ImplementSprint` prompt. Update `ValidateBuild` to canonical version. |
| `sprint_exec-cheap.dip` | Strip Environment Rules + Test Infrastructure from `ImplementCheap` and `ImplementRescue` prompts. Update `ValidateBuild` and `ValidateRescue` to canonical version. |
| `sprint_runner.dip` | Strip Environment Rules + Test Infrastructure from `implement_sprint` prompt. Update `validate_build` to canonical version. |

## Residual risk

Three copies of the same tool node shells will still exist. This is a process discipline issue, not an architecture issue. The 20-line auto-detect block is small enough to diff visually. If drift becomes a recurring problem, the right fix is a mammoth engine feature (shared tool definitions or dip includes), not more layers of indirection in the dip files.
