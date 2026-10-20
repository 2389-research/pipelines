# Build & Ship

Single-pass build pipelines — the fastest path from a spec or bug report to shipped code.

## Pipelines

| Pipeline | Description |
|----------|-------------|
| `speedrun.dip` | Ultra-minimal build pipeline — read spec, plan, implement, test, ship. Fully headless. |
| `build_from_superpowers.dip` | Builds a project from a superpowers spec and plan — finds the spec, executes every task, and commits with passing tests. |
| `bug-hunter.dip` | Autonomous bug fix — reads a bug report, reproduces, diagnoses, fixes via TDD, and commits the fix on a branch. |
| `idea-to-pr.dip` | Free-text idea to shipped change — writes a reviewable spec.md / plan.md / tasks.md first, then builds and validates the P1 slice (left in the working tree; the caller commits it). |
| `refactor-express.dip` | Incremental refactoring — analyzes code, plans steps where tests stay green at every step, executes with rollback on failure. |
| `doc-writer.dip` | Documentation generator — explores a codebase and produces README, API reference, architecture guide, and tutorials. |

## Usage

```bash
tracker build-and-ship/speedrun.dip
```

These are the canonical versions tracker-runner runs in production. None of them
opens a pull request: `bug-hunter`, `doc-writer`, `refactor-express` and
`speedrun` commit their change on a branch, and `idea-to-pr` leaves it in the
working tree. Opening the PR is the caller's job (tracker-runner's host, or you),
so a run never holds a GitHub write token.
