# Reasoning-Tier Study: how low can the spec→sprints upstream go?

**Question.** The `spec_to_sprints` pipeline runs frontier models (Opus/GPT/Gemini) for decomposition and a frontier architect. Each LLM node takes a unified `reasoning_effort` (low / medium / high). **How much reasoning does each upstream stage actually need before output quality degrades — and where does the cost go?**

**TL;DR recommendation.** Run **`analyze_spec` at `medium`** and the **decomposition tournament at `low`**. On NIFB this lands on the faithfulness frontier (8.0/10 by a judge panel) at **~$1.85** — *cheaper **and** more faithful* than the default all-`high` run ($2.78, 7.7/10). Higher reasoning buys essentially nothing in faithfulness here; the real quality lever is the `analyze_spec` **prompt**, not its reasoning level.

This directory contains the experiment definitions (`dips/`), the evaluation harness (`harness/`), and the artifacts that back every number below (`results/`).

---

## Method

Two ideas made this measurable where the monolithic pipeline did not:

1. **Stage decomposition (microservice dips).** `spec_to_sprints.dip` was split at its natural `.ai/` artifact seams so each stage runs and is judged in isolation:
   - `dips/stage_01_ingest.dip` — `find_spec` + `analyze_spec` → `.ai/spec_analysis.md`
   - `dips/stage_02_tournament.dip` — decompose ×3 + cross-critique ×6 + merge → `.ai/sprint_plan.md`
   - `dips/stage_03_plan_gate.dip` — human plan review (present + approve/feedback)

   Stages hand off through the `.ai/` workspace (one stage `writes:` a file, the next `reads:` it). The monolith yields one expensive, confounded sample per run; isolated stages make N samples cheap and let you attribute a defect to a specific stage.

2. **Stop before the architect.** The artifact the architect consumes is `.ai/sprint_plan.md`. The `dips/upto_architect_*.dip` variants run the whole upstream and **stop at `sprint_plan.md`** (`merge_decomposition -> Exit`). This (a) isolates the reasoning-sensitive upstream, (b) avoids the expensive per-sprint dispatch fan-out, and (c) sidesteps a tool-registration hazard (see *Gotchas*).

   | dip | analyze_spec | tournament |
   |---|---|---|
   | `upto_architect_high.dip`   | high   | high |
   | `upto_architect_medium.dip` | medium | medium |
   | `upto_architect_low.dip`    | low    | low |
   | `upto_architect_hybrid.dip` | high   | low |
   | `upto_architect_medlow.dip` | **medium** | **low** ← recommended |

3. **Faithfulness judged by a panel, against the spec as ground truth.** A single LLM judge proved unreliable here (±4-point swings; it even anchored on one plan's FR count and mislabeled real requirements as "phantom"). The reliable instrument is `harness/faithfulness_panel.workflow.js`: **3 independent lenses** — *completeness* (real requirements missing?), *scope-discipline* (items that don't trace to the spec / action-items miscast as features?), and *holistic* — each reads the **source spec** and scores the plan 0–10. Scores are averaged across lenses to cancel single-judge noise.

All runs are on the **NIFB** spec (a messy meeting transcript + emails — a hard, implicit spec). Each `upto_*` run needs only `TRACKER_NOTES_WRITER_MODEL` set (the decompose/merge offload tool); it deliberately does **not** set the dispatch env vars.

---

## Findings

### 1. The decomposition tournament is reasoning-insensitive — run it `low`
Across every config, the `sprint_plan` FR count is **identical** to the `spec_analysis` FR count:

| config | analyze_spec FRs | → sprint_plan FRs |
|---|---|---|
| high   | 22 | 22 |
| hybrid | 27 | 27 |
| medlow | 19 | 19 |
| low    | 34 | 34 |

The tournament **never adds or drops a requirement** — it decomposes exactly the set `analyze_spec` emits. Lowering it is free quality-wise, and it's where most of the cost reduction comes from. (This replicates the earlier production finding that a low-reasoning tournament was cheaper, ~2× faster, and avoided the high-reasoning output-cap truncation that *dropped* requirements.)

### 2. More FRs is **not** worse — faithfulness is driven by error *type*, not count
The judge panel found **no correlation between FR count and faithfulness**:

| config | FR count | panel faithfulness | invented flags | missed flags |
|---|---|---|---|---|
| medium | ~15 | **8.0** | 6 | 14 |
| hybrid | ~27 | **8.0** | 9 | 14 |
| **medlow** | **~19** | **8.0** | — | — |
| high   | 22 | 7.7 | 10 | 14 |
| low    | 34 | 7.7 | 7 | 17 |

The configs at *opposite* ends of the count spectrum (medium ~15, hybrid ~27) tied at the top. A higher FR count is fine as long as each FR traces to a real requirement (finer-grained decomposition is legitimate). The failure modes are about *kind* of error:
- **`high` over-specifies** — invents acceptance criteria not in the spec (Lighthouse ≥90, "<2s page load" SLAs, an audit trail, a concrete tech stack). 10 invented flags — the most.
- **`low` under-specifies** — flattens the spec's "entirely conversational concierge" experience into a static quiz; stubs login. 17 missed — the most.
- **`medium`/`medlow`/`hybrid`** make fewer of either.

