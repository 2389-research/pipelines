# Sprint

Sprint decomposition and execution pipelines. Spec → sprints → execute → review loop.

Includes budget variants (`-cheap`) that use smaller models with escalation, YAML-output variants for structured data, and `megaplan` for multi-model planning.

## Pipelines

| Pipeline | Description |
|----------|-------------|
| `spec_to_sprints.dip` | Decomposes a spec into `SPRINT-*.md` files and a `.ai/ledger.tsv` using multi-model tournament decomposition with human approval. |
| `spec_to_sprints_yaml.dip` | YAML-output variant of spec-to-sprints. |
| `spec_to_sprints_yaml_v2.dip` | Revised YAML-output variant with updated quality gates. |
| `sprint_exec.dip` | Executes the next incomplete sprint through implementation, validation, multi-model review, and completion. |
| `sprint_exec-cheap.dip` | Budget variant using smaller models (Haiku/Nano/Flash-Lite) with escalation. |
| `sprint_exec_yaml.dip` | YAML-output variant of sprint execution. |
| `sprint_exec_yaml_v2.dip` | Revised YAML-output variant with updated gates. |
| `sprint_runner.dip` | Runs all sprints in sequence, looping until every sprint is completed. |
| `sprint_runner-cheap.dip` | Budget variant of the sprint runner. |
| `sprint_runner_yaml.dip` | YAML-output variant of the sprint runner. |
| `sprint_runner_yaml_v2.dip` | Revised YAML-output sprint runner. |
| `spec_to_ship_yaml.dip` | End-to-end spec-to-ship with YAML output. |
| `megaplan.dip` | Creates a sprint plan using multi-model orientation, drafting, critique, and merge stages. |

## Usage

```bash
tracker sprint/spec_to_sprints.dip
tracker sprint/sprint_runner.dip
```
