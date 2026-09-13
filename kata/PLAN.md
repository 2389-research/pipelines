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

Validation: `kata/check` passes with tracker v0.66.0 and dippin v0.68.0.
It checks parsing/lint, concrete simulated routes, real Git evidence guards,
CLI contract fixtures, and real tracker preflight rejection. Independent
fresh-eyes review approved after fixes. No live model completion was tested.

No live issue may be created just for testing. Live model execution is a
separate validation layer from graph simulation; report any untested layer.
