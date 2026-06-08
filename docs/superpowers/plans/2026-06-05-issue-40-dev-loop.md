# Plan — `dev_loop/` autonomous issue-driven PR-review squad loop (issue #40, v6 design)

> Source of truth: `gh issue view 40 --repo 2389-research/pipelines` (v6 body) + the implementer brief at `/tmp/dev_loop_implementer_brief.md`. Implement v6 as specified. Stop, document, and ask if dippin/tracker constraints diverge from v6.

## 1. Mission

A single autonomous `.dip` workflow that:

1. Picks the highest-priority open issue from `2389-research/pipelines`.
2. Plans minimal PR(s).
3. Implements them in a git worktree.
4. Pushes + opens PR.
5. Runs an iterative 5-persona squad review against the PR diff.
6. Synthesizes verdicts → routes to merge / iterate / abandon.
7. Handles CI status, merge conflicts, branch protection.
8. On approval + green CI: merges. Otherwise: comments, increments iter, re-implements with feedback, re-reviews.
9. Cleans up worktree + ratchets a log on every exit path.

Squad applies the repo's coding guidelines (pragmatism, empathy, YAGNI, simplicity, no unnecessary complexity, comprehensive-but-reasonable testing, holistic fit). Diverse models per reviewer. Structured outputs (JSON schemas). All prompts/scripts in their own files. All reviewers `tool_access: none`; `writable_paths` only on the one agent that legitimately writes (the implementer). One workflow file, autonomous start to ratchet.

## 2. Settled answers to v6's open questions

