# Greenfield Pipeline Surgical Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all critical, important, and minor findings from the 8-expert review panel — edge/retry conflicts, silent failure paths, shell bugs, missing sentinels, feedback loops, contract sanitization gaps, and prompt deficiencies.

**Architecture:** Surgical edits to the existing 5 .dip pipeline files. No new files created. Each task targets a specific finding or cluster of related findings in a single file. Tasks are ordered by severity (criticals first) then by file (to minimize context switches).

**Tech Stack:** DIP pipeline format (declarative workflow DSL), shell (bash in tool nodes), tracker CLI for validation.

**Scope exclusion:** Provider fallback system (CRIT 5-6 from the review) is a separate plan — it adds new agents and routing to all 4 subgraph files and will be implemented independently.

**Validation:** After each task, run `tracker validate <file>.dip` to verify structural correctness. After all tasks, run `tracker validate greenfield.dip` to verify the full pipeline including subgraph references.

---

## File Map

All changes are modifications to existing files:

| File | Tasks | What Changes |
|---|---|---|
| `greenfield_synthesis.dip` | 1, 2, 5, 8, 10, 14, 16 | Gate1 retry conflict, retry target, stale cleanup, Gate1b spec count, Gate1b gap reference, Synthesizer provenance, WriteL2L3Summary disk file |
| `greenfield_validation.dip` | 3, 4, 6, 7, 9, 11, 15 | Gate2 retry conflict, retry target, feedback loop, SanitizationToolCheck fallback, Gate2ToolCheck false-positive, contract sanitization, sanitization REMOVE rule |
| `greenfield.dip` | 12, 13, 17, 18, 19 | L1Failed sentinel, FinalReport prompt, CheckReviewOutput tool+edges, DiscoverTarget find bug, SetupWorkspace .gate2-retries |
| `greenfield_discovery.dip` | 20, 21, 22, 23 | CoverageCheck fan_in_failed path, CoverageCheck incomplete message, WriteL1Summary paths field, CommunityAnalyst project name |
| `greenfield_review.dip` | 24, 25 | L6 reviewer scope deduplication, L7 acceptance criteria fidelity validator |

---

### Task 1: Fix Gate1AgentReview retry_target vs explicit fail edge conflict

**Finding:** CRIT 1 — `Gate1AgentReview` has `auto_status: true`, `retry_target: DeepSpecsParallel`, AND explicit `ctx.outcome = fail -> Gate1Failed` edges. These are irreconcilable — one mechanism is dead code.

**Spec says:** Gate pattern is `auto_status` with `retry_target` for retries, `fallback_target` for terminal failure after exhaustion. The explicit fail edges conflict with this.

**Fix:** Remove the explicit `ctx.outcome = fail` and bare fallback edges from `Gate1AgentReview`. The `auto_status` + `retry_target` + `fallback_target` mechanism handles both retry and terminal failure. Keep only the `ctx.outcome = success` edge.

**Files:**
- Modify: `greenfield_synthesis.dip:419-421` (edges section)

- [ ] **Step 1: Remove conflicting edges**

In `greenfield_synthesis.dip`, replace the Gate1AgentReview edge block:

```
    Gate1AgentReview -> Gate1bCompleteness  when ctx.outcome = success  label: gate1_pass
    Gate1AgentReview -> Gate1Failed         when ctx.outcome = fail     label: gate1_fail
    Gate1AgentReview -> Gate1Failed
```

with:

```
    Gate1AgentReview -> Gate1bCompleteness  when ctx.outcome = success  label: gate1_pass
```

The `auto_status: true` + `retry_target: DeepSpecsParallel` handles failure retries. The `fallback_target: Gate1Failed` handles terminal failure after `max_retries: 3` exhaustion.

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_synthesis.dip`
Expected: validation passes (Gate1AgentReview now routes via auto_status on fail, explicit edge on success)

- [ ] **Step 3: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): remove Gate1AgentReview explicit fail edges conflicting with auto_status retry"
```

---

### Task 2: Fix Gate1AgentReview retry_target to target only DeepDiveAnalyzer

**Finding:** CRIT 11 — Spec says `retry_target: DeepDiveAnalyzer`, impl has `retry_target: DeepSpecsParallel` (re-runs all 4 L3 agents). This is wasteful and causes stale file accumulation.

**Fix:** Change `retry_target` to `DeepDiveAnalyzer` per spec. DeepDiveAnalyzer is the only L3 agent that reads `gate1-findings.md`, so it's the only one that benefits from a retry.

**Files:**
- Modify: `greenfield_synthesis.dip:287` (Gate1AgentReview agent definition)

- [ ] **Step 1: Change retry_target**

In `greenfield_synthesis.dip`, in the `Gate1AgentReview` agent definition, replace:

```
    retry_target: DeepSpecsParallel
```

with:

```
    retry_target: DeepDiveAnalyzer
```

- [ ] **Step 2: Add restart edge from DeepDiveAnalyzer back to Gate1ToolCheck**

The retry_target sends to DeepDiveAnalyzer, which needs to flow back to the gate check. Add an edge for the retry loop. In the edges section, add after the existing `DeepDiveAnalyzer -> DeepSpecsJoin` edge:

```
    DeepDiveAnalyzer -> Gate1ToolCheck  restart: true
```

Wait — this creates ambiguity: DeepDiveAnalyzer would have two outgoing edges (one to DeepSpecsJoin from normal parallel flow, one to Gate1ToolCheck from retry). In DIP, the `retry_target` mechanism handles this: when `auto_status` retries, it sends to the `retry_target` node and on completion routes back to the retrying agent. So we don't need an explicit restart edge — the auto_status mechanism manages the return path.

Actually, looking at how L6/L7 work (which the reviewers said are correctly aligned): `L6AgentVerdict` has `retry_target: RemediateL6` and there IS an explicit `RemediateL6 -> L6ToolCheck restart: true` edge. So the pattern is: `retry_target` names where to send on fail, and the restart edge brings it back to the tool check.

But with `retry_target: DeepDiveAnalyzer`, DeepDiveAnalyzer already has an edge `DeepDiveAnalyzer -> DeepSpecsJoin` from the parallel fan-in. A retry from Gate1AgentReview would need DeepDiveAnalyzer to route back to Gate1ToolCheck, not to DeepSpecsJoin. This creates a routing conflict.

The L6/L7 pattern works because RemediateL6 is a dedicated node that ONLY exists in the retry loop — it has no other purpose. Similarly, the Gate1b pattern works because JourneyContractRemediation is dedicated.

For Gate1, the spec's intent (retry_target: DeepDiveAnalyzer) means DeepDiveAnalyzer serves double duty: parallel L3 agent AND retry target. This is architecturally problematic in DIP because the node's outgoing edges would be ambiguous.

