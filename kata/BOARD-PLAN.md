# Kata board runner implementation plan

Goal: process the target repository's board through the existing complete.dip,
one ready, unowned item at a time. Doctor Biz chose stacked task branches and
PRs, with merging left to the operator.

Design: board.dip calls a shell controller through graph.workflow_dir. The
controller launches separate Tracker CLI runs of complete.dip, since native
subgraphs in Tracker 0.73.1 share run identity/artifacts and lack child checkpoints.
Child logs and a board ledger live under the parent run directory. Child runs
retain standard .tracker/runs locations so ordinary Tracker resume works.

Each completed child supplies a frozen branch, commit, and GitHub identity for
the next child. First items retain the normal default-branch base. Later items
fetch and verify the previous task branch, use it as their PR base, and retain
the existing reviews and closure gates. No automatic merges or force pushes.

A failed child hands its kata off for review and the board claims the next one;
three consecutive failed children, or a failure that leaves the handoff record,
checkout, tree, or kata unclean, stop the board. Recovery reconciles an existing
child before starting another, including completion after a manual child resume.
No eligible item triggers a full open-board check: zero open items means success;
remaining owned/blocked items mean an explicit incomplete-board report. A resumed
blocked board may query again. No source changes or claims for other repositories.

Constraints: source .dip only; nested Tracker reloads stored provider configuration
because tool subprocesses filter environment-only credentials. Parent budget and
token summaries do not aggregate nested CLI runs. Never create practice issues.

- [x] Add and test optional verified stack-base input in claim-next.sh.
- [x] Add board.dip and controller with durable child tracking and recovery.
- [x] Test multiple items, stacked bases, empty/blocked queues, failure and resume.
- [x] Exercise real Tracker orchestration without models using isolated tool workflows.
- [x] Run kata/check, fresh-eyes review, document usage/limits, and commit.
- [x] Hold a `Morning review` gate with no default after every sweep that leaves katas open or stops; validate the records the review pastes; isolate the tests from the operator's Git and Tracker configuration (2026-09-18).

Validation (2026-09-14): tests first failed for the absent controller and for
discarding previous task work. Real Tracker parent/child runs now verify distinct
IDs, two stacked commits, empty/blocked boards, failure propagation, manual child
resume, and no duplicate claims. Stale approvals, dirty work, changed branches,
unclosed issues, and missing closure markers prevent recovery from advancing.
GitHub stack setup tests verify the actual fetched SHA using temporary Git remotes.
Kata/GitHub boundaries use fixtures; no live board or model run was started.

Independent review found no blocking controller issues. Final fresh-eyes review
removed test-only hook suppression; the board suite passes with ordinary hooks.
The inherited crash window after Kata closure but before its checkpoint still
requires manual reconciliation. Parent budgets do not aggregate child usage.

Final verification: `./kata/check` passed after all edits, including zero-warning
Dippin checks, Tracker validation, real parent/child runs, Git integration, and
ShellCheck. `git diff --check` passed. No live kata-to-GitHub board run was made.

Gate validation (2026-09-18): real Tracker parents answer the gate both ways
(`Sweep again` twice, then `Done`), fail it on closed stdin with a checkpoint,
end after one sweep under `--auto-approve`, and hold it after a three-failure
stop and after a child integrity stop with the child's resume command in the
prompt. Every stop after the ledger exists reaches the gate; the review refuses
a child record with an unsafe id, branch, commit, or PR URL. An interrupt to the
controller reaches the child Tracker and leaves no lock or `child.pid`. The test
suite runs under a fixture `HOME`, Git configuration, and Tracker state.
`./kata/check` passes on an exported tree. No live board run was made.
