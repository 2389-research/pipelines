# Migration: `write_sprint_docs` → architect + Sonnet generator

## What changed

`spec_to_sprints.dip:537` — the `write_sprint_docs` agent.

**Before:** Opus reads upstream inputs and uses its native `write` tool 16 times to emit thin SPRINT-NNN.md files (~50 lines each, ~5 KB total).

**After:** Opus is the architect. It reads upstream inputs, authors a project-wide contract to `.ai/contract.md`, then iterates over the sprint plan calling `write_enriched_sprint` once per sprint. The tool reads the contract from disk on every invocation and uses Sonnet to generate the per-sprint markdown (~700-800 lines each, ~30 KB per sprint).

Pipeline shape (edges/nodes) is **unchanged**. The architect's tool calls map 1:1 with sprints, so the natural stop signal that made the original pattern reliable is preserved.

## Why

- The thin format wasn't dense enough to feed local-LLM sprint executors (qwen via `sprint_exec_local_gen_qwen.dip`) reliably — too much was left to inference.
- Doing the enriched output in one Opus call hit the per-turn output cap.
- Single Opus call producing all 16 enriched sprints in one batch lost the natural stop signal and required hard-coded STOP instructions; iterate-per-sprint reuses the proven shape.
- Sonnet generator does the formatting/density work at ~1/5 the per-token cost of Opus.

## New runtime requirements

The architect requires the `write_enriched_sprint` tool registration in tracker. The tool registers itself only when these env vars are set on the tracker process:

- `TRACKER_SPRINT_WRITER_MODEL` — required, e.g. `claude-sonnet-4-6`
- `TRACKER_SPRINT_WRITER_PROVIDER` — optional, defaults to `anthropic`

If `TRACKER_SPRINT_WRITER_MODEL` is unset, the tool isn't available and the architect's tool calls will fail. Set it in the shell environment before running tracker:

```fish
set -x TRACKER_SPRINT_WRITER_MODEL claude-sonnet-4-6
```

Or per-invocation:

```fish
TRACKER_SPRINT_WRITER_MODEL=claude-sonnet-4-6 tracker spec_to_sprints.dip
```

## Cost & time impact

Measured on a 16-sprint run against the NIFB fixtures:

| Metric | Old (thin sprints) | New (enriched sprints) |
|---|---|---|
| Cost per pipeline run | ~$0.30 | ~$3.30 |
| Time | ~3 min | ~30 min |
| Output bytes | ~5 KB total | ~470 KB total (16 × 30 KB) |
| Output lines | ~800 total | ~12,000 total |

Cost is ~10× higher; output is ~95× richer. Per-line cost is ~10× lower.

Cost breakdown for new pipeline:
- Sonnet (16 sprint generations): ~$2.20
- Opus (architect): ~$1.10

## New artifact: `.ai/contract.md`

The architect now writes `.ai/contract.md` (~600-800 lines) before any sprint is generated. It documents:
- Stack & runtime decisions
- Project-wide conventions (error handling, naming, async/sync, logging)
- Sprint file-ownership map
- Cross-sprint type/symbol ownership map (with exact field names + signatures)
- Cross-sprint dependency edges
- Mandatory rules across all sprints

The contract is committed alongside `.ai/sprints/` and `.ai/ledger.tsv` via `commit_output`. It's the single source of truth for the cross-sprint surface and useful for review/audit.

## Section format change in SPRINT-NNN.md

Enriched sprints have a different section list than the thin format. `validate_output` updated accordingly.

| Section | Thin format | Enriched format |
|---|---|---|
| `## Scope` | required | required |
| `## Non-goals` | optional | required |
| `## Requirements` (FR list) | required | dropped — FR coverage woven into Scope/Dependencies |
| `## Dependencies` | required | required |
| `## Interface contract` | not present | required (load-bearing for qwen executor) |
| `## Imports per file` | not present | required (load-bearing for qwen executor) |
| `## Algorithm notes` | not present | required (load-bearing for qwen executor) |
| `## Test plan` | not present | required (load-bearing for qwen executor) |
| `## Expected Artifacts` | required | required |
| `## DoD` | required | required |
| `## Validation` | required | required |

The four "load-bearing" sections are the ones `sprint_exec_local_gen_qwen.dip` references in its per-file generator prompt: *"Use the Interface contract, Algorithm notes, Imports per file, and Test plan sections for this file"*.

## Downstream consumers

- **`sprint_exec_local_gen_qwen.dip` and siblings** — work unchanged. They benefit from the richer format (more reliable single-shot generation by qwen).
- **`sprint_exec_tier2*.dip` (cloud executors)** — work unchanged.
- **Anything that parsed `## Requirements` for FR IDs** — needs an update. FR coverage is now in `## Scope` prose or `## Dependencies` lines. (Not aware of any current consumer that does this.)
- **`enrich_one.dip`** — becomes redundant in the spec→sprints flow since enrichment is now built in. Keep it for retrofitting older projects that have thin sprints.

## Validation retry behavior

`validate_output` runs after `write_sprint_docs`. If validation fails, the existing edge restarts the architect:

```
validate_output -> write_sprint_docs  when ctx.tool_stdout != valid  label: fix_validation  restart: true
```

A retry now reruns the full architect (re-reads inputs, rewrites contract, regenerates sprints) — costly. Most validation failures should be rare (missing section is the most likely cause). If retries become common, consider adding a cheaper "fix one missing section" sub-flow.

## Rollback

Revert spec_to_sprints.dip to the prior commit. The `write_enriched_sprint` tool stays registered (no harm) but goes unused.

## Test workdirs

- `experiments/enrich_sprints_test/architect_v1/.ai/sprints/` — full 16-sprint NIFB run output (validates pattern at scale, confirms cross-sprint coherence)
- `experiments/enrich_sprints_test/architect_v1/.ai_run3_3sprints/` — earlier 3-sprint run (kept for diff comparisons)
- `experiments/enrich_sprints_test/probe/` — tool-only smoke test (single sprint generation with hand-crafted contract)
