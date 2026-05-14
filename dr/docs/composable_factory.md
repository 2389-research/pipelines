# Composable Factory — Architecture

**Status:** Draft v1. Architecture / philosophy doc. Not a build plan. Not a schema reference.
**Authors:** Dyl-Dawg + Claude (conversation 2026-05-13/14)
**Last updated:** 2026-05-14

This doc captures *the pattern* underneath the dr/ pipelines, not the specific
software-dev-shaped instantiation we have today. The vocabulary here is meant to
be **domain-agnostic** — the same pattern can host a software factory, a
marketing factory, an editorial calendar factory, or any other "decompose-a-
goal-into-units, produce-each-unit, validate, recover" workflow.

---

## TL;DR

A factory is a graph of work. Every factory has four axes of swappable
behavior: how it **decomposes** a goal into units, how it **implements** each
unit, how it **validates** what was produced, and how it **recovers** from
failure. Each axis is a *contract*. Each contract has multiple *implementations*
(plugins). The orchestrator selects implementations based on the goal — at
plan time for the long-lived choices (decomposer; per-unit validators) and
at run time for the moment-of-failure choices (recovery).

Plugins are themselves dippin subgraphs and follow the same composition rules
as the artifacts they produce: small purposes, named units, reusable parts.
**The factory eats its own dog food.**

---

## Dippin's node taxonomy IS the composition substrate

We've been borrowing from atomic-design vocabulary (atom / molecule / organism /
template / page), but the actual substrate is dippin's node types. The mapping:

| Atomic-design level | dippin construct | Examples in dr/ today |
|---|---|---|
| **Atom** | a single node — `agent`, `tool`, `human`, `parallel`, `fan_in` | `tool EnsureLedger`, `agent ReadSprint`, `human approval_gate` |
| **Molecule** | a small subgraph (2-5 nodes) with one clear purpose | (none yet — would be e.g. a `consolidate_smells` subgraph) |
| **Organism** | a medium subgraph (5-15 nodes) implementing a cohesive process | `recover_sprint`, `write_and_validate_sprint_artifacts`, `implement_and_validate` |
| **Template** | a top-level workflow OR a contract describing what an organism category must look like | `spec_to_sprints`, `sprint_runner`, `sprint_exec` (workflow); future `validator-contract.md` (contract) |
| **Page** | a specific configuration of templates + organisms | `pipelines-eval/variants/01-baseline/`, future `02-orphan-detector/` |

**The vocabulary is a communication tool, not a directory mandate.** Don't
create empty directories for tiers that don't have inhabitants yet. Earn each
tier when it's needed.

---

## The four graph-type axes

Every factory has these four categories of swappable behavior. Each is a
*template* (contract) with potentially multiple *organism* implementations.

### Decomposer

> *Given a goal/spec, produce a plan of work units.*

- Input: a high-level goal artifact + any environmental context.
- Output: a structured plan (a list of work units with dependencies and metadata).
- Software dev example today: `spec_to_sprints.dip` — analyzes a spec, drafts sprints, reviews, writes per-sprint contracts.
- Hypothetical domains:
  - Marketing: `campaign-to-content-calendar.dip` — takes a quarterly marketing goal, produces a per-channel content calendar.
  - Editorial: `outline-to-chapter-plan.dip` — takes a book outline, produces a per-chapter plan.
- Future variants in software dev: `frontend-decomposer` (thinks in primitive/pattern/page layers), `library-decomposer` (pure-API projects), `data-pipeline-decomposer` (ETL shapes).

### Implementer

> *Given one work unit, produce its artifacts.*

- Input: the work unit's contract (scope, expected artifacts, validation criteria) + workspace state.
- Output: artifacts written to the workspace; status of the work.
- Software dev example today: `implement_and_validate.dip` — runs an LLM that writes code, validates, commits.
- Hypothetical domains:
  - Marketing: `post-implementer.dip` — drafts a piece of copy + creative for a specific channel.
  - Editorial: `chapter-implementer.dip` — drafts a chapter with the agreed structure.
- Future variants in software dev: `react-component-implementer` that knows design-system primitives, `sql-migration-implementer` that knows reversibility, `infra-as-code-implementer` for terraform.

### Validator

> *Given a workspace + work-unit context, emit smell tokens describing concerns.*

- Input: workspace + the just-completed unit's contract.
- Output: zero or more **smell tokens** of shape `<category>-<subject>` (see below).
- Software dev example today: the 3-reviewer Claude/Codex/Gemini fan-out inside `sprint_exec` (currently embedded; will become the `quality-review` plugin).
- Hypothetical domains:
  - Software dev future: `orphan-detector` emits `orphan-<component>` when a module has no non-test importers; `monolith-detector` emits `oversize-<file>` when LoC exceeds threshold.
  - Marketing: `brand-voice-checker` emits `off-brand-<post-id>`; `audience-fit-checker` emits `audience-mismatch-<post-id>`; `regulatory-checker` emits `regulatory-flag-<creative-id>`.
- **Validators are the most active layer** — multiple selected per unit; new ones added often.

### Recovery

