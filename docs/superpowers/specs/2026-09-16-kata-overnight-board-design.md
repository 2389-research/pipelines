# Kata overnight board — design spec

**Date:** 2026-09-16
**Branch:** `feat/kata-pipeline`
**Scope:** `kata/` in this repository. Toolchain: Tracker 0.73.1, Dippin 0.72.0, Kata 0.17.2 or newer.

## 1. Problem

`kata/board.dip` runs `complete.dip` once per kata, but it stops at the first
failed child, and a failed child leaves the checkout on its task branch,
sometimes dirty. One failure ends the night. Recovery needs a person at the
keyboard and, for turn-limit failures, checkpoint surgery with
`retry-implementation`. A turn-limit failure is the failure a second attempt
most often fixes, yet it gets no automatic retry. A worker that needs a
decision can only fail with a `needs-review` label that looks like every other
failure.

The intended use: start the board in the evening, let it work through the
queue unattended, and in the morning read one report and act on it, mostly
through an agent.

## 2. Goals and non-goals

Goals:

- A board never stops because one kata failed. It stops only for an integrity
  problem or three consecutive failed children.
- A turn-limited implementation gets one automatic warm continue inside the
  same run, with its partial work and episode memory intact.
- Failed work survives as a WIP commit on its task branch, and the checkout
  returns to the branch the claim started from.
- A kata that needs a human decision carries the exact question and its own
  label.
- The morning is one report to read and one command to hand a kata back.
- The kata tracker stays the only state store. GitHub holds the PR stack. Run
  directories hold the evidence.

Non-goals:

- No Tracker `human` gate, webhook, or daemon. A blocking gate is fake under
  `--no-tui` and a webhook gate would stall the whole board.
- No fresh-attempt retry after review rejections. The existing single repair
  pass is the one review retry.
- No merging of the PR stack. No changes to Tracker or Kata themselves.
- No automatic release of stale claims. `kata unassign` covers that by hand.

## 3. Kata states

A kata's state is its owner plus one label. Nothing else records progress.

| Owner | Label | Meaning |
| --- | --- | --- |
| none | none | ready; the next run may claim it |
| `kata-pipeline-<run>` | none | in progress |
| none (closed) | none | done; its PR is in the stack |
| `kata-pipeline-<run>` | `needs-review` | failed after the retry and the repair pass; waiting for a person |
| `kata-pipeline-<run>` | `needs-decision` | the worker asked a question; waiting for an answer |

The claim is the blocker. No run re-attempts an owned kata. A person hands it
back with `kata/answer`, which comments and unassigns. The next claim removes
either label, so a stale label never blocks anything and selection rules do not
change: ready, unowned, no open children.

## 4. Pipeline changes in `complete.dip`

### 4.1 The `ContinueImplement` node

A tool node between `Implement` and `Handoff`, `command_file:
scripts/continue-implement.sh`, timeout 10s. Tracker's native backend
classifies a turn-limit breach; steady progress with no loop yields
`ctx.turn_breach_class = operator_decision` (verified on run `6f39f64af6a2` in
the skate workspace, 300 turns). Tracker also reads a per-node turn override
from `.tracker/turn_overrides/<nodeID>` under the workspace on re-entry and
carries `episode_summaries` in context, which is how `build_product.dip` does
its warm continue.

Edges, in this order:

```
Implement -> ReviewFreshEyes    when ctx.outcome = success
Implement -> ContinueImplement  when ctx.turn_breach_class = operator_decision
Implement -> Handoff            when ctx.outcome = fail
ContinueImplement -> Implement  when ctx.outcome = success  restart: true
ContinueImplement -> Handoff
```

Order matters. Tracker takes the first matching edge in declaration order, and
`turn_breach_class` is sticky in context. The success edge comes first so a
successful re-entry after a breach goes to review, and the breach edge comes
before the fail edge so a breach reaches the continue node. A plain failure
after a continue still carries the sticky class and passes through
`ContinueImplement`, whose once-marker sends it to `Handoff`. The graph's
default `max_restarts` is 5 per target, so one restart into `Implement` is
within budget.

### 4.2 `scripts/continue-implement.sh`

Requires `TRACKER_RUN_DIR` and `TRACKER_WORKDIR`.

1. If `$TRACKER_RUN_DIR/continue-implement.json` exists, print
   `continue-exhausted` and exit 1. The run gets one continue.
