# Kata lands on close

Date: 2026-09-18
Status: design approved in conversation on 2026-09-18; spec awaiting Doctor Biz's review
Scope: `kata/` in the pipelines repository
Supersedes: the branch-and-PR publication in `kata/PLAN.md` (2026-09-14) and the
stacked bases in `kata/BOARD-PLAN.md`

## Problem

The kata pipeline never merges. Each completed kata leaves its approved commit on a
`kata/<id>-<run>` branch, and for GitHub repositories a pull request stacked on the
previous task branch. The board carries the newest completed branch forward as the base
of the next claim, but only inside one board run: the stack lives in that run's ledger,
and a fresh board run starts from whatever `HEAD` is. An overnight board builds a whole
project and every commit sits in branches nobody merged.

The stack also breaks. In tetris-cosmic on 2026-09-18, run `16bf27d061f8` (child 26 of
board `bb02b7c28f69`, with 25 completed children before it) claimed P2.13 with base
`08ec84c`, the frozen stack tip, and failed. Run `71243f52e751` reclaimed the same kata
as child 1 of a fresh board `24f6284cedcd`, whose ledger listed no completed children, so
no `KATA_STACK_BASE_FILE` reached the claim and it cut the branch from `HEAD`: `main` at
`35a3935`, a docs-only commit with no engine. Doctor Biz fast-forwarded `main` to
`08ec84c` by hand at 21:40:38. The audit in `../tetris-cosmic/tracker-audit.md` blames a
lost blocked-by edge; the run records show the stack forgetting itself between board
runs.

Both problems have one cause: the branch that should hold finished work never receives
it. When trunk is the stack there is nothing to carry forward and nothing to forget.

## Decision

A kata lands on the trunk branch when it closes. The close step, which already refuses
to close without verification evidence and two SHA-bound review approvals,
fast-forwards trunk to the approved commit, closes the kata, returns the checkout to
trunk, and deletes the task branch. The pipeline touches no remote: no fetch, no push,
no default-branch lookup, no `gh`. Doctor Biz decided each point on 2026-09-18:

- Land at the existing gate. The evidence and both approvals are the test gate; no new
  test runner.
- Land inside the close step, before the kata closes, so a failed landing leaves the
  kata open and a failed close leaves a landing that a retry finds already done.
- No remote Git actions anywhere in the pipeline. Pushing is the operator's job.
- Delete the merged task branch.
- Commit the pending `kata/complete.dip` model swap first, as its own chore commit, so
  the landing plan starts from a clean tree.

## Trunk

Trunk is the branch checked out when the run begins. The claim records it, the close
lands on it, the handoff returns to it. Nothing else names it: no config key, no
environment variable, no remote lookup.

The claim (`kata/scripts/claim-next.sh`) refuses:

