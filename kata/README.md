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

- **Correctness (`glm-5.3`):** acceptance criteria, regressions, error paths, and tests.
- **Scope (`deepseek-4.1-flash`):** unnecessary changes, maintainability, and relevant security risks.

The worker and repair agent also use `glm-5.3`. All six agent nodes use
tracker's `openai-compat` provider through Lunaroute. The adapter does not
forward `reasoning_effort`; reasoning behavior follows the gateway defaults.

Both must approve publication and closure. Rejected work gets at most one repair pass and
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
You also need `kata`, `git`, and `jq` on PATH. GitHub repositories additionally
need an authenticated `gh` CLI and permission to push a branch and open a PR.

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
below. When a sweep ends with katas that need you, the run holds at the
`Morning review` gate: Tracker prints the review with two numbered choices and
reads the choice number from stdin. Run the board in a terminal that stays
open, such as a tmux window. A run without a terminal on stdin fails at the
gate; `tracker --auto-approve` answers every gate with its default, which ends
the run after one sweep (verified 2026-09-18).

The board runner calls this same `complete.dip` once per item, with separate
Tracker run IDs, claims, reviews, and checkpoints. It runs sequentially. After
the first item, each task branches from the previous approved commit and opens
its PR against the previous task branch. This keeps later work available while
the PRs await your review. Merge the stack from oldest to newest; the pipeline
does not merge it. Standalone `complete.dip` retains the default-branch behavior
described below.

A child that fails cleanly does not stop the board. The handoff labels the kata
`needs-review` (or `needs-decision` when the worker wrote a question), comments
the branch and base commit, commits any uncommitted work as a WIP commit on the
task branch, and returns the checkout to the branch the child started on. The
board records the failure in its ledger and claims the next kata from the same
stack base, so a failed kata never becomes the base of a later one. Three
consecutive failed children stop the board with `stop_reason` set in the ledger.
If no item is ready and unowned, the board checks all open items: katas it
already handed off are expected, and any other open kata is listed in
`board/blocked.json` and counted in the `Board incomplete` line. The board then
finishes; the report lists those katas under `Remaining open`. It never takes
another actor's claim. Parents become eligible as their children close. The
runner rechecks the live board after each child, so newly added eligible work
is included. The controller exits 0 at the end of the queue and 1 on every
early stop. It prints the morning review at the end of the queue and after
three consecutive failures. An inspection stop prints recovery instructions
instead of the review. Its last line routes the parent run: `board-clean` ends
the run, and `board-needs-human` opens the morning review gate.

