# pipelines

A collection of [Dippin](https://github.com/2389-research/dippin-lang) pipelines for use with [tracker](https://github.com/2389-research/tracker) — the agentic pipeline engine that executes multi-step AI workflows.

## Quick Start

```bash
# Install tracker
go install github.com/2389-research/tracker/cmd/tracker@latest

# Configure API keys
tracker setup

# Run a pipeline
tracker build-and-ship/speedrun.dip
```

You will need API keys for the LLM providers used in each pipeline (Anthropic, OpenAI, Gemini). See the [tracker docs](https://github.com/2389-research/tracker#configuration) for details.

## Projects

### [Build & Ship](build-and-ship/)

Single-pass build pipelines — fastest path from spec or bug report to shipped code.

| Pipeline | Description |
|----------|-------------|
| [`speedrun.dip`](build-and-ship/speedrun.dip) | Ultra-minimal build pipeline — read spec, plan, implement, test, ship. Fully headless. |
| [`build_from_superpowers.dip`](build-and-ship/build_from_superpowers.dip) | Builds from a superpowers spec — finds the spec, executes every task, commits with passing tests. |
| [`bug-hunter.dip`](build-and-ship/bug-hunter.dip) | Autonomous bug fix — reproduces, diagnoses, fixes via TDD, and ships a PR. |
| [`refactor-express.dip`](build-and-ship/refactor-express.dip) | Incremental refactoring — tests stay green at every step, rollback on failure. |
| [`doc-writer.dip`](build-and-ship/doc-writer.dip) | Documentation generator — README, API reference, architecture guide, and tutorials. |

### [Sprint](sprint/)

Sprint decomposition and execution with budget and YAML variants.

| Pipeline | Description |
|----------|-------------|
| [`spec_to_sprints.dip`](sprint/spec_to_sprints.dip) | Decomposes a spec into `SPRINT-*.md` files via multi-model tournament with human approval. |
| [`sprint_exec.dip`](sprint/sprint_exec.dip) | Executes the next incomplete sprint through implementation, validation, and review. |
| [`sprint_runner.dip`](sprint/sprint_runner.dip) | Runs all sprints in sequence until every sprint is completed. |
| [`sprint_exec-cheap.dip`](sprint/sprint_exec-cheap.dip) | Budget variant using smaller models with escalation. |
| [`sprint_runner-cheap.dip`](sprint/sprint_runner-cheap.dip) | Budget variant of the sprint runner. |
| [`megaplan.dip`](sprint/megaplan.dip) | Multi-model orientation, drafting, critique, and merge for sprint planning. |

YAML variants: `spec_to_sprints_yaml`, `spec_to_sprints_yaml_v2`, `sprint_exec_yaml`, `sprint_exec_yaml_v2`, `sprint_runner_yaml`, `sprint_runner_yaml_v2`, `spec_to_ship_yaml`

### [Local Code Gen](local_code_gen/)

Sprint pipeline that uses Opus/Sonnet for architecture and a local **qwen3.6:35b-a3b** (via Ollama) for code generation, with cloud (gpt-5.4) escalation only when local fix attempts are exhausted. Architect emits enriched `SPRINT-*.md` files via the `dispatch_sprints` tool; runner uses 4-strategy SR-block matching with rollback. Happy path costs $0.00 for codegen.

| Pipeline | Description |
|----------|-------------|
| [`architect_only.dip`](local_code_gen/architect_only.dip) | Just the architect step — produces contract, sprint plan JSONL, and `SPRINT-*.md` files. Skips upstream decomposition tournament. |
| [`spec_to_sprints.dip`](local_code_gen/spec_to_sprints.dip) | Full upstream tournament + the architect step end-to-end. |
| [`sprint_runner.dip`](local_code_gen/sprint_runner.dip) | Per-sprint loop: qwen Generate → SR-block LocalFix → CloudFix escalation → Audit → Commit. |

See [`local_code_gen/README.md`](local_code_gen/README.md) for setup, model config, and the design principles in [`local_code_gen/principles/`](local_code_gen/principles/).

### [Pipeline Generation](pipeline-gen/)

Meta-pipelines that generate `.dip` files from specs via multi-model tournament.

| Pipeline | Description |
|----------|-------------|
| [`spec_to_dip.dip`](pipeline-gen/spec_to_dip.dip) | Generates a validated `.dip` pipeline with domain-specific review panels. |
| [`pipeline_from_spec.dip`](pipeline-gen/pipeline_from_spec.dip) | Generates a pipeline scoring against objective pattern and coverage metrics. |
| [`pipeline_from_spec_v2.dip`](pipeline-gen/pipeline_from_spec_v2.dip) | Revised with updated quality gates. |
| [`pipeline_from_superpowers.dip`](pipeline-gen/pipeline_from_superpowers.dip) | Generates a pipeline from a superpowers-format spec. |

### [Greenfield](greenfield/)

New project validation — discovery, synthesis, review, and validation stages.

| Pipeline | Description |
|----------|-------------|
| [`greenfield.dip`](greenfield/greenfield.dip) | Orchestrator — runs the full greenfield validation flow. |
| [`greenfield_discovery.dip`](greenfield/greenfield_discovery.dip) | Explores the problem space, identifies constraints and opportunities. |
| [`greenfield_synthesis.dip`](greenfield/greenfield_synthesis.dip) | Generates candidate architectures and approaches. |
| [`greenfield_review.dip`](greenfield/greenfield_review.dip) | Multi-model evaluation of synthesized candidates. |
| [`greenfield_validation.dip`](greenfield/greenfield_validation.dip) | Final feasibility and risk assessment. |

### [Iterative](iterative/)

Incremental development with PAR (Parallel Adversarial Review) gates.

| Pipeline | Description |
|----------|-------------|
| [`iter_dev.dip`](iterative/iter_dev.dip) | Orchestrator — coordinates scope → extract → run → audit cycle. |
| [`iter_scope.dip`](iterative/iter_scope.dip) | Scopes work from a behavior corpus with structural/risk PAR review. |
| [`iter_extract.dip`](iterative/iter_extract.dip) | Extracts actionable tasks with coverage/intent PAR review. |
| [`iter_run.dip`](iterative/iter_run.dip) | Implements a task with spec/quality PAR reviews and failure loops. |
| [`iter_audit.dip`](iterative/iter_audit.dip) | Three-tier audit — traceability, execution verification, drift detection. |

### [Interactive](interactive/)

Human-in-the-loop games and debates.

| Pipeline | Description |
|----------|-------------|
| [`20q.dip`](interactive/20q.dip) | 20 Questions — AI asks yes/no questions to guess what you're thinking of. |
| [`story-engine.dip`](interactive/story-engine.dip) | Choose-your-own-adventure with branching narrative. |
| [`model-debate.dip`](interactive/model-debate.dip) | Multi-model debate arena — Claude, GPT, and Gemini argue, you judge. |

## How It Works

Each `.dip` file defines a workflow in the [Dippin language](https://github.com/2389-research/dippin-lang) — a DSL for describing agentic pipelines. Workflows declare nodes (agents, tools, human gates, parallel branches, conditionals) and edges with optional conditions.

Tracker reads the `.dip` file, builds the execution graph, and orchestrates LLM agents through it — dispatching tasks to Claude, GPT, or Gemini in isolated git worktrees with parallel execution support and a TUI dashboard.

### Node Types

- **agent** — LLM call with tool access
- **human** — Human input gate (choice, freeform, or interview)
- **tool** — Shell command execution
- **parallel** / **fan_in** — Parallel fan-out and synchronization
- **conditional** — Branching based on context

## Related Projects

- [tracker](https://github.com/2389-research/tracker) — The runtime engine that executes these pipelines
- [dippin-lang](https://github.com/2389-research/dippin-lang) — The Dippin language compiler, LSP, and toolchain

---

Built by [2389.ai](https://2389.ai)
