# Complete one kata item

`complete.dip` claims the next ready, unowned issue without open children in
the target repository, works on that issue, and stops. Planning is optional
and stays within its acceptance criteria. If no eligible issue exists, it does no work.

Kata's readiness check only rules out open blocking predecessors; a parent
epic can still be ready while its children are unfinished. Selection filters
those parents before claiming. It keeps Kata's ordering: lowest explicit
priority first, unset priority last, and the returned order for ties. Parents
whose children are all closed remain eligible.

The worker uses TDD and the repository's own checks. Two models then review
in parallel, emulating the fresh-eyes skill:

- **Correctness (`deepseek-4.1-flash`):** acceptance criteria, regressions, error paths, and tests.
- **Scope (`glm-5.3`):** unnecessary changes, maintainability, and relevant security risks.

The worker and repair agent also use `deepseek-4.1-flash`. All six agent nodes use
tracker's `openai-compat` provider through Lunaroute. The adapter does not
forward `reasoning_effort`; reasoning behavior follows the gateway defaults.

Both must approve landing and closure. Rejected work gets at most one repair pass and
another review. A worker that hits its turn limit while still making progress gets one
automatic continue. Unfinished work stays open, labeled `needs-review` or `needs-decision`,
for the morning review.
The pipeline does not depend on locally installed agent skills.

Turn ceilings leave room for implementation, checks, evidence, and commits:

| Agent | Maximum turns |
| --- | ---: |
| Implement | 300 |
| Repair | 150 |
| Each correctness/scope review and re-review | 100 |

These are safety ceilings, not targets. Keep discovery focused on the selected
item and move into implementation once its contract and relevant code are clear.
The larger ceilings preserve the same one-item scope and single repair pass.