| # | Question | Answer | Rationale |
|---|---|---|---|
| G1 | dippin version | `v0.35.0+1` is fine (one commit past v0.35.0); v0.36.0 adds nothing critical | CHANGELOG inspection: v0.36.0 = DIP143 hint (no subgraph/manager_loop used) + `@file` TOCTOU fix (no `@file` used) |
| G2 | install `bats` + `ajv` | approved | needed for §9 smoke gates |
| G3 | branch ordering | land #26 first off `main`, then branch `dev_loop` off `main` | squad consensus; avoid stacking two safety-relevant changes |
| Q1 | Implementer model | `gpt-5.3-codex` (REVISED — was `gpt-5-codex`) | Initial answer cited `mcp__pal__listmodels` (PAL's alias table), but tracker + dippin are the runtime authority. Their embedded catalogs accept `gpt-5.3-codex` and reject `gpt-5-codex`. Decision documented in memory `model-ids-from-tracker-dippin.md`. |
| Q2 | Implementer `max_turns` | `25` | `docs/agent-node-safety.md:155` flags >30 as anti-pattern; v6's 40 violates the repo's own safety doc |
| Q3 | `max_iters` | `5` (`defaults max_restarts: 6`) | blocker squad attestation; YAGNI pushed for 3 but 5 keeps room and can be lowered after first run |
| Q4 | `allow_no_ci` | `false` | property of dev_loop the artifact, not of this repo's current state; orthogonal to whether this repo has CI |
| Q5 | run host | "wherever someone runs it" | scripts use `${XDG_CACHE_HOME:-$HOME/.cache}`; README documents Linux + writable_paths fs-jail requirement |
| Q6 | tracker session-root env | defer; grep tracker source when writing `create_worktree.sh` | per brief §11 |
| Q7 | branch protection | yes; route `merge-blocked-*` → CleanupWorktree (escalate-to-abandoned) | v6 default |
| Q8 | CI workflow location | same PR | gates own diff from day 1 |
| Δ | model IDs (REVISED) | Stay on v6 spec: `gemini-3.1-pro-preview` and `gpt-5.3-codex`. | The initial Δ entry above was wrong: it picked PAL's IDs because PAL's `listmodels` lists them, but tracker's `validate` rejects them as "unknown model for provider". tracker + dippin are the runtime — PAL is a separate router. The PR commits implement the v6 spec IDs; CI's `test_branch_model_ids.sh` enforces against tracker's allowlist. |
| Δ | `defaults on_failure:` | NOT supported by installed dippin (`48ce8a5`); fall back to per-agent `fallback_target:` or inline failure edges | probe `/tmp/on_failure_probe.dip` → `dippin check` rejects as unknown defaults field; feature exists on dippin-lang main (PR #95) but unreleased in any tag accessible to us |

## 3. File layout

```
dev_loop/
  README.md                          # how to run, deps, Linux requirement, config knobs
  dev_loop.dip                       # ONE master workflow (~28 nodes, ~30 edges)
  config/dev_loop.config.yaml        # repo, base_branch, models, max_iters, allow_no_ci, issue_filter
  prompts/
    select_next_issue.{system,task}.md
    plan_minimal_prs.{system,task}.md
    implementer.{system,task}.md
    squad/
      pragmatism.system.md
      yagni.system.md
      testability.system.md
      holistic.system.md
      blocker.system.md
      task.md                        # shared per-invocation body
    squad_synthesizer.{system,task}.md
  scripts/
    setup_run.sh                     # mkdir state, lock check, export envs
    fetch_open_issues.sh             # gh issue list (GH_REPO-locked) → issues.json
    pre_filter_issues.sh             # deterministic P0–P3 filter + excludes
    persist_selected_issue.sh
    persist_plan.sh
    persist_synthesis.sh             # writes synthesis.json + extracts feedback.json
    persist_pragmatism_verdict.sh
    persist_yagni_verdict.sh
    persist_testability_verdict.sh
    persist_holistic_verdict.sh
    persist_blocker_verdict.sh
    create_worktree.sh               # git worktree add under $XDG_CACHE_HOME/dip/<repo>/wt/<branch>/
    init_iter_counter.sh             # iter=1; emits "iter-init-1-of-5"
    inc_iter_counter.sh              # iter += 1; emits "iter-N-of-M" or "iter-exhausted"
    push_and_open_pr.sh
    fetch_pr_context.sh              # pins HEAD SHA per iter
    recheck_pr_sha.sh                # compares pinned SHA; routes sha-drifted → abandon
    local_gates.sh                   # dippin check + doctor + simulate + tracker validate
    poll_ci.sh                       # tolerates no-CI via ci-no-checks marker
    merge_pr.sh                      # gh pr merge --squash; routes merge-blocked-*
    post_squad_comment.sh
    cleanup_worktree.sh              # idempotent; runs from all exit paths
    ratchet_log.sh
    markers.txt                      # registry of every marker any script emits
  schemas/
    selected_issue.schema.json
    plan.schema.json
    verdict.schema.json
    synthesis.schema.json
  tests/
    test_pre_filter.bats
    test_persist_selected_issue.bats
    test_persist_plan.bats
    test_persist_synthesis.bats
    test_persist_verdict.bats
    test_init_iter_counter.bats
    test_inc_iter_counter.bats
    test_poll_ci.bats                # mocks gh via PATH shim
    test_recheck_pr_sha.bats
    test_local_gates.bats
    test_marker_coverage.sh          # every marker_grep regex matches a marker in markers.txt
    test_branch_model_ids.sh         # rejects unknown model IDs in per-branch overrides
    fixtures/
      issues_sample.json
      pr_diff_sample.txt
      pr_view_sample.json
      verdict_pass.json
      verdict_block.json
      verdict_attest_valid.json
      verdict_attest_invalid.json
.github/workflows/
  dev_loop_smoke.yml                 # first CI in the repo; gates dev_loop diff from day 1
```

Runtime state at `${XDG_CACHE_HOME:-$HOME/.cache}/dip/2389-research-pipelines/runs/<rid>/`. Repo contains config + prompts + scripts + schemas + tests only.

## 4. The workflow — phases + routing

### Phase 1 — Pick + plan (linear)

```
Start
 → SetupRun                       (tool, marker_grep "^(setup-ok|setup-resume-required)$")
 → FetchOpenIssues                (tool, marker_grep "^(fetched-[0-9]+|fetch-failed)$")
 → PreFilter                      (tool, marker_grep "^(filter-ok-[0-9]+|filter-empty)$")
 → SelectNextIssue                (agent: claude-opus-4-6, tool_access:none,
                                    response_format:json_schema with selected_issue schema)
 → PersistSelectedIssue           (tool)
 → PlanMinimalPRs                 (agent: claude-opus-4-6, tool_access:none,
                                    response_format:json_schema with plan schema)
 → PersistPlan                    (tool)
 → CreateWorktree                 (tool, marker_grep "^(worktree-ok|worktree-failed)$")
 → InitIterCounter                (tool, marker_grep "^iter-init-[0-9]+-of-[0-9]+$")
 → Implementer
```

### Phase 2 — Implement + squad-review iteration

```
Implementer (agent: gpt-5.3-codex, max_turns:25,
             writable_paths:".dev_loop_worktree/**",
             working_dir:".dev_loop_worktree", auto_status:true)
  → on success → PushAndOpenPR    (marker_grep "^(pr-ready-[0-9]+|pr-push-failed)$")
      → pr-ready-N → FetchPRContext (marker_grep "^(pr-context-ok|pr-closed|pr-merged-externally)$")
          → pr-context-ok → SquadFanout (block-form parallel)
          → pr-closed | pr-merged-externally → CleanupWorktree

  parallel SquadFanout
    branch: SquadPragmatism   (model: claude-opus-4-6)
    branch: SquadYagni        (model: gemini-3.1-pro-preview)
    branch: SquadTestability  (model: gpt-5.2)
    branch: SquadHolistic     (model: gpt-5.3-codex)
    branch: SquadBlocker      (model: claude-opus-4-6)

  Each squad agent: tool_access:none, reasoning_effort:high,
    response_format:json_schema with verdict schema,
    auto_status:true, system_prompt_file per persona, shared task.md,
    writes: verdict_<persona>

  Each branch is followed by its OWN Persist<Persona>Verdict tool node which
  writes verdict_<persona>.json to disk BEFORE the fan_in collapses last_response.

  fan_in SquadJoin <- PersistPragmatismVerdict, PersistYagniVerdict,
                       PersistTestabilityVerdict, PersistHolisticVerdict,
                       PersistBlockerVerdict

  SquadJoin → SquadSynthesizer    (agent: claude-opus-4-6, tool_access:none,
                                    response_format:json_schema with synthesis schema)
    → on success → PersistSynthesis (writes synthesis.json + feedback.json,
                                      marker_grep "^synthesized-(approved|changes_requested|abandoned)$")
       → RecheckPRSHA              (marker_grep "^(sha-same|sha-drifted)$")
          → sha-same → LocalGates  (marker_grep "^(gates-pass|gates-fail)$")
                → gates-pass → PollCI (marker_grep "^(ci-success|ci-failed|ci-timeout|ci-no-checks)$")
                     → ci-success → MergePR (marker_grep "^(merge-ok|merge-blocked-[a-z_]+)$")
                          → merge-ok | merge-blocked-* → CleanupWorktree
                     → ci-no-checks → CleanupWorktree   (allow_no_ci:false default)
                     → ci-failed | ci-timeout → PostSquadComment
                → gates-fail → PostSquadComment
          → sha-drifted → CleanupWorktree

  PostSquadComment (marker_grep "^comment-posted$")
    → IncIterCounter (marker_grep "^(iter-[0-9]+-of-[0-9]+|iter-exhausted)$")
       → contains "-of-" → Implementer  (restart: true, label: next_iter)
       → iter-exhausted → CleanupWorktree
```

### Phase 3 — Cleanup + ratchet

```
CleanupWorktree (marker_grep "^worktree-cleaned$")
 → RatchetLog   (marker_grep "^ratcheted$")
 → Exit
```

### Routing invariants

- `marker_grep:` lives on every routing tool node (not as edge keyword).
- Edges use only `= literal`, `startswith literal-`, or `contains substring`. No regex in edges.
- Iter back-edge: `ctx.tool_marker contains "-of-"` vs `= iter-exhausted`.
- Every routable agent has a failure route via per-agent `fallback_target: CleanupWorktree` (since `defaults on_failure:` unsupported in installed dippin).

## 5. Loop bound

`max_restarts` is the engine's restart budget. Iter 1 = initial entry (no restart). Iters 2–5 each consume a `restart: true` traversal of the back-edge. For `max_iters: 5`, `defaults max_restarts: 6` gives headroom for the non-restart first entry. The shell counter (`init/inc_iter_counter.sh`) is observational — emits markers for routing + so the implementer prompt can name the iter. Engine refuses an over-budget restart before the shell counter runs.

## 6. Models (catalog-valid)

| Role | Model | Provider |
|---|---|---|
| SelectNextIssue | `claude-opus-4-6` | anthropic |
| PlanMinimalPRs | `claude-opus-4-6` | anthropic |
| **Implementer** | **`gpt-5.3-codex`** | openai |
| SquadPragmatism | `claude-opus-4-6` | anthropic |
| SquadYagni | `gemini-3.1-pro-preview` | gemini |
| SquadTestability | `gpt-5.2` | openai |
| SquadHolistic | `gpt-5.3-codex` | openai |
| SquadBlocker | `claude-opus-4-6` | anthropic |
| SquadSynthesizer | `claude-opus-4-6` | anthropic |

Per-branch overrides escape lint (`checkNodeModelProvider` doesn't inspect branches). Smoke CI adds a branch-model-ID assertion (`tests/test_branch_model_ids.sh`).

## 7. Persona prompts

- **`pragmatism.system.md`** — "Would a senior engineer say this is overcomplicated for the issue's actual ask? Does it respect the user's stated intent without imposing new patterns?"
- **`yagni.system.md`** — "Find every speculative abstraction, premature flexibility, configurability for hypothetical futures, dead branches, indirection that doesn't earn its keep. Recommend deletions."
- **`testability.system.md`** — "Every changed branch has a test that exercises it. Integration over mocks per repo policy. Coverage delta ≥0 on changed code. Tests must not be weakened to pass — count + list test deletions."
- **`holistic.system.md`** — "Cross-module impact, edge cases, prod-readiness, consistency with repo idioms, interactions with existing automation. Walk the system, not just the diff."
- **`blocker.system.md`** — "You are the veto seat. EITHER cite ≥1 concrete failure mode + emit `verdict: BLOCK`, OR emit `verdict: ATTEST` with an attestation list of ≥3 items, each naming a file:line in the diff you walked. Empty/malformed attestation = BLOCK."

Shared `task.md` reads the JSON fixtures (diff, plan, prior feedback) and asks for a structured verdict per the inlined `verdict.schema.json`.

Synthesizer decision rule (in its system prompt):
- Any `verdict.verdict == BLOCK` → outcome `changes_requested`
- `blocker.verdict == ATTEST` and `len(attestation) >= 3` → counts toward approval
- `blocker.verdict == ATTEST` and `len(attestation) < 3` → outcome `changes_requested`
- Else (all PASS or valid ATTEST) → outcome `approved`

## 8. Safety + DIP posture

| Concern | Mitigation |
|---|---|
| Reviewer agents shipping native tool catalog | All 5 reviewers + synthesizer + selector + planner declare `tool_access: none`. Only Implementer has tools. |
| DIP141 (`tool_access:none` + `writable_paths` same agent) | Not present — Implementer is the only agent with `writable_paths`. |
| DIP143 (subgraph containment) | N/A — no `subgraph` or `manager_loop`. |
| DIP144 (no failure routing) | v6 wanted `defaults on_failure: CleanupWorktree`. Installed dippin doesn't support. **Fallback: per-agent `fallback_target: CleanupWorktree`** on every agent. |
| DIP101/DIP102 (conditional-only / no-default routing) | Suppressed on every routing tool via node-level `marker_grep:`. |
| Implementer is credentialed actor | `writable_paths: ".dev_loop_worktree/**"` + `working_dir: ".dev_loop_worktree"`. tracker's Landlock+openat2 fs-jail roots the glob at the session root. Linux only. README documents. |
| `${ctx.last_response}` cross-node injection | Implementer's last_response flows into PushAndOpenPR + next iter's Implementer (via `feedback.json` from PersistSynthesis). Reviewers read the *diff* + *plan* from disk, not the implementer's narrative. Synthesizer reads the 5 verdict JSON files from disk. |
| Post-`fan_in` addressability | After `fan_in`, `last_response` collapses. Each squad branch persists its verdict via dedicated `Persist*Verdict` tool wired as the `fan_in <- …` input. |
| Worktree cleanup | `cleanup_worktree.sh` is idempotent; runs from every exit path + every agent's `fallback_target`. |
| `gh` repo lock | `GH_REPO=2389-research/pipelines` exported in every script (from config YAML). |
| PR force-push race | `fetch_pr_context.sh` pins HEAD SHA per iter; `recheck_pr_sha.sh` compares before merge; sha-drifted → abandoned. |
| Branch protection | `merge_pr.sh` detects + routes `merge-blocked-*` → CleanupWorktree (escalation log). |
| External close/merge mid-cycle | `fetch_pr_context.sh` checks PR state at top of each iter. |
| Iteration runaway | Bound by `defaults max_restarts: 6` (engine). Shell counter observational. |
| Validate gives false confidence | Smoke CI runs `dippin simulate` AND `dippin check`/`doctor` (B5: validator silently disables condition checks after first parse failure). |

## 9. Smoke CI — `.github/workflows/dev_loop_smoke.yml`

- `dippin check` + `dippin doctor` on `dev_loop/dev_loop.dip` — grade A target.
- `dippin simulate dev_loop/dev_loop.dip` — MANDATORY (catches B5 validator blind spot).
- Branch-model-ID assertion — enumerates every per-branch `model:` in SquadFanout; rejects unknown IDs.
- `shellcheck` on `scripts/*.sh`.
- `ajv` compile + validate schemas vs fixtures.
- `bats` unit tests for non-trivial scripts.
- `tracker validate` end-to-end on `dev_loop.dip`.
- `test_marker_coverage.sh` — every `marker_grep` regex matches at least one marker in `scripts/markers.txt`.

## 10. Config — `dev_loop/config/dev_loop.config.yaml`

```yaml
repo: 2389-research/pipelines
base_branch: main
runtime_state_root: ${XDG_CACHE_HOME:-$HOME/.cache}/dip
max_iters: 5
allow_no_ci: false

issue_filter:
  priority_label_order: ["P0","P1","P2","P3"]
  excluded_labels: ["survey","question","tracking","blocked"]
  excluded_author_globs: ["*[bot]"]
  excluded_title_regex: "(?i)(dev_loop|dippin meta|tracker meta)"

models:
  selector: claude-opus-4-6
  planner: claude-opus-4-6
  implementer: gpt-5.3-codex
  squad:
    pragmatism:  claude-opus-4-6
    yagni:       gemini-3.1-pro-preview
    testability: gpt-5.2
    holistic:    gpt-5.3-codex
    blocker:     claude-opus-4-6
  synthesizer: claude-opus-4-6

local_test_command: ""
```

## 11. Implementation order

1. **Land #26** (currently PR #41). Branch dev_loop off main once merged.
2. **Schemas first.** Author the 4 JSON schemas. Validate each with `ajv` against a hand-crafted fixture. (~30 min)
3. **Markers registry.** Write `scripts/markers.txt` listing every marker the workflow expects to emit. Contract surface; referenced by `.dip` `marker_grep:` regexes and each script. (~15 min)
4. **`dev_loop.dip` skeleton.** Copy v6 §3 verbatim into the file; fix any tracker-version-specific syntax issues; get `dippin check` to pass. Schemas inline; prompts/scripts can be empty placeholders. **Use per-agent `fallback_target:` instead of `defaults on_failure:`.** (~1 hour)
5. **Scripts.** Write each shell script with `set -euo pipefail`, a per-script `bats` test, and `shellcheck`-clean output. Order: `setup_run.sh` → `fetch_open_issues.sh` → `pre_filter_issues.sh` → `persist_*.sh` → counter scripts → worktree scripts → PR scripts → review scripts → cleanup/ratchet. (~4-6 hours)
6. **Prompts.** Author each persona's `system_prompt_file` (~150-300 words per persona; include STATUS line reminder; reference repo's coding guidelines verbatim). Shared `task.md` reads JSON fixtures and asks for `response_format: json_schema`-compliant verdict. (~3-4 hours)
7. **CI workflow.** `dev_loop_smoke.yml` runs everything. Includes branch-model-ID assertion. (~1 hour)
8. **End-to-end dry run.** Run `tracker dev_loop/dev_loop.dip` against a deliberately-crafted test issue. Walk every routing path: success, BLOCK, ATTEST-invalid, sha-drift, CI-no-checks, max-iters-exhausted. Fix what doesn't work. (~3-5 hours)
9. **Open PR.** Title `feat(dev_loop): autonomous issue-driven dev loop (v6 design from #40)`. PR body links #40 and lists each verification command + result. Human review required — do NOT auto-merge through dev_loop itself.

Estimated total: ~16-22 hours. If over 30 hours, stop and re-scope.

## 12. Out of scope for v1

- Squad eval corpus + calibration + per-prompt regression gate (follow-up).
- Adaptive squad sizing by `risk_class` annotated in plan (follow-up).
- Cross-repo support — currently locked to `2389-research/pipelines` (follow-up).
- Plan-level review fanout — currently planner is one Opus pass (follow-up).
- Reverse-engineer `TRACKER_SESSION_ROOT` (or equivalent) env for `writable_paths` glob anchoring; pin in `setup_run.sh`.

## 13. Refs

- Issue #40 (v6 design body + comments).
- `/tmp/dev_loop_implementer_brief.md` (implementer brief).
- `docs/agent-node-safety.md`.
- `iterative/iter_run.dip` (implementer + par-reviewer + counter pattern).
- `sprint/sprint_exec_yaml_v2.dip` (manager journals, retry edges, mechanical gates).
- dippin-lang `parser/parse_nodes.go`, `parser/parse_edges.go`, `simulate/condition.go`, `validator/lint*.go`, `validator/lint_failure_route.go`.
- tracker `agent/exec/jail_linux.go` + `jail_other.go`.
- PR #41 (issue #26 writable_paths landing) — must merge before this PR branches.