**Revised fix:** Keep `retry_target: DeepSpecsParallel` (current behavior) but acknowledge the spec deviation. The alternative would require a dedicated `Gate1Remediation` agent, which the spec doesn't define. The stale file accumulation issue (IMP finding) is addressed separately in Task 5.

Actually, re-reading the spec more carefully: line 356 says `retry_target: DeepDiveAnalyzer`. The spec envisioned DeepDiveAnalyzer as the retry target directly. But in DIP, a node that participates in a parallel fan-out can't also serve as a standalone retry target because its edges point to the fan-in join.

The cleanest solution that matches spec intent: create a dedicated `Gate1Remediation` agent that has the same prompt as DeepDiveAnalyzer (reads gate1-findings.md, rewrites module specs) but exists only in the retry loop, just like `JourneyContractRemediation` exists for Gate1b and `RemediateL6`/`RemediateL7` exist for L6/L7.

- [ ] **Step 1: Add Gate1Remediation agent**

In `greenfield_synthesis.dip`, add a new agent after `ContractExtractor` and before `Gate1ToolCheck`:

```
  agent Gate1Remediation
    label: "Gate 1 Remediation"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Gate 1 Remediation agent. Gate 1 found quality issues with the behavioral specs.

      Read workspace/raw/specs/gate1-findings.md for the specific issues found.

      Read L2 summary files for context:
      - workspace/raw/synthesis/module-map.md
      - workspace/raw/synthesis/features/
      - workspace/raw/synthesis/architecture/
      - workspace/raw/synthesis/api/
      - workspace/raw/synthesis/behavioral-summaries/

      Fix ONLY the issues identified in gate1-findings.md. Rewrite the affected spec files in workspace/raw/specs/modules/. Do NOT re-run full L3 analysis — make targeted fixes.

      Every claim needs provenance: <!-- cite: source=synthesis, ref=<path>, confidence=<level>, agent=gate1-remediation -->
```

- [ ] **Step 2: Change retry_target to Gate1Remediation**

Replace:

```
    retry_target: DeepSpecsParallel
```

with:

```
    retry_target: Gate1Remediation
```

- [ ] **Step 3: Add restart edge for Gate1Remediation**

In the edges section, add:

```
    Gate1Remediation -> Gate1ToolCheck  restart: true
```

- [ ] **Step 4: Validate**

Run: `tracker validate greenfield_synthesis.dip`
Expected: validation passes

- [ ] **Step 5: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): replace DeepSpecsParallel retry with dedicated Gate1Remediation agent"
```

---

### Task 3: Fix Gate2AgentReview retry_target vs explicit fail edge conflict

**Finding:** CRIT 2 — Same conflict as Gate1AgentReview but in `greenfield_validation.dip`.

**Fix:** Remove explicit fail edges, add dedicated Gate2Remediation agent (matching the pattern from Task 2).

**Files:**
- Modify: `greenfield_validation.dip:148-149, 265-267` (agent definition + edges)

- [ ] **Step 1: Add Gate2Remediation agent**

In `greenfield_validation.dip`, add a new agent after `AcceptanceCriteriaWriter` and before `Gate2ToolCheck`:

```
  agent Gate2Remediation
    label: "Gate 2 Remediation"
    model: gpt-5.4
    provider: openai
    reasoning_effort: high
    prompt:
      You are the Gate 2 Remediation agent. Gate 2 found quality issues with test vectors and acceptance criteria.

      Read workspace/raw/specs/gate2-findings.md for the specific issues found.
      Read the behavioral specs in workspace/raw/specs/modules/ and workspace/raw/specs/journeys/ for context.

      Fix ONLY the issues identified in gate2-findings.md. Rewrite affected files in workspace/raw/specs/test-vectors/ and workspace/raw/specs/validation/. Do NOT re-run full L4 generation — make targeted fixes.
```

- [ ] **Step 2: Change retry_target to Gate2Remediation**

In the `Gate2AgentReview` agent definition, replace:

```
    retry_target: ValidationParallel
```

with:

```
    retry_target: Gate2Remediation
```

- [ ] **Step 3: Remove conflicting edges**

Replace:

```
    Gate2AgentReview -> SanitizationParallel  when ctx.outcome = success  label: gate2_pass
    Gate2AgentReview -> Gate2Failed            when ctx.outcome = fail     label: gate2_fail
    Gate2AgentReview -> Gate2Failed
```

with:

```
    Gate2AgentReview -> SanitizationParallel  when ctx.outcome = success  label: gate2_pass
```

- [ ] **Step 4: Add restart edge for Gate2Remediation**

In the edges section, add:

```
    Gate2Remediation -> Gate2ToolCheck  restart: true
```

- [ ] **Step 5: Validate**

Run: `tracker validate greenfield_validation.dip`
Expected: validation passes

- [ ] **Step 6: Commit**

```bash
git add greenfield_validation.dip
git commit -m "fix(validation): replace ValidationParallel retry with dedicated Gate2Remediation agent"
```

---

### Task 4: Add Gate2 feedback loop — Gate2Remediation reads gate2-findings.md

**Finding:** CRIT 8 — On Gate2 retry, L4 agents don't read `gate2-findings.md`, so they repeat the same mistakes.

**Fix:** Already addressed by Task 3 — `Gate2Remediation` explicitly reads `gate2-findings.md`. This task ensures the `Gate2AgentReview` prompt is also clear about writing actionable findings.

**Files:**
- Modify: `greenfield_validation.dip:151-162` (Gate2AgentReview prompt)

- [ ] **Step 1: Enhance Gate2AgentReview prompt**

In the `Gate2AgentReview` agent prompt, replace:

```
      Write findings to workspace/raw/specs/gate2-findings.md.
```

with:

```
      Write findings to workspace/raw/specs/gate2-findings.md. For each finding, specify the file path, the issue, and what the fix should look like. This file is read by the remediation agent on retry — make findings actionable.
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_validation.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_validation.dip
git commit -m "fix(validation): make Gate2AgentReview findings actionable for remediation agent"
```

---

### Task 5: Add pre-cleanup before Gate1/Gate2 retry loops

**Finding:** IMP 2 — Stale output files accumulate across Gate1/Gate2 retries, inflating counts.

**Fix:** Gate1Remediation and Gate2Remediation should clean up stale files before rewriting. Add cleanup instructions to their prompts.

**Files:**
- Modify: `greenfield_synthesis.dip` (Gate1Remediation prompt, from Task 2)
- Modify: `greenfield_validation.dip` (Gate2Remediation prompt, from Task 3)

- [ ] **Step 1: Add cleanup to Gate1Remediation prompt**

In `greenfield_synthesis.dip`, in the `Gate1Remediation` agent prompt, add after "Read workspace/raw/specs/gate1-findings.md for the specific issues found.":

```
      Before rewriting any spec file, remove the old version first. If gate1-findings.md identifies modules that were renamed or merged, delete the orphaned files from workspace/raw/specs/modules/ to prevent stale file accumulation.
