# Pipeline notes

For the kata pipeline, Doctor Biz chose next ready, unowned selection,
exactly one item per run. Planning stays within that item. Reviews emulate
fresh-eyes checks with two different models and distinct expert roles.

Never create practice issues to probe kata. Inspect CLI help, source, or
existing records read-only. Isolate test state from the real daemon.

Kata runs may start on main in a repository without tracker ignore rules.
Prepare local artifact exclusions and a task branch automatically; preserve
unrelated uncommitted work and report its paths. Keep preflight failures on
ClaimNext rather than masking them with a generic Stop node.

Doctor Biz wants kata agents routed through the configured Lunaroute gateway
using `openai-compat`: `glm-5.3` for worker/repair/correctness and
`deepseek-4.1-flash` for scope. After post-claim authentication failures, resume
the saved run with the same pipeline to preserve its claim; do not start over.

Doctor Biz wants much larger kata turn ceilings so checks, evidence, and
commits can finish: implementation 300, repair 150, each review 100. Bound
discovery to relevant code; do not narrow the selected item's goal to fit a cap.

Tracker resume continues at the saved node, including a terminal Handoff.
After an implementation turn-limit failure, use kata/retry-implementation to
back up and rewind only the failed worker state while retaining its claim.
Check the repository-local checkpoint: tracker v0.73.1 can write fresh logs
under ~/.local/state/tracker while leaving a stale checkpoint copy there.

Live recovery and completion passed for todo-test#tzrg on 2026-09-13: both
model reviews approved commit 510d313, closure succeeded, and the tree was clean.

Kata ready/next may return parent epics with open children: parent links do
not count as blocking predecessors. Filter ready results by child_counts.open
before claiming. Preserve explicit priority order (unset last, received order
for ties), and never try another claim after losing an ownership race.

Doctor Biz wants a fresh branch for every claimed kata and a PR when GitHub
is configured. GitHub tasks start from the fetched default branch; local-only
tasks start from current HEAD. Publish only the SHA approved by both reviewers,
reuse a matching open PR, and leave the kata open if publication fails.

Doctor Biz chose stacked branches and PRs for whole-board runs, leaving merging
to the operator. Each kata uses the previous approved task as its base. Tracker
0.73.1 native subgraphs share run identity/artifacts, so board.dip calls separate
complete.dip CLI runs and records their IDs. Resume resolves the current child
before another claim. No ready work with open items remaining means incomplete.

Tracker 0.73.1 treats any TUI exit as a run cancel. Pressing `q` or Ctrl-C in
the TUI cancels the pipeline context, SIGKILLs the running tool's process group
(for board.dip: the controller and its child tracker), and reports the failure
as `command timed out after <node timeout>` because translateExecError labels
every ctx.Err() a timeout. Run board.dip with `--no-tui`. A killed child keeps
its kata claim, so resume the child before the board. Verified 2026-09-15 under
tmux with a sleeping nested child: `q` and Ctrl-C both reproduced the exact
board failure; the same runs left alone completed with the TUI on or off.