- a detached `HEAD` (line 30 refuses this today with "detached HEAD cannot be prepared
  automatically"); the message becomes "check out the branch this work should land on";
- a checked-out `kata/*` branch, with the same message, so a run started from a
  leftover task branch never lands one task on another;
- a dirty tree, an existing `selected.json`, and the rest of today's guards, unchanged.

`selected.json` becomes `{issue_uid, short_id, qualified_id, workspace, branch,
base_commit, actor, trunk, issue}`. `trunk` replaces `start_branch`; `github` goes.
`base_commit` stays: it is trunk's tip at the claim, and the close step's "no task
commit" and "descends from the claimed base" checks use it. The task branch is still cut
from `base_commit` with `git switch -c`.

Gone from `claim-next.sh` (lines 82 to 185 today): the stack-base file and
`KATA_STACK_BASE_FILE`, the frozen-stack checks, GitHub remote detection and identity
checks, `gh repo view`, `git fetch`, and the `.kata.toml` base guard. A run claimed
before this change carries `start_branch` and `github` and no `trunk`; the close and
handoff steps refuse it with "selected.json has no trunk; this run predates landing on
close and needs manual inspection". No shim reads the old shape.

## Close step

`kata/scripts/close-selected.sh` keeps its name and its checks through "selected kata
is no longer open and owned by this run" (lines 16 to 38 today): workspace compared
with `pwd -P`, checkout on the task branch, clean tree, `head != base`, base an
ancestor of head, `verification.txt` present, `completion.md` at least 60 characters,
both `review-*.approved` files naming `head`, kata open and owned. Lines 39 to 112 (the
GitHub block: remote identity checks, the push, `gh pr list`, `gh pr create`, `gh pr
view`, `pr-url.txt`, `pr-body.md`) go. In their place, in order:

1. Read `trunk` from `selected.json`; refuse when it is missing (message above).
2. Refuse, changing nothing, when:
   - `refs/heads/<trunk>` does not resolve to a commit: "trunk <trunk> is missing";
   - trunk is checked out in another worktree (`git worktree list --porcelain` lists
     `branch refs/heads/<trunk>`): "trunk <trunk> is checked out in another worktree".
     A fast-forward under another worktree's feet leaves that worktree's index behind
     its `HEAD`, and the switch in step 5 would fail there too;
   - `git merge-base --is-ancestor <trunk commit> <head>` fails: "trunk <trunk> moved
     from <base_commit> to <trunk commit> since the claim; rebase the task branch on it
     and rerun the reviews". Nothing rebases automatically.
3. Land: `git update-ref -m "kata: land <qualified id>" refs/heads/<trunk> <head>
   <trunk commit>`. The old value makes it a compare-and-swap: if trunk moved between
   step 2 and now, the update fails and nothing changed. No checkout is involved, so
   the working tree stays on the task branch.
4. Close: `kata close --workspace <workspace> --as <actor> <uid> --done --message
   <completion> --commit <head> --test <evidence> --json`, as today, with the completion
   message ending in `Landed on <trunk>` instead of `Pull request: <url>`.
5. Return: `git switch --quiet <trunk>`, then `git branch --quiet --delete <branch>`.
   Trunk equals head, so the switch changes no file and the safe delete succeeds.
6. Report: `Landed <qualified id> on <trunk> at <head>` on stdout, then `close-ok`. The
   `turn_overrides/Implement` removal stays.

The re-check of branch and tree just before the close call stays, reworded from
"during publication" to "during landing".

## Handoff

`kata/scripts/handoff-selected.sh` reads `trunk` instead of `start_branch` (lines 17 to
18) and returns the checkout with `git switch -q <trunk>` (line 52). The reason
`publish` (line 35) becomes `land`. `handoff.json` becomes `{run_id, issue_uid,
qualified_id, reason, label, branch, base_commit, wip_commit, trunk, question}`.

Before labeling or commenting, the handoff checks that the kata is still open. When it
is closed, the handoff prints "kata <qualified id> is closed; the close step landed it
but did not finish; inspect <workspace>" and exits 1 without writing `handoff.json`.
The board's existing path for a failed child with no valid `handoff.json` then stops
the sweep with `child <id> needs inspection`. That covers the only way step 5 of the
close can fail after the kata closed, and a kata the operator closed by hand mid-run.

## Board

`kata/scripts/run-board.sh` stops carrying a stack. Lines 138 to 144 (`base.json`,
`KATA_STACK_BASE_FILE`) go; each child claims from trunk's current tip because that is
`HEAD` when it starts, and the board itself runs from trunk.

A completed child passes when: `selected.json` carries `trunk` (line 185 checks
`github` today); `CloseSelected/status.json` says `success` with marker `close-ok`;
the checkout is on trunk and clean; `HEAD` equals both approval files; the task branch
no longer exists; the kata is closed; the ledger does not already list the kata. Any
miss stops the sweep for inspection, as today. The ledger entry becomes `{run_id,
kind: "completed", issue_uid, branch, commit}`; `github` and `pr_url` go (lines 202 to
208). The board's line (line 210) becomes `Landed <qualified id> on <trunk> at <commit>`.

A failed child passes when the checkout is on the `trunk` named in `handoff.json`
(line 107 reads `start_branch` today) and clean. The frozen-stack `HEAD` check (lines
110 to 112) goes. Three consecutive failures still stop the board.

## Board report

`kata/board-report` drops `pr_url` from its records (lines 72, 80, 119), the
pull-request URL regex (line 89) and its clause in the refusal (lines 95 to 97: the
message names "id, branch, or commit" only), and the `no pull request` line (line 148).
A completed item prints as `- <qualified id>: landed <12 hex commit> (run <child id>)`.
The reason text for `land` is `landing failed`; `publication failed` goes.

## complete.dip

`CloseSelected`'s label becomes "Land the approved task and close the kata". The
script name, marker, timeout, and edges stay.

## Prerequisite: commit the model swap

The working tree carries an uncommitted swap in `kata/complete.dip`: Implement,
ReviewCorrectness, Repair, and ReReviewCorrectness move from `glm-5.3` to
`deepseek-4.1-flash`; ReviewScope and ReReviewScope move from `deepseek-4.1-flash` to
`glm-5.3`. This is the set that built tetris-cosmic. `kata/tests/check.sh:35` pins the
old mapping (`Scope$` to `deepseek-4.1-flash`, else `glm-5.3`), so the chore commit
flips that line too: `Scope$` to `glm-5.3`, else `deepseek-4.1-flash`. Six agents, two
distinct models, unchanged. The audit's finding that the correctness reviewer shares the
implementer's model holds under this mapping; that is Doctor Biz's call and outside
this design.

The swap is the first commit on the landing branch, cut from `main` after the board gate
review branch merges; that branch's plan forbids staging `complete.dip`.

## Error handling

| Situation | Where | Result |
|---|---|---|
| Detached `HEAD` or a `kata/*` branch checked out | claim | refused; the run fails before any work |
| `selected.json` has no `trunk` (a run claimed before this change) | close, handoff | refused with the "predates landing on close" message; nothing changes |
| Trunk branch missing, or checked out in another worktree | close step 2 | refused; the handoff's own switch to trunk fails too, so it writes no `handoff.json` and the board stops for inspection |
| Trunk moved: its tip is not an ancestor of head | close step 2 | refused naming both commits; handoff `land` keeps the branch and returns to trunk; the review lists `landing failed`; the human rebases and reruns the reviews, or lets the next sweep reclaim it |
| Compare-and-swap fails (trunk moved between check and update) | close step 3 | as trunk moved; nothing changed |
| `kata close` fails | close step 4 | trunk at head, kata open, branch kept, no marker; handoff `land` returns to trunk; a rerun of the step finds trunk at head and lands nothing twice; the human closes with the same `kata close` command |
| `git switch` or `git branch --delete` fails | close step 5 | kata closed and landed, no marker; the handoff finds the kata closed and writes no `handoff.json`; the board stops with `child <id> needs inspection`; the human switches to trunk and deletes the branch |
| Completed child ends off trunk, dirty, with the branch present, or with `HEAD` off the approvals | board | stop for inspection, as today |

## Idempotency

Rerunning the close step after any failure lands nothing twice. Before the land, every
check is read-only. After the land, trunk equals head, so the ancestor check passes and
the compare-and-swap writes the value already there. After the close, the "kata open
and owned" check refuses the rerun, which is right: the kata is done.

## Tests

Every test keeps the plan rules already in force: a fixture `kata` on `PATH`, a
disposable repository under `mktemp -d`, `kata/tests/isolate.sh` sourced first, no real
daemon or provider.

- `kata/tests/close.sh` gains: trunk fast-forwards to head, the checkout ends on trunk
  with the task branch gone, the fixture's close call carries `--commit <head>` and a
  message ending `Landed on <trunk>`, stdout carries the `Landed` line then
  `close-ok`; a trunk with a commit added after the claim is refused before any change
  (trunk unchanged, branch present, checkout on the task branch, no close call
  recorded); a fixture close that fails once leaves trunk at head, and a rerun lands
  nothing twice and closes; trunk checked out in a second worktree is refused; a
  `selected.json` without `trunk` is refused with the "predates" message.
- `kata/tests/handoff.sh` gains: reason `land` when `CloseSelected/status.json` says
  fail, the checkout back on trunk, `handoff.json` carrying `trunk`; a closed kata
  leaves no `handoff.json` and exits 1 with the "is closed" message.
- `kata/tests/board.sh`: the stacked cases become trunk cases. Two children in one
  sweep, where the second claims from the first's landed commit and the ledger lists
  both commits. A fresh board run in the same workspace claims from trunk's tip (the
  tetris-cosmic case). A completed child that ends on its task branch, or leaves the
  branch behind, stops the sweep with `child <id> needs inspection`. A failed child
  that ends on trunk and clean is recorded.
