# Task 1 implementation report

This report preserves commands and output from before the tracker-claw rename.
Current workflow and check paths live under `tracker-claw/`.

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

The shared agent defaults are `deepseek-4.1-flash` through `openai-compat`, with
`Execute` overriding the model to `glm-5.3`. Every agent declares the native
backend. `Propose` and `RevisePlan` have eight-turn limits, `Execute` has 80,
and `Remember` has six. The graph allows 40 restarts and uses the `none` retry
policy without a `max_retries` override or fallback target.

`Propose`, `RevisePlan`, and `Execute` are goal gates so a missing or malformed
`STATUS` verdict fails closed. Planning failures reach `Problem`; its human
choices explicitly resolve or discard the failed planning gate. `Execute`
failures go through `Remember` and then `Review`. Stopping there leaves the run
failed without retry; `Next task` restarts at `Request`, clears the failed
execution gate, and requires a fresh proposal and approval. Hard provider or
handler failures may stop directly, as Tracker does not convert every runtime
error into an outcome edge.

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
`openai-compat` provider succeeded, so the first working revision changed to
`glm-5.3` / `openai-compat`; the later performance refinement is recorded below.
The parent task owns the complete live workflow suite and its evidence.

## Review fixes after `d44923c`

The independent review found two P2 state errors. Tests changed first and the
old workflow failed the new parsed identity/goal-gate contract:

```text
$ sh openclaw/tests/graph.sh
validation passed
exit 1
```

The fix makes `Execute` a goal gate with no fallback and keeps
`retry_policy: none`. A missing or malformed execution verdict now follows the
failed execution path and cannot be remembered as success. The parent verified
from Tracker 0.73.1 behavior that Stop after failed execution exits nonzero
without retry, while `Next task` clears the failed gate when it restarts
`Request`.

The execution prompt now requires its report to restate the approved objective,
actions, and targets. `Remember` labels the original request as historical and
treats that execution report's approved scope as authoritative; removed or
revised-away actions cannot survive as current goals or unfinished work.

A real configured-provider probe measured `deepseek-4.1-flash` at 2.3 seconds
and 293 tokens for proposal work, versus 2 minutes 58 seconds and 1,172 tokens
for `glm-5.3`. The shared planning/memory default is therefore
`deepseek-4.1-flash`; only `Execute` overrides to `glm-5.3`. Proposal and revision
responses are capped by prompt at roughly 200 words, and memory at 500 words.

Green evidence after both fixes:

```text
$ sh openclaw/check
validation passed
ok - parsed routes, safe defaults, and agent bounds
ok - real Tracker gates default to stop, reject bad input and EOF, and resume
exit 0
```

Dippin all-path simulation enumerated 66 paths and resolved the effective agent
identities as Deepseek for `Propose`, `RevisePlan`, and `Remember`, with GLM for
`Execute`; all use `openai-compat`. Dippin check reported zero warnings and
errors. Shellcheck and `git diff --check` passed.

## Known limits

- Approval governs the task prompt, not each tool call. `Execute` receives the
  native tool catalog after approval.
- Tracker resume is checkpointed, not exactly once. An interrupted side effect
  must be inspected before an execution-node resume; the prompt states this.
- A hard provider/configuration failure can terminate without reaching a human
  gate. Normal planning and execution outcomes have explicit human paths.

## Offline gate bootstrap fix after `6649255`

An empty Tracker configuration exposed that Tracker 0.73.1 constructs a native
LLM client before it runs a graph, even when the graph has no agent nodes. The
pre-fix check failed before its first human gate:

```text
$ isolated_config=$(mktemp -d); XDG_CONFIG_HOME="$isolated_config" sh openclaw/check
validation passed
ok - parsed routes, safe defaults, and agent bounds
gate test logs retained at /var/folders/.../tmp.U5aFFExTaK
exit 1

$ cat /var/folders/.../tmp.U5aFFExTaK/stop.log
error: create LLM client: no providers configured
```

`tests/gates.sh` now uses isolated XDG config and state directories, removes all
provider API keys supported by Tracker, and supplies a literal nonsecret OpenAI
placeholder key with `http://127.0.0.1:1` as its base URL. This client exists
only to satisfy Tracker startup. Before Tracker runs, the test simulates the
fixture with Dippin and fails unless the parsed event stream contains zero agent
nodes. That ordering guarantees the test cannot make a provider request; adding
an agent makes the test stop before client use. The script never reads a stored
credential.

Both ambient and caller-isolated runs passed, as did ShellCheck:

```text
$ sh openclaw/check
validation passed
ok - parsed routes, safe defaults, and agent bounds
ok - real Tracker gates default to stop, reject bad input and EOF, and resume
exit 0

$ isolated_config=$(mktemp -d); XDG_CONFIG_HOME="$isolated_config" sh openclaw/check
validation passed
ok - parsed routes, safe defaults, and agent bounds
ok - real Tracker gates default to stop, reject bad input and EOF, and resume
exit 0

$ shellcheck openclaw/tests/gates.sh
exit 0
```
