# Simmer Trajectory — spec_to_dip.dip

| Iter | Gen Success | Prompt Clarity | Robustness | Composite | Key Change |
|------|------------|----------------|------------|-----------|------------|
| 0    | 6          | 5              | 8          | 6.3       | seed       |
| 1    | 8          | 7              | 9          | 8.0       | fix regen_missing, resolve set-e, add fallback_targets |
| 2    | 9          | 8              | 10         | 9.0       | replace bracket pseudo-code, self-test checklist, 5 more fallbacks |
| 3    | 9          | 9              | 10         | 9.3       | reasoning_effort/retry_target in example, fix header, analyze_spec fallback |

## Iteration 0 — Seed

### Judge Board Findings (convergent):
1. regen_missing uses bracket edge syntax — the exact anti-pattern (all 3 judges)
2. regen_missing is severely truncated vs gen_claude/gen_gpt/gen_gemini (judges 1, 2)
3. set -e contradiction: gen agents warn against it, but Gemini emphasis + review criteria recommend it (judges 1, 2)
4. Missing fallback_targets on synthesize_scores and simmer_judge (judge 3)
5. Bracket notation in "Required Patterns" pseudo-code could confuse LLMs (judges 1, 2)
6. Missing constructs in example: subgraph, reasoning_effort, retry_target, reads/writes (judges 1, 2)

### ASI (synthesized):
Fix regen_missing to match the other three gen agents: replace bracket edge syntax with keyword syntax, add full anti-pattern list, add WRONG/RIGHT edge examples, add set -e warning. Resolve the set -e contradiction by distinguishing routing vs non-routing tool scripts in Gemini emphasis and review criteria. Add fallback_targets to synthesize_scores and simmer_judge.

## Iteration 1 — Generator applied ASI

### Judge Board Findings:
1. regen_missing fully fixed — keyword syntax, full anti-pattern list, WRONG/RIGHT examples (all 3 judges confirmed)
2. set-e contradiction resolved in gen_gemini emphasis, review_robustness, fresh_eyes (all 3)
3. fallback_targets added to synthesize_scores and simmer_judge (robustness judge confirmed)
4. REMAINING: 20 bracket pseudo-code instances in "Required Patterns" sections (clarity judge)
5. REMAINING: 5 nodes still missing fallback_target (robustness judge)
6. REMAINING: Missing constructs in example — reasoning_effort, retry_target (clarity judge)

### ASI (synthesized):
Replace bracket-based pseudo-code in ALL "Required Patterns" sections with edge-style notation (e.g., `-> continue  when ctx.outcome = success` instead of `[pass: continue]`). Add fallback_targets to remaining 5 unprotected nodes. Add self-test checklist to gen agent prompts for LLMs to verify their own output.

## Iteration 2 — Generator applied ASI

### Judge Board Findings:
1. All bracket pseudo-code replaced with edge-style notation — zero bracket instances remain (all 3)
2. Self-test checklist added to all 4 gen agent prompts (gen success, clarity)
3. All 5 remaining fallback_targets added — zero unprotected agent nodes (robustness: 10/10)
4. REMAINING: regen_missing example only shows unconditional edges — no `when` clauses (gen success)
5. REMAINING: Example claims "EVERY construct" but omits reasoning_effort, retry_target, human freeform (clarity)
6. REMAINING: analyze_spec lacks fallback_target, uses retry_target only (robustness, minor)

### ASI (synthesized):
Add conditional edges (when ctx.tool_stdout = pass/fail) to regen_missing's example. Add reasoning_effort and retry_target to the embedded example's implement node. Change "EVERY construct" header to "most common constructs" or make it truly exhaustive by adding a human freeform example. Add fallback_target to analyze_spec.

## Iteration 3 (final) — Generator applied ASI

### Judge Board Findings:
1. reasoning_effort and retry_target added to embedded example in all 4 gen agents (clarity: confirmed)
2. "EVERY construct" header corrected to "most common constructs" in all 4 gen agents (clarity: confirmed)
3. regen_missing now at full parity with other gen agents (all 3: confirmed)
4. analyze_spec now has fallback_target: Done (robustness: confirmed)
5. Robustness: 10/10 — "No further improvements needed" (robustness judge)
6. Minor remaining gaps: embedded example doesn't show human freeform mode; no multi-branch routing example

### Final Result
Best candidate: iteration 3 (9.3/10 composite)
Written to: docs/simmer/result.dip
