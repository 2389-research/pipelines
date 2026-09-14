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
another review. Unfinished work stays open with a `needs-review` handoff.
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

To work through the whole board, run:

```sh
tracker --workdir "$PWD" /path/to/pipelines/kata/board.dip
```

The board runner calls this same `complete.dip` once per item, with separate
Tracker run IDs, claims, reviews, and checkpoints. It runs sequentially. After
the first item, each task branches from the previous approved commit and opens
its PR against the previous task branch. This keeps later work available while
the PRs await your review. Merge the stack from oldest to newest; the pipeline
does not merge it. Standalone `complete.dip` retains the default-branch behavior
described below.

The board stops on its first failed child. If no item is ready and unowned,
it checks all open items: an empty board succeeds; remaining owned or blocked
items produce an incomplete-board report. It never takes another actor's claim.
Parents become eligible as their children close. The runner rechecks the live
board after each completion, so newly added eligible work is included.

The parent run's `board/state.json` records child IDs, commits, and PR URLs.
Each child's console output is under `board/items/<attempt>/child.log`; full
artifacts remain in the target repository's `.tracker/runs/<child-id>`.
Inspect and recover a failed child using the one-item recovery guidance below,
then resume the parent with `tracker -r <board-run-id> /path/to/kata/board.dip`.
The controller verifies the existing child's successful completion before
advancing, so resuming the parent does not silently claim a replacement item.
An incomplete board can be resumed after its blockers or ownership are resolved.
Keep the checkout on the last task branch with a clean working tree.

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

If `Implement` exhausted its turns and the run reached `Handoff`, stop tracker
and prepare an implementation retry from the target repository:

```sh
/path/to/pipelines/kata/retry-implementation "<run-id>"
```

This command verifies the saved workspace, branch, base commit, and live issue
ownership, backs up the repository-local checkpoint, and returns it to
`Implement`. It restores the selected issue's prompt context and removes failed
worker routing state. It preserves the claim and all source changes, then prints
the tracker resume command. It requires `pgrep` and refuses while any tracker
process is running. It only handles an implementation turn-limit failure before
reviews; later failures need inspection rather than restarting the whole review cycle.

For tracker v0.73.1, `-r` reads `.tracker/runs/<run-id>/checkpoint.json` in the
target repository. A copy under `~/.local/state/tracker` can be stale even when
that directory contains the current activity log. Inspect the repository-local
checkpoint before choosing a recovery action.

Release an abandoned claim with
`kata unassign <ref>` only after confirming the old run has stopped and its
work has been accounted for.

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
These checks do not prove that a model can solve an arbitrary issue. A live
run needs a real, initialized target repository and working provider credentials.

Tracker's static validator reports unset runtime context variables before a
run exists; `kata/check` reports that known tool warning. Dippin lint and
ShellCheck must pass without warnings. Tracker v0.66.0 executes parallel
review handlers once despite their declared retry settings; runtime review
failures follow the repair or handoff route.