### 3. All reasoning configs are roughly equally faithful (7.7–8.0/10)
A 0.3-point spread across the board. Earlier single-judge comparisons that showed an 8-point high-vs-low chasm were **judge noise** — averaging lenses collapses it. High reasoning is not meaningfully more faithful than medium or low on this spec.

### 4. The real quality gap is reasoning-independent — it's a prompt problem
**Every** config — high through low — independently missed the same requirements: **login modernization** (Google/Apple SSO, phone-code OTP, biometric/badge sign-in) and the spec's marquee **in-flow donor recognition** ("by the fourth question… *Colleen, you've been such an important donor*"). No reasoning level fixes this. The highest-leverage improvement is sharpening the `analyze_spec` **prompt** to explicitly hunt for these categories — not turning a reasoning knob.

### 5. Cost is flat and non-monotonic (~$1.8–$2.9)
Because the decompose/merge nodes offload their verbose write-up to a cheap writer (`expand_from_notes`), expensive *output* tokens stay low at every tier. So reasoning level barely moves dollar cost, and the ordering isn't even monotonic (all-`medium` was the most expensive run at $2.86). Low-reasoning runs spend *more input* tokens (more tool round-trips) but fewer expensive output tokens.

---

## Recommendation

**`analyze_spec: medium` + tournament `: low`** (`dips/upto_architect_medlow.dip`). Faithfulness frontier (8.0/10) at ~$1.85 — beats the default all-`high` on both cost and faithfulness. Run the tournament `low` unconditionally; it's reasoning-insensitive.

**Next improvement is not a reasoning knob** — it's an `analyze_spec` prompt that stops missing login-modernization and the live donor-recognition moment.

### Caveats (read before trusting any single number)
- **n = 1 generation per config.** The panel removes *judge* noise (3 lenses) but not *generation* noise. `analyze_spec` is itself variance-prone — `medium` produced 19 FRs in one run and 35 in another. The **replicated, trustworthy** conclusions are the structural ones: tournament-insensitivity (#1), count≠faithfulness (#2), and the universal blind spots (#4). Exact per-config scores and the cost ordering would firm up with 3–5 generations each.
- Findings are on one hard spec (NIFB). A clean, pre-structured `spec.md` may behave differently (low extraction was complete on a well-structured spec elsewhere).

---

## Cross-module integration tests (this flow's correctness mechanism)

This pipeline targets **local** code generation, where the per-sprint writer (qwen) makes no architectural decisions — so cross-sprint contract violations (a duplicated enum, a renamed field, a drifted signature) must be caught *mechanically*, not by reasoning. The architect enforces this in `contract.md` **§7 — Cross-Sprint Dependency Edges + Required Cross-Module Tests**:

> For every directed edge `Sprint N → Sprint M` (N consumes a symbol from M), the contract declares **(a)** the symbols consumed and **(b)** one named **cross-module test** that Sprint N MUST include — a test that obtains a *real* upstream value through Sprint M's public API and feeds it to Sprint N's public API (no mocks, no hand-rebuilt fixtures), plus a 3–6 line body sketch and a one-line "what it catches."

Why it's load-bearing: a sprint's own unit tests can be internally self-consistent even while it silently violates a cross-sprint contract — the break only surfaces when *another* module composes against the broken API. The required cross-module test forces that composition into the dependent sprint's own suite at compile/parse time, so the violation fails **before** the sprint can freeze, while the root cause is still editable. The mandate applies to every project regardless of stack; the local writer has zero discretion to skip, rename, or weaken it. (See the `write_sprint_docs` architect prompt in `local_code_gen/spec_to_sprints.dip`.)

---

## Reproduce

```fish
# only env var needed (offload writer); NO dispatch vars → no architect, no tool-bleed
set -gx TRACKER_NOTES_WRITER_MODEL claude-sonnet-4-6

# run any config up to sprint_plan.md (put a spec.md / transcript in $W first)
mkdir -p $W; cd $W
tracker --no-tui --auto-approve -w . path/to/dips/upto_architect_medlow.dip
# → produces .ai/spec_analysis.md and .ai/sprint_plan.md

# score faithfulness with the judge panel (edit the spec/plan paths at the top of the script)
# harness/faithfulness_panel.workflow.js  — run via the Workflow tool (4 configs × 3 lenses)
# harness/nifb_compare.py / sprintplan_judge.py — lighter single/3-way spec-grounded judges
```

### Gotchas discovered (orthogonal to reasoning level)
- **`--auto-approve` can't drive the plan-gate's human-feedback loop** — tracker auto-selects the first labeled edge ("[A] Revise"), looping `apply_feedback → approval_gate` to the restart cap. Run the gate interactively, or collapse it to a single approve edge for headless runs.
- **Dispatch tools register globally.** Setting `TRACKER_SPRINT_WRITER_MODEL` registers `dispatch_sprints` for *every* agent. In a full all-low run, a low-reasoning tournament node grabbed it mid-decomposition and short-circuited the architect. Scope it per-node (tracker supports `disallowed_tools`) or — better — keep dispatch in its own stage so tournament nodes can't reach it. The `upto_*` runs avoid this entirely by not setting the dispatch vars.