```

- [ ] **Step 2: Add cleanup to Gate2Remediation prompt**

In `greenfield_validation.dip`, in the `Gate2Remediation` agent prompt, add after "Read workspace/raw/specs/gate2-findings.md for the specific issues found.":

```
      Before rewriting any file, remove the old version first. Delete orphaned files from workspace/raw/specs/test-vectors/ and workspace/raw/specs/validation/ that gate2-findings.md identifies as needing replacement.
```

- [ ] **Step 3: Commit**

```bash
git add greenfield_synthesis.dip greenfield_validation.dip
git commit -m "fix(gates): add stale file cleanup to Gate1/Gate2 remediation agents"
```

---

### Task 6: Fix SanitizationToolCheck bare fallback to success

**Finding:** IMP 1 — `SanitizationToolCheck` bare fallback routes to `WriteL4L5Summary` (success path). Should fail-safe.

**Fix:** Change the bare fallback edge to route to `Gate2Failed`.

**Files:**
- Modify: `greenfield_validation.dip:275-277` (edges)

- [ ] **Step 1: Fix the bare fallback edge**

Replace:

```
    SanitizationToolCheck -> WriteL4L5Summary  when ctx.tool_stdout startswith sanitization-ok  label: sanitization_ok
    SanitizationToolCheck -> Gate2Failed       when ctx.tool_stdout startswith sanitization-incomplete  label: sanitization_failed
    SanitizationToolCheck -> WriteL4L5Summary