The parent run's `board/state.json` records every child: `completed` entries
carry the commit and PR URL, `failed` entries carry the branch, reason, and
label, and `empty` entries mark an empty queue. Each child's console output is
under `board/items/<attempt>/child.log`; full artifacts remain in the target
repository's `.tracker/runs/<child-id>`. A stop with `child <child-id> needs
inspection` means the child ended in a state the controller could not verify:
a failed closure, a dirty tree, an unexpected branch, or a handoff that did not
complete. Inspect and recover that child using the one-item recovery guidance
below, then resume the parent with
`tracker --no-tui -r <board-run-id> /path/to/kata/board.dip`.
A child killed with its parent (a closed TUI or Ctrl-C) still owns its kata as
`kata-pipeline-<child-id>`. Resume that child from the target repository with
`tracker -r <child-id> /path/to/kata/complete.dip` before resuming the board.
The controller verifies the existing child's outcome before advancing, so
resuming the parent does not silently claim a replacement item. A board stopped
by three consecutive failures can be resumed; it claims again from the same
stack base. A finished ledger sweeps again on re-entry: `Sweep again` at the
gate claims the katas released since and records them in the same ledger. A
run that ended with `Done` is over; start a new board run to sweep again. Keep
the checkout on the last task branch with a clean working tree. Runs claimed
before the handoff recorded a starting branch stop for inspection at handoff.

Board runs require the source `.dip` directory; packed `.dipx` bundles are not
supported. Tracker 0.73.1 native subgraphs share the parent's artifact directory,
so this runner uses separate CLI processes to preserve per-item state and resume.
Nested Tracker reloads stored provider settings such as `~/.config/tracker/.env`;
Tracker's default tool environment filters environment-only API keys. Configure
stored credentials before running the board. The runner does not change that policy.
The outer tool allows seven days; parent token/cost limits and summaries do not
aggregate child processes. Review each child run's usage separately.

For a standalone one-item run, `complete.dip` creates a branch named
`kata/<short-id>-<run-id>`, even when starting on another feature branch.
For GitHub repositories, it fetches the remote's default branch and starts
from that commit. Existing local branches and commits remain intact. For
repositories without GitHub, the task branch starts from current HEAD.
An empty queue leaves the current branch unchanged.
Each one-item run never claims a second issue, including when a competing agent wins
the claim. Candidate filtering happens before that single claim attempt.
The pipeline recognizes GitHub.com SSH and HTTPS remotes. It prefers a GitHub
`origin`; otherwise it requires exactly one GitHub remote. It verifies remote
and authentication setup before claiming and records the repository and PR base.

After both reviews approve the same commit, the final tool step pushes that
commit to the task branch and opens a PR with the completion summary and
verification evidence. A retry reuses a matching open PR. The URL is saved in
`pr-url.txt` under the run directory and included in the kata closure message.
Only then does the pipeline close the kata. Push or PR failures leave it open
with a handoff. It never force-pushes or merges. Repositories without GitHub
finish with the local commit and kata closure.

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

Runs claimed before GitHub publication was added lack the saved `github` setting.
Closure stops with a recovery error for these runs. Inspect the existing branch,
claim, and review evidence before recovering it; starting another run would leave
the original claim behind.

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
person working that inbox. The board run holds at its `Morning review` gate with
the review on screen. To print it again, or after the run ended, from the target
Git root:

```sh
/path/to/pipelines/kata/board-report
```

prints the newest board run: completed katas with branches and PR URLs, katas
that need a decision with their questions, katas that need review with their
branches, and open katas the board never touched. A kata the board swept more
than once appears once, as its latest run left it. `board-report --json
<board-run-id>` prints the same for one run as JSON.

For each kata that needs a decision, read the question and answer it:

```sh
/path/to/pipelines/kata/answer <issue-ref> "<your answer>"
```

For each kata that needs review, diff the WIP branch against its base commit
and read the review records under the child run directory
(`.tracker/runs/<child-id>/Review*/status.json` and
`.tracker/runs/<child-id>/ReReview*/status.json`).
Either finish and close it by hand, or answer with guidance so the next sweep
can finish it. Merge the PR stack oldest first. Then choose `Sweep again` at
the gate: the board claims the katas you released and holds the review again
when that sweep ends. Each `Sweep again` is one of the run's 50 restarts.
Choose `Done` to end the run; start a new board run to sweep again later.

`kata/answer` comments the text on the kata and releases the pipeline's claim,
so the next sweep can claim it. It refuses katas owned by anyone other than
a pipeline actor. The label stays until the next claim removes it. The next
sweep reads the comment thread and reuses the branch's work. Both commands run
from another shell in the target Git root and change nothing else.

## Check

With the matching tools plus ShellCheck available:

```sh
./kata/check
```

Graph simulation checks routing without making model calls. Unit tests use
kata/GitHub response fixtures and real Git repositories, including pushes to
temporary bare remotes; the preflight smoke test
runs the actual tracker binary. Closure guards reject stale or missing
approvals, missing evidence, and changes to the task branch or workspace.
Board orchestration tests also run real Tracker child processes and local Git
commits, using tool-only child workflows and fixture Kata records without models
or live GitHub publication. Stack-base tests verify the fetched predecessor SHA.
Board tests also run the real handoff script inside child runs. Continue tests
drive a real tracker restart; handoff, answer, and report tests use fixture Kata
records and run directories.
These checks do not prove that a model can solve an arbitrary issue. A live
run needs a real, initialized target repository and working provider credentials.

Tracker's static validator reports unset runtime context variables before a
run exists; `kata/check` reports that known tool warning. Dippin lint and
ShellCheck must pass without warnings. Tracker v0.66.0 executes parallel
review handlers once despite their declared retry settings; runtime review
failures follow the repair or handoff route.
