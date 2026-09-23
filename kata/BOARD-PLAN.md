# Kata board runner implementation plan

Goal: process the target repository's board through the existing complete.dip,
one ready, unowned item at a time. Run it from the local branch where approved
work should land.

## 2026-09-20: board.dip is now a looping subgraph

board.dip no longer drives a shell controller. It is a native looping subgraph:
board.dip runs `board-item.dip` (complete.dip's graph plus two fail edges) once
per kata inside one Tracker run, on tracker 0.76.0. Every kata's steps now stream
to the board console as `RunKata/<Node>` events (`--no-tui --json`), which is the
whole reason for the change: the old controller ran each kata as a hidden child
process, so the board printed nothing for hours.

Preflight, RecordOutcome, and Report are tool nodes; the body's records live at
the workspace root during a sweep and are scrubbed after RecordOutcome reads
them. The durable board memory is the ledger under
`.tracker/runs/<board-run-id>/board/state.json`, the Git branches and landed
commits, and each kata's own labels and comments.

Removed with the controller — capability lost, not disabled:

- **Per-kata resume.** The body runs as a nested run whose nodes get only
  `TRACKER_WORKDIR`; there is no per-kata run directory or checkpoint, so a stuck
  kata can no longer be resumed on its own with `tracker -r <child-id>`. Resume
  the whole board run instead.
- **Per-kata restart.** One `max_restarts` budget belongs to the board run, not
  to a kata, so a single kata can no longer be restarted independently.
- **The controller's runtime health-check.** `child.pid`, `child.log`, and the
  live-process reconciliation are gone; there is no child process to watch.

`max_restarts` is now pinned per run. Tracker counts restarts once per run, so
the sweep-again after each kata and `Sweep again` at the morning review both
spend from the same budget (`max_restarts: 200` in board.dip). The run that trips
it fails with `max restarts (200) exceeded`; start a fresh board run to keep
going. tests/board.sh pins this against a two-restart probe.

Everything below describes the superseded shell controller and is kept as
history.

Design: board.dip calls a shell controller through graph.workflow_dir. The
controller launches separate Tracker CLI runs of complete.dip, since native
subgraphs in Tracker 0.73.1 share run identity/artifacts and lack child checkpoints.
Child logs and a board ledger live under the parent run directory. Child runs
retain standard .tracker/runs locations so ordinary Tracker resume works.

Each completed child lands its SHA-bound, two-model-approved commit on the
recorded trunk and returns the checkout there. The next child starts from that
advanced local tip. The controller records the landed commit and verifies the
checkout, clean tree, deleted task branch, approvals, and closed kata. The
pipeline performs no remote Git or GitHub action; pushing belongs to the operator.

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

The checklist and validation below describe the 2026-09-14 stacked-PR release
and are retained as history. They are superseded by the landing-on-close
behavior above. Current completed ledger entries contain `commit`, not a PR
URL; failures record `trunk` in their handoff. A closed kata after landing with
an incomplete switch or branch deletion stops the board for inspection.

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
