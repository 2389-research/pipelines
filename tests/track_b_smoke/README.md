# Track B runtime smoke tests

Runtime smoke harness for the `tool_access: none` sweep in PRs [#21][pr21]
(Phase 1) and [#23][pr23] (Phase 2 partial). Tracking [issue #19][issue19].

The Phase 1 / Phase 2 PRs landed under `dippin doctor` + `tracker validate`
static gates. Squad review (gpt-5.2, gpt-5.1-codex, o3) flagged that static
checks can't catch:

1. Backends auto-injecting `finish` / `send_message` / status-formatting tools
   that converted agents may have implicitly relied on.
2. Provider-specific response-format shifts when the tool catalog is empty.
3. Subgraph / parallel call-site differences where the same agent is invoked
   with different tool needs.
4. Pipelines that incidentally relied on tools the HARD CONSTRAINT prompt told
   the model not to use.

This directory holds the runtime smoke harness that exercises each converted
agent against a real LLM backend and asserts it produced text without
dispatching tools.

## Files

```
tests/track_b_smoke/
  README.md          — this file
  smoke.sh           — runtime harness (POSIX sh; invokes tracker)
  lib.sh             — assertion helpers (sourced by smoke.sh; pure POSIX)
  test_lib.bats      — bats tests for the assertion helpers
  test_smoke.bats    — bats tests for smoke.sh workdir lifecycle (uses
                       PATH shim; no real tracker invocation)
```

## How to run

### Assertion-helper unit tests (free, no LLM calls)

```sh
bats tests/track_b_smoke/
```

21 tests across two files:

- `test_lib.bats` (17) — exercises every helper in `lib.sh` against
  synthetic `.tracker/runs/<rid>/` directories, including regression guards
  for nested `tool_call_start` payloads, node IDs with regex metacharacters,
  and symlinks under `runs/`.
- `test_smoke.bats` (4) — uses a PATH shim to stand in for `tracker` and
  covers the workdir lifecycle: removed on success, retained on failure
  (with `tracker.stdout`/`tracker.stderr` dumped to stderr), and forced
  retention via `TRACK_B_SMOKE_KEEP=1`.

Required tooling: `bats`. No tracker / no API keys.

### Runtime smoke probes (real LLM calls)

```sh
# Cheapest probe — exercises the converted Exit agent in
# sprint/verify_sprint.dip via a fail-fast Start. ~1 LLM call.
tests/track_b_smoke/smoke.sh verify

# Cheap probe — exercises the converted Exit agent in
# sprint/verify_sprints_runner.dip via a no-ledger fail-fast. ~1 LLM call.
tests/track_b_smoke/smoke.sh verify-runner

# Sprint-exec family — exercises the converted Start + Exit agents in
# sprint/sprint_exec_yaml_v2.dip. Pre-seeds an all-completed .ai/ledger.yaml so
# FindNextSprint short-circuits to `all-done` and the workflow exits without
# entering the implementation lane. ~2 LLM calls.
tests/track_b_smoke/smoke.sh verify-sprint-exec

# Sprint-runner family — exercises the converted Start + Exit agents in
# sprint/sprint_runner_yaml_v2.dip via a no-ledger fail-fast. Routes through
# no_ledger_exit -> Exit. ~3 LLM calls.
tests/track_b_smoke/smoke.sh verify-sprint-runner

# Greenfield family — exercises the converted Start + Exit agents in
# greenfield/greenfield_synthesis.dip via a no-l1-summary fail-fast (no
# workspace/raw/l1-summary.yaml seeded). ~2 LLM calls.
tests/track_b_smoke/smoke.sh verify-greenfield
```

Required: `tracker` on `$PATH`, valid `ANTHROPIC_API_KEY` (or whichever
provider `tracker setup` selected). Observed per-invocation cost against
Claude Sonnet **assuming tracker#366 is fixed** (while the regression is
live, the converted agent runs with full tool access and the observed cost
per probe may exceed these):

- `verify` / `verify-runner`: ~$0.001 (Exit-only, one LLM call)
- `verify-sprint-exec`: ~$0.005 (Start + Exit, two LLM calls)
- `verify-greenfield`: ~$0.003 (Start + Exit, two LLM calls)
- `verify-sprint-runner`: ~$0.07 — the no_ledger_exit node is a
  tool-enabled agent on the short-circuit path and dominates the cost;
  Start + Exit themselves stay in the cheap band

Each probe hermetically copies the pipeline into a temp workdir and asserts
on the resulting `.tracker/runs/<rid>/` artifacts.

### Heavier probes (not implemented as auto-runners)

The remaining families need a real seed (a sprint to execute, a spec to
synthesize) and run to completion across many LLM nodes. They are NOT
implemented in `smoke.sh` because:

- The smoke value is in exercising the converted agent under a realistic
  catalog, not in re-running expensive pipelines.
- Per-family seeds belong to the operator's environment, not this repo.

Documented operator procedure per family:

| Family | Pipeline | Seed | Converted nodes to assert |
|---|---|---|---|
| sprint (exec) | `sprint/sprint_exec-cheap.dip` | `.ai/sprints/SPRINT-001.md` + `.ai/ledger.tsv` (sprint with trivial DoD) | `Start`, `Exit`, `GateCheap` |
| sprint (runner) | `sprint/sprint_runner_yaml_v2.dip` | `.ai/sprints/` populated | `Start`, `Exit` |
| greenfield | `greenfield/greenfield_synthesis.dip` | `workspace/raw/`, `workspace/public/` populated | `Start`, `Exit` |
| greenfield (orchestrator) | `greenfield/greenfield.dip` | greenfield discovery output | `Start`, `Exit` |

After the operator runs one of these by hand, the same `lib.sh` helpers
apply against the resulting `.tracker/runs/<rid>/`:

```sh
. tests/track_b_smoke/lib.sh
run_dir=$(track_b_run_dir .)
for node in Start Exit; do
  track_b_assert_node_reached "$run_dir" "$node" || true
  track_b_assert_response_exists "$run_dir" "$node"
  track_b_assert_no_tool_calls_in_response "$run_dir" "$node"
  track_b_assert_no_tool_events_in_activity "$run_dir" "$node"
done
```

## Current status

**`verify` and `verify-runner` probes FAIL on `main` against tracker
v0.35.1.** The smoke harness is correctly identifying the regression issue
#19 was filed to catch — see [2389-research/tracker#366][tracker366].

Root cause: tracker's dippin adapter never propagates the top-level IR field
`cfg.ToolAccess` into the per-node `attrs["tool_access"]` map, so
`SessionConfig.ToolAccess` stays empty and `IsToolAccessRestricted()` returns
false. The tool registry never gets cleared. Putting `tool_access: none`
inside a `params:` block DOES propagate (the adapter reads
`extractAgentBackendAttrs(cfg.Params, attrs)`) — but dippin emits a hint
steering authors back to the top-level form. Every Track B `.dip` in this
repo uses the canonical top-level form.

Once tracker#366 lands and this repo's `tracker` pin advances, both probes
should go green without any `.dip` changes.

The `bats` assertion-helper tests are independent of this regression and pass
clean: `lib.sh` is verified on synthetic fixtures.

## Why this isn't wired into PR CI

- Each probe costs a real LLM call (~$0.001-$0.01 each on the cheap path,
  $0.10-$10 on the heavier procedures). Squad-review consensus on issue #19
  was: smoke testing belongs out of band of the PR gate.
- The regression caught by `verify` / `verify-runner` is an upstream tracker
  bug, not a Track B regression in this repo. Gating PRs on it would block
  all unrelated work until the upstream fix lands.

Operators run smoke probes by hand when changing Track B sites, when
bumping the tracker pin, or when investigating a suspected `tool_access`
regression.

## What the harness asserts

For each converted agent (the node ID is family-specific):

1. **`stage_started` event in `activity.jsonl`** — the node was actually
   reached. Without this the rest pass vacuously.
2. **`<node>/response.md` exists, non-empty** — the agent emitted text.
3. **No `TOOL CALL:` line in `response.md`** — the transcript-formatter
   marker tracker writes for every dispatched tool call.
4. **No `tool_call_start` event for the node in `activity.jsonl`** — the
   stricter check: catches the case where tracker dispatched a tool but the
   response transcript elided the marker.

All four are necessary; any one passing without the others is consistent
with a quiet regression.

## When to extend this

- New Track B conversion → add the family to the table above, document the
  seed, and (if cheap-fail-fast path exists) wire it into `smoke.sh`.
- Tracker minor-version bump → re-run `verify` + `verify-runner` to confirm
  no enforcement regression.
- New backend (claude-code / ACP / etc.) added to converted-agent surface →
  smoke against that backend with `--backend <name>`; the harness shape is
  backend-agnostic.

## Conventions matched

- Cross-workflow suite location under `tests/<name>/` (per
  `dev_loop/config/repo_conventions.md` "Testing policy") — Track B agents
  live across multiple top-level families, not just `dev_loop/`, so this
  harness sits at the repo root rather than under `dev_loop/tests/`.
- POSIX `sh`, not bash (per `dev_loop/README.md` "Scripts are POSIX sh not
  bash" and `dev_loop/config/repo_conventions.md`).
- bats tests for shell helpers (matches `dev_loop/tests/*.bats`).
- No external deps beyond tracker, bats, shellcheck, grep, sed (already in
  the dev_loop CI image).
- No mocks of LLM backends — `tracker validate` and the bats tests give
  static coverage; the runtime probes use real backends only.

[pr21]: https://github.com/2389-research/pipelines/pull/21
[pr23]: https://github.com/2389-research/pipelines/pull/23
[issue19]: https://github.com/2389-research/pipelines/issues/19
[tracker366]: https://github.com/2389-research/tracker/issues/366
