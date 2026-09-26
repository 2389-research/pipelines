# roborev

A headless repair loop for [roborev](https://github.com/kenn-io/roborev) findings.

| File | Purpose |
|------|---------|
| [`roborev_issue_fixer.dip`](roborev_issue_fixer.dip) | Re-check each open review's findings against the code, repair the valid ones, verify, audit, commit, wait for roborev's re-review, and close what it resolves. |
| [`drainrev.sh`](drainrev.sh) | Run the pipeline on a repository's current branch until its roborev queue is empty. |
| [`check`](check) | Offline graph, audit-verdict, `drainrev.sh`, and shellcheck tests. Calls no model and no roborev daemon. |

## Run

```sh
roborev/drainrev.sh [repo] [tracker flags...]
```

`repo` defaults to the current directory, and the pipeline runs on its root.
Flags after `repo` go to tracker and win over the defaults: `--no-tui`, or
`--param review_id=42 --param drain_queue=false` to fix one review.
`drainrev.sh` resolves symlinks, so a link on your `PATH` works.

The pipeline's Preflight validates `max_reviews` and `max_repairs` before
touching the repository — both must be positive integers below
`max_restarts`, else the run stops with `invalid_params` — then stops unless
`roborev` and `jq` are on `PATH`, the tree is clean (tracker's own
`.tracker/` aside), HEAD is on a named branch, `git var GIT_AUTHOR_IDENT`
succeeds, and `roborev list` reaches the daemon. Queue snapshots use `jq` to
pass agents each review's id, commit, branch, status, and verdict, never
roborev's stored review prompt.

Agents run `deepseek-4.1-flash` through `openai-compat`, so tracker needs
`OPENAI_COMPAT_API_KEY` and an `OPENAI_COMPAT_BASE_URL` that points at
LunaRoute (`tracker setup`, or `~/.config/tracker/.env`). `check` passes with
tracker 0.76.0 and dippin 0.76.0, `dippin check` also passes under the repo's
CI pin (dippin 0.72.0), and the roborev commands match the 0.69.0 CLI.

## Limits

- No token cap: `--max-tokens` defaults to 0. `--max-cost` never trips, because
  tracker prices `openai-compat` models missing from dippin's catalog at $0.
- No run-wide clock: operators can still bound one with `--max-wall-time`.
  `max_reviews` (default 30) ends the run cleanly at a review boundary once
  that many reviews have been selected; run `drainrev.sh` again to continue
  with the rest of the queue. `max_repairs` (default 3) bounds each review's
  repair loop; past it, the review is deferred instead of repaired further.
  Both must stay below `max_restarts: 40`, which remains the engine's own
  backstop, and every agent still carries a `max_turns`.
- A deferred review's uncommitted edits (outside `.tracker`) are stashed with
  `git stash push --include-untracked`; the roborev comment on that review
  names the stash message and `stash@{0}` so a human can find and recover it.
- Quitting tracker 0.73.1's TUI cancelled the run it was showing (see
  [`gotchas.md`](../gotchas.md)).

## Commit gate

Tracker counts a missing STATUS line as success on agents that are not goal
gates. PatchAudit therefore writes `AUDIT: approve` or `AUDIT: reject`, and
RoutePatchAudit checks that line before anything reaches CommitFix. An audit
that fails goes back to ImplementFix; one that succeeds without a valid line
aborts the run. `tests/graph.sh` pins those routes and runs the parser against
sample replies.

`dippin check` reports two expected warnings, DIP101 and DIP102: Abort reaches
Done only on a fail outcome, so an Abort that claims success never exits as a
pass.
