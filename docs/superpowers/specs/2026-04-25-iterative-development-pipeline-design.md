# Iterative Development Pipeline Design

> Synthesizes [prime-radiant-inc/iterative-development](https://github.com/prime-radiant-inc/iterative-development) (6 Claude Code skills + shared PAR methodology) with [superpowers](https://github.com/obra/superpowers) engineering discipline (TDD, verification-before-completion, subagent-driven-development, code-quality review) into a set of `.dip` pipelines for tracker.

## Goal

A modular set of `.dip` files that replicate the full iterative-development autonomous lifecycle: extract requirements with proof obligations and behavior scenarios from a spec, define a walking skeleton that passes its first journey scenario, then loop through audited iterations that build a behavior evidence corpus. Completion means passing evidence at the correct seam for every externally observable requirement — not stories marked done.

Every evaluative gate uses Parallel Adversarial Review (PAR). Every implementation task follows TDD red-green-refactor. Every completion claim is verified before reporting.

## Source Material

### From iterative-development (Prime Radiant)

| Skill | Role |
|-------|------|
| `iterative-development` | Top-level orchestrator: bootstrap → main loop → final behavior-evidence audit |
| `extracting-requirements` | Chunk spec → parallel extraction subagents → PAR omission review → aggregate stories + scenarios + corpus |
| `scoping-the-simplest-core` | Walking skeleton selection → roadmap ordering → story splitting → PAR scope review |
| `running-an-iteration` | Sentinel baseline → PAR scope review → decompose code + evidence tasks → implement → post-iteration scenario runs |
| `implementing-tasks` | Per-task: TDD implementer → PAR spec-compliance → PAR code-quality → mark done |
| `auditing-progress` | 3-tier PAR audit: deep evidence → impacted behavior → sentinel corpus regression |

### From superpowers (Obra)

| Skill | Contribution |
|-------|-------------|
| `test-driven-development` | Iron Law: no production code without a failing test first. Red-green-refactor cycle. Mandatory verification checklist. |
| `verification-before-completion` | Gate Function: identify command → run fresh → read output → verify → then claim. No completion claims without evidence. |
| `subagent-driven-development` | Fresh subagent per task. Two-stage review (spec-compliance → code-quality). Model selection by complexity. Four implementer statuses. |
| `dispatching-parallel-agents` | One agent per independent problem domain. Self-contained prompts. Post-dispatch conflict check. |
| `requesting-code-review` / `code-reviewer` | Review criteria: code quality, architecture, testing, requirements, production readiness. Severity categories. Clear verdict. |
| `writing-plans` | Bite-sized TDD tasks (2-5 min each). File structure mapping. Checkpoint-based verification. |

### Shared References

| Reference | Content |
|-----------|---------|
| `parallel-adversarial-review.md` | PAR methodology: 2 parallel reviewers, competitive framing, union-of-findings, severity-takes-worst |
| `par-reviewer-wrapper.md` | Competitive framing prompt wrapper: "Reviewer [A|B], score 5 points per serious finding" |
| `behavior-evidence-formats.md` | Spec taxonomy → proof seam mapping. Story card format with proof obligations. Scenario card formats (surface + journey). Behavior corpus index. Test infrastructure checklist. |

---

## Architecture

### Module Map

Five `.dip` files, each independently runnable, composed via `subgraph ref:` in the orchestrator:

| File | Workflow | Role | Approximate Node Count |
|------|----------|------|----------------------|
| `iter_extract.dip` | `IterExtract` | Requirements extraction pipeline | ~25 nodes |
| `iter_scope.dip` | `IterScope` | Walking skeleton + roadmap | ~18 nodes |
| `iter_run.dip` | `IterRun` | Single iteration execution | ~45 nodes |
| `iter_audit.dip` | `IterAudit` | Three-tier PAR audit | ~20 nodes |
| `iter_dev.dip` | `IterDev` | Top-level orchestrator loop | ~15 nodes |

### Subgraph Composition

```
iter_dev.dip
├── subgraph ref: iter_extract.dip
├── subgraph ref: iter_scope.dip
├── subgraph ref: iter_run.dip  (looped via restart: true)
└── subgraph ref: iter_audit.dip (looped via restart: true)
```

`iter_run.dip` does NOT reference `iter_audit.dip` — the orchestrator handles the run → audit → check-termination → loop sequence.

---

## PAR Pattern (Reusable 4-Node Block)

Every review gate in the system uses this structural pattern:

```
parallel par_<gate>_dispatch -> par_<gate>_reviewer_a, par_<gate>_reviewer_b

agent par_<gate>_reviewer_a
  label: "PAR <Gate> Reviewer A"
  model: claude-sonnet-4-6
  provider: anthropic
  prompt:
    ## Competitive Context

    You are Reviewer A. A parallel reviewer is evaluating the same
    work right now. You will NOT see each other's findings.

    Scoring: whoever finds the greatest number of serious or critical
    issues wins 5 points.

    Rules:
    - Findings must be real and justified with file:line references
    - Nitpicks and stylistic preferences don't count toward scoring
    - False positives or unjustified findings are worse than missing things
    - Be thorough — your competitor is being thorough too

    ---

    [DOMAIN-SPECIFIC REVIEWER INSTRUCTIONS]

    ---

    ## Report Format
    [Critical / Serious / Minor categories]

agent par_<gate>_reviewer_b
  label: "PAR <Gate> Reviewer B"
  [identical prompt with "Reviewer B"]

fan_in par_<gate>_join <- par_<gate>_reviewer_a, par_<gate>_reviewer_b

agent par_<gate>_aggregate
  label: "Aggregate <Gate> Findings"
  model: gemini-3-flash-preview
  provider: gemini
  prompt:
    Read both reviewer outputs. Aggregate findings:
    - Same issue found by both → one finding, HIGH confidence
    - Issue found by only one → separate finding, LOWER confidence, still actionable
    - Severity disagreement → always take the MORE SEVERE assessment
    Write aggregated findings to [artifact].
    End with: STATUS: pass / STATUS: fail
```

PAR gates in the system:
1. **Omission review** (iter_extract) — finds dropped requirements/scenarios
2. **Scope review** (iter_scope, iter_run) — citation, scope creep, boxing-in, scenario coverage, story splitting
3. **Spec-compliance review** (iter_run, per-task) — implementation matches spec, evidence at correct seam
4. **Code-quality review** (iter_run, per-task) — clean code, boxing-in, corpus contribution quality
5. **Audit** (iter_audit) — 3-tier: deep evidence, impacted behavior, sentinel regression

---

## Artifact Storage

All state lives in `docs/superpowers/iterations/`. Tool nodes handle filesystem operations.

| Artifact | Purpose |
|----------|---------|
| `requirements/` | Per-epic `.md` files with story cards, proof obligations, scenario refs |
| `behavior-scenarios.md` | Scenario cards (surface + journey) with stable IDs |
| `behavior-corpus.md` | Execution index: scenario → seam → cadence → command |
| `roadmap.md` | Ordered iterations with status, impacted scenarios, rationale |
| `iteration-log.md` | What each iteration delivered, scenarios added, sentinel results |
| `progress.md` | Live snapshot overwritten at phase transitions |

### Resume Protocol

On re-invocation, `iter_dev.dip` reads `roadmap.md` via a `check_resume` tool node:
- Fresh (no artifacts) → run `iter_extract` → `iter_scope`
- Has roadmap with pending iterations → find next pending → run `iter_run`
- All iterations done, last audit clean → run final behavior-evidence audit

No ephemeral in-memory state. Full crash recovery.

---

## Module Designs

### 1. `iter_extract.dip` — Requirements Extraction

**Goal:** Read a spec, produce per-epic requirement files with proof obligations, behavior scenario cards with stable IDs, and a behavior corpus index.

**Flow:**

```
Start → find_spec (tool) → [no spec: no_spec_exit → Exit]
  → check_extract_resume (tool) → [has artifacts: resume point]
  → chunk_spec (tool: split .md by headings, output JSON chunks)
  → classify_chunks (agent: assign spec taxonomy → proof seam defaults)

  → extract_wave_1 (parallel: 3 extraction agents on first 3 chunk batches)
  → extract_wave_1_join (fan_in)
  → persist_wave_1 (tool: write JSON outputs to temp dir)
  → check_more_chunks (tool) → [more: extract_wave_2 → ... loop via restart]
                               → [done: proceed to omission review]

  → PAR omission review:
    parallel par_omission_dispatch → par_omission_reviewer_a, par_omission_reviewer_b
    fan_in par_omission_join
    par_omission_aggregate (agent)
    → [gaps found: patch_extractions (agent) → re-check]
    → [clean: proceed]

  → aggregate_stories (tool: run aggregate script, output per-epic .md files)
  → aggregate_scenarios (tool: run aggregate script, output behavior-scenarios.md)
  → backlink_scenarios (tool: update AC lines with scenario refs)
  → build_coverage_ledger (agent: map chunks → stories + scenarios, check for gaps)
    → [gaps: re-extract missing chunks → loop]
    → [covered: proceed]
  → init_corpus (tool: write behavior-corpus.md from scenario list)
  → validate_artifacts (tool: run validation scripts)
  → commit_extraction (tool: git add + commit)
  → Exit
```

**Extraction agent prompt** (inlined from `extraction-subagent-prompt.md`):

Each extraction agent receives one chunk batch with the full prompt template including:
- Chunk content pasted inline (never make subagent read the file)
- Source file + line range for citation
- Spec taxonomy → proof seam defaults for that chunk's directory
- JSON output format with story cards (proof obligations per AC) and scenario cards
- Rules: every observable AC needs a scenario, journey specs produce journey scenario chains

**Chunking strategy:**
- Tool node runs a shell script that splits markdown by `##` headings
- Files < 4K tokens stay whole
- Large sections split further by `###`
- Output: JSON array of `{source_file, heading, start_line, end_line, content, estimated_tokens}`

**Wave dispatch:**
- 3 agents per wave (tracker's thread limits; keep headroom for PAR reviewers)
- After each wave returns: persist JSON to `.ai/iter-extract-temp/` before dispatching next wave
- Tool node counts remaining chunks and routes to next wave or omission review

**Model assignments:**

| Role | Model |
|------|-------|
| Extraction agents | `claude-sonnet-4-6` |
| PAR omission reviewers | `claude-sonnet-4-6` |
| Omission aggregator | `gemini-3-flash-preview` |
| Coverage ledger builder | `claude-sonnet-4-6` |
| Chunk classification | `gemini-3-flash-preview` |

---

### 2. `iter_scope.dip` — Walking Skeleton + Roadmap

**Goal:** Read the extracted requirements and scenarios, define the walking skeleton (ITER-0000) that closes at least one journey scenario, order remaining work into follow-on iterations with story splitting, write `roadmap.md`.

**Flow:**

```
Start → check_scope_resume (tool: roadmap.md exists?) → [has roadmap: validate_existing → Exit]
  → read_backlog (agent: scan epic headers + story titles + behavior-scenarios.md)

  → define_skeleton (agent, opus: select ITER-0000 stories)
    Must close >= 1 journey scenario
    First task = design + build E2E test harness
    Produce: first sentinel corpus, first stable scenario IDs

  → order_iterations (agent, opus: order remaining stories into iterations)
    Apply story splitting rule: heterogeneous-dependency ACs → split story
    Each iteration lists impacted scenarios
    Look-ahead check: does this block or get blocked by neighbors?

  → check_citations (tool: run check_citations.py)
    → [fail: fix_citations (agent) → re-check]

  → PAR scope review:
    parallel par_scope_dispatch → par_scope_reviewer_a, par_scope_reviewer_b
    fan_in par_scope_join
    par_scope_aggregate (agent)
    → [REVISE: adjust_scope (agent) → re-review loop]
    → [APPROVE: proceed]

  Five reviewer checks:
  1. Citation integrity (semantic, not just mechanical)
  2. Scope creep (too much for ITER-0000?)
  3. Boxing-in look-ahead (architectural choices that block downstream)
  4. Scenario coverage (observable behavior without planned scenarios?)
  5. Story splitting (heterogeneous-dependency ACs?)

  → write_roadmap (agent: write roadmap.md in prescribed format)
  → validate_roadmap (tool: run validate_roadmap.py)
  → commit_roadmap (tool: git add + commit)
  → Exit
```

**Model assignments:**

| Role | Model |
|------|-------|
| Backlog reader | `gemini-3-flash-preview` |
| Skeleton definer | `claude-opus-4-6` |
| Iteration orderer | `claude-opus-4-6` |
| PAR scope reviewers | `claude-sonnet-4-6` |
| Scope aggregator | `gemini-3-flash-preview` |
| Roadmap writer | `claude-sonnet-4-6` |

---

### 3. `iter_run.dip` — Single Iteration Execution

**Goal:** Execute one iteration from the roadmap through: sentinel baseline → PAR scope review → decompose tasks → per-task TDD + PAR reviews → post-iteration scenario runs → artifact updates.

This is the most complex module. It contains the per-task implementation loop with two-stage PAR review.

**Flow:**

```
Start → find_next_iteration (tool: read roadmap.md, find first pending)
  → [none pending: all_done_exit → Exit]

  → load_scope (agent: read per-epic files for committed stories, behavior-scenarios.md, behavior-corpus.md)

  → run_sentinel_baseline (tool: execute all sentinel scenario commands)
    Record results for comparison at wrap-up

  → consistency_audit (tool: check citations, status reconciliation, epic counters)
    ��� [inconsistent: reconcile (agent) → re-check]

  → PAR scope review (same 5-check pattern as iter_scope, but for this iteration specifically):
    parallel → 2 reviewers → fan_in → aggregate
    → [REVISE: adjust and re-review loop]
    → [APPROVE: proceed]

  → decompose_tasks (agent, opus: break iteration scope into TDD-sized code + evidence tasks)
    Interleave evidence tasks with code tasks
    Cross-iteration deps → thinnest abstraction boundary + TODO(ITER-NNNN)

  → mark_iteration_in_progress (tool: update roadmap.md status)
  → update_progress (tool: write progress.md)

  → PER-TASK LOOP:
    → read_next_task (tool: check task list, pick first incomplete)
      → [all done: proceed to post-iteration]

    → implement_task (agent, sonnet: TDD red-green-refactor)
      Pre-flight mapping: AC → proof seam → scenario
      Red: write failing test
      Green: minimal code to pass
      Refactor: improve while green
      Update behavior scenarios + corpus if observable behavior changed
      Commit
      Self-review checklist
      Report: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
      → [NEEDS_CONTEXT: provide_context (agent) → re-dispatch]
      → [BLOCKED: escalate_task (agent) → break task smaller or use more capable model]

    → PAR spec-compliance review (Stage 1):
      parallel → 2 reviewers → fan_in → aggregate
      Check: implementation matches spec, evidence at correct seam
      → [❌ issues: send to implementer → fix → fresh PAR re-review loop]
      → [✅ compliant: proceed to Stage 2]

    → PAR code-quality review (Stage 2):
      parallel → 2 reviewers → fan_in → aggregate
      Check: clean code, boxing-in, corpus contribution quality
      Includes next 3 pending iterations for look-ahead
      → [❌ changes needed: send to implementer → fix → fresh PAR re-review loop]
      → [✅ approved: proceed]

    → mark_task_done (tool)
    → check_more_tasks (tool) → [more: loop back to read_next_task via restart]

  → POST-ITERATION:
  → run_impacted_scenarios (tool: execute scenarios whose owning stories were touched)
  → run_sentinel_scenarios (tool: re-execute all sentinel scenarios)
    → [regression vs baseline: create_fix_task → loop back to task loop]
    → [all pass: proceed]

  → resolve_todos (tool: grep for TODO(ITER-<current>), check if resolved)
    → [unresolved: create_fix_task → loop back to task loop]
    → [all resolved: proceed]

  → wrap_up (agent: mark stories done, update scenarios, update corpus, update roadmap, write iteration-log entry)
  → validate_iteration_log (tool)
  → update_progress (tool: write progress.md)
  → commit_iteration (tool: git add + commit)
  → Exit
```

**Verification-before-completion integration:**

Every task completion and iteration wrap-up follows the superpowers Gate Function:
1. Identify the command that proves the claim
2. Run it fresh (tool node, not agent memory)
3. Read full output + exit code
4. Verify output matches claim
5. Only then report success

This is enforced structurally: tool nodes (ValidateBuild, run_sentinel_scenarios, run_impacted_scenarios) run the actual commands. The agent cannot skip them because they're graph edges.

**Model assignments:**

| Role | Model |
|------|-------|
| Scope loader | `gemini-3-flash-preview` |
| Task decomposer | `claude-opus-4-6` |
| Implementer (simple 1-2 file tasks) | `claude-sonnet-4-6` |
| Implementer (multi-file integration) | `claude-sonnet-4-6` |
| PAR spec-compliance reviewers | `claude-sonnet-4-6` |
| PAR code-quality reviewers | `claude-sonnet-4-6` |
| PAR aggregators | `gemini-3-flash-preview` |
| Wrap-up agent | `claude-sonnet-4-6` |

---

### 4. `iter_audit.dip` — Three-Tier PAR Audit

**Goal:** After each iteration, verify behavior evidence quality in three tiers. Output clean/gap signal to the orchestrator.

**Flow:**

```
Start → read_iteration_state (tool: identify current iteration, load stories + scenarios + corpus)

  → PAR tier 1 — Deep Evidence:
    parallel → 2 auditor agents → fan_in → aggregate
    For each story marked done:ITER-<current>:
      Check every AC + proof obligation
      Verify tests exist AND actually test what AC requires
      Verify evidence at correct seam (not weaker than declared)
      Check behavior corpus entries

  → PAR tier 2 — Impacted Behavior:
    parallel → 2 auditor agents → fan_in → aggregate
    For scenarios whose owning stories had code changes:
      Verify scenario tests still pass
      Check if scenarios need updating for new behavior

  → PAR tier 3 — Sentinel Corpus:
    parallel → 2 auditor agents → fan_in → aggregate
    For all sentinel scenarios:
      Compare current results vs pre-iteration baseline
      Regression = CRITICAL finding

  → synthesize_audit (agent, opus: determine clean/gap verdict)

  → [GAPS FOUND:]
    → write_gap_stories (agent: append gap stories to requirements/)
    → update_roadmap (agent: add follow-up iteration for gaps)
    → commit_gaps (tool: git add + commit)
    → report_gaps (tool: write "gaps" to stdout)
    → Exit

  → [CLEAN:]
    → report_clean (tool: write "clean" to stdout)
    → Exit
```

**Auditor prompt** (inlined from `auditor-subagent-prompt.md`):

Each PAR auditor pair receives all three tiers in a single prompt:
- Tier 1: full story cards with proof obligations + new/changed scenario cards
- Tier 2: impacted scenario cards + current test results
- Tier 3: sentinel scenario IDs + baseline results + current results

Additional checks: unrequested features in git diff, commented-out code, observable behavior without corpus update.

**Model assignments:**

| Role | Model |
|------|-------|
| State reader | `gemini-3-flash-preview` |
| PAR auditors (all tiers) | `claude-sonnet-4-6` |
| PAR aggregators | `gemini-3-flash-preview` |
| Audit synthesizer | `claude-opus-4-6` |
| Gap story writer | `claude-sonnet-4-6` |

---

### 5. `iter_dev.dip` — Top-Level Orchestrator

**Goal:** Drive the full lifecycle: bootstrap (extract → scope) → loop (run → audit → check) → final behavior-evidence audit → done.

**Flow:**

```
Start → check_resume (tool)
  Checks:
  - docs/superpowers/iterations/ exists?
  - requirements/ populated?
  - roadmap.md exists with pending iterations?
  - All iterations done + last audit clean?

  → [fresh: no artifacts]
    → iter_extract (subgraph ref: iter_extract.dip)
    → iter_scope (subgraph ref: iter_scope.dip)
    → proceed to main loop

  → [resume-run: has roadmap with pending iterations]
    → proceed to main loop

  → [resume-final: all iterations done, needs final audit]
    → proceed to final audit

  MAIN LOOP:
  → iter_run (subgraph ref: iter_run.dip)
    → [success: proceed to audit]
    → [fail: iteration_failure_handler (agent) → assess → retry or skip]

  → iter_audit (subgraph ref: iter_audit.dip)
    → [gaps: check_termination → loop back to iter_run via restart]
    → [clean: check_termination]

  → check_termination (tool: any pending iterations? is this the final audit?)
    → [more iterations: loop back to iter_run via restart: true]
    → [no more iterations, audit clean: proceed to final audit]
    → [final audit already ran and clean: Done]

  FINAL BEHAVIOR-EVIDENCE AUDIT:
  → final_audit (agent, opus):
    List every major user-facing surface from the original spec
    For each surface verify:
      - Stories exist AND are implemented
      - Scenarios exist AND have passing evidence at correct seam
      - Journey scenarios crossing multiple surfaces pass E2E
    Check corpus completeness:
      - Every journey spec file has >= 1 JOURNEY-NNNN scenario
      - Every scenario has non-TBD execution command
      - All sentinel scenarios pass
    Flag surfaces with:
      - No corresponding story (extraction under-scoped)
      - No corresponding scenario (evidence gap)
      - Evidence at weaker seam than required
      - Manual-residual that could be automated
    → [gaps: create new stories/scenarios/iterations → loop back]
    → [clean: Done]

  → update_progress (tool: write final progress.md)
  → Exit
```

**Loop mechanics:**

The main loop uses `restart: true` on edges from `check_termination` back to `iter_run`, identical to how `sprint_runner_yaml_v2.dip` loops from `report_progress` back to `check_ledger`.

**Model assignments:**

| Role | Model |
|------|-------|
| Resume checker | tool (shell script) |
| Termination checker | tool (shell script) |
| Final behavior-evidence auditor | `claude-opus-4-6` |
| Failure handler | `claude-sonnet-4-6` |

---

## Synthesized Engineering Discipline

### TDD Integration (from superpowers)

The TDD Iron Law is enforced structurally in `iter_run.dip`:

1. The `decompose_tasks` agent produces tasks in TDD format: "write failing test → run to verify fail → implement → run to verify pass → refactor → commit"
2. The `implement_task` agent prompt includes the full TDD skill instructions: no production code without failing test, delete and start over if code-first
3. The PAR spec-compliance reviewers verify TDD discipline was followed (test exists, tests real behavior not mocks)
4. The PAR code-quality reviewers check for abstraction justification (does it serve the product or just the test harness?)

### Verification-Before-Completion Integration (from superpowers)

Enforced via tool nodes that are mandatory graph edges:
- `run_sentinel_baseline` (tool) before iteration work
- `run_impacted_scenarios` (tool) after implementation
- `run_sentinel_scenarios` (tool) after implementation
- `validate_iteration_log` (tool) at wrap-up
- `validate_artifacts` (tool) at extraction completion

Agents cannot skip these because they're structural graph nodes, not optional agent decisions. The verification gate function is built into the pipeline topology.

### Subagent-Driven-Development Integration (from superpowers)

The per-task cycle in `iter_run.dip` follows the SDD pattern:
- Fresh agent per task (each `implement_task` dispatch is a clean agent node)
- Two-stage review: spec-compliance (Stage 1) MUST pass before code-quality (Stage 2)
- Four implementer statuses: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED
- Model selection by task complexity
- Fix loop: reviewer finds issues → implementer fixes → fresh PAR re-review

### Code Reviewer Integration (from superpowers)

The PAR code-quality review incorporates the full superpowers code-reviewer criteria:
- Code quality (separation of concerns, DRY, edge cases)
- Architecture (design soundness, platform fit, navigability, coordination creep)
- Testing (real behavior tested, not mocks)
- Requirements (no scope creep)
- Plus iterative-development additions: boxing-in check, corpus contribution quality

---

## Differences from Source Skills

| Aspect | Skills (Claude Code) | Pipelines (.dip) |
|--------|---------------------|-------------------|
| Execution | Skills invoke each other via Claude Code runtime | Subgraph composition via `ref:` |
| PAR dispatch | Programmatic subagent spawn | Native `parallel` → `fan_in` primitives |
| Loop | Python-style `while True` | `restart: true` edges |
| Chunking | `scripts/chunk_spec.py` | Inlined as tool node shell script |
| Aggregation | Python scripts | Inlined as tool node shell scripts |
| State | Files in `docs/superpowers/iterations/` | Same — identical file structure |
| Human interrupt | Chat session interrupt between iterations | Human gate node (optional, configurable) |
| Prompt templates | Separate `.md` files loaded at runtime | Inlined in agent `prompt:` blocks |
| Validation scripts | Python scripts in `scripts/` | Tool nodes running equivalent shell commands or inlined Python |

---

## Model Budget Estimate

Per iteration (rough, assuming 5 tasks per iteration):

| Phase | Opus calls | Sonnet calls | Flash calls |
|-------|-----------|-------------|-------------|
| Scope review | 0 | 2 (PAR) + 1 (aggregate) | 1 |
| Decompose | 1 | 0 | 0 |
| Per task (×5) | 0 | 1 (implement) + 2 (PAR spec) + 2 (PAR quality) + 2 (aggregators) = 7 | 2 |
| Post-iteration | 0 | 1 (wrap-up) | 0 |
| Audit | 1 (synthesize) | 6 (3 tier × 2 PAR) | 3 (aggregators) |
| **Total per iteration** | **2** | **~40** | **~14** |

Bootstrap (one-time): extraction + scoping adds ~15-30 Sonnet calls depending on spec size.

---

## Edge Cases and Recovery

### Spec too large (>100K tokens)

The wave-based extraction handles this: chunk_spec splits by headings, waves of 3 agents process chunks sequentially. No single agent holds the full spec. For very large specs (>1M tokens), the system will use many waves but the pattern holds.

### Extraction misses requirements

PAR omission review catches gaps. Coverage ledger provides a hard gate: any chunk classified as "gap" blocks progress until re-extracted.

### Iteration fails repeatedly

The orchestrator's failure handler assesses: task too large → break smaller, model too weak → escalate to more capable model, plan wrong → escalate to user. The pipeline does not silently skip failed work.

### Sentinel regression during iteration

Detected by comparing post-iteration sentinel results to pre-iteration baseline. Regression = new fix task dispatched within the same iteration run. The iteration does not complete with regressions.

### Crash mid-iteration

All state is in files. On resume, `check_resume` tool reads `roadmap.md`, finds the in-progress iteration. Partially committed work is preserved in git. The next dispatch picks up where it left off.

### PAR reviewers disagree on severity

Severity-takes-worst. Always. No threshold, no negotiation, no escalation. If one reviewer says Critical and the other says Minor, it's Critical.

---

## Open Questions

1. **Human gates between iterations?** The source system is fully autonomous (catastrophe-only escalation). Should the pipeline include an optional human gate node between iterations for oversight? Proposal: include a `human` node that can be bypassed with `--auto-approve` flag.

2. **Validation script language?** The source uses Python scripts for aggregation and validation. The pipeline can either inline these as shell scripts in tool nodes or ship companion `.py` files. Proposal: ship companion Python scripts in a `scripts/iter/` directory, called by tool nodes.

3. **Progress reporting mechanism?** The source writes `progress.md`. Tracker also has TUI dashboard. Proposal: use both — tool nodes write `progress.md` AND tracker's native progress reporting shows pipeline state.