> *Given a failed unit + diagnosis, decide what to do.*

- Input: the failed unit's status, the failure analysis, ledger state.
- Output: an action (retry, redecompose, rollback, escalate, abort) and any side-effect artifacts (e.g. a redecompose-request file).
- Software dev example today: `recover_sprint.dip` — MarkFailed, SnapshotForRecovery, RecoveryManager, EnforceRecoveryBoundary, FailureSummary.
- Hypothetical domains:
  - Marketing: when a post is rejected by a platform, decide: revise-and-resubmit vs. swap-to-different-channel vs. escalate-to-creative-director.
- Future variants in software dev: `rollback-and-retry`, `redecompose-this-only`, `escalate-immediately`, `split-into-bootstrap-and-feature`.

---

## Plugin lifecycle by level

Different composition levels have different lifecycles:

### Template-level (contracts) — stable, evolve rarely

A template defines what an organism in its category must do. Lives at
`dr/docs/contracts/<type>.md` (validator.md, decomposer.md, implementer.md,
recovery.md). Specifies entry/exit shape, expected outputs, smell-token format
where relevant. Written when the first organism of that type ships; refined
over time as more organisms reveal patterns.

### Organism-level (plugins) — actively selected

The actual swappable units. Each lives at `dr/parts/<axis>/<plugin-name>/`:

```
dr/parts/validators/orphan-detector/
  orphan-detector.dip          # the subgraph
  README.md                    # what it does, why, when to use it
  applies-when.md              # plaintext "use when..." description (Claude-skills style)
  fixture/                     # known-bad workspace
    .ai/...
    src/...
  test.sh                      # exercise the validator against the fixture
```

**Selection** happens at plan time. For validators specifically: the
`select_validators` step in the decomposer reads the registry + spec analysis +
sprint plan, and writes a `validators: [name1, name2, ...]` field into each
`SPRINT-NNN.yaml`. The selector is an LLM call that reads each plugin's
`applies-when.md` and decides what fits — same pattern as Claude skills.

For decomposers / implementers / recoveries: same mechanism, different
selection moment. (Implementers may be selected per-unit. Decomposers are
selected once at the start of a run. Recoveries are selected per-failure.)

### Molecule-level (shared dependencies) — imported, not selected

Small subgraphs reused across organisms. Examples: `consolidate_smells`,
`read_inventory`, `emit_smell_token`. Live at `dr/parts/_lib/molecules/` if
multiple organisms need them. **Earn the tier**: only factor up when 2+
organisms are duplicating logic.

### Atom-level (reusable node definitions) — imported, not selected

Individual node specifications: a standard `agent` block with a battle-tested
prompt, a standard `tool` block with a known-good shell command. Live at
`dr/parts/_lib/atoms/` when needed. Same earn-the-tier rule.

---

## Selection mechanism: Claude-skills style

Each plugin declares its applicability as **plaintext**, not structured tags:

```markdown
# applies-when.md (for orphan-detector)
Use this validator when:
- The work units produce code that has an entrypoint file (App.tsx, main.ts,
  index.ts, server.ts, cli.ts, etc.)
- AND the codebase has more than one component/module that should be
  reachable from the entrypoint
- AND the language has a deterministic import system (most static languages)

Do NOT use when:
- The unit produces pure library code with no single entrypoint
- The "code" is config files, infrastructure-as-code, or non-executable text
```

At selection time, the LLM in `select_validators` reads each plugin's
`applies-when.md` alongside the spec analysis and decides. Same mental model
as how Claude itself decides whether to invoke a skill: `description` +
`when_to_invoke` → the LLM picks.

We start plaintext for v1. If patterns emerge across many plugins (e.g., all
FE-relevant ones share "produces JSX" applicability), we add a structured
tag system later as a *cache* over the LLM-driven selection.

---

## Smell-token contract

The cross-cutting concern across all validators. The shape:

```
<category>-<subject>
```

Where:
- `<category>` is the smell name (verb-noun preferred: `orphan-component`,
  `oversize-file`, `back-edge`, `off-brand`).
- `<subject>` is what's flagged (a file path, a component name, a unit id,
  a pair of dep IDs for graph-level smells).

Examples we already use or will:
- `back-edge-020-030` (graph: sprint 020 ← 030)
- `missing-scope-SPRINT-005.md` (file: section absent)
- `orphan-NoteList.tsx` (component: zero non-test importers)
- `oversize-dashboard.js-719loc` (file: LoC exceeds threshold)
- `off-brand-twitter-launch-thread-2` (marketing: post fails brand-voice)

**Storage:** per-sprint-per-plugin under `.ai/smells/<sprint-id>/<plugin>.md`.
Each plugin writes its own slice; nothing else stomps on it.

