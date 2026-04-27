# Build & Ship

Single-pass build pipelines — the fastest path from a spec or bug report to shipped code.

## Pipelines

| Pipeline | Description |
|----------|-------------|
| `speedrun.dip` | Ultra-minimal build pipeline — read spec, plan, implement, test, ship. Fully headless. |
| `build_from_superpowers.dip` | Builds a project from a superpowers spec and plan — finds the spec, executes every task, and commits with passing tests. |
| `bug-hunter.dip` | Autonomous bug fix — reads a bug report, reproduces, diagnoses, fixes via TDD, and ships a PR. |
| `refactor-express.dip` | Incremental refactoring — analyzes code, plans steps where tests stay green at every step, executes with rollback on failure. |
| `doc-writer.dip` | Documentation generator — explores a codebase and produces README, API reference, architecture guide, and tutorials. |

## Usage

```bash
tracker build-and-ship/speedrun.dip
```
