# Iterative

Iterative development pipelines for incremental feature delivery with PAR (Parallel Adversarial Review) gates at each stage.

## Pipelines

| Pipeline | Description |
|----------|-------------|
| `iter_run.dip` | Runs a single iteration — implements a task, validates with spec/quality PAR reviews, and loops on failures. |
| `iter_audit.dip` | Three-tier audit — AC traceability, execution verification, and drift detection with command-level validation. |
| `iter_dev.dip` | Development orchestrator — coordinates scope → extract → run → audit cycle. |
| `iter_scope.dip` | Scopes work from a behavior corpus — structural linkage and strategic risk PAR review. |
| `iter_extract.dip` | Extracts actionable tasks from scoped stories — textual coverage and semantic intent PAR review. |

## Usage

```bash
tracker iterative/iter_dev.dip
```

Pipeline state lives under `docs/iterations/` in the project being built (requirements, roadmap, behavior scenarios, behavior corpus, iteration log).

## Inspiration

These pipelines draw inspiration from Obra's superpowers project — the iterative-development skill in particular. The behavior-evidence loop, PAR review gates, and walking-skeleton scoping pattern are adapted from that workflow into tracker-driven `.dip` form. This is not superpowers; it is a separate implementation that borrows the shape of the idea.
