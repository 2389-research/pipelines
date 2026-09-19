# OpenClaw-style agent with human gates

Doctor Biz approved bounded-task approval on 2026-09-19 (option A).

## Behavior

One DIP workflow runs a persistent conversation: request, propose, approve,
execute, remember, review, next request. A proposal states the objective,
permitted actions and targets, exclusions, and evidence needed for success.
The human can stop, revise the proposal, or approve that one task. Results
return to a human gate before another task can run. Follow-up work requires
a new proposal and approval.

Planning and memory agents use `tool_access: none`. Only Execute has tools.
Discovery that requires tools is itself an approved task. Tool access after
approval is governed by the task prompt, not a per-command sandbox; the README
must state this limit. No background daemon, messaging integration, or scheduler
is part of this workflow.

## State and failures

Tracker checkpoints and node response keys are the source of session state.
A bounded memory summary carries goals, decisions, completed work, evidence,
and unfinished work between tasks. New runs start fresh; `--resume` continues
the existing session. There is no second application state store.

Choice gates put Stop first and default to Stop. Freeform input has no default.
Planning failures return to a human gate without reaching Execute. Execution
failures report partial work and require fresh approval before another attempt.
Hard provider errors and billing pauses may halt Tracker directly instead.
Execute is a goal gate so a missing STATUS marker cannot become success.
Choosing Stop after a failed task ends the run with a nonzero exit; Next task
clears the failed gate through the Request restart and requires fresh approval.
Execution reports restate approved scope, and memory treats the original
request as historical when a revision superseded it.
Use `retry_policy: none`, because this Tracker version drops `max_retries: 0`
in the DIP adapter. Bound model turns and conversation restarts. Do not retry
an interrupted side effect blindly; document inspection before execution-node
resume. Use full fidelity to preserve response state. Reference the built-in
response keys directly in prompts; Dippin 0.72.0 flags `reads:` declarations for
those automatically populated keys as unwritten. Do not invent JSON writes to
satisfy that lint rule.

The working provider is the existing Lunaroute `openai-compat` configuration.
Planning, revision, and memory use `deepseek-4.1-flash`; Execute uses `glm-5.3`.
Real probes established this configuration after the configured Anthropic
endpoint rejected its key. Proposals stay under 200 words and memory under
500 words by instruction.

## Verification

Use Tracker 0.73.1 and Dippin 0.72.0, matching repository CI. Write failing
graph and gate tests before the workflow. Cover the only path into Execute,
safe defaults, revision, failure handoff, memory, and bounded loops. Run real
Tracker gates without model calls where possible; live end-to-end tests use
the real configured provider in temporary workspaces and verify actual files,
approval, revision, a second task, and gate resume. No mocked end-to-end models.
Run structural validation, shellcheck, and the repository-wide DIP check.

## Deliverables

- `openclaw/agent.dip`: the workflow.
- `openclaw/check` and `openclaw/tests/`: repeatable local verification.
- `openclaw/README.md`: launch, approval scope, state, recovery, and limits.
- Root README and changelog entries; a focused CI check.

## Review

Scope checked: one workflow using existing Tracker facilities, no new runtime.
The approved gate policy is the architectural decision; ordinary implementation
details proceed under the existing build request.
