# roborev drain budgets

## Now
- Step: implement option 2 tasks 1-6 with TDD on `feat/roborev-drain` (implementer subagent)
- Next: one independent review pass, then report to Doctor Biz
- Open: none
- Approved: "2" (2026-09-25): option 2, keep the queue loop in one run
- Withdrawn: Doctor Biz picked "a" (raise the limits to 400 restarts and 24h), then withdrew it: "but wait. isnt that a pipeline weakness that shoukd br solved in thr pipeline" and "not a hack" (2026-09-25)
- Compactions: 0

## Problem

A drain runs the whole queue inside one Tracker run, and two budgets grow with
the queue:

- The queue loop restarts QueueContext once per review. Tracker caps restarts
  per target at `max_restarts` (40), so one run handles at most 40 reviews and
  fails with `max restarts (40) exceeded` on the next. Footwork has 40 open.
- `max_wall_time: 4h` covers every review in the run.

The same `max_restarts` also caps each review's repair loops (ImplementFix,
SnapshotReview) at 40 apiece, far looser than one review needs.

## Tracker 0.76.0 facts (read at tracker@29cbb38c)

- Any loop-back is a restart, with or without `restart: true`
  (`docs/architecture/engine.md`, Restart).
- `max_restarts` is a graph attribute, enforced per resolved restart target
  (#603). Restarting a loop header resets the budgets of loops nested inside it
  (#643, `pipeline/engine_restart_scope.go`).
- "the outermost loop's `max_restarts` is the run-wide bound the author must
  size" (engine.md); `build_product.dip` and `kata/board.dip` both use 200.
- A subgraph runs a child engine with its own restart counts, but
  `buildSubgraphChildEngine` (`pipeline/subgraph.go`) sets no artifact dir and
  no checkpoint. The kata board scrubs its body's node dirs from the workspace
  root (`gotchas.md`); here CommitFix's `git add -A` would commit them.
- BudgetGuard checks `max_wall_time` between nodes, and a child engine shares
  its parent's guard.

## Options

1. **One review per run (recommended).** The pipeline takes one review through
   its repair chain and ends; `drainrev.sh` runs it again until no eligible
   review remains and stops at the first failed run. Every Tracker budget then
   belongs to one review: `max_restarts` caps that review's repair attempts and
   `max_wall_time` its clock. DeferCurrent records deferred ids in the repo's
   `.tracker/roborev/deferred`, so later runs skip them. No number grows with
   the queue, and each review gets its own run dir, logs, and `tracker -r`.
2. **Keep the queue loop in one run.** Tracker still needs a cap on the
   outermost loop, so the pipeline counts reviews itself and ends cleanly with a
   report at a `max_reviews` param set below `max_restarts`. A per-review
   attempt counter in the state dir bounds repair loops, and the run-wide clock
   goes. Another run continues the queue.

## Option 2 tasks

Follow Tracker's own `examples/build_product.dip`: on-disk counter gates placed
before the work bound each item's loops, and `max_restarts` is only the
engine's backstop ("not by starving this ceiling"). `marker_grep` takes the
last matching line (`pipeline/handlers/tool.go` `extractToolMarker`), so a
tool may print feedback before its marker. Tool commands may interpolate
`${params.*}` (workflow `vars`, overridable with `--param`) and `${graph.*}`
(`max_restarts` is a graph attr); `${ctx.*}` except a safe list, and
`${inputs.*}`, are refused (`pipeline/expand.go`). No shell `${...}` in a
command may contain a dot (`gotchas.md`).

All work is in `roborev/`: TDD, then `sh roborev/check` and the pinned
`dippin check` (v0.72.0) must pass.

1. **Params and clock.** Add `max_reviews: 30` and `max_repairs: 3` to `vars`;
   keep `max_restarts: 40`; delete `max_wall_time` (no run-wide clock:
   `pipeline/budget.go` skips the check at 0). Preflight validates first,
   before touching anything: both params are positive integers and both are
   below `${graph.max_restarts}`, else marker `invalid_params` (logged with the
   reason). Preflight also writes `0` to `selected-count` and `repair-attempts`.
2. **Review cap.** RecordSelection, on `selected`, increments `selected-count`,
   writes `0` to `repair-attempts`, and empties `verify.log` and `commit.log`
   so no feedback leaks between reviews. QueueContext checks first: when
   `selected-count` >= `max_reviews` it prints `review_cap` without calling
   roborev; edge `QueueContext -> FinalContext when ctx.tool_marker = review_cap`.
   FinalContext adds a `--- REVIEW CAP ---` block (`selected: N`,
   `max_reviews: M`, `cap_reached: yes|no`). FinalAudit's criteria gain: with
   `drain_queue == true`, stopping at the cap with reviews still open is
   success. DEFERRED must still be empty.
3. **Repair budget.** New tool `RepairBudget` is the only way into ImplementFix
   (`repair` -> ImplementFix, `exhausted` -> DeferCurrent, anything else ->
   Abort). Every edge that led into ImplementFix now leads into RepairBudget,
   restart flags unchanged: RouteTriage fix, VerifyProject verify_fail,
   NoOracleAudit fail, PatchAudit fail, RoutePatchAudit reject, CommitFix
   commit_fail. Gate before work: when `repair-attempts` >= `max_repairs`
   (or the count is unreadable) print `exhausted`; else increment and print
   `repair`. Before the marker, print the tails of `verify.log` (250 lines) and
   `commit.log` (120 lines) under headings, because ImplementFix's
   `${ctx.tool_stdout}` now comes from this node. Agent feedback still arrives
   through `${ctx.last_response}`. The count spans the whole repair chain, so
   re-review failures and no-change loops, which all pass RouteTriage, are
   bounded too.
4. **Clean tree after deferral.** DeferCurrent, when the tree outside
   `.tracker` has changes, stashes them with
   `git stash push --include-untracked -m "roborev_issue_fixer: deferred job N" -- . ':(exclude).tracker'`,
   names the stash in its roborev comment, and prints `defer_error` if the
   stash fails or the tree is still dirty. Without this, an ImplementFix
   failure or a `secret_risk` leaves edits that the next review's
   `git add -A` commits under the wrong job (already true before option 2;
   the repair budget sends more reviews down this path).
5. **Tests.** Extend `tests/graph.sh`: ImplementFix's only incoming edge is
   RepairBudget on `repair`; RepairBudget -> DeferCurrent on `exhausted`;
   QueueContext -> FinalContext on `review_cap`; no `max_wall_time` line. Run
   each changed tool command, rendered with test values for `${params.*}` and
   `${graph.*}` (sh cannot parse them raw), against stand-ins: Preflight's
   `invalid_params` cases and the existing `missing_jq` case; QueueContext
   `review_cap` without a roborev call; RecordSelection counters and log
   reset; RepairBudget `repair`, `exhausted`, and feedback before the marker;
   DeferCurrent in a scratch repo, stashing a tracked edit and an untracked file,
   keeping `.tracker/`, making no stash on a clean tree; the FinalContext cap
   block. Commits made by tests pass `-c core.hooksPath=/dev/null`.
6. **Docs.** `roborev/README.md` (Limits, Preflight, deferral stash),
   `drainrev.sh --help` (mention `--param max_reviews=N`), and the roborev
   entry in `CHANGELOG.md`.

## Verify at implementation

- That ImplementFix and SnapshotReview sit inside QueueContext's natural loop
  (look for `restart_budget_reset` events in a real run). This matters for
  option 2 only.
- How `drainrev.sh` reads each run's result (closed, deferred, no work, or
  failed) under option 1: Tracker's exit status alone may not separate them.
