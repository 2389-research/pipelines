# Task 1 implementation report

## Result

Implemented `openclaw/agent.dip`, `openclaw/check`, and focused offline tests.
The workflow keeps planning, revision, and memory tool-free; only `Execute` has
the native tool catalog. Every task must enter `Execute` through the explicit
`Approval -> Execute` edge labeled `Approve`.

## Runtime interface

- Launch: `tracker --no-tui -w TARGET openclaw/agent.dip`
- Request gate: `Request`, freeform
- Approval gate: `Approval`; choices in order `Stop` (default), `Approve`, `Revise`
- Revision gate: `Feedback`, freeform
- Result gate: `Review`; choices in order `Stop` (default), `Next task`
- Failure gate: `Problem`; choices in order `Stop` (default), `New request`
- Offline check: `sh openclaw/check`
- Check help: `sh openclaw/check --help`

The shared agent defaults are `glm-5.3` through `openai-compat`. Every agent
declares `backend: native`. `Propose` and `RevisePlan` have eight-turn limits,
`Execute` has 80, and `Remember` has six. The graph allows 40 restarts and uses
`retry_policy: none` without a `max_retries` override.

`Propose` and `RevisePlan` are goal gates so a missing or malformed `STATUS`
verdict fails closed. Their failure path reaches `Problem`; its human choices
explicitly resolve or discard the failed planning gate. `Execute` failures go
through `Remember` and then `Review`, so another attempt needs a new request and
approval. Hard provider or handler failures may stop directly, as Tracker does
not convert every runtime error into an outcome edge.

Tracker automatically stores human and agent responses under `response.<Node>`.
The prompts use `response.Request`, `response.Feedback`, `response.Remember`,
and `response.Execute` without declared writes or JSON extraction. Full fidelity
preserves the checkpoint context; resume degrades it to `summary:high`, which
still retains all keys. Declarative `reads:` were omitted because Dippin 0.72.0
incorrectly reports Tracker's automatic keys as DIP112 warnings. This keeps the
required zero-warning check without duplicating state.

## TDD evidence

Red, before `openclaw/agent.dip` existed:

```text
$ sh openclaw/check
error: open /Users/harper/Public/src/2389/pipelines-openclaw/openclaw/agent.dip: no such file or directory
exit 1
```

The provider test was changed before the runtime identity change and failed
against the old Anthropic identity:

```text
$ sh openclaw/tests/graph.sh
validation passed
exit 1
```

Green after implementation:

```text
$ sh openclaw/check
validation passed
ok - parsed routes, safe defaults, and agent bounds
ok - real Tracker gates default to stop, reject bad input and EOF, and resume
exit 0
```

## Coverage

`tests/graph.sh` runs real Dippin validation, zero-warning checking, and all-path
simulation plus Tracker validation. It checks the only parsed incoming route to
`Execute`, revision and failure paths, next-task reapproval, safe edge ordering
and defaults, planning-gate overrides, model/provider inheritance, explicit
native backends, tool access, turn/restart bounds, response-key references, and
the no-retry policy.

`tests/gates.sh` runs the real Tracker console handler in isolated temporary
workdirs with an isolated `XDG_STATE_HOME`. Its provider-free fixture verifies
explicit Stop, EOF selecting the safe choice default, invalid choice rejection,
missing freeform input rejection, saved checkpoints, and successful resume. It
contains no fake agent and does not contact a target repository.

## Fresh-eyes review

Reviewed five implementation/test files for authorization bypasses, unsafe shell
input, unbounded loops, misleading task status, resume state, and failure routes.
Two issues were found and fixed:

1. The tool-access assertion counted planner declarations but did not prove
   `Execute` remained tool-enabled. It now checks the per-agent mapping.
2. The safe-default gate test used `--auto-approve`; it now closes real console
   stdin after the freeform request and proves the choice gate selects Stop.

The failed Anthropic live attempt exposed invalid configured credentials before
execution. A real native no-tool probe through the configured Lunaroute
`openai-compat` provider succeeded, so the shared model/provider default changed
to `glm-5.3` / `openai-compat`. The parent task owns the complete live workflow
suite and its evidence.

## Known limits

- Approval governs the task prompt, not each tool call. `Execute` receives the
  native tool catalog after approval.
- Tracker resume is checkpointed, not exactly once. An interrupted side effect
  must be inspected before an execution-node resume; the prompt states this.
- A hard provider/configuration failure can terminate without reaching a human
  gate. Normal planning and execution outcomes have explicit human paths.