- `kata/tests/preflight.sh` gains the two claim refusals (detached `HEAD`, `kata/*`
  branch).
- Delete `kata/tests/github-setup.sh` and `kata/tests/publish.sh`; drop their two lines
  from `kata/check`. Strip the GitHub and stack assertions from `kata/tests/check.sh`
  and `kata/tests/report.sh`. Every test that writes a `selected.json` or
  `handoff.json` fixture moves to the new shapes; `git grep -n -e start_branch -e
  github -e pr_url kata/tests` finds them.
- `kata/tests/check.sh:35` moves to the swapped model mapping in the chore commit.

## Docs

- `kata/README.md`: the requirements paragraph (lines 53 to 54: no `gh`, no push
  permission), the board paragraphs on stacked PRs and merging (89 to 91, 99, 114,
  129), the GitHub publication section (146 to 161), the pre-GitHub runs paragraph
  (189 to 192), the morning-review lines on PR URLs and merging the stack (216, 233),
  and the check section's GitHub fixtures (253, 259). The new text says: run the board
  from the branch the work should land on; each close fast-forwards that branch;
  nothing is pushed; push when you like.
- `README.md`: the `board.dip` row.
- `kata/BOARD-PLAN.md` lines 15 to 16 and `kata/PLAN.md` lines 15 to 17 and 121 to
  135: the branch rule becomes "land on trunk at close; never touch a remote".
