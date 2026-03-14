# dot-files

A collection of [mammoth](https://github.com/2389-research/mammoth) DOT pipelines for use with [tracker](https://github.com/2389-research/tracker) — the agentic pipeline engine that executes multi-step AI workflows defined as Graphviz DOT graphs.

## Quick Start

```bash
# Install tracker
go install github.com/2389-research/tracker/cmd/tracker@latest

# Configure API keys
tracker setup

# Run a pipeline
tracker speedrun.dot
```

You will need API keys for the LLM providers used in each pipeline (Anthropic, OpenAI, Gemini). See the [tracker docs](https://github.com/2389-research/tracker#configuration) for details.

## Pipelines

### Development Pipelines

| Pipeline | Description |
|----------|-------------|
| `speedrun.dot` | Ultra-minimal build pipeline — fastest path from spec to shipped code. No brainstorm, no design doc. Read spec, plan, implement, test, ship. Fully headless. |
| `bug-hunter.dot` | Autonomous bug fix pipeline — reads a bug report, reproduces, diagnoses, fixes via TDD, and ships a PR. Fully headless. |
| `refactor-express.dot` | Autonomous incremental refactoring — analyzes code, plans steps where tests stay green at every step, executes with rollback on failure. |
| `doc-writer.dot` | Autonomous documentation generator — explores a codebase and produces README, API reference, architecture guide, and tutorials with verified code examples. |

### Interactive Pipelines

| Pipeline | Description |
|----------|-------------|
| `20q.dot` | 20 Questions game — the AI asks yes/no questions to guess what you're thinking of within 20 questions. |
| `story-engine.dot` | Choose-your-own-adventure game — AI writes branching narrative scenes, you make story choices that shape the plot across multiple chapters. |
| `model-debate.dot` | Multi-model debate arena — Claude, GPT, and Gemini argue positions on a topic you choose across three rounds, then you judge the winner. |

## How It Works

Each `.dot` file defines a directed graph where nodes represent pipeline steps and edges define control flow. Node shapes map to handler types in tracker:

- `box` — LLM call with tool access
- `hexagon` — Human input gate (yes/no or freeform)
- `parallelogram` — Shell command execution
- `component` / `tripleoctagon` — Parallel fan-out / fan-in
- `diamond` — Conditional branching

Pipelines configure LLM providers and models via `model_stylesheet` in the graph attributes. Most pipelines use a mix of Claude, GPT, and Gemini models for different roles.

## Related Projects

- [tracker](https://github.com/2389-research/tracker) — The runtime engine that executes these pipelines
- [mammoth](https://github.com/2389-research/mammoth) — The DOT pipeline format and ecosystem
- [dotpowers](https://github.com/2389-research/dotpowers) — Superpowers-based pipelines (kitchen-sink, test-kitchen, scenario-testing)

---

Built by [2389.ai](https://2389.ai)