2. Otherwise write `450` to `$TRACKER_WORKDIR/.tracker/turn_overrides/Implement`
   (the node's 300 plus 150; both numbers are named constants in the script
   and must match `max_turns` in `complete.dip`), write the marker
   `{"attempt":1,"max_turns":450,"run_id":...}`, print `continue-ok`, exit 0.

`.tracker/` is already in `.git/info/exclude` from the claim preflight, so the
override never reaches a commit.

### 4.3 Override hygiene

The override is keyed by workspace and node id, not by run, so a stale file
would inflate the next child's budget. `claim-next.sh` deletes
`.tracker/turn_overrides/Implement` before claiming, and both
`handoff-selected.sh` and `close-selected.sh` delete it as their last step.

## 5. Claim changes in `scripts/claim-next.sh`

- Record `start_branch` in `selected.json`: the branch name at claim time. The
  preflight already refuses a detached HEAD, so it always exists. For a board
  child with a stack base this is the stack tip branch.
- After a successful claim, remove `needs-review` and `needs-decision` from the
  issue when present (`kata label rm`, as the run's actor).
- Delete a stale turn override (section 4.3).

Selection is unchanged.

## 6. Handoff in `scripts/handoff-selected.sh`

Runs on every failure route: worker fail, second turn breach, second review
rejection, publish failure. Steps, in order:

1. **Read state.** `selected.json` gives workspace, issue, actor, task branch,
   base commit, and `start_branch`; `TRACKER_RUN_ID` gives the run.
2. **Check the checkout.** If the current branch is not the task branch, touch
   no git state: the reason is `unexpected_checkout`, steps 3 to 5 are skipped,
   and steps 6 to 8 run as written. The board then sees a `handoff.json` whose
   `start_branch` does not match the checkout and stops for inspection.
3. **Classify** the reason from run artifacts, first match wins:
   - `decision`: `$TRACKER_RUN_DIR/question.md` is non-empty.
   - `publish`: `CloseSelected/status.json` exists with outcome `fail`.
   - `review`: any review or re-review `status.json` exists and no `close-ok`.
   - `turn_limit`: `Implement/status.json` has outcome `fail` and
     `turn_breach_class = operator_decision`.
   - `implement`: anything else (the worker returned `STATUS: fail`).
   The label is `needs-decision` for `decision`, else `needs-review`.
4. **Preserve.** If `git status --porcelain --untracked-files=normal` is
   non-empty, commit everything on the task branch:
   `wip(kata): <qualified_id> handoff from run <run_id>`. The claim refused a
   dirty tree at the start, so everything dirty now belongs to this attempt.
   Nothing is pushed on failure.
5. **Restore.** `git switch <start_branch>`. The task branch stays local.
6. **Label and comment**, as the run's actor: add the label; post
   `handoff.md` (or the current default text) followed by a footer:
   `Branch: <branch> (base <base_commit>, wip <wip_commit or none>)`,
   `Run: <run_id>`, and `Question:` with the question when present.
7. **Record** `$TRACKER_RUN_DIR/handoff.json` last, because the board treats
   its presence as proof the handoff finished:
   `{run_id, issue_uid, qualified_id, reason, label, branch, base_commit,
   wip_commit, start_branch, question}` with `wip_commit` and `question` null
   when absent.
8. Delete the turn override, print `handoff-ok`, exit 1.

If a kata command fails in step 6 the script exits before step 7. The checkout
is already restored, `handoff.json` is missing, and the board stops for
inspection rather than recording a clean failure.

## 7. Board changes in `scripts/run-board.sh`

After each child ends the controller sorts it into one of four outcomes:

- **Completed**, exactly as today. The stack tip advances.
- **Empty**, as today.
- **Failed cleanly**: `$child/handoff.json` parses; `Handoff/status.json`
  printed `handoff-ok`; the current branch equals `handoff.json.start_branch`;
  the tree is clean; when a stack base exists, HEAD equals its commit; and
  `kata show` reports the kata open and owned by `kata-pipeline-<child id>`.
  The ledger gains `{run_id, kind:"failed", issue_uid, branch, reason, label}`.
  The stack tip does not move. The loop continues.
- **Anything else** stops with today's recovery message. That is an integrity
  problem: crash, unknown run id, dirty tree, wrong branch.

Three consecutive `failed` entries at the end of the ledger stop the board.
The count is derived from the ledger, never stored separately. A completed
child resets it by construction.

`state.json` gains an optional `stop_reason` string. Both stop paths write it
(`three consecutive failed children`, or `child <id> needs inspection`). The
loop deletes it at the start of each iteration, so a resumed board clears it.
The validator accepts the new kind and field.

Exit codes: 0 when the board reaches the end of the queue, whatever the mix of
completed and failed katas. 1 only when it stopped early. Today's incomplete
board exits 1 even when it merely ran out of claimable work; that changes.
`blocked.json` is still written when open katas remain.

When the board finishes or stops for three failures, the controller's last
action is `kata/board-report <board run id>`, printed to stdout, so the parent
run's tool output ends with the report. An integrity stop keeps today's
recovery message instead, because the ledger is mid-inspection. A failing
report script fails the board; a broken report must not pass silently.

## 8. The report: `kata/board-report`

```
kata/board-report [--json] [BOARD_RUN_ID]
```

Run from the target Git root. Without an id it uses the newest
`.tracker/runs/*/board/state.json` by modification time. Sources: the ledger
for run ids and kinds; each child's `selected.json`, `handoff.json`, and
`pr-url.txt`; the live `kata list --status open --limit 0 --json` for what
remains. It stores nothing.

Five groups, in this order: completed (kata, branch, PR), needs decision
(kata, question), needs review (kata, reason, branch, base, WIP commit, run),
remaining open katas that this board never started (kata, owner, labels, so a
failure left by an earlier board is visible), and the stop reason. Every failed item carries its next commands verbatim, for example:

```
Board 4cca7c4fd575 in /path/to/repo: finished
Completed (1)
  demo#5fav  kata/5fav-abc123def456  https://github.com/o/r/pull/12
Needs decision (1)
  demo#n4vr  Q: Should the CLI accept --format=json as well as --json?
             kata/answer demo#n4vr "<your answer>"
Needs review (1)
  demo#bq4e  review rejected twice; branch kata/bq4e-1fcdede0a1a2 (base 1234abcd, wip 5678ef01); run 1fcdede0a1a2
             git diff 1234abcd..kata/bq4e-1fcdede0a1a2
             kata/answer demo#bq4e "<guidance>"
Remaining open (1)
  demo#a2j0  owned by kata-pipeline-b20d9e898b16
```

`--json` prints one object: `{board_run_id, workspace, finished, stop_reason,
completed[], needs_decision[], needs_review[], remaining[]}`. Each item has
`qualified_id`, `issue_uid`, `run_id`, `branch`, `base_commit`, `wip_commit`,
`pr_url`, `reason`, `question`, `owner`, and `next` (a list of commands), with
nulls where a field does not apply.

## 9. The hand-back: `kata/answer`

```
kata/answer <issue-ref> "<text>"
```

Run from the target Git root. It shows the issue, requires status `open` and
an owner starting with `kata-pipeline-`, then runs
`kata unassign <ref> --expect-owner <owner> --comment "<text>"`. The comment is
posted under the caller's own kata identity. It refuses an empty text and any
owner that is not a pipeline actor, so it can never take a person's claim. It
prints the issue's new owner and labels.

## 10. Prompt changes in `prompts/implement.md`

Three additions, each one or two sentences:

- Decisions: when finishing this item needs a decision only a person can make,
  write the exact question to `question.md` beside `STATE_PATH`, keep the
  handoff current, and finish with `STATUS: fail`.
- Prior attempts: when the issue's comments record an earlier pipeline attempt,
  that comment names its branch and base commit. Diff that branch against its
  base and reuse what is correct. Do not switch to it.
- Continues: the run may re-enter this step after a turn limit with a larger
  budget and the earlier episode summary. Continue from the current diff.

## 11. README changes in `kata/README.md`

- Replace the stop-on-first-failure paragraph with fail-forward, the
  three-failure stop, and the new exit codes.
- Describe the automatic continue and the two labels.
- Add a "Morning review" section written for an agent: run `kata/board-report`;
  for each decision item read the question and answer with `kata/answer`; for
  each review item diff the WIP branch against its base and read the reviews
  under the child run directory, then either finish and close it by hand or
  answer with guidance; merge the PR stack oldest first; run the board again in
  the evening. The evening command is unchanged.
- Remove the `retry-implementation` section.

## 12. Retire `retry-implementation`

Delete `kata/retry-implementation`, `kata/tests/retry-implementation.sh`, their
lines in `kata/check`, and the README references. The automatic continue covers
its case, and its checkpoint checks would refuse the new graph shape. A third
attempt goes through `kata/answer`, and the fresh attempt reuses the WIP branch.
Update the `gotchas.md` entry that names the deleted test so it keeps the
`pwd -P` lesson without pointing at a missing file.

## 13. Data formats

`selected.json` adds `start_branch` (string).

`handoff.json` (child run directory):

```json
{"run_id":"1fcdede0a1a2","issue_uid":"01ARZ...","qualified_id":"demo#bq4e",
 "reason":"review","label":"needs-review","branch":"kata/bq4e-1fcdede0a1a2",
 "base_commit":"<sha>","wip_commit":"<sha or null>","start_branch":"main",
 "question":null}
```

`continue-implement.json` (child run directory): `{"attempt":1,"max_turns":450,"run_id":"..."}`.

`board/state.json`: `runs[].kind` is `completed`, `empty`, or `failed`; failed
entries carry `issue_uid`, `branch`, `reason`, `label`; optional `stop_reason`.

## 14. Error handling

| Situation | Behavior |
| --- | --- |
| Second turn breach in one run | `ContinueImplement` exits 1, run goes to `Handoff`, reason `turn_limit` |
| Worker fails after a continue (sticky class) | passes through `ContinueImplement`, marker present, `Handoff` |
| Handoff finds the wrong branch | no git changes, label and comment, exit 1, board stops |
| Kata API fails during handoff | checkout restored, no `handoff.json`, board stops |
| Three consecutive failed children | `stop_reason` recorded, board exits 1, report printed |
| Child crash or unknown run id | today's integrity stop and recovery message |
| Report script fails at the end | board exits 1 |
| `kata/answer` on a human-owned kata | refused, nothing changes |

## 15. Testing

All tests are POSIX shell in the existing style, run by `kata/check`, using the
fake kata fixture, real temporary Git repositories, and real Tracker child
processes where the board is involved.

- `tests/routes.sh`: graph simulation scenarios for one breach then success
  (reviews reached, one `Implement` restart), two breaches (exactly one
  `Handoff`), and a plain fail after a continue (one `Handoff`).
- `tests/continue.sh`: the override file holds 450; the marker makes the second
  call exit 1; the claim step removes a stale override.
- `tests/handoff.sh`: `question.md` selects `needs-decision`; each reason
  classifies from fixture artifacts; a dirty tree becomes one WIP commit; the
  checkout returns to `start_branch`; `handoff.json` has every field; the
  wrong-branch case changes no git state; exit 1 throughout.
- `tests/board.sh`: a failing child followed by a completing child (ledger
  kinds, stack tip unchanged, exit 0); three failures (stop reason, exit 1);
  end of queue with open katas remaining (exit 0); the report printed last.
- `tests/report.sh`: text and JSON from a fixture ledger and run directories,
  including the newest-board default.
- `tests/answer.sh`: refuses a human owner and empty text; calls unassign with
  the expected owner and comment.
- Remove `tests/retry-implementation.sh`. ShellCheck covers every new script.

The tests cannot prove a model finishes a kata. The final check is a live board
on a scratch repository with two small katas, run from a shell with the
Lunaroute key.

## 16. Facts to confirm during implementation

Not assumptions in the design, but details the plan must check before relying
on them:

- The exact `dippin simulate --scenario` syntax for a node context key such as
  `Implement.turn_breach_class=operator_decision`, and whether simulation
  models the sticky class.
- That Tracker evaluates the three `Implement` edges in declaration order as
  section 4.1 requires.
- `kata label rm` behavior on a label the issue does not carry, and whether
  the claim response lists the issue's labels.
- The fields `kata list --json` returns for owner and labels.
- How `goal_gate: true` and `auto_status: true` on `Implement` behave when the
  node is re-entered through the restart edge (`build_product`'s `Implement`
  sets neither).
- The `status.json` field that holds a tool node's stdout when the node has no
  `marker_grep`, which the board's `handoff-ok` check reads.
- That the codergen handler resolves `.tracker/turn_overrides` against the
  Tracker `--workdir`.
- What `tests/check.sh` asserts about turn ceilings and the README table.

## 17. Size

Roughly 40 lines for the continue script, 90 for the handoff, 20 in the claim,
60 in the board, 150 for the report, 40 for the answer helper, 60 across
prompts and README, and about 400 of tests.

## 18. Out of scope, flagged upstream

Tracker 0.73.1 labels a cancelled tool as `command timed out` and kills the
board's child when the TUI exits. Both are Tracker bugs, noted in
`gotchas.md`, and untouched here.
