# Single-kata pipeline plan

Goal: claim the next ready, unowned kata item in the target repository and
complete only that item through tracker. Stop after one item.
Candidates with open children are excluded before claiming; keep Kata's
priority order among the remaining ready, unowned items.

Design: deterministic selection and claim; one agent scopes the item and
implements it with TDD, writing a small plan only when needed. Two models
review in parallel using fresh-eyes checks. Allow at most one repair pass
and close with evidence only after approval. Failed work stays open with
a needs-review handoff.
An empty queue is a clean no-op; claim races stop without selecting again.
Create a fresh task branch for each claimed item. For GitHub repositories,
start from the fetched default branch, which must carry the committed
`.kata.toml` binding (`claim-next.sh` refuses a base without it: the checkout
would drop the binding and strand the claim), and publish a PR after review,
before closing the kata. For other repositories, start from current HEAD and finish
locally. Preserve existing branches and never merge automatically. Locally
exclude tracker artifacts. Keep runtime state under .tracker, bind the selected
full issue identity and workspace,
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

Turn-limit update (2026-09-13): the live run exhausted Implement's 30-turn
ceiling after about 15 investigative turns, then implementation and a passing
`make check`, before recording evidence and committing. Doctor Biz requested
much larger limits: Implement 300, Repair 150, and each of the four review
nodes 100. These ceilings allow the full implementation and review workflow
to finish; they are not turn targets. Bound discovery to the selected item's
contract and relevant code while preserving the full acceptance criteria,
one-item scope, and single repair pass. Worker prompts now target three turns
for initial discovery, preserve partial work on resume, keep the saved branch,
and move directly from passing checks to sanity review, evidence, and commit.
Fresh-eyes review found and corrected misleading integration wording; the
pipeline leaves integration to the operator. The graph contract failed against the
old limits before the configuration changed; `./kata/check` then passed,
including graph routes, shell guards, real tracker preflight, and ShellCheck.
The known static runtime-context warning remains. A full live completion
under the larger ceilings has not yet been verified.

Recovery update (2026-09-13): ordinary resume re-entered Handoff because the
active repository-local checkpoint had advanced past Implement. A stale copy
under ~/.local/state/tracker still named Implement; its fresh activity log
did not make that checkpoint authoritative. Recovery must inspect the local
checkpoint and account for its saved route, not infer the next node from logs.
The retry-implementation command is limited to a first implementation turn-limit
handoff before reviews. It verifies the claim and Git state, backs up the
checkpoint, restores the claim prompt context, and clears failed worker routing
without changing the selected issue or source files. Operator invocation gives
the worker another attempt; automatic repair and review bounds remain unchanged.
Regression checks failed before the helper existed and when hidden review
history was accepted, then passed after implementation and guard fixes.
Canonical kata/check and ShellCheck pass. Fresh-eyes review tightened the
refusal of legacy gate and memo state. Live recovery backed up the actual
checkpoint and preserved all source and selected-state hashes; tracker then
resumed Implement through Lunaroute instead of repeating Handoff.

Live completion verified (2026-09-13): recovered run 9a3759fbecae completed
in 3m46s. Implement committed 510d313; both model reviews approved without a
repair pass, SHA-bound closure succeeded, and todo-test#tzrg is closed with
a clean working tree. This verifies one real item through recovery and closure.

No live issue may be created just for testing. Live model execution is a
separate validation layer from graph simulation; report any untested layer.

Selection update (2026-09-13): mux run 8cb3219a7812 claimed parent epic x3hz
with open children. The worker correctly stopped without source changes.
Kata v0.17.2 ready/next excludes open blocks predecessors but does not exclude
open-child parents. Ready results include child_counts, so filter them before
the single claim attempt and preserve next's lowest-explicit-priority ordering
(unset priorities last; received order breaks ties). An all-parent queue is
a no-op; claim races still stop without trying another candidate.
Regression tests reproduced the parent selection and a file-path assumption
under tracker-style inline execution. The selector now lives in claim-next.sh;
all selection tests execute its contents through sh -c. Canonical kata/check,
ShellCheck, and fresh-eyes review passed. A read-only check against Mux's live
ready queue skipped x3hz and chose ac2b. The mistaken epic claim was released
with an expected-owner guard after verifying no source changes or commits;
the checkout returned to main. No replacement issue was claimed in this check.

Branch and PR update (2026-09-14): every confirmed claim creates a fresh kata
branch. GitHub repositories start from their fetched default branch, after a
check that it carries `.kata.toml` (added 2026-09-17: a binding that exists
only locally vanishes from the checkout and strands the claim); other
repositories start from current HEAD. GitHub identity and base are saved before
worker execution. After both reviews approve, closure pushes only that approved
commit, creates or reuses an open PR, verifies its head and base, and records its
URL before closing the kata. Publication failures leave the claim open with a
handoff. Setup and publication each allow five minutes for network operations.
Saved runs without publication metadata require inspection and recovery.

Regression tests reproduced feature-branch reuse, the wrong base, implicit
GitHub host selection, and publication failures. Independent review also found
inconsistent slash-containing remote names and unintended annotated-tag pushes.
The tests use real temporary Git repositories with GitHub/Kata CLI fixtures;
they do not claim live GitHub end-to-end coverage. No practice issue or PR was
created. A live kata-to-PR run remains the next validation layer.
Final `./kata/check` and `git diff --check` passed, including graph validation,
ShellCheck, real tracker preflight, setup, publication, and recovery tests.
Fresh-eyes review is complete; both remote-name and tag-scope findings are fixed.
Removing the tag guard in an isolated copy reproduces its regression failure.