```

with:

```
    SanitizationToolCheck -> WriteL4L5Summary  when ctx.tool_stdout startswith sanitization-ok          label: sanitization_ok
    SanitizationToolCheck -> Gate2Failed       when ctx.tool_stdout startswith sanitization-incomplete  label: sanitization_failed
    SanitizationToolCheck -> Gate2Failed
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_validation.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_validation.dip
git commit -m "fix(validation): route SanitizationToolCheck bare fallback to Gate2Failed"
```

---

### Task 7: Fix Gate2ToolCheck false-positive on skeleton test files

**Finding:** CRIT 10 — Gate2ToolCheck counts files in `test-vectors/` including `test-specs/` subdirectory, which contains skeleton test files that look like code (they contain `function`, `def`, `class` patterns by design).

**Fix:** Exclude the `test-specs/` subdirectory from leakage checks. Skeleton test files are expected to contain code-like patterns.

**Files:**
- Modify: `greenfield_validation.dip:123-131` (Gate2ToolCheck command)

- [ ] **Step 1: Exclude test-specs from leakage checks**

In the `Gate2ToolCheck` tool command, replace all four leakage-scanning `find` commands to exclude `test-specs/`:

Replace:

```
      leak_pyjs=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "function \|def \|class \|import \|require(" 2>/dev/null | wc -l)
      leak_go=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^func \|^package \|^import (" 2>/dev/null | wc -l)
      leak_rust=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^fn \|^pub struct \|^impl \|^use " 2>/dev/null | wc -l)
      leak_c=$(find "workspace/raw/specs/test-vectors/" -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^void \|^int \|^#include " 2>/dev/null | wc -l)
```

with:

```
      leak_pyjs=$(find "workspace/raw/specs/test-vectors/" -path "*/test-specs" -prune -o -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "function \|def \|class \|import \|require(" 2>/dev/null | wc -l)
      leak_go=$(find "workspace/raw/specs/test-vectors/" -path "*/test-specs" -prune -o -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^func \|^package \|^import (" 2>/dev/null | wc -l)
      leak_rust=$(find "workspace/raw/specs/test-vectors/" -path "*/test-specs" -prune -o -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^fn \|^pub struct \|^impl \|^use " 2>/dev/null | wc -l)
      leak_c=$(find "workspace/raw/specs/test-vectors/" -path "*/test-specs" -prune -o -name "*.md" -print0 2>/dev/null | xargs -0 grep -rl "^void \|^int \|^#include " 2>/dev/null | wc -l)
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_validation.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_validation.dip
git commit -m "fix(validation): exclude test-specs/ from Gate2ToolCheck leakage scan"
```

---

### Task 8: Fix Gate1bCompleteness spec count inflation by bd-*.md files

**Finding:** IMP 4 — `Gate1bCompleteness` counts ALL `*.md` files in `modules/` including BehaviorDocumenter's `bd-*.md` files, inflating the spec count vs the module count from module-map.md.

**Fix:** Exclude `bd-*.md` and `gate*.md` files from the spec count to match only DeepDiveAnalyzer output (which is what the module map maps to).

**Files:**
- Modify: `greenfield_synthesis.dip:320-321` (Gate1bCompleteness command)

- [ ] **Step 1: Filter spec count**

In the `Gate1bCompleteness` tool command, replace:

```
        spec_count=$(find "workspace/raw/specs/modules/" -name "*.md" -not -name "gate*" 2>/dev/null | wc -l | tr -d ' ')
```

with:

```
        spec_count=$(find "workspace/raw/specs/modules/" -name "*.md" -not -name "gate*" -not -name "bd-*" 2>/dev/null | wc -l | tr -d ' ')
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_synthesis.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): exclude bd-*.md from Gate1bCompleteness spec count"
```

---

### Task 9: Add SanitizerContracts agent for contracts/ directory

**Finding:** CRIT 12 — `raw/specs/contracts/` is never sanitized into `output/`. ContractExtractor output is lost.

**Fix:** Add a `SanitizerContracts` agent to the sanitization parallel group. Also add a contracts output directory to SetupWorkspace.

**Files:**
- Modify: `greenfield_validation.dip:172, 218, 268-273` (parallel declaration, fan_in, edges)
- Modify: `greenfield.dip:39` (SetupWorkspace mkdir)

- [ ] **Step 1: Add SanitizerContracts agent**

In `greenfield_validation.dip`, add a new agent after `SanitizerAcceptanceCriteria`:

```
  agent SanitizerContracts
    label: "Sanitizer — Contracts"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are a Sanitizer worker for Greenfield. Sanitize dependency contracts and protocol specs.

      Read workspace/raw/specs/contracts/.
      Write sanitized versions to workspace/output/contracts/.

      PRESERVE: environment variables, CLI flags, config keys, API fields, wire protocol names, error messages, user-facing paths.
      REMOVE: function names, variable names, minified identifiers, line numbers, source file paths, code structure descriptions, internal data structure names.

      Provenance citations survive — but replace raw source paths with workspace-relative refs.

      You REWRITE from understanding, not copy. The output must read as if written by someone who knows the behavior but never saw the code.
```

- [ ] **Step 2: Update parallel declaration**

Replace:

```
  parallel SanitizationParallel -> SanitizerSpecs, SanitizerTestVectors, SanitizerAcceptanceCriteria
```

with:

```
  parallel SanitizationParallel -> SanitizerSpecs, SanitizerTestVectors, SanitizerAcceptanceCriteria, SanitizerContracts
```

- [ ] **Step 3: Update fan_in**

Replace:

```
  fan_in SanitizationJoin <- SanitizerSpecs, SanitizerTestVectors, SanitizerAcceptanceCriteria
```

with:

```
  fan_in SanitizationJoin <- SanitizerSpecs, SanitizerTestVectors, SanitizerAcceptanceCriteria, SanitizerContracts
```

- [ ] **Step 4: Add parallel-to-agent and agent-to-join edges**

In the edges section, add:

```
    SanitizationParallel -> SanitizerContracts
    SanitizerContracts -> SanitizationJoin
```

- [ ] **Step 5: Add output/contracts/ to SetupWorkspace**

In `greenfield.dip`, in the `SetupWorkspace` tool command, after the line:

```
      mkdir -p workspace/output/specs workspace/output/test-vectors workspace/output/validation/acceptance-criteria
```

add `workspace/output/contracts` to the same mkdir:

Replace:

```
      mkdir -p workspace/output/specs workspace/output/test-vectors workspace/output/validation/acceptance-criteria
```

with:

```
      mkdir -p workspace/output/specs workspace/output/test-vectors workspace/output/validation/acceptance-criteria workspace/output/contracts
```

- [ ] **Step 6: Update SanitizationToolCheck to check contracts**

In `greenfield_validation.dip`, in the `SanitizationToolCheck` tool command, add a contracts count check. After:

```
      ac_count=$(find "workspace/output/validation/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      if [ "$ac_count" -eq 0 ]; then errors="${errors}no-output-acceptance-criteria "; fi
```

add:

```
      contract_count=$(find "workspace/output/contracts/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
```

Note: Don't make contract_count=0 a hard error — contracts may legitimately not exist for all targets. Only add it to the output string for visibility:

Replace:

```
      printf 'sanitization-ok-specs-%s-tv-%s-ac-%s' "$spec_count" "$tv_count" "$ac_count"
```

with:

```
      contract_count=$(find "workspace/output/contracts/" -name "*.md" -print0 2>/dev/null | xargs -0 -I{} echo x | wc -l)
      printf 'sanitization-ok-specs-%s-tv-%s-ac-%s-contracts-%s' "$spec_count" "$tv_count" "$ac_count" "$contract_count"
```

- [ ] **Step 7: Validate both files**

Run: `tracker validate greenfield_validation.dip && tracker validate greenfield.dip`
Expected: both pass

- [ ] **Step 8: Commit**

```bash
git add greenfield_validation.dip greenfield.dip
git commit -m "feat(validation): add SanitizerContracts agent for contracts/ directory"
```

---

### Task 10: Fix Gate1bCompleteness bare fallback to success

**Finding:** IMP 5 — `Gate1bCompleteness` bare fallback routes to `WriteL2L3Summary` (success). Should fail-safe.

**Files:**
- Modify: `greenfield_synthesis.dip:425` (edges)

- [ ] **Step 1: Fix the bare fallback edge**

Replace:

```
    Gate1bCompleteness -> Gate1bAgent       when ctx.tool_stdout startswith gaps    label: gaps_found
    Gate1bCompleteness -> WriteL2L3Summary  when ctx.tool_stdout = gate1b-pass      label: gate1b_pass
    Gate1bCompleteness -> Gate1Failed       when ctx.tool_stdout = budget-exhausted label: gate1b_budget
    Gate1bCompleteness -> WriteL2L3Summary
```

with:

```
    Gate1bCompleteness -> Gate1bAgent       when ctx.tool_stdout startswith gaps    label: gaps_found
    Gate1bCompleteness -> WriteL2L3Summary  when ctx.tool_stdout = gate1b-pass      label: gate1b_pass
    Gate1bCompleteness -> Gate1Failed       when ctx.tool_stdout = budget-exhausted label: gate1b_budget
    Gate1bCompleteness -> Gate1Failed
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_synthesis.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): route Gate1bCompleteness bare fallback to Gate1Failed"
```

---

### Task 11: Add "internal data structure names" to sanitization REMOVE rules

**Finding:** IMP 13 — Spec REMOVE list includes "internal data structure names" but impl omits it.

**Files:**
- Modify: `greenfield_validation.dip:186, 203, 213` (all three sanitizer prompts)

- [ ] **Step 1: Update SanitizerSpecs REMOVE rule**

Replace:

```
      REMOVE: function names, variable names, minified identifiers, line numbers, source file paths, code structure descriptions.
```

with:

```
      REMOVE: function names, variable names, minified identifiers, line numbers, source file paths, code structure descriptions, internal data structure names.
```

- [ ] **Step 2: Update SanitizerTestVectors prompt**

Replace:

```
      Same PRESERVE/REMOVE rules as spec sanitization. Test vectors should describe behavior (Given/When/Then) without referencing internal code.
```

with:

```
      Same PRESERVE/REMOVE rules as spec sanitization (including removal of internal data structure names). Test vectors should describe behavior (Given/When/Then) without referencing internal code.
```

- [ ] **Step 3: Update SanitizerAcceptanceCriteria prompt**

Replace:

```
      Same PRESERVE/REMOVE rules. AC IDs and spec links must be preserved.
```

with:

```
      Same PRESERVE/REMOVE rules (including removal of internal data structure names). AC IDs and spec links must be preserved.
```

- [ ] **Step 4: Commit**

```bash
git add greenfield_validation.dip
git commit -m "fix(validation): add internal data structure names to sanitization REMOVE rules"
```

---

### Task 12: Make L1Failed write sentinel file

**Finding:** CRIT 7 — `L1Failed` agent only says "Report." It never writes `workspace/.l1-failed`, so `CheckL1Output` can't detect the failure on pipeline restart.

**Files:**
- Modify: `greenfield.dip:196-200` (L1Failed prompt)

- [ ] **Step 1: Update L1Failed prompt**

Replace:

```
  agent L1Failed
    label: "L1 Output Check Failed"
    max_turns: 1
    prompt:
      L1 output check failed — no intelligence sources produced results. Report.
```

with:

```
  agent L1Failed
    label: "L1 Output Check Failed"
    max_turns: 2
    prompt:
      L1 output check failed — no intelligence sources produced results.
      Write workspace/.l1-failed with the reason (e.g., "no completed sources" or "l1 output empty").
      Then report the failure status.
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield.dip
git commit -m "fix(runner): make L1Failed write .l1-failed sentinel file"
```

---

### Task 13: Fix FinalReport hardcoded "all passed" claim

**Finding:** IMP 7 — `FinalReport` prompt says "Gate results (all passed)" which is always true even if gates failed.

**Files:**
- Modify: `greenfield.dip:177-188` (FinalReport prompt)

- [ ] **Step 1: Fix the prompt**

Replace:

```
      Summarize:
      1. Target analyzed and sources discovered
      2. Number of behavioral specs produced
      3. Number of test vectors and acceptance criteria
      4. Gate results (all passed)
      5. Overall confidence assessment
      6. Output location: workspace/output/
```

with:

```
      Summarize:
      1. Target analyzed and sources discovered
      2. Number of behavioral specs produced
      3. Number of test vectors and acceptance criteria
      4. Gate results — read workspace/review/ for L6/L7 findings. Report the actual gate outcome, do not assume all passed.
      5. Overall confidence assessment (read workspace/raw/l1-summary.yaml for provider_fallback status)
      6. Output location: workspace/output/
```

- [ ] **Step 2: Commit**

```bash
git add greenfield.dip
git commit -m "fix(runner): remove hardcoded 'all passed' from FinalReport prompt"
```

---

### Task 14: Fix Gate1bAgent gap list file reference

**Finding:** IMP 9 — `Gate1bAgent` prompt says "Read the gap list from the Gate 1b tool check" but no such file exists. The tool check emits stdout, not a file.

**Fix:** Make the prompt reference the actual tool output format, and note that gaps are communicated via the tool's stdout (which the agent sees as context from the preceding edge).

**Files:**
- Modify: `greenfield_synthesis.dip:349-356` (Gate1bAgent prompt)

- [ ] **Step 1: Fix the prompt**

Replace:

```
      You are the Gate 1b completeness reviewer. Verify every user-facing surface is captured in specs.

      Read the gap list from the Gate 1b tool check. Assess whether the gaps represent missing behavioral coverage or are benign (e.g., utility code with no user-facing behavior).
```

with:

```
      You are the Gate 1b completeness reviewer. Verify every user-facing surface is captured in specs.

      The Gate 1b tool check identified gaps (reported in the tool output above you in the conversation). The gap format is: module-spec-deficit:expected-N-got-M, no-journeys, no-contracts.

      Assess whether the gaps represent missing behavioral coverage or are benign (e.g., utility code with no user-facing behavior). Read workspace/raw/synthesis/module-map.md to understand what modules exist. Read workspace/raw/specs/ to see what specs are present.
```

- [ ] **Step 2: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): fix Gate1bAgent to reference actual tool output format"
```

---

### Task 15: Add Synthesizer provenance requirement

**Finding:** IMP 8 — Synthesizer is the most critical L2 agent but has no provenance citation requirement.

**Files:**
- Modify: `greenfield_synthesis.dip:124-141` (Synthesizer prompt)

- [ ] **Step 1: Add provenance requirement**

In the Synthesizer prompt, after "This module map is the PRIMARY input for L3 deep spec agents. It must be comprehensive.", add:

```

      Every claim needs provenance: <!-- cite: source=synthesis, ref=<L2-evidence-path>, confidence=<level>, agent=synthesizer -->
```

- [ ] **Step 2: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): add provenance requirement to Synthesizer prompt"
```

---

### Task 16: Make WriteL2L3Summary write a file to disk

**Finding:** IMP 6 — `WriteL2L3Summary` only emits stdout, no disk file. Inconsistent with `WriteL1Summary` which writes `l1-summary.yaml`.

**Files:**
- Modify: `greenfield_synthesis.dip:373-381` (WriteL2L3Summary command)

- [ ] **Step 1: Add file write**

Replace:

```
      set -eu
      spec_count=$(find "workspace/raw/specs/modules/" -name "*.md" 2>/dev/null | wc -l)
      journey_count=$(find "workspace/raw/specs/journeys/" -name "*.md" 2>/dev/null | wc -l)
      contract_count=$(find "workspace/raw/specs/contracts/" -name "*.md" 2>/dev/null | wc -l)
      printf 'summary-specs-%s-journeys-%s-contracts-%s' "$spec_count" "$journey_count" "$contract_count"
```

with:

```
      set -eu
      spec_count=$(find "workspace/raw/specs/modules/" -name "*.md" -not -name "gate*" -not -name "bd-*" 2>/dev/null | wc -l)
      journey_count=$(find "workspace/raw/specs/journeys/" -name "*.md" 2>/dev/null | wc -l)
      contract_count=$(find "workspace/raw/specs/contracts/" -name "*.md" 2>/dev/null | wc -l)
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf 'spec_count: %s\njourney_count: %s\ncontract_count: %s\ntimestamp: "%s"\n' "$spec_count" "$journey_count" "$contract_count" "$now" > "workspace/raw/l2l3-summary.yaml"
      printf 'summary-specs-%s-journeys-%s-contracts-%s' "$spec_count" "$journey_count" "$contract_count"
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_synthesis.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_synthesis.dip
git commit -m "fix(synthesis): make WriteL2L3Summary write l2l3-summary.yaml to disk"
```

---

### Task 17: Add CheckReviewOutput tool between L6L7_Review and FinalReport

**Finding:** CRIT 3 — L6/L7 failures are invisible to the parent pipeline. No `CheckReviewOutput` tool exists. Subgraph exits success even on L6/L7 failure. FinalReport runs with "all passed."

**Fix:** Add a `CheckReviewOutput` tool in `greenfield.dip` (matching the pattern of `CheckL1Output`, `CheckSynthesisOutput`, `CheckValidationOutput`). Update edges to route through it.

**Files:**
- Modify: `greenfield.dip:248-250` (edges), plus add new tool node

- [ ] **Step 1: Add CheckReviewOutput tool**

In `greenfield.dip`, add a new tool after the `L6L7_Review` subgraph declaration and before the `FinalReport` agent:

```
  tool CheckReviewOutput
    label: "Check Review Output"
    timeout: 15s
    command:
      set -eu
      if [ -f "workspace/.review-failed" ]; then
        printf 'review-failed-%s' "$(cat workspace/.review-failed)"
        exit 0
      fi
      l6_findings=$(find "workspace/review/" -name "l6-*.md" -print0 2>/dev/null | xargs -0 grep -c "## Finding" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      l7_flags=$(find "workspace/review/" -name "l7-*.md" -print0 2>/dev/null | xargs -0 grep -c "## Fidelity Flag" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      printf 'review-ok-l6-%s-l7-%s' "$l6_findings" "$l7_flags"
```

- [ ] **Step 2: Update edges**

Replace:

```
    L6L7_Review -> FinalReport                when ctx.outcome = success  label: review_done
    L6L7_Review -> ReviewFailed               when ctx.outcome = fail     label: review_subgraph_failed
    L6L7_Review -> ReviewFailed
```

with:

```
    L6L7_Review -> CheckReviewOutput          when ctx.outcome = success  label: review_done
    L6L7_Review -> ReviewFailed               when ctx.outcome = fail     label: review_subgraph_failed
    L6L7_Review -> ReviewFailed
    CheckReviewOutput -> FinalReport          when ctx.tool_stdout startswith review-ok      label: review_ok
    CheckReviewOutput -> ReviewFailed         when ctx.tool_stdout startswith review-failed  label: review_failed
    CheckReviewOutput -> ReviewFailed
```

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield.dip`
Expected: validation passes

- [ ] **Step 4: Commit**

```bash
git add greenfield.dip
git commit -m "feat(runner): add CheckReviewOutput tool to detect L6/L7 failures in parent pipeline"
```

---

### Task 18: Fix DiscoverTarget find -o without grouping parens

**Finding:** CRIT 4 — `find . -maxdepth 3 -name "*.py" -o -name "*.js" ...` without parens causes the `-maxdepth` and initial path conditions to apply only to the first `-name`, not the subsequent `-o` alternatives.

**Fix:** Wrap the `-name -o -name` groups in escaped parens: `\( -name "*.py" -o -name "*.js" \)`.

**Files:**
- Modify: `greenfield.dip:52-77` (DiscoverTarget command)

- [ ] **Step 1: Fix all find -o commands**

Replace the source code detection line:

```
      if find . -maxdepth 3 -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.c" -o -name "*.cpp" -o -name "*.rb" 2>/dev/null | head -1 | grep -q .; then
```

with:

```
      if find . -maxdepth 3 \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.c" -o -name "*.cpp" -o -name "*.rb" \) 2>/dev/null | head -1 | grep -q .; then
```

Replace the binary detection line:

```
      if find . -maxdepth 2 -name "*.exe" -o -name "*.so" -o -name "*.dylib" -o -name "*.dll" 2>/dev/null | head -1 | grep -q .; then
```

with:

```
      if find . -maxdepth 2 \( -name "*.exe" -o -name "*.so" -o -name "*.dylib" -o -name "*.dll" \) 2>/dev/null | head -1 | grep -q .; then
```

Replace the test detection line:

```
      if find . -maxdepth 3 -name "*test*" -o -name "*spec*" 2>/dev/null | head -1 | grep -q .; then
```

with:

```
      if find . -maxdepth 3 \( -name "*test*" -o -name "*spec*" \) 2>/dev/null | head -1 | grep -q .; then
```

Replace the visual detection line:

```
      if find . -maxdepth 3 -name "*.html" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" -o -name "*.svelte" 2>/dev/null | head -1 | grep -q .; then
```

with:

```
      if find . -maxdepth 3 \( -name "*.html" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" -o -name "*.svelte" \) 2>/dev/null | head -1 | grep -q .; then
```

Replace the contracts detection line:

```
      if find . -maxdepth 3 -name "*.proto" -o -name "openapi*" -o -name "swagger*" -o -name "*.graphql" 2>/dev/null | head -1 | grep -q .; then
```

with:

```
      if find . -maxdepth 3 \( -name "*.proto" -o -name "openapi*" -o -name "swagger*" -o -name "*.graphql" \) 2>/dev/null | head -1 | grep -q .; then
```

- [ ] **Step 2: Also exclude workspace/ from find scans**

Each find command scans from `.` which includes `workspace/`. Add `-path ./workspace -prune -o` to prevent pipeline artifacts from inflating counts. Replace the first find (source code) as the pattern for all:

```
      if find . -path ./workspace -prune -o -maxdepth 3 \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.c" -o -name "*.cpp" -o -name "*.rb" \) -print 2>/dev/null | head -1 | grep -q .; then
```

Apply the same `-path ./workspace -prune -o ... -print` pattern to all 5 find commands.

- [ ] **Step 3: Validate**

Run: `tracker validate greenfield.dip`
Expected: validation passes

- [ ] **Step 4: Commit**

```bash
git add greenfield.dip
git commit -m "fix(runner): fix DiscoverTarget find -o grouping and exclude workspace/ from scans"
```

---

### Task 19: Add .gate2-retries cleanup to SetupWorkspace

**Finding:** MINOR — `.gate2-retries` was already added to cleanup in a prior commit, but verify it's present alongside all other sentinel cleanups.

**Files:**
- Modify: `greenfield.dip:31-32` (SetupWorkspace command) — verify only

- [ ] **Step 1: Verify .gate2-retries is in cleanup**

Read `greenfield.dip:31-32` and confirm this line exists:

```
      rm -f workspace/.gate1-retries workspace/.gate1b-retries workspace/.gate2-retries workspace/.l6-retries workspace/.l7-retries
```

If `.gate2-retries` is present (it should be per the current code), this task is already done. Skip to commit note.

- [ ] **Step 2: If missing, add it**

This should already be present. If not, add `workspace/.gate2-retries` to the rm -f line.

- [ ] **Step 3: Commit (only if changes needed)**

```bash
git add greenfield.dip
git commit -m "fix(runner): ensure .gate2-retries cleaned in SetupWorkspace"
```

---

### Task 20: Fix CoverageCheck fan_in_failed silent exit

**Finding:** IMP 3 — When CoverageCheck emits `incomplete`, pipeline routes directly to Exit with no diagnostics.

**Fix:** Route `fan_in_failed` to a new `L1IncompleteFailed` agent that logs which markers are missing, then exits.

**Files:**
- Modify: `greenfield_discovery.dip:380` (edge) + add new agent

- [ ] **Step 1: Add L1IncompleteFailed agent**

In `greenfield_discovery.dip`, add a new agent before `Exit`:

```
  agent L1IncompleteFailed
    label: "L1 Incomplete — Missing Markers"
    max_turns: 2
    prompt:
      One or more L1 intelligence agents completed without writing a completion marker (.completed, .skipped, or .failed).

      Check each directory for markers:
      - workspace/raw/source/
      - workspace/public/docs/
      - workspace/public/ecosystem/
      - workspace/public/community/
      - workspace/raw/runtime/
      - workspace/raw/binary/
      - workspace/raw/project-history/
      - workspace/raw/test-evidence/

      Report which agents are missing markers. Write workspace/.l1-failed with "incomplete fan-in: <list of missing agent types>".
```

- [ ] **Step 2: Update edge**

Replace:

```
    CoverageCheck -> Exit               when ctx.tool_stdout startswith incomplete    label: fan_in_failed
```

with:

```
    CoverageCheck -> L1IncompleteFailed  when ctx.tool_stdout startswith incomplete  label: fan_in_failed
```

- [ ] **Step 3: Add edge from L1IncompleteFailed to Exit**

Add:

```
    L1IncompleteFailed -> Exit
```

- [ ] **Step 4: Validate**

Run: `tracker validate greenfield_discovery.dip`
Expected: validation passes

- [ ] **Step 5: Commit**

```bash
git add greenfield_discovery.dip
git commit -m "fix(discovery): route fan_in_failed to diagnostic agent instead of silent exit"
```

---

### Task 21: Fix CoverageCheck incomplete message to name missing types

**Finding:** IMP 14 — Spec requires `incomplete-<type>`, impl emits `incomplete-missing-N-markers` (count only, no type names).

**Fix:** Change CoverageCheck to name the missing types.

**Files:**
- Modify: `greenfield_discovery.dip:296-311` (CoverageCheck command)

- [ ] **Step 1: Update CoverageCheck to name missing types**

Replace:

```
      missing=0
```
and the missing counter logic:
```
        else
          missing=$((missing + 1))
        fi
```
and the incomplete output:
```
      if [ "$missing" -gt 0 ]; then
        printf 'incomplete-missing-%s-markers' "$missing"
        exit 0
      fi
```

with a version that tracks missing type names:

Replace the entire CoverageCheck command with:

```
      set -eu
      completed=0
      skipped=0
      failed=0
      missing_types=""
      entries="source:workspace/raw/source docs:workspace/public/docs ecosystem:workspace/public/ecosystem community:workspace/public/community runtime:workspace/raw/runtime binary:workspace/raw/binary git_history:workspace/raw/project-history tests:workspace/raw/test-evidence"
      for entry in $entries; do
        key=$(printf '%s' "$entry" | cut -d: -f1)
        d=$(printf '%s' "$entry" | cut -d: -f2)
        if [ -f "$d/.completed" ]; then
          completed=$((completed + 1))
        elif [ -f "$d/.skipped" ]; then
          skipped=$((skipped + 1))
        elif [ -f "$d/.failed" ]; then
          failed=$((failed + 1))
        else
          missing_types="${missing_types}${key},"
        fi
      done
      if [ -n "$missing_types" ]; then
        printf 'incomplete-%s' "$missing_types"
        exit 0
      fi
      community_done=0
      [ -f "workspace/public/community/.completed" ] && community_done=1
      non_community=$((completed - community_done))
      printf 'coverage-%s-completed-%s-skipped-%s-failed-noncommunity-%s' "$completed" "$skipped" "$failed" "$non_community"
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_discovery.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_discovery.dip
git commit -m "fix(discovery): CoverageCheck names missing source types instead of just counting"
```

---

### Task 22: Add paths field to WriteL1Summary

**Finding:** IMP 15 — Spec requires source counts AND paths. Impl writes only counts.

**Files:**
- Modify: `greenfield_discovery.dip:337-353` (WriteL1Summary command)

- [ ] **Step 1: Add per-source paths to summary**

Replace the WriteL1Summary command:

```
      set -eu
      completed=0
      dirs="workspace/raw/source workspace/public/docs workspace/public/ecosystem workspace/public/community workspace/raw/runtime workspace/raw/binary workspace/raw/project-history workspace/raw/test-evidence"
      for d in $dirs; do
        if [ -f "$d/.completed" ]; then
          completed=$((completed + 1))
        fi
      done
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      fallback=false
      [ -f "workspace/raw/coverage-assessment.md" ] && fallback=true
      printf 'completed_sources: %s\ntimestamp: "%s"\nprovider_fallback: %s\n' "$completed" "$now" "$fallback" > "workspace/raw/l1-summary.yaml"
      printf 'l1-summary-written-%s-sources' "$completed"
```

with:

```
      set -eu
      completed=0
      paths=""
      entries="source:workspace/raw/source docs:workspace/public/docs ecosystem:workspace/public/ecosystem community:workspace/public/community runtime:workspace/raw/runtime binary:workspace/raw/binary git_history:workspace/raw/project-history tests:workspace/raw/test-evidence"
      for entry in $entries; do
        key=$(printf '%s' "$entry" | cut -d: -f1)
        d=$(printf '%s' "$entry" | cut -d: -f2)
        if [ -f "$d/.completed" ]; then
          completed=$((completed + 1))
          paths="${paths}\n  ${key}: ${d}"
        elif [ -f "$d/.skipped" ]; then
          paths="${paths}\n  ${key}: skipped"
        elif [ -f "$d/.failed" ]; then
          paths="${paths}\n  ${key}: failed"
        fi
      done
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      fallback=false
      [ -f "workspace/raw/coverage-assessment.md" ] && fallback=true
      printf 'completed_sources: %s\ntimestamp: "%s"\nprovider_fallback: %s\nsource_paths:%b\n' "$completed" "$now" "$fallback" "$paths" > "workspace/raw/l1-summary.yaml"
      printf 'l1-summary-written-%s-sources' "$completed"
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_discovery.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_discovery.dip
git commit -m "fix(discovery): add per-source paths to WriteL1Summary output"
```

---

### Task 23: Give CommunityAnalyst access to project name

**Finding:** IMP 11 — CommunityAnalyst has no way to identify the project name for web searches.

**Fix:** Add instruction to read workspace/discovery-manifest.yaml and workspace.json for the target name/path.

**Files:**
- Modify: `greenfield_discovery.dip:157-174` (CommunityAnalyst prompt)

- [ ] **Step 1: Update prompt**

Replace:

```
      ## Your job
      Search the web for public information about the target software: documentation sites, GitHub issues, discussions, blog posts, Stack Overflow questions, tutorials.

      Community analysis is ALWAYS available (web search). There is no skip marker for this source type.

      1. Search for the project name, key APIs, error messages
```

with:

```
      ## Your job
      Search the web for public information about the target software: documentation sites, GitHub issues, discussions, blog posts, Stack Overflow questions, tutorials.

      Community analysis is ALWAYS available (web search). There is no skip marker for this source type.

      First, read workspace/discovery-manifest.yaml for the target path. Read any README*, package.json, go.mod, Cargo.toml, or pyproject.toml in the target to identify the project name, description, and key terms for searching.

      1. Search for the project name, key APIs, error messages
```

- [ ] **Step 2: Commit**

```bash
git add greenfield_discovery.dip
git commit -m "fix(discovery): give CommunityAnalyst access to project identity for web searches"
```

---

### Task 24: Reduce L6 reviewer scope overlap

**Finding:** IMP 10 — L6 reviewers have overlapping scope causing duplicate findings inflation.

**Fix:** Make each reviewer's scope more distinct in their prompts. StructuralLeakage focuses on organization/naming patterns. ContentContamination focuses on identifiers/paths/symbols. BehavioralCompleteness focuses on coverage gaps. DeepReadAuditor focuses on subtle leakage missed by the others.

**Files:**
- Modify: `greenfield_review.dip:49-98` (four L6 reviewer prompts)

- [ ] **Step 1: Add scope boundaries to each reviewer**

In `StructuralLeakageReviewer` prompt, add at the end:

```

      SCOPE BOUNDARY: Focus on structural/organizational leakage ONLY. Do NOT flag individual identifiers or variable names — that's the Content Contamination Reviewer's job. Do NOT assess coverage gaps — that's the Behavioral Completeness Reviewer's job.
```

In `ContentContaminationReviewer` prompt, add at the end:

```

      SCOPE BOUNDARY: Focus on individual identifiers, paths, and symbols ONLY. Do NOT flag structural/organizational patterns — that's the Structural Leakage Reviewer's job.
```

In `BehavioralCompletenessReviewer` prompt, add at the end:

```

      SCOPE BOUNDARY: Focus on coverage and completeness ONLY. Do NOT flag contamination — that's the job of the Structural Leakage and Content Contamination Reviewers.
```

In `DeepReadAuditor` prompt, replace the current prompt content:

```
      You are the Deep Read Auditor. Line-by-line audit of workspace/output/specs/ for any contamination the other reviewers might have missed.

      Write findings to workspace/review/l6-deep-read-audit.md.
```

with:

```
      You are the Deep Read Auditor. Line-by-line audit of workspace/output/specs/ for subtle contamination that pattern-based reviewers miss.

      Focus on: implied code knowledge (descriptions that only make sense if you've read the source), accidental specificity (exact byte sizes, buffer counts, thread pool sizes that leak implementation), and prose that reads like paraphrased source comments.

      Do NOT duplicate findings from the other three L6 reviewers. Read their output files first (workspace/review/l6-structural-leakage.md, l6-content-contamination.md, l6-behavioral-completeness.md) and skip anything already flagged.

      Write findings to workspace/review/l6-deep-read-audit.md.
```

- [ ] **Step 2: Validate**

Run: `tracker validate greenfield_review.dip`
Expected: validation passes

- [ ] **Step 3: Commit**

```bash
git add greenfield_review.dip
git commit -m "fix(review): reduce L6 reviewer scope overlap with explicit boundaries"
```

---

### Task 25: Add FidelityValidatorAcceptanceCriteria for L7

**Finding:** CRIT 9 — L7 only validates specs and test vectors. Acceptance criteria pass through unchecked for fidelity loss.

**Fix:** Add `FidelityValidatorAcceptanceCriteria` to the L7 parallel group.

**Files:**
- Modify: `greenfield_review.dip:168, 200, 299-302` (parallel declaration, fan_in, edges)

- [ ] **Step 1: Add FidelityValidatorAcceptanceCriteria agent**

In `greenfield_review.dip`, add a new agent after `FidelityValidatorTestVectors`:

```
  agent FidelityValidatorAcceptanceCriteria
    label: "Fidelity Validator — Acceptance Criteria"
    model: claude-opus-4-6
    provider: anthropic
    reasoning_effort: high
    prompt:
      You are the Fidelity Validator for acceptance criteria. Compare workspace/raw/specs/validation/ against workspace/output/validation/acceptance-criteria/.

      Flag where acceptance criteria were weakened, IDs were lost, or spec links were broken during sanitization.

      Write findings to workspace/review/l7-fidelity-acceptance-criteria.md using the same format:
      ## Fidelity Flag FL-001
      **Raw spec:** <file>
      **Output spec:** <file>
      **Lost detail:** <description>
      **Severity:** critical | notable | minor
      **Recommendation:** <how to restore without reintroducing contamination>
```

- [ ] **Step 2: Update parallel declaration**

Replace:

```
  parallel FidelityParallel -> FidelityValidatorSpecs, FidelityValidatorTestVectors
```

with:

```
  parallel FidelityParallel -> FidelityValidatorSpecs, FidelityValidatorTestVectors, FidelityValidatorAcceptanceCriteria
```

- [ ] **Step 3: Update fan_in**

Replace:

```
  fan_in FidelityJoin <- FidelityValidatorSpecs, FidelityValidatorTestVectors
```

with:

```
  fan_in FidelityJoin <- FidelityValidatorSpecs, FidelityValidatorTestVectors, FidelityValidatorAcceptanceCriteria
```

- [ ] **Step 4: Add edges**

In the edges section, add:

```
    FidelityParallel -> FidelityValidatorAcceptanceCriteria
    FidelityValidatorAcceptanceCriteria -> FidelityJoin
```

- [ ] **Step 5: Validate**

Run: `tracker validate greenfield_review.dip`
Expected: validation passes

- [ ] **Step 6: Commit**

```bash
git add greenfield_review.dip
git commit -m "feat(review): add FidelityValidatorAcceptanceCriteria to L7 parallel group"
```

---

## Self-Review

**Spec coverage check against the consolidated review findings:**

| Finding | Task | Covered? |
|---|---|---|
| CRIT 1: Gate1 retry vs fail edge | Task 1 | Yes |
| CRIT 2: Gate2 retry vs fail edge | Task 3 | Yes |
| CRIT 3: L6/L7 failures invisible to parent | Task 17 | Yes |
| CRIT 4: DiscoverTarget find -o bug | Task 18 | Yes |
| CRIT 5: Provider fallback agents absent | DEFERRED (Plan B) | Scoped out |
| CRIT 6: Provider probes missing | DEFERRED (Plan B) | Scoped out |
| CRIT 7: L1Failed no sentinel | Task 12 | Yes |
| CRIT 8: Gate2 no feedback loop | Tasks 3, 4 | Yes |
| CRIT 9: No L7 AC fidelity validator | Task 25 | Yes |
| CRIT 10: Gate2ToolCheck false-positive | Task 7 | Yes |
| CRIT 11: Gate retry targets wrong | Tasks 2, 3 | Yes |
| CRIT 12: Contracts never sanitized | Task 9 | Yes |
| IMP 1: SanitizationToolCheck fallback | Task 6 | Yes |
| IMP 2: Stale files on retry | Task 5 | Yes |
| IMP 3: fan_in_failed silent exit | Task 20 | Yes |
| IMP 4: Gate1b spec count inflation | Task 8 | Yes |
| IMP 5: Gate1b bare fallback | Task 10 | Yes |
| IMP 6: WriteL2L3Summary no disk file | Task 16 | Yes |
| IMP 7: FinalReport "all passed" | Task 13 | Yes |
| IMP 8: Synthesizer no provenance | Task 15 | Yes |
| IMP 9: Gate1bAgent gap reference | Task 14 | Yes |
| IMP 10: L6 reviewer overlap | Task 24 | Yes |
| IMP 11: CommunityAnalyst no project name | Task 23 | Yes |
| IMP 12: workspace.json target hardcoded | Not in plan — low risk, requires pipeline input mechanism | Deferred |
| IMP 13: Sanitization REMOVE rules | Task 11 | Yes |
| IMP 14: CoverageCheck no type names | Task 21 | Yes |
| IMP 15: WriteL1Summary no paths | Task 22 | Yes |
| IMP 16: No fail edges from SetupWorkspace | Not in plan — SetupWorkspace uses set -eu, tool crash = DIP-level failure | Acceptable |
| IMP 17: L1 markers agent-written | Structural — acknowledged, mitigated by Task 20 | Acknowledged |
| MINOR 1-12 | Various tasks address root causes | Covered by parent fixes |

**Placeholder scan:** No TBD, TODO, or "fill in details" found.

**Type consistency:** All node names, edge targets, and file paths cross-reference correctly.

**Deferred to Plan B:** Provider fallback system (CRIT 5-6), workspace.json target parameterization (IMP 12).