- `CHANGELOG.md`: an `Unreleased` / `Changed` entry for landing on close and a
  `Removed` entry for GitHub publication and stacked bases.
- `gotchas.md:85` "The kata binding must be on the GitHub base branch" becomes an entry
  on running the board from trunk; the `.kata.toml` guard goes with the fetch that
  needed it. The auto-memory `project_kata_binding_on_remote_base.md` retires with it;
  that file lives outside the repository and is the controller's to fix.

Task 8 of the board gate review plan edits `kata/README.md`, `gotchas.md`,
`kata/BOARD-PLAN.md`, `kata/PLAN.md`, and `CHANGELOG.md` first. The landing plan
branches from `main` after that branch merges, so the two never fight over a paragraph.

## Size

About 700 lines go and 350 arrive, most of the arrivals in tests. `claim-next.sh`
loses about 100, `close-selected.sh` loses about 80 and gains 30, the two deleted tests
are 459 together, and the board, report, handoff, and doc changes are small.

## Out of scope

- Stranded branches from earlier runs: tetris-cosmic (`kata/mreb-0b1aaa1f2339`, one
  commit ahead; `kata/y6d9-16bf27d061f8` and `kata/y6d9-71243f52e751`, two each),
  bounce-9000 (three `kata/fpkj-*` attempts), todo-test (`kata/jbr3-6e9ee54608ef`,
  seven commits, two of them `wip`), todo-test-2 (`kata/n4vr-e29f4561e62f`, with `main`
  four behind). Hand-landing is an offer for after this ships; competing attempts need
  Doctor Biz's choice.
- Open GitHub PR stacks (mux 9, typesafe-go 12, address-collector-go 14) stay for the
  human.
- Rebasing automatically when trunk moved.
- A pipeline-run test gate beyond the existing evidence and approvals.
- Any remote action.

## Known weaknesses

- A kata that stays open after its landing (a failed close call) is reclaimed by the
  next sweep, which cuts a fresh branch from a trunk that already holds the work. Rare
  (a kata daemon failure inside the close step), visible in the morning review, and
  fixed by one hand `kata close`.
- The correctness reviewer and the implementer share a model after the swap commit,
  the audit's finding. Not changed here.
