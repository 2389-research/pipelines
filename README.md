# pipelines

A collection of [Dippin](https://github.com/2389-research/dippin-lang) pipelines for use with [tracker](https://github.com/2389-research/tracker) — the agentic pipeline engine that executes multi-step AI workflows.

## Quick Start

```bash
# Install tracker
go install github.com/2389-research/tracker/cmd/tracker@latest

# Configure API keys
tracker setup

# Run a pipeline
tracker speedrun.dip
```

You will need API keys for the LLM providers used in each pipeline (Anthropic, OpenAI, Gemini). See the [tracker docs](https://github.com/2389-research/tracker#configuration) for details.

## Pipelines

### Build & Ship

| Pipeline | Description |
|----------|-------------|
| `speedrun.dip` | Ultra-minimal build pipeline — fastest path from spec to shipped code. Read spec, plan, implement, test, ship. Fully headless. |
| `build_from_superpowers.dip` | Builds a project from a superpowers spec and plan — finds the spec, executes every task, and commits with passing tests. |
| `bug-hunter.dip` | Autonomous bug fix — reads a bug report, reproduces, diagnoses, fixes via TDD, and ships a PR. |
| `refactor-express.dip` | Incremental refactoring — analyzes code, plans steps where tests stay green at every step, executes with rollback on failure. |
| `doc-writer.dip` | Documentation generator — explores a codebase and produces README, API reference, architecture guide, and tutorials. |

### Sprint Execution

| Pipeline | Description |
|----------|-------------|
| `spec_to_sprints.dip` | Decomposes a spec into `SPRINT-*.md` files and a `.ai/ledger.tsv` using multi-model tournament decomposition with human approval. |
| `sprint_exec.dip` | Executes the next incomplete sprint from the ledger through implementation, validation, multi-model review, and completion. |
| `sprint_runner.dip` | Runs all sprints in sequence, looping until every sprint is completed. Inlines full sprint execution with review tournament and human gates. |
| `sprint_exec-cheap.dip` | Budget variant of sprint execution using smaller models (Haiku/Nano/Flash-Lite) with escalation. |
| `sprint_runner-cheap.dip` | Budget variant of the sprint runner with the same loop-and-escalation pattern. |
| `megaplan.dip` | Creates a sprint plan using multi-model orientation, drafting, critique, and merge stages. |
| `sprint_exec_local_gen_qwen.dip` | Local-first sprint execution using **qwen3.6:35b-a3b-q8_0** via Ollama for both generation and fixing. Language auto-detected (Go, Node.js, Python). Escalates to gpt-5.4 cloud only if local model exhausts 4 fix attempts. Happy path costs $0.00. |
| `sprint_exec_local_gen_gemma.dip` | Same local-first pipeline using **gemma4:26b** via Ollama. Faster generation than qwen (~2x), slightly noisier output. Same language detection and cloud escalation. |

### Pipeline Generation

| Pipeline | Description |
|----------|-------------|
| `spec_to_dip.dip` | Generates a validated `.dip` pipeline from a spec using multi-model tournament with domain-specific review panels. |
| `pipeline_from_spec.dip` | Generates a pipeline `.dip` file from a spec, scoring against objective pattern and coverage metrics. |
| `pipeline_from_spec_v2.dip` | Revised pipeline-from-spec with updated quality gates. |
| `pipeline_from_superpowers.dip` | Generates a pipeline from a superpowers-format spec. |

### Interactive

| Pipeline | Description |
|----------|-------------|
| `20q.dip` | 20 Questions game — the AI asks yes/no questions to guess what you're thinking of. |
| `story-engine.dip` | Choose-your-own-adventure — AI writes branching narrative scenes, you make choices that shape the plot. |
| `model-debate.dip` | Multi-model debate arena — Claude, GPT, and Gemini argue positions on a topic across rounds, then you judge. |

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
