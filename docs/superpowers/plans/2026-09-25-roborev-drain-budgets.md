# roborev drain budgets

## Now
- Step: Doctor Biz chooses how `roborev/roborev_issue_fixer.dip` bounds a drain (options below)
- Next: implement the chosen option with TDD on `feat/roborev-drain`
- Open: option 1 or option 2
- Approved: none. Doctor Biz picked "a" (raise the limits to 400 restarts and 24h), then withdrew it: "but wait. isnt that a pipeline weakness that shoukd br solved in thr pipeline" and "not a hack" (2026-09-25)
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

## Verify at implementation

- That ImplementFix and SnapshotReview sit inside QueueContext's natural loop
  (look for `restart_budget_reset` events in a real run). This matters for
  option 2 only.
- How `drainrev.sh` reads each run's result (closed, deferred, no work, or
  failed) under option 1: Tracker's exit status alone may not separate them.