**Consolidation:** a separate subgraph (`consolidate_smells.dip`, molecule-
level) reads the slices and produces a rolled-up view on demand. Used by
PlanManager (wants smells from all completed sprints), ImplementSprint (wants
this-sprint's smells + any cross-cutting flags), and RecoveryManager (wants
recent smells overlapping the failed unit's scope).

**Taxonomy registry:** `dr/docs/validation_error_taxonomy.md` is the master
list of every smell token in use, what it means, and the surgical fix recipe.
Each new validator contributes entries.

---

## Cross-cutting principles

### 1. Domain-agnostic vocabulary

The contracts above mention "work unit," "decomposer," "validator" — not
"sprint," "code," "tests." The current dr/ pipelines are a *software-dev
instantiation* of the pattern. Future instantiations would replace `sprint_*`
with domain-appropriate names. The architecture is stable; the vocabulary
broadens as new domains land.

What's domain-locked in dr/ today (not in the architecture):
- `validation.commands` assumes shell invocations
- `stack.lang/runner/test/lint/build` is software-dev metadata
- The current 3-reviewer rubric is coding-quality-flavored

These are properties of the *current implementations*, not the contracts.

### 2. Earn each composition tier

Don't pre-build directories for tiers that have no inhabitants. The
`dr/parts/_lib/molecules/` directory shouldn't exist until two organisms
share a molecule. The `dr/parts/decomposers/` directory shouldn't exist
until we have a *second* decomposer.

### 3. The factory eats its own dog food

Plugin organisms ARE components. They have a single purpose, named units,
clear interfaces, test fixtures. The orphan-detector validator we want to
build for *code* should — eventually — also run against `dr/parts/` and
flag if any of OUR subgraphs are dead. Same principles, two layers.

### 4. Plugins are first-class artifacts

Every organism plugin has a README explaining what it does, an
`applies-when.md` for the selector, a fixture demonstrating its trigger
case, and a test script exercising it. No plugin is just a `.dip` file
alone. Discoverability and trust-by-default require the full bundle.

---

## What this doc IS NOT

- **Not a build plan.** The order in which we build the substrate, the first
  organism plugin, the second one, etc., is a separate planning artifact.
- **Not a schema reference.** The plugin directory layout sketched above is
  illustrative; the actual schema is locked in `dr/docs/contracts/<type>.md`
  documents as each contract gets fleshed out.
- **Not a complete spec.** Several open questions called out below.

---

## Open questions

1. **Plugin contract uniformity across deterministic vs. LLM plugins.** Some
   plugins are purely deterministic (orphan-detector = count importers, no
   LLM). Some are LLM-driven (quality-review = the existing fan-out). Should
   the contract treat them uniformly (everything is a subgraph that emits
   smells) or distinguish "tool-organism" vs. "agent-organism"? Current
   lean: uniform — the implementation detail of whether it calls an LLM is
   hidden from the orchestrator.

2. **Helper / utility exception for orphan-detection.** A `*-helper.ts` that's
   only used in one place may legitimately have zero transitive importers
   from the entrypoint. How do we distinguish "orphan because broken wiring"
   from "orphan because intentionally standalone tool"? Probably the plugin
   itself decides via its prompt; or we accept some false positives in v1.

3. **Per-sprint vs. per-spec for non-validator plugins.** Validators are
   per-sprint (different sprints in the same project may need different
   validators). Decomposers are per-spec (one per run). Implementers
   *could* be per-sprint (different sprint shapes need different
   implementers). Recovery is per-failure. The granularity is different per
   axis; the registry / selector should support it.

4. **Selector caching.** The plaintext applies-when + LLM-driven selection is
   a real cost per sprint. We may want a small cache: once the selector has
   evaluated a plugin against a particular spec, remember the answer for the
   rest of the run.

---

## Map to current state (2026-05-14)

What we have, in this architecture's vocabulary:

| Axis | Implementation | Status |
|---|---|---|
| Decomposer | `spec_to_sprints.dip` | One implementation; hardened against scope-fence + back-edge issues. |
| Implementer | `implement_and_validate.dip` (subgraph), called from `sprint_exec.dip` | One implementation. |
| Validator | 3-reviewer fan-out (Claude/Codex/Gemini) inside `sprint_exec` | Hardcoded today; should become the `quality-review` organism plugin (default-required). |
| Recovery | `recover_sprint.dip` | One implementation. |
| Registry | Not implemented yet | Phase 1 of the validator-plugin build. |
| Selector | Not implemented yet | Phase 1 — new `select_validators` node in the decomposer. |
| Smell consolidator | Not implemented yet | Phase 1 — molecule-level subgraph. |
| First new organism plugin | Not implemented yet | Phase 2 — `orphan-detector` based on the V0 readout findings. |

## Where it goes from here

Once this doc is accepted, the build order is:

1. **Phase 1 (substrate)**: plugin contract spec at `dr/docs/contracts/validator.md`, registry layout, `select_validators` node, `SPRINT-NNN.yaml.validators` field, refactor existing fan-out into `quality-review` plugin. Smell consolidator molecule.
2. **Phase 2 (first new organism)**: `orphan-detector` plugin with README + applies-when + fixture + test.
3. **Phase 3 (eval)**: snapshot to `pipelines-eval/variants/02-orphan-detector/`, run 3 small specs, compare against `01-baseline`.

Future axes (decomposer variants, implementer variants, recovery variants)
follow the same pattern when they're worth building.
