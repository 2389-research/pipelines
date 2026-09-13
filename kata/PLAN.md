# Single-kata pipeline plan

Goal: claim the next ready, unowned kata item in the target repository and
complete only that item through tracker. Stop after one item.

Design: deterministic selection and claim; one agent scopes the item and
implements it with TDD, writing a small plan only when needed. Two models
review in parallel using fresh-eyes checks. Allow at most one repair pass
and close with evidence only after approval. Failed work stays open with
a needs-review handoff.
An empty queue is a clean no-op; claim races stop without selecting again.
Create a task branch when starting on the default branch; preserve existing
work and never push or merge. Locally exclude tracker artifacts. Keep runtime
state under .tracker, bind the selected full issue identity and workspace,
and require a clean target tree apart from runtime artifacts before changes. Scope containment is
workflow discipline, not an OS security sandbox.

Review roles: correctness (acceptance criteria, regressions, error paths,
tests) and scope (unnecessary changes, maintainability, security risks).
Both must approve. No standing extra squad or unconditional planning stage.

Files: complete.dip, shared prompts/scripts only where they avoid duplication,
README.md, and a named check command with graph and real-command checks.
Use installed kata help/quickstart and local tracker/dippin sources as the
API contract. Avoid adding an application framework or a queue runner.

- [x] Write failing routing/preflight checks.
- [x] Implement the smallest workflow and helpers that pass them.
- [x] Validate with matching dippin/tracker; exercise success and failure paths.
- [x] Review scope, claim/closure handling, retry bounds, and documentation.
- [x] Commit the contained directory and root README entry.

Before the Lunaroute switch, `kata/check` passed with tracker v0.66.0 and
Dippin v0.68.0. It checked parsing/lint, concrete simulated routes, real Git
evidence guards, CLI contract fixtures, and real tracker preflight rejection. Independent
fresh-eyes review approved after fixes. Initial validation did not make live
model calls.

Provider update (2026-09-13): Doctor Biz chose the configured Lunaroute gateway
through `openai-compat`. Worker, repair, and correctness reviews use `glm-5.3`;
scope reviews use `deepseek-4.1-flash`. The graph contract requires all six
agents to use the compatible provider and two distinct models. The adapter
does not forward `reasoning_effort`, so those attributes were removed.
The updated graph contract failed on the old provider configuration, then
`./kata/check` passed after the switch, including ShellCheck and real tracker
preflight checks. The existing static runtime-context warning remains.
The current pipeline requires the validated tracker v0.73.1 / Dippin v0.72.0
toolchain. Dippin v0.68.0 lacks `openai-compat` lint support: its six DIP108
unknown-provider warnings fail the check. No warnings were suppressed.
Resume an authentication failure after claim with the same run ID and pipeline
to retain the selected issue and actor.

Live provider validation: the configured `/models` endpoint lists both models.
Installed tracker completed a separate smoke workflow through `openai-compat`:
each model took two turns and made one real file-read tool call (run
`8a94c566bfe4`). This verifies authentication and tool calls; a full live kata
completion remains untested.

No live issue may be created just for testing. Live model execution is a
separate validation layer from graph simulation; report any untested layer.
