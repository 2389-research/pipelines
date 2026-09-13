# Complete one kata item

`complete.dip` claims the next ready, unowned issue in the target repository,
works on that issue, and stops. Planning is optional and stays within its
acceptance criteria. An empty queue does no work.

The worker uses TDD and the repository's own checks. Two models then review
in parallel, emulating the fresh-eyes skill:

- **Correctness (`glm-5.3`):** acceptance criteria, regressions, error paths, and tests.
- **Scope (`deepseek-4.1-flash`):** unnecessary changes, maintainability, and relevant security risks.

The worker and repair agent also use `glm-5.3`. All six agent nodes use
tracker's `openai-compat` provider through Lunaroute. The adapter does not
forward `reasoning_effort`; reasoning behavior follows the gateway defaults.

Both must approve closure. Rejected work gets at most one repair pass and
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
You also need `kata`, `git`, and `jq` on PATH.

Use the validated toolchain: tracker **v0.73.1** with Dippin **v0.72.0**.
Dippin **v0.68.0** lacks `openai-compat` lint support and fails `kata/check`
with six DIP108 unknown-provider warnings. Match the Dippin CLI to tracker's
dependency for validation. Kata **v0.17.2** or newer is required. This directory
has newer tool requirements than the collection's general quickstart.

```sh
cd /path/to/target-repo
tracker --workdir "$PWD" /path/to/pipelines/kata/complete.dip
```

Run once per item. When work is ready, the pipeline creates a branch named
`kata/<short-id>-<run-id>` from `main`, `master`, or `trunk`. It keeps any
existing non-default branch. An empty queue leaves the current branch unchanged.
The selection never advances to a second issue, including when a competing
agent wins the claim. The workflow does not push or merge; review the resulting
branch before integrating it.

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
selected issue and run actor instead of claiming another item. Release it with
`kata unassign <ref>` only after confirming the old run has stopped and its
work has been accounted for.

## Check

With the matching tools plus ShellCheck available:

```sh
./kata/check
```

Graph simulation checks routing without making model calls. Unit tests use
kata response fixtures and real Git repositories; the preflight smoke test
runs the actual tracker binary. Closure guards reject stale or missing
approvals, missing evidence, and changes to the task branch or workspace.
These checks do not prove that a model can solve an arbitrary issue. A live
run needs a real, initialized target repository and working provider credentials.

Tracker's static validator reports unset runtime context variables before a
run exists; `kata/check` reports that known tool warning. Dippin lint and
ShellCheck must pass without warnings. Tracker v0.66.0 executes parallel
review handlers once despite their declared retry settings; runtime review
failures follow the repair or handoff route.
