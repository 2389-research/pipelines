# Pickup notes — 2026-04-28

## The plan we landed on

Replace the current `write_sprint_docs` Opus call (which produces 16 thin
SPRINT-NNN.md files in one shot) with an **architect + generator** pattern:

- **Architect = Opus.** Reads `sprint_plan.md` + `spec_analysis.md` + spec.
  Writes one shared "enrichment contract": conventions, naming, runtime,
  cross-sprint inheritance rules — basically a project-wide style guide
  derived from the merge output. ~300 lines.
- **Generator = Sonnet.** Invoked via tracker's `generate_code` tool, once
  per sprint. Gets the contract + per-sprint description. Returns the
  full enriched `SPRINT-NNN.md` (~400 lines).

Why this shape:

1. **Quality:** matches enrich_one density (validated on `local-gen-test/`)
2. **Token cap:** monolithic enrichment of all 16 sprints in one call
   blows past Opus's 8K output ceiling. Per-sprint generation stays under.
3. **Cost:** architect is one Opus call; the 16 expensive per-sprint
   enrichments run at Sonnet rates. Rough estimate: 1×$0.30 + 16×$0.10 ≈
   $1.90 vs ~$3.20 if all 16 were Opus.
4. **Consistency:** single contract = single source of truth for conventions.
   No need for sequential inheritance chains — every Sonnet call sees the
   same conventions.

## The pattern already exists in this repo

`sprint_exec_tier2_strong_architect.dip` (lines 1–80) is the template.
It does architect + generator for **code** (gpt-5.4 architects, nano
generates). We're translating it to **markdown sprint docs** with
Opus → Sonnet.

Other relevant variants:

- `sprint_exec_nano_architect.dip` — nano architects, nano generates
  (cheap-everywhere variant of the same pattern)
- `sprint_exec_tier2_transcribe.dip` — even more constrained
- `sprint_exec_tier2.dip` — base version

## Things to verify before writing the patch

1. **Where is the generator model configured?** In tier2_strong_architect
   the architect is explicitly `gpt-5.4`, but the generator (nano) isn't
   visibly pinned. Probably in workflow `defaults` or a `codergen` handler
   config. Confirm before drafting.
2. **Can `generate_code` mix providers?** Architect Opus (Anthropic) →
   generator Sonnet (Anthropic) is same-provider so likely fine. Worth
   double-checking we're not locked into matching architect's provider.
3. **Does `generate_code` accept markdown files?** The tool takes
   `{path, description}` per file; description doesn't seem to enforce
   code semantics. Should work for `.md`, but verify with a small test
   before scaling.

## Where to start tomorrow

1. Read `sprint_exec_tier2_strong_architect.dip` end-to-end (haven't read
   past line 80; want to see the Setup, generator config, fix loop).
2. Draft `enrich_sprints_architect.dip` — architect block produces the
   enrichment contract; calls `generate_code` with one entry per sprint
   in `sprint_plan.md`.
3. Test against either:
   - `local-gen-test/.ai/sprints/SPRINT-005.md` (already have a working
     project to compare; first un-enriched sprint in that dir)
   - Or a NIFB sprint (richer client context but no working code to verify
     against; would need to seed `inputs/spec.md` with a stack)
4. If quality holds, draft the patch to `spec_to_sprints.dip` replacing
   `write_sprint_docs` with the architect+generator block.

## Today's findings worth carrying forward

### Tournament insights

- **Critiques are detailed but heavily compressed.** Total ~350KB of
  structured findings across 6 critiques (typically ~80 issues total).
  Merge sees them via `fidelity: summary:medium` injection in its prompt,
  compressed to ~6KB. Critical/important findings survive; minor and
  long-tail findings get squashed.
- **Bumping fidelity on the merge node is probably the highest-leverage
  cheap edit** to the existing pipeline. Should test once we have a
  working harness.
- **Same systematic errors recur run-over-run** (CRM bundle, dep
  inversion, FR6 OAuth gap) → the merge prompt isn't forcing the model
  to address every flagged finding. A merge-prompt rewrite to enumerate
  every critical/important finding by name is also high-leverage.

### Model A/B for `decompose_gpt` (apples-to-apples with isolated workdirs)

| Variant | Cost | Sprints | Bundles | Verdict |
|---|---|---|---|---|
| 5.2-high | $0.27 | 15 | 2 | dep inversion present |
| 5.2-medium | $0.23 | 16 | 2 | best granularity, worst schema |
| 5.4-low | $0.14 | 15 | n/a | **missed FR2** — disqualified |
| 5.4-medium | $0.20 | 12 | 4 (incl. bad fusion) | over-consolidates |
| **5.4-high** | **$0.29** | **13** | **1 (CRM only)** | **clear winner** |
| 5.4-mini | $0.01 | failed | — | needs anti-snooping prompt; failed on sterile workdir |

5.4-high autonomously fixed: dep inversion, schema discipline (separate
Title field, JSON deps, `- [ ]` checkboxes), special-pathways/E2E split,
added production-readiness sprint with feature flags + monitoring +
runbooks. **Best output of any variant tested, by a wide margin.**

### Production migration target

For `decompose_gpt` in `spec_to_sprints.dip`: swap `gpt-5.2` → `gpt-5.4`
with `reasoning_effort: high`. Strictly better; ~+$0.27/pipeline run.
Hard deadline: gpt-5.2 retires June 5, 2026.

### Remaining unfixed issues (need real prompt edits)

- CRM bundle (FR22+23+24 in one sprint) — every variant kept this
- 18 Open Questions never referenced anywhere in sprint plans
- FR6 OAuth (Google/Apple) silently dropped in non-goals — every variant

## Tools/state on disk

- Harness: `experiments/decompose_gpt_harness/`
  - 6 .dip variants (5.2 high/medium, 5.4 low/medium/high, 5.4-mini)
  - `workdirs/<variant>/` — isolated per-run workdirs
  - `baseline/` — outputs from all variants for comparison
  - `.ai/spec_analysis.md` — input fixture (NIFB)
- Production pipeline: `spec_to_sprints.dip` (root)
- Enrichment template: `enrich_one.dip` (root) — has BEFORE/AFTER example
  inline that's the canonical density spec
- Validated enrichment outputs: `experiments/local-gen-test/.ai/sprints/`
  (SPRINT-000 through SPRINT-004, ~200–480 lines each)

## Important note on tracker hygiene

Use `tracker --workdir workdirs/<name>` for isolated runs. The model will
glob `**/*` and read everything it finds — leaving previous outputs or
the README in the workdir contaminates A/B tests. Cost and quality both
got distorted before we caught this.