`Implement` gets one automatic warm continue. When it stops at its turn limit while
still making steady progress (tracker's `operator_decision` breach class), the pipeline
raises its ceiling to 450 turns and restarts the worker once with its earlier episode
summary. A second breach hands the kata off.

## Run

Use a clean target repository with kata already initialized for that repository.
Configure `OPENAI_COMPAT_API_KEY` with your Lunaroute API key and
`OPENAI_COMPAT_BASE_URL` with `https://gw.lunaroute.com/v1`. Tracker accepts
these from your environment or `~/.config/tracker/.env`; `tracker setup`
can configure them. Existing Lunaroute settings can be reused.
You also need `kata`, `git`, and `jq` on PATH. The pipeline makes no remote Git
or GitHub calls. Pushing the landed trunk is an operator action.

Use the validated toolchain: tracker **v0.73.1** with Dippin **v0.72.0**.
Dippin **v0.68.0** lacks `openai-compat` lint support and fails `kata/check`
with six DIP108 unknown-provider warnings. Match the Dippin CLI to tracker's
dependency for validation. Kata **v0.17.2** or newer is required. This directory
has newer tool requirements than the collection's general quickstart.

```sh
cd /path/to/target-repo
tracker --workdir "$PWD" /path/to/pipelines/kata/complete.dip
```

To work through the whole board, run it without the TUI:

```sh
tracker --no-tui --workdir "$PWD" /path/to/pipelines/kata/board.dip
```

Do not run the board in Tracker's TUI. The whole board is one long tool node, so
the TUI shows one running node for hours. Leaving that screen with `q` or Ctrl-C
cancels the run: Tracker 0.73.1 kills the controller and its child Tracker, then
labels the failure `command timed out after 168h0m0s` (verified 2026-09-15).
Tracker never prints a tool node's output, so the board is silent while it
sweeps; follow progress under the parent run's `board/` directory as described
below. Run the board in a terminal that stays open, such as a tmux window.

A board run is a series of sweeps. One sweep is one pass of the controller
over the queue: it claims ready, unowned katas one at a time until none is
left, then prints its review. A sweep that leaves katas needing you, or that
stops, holds the run at the `Morning review` gate with the review in the
prompt; a clean sweep ends the run without a gate. The gate has two surfaces:

- In a terminal, Tracker draws the gate as a modal. Move with the arrow keys
  and press Enter; Escape chooses `Done`. A review taller than the window
  keeps only its last lines (Tracker 0.73.1 `tui/modal.go`, reviewed
  2026-09-18), so run `board-report <board-run-id>` from another shell to
  read the whole review.
- With stdin piped, Tracker prints the review, then `1) Done` and
  `2) Sweep again`, then `Enter choice:`. Type the number or the choice text
  (`1` or `Done`, `2` or `Sweep again`) and press Enter. A blank line or any
  other text, `sweep` included, fails the gate with `invalid choice`
  (verified 2026-09-18).

The gate has no default. A run whose stdin is closed (`nohup`, `< /dev/null`,
a detached process) fails at the gate with `no input received` after saving a
checkpoint; `tracker --no-tui -r <board-run-id> /path/to/pipelines/kata/board.dip`
from a terminal reopens the gate (verified 2026-09-18). `tracker --auto-approve`
is the unattended mode: it takes the first choice, `Done`, so the run ends
after one sweep.

The board runner calls this same `complete.dip` once per item, with separate
Tracker run IDs, claims, reviews, and checkpoints. It runs sequentially from
the branch checked out when the board starts. Each successful child
fast-forwards that local trunk to its reviewed commit before closing the kata;
the next child starts at the new trunk tip. Run the board from the branch where
the work should land. The pipeline does not fetch, push, open a PR, or inspect
a remote. Push the trunk when you choose.

A child that fails cleanly does not stop the board. The handoff labels the kata
`needs-review` (or `needs-decision` when the worker wrote a question), comments
the branch and base commit, commits any uncommitted work as a WIP commit on the
task branch, and returns the checkout to the recorded trunk. The board records
the failure in its ledger and claims the next kata from the current trunk, so a
failed worker or unlanded task branch never becomes the base of a later one. A
close failure after the ref update leaves the approved commit on trunk. Three
consecutive failed children stop the sweep with `stop_reason` set in the ledger.
If no item is ready and unowned, the controller lists all open items: katas it
already handed off are expected, and any other open kata is written to
`board/blocked.json` and counted in the `Board incomplete` line. The sweep then
finishes; the review lists those katas under `Remaining open`. A later sweep
that finds no such kata removes `board/blocked.json`. The board never takes
another actor's claim. Parents become eligible as their children close. The
controller rechecks the live board after each child, so newly added eligible
work is included.

Tracker discards the controller's output under `--no-tui`. The controller's
last stdout line is a marker that routes the parent run. `board-clean` ends the
run: the queue was empty, no kata's latest ledger entry is a handoff, no
untouched open kata remains, and the review printed. `board-needs-human` runs
`board-report` and opens the `Morning review` gate with that review. Once the
ledger exists, every stop ends the same way: three consecutive failed children,
a child that needs inspection, a `git status` the controller could not run, an
open-board listing command it could not run (`could not list open katas`) or a
listing response it could not read (`invalid open-board response`), a child that
closed a kata the ledger already lists as completed, a child log that does not
name exactly one hex run ID (`child identity is unknown; inspect
<item>/child.log before retrying`) or
names one of the wrong length (`invalid child run ID`), a `child.pid` whose
process is still running, and a `child.pid` that does not hold a PID (`invalid
child PID; inspect <item>`). The controller records the stop in the ledger's
`stop_reason`, prints the review, which repeats the reason under its header,
and prints `board-needs-human`, so the gate opens for exactly the runs that
need a person. Before the ledger exists (Tracker variables unset, a missing
tool, a lock held by a live controller, a ledger the controller does not trust)
the controller exits 1 with no marker: Tracker fails the run without a
checkpoint, and the message is in
`.tracker/runs/<board-run-id>/RunBoard/status.json` under
`.context_updates.tool_stderr` (verified 2026-09-18). Fix the cause and start a
new board run. The controller's whole output for the latest sweep, its summary
line `Sweep finished: <n> katas completed and <m> left open for review so far
in this board run` included, is in the same file under
`.context_updates.tool_stdout`.

The parent run's `board/state.json` records every child: `completed` entries
carry the landed commit, `failed` entries carry the branch, reason, and
label, and `empty` entries mark an empty queue. A stop adds `stop_reason`, an
inspection stop adds `stop_child`, and the next sweep clears both. Each child's
console output is under `board/items/<attempt>/child.log`; full artifacts
remain in the target repository's `.tracker/runs/<child-id>`. A stop with
`child <child-id> needs inspection` means the child ended in a state the
controller could not verify: a failed closure, a dirty tree, an unexpected
branch, or a handoff that did not complete. The review prints
`tracker -r <child-id> <pipeline>` under the stop reason. Inspect and recover
that child using the one-item recovery guidance below, then choose `Sweep
again` at the gate: the controller verifies the recovered child's outcome
before it claims anything, so it does not silently claim a replacement item.
A child killed with its parent (a closed TUI or Ctrl-C) still owns its kata as
`kata-pipeline-<child-id>`. Resume that child from the target repository with
`tracker -r <child-id> /path/to/kata/complete.dip`, then resume the parent with
`tracker --no-tui -r <board-run-id> /path/to/kata/board.dip`. A HUP, INT, or
TERM that reaches the controller itself is passed to the child Tracker as an
interrupt: the child cancels its node, saves a checkpoint, and exits; the
controller then removes the child's `child.pid` and its own lock and exits
130. A `child.pid` left behind by a kill the controller never saw is removed
on the next sweep once that process is gone; while the process lives, the
sweep stops with `child process <pid> is still running; wait before resuming
the board`. A sweep stopped by three consecutive failures claims again from
the current trunk on the next `Sweep again`. A finished ledger sweeps again
on re-entry: `Sweep again` at the gate claims the katas released since and
records them in the same ledger. A run that ended with `Done` is over. So is
a run that took its 51st `Sweep again`: the restart budget (`max_restarts: 50`
in `board.dip`) belongs to the run, not to a kata or a repository, and never
resets, so the 51st fails the run with a restart-limit error. Start a new
board run to sweep again. Keep the checkout on the recorded trunk with a clean
working tree. Runs claimed before landing on close have no recorded trunk and
stop for manual inspection.

Board runs require the source `.dip` directory; packed `.dipx` bundles are not
supported. Tracker 0.73.1 native subgraphs share the parent's artifact directory,
so this runner uses separate CLI processes to preserve per-item state and resume.
Nested Tracker reloads stored provider settings such as `~/.config/tracker/.env`;
Tracker's default tool environment filters environment-only API keys. Configure
stored credentials before running the board. The runner does not change that policy.
The outer tool allows seven days; parent token/cost limits and summaries do not
aggregate child processes. Review each child run's usage separately.

That key filter has an off switch inside the target repository: Tracker also
reads `<workspace>/.env`, and `TRACKER_PASS_ENV=1` there, or in the
environment, passes every provider key into each tool command (verified
2026-09-18 on Tracker 0.73.1). A `.env` in the target repository persists
across sweeps and a worker can write one, so check that file before a board
run. The records a child writes under `.tracker/runs/<child-id>` (the
selection, the handoff, the review approvals) come from the worker's own run.
`board-report` validates every id, branch, and commit it pastes into a
command and refuses the whole review when one is unsafe; the controller checks
both approvals against the child's final commit before it records a
completion. Those checks defend against model error, not against a worker
that sets out to forge its records.

For a standalone one-item run, `complete.dip` records the checked-out branch as
`trunk` and creates `kata/<short-id>-<run-id>` from its current `HEAD`. It
refuses a detached `HEAD` or a checked-out `kata/*` branch. Existing unrelated
branches and commits remain intact. An empty queue leaves the current branch
unchanged.
Each one-item run never claims a second issue, including when a competing agent wins
the claim. Candidate filtering happens before that single claim attempt.
After both reviews approve the same commit, the final tool step checks that the
current trunk tip is an ancestor of that commit, then updates the local trunk
with a compare-and-swap. Movement that remains in the reviewed task's history
is safe, including a retry after the same commit already landed. Divergence is
refused with both the claimed base and current trunk tip named; rebase the task
branch, rerun both reviews, and retry. After landing, the tool closes the kata,
switches to trunk, and deletes the task branch.

If the Kata close call fails after the ref update, the kata remains open while
trunk already points at the reviewed commit; retrying the close is safe. If the
kata closes but the final switch or branch deletion fails, handoff refuses to
write a normal failure record and the board stops with `child <id> needs
inspection`. Check that trunk points at the approved commit and reconcile the
closed child, its saved `CloseSelected` state, checkout, and task branch before
resuming the board. The pipeline does not automate recovery from this state.

Runtime artifacts live under `.tracker`. The preflight adds only `/.tracker/`
to `.git/info/exclude`; it does not edit the repository's `.gitignore`. Unrelated
dirty paths stop the run before Kata selection. Resolve every path printed by
the preflight, then start a fresh tracker run. To inspect a saved preflight error:

```sh
jq -r '.context_updates.tool_stderr' .tracker/runs/<run-id>/ClaimNext/status.json
```

Do not run concurrent coding pipelines in the same checkout. Scope limits are
workflow rules and verification checks, not an OS sandbox.

If a run is interrupted, inspect its artifacts and the selected issue before
restarting. If authentication fails after `ClaimNext` succeeds, fix the provider
environment and resume the existing run from the same target repository with
the same pipeline:

```sh
tracker -r "<run-id>" --workdir "$PWD" /path/to/pipelines/kata/complete.dip
```

The saved checkpoint preserves the completed claim step; resume keeps the
selected issue and run actor instead of claiming another item. Resume continues
at the checkpoint's current node; it does not automatically retry a failed worker.

Runs claimed before landing on close lack the saved `trunk` setting. Closure
and handoff stop with `selected.json has no trunk; this run predates landing on
close and needs manual inspection`. Inspect the branch, claim, and review
evidence before recovering it; starting another run would leave the original
claim behind.

For tracker v0.73.1, `-r` reads `.tracker/runs/<run-id>/checkpoint.json` in the
target repository. A copy under `~/.local/state/tracker` can be stale even when
that directory contains the current activity log. Inspect the repository-local
checkpoint before choosing a recovery action.

Release an abandoned claim with
`kata unassign <ref>` only after confirming the old run has stopped and its
work has been accounted for.

## Morning review

Katas the board could not finish stay open, owned by `kata-pipeline-<child-id>`,
with a `needs-review` or `needs-decision` label and a comment naming the branch,
base commit, WIP commit, and question. This section is written for the agent or
person working that inbox. A sweep that leaves such katas, or that stops, holds
the board run at its `Morning review` gate with the review in the prompt; a
clean sweep ends the run without a gate. To print the review again, when the
gate clipped it, or after the run ended, from the target Git root:

```sh
/path/to/pipelines/kata/board-report
```

prints the newest board run. `board-report --json <board-run-id>` prints the
same for one run as JSON; `board-report -h` prints the usage. Outside a Git
repository the text and JSON forms both print `run this from inside the target
Git repository`. The text review is laid out to survive Tracker's prompt reflow
(76 columns, indentation dropped): short lines, and every command whole on one
line.

```
Board <board-run-id> in <workspace>: stopped
Stop reason: three consecutive failed children
  tracker -r <child-id> ~/src/pipelines/kata/complete.dip
Completed (1)
- demo#1abc: landed 0123456789ab (run <child-id>)
Needs decision (1)
- demo#2def: needs a decision (run <child-id>)
  branch kata/2def-<child-id>, base 0123456789ab, wip 89abcdef0123
  Q: <the worker's question>
  ~/src/pipelines/kata/answer demo#2def "<your answer>"
Needs review (1)
- demo#3ghi: review rejected (run <child-id>)
  branch kata/3ghi-<child-id>, base 0123456789ab, wip 89abcdef0123
  git diff 0123456789ab..kata/3ghi-<child-id>
  ~/src/pipelines/kata/answer demo#3ghi "<guidance>"
Remaining open (1)
- demo#4jkl owned by nobody, labels task
```

The header ends with `finished`, `stopped`, or `in progress`. `Stop reason:`
appears only after a stop, and the `tracker -r` line only when a child needs
inspection. The reason after each kata comes from its handoff: `needs a
decision`, `review rejected`, `landing failed`, `turn limit reached twice`,
`worker stopped`, or `handoff found the wrong branch`. A kata the board swept
more than once appears once, as its latest run left it. Paths print as `~/...` when the
pipeline lives under your home directory and single-quoted otherwise. Every
id, branch, and commit that reaches a pasteable command is checked
against a fixed character set first; when a child record fails that check,
`board-report` prints `refusing to print the review: a child record under
<runs dir> has a missing or unsafe id, branch, or commit`
and exits 1. Inside a board run that failure fails the `Report` node
(`node "Report" failed with no conditional edges to handle failure`) after a
checkpoint; read `.tracker/runs/<board-run-id>/Report/status.json`, fix or
remove the record, and resume with
`tracker --no-tui -r <board-run-id> /path/to/pipelines/kata/board.dip`, which
runs the report again and opens the gate (verified 2026-09-18).

For each kata that needs a decision, read the question and answer it:

```sh
/path/to/pipelines/kata/answer <issue-ref> "<your answer>"
```

For each kata that needs review, diff the WIP branch against its base commit
and read the review records under the child run directory
(`.tracker/runs/<child-id>/Review*/status.json` and
`.tracker/runs/<child-id>/ReReview*/status.json`).
Either finish and close it by hand, or answer with guidance so the next sweep
can finish it. Then choose `Sweep again` at
the gate (arrow keys and Enter in a terminal; `2` or `Sweep again` on piped
stdin): the board claims the katas you released and holds the review again
when that sweep ends, or ends the run when the sweep is clean. Each `Sweep
again` spends one of the run's 50 restarts, and the budget never resets.
Choose `Done` (`1`, or Escape in a terminal) to end the run; start a new board
run to sweep again later.

`kata/answer` comments the text on the kata, releases the pipeline's claim, and
prints `Released <kata>` followed by the kata's owner and labels, so the next
sweep can claim it. It refuses katas owned by anyone other than a pipeline
actor, and it says so when the reference is unknown (`kata show <ref> failed
with status <n>; check the reference and the workspace binding`) or when it
runs outside a Git repository (`run this from inside the target Git
repository`); `answer -h` prints the usage. The label stays until the next
claim removes it. The next sweep reads the comment thread and reuses the
branch's work. Both commands run from another shell in the target Git root and
change nothing else.

## Check

With the matching tools plus ShellCheck available:

```sh
./kata/check
```

Graph simulation checks routing without making model calls. Unit tests use
Kata response fixtures and real local Git repositories; a source guard rejects
remote Git and `gh` commands in live kata scripts. The preflight smoke test
runs the actual tracker binary. Closure guards reject stale or missing
approvals, missing evidence, and changes to the task branch or workspace.
Board orchestration tests also run real Tracker child processes and local Git
commits, using tool-only child workflows and fixture Kata records without models.
Landing tests verify successive children and fresh board runs start from the
advanced trunk.
Board tests also run the real handoff script inside child runs. Continue tests
drive a real tracker restart; handoff, answer, and report tests use fixture Kata
records and run directories.
Every test sources `kata/tests/isolate.sh` first. It points `HOME`, the XDG
directories, Git's global configuration, and Tracker's state at a fixture
directory, so no test runs the operator's Git hooks, reads the operator's
Tracker configuration, or writes under `~/.local/state/tracker`;
`kata/tests/isolation.sh` proves that against a planted hook and config.
These checks do not prove that a model can solve an arbitrary issue. A live
run needs a real, initialized target repository and working provider credentials.

Tracker's static validator reports unset runtime context variables before a
run exists; `kata/check` reports that known tool warning. Dippin lint and
ShellCheck must pass without warnings. Tracker v0.66.0 executes parallel
review handlers once despite their declared retry settings; runtime review
failures follow the repair or handoff route.
