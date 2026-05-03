# Pipeline Generation

Meta-pipelines that generate `.dip` pipeline files from specs. Uses multi-model tournament with domain-specific review panels.

## Pipelines

| Pipeline | Description |
|----------|-------------|
| `spec_to_dip.dip` | Generates a validated `.dip` pipeline from a spec using multi-model tournament with domain-specific review panels. |
| `pipeline_from_spec.dip` | Generates a pipeline `.dip` file from a spec, scoring against objective pattern and coverage metrics. |
| `pipeline_from_spec_v2.dip` | Revised pipeline-from-spec with updated quality gates. |
| `pipeline_from_superpowers.dip` | Generates a pipeline from a superpowers-format spec. |

## Usage

```bash
tracker pipeline-gen/spec_to_dip.dip
```
