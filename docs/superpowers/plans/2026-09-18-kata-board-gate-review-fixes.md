# Kata Board Gate Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the critical and important findings from the 2026-09-18 review squad on the kata board morning-review gate so the branch `fix/kata-scripts-by-path` can merge to `main` locally.

**Architecture:** The board controller (`kata/scripts/run-board.sh`) records every stop after its ledger exists and always ends with the `board-needs-human` marker, so the parent run (`kata/board.dip`) holds at the `Morning review` human gate instead of ending or failing silently. The gate has no default choice, so it never answers itself. The review (`kata/board-report`) validates every agent-written record before it prints and emits commands that survive Tracker's 76-column reflow. The tests get a shared isolation snippet so no test reads or writes the operator's real Git or Tracker configuration.

**Tech Stack:** POSIX `sh`, `jq` 1.8.2, `git` 2.50.1, Tracker 0.73.1, Dippin 0.72.0, ShellCheck. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-kata-board-gate-review-findings.md` (the consolidated review; finding ids C1-C6, I1-I13, M1-M12 below refer to it) and `docs/superpowers/specs/2026-09-16-kata-overnight-board-design.md` (the board design this branch implements).

## Status

- 2026-09-18: plan written. Doctor Biz chose option 1 of the review menu ("Fix criticals and importants as planned, then merge to main locally"), so execution and the local merge are authorized. Pushing `main` is not.
- Branch: `fix/kata-scripts-by-path` (forked from `main` at 1aeddf7; `main` has not moved). Commits before the plan: 686ee42, 09ff603, 0b23d91. Tasks 1 and 2: ce116d9, 1cfa83e, 72a0b3a. Tasks 3 to 8: one commit each, in order, on the same branch.
- Task order differs from the review menu on purpose: the gate fix (C2, C3) lands before the stop-handling fix (C1) because the tests for C1 assert what a real Tracker parent does at a gate with no default.
- 2026-09-18: Tasks 1 to 8 landed and the exported-tree check passed after the last commit. Next step: merge `fix/kata-scripts-by-path` into `main` locally, without pushing, then hand the Tracker bugs listed under "Not in this plan" to Doctor Biz to file upstream. The auto-memory note that mirrors the `gotchas.md` human-gate entry is the controller's to fix.

## Global Constraints

- Every script is POSIX `sh` with `set -eu`, a shebang, then two `# ABOUTME:` lines, and ShellCheck clean. The one sourced snippet (`kata/tests/isolate.sh`, Task 6) starts with `# shellcheck shell=sh` and the two ABOUTME lines (no shebang: it is sourced) and sets no shell options, because the caller already did.
- "Tests never contact a real kata daemon or model provider. Every test puts a fixture `kata` on `PATH` and works in a disposable Git repository under `mktemp -d`. Never create practice issues in a real workspace. Do not touch the `mux` or `todo-test-2` workspaces or their kata state."
- "Only the pipelines repository changes. Tracker and kata bugs are flagged in the final report, never patched here."
- "Never print `~/.config/tracker/.env` values."
- "Every path comparison uses `pwd -P`."
- "Never bypass hooks: `--no-verify`, `--no-hooks`, and `--no-pre-commit-hook` are forbidden."
- "Run `git status` before every `git add`; never `git add -A` in this repository."
- Never stage `kata/complete.dip` (it carries Doctor Biz's uncommitted model swap) or `HANDOFF.md`. Name every file in each `git add`.
- Conventional commits, imperative, present tense, scope `kata`.
- The canonical check is `./kata/check`. It fails on the live tree because of the uncommitted `kata/complete.dip` change (its `check.sh` test asserts the committed models), so run it on an exported tree after each commit:

  ```sh
  d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"
  ```

  Individual test files run fine on the live tree: `sh kata/tests/board.sh`, `sh kata/tests/report.sh`, `sh kata/tests/answer.sh`.
- Tracker facts every task relies on (verified 2026-09-18 on Tracker 0.73.1 / Dippin 0.72.0): `--no-tui` never prints a tool node's stdout or stderr; a `human` choice gate prints the prompt and the choices numbered in edge order, then reads the choice number or the choice text from stdin; with no `default:` an empty, closed, or exhausted stdin fails the gate; `--auto-approve` takes the default, else the first choice; the TUI's Escape key does the same; the prompt is reflowed at 76 columns with leading whitespace stripped, so no review line may depend on indentation or exceed 76 characters when it must be pasted whole; `gate_opened.gate_prompt` is the raw prompt capped at 4096 bytes; `gate_resolved` shares the `Enter choice` console line, so JSON event parsers strip everything before the first `{`; `max_restarts` lives only in `defaults`; a tool node whose stdout lacks the `marker_grep` match fails the run without a checkpoint. Tracker refuses to run any workflow, even one with only tool nodes, until a provider key is configured (`no providers configured`); it reads `$XDG_CONFIG_HOME/tracker/.env` (else `$HOME/.config/tracker/.env`) and then `<workdir>/.env` for keys not already in the environment, and it drops every provider key from each tool node's environment while passing `HOME`, `PATH`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM`, `TRACKER_NO_UPDATE_CHECK`, `TRACKER_RUN_DIR`, `TRACKER_RUN_ID`, and `TRACKER_WORKDIR`, so a nested child Tracker finds its provider through the same `.env` file. A tool node may start before `$TRACKER_RUN_DIR` exists on disk. A backgrounded Tracker sent `kill -INT` cancels its running tool node within seconds, kills the tool's process group (a probe's `sleep 30` died with it), writes a checkpoint, prints the `tracker -r <id> <dip>` resume hint even under `--json --no-tui`, and exits 1. At a choice gate with no default, a closed stdin makes Tracker emit `gate_resolved` whose `error` holds the text `human gate choice selection failed for node "MorningReview": no input received` and whose `gate_response` is null, then `stage_failed` and `pipeline_failed`, write a checkpoint, print the resume hint, and exit 1; under `--auto-approve` it emits `gate_resolved` with the first choice's value and continues. Tracker has no `--no-color` flag; the flags these tasks use are `-r`/`--resume`, `--json`, `--no-tui`, `--auto-approve`, `--git off`, and `--workdir`.
- Design decisions in this plan that go beyond the review (Doctor Biz should know they were the planner's call): the review prints each command's path single-quoted in full, or as `~/...` when the path lies under `$HOME` and contains only `[A-Za-z0-9._/-]`, because Doctor Biz's shell is fish, which has no `NAME=value` assignment syntax, so a `KATA='<path>'` header line that later commands reuse could not be pasted; agent-written text (questions, reasons, owners, labels) is flattened with `gsub("[[:cntrl:]]+"; " ")` so escape sequences never reach the terminal; every test writes `OPENAI_API_KEY=fixture-not-a-key` into an isolated Tracker `.env` because Tracker refuses tool-only workflows without a provider, and no test runs an agent node, so the key is never sent anywhere.
- Never type Unicode escapes such as backslash-u sequences into shell commands; use `[[:cntrl:]]` classes and `([27] | implode)` in jq when a test needs a control character.

## File map

| File | Responsibility | Tasks |
|------|----------------|-------|
| `kata/board.dip` | Parent workflow: RunBoard, Report, MorningReview gate, edges | 1 |
| `kata/check` | Canonical check: graph greps, test order, ShellCheck | 1, 6 |
| `kata/board-report` | Morning review renderer (text and `--json`) | 2 |
| `kata/scripts/run-board.sh` | Board controller: ledger, child runs, stop handling, markers | 3, 5, 7 |
| `kata/answer` | Operator reply that releases a pipeline claim | 7 |
| `kata/tests/board.sh` | Controller and nested-Tracker tests | 1, 2, 3, 4, 5, 6, 7 |
| `kata/tests/report.sh` | `board-report` tests | 2, 6 |
| `kata/tests/answer.sh` | `answer` tests | 6, 7 |
| `kata/tests/tool-commands.sh` | Expansion guard test | 6 |
| `kata/tests/isolate.sh` | New: HOME/XDG/Git/Tracker isolation, sourced by every test | 6 |
| `kata/tests/isolation.sh` | New: proves the isolation snippet stops an operator hook and config | 6 |
| the other nine `kata/tests/*.sh` | Source the isolation snippet, physical paths, signal traps | 6 |
| `kata/README.md`, `CHANGELOG.md`, `gotchas.md`, `kata/BOARD-PLAN.md`, `kata/PLAN.md` | Documentation of the gate, the stops, and the review | 8 |
| `docs/superpowers/plans/2026-09-18-kata-board-gate-review-fixes.md` | This plan: the `## Status` section | 8 |

## Verifying a task

Each task ends with the same three checks unless it says otherwise:

1. The task's own test file on the live tree, for example `sh kata/tests/board.sh`; it must print only `ok - ...` lines and exit 0.
2. `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh` prints nothing.
3. After the commit, the exported-tree check from Global Constraints exits 0.

`kata/tests/board.sh` runs real Tracker parents in its `nested*` cases and takes a few minutes; run it in the foreground and wait.

---

### Task 1: The gate never answers itself (C2, C3, I7, I8)

**Files:**
- Modify: `kata/board.dip` (whole file)
- Modify: `kata/check:22-24` (the three `dippin simulate` lines)
- Modify: `kata/tests/board.sh` (insert a `fail` helper before `new_case() {`, replace the `nested` case, append two cases at the end)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `fail MESSAGE [LOG]` in `kata/tests/board.sh`: prints `FAIL: MESSAGE` to stderr, prints the last 60 lines of LOG (or of `$test_root/output` when no LOG is given) to stderr, exits 1. Every later board test task uses it. The gate's choice values are `done` and `sweep`, its labels `Done` and `Sweep again`, it has no `default:`, and the `Done` edge comes first. `Report` has `timeout: 10m` and `Exit` has `timeout: 5s`.

**Why:** `default: done` lets a closed stdin or `--auto-approve` answer the morning review with `Done` (C2). The labels `[D] Done` and `[S] Sweep again` advertise letters Tracker rejects; it accepts the label text or a number (C3). `kata/check` greps only `MorningReview` and `"restart":true` from the simulation, so a renamed choice or a dropped edge passes (I7). The 51st `Sweep again` ends the run with a restart-limit failure and nothing says so (I8).

- [ ] **Step 1: Make `kata/check` assert every edge and refuse a default choice**

Replace lines 22-24 of `kata/check`, which are exactly:

```sh
dippin simulate "$KATA_DIR/board.dip" --all-paths >"$simulation_log" 2>&1
grep -F 'MorningReview' "$simulation_log" >/dev/null
grep -F '"restart":true' "$simulation_log" >/dev/null
```

with:

```sh
dippin simulate "$KATA_DIR/board.dip" --all-paths >"$simulation_log" 2>&1
# Every route the board relies on, as dippin prints it; a renamed label or a dropped restart fails here.
for edge in \
  '"from":"RunBoard","to":"Report","condition":"ctx.tool_marker = board-needs-human"' \
  '"from":"RunBoard","to":"Exit","condition":"ctx.tool_marker = board-clean"' \
  '"from":"Report","to":"MorningReview"' \
  '"from":"MorningReview","to":"Exit","label":"Done"' \
  '"from":"MorningReview","to":"RunBoard","label":"Sweep again","restart":true'; do
  grep -F "$edge" "$simulation_log" >/dev/null || {
    printf 'board.dip simulation lacks the edge %s\n' "$edge" >&2
    exit 1
  }
done
# A default choice would let a closed stdin or --auto-approve answer the morning review by itself.
if grep -nE '^[[:space:]]*default:' "$KATA_DIR/board.dip"; then
  printf 'board.dip gives the morning review a default choice\n' >&2
  exit 1
fi
# With no default, --auto-approve and the TUI's Escape take the first choice, which must be Done.
grep -E '^[[:space:]]*MorningReview ->' "$KATA_DIR/board.dip" | sed -n '1p' | grep -F 'choice: done' >/dev/null || {
  printf 'board.dip must list Done as the first morning review choice\n' >&2
  exit 1
}
```

- [ ] **Step 2: Run the check to see the new assertion fail**

Run: `./kata/check`
Expected: exit 1 before any test runs, with `board.dip simulation lacks the edge "from":"MorningReview","to":"Exit","label":"Done"` on stderr. The first three edges already exist; the current labels are `[D] Done` and `[S] Sweep again`.

- [ ] **Step 3: Write the failing nested tests**

In `kata/tests/board.sh`, insert this helper immediately before the line `new_case() {` (line 219 today):

```sh
# Every assertion names what it expected; the tail of the named log (the controller output by default) follows.
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail_log=${2:-$test_root/output}
  [ ! -f "$fail_log" ] || tail -n 60 "$fail_log" >&2
  exit 1
}

```

Replace the `nested` case. It runs from the comment line `# Invoke the actual parent workflow so nested tool environments and failure routing are real.` (line 570 today) through `[ "$(claim_count)" -eq 2 ]` (line 583, the line before `new_case nested-failure 1`). The replacement:

```sh
# Invoke the actual parent workflow so nested tool environments and routing are real. A clean board must end
# without a gate, and stdin is closed so a gate that did open could not be answered by accident.
new_case nested 1
tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent.log" 2>&1 </dev/null ||
  fail 'real Tracker parent did not complete its child workflow' "$test_root/parent.log"
# Tracker prints some events on the same console line as a prompt, so strip anything before the first brace.
parent_id=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent.log")
case "$parent_id" in ''|null) fail 'nested: the parent log has no pipeline_started event' "$test_root/parent.log" ;; esac
parent_ledger="$repo/.tracker/runs/$parent_id/board/state.json"
jq -e --arg parent "$parent_id" '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","empty"] and all(.runs[]; .run_id != $parent)' "$parent_ledger" >/dev/null ||
  fail 'nested: the ledger does not show one completed kata and one empty sweep under a distinct parent id'
[ "$(claim_count)" -eq 2 ] || fail "nested: claim count is $(claim_count), expected 2"
jq -Rne '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_opened")] | length == 0' \
  <"$test_root/parent.log" >/dev/null || fail 'nested: a clean board opened the morning review gate' "$test_root/parent.log"
printf 'ok - a real Tracker parent sweeps a clean board and ends without a gate\n'
```

Append these two cases after the last line of the file (today that is `printf 'ok - real Tracker parent opens the morning review for a handed-off kata and sweeps again on request\n'`):

```sh

# Nobody is on stdin. With no default choice the gate must fail the run rather than pick an answer.
new_case nested-gate-eof 1
printf '1\n' >"$fixture/fail-implement"
if tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-gate-eof.log" 2>&1 </dev/null; then
  fail 'the morning review answered itself with stdin closed' "$test_root/parent-gate-eof.log"
fi
jq -Rne '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_opened")] | length == 1' \
  <"$test_root/parent-gate-eof.log" >/dev/null || fail 'nested-gate-eof: the gate did not open exactly once' "$test_root/parent-gate-eof.log"
# Tracker still emits gate_resolved on the failure, carrying the error text; only a real choice is wrong here.
jq -Rne '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_resolved") |
  select(.gate_response == "done" or .gate_response == "sweep")] | length == 0' \
  <"$test_root/parent-gate-eof.log" >/dev/null || fail 'nested-gate-eof: the gate resolved without a person' "$test_root/parent-gate-eof.log"
[ "$(claim_count)" -eq 2 ] || fail "nested-gate-eof: claim count is $(claim_count), expected 2"
printf 'ok - a real Tracker parent fails at the morning review when nobody can answer it\n'

# --auto-approve takes the first choice when there is no default; Done must be first so an unattended run ends.
new_case nested-auto-approve 1
printf '1\n' >"$fixture/fail-implement"
tracker --git off --workdir "$repo" --json --no-tui --auto-approve "$test_root/workflow/board.dip" \
  >"$test_root/parent-auto.log" 2>&1 </dev/null ||
  fail 'a real Tracker parent under --auto-approve did not end' "$test_root/parent-auto.log"
responses=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_resolved") | .gate_response] | join(",")' \
  <"$test_root/parent-auto.log")
[ "$responses" = done ] || fail "nested-auto-approve: gate responses are \"$responses\", expected done" "$test_root/parent-auto.log"
[ "$(claim_count)" -eq 2 ] || fail "nested-auto-approve: claim count is $(claim_count), expected 2"
printf 'ok - a real Tracker parent under --auto-approve ends after one sweep\n'
```

Claim counts: the fixture's first claim takes item 1, which fails and is handed off; the second claim finds the queue empty. Both new cases therefore claim twice. The `nested-failure` case keeps its own `ok` line; Task 3 rewrites it.

- [ ] **Step 4: Run the board tests to see them fail**

Run: `sh kata/tests/board.sh`
Expected: every earlier case prints its `ok - ...` line, then `FAIL: the morning review answered itself with stdin closed`, exit 1. (`nested-auto-approve` would pass today because the default and the first choice agree; it pins the choice order for after the default is gone.)

- [ ] **Step 5: Write the new `kata/board.dip`**

Replace the whole file with:

```
# ABOUTME: Completes the repository's kata board through isolated complete.dip runs.
# ABOUTME: Stacks reviewed task branches and PRs, then holds the morning review until the operator sweeps again or stops.
workflow CompleteKataBoard
  goal: "Complete all ready unowned katas sequentially with stacked PRs, then hold the morning review until the operator sweeps again or stops."
  start: RunBoard
  exit: Exit

  defaults
    # Each "Sweep again" is one restart; Tracker's default of five would end a week-long board early.
    # The 51st "Sweep again" ends the run with a restart-limit failure; start a new board run then.
    max_restarts: 50

  tool RunBoard
    label: "Complete the board one reviewed kata at a time"
    timeout: 168h
    marker_grep: "^(board-clean|board-needs-human)$"
    command: sh "${graph.workflow_dir}/scripts/run-board.sh" "${graph.workflow_dir}/complete.dip"

  tool Report
    label: "Print the morning review"
    timeout: 10m
    command: sh "${graph.workflow_dir}/board-report" "$TRACKER_RUN_ID"

  human MorningReview
    label: "Morning review"
    mode: choice
    prompt:
      The board stopped with katas that need you; the review below lists each one.
      In a terminal, pick with the arrow keys and Enter; Escape chooses Done.
      With a numbered list, type the number or the choice text and press Enter.
      Answer or finish katas from another shell in the target Git root with the
      commands the review shows, then choose Sweep again to claim the katas you
      released, or Done to end this run.
      ${ctx.tool_stdout}

  tool Exit
    label: "Board finished"
    timeout: 5s
    command: true

  edges
    RunBoard -> Report  on board-needs-human
    RunBoard -> Exit  on board-clean
    Report -> MorningReview
    # Done is first on purpose: with no default, Escape and --auto-approve take the first choice.
    MorningReview -> Exit  label: "Done"  choice: done
    MorningReview -> RunBoard  label: "Sweep again"  choice: sweep  restart: true
```

- [ ] **Step 6: Validate the workflow**

Run: `tracker validate kata/board.dip`
Expected: exit 0 and no `DIP111` line (every tool node now has a `timeout:`).

Run: `dippin simulate kata/board.dip --all-paths 2>&1 | grep -c '"label":"Done"'`
Expected: `2` (once per simulated path through the gate).

- [ ] **Step 7: Run the checks to see them pass**

Run: `./kata/check`
Expected: the simulation assertions pass; the run then fails inside `kata/tests/check.sh` on the live tree because of the uncommitted `kata/complete.dip` model swap (pre-existing, see Global Constraints). Any other failure is yours.

Run: `sh kata/tests/board.sh`
Expected: only `ok - ...` lines, ending with `ok - a real Tracker parent under --auto-approve ends after one sweep`, exit 0.

Run: `shellcheck kata/check kata/tests/board.sh`
Expected: no output.

- [ ] **Step 8: Commit**

```sh
git status
git add kata/board.dip kata/check kata/tests/board.sh
git commit -m 'fix(kata): stop the morning review gate answering itself'
```

- [ ] **Step 9: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: `all kata checks passed`, exit 0.

No file outside `kata/board.dip` references the old labels or the default (a grep for `[D] Done`, `[S] Sweep`, and `default: done` across `kata`, `CHANGELOG.md`, `gotchas.md`, and `README.md` on 2026-09-18 found only `kata/board.dip`). The prose that describes the gate changes in Task 8.

### Task 2: The review validates its records and prints pasteable commands (C5, C6, M8, M9, M2, M3, M6, M7)

**Files:**
- Modify: `kata/board-report` (whole file; mode 755, because `kata/scripts/run-board.sh` refuses a report it cannot execute)
- Modify: `kata/tests/report.sh` (whole file)
- Modify: `kata/tests/board.sh` (the three review greps quoted in Step 1)

**Interfaces:**
- Consumes: the ledger `board/state.json` under the board run (`workspace`, `pipeline`, `finished`, `stop_reason`, `runs[]` with `run_id`, `kind`, `issue_uid`, `branch`, `commit`, `pr_url`, `reason`, `label`); each completed child's `ClaimNext/selected.json` and `pr-url.txt`; each failed child's `handoff.json`; `kata list --workspace <ws> --status open --limit 0 --json`. It also reads an optional ledger field `stop_child` (12 hex characters, the child that needs inspection) that Task 3 starts writing; when present the review prints that child's resume command under the stop reason.
- Produces: `kata/board-report [--json] [BOARD_RUN_ID]`, run from inside the target Git repository. Exit 0 on success; 1 when the ledger, a selection record, or a handoff record is missing, when a record fails validation, or when the open-board listing is not a list; 2 for a bad argument. Stderr lines later tasks and documentation rely on: `run this from inside the target Git repository`, `no board ledger at <path>`, `invalid board ledger: <path>`, `completed child <id> has no selection record: <path>`, `failed child <id> has no handoff record: <path>`, `invalid open-board response`, and `refusing to print the review: a child record under <runs dir> has a missing or unsafe id, branch, commit, or pull request URL`. `--json` prints one object: `board_run_id`, `workspace`, `pipeline`, `finished`, `stop_reason`, `stop_child`, and the arrays `completed`, `needs_decision`, `needs_review`, `remaining`; every item in every array carries the same keys (`qualified_id`, `issue_uid`, `run_id`, `branch`, `base_commit`, `wip_commit`, `pr_url`, `reason`, `question`, `owner`, `labels`, `next`), `null` or `[]` where the group has no such value, and `next` lists the commands the text review prints for that kata.

The text review. Tracker reflows it at 76 columns and strips leading spaces before a person sees it, so every line is short, no line depends on its indent, and each command is whole on one line:

```
Board <board-run-id> in <workspace>: stopped|finished|in progress
Stop reason: <reason>                        (only when the ledger has one)
  tracker -r <child-id> <pipeline path>      (only when the ledger names a stop_child)
Completed (<n>)
- <qualified id> on <branch>
  <pull request URL, or: no pull request>
Needs decision (<n>)
- <qualified id>: needs a decision (run <child-id>)
  branch <branch>, base <12 hex or none>, wip <12 hex or none>
  Q: <the question, flattened to one line>
  <answer path> <qualified id> "<your answer>"
Needs review (<n>)
- <qualified id>: <reason in words> (run <child-id>)
  branch <branch>, base <12 hex or none>, wip <12 hex or none>
  git diff <base>..<branch>                  (only when the handoff recorded a base)
  <answer path> <qualified id> "<guidance>"
Remaining open (<n>)
- <qualified id> owned by <owner, or nobody>[, labels <a,b>]
```

`<answer path>` is `~/...` when `kata/answer` lies under `$HOME` and its path contains only `[A-Za-z0-9._/-]`; otherwise it is the full path in single quotes (with any single quote inside it escaped the way `sh` needs). The pipeline path after `tracker -r` follows the same rule. Reasons print as words: `decision` as `needs a decision`, `implement` as `worker stopped`, `review` as `review rejected`, `publish` as `publication failed`, `turn_limit` as `turn limit reached twice`, `unexpected_checkout` as `handoff found the wrong branch`, a missing reason as `handed off`, and an unknown reason as itself, flattened.

**Why:** The review is what a person reads at 06:00 and pastes into a shell. Today it prints branch names, ids, and URLs straight from records an agent's run wrote, without checking them (C5); its two-space layout collapses under Tracker's 76-column reflow (C6); the stop reason sits at the bottom, where the reflow buries it (M8); only some agent-written fields are flattened (M9); its signal traps exit 0 (M2); it resolves paths logically (M3); it has no `-h` (M6); and outside a repository it dies with Git's error instead of its own (M7). The new report refuses the whole review when any field that reaches a command does not look like what it claims to be, prints one fact per line with each command whole and quoted, and puts the stop reason under the header.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `kata/tests/report.sh` with this file (Task 6 later swaps its `HOME` lines for the shared isolation snippet):

```sh
#!/bin/sh
# ABOUTME: Checks kata/board-report against fixture ledgers, handoff records, and a fixture open-issue list.
# ABOUTME: Compares the text report exactly, checks the JSON shape, and proves unsafe records are refused.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
report="$pipeline_dir/board-report"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v jq >/dev/null
# The report prints commands as ~/... under the operator's home; a fixture home keeps the expected text fixed.
HOME="$test_root/home"
mkdir -p "$HOME"
export HOME

mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Fixture kata for report tests: answers only the open-issue listing.
# ABOUTME: Rejects every other call so the report stays read-only.
set -eu
[ "$1" = list ] && [ "$2" = --workspace ] || exit 91
shift 3
[ "$*" = '--status open --limit 0 --json' ] || exit 92
cat <<'JSON'
{"issues":[
  {"uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","status":"open","owner":"kata-pipeline-d1d1d1d1d1d1","labels":["needs-decision"]},
  {"uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","status":"open","owner":"kata-pipeline-f1f1f1f1f1f1","labels":["needs-review","task"]},
  {"uid":"01UNTOUCHED000000000000000","qualified_id":"demo#a2j0","status":"open","owner":"kata-pipeline-b20d9e898b16","labels":null},
  {"uid":"01UNOWNED00000000000000000","qualified_id":"demo#zz11","status":"open","owner":null,"labels":["task"]}
]}
JSON
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"

repo="$test_root/repo"
git init -q -b main "$repo"
repo=$(cd "$repo" && pwd -P)
runs="$repo/.tracker/runs"
base=1234abcd1234abcd1234abcd1234abcd1234abcd
head=9abcdef09abcdef09abcdef09abcdef09abcdef0
wip=5678ef015678ef015678ef015678ef015678ef01
short_base=$(printf '%.12s' "$base")
short_wip=$(printf '%.12s' "$wip")

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

ledger() {
  mkdir -p "$runs/$1/board"
  printf '%s\n' "$2" >"$runs/$1/board/state.json"
}

handoff() {
  mkdir -p "$runs/$1"
  printf '%s\n' "$2" >"$runs/$1/handoff.json"
}

selected() {
  mkdir -p "$runs/$1"
  printf '%s\n' "$2" >"$runs/$1/selected.json"
}

ledger older '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"three consecutive failed children","runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"}]}'
touch -t 202001010000 "$runs/older/board/state.json"
ledger newer '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://github.com/o/r/pull/12"},
  {"run_id":"d1d1d1d1d1d1","kind":"failed","issue_uid":"01DECISION0000000000000000","branch":"kata/n4vr-d1d1d1d1d1d1","reason":"decision","label":"needs-decision"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"}]}'
selected c1c1c1c1c1c1 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}'
handoff d1d1d1d1d1d1 '{"run_id":"d1d1d1d1d1d1","issue_uid":"01DECISION0000000000000000","qualified_id":"demo#n4vr","reason":"decision","label":"needs-decision","branch":"kata/n4vr-d1d1d1d1d1d1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":"Should the CLI accept --format=json\nas well as --json?"}'
handoff f1f1f1f1f1f1 '{"run_id":"f1f1f1f1f1f1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/bq4e-f1f1f1f1f1f1","base_commit":"'"$base"'","wip_commit":"'"$wip"'","start_branch":"main","question":null}'
handoff b1b1b1b1b1b1 '{"run_id":"b1b1b1b1b1b1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"turn_limit","label":"needs-review","branch":"kata/bq4e-b1b1b1b1b1b1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'

# Tracker reflows the review at 76 columns: every line is short, no line depends on its indent,
# and every command is whole on one line with its path quoted.
cat >"$test_root/expected" <<EXPECTED
Board newer in $repo: finished
Completed (1)
- demo#5fav on kata/5fav-c1c1c1c1c1c1
  https://github.com/o/r/pull/12
Needs decision (1)
- demo#n4vr: needs a decision (run d1d1d1d1d1d1)
  branch kata/n4vr-d1d1d1d1d1d1, base $short_base, wip none
  Q: Should the CLI accept --format=json as well as --json?
  '$pipeline_dir/answer' demo#n4vr "<your answer>"
Needs review (1)
- demo#bq4e: review rejected (run f1f1f1f1f1f1)
  branch kata/bq4e-f1f1f1f1f1f1, base $short_base, wip $short_wip
  git diff $short_base..kata/bq4e-f1f1f1f1f1f1
  '$pipeline_dir/answer' demo#bq4e "<guidance>"
Remaining open (2)
- demo#a2j0 owned by kata-pipeline-b20d9e898b16
- demo#zz11 owned by nobody, labels task
EXPECTED
(cd "$repo" && "$report") >"$test_root/output" 2>&1 || fail 'report failed for the newest run'
diff -u "$test_root/expected" "$test_root/output" || fail 'text report differs from the expected output'
printf 'ok - the text report picks the newest board run and groups its katas\n'

(cd "$repo" && "$report" --json newer) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed'
jq -e --arg repo "$repo" --arg answer "$pipeline_dir/answer" --arg base "$base" --arg wip "$wip" --arg short "$short_base" '
  .board_run_id == "newer" and .workspace == $repo and .pipeline == "/p/complete.dip" and .finished == true and
  .stop_reason == null and .stop_child == null and
  [.completed[].qualified_id] == ["demo#5fav"] and .completed[0].run_id == "c1c1c1c1c1c1" and
  .completed[0].pr_url == "https://github.com/o/r/pull/12" and .completed[0].next == [] and
  [.needs_decision[].qualified_id] == ["demo#n4vr"] and
  .needs_decision[0].question == "Should the CLI accept --format=json\nas well as --json?" and
  .needs_decision[0].owner == "kata-pipeline-d1d1d1d1d1d1" and .needs_decision[0].labels == ["needs-decision"] and
  .needs_decision[0].next == ["\($answer) demo#n4vr \"<your answer>\""] and
  [.needs_review[].qualified_id] == ["demo#bq4e"] and .needs_review[0].reason == "review" and
  .needs_review[0].base_commit == $base and .needs_review[0].wip_commit == $wip and
  .needs_review[0].next == ["git diff \($short)..kata/bq4e-f1f1f1f1f1f1", "\($answer) demo#bq4e \"<guidance>\""] and
  [.remaining[].qualified_id] == ["demo#a2j0","demo#zz11"] and [.remaining[].labels] == [[],["task"]] and
  [.remaining[].owner] == ["kata-pipeline-b20d9e898b16",null] and
  ([.completed[], .needs_decision[], .needs_review[], .remaining[]] |
    all(keys == ["base_commit","branch","issue_uid","labels","next","owner","pr_url","qualified_id","question","reason","run_id","wip_commit"]))
' "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'json report has the wrong shape'; }
printf 'ok - the JSON report carries every field for agents\n'

(cd "$repo" && "$report" older) >"$test_root/output" 2>&1 || fail 'report failed for a named run'
grep -Fx "Board older in $repo: stopped" "$test_root/output" >/dev/null || fail 'older: header is wrong'
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null || fail 'older: stop reason is missing'
grep -Fx -e '- demo#bq4e: turn limit reached twice (run b1b1b1b1b1b1)' "$test_root/output" >/dev/null || fail 'older: review row is wrong'
grep -Fx "  branch kata/bq4e-b1b1b1b1b1b1, base $short_base, wip none" "$test_root/output" >/dev/null || fail 'older: branch line is wrong'
grep -Fx 'Remaining open (3)' "$test_root/output" >/dev/null || fail 'older: remaining count is wrong'
printf 'ok - a named stopped run reports its stop reason under the header\n'

ledger nullreason '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"runs":[
  {"run_id":"a1a1a1a1a1a1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-a1a1a1a1a1a1","reason":null,"label":"needs-review"}]}'
handoff a1a1a1a1a1a1 '{"run_id":"a1a1a1a1a1a1","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":null,"label":"needs-review","branch":"kata/bq4e-a1a1a1a1a1a1","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'
(cd "$repo" && "$report" nullreason) >"$test_root/output" 2>&1 || fail 'report failed for a handoff without a reason'
grep -Fx 'Needs review (1)' "$test_root/output" >/dev/null || fail 'null reason: the review group is missing'
grep -Fx -e '- demo#bq4e: handed off (run a1a1a1a1a1a1)' "$test_root/output" >/dev/null || fail 'null reason: the kata row is wrong'
printf 'ok - a handoff record without a reason still reports its kata\n'

# A board that swept more than once carries several entries for one kata; the latest one is its state.
ledger resweep '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://github.com/o/r/pull/12"},
  {"run_id":"e2e2e2e2e2e2","kind":"empty"},
  {"run_id":"a2a2a2a2a2a2","kind":"completed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-a2a2a2a2a2a2","commit":"'"$wip"'","github":null,"pr_url":""},
  {"run_id":"e3e3e3e3e3e3","kind":"empty"}]}'
selected a2a2a2a2a2a2 '{"issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e"}'
cat >"$test_root/expected" <<EXPECTED
Board resweep in $repo: finished
Completed (2)
- demo#5fav on kata/5fav-c1c1c1c1c1c1
  https://github.com/o/r/pull/12
- demo#bq4e on kata/bq4e-a2a2a2a2a2a2
  no pull request
Needs decision (0)
Needs review (0)
Remaining open (3)
- demo#n4vr owned by kata-pipeline-d1d1d1d1d1d1, labels needs-decision
- demo#a2j0 owned by kata-pipeline-b20d9e898b16
- demo#zz11 owned by nobody, labels task
EXPECTED
(cd "$repo" && "$report" resweep) >"$test_root/output" 2>&1 || fail 'report failed for a ledger with several sweeps'
diff -u "$test_root/expected" "$test_root/output" || fail 'resweep: text report differs from the expected output'
ledger twice '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"b1b1b1b1b1b1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-b1b1b1b1b1b1","reason":"turn_limit","label":"needs-review"},
  {"run_id":"e1e1e1e1e1e1","kind":"empty"},
  {"run_id":"f1f1f1f1f1f1","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-f1f1f1f1f1f1","reason":"review","label":"needs-review"},
  {"run_id":"e2e2e2e2e2e2","kind":"empty"}]}'
(cd "$repo" && "$report" --json twice) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for a kata handed off twice'
jq -e '.completed == [] and [.needs_review[] | .run_id] == ["f1f1f1f1f1f1"] and .needs_review[0].reason == "review"' \
  "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'twice: the latest handoff is not the only one reported'; }
printf 'ok - a kata handed off and later finished, or handed off twice, is reported once by its latest run\n'

# An inspection stop names the child; the review prints the command that resumes it.
ledger inspect '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"child a1b2c3d4e5f6 needs inspection","stop_child":"a1b2c3d4e5f6","runs":[]}'
(cd "$repo" && "$report" inspect) >"$test_root/output" 2>&1 || fail 'report failed for an inspection stop'
grep -Fx "Board inspect in $repo: stopped" "$test_root/output" >/dev/null || fail 'inspect: header is wrong'
grep -Fx 'Stop reason: child a1b2c3d4e5f6 needs inspection' "$test_root/output" >/dev/null || fail 'inspect: stop reason is missing'
grep -Fx "  tracker -r a1b2c3d4e5f6 '/p/complete.dip'" "$test_root/output" >/dev/null || fail 'inspect: the resume command is missing'
(cd "$repo" && "$report" --json inspect) >"$test_root/report.json" 2>"$test_root/output" || fail 'json report failed for an inspection stop'
jq -e '.stop_child == "a1b2c3d4e5f6" and .pipeline == "/p/complete.dip" and
  .stop_reason == "child a1b2c3d4e5f6 needs inspection" and .completed == [] and .needs_review == []' \
  "$test_root/report.json" >/dev/null || { cat "$test_root/report.json" >&2; fail 'inspect: json lacks the stop fields'; }
ledger badchild '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":false,"stop_reason":"child ../x needs inspection","stop_child":"../x","runs":[]}'
status=0
(cd "$repo" && "$report" badchild) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "badchild exited $status, expected 1"
grep -F 'invalid board ledger' "$test_root/output" >/dev/null || fail 'badchild: message is wrong'
printf 'ok - an inspection stop prints the resume command, and a malformed child id is refused\n'

# Records a worker's run can write must not reach a pasteable command unchecked.
ledger poison-branch '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"b2b2b2b2b2b2","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/x","reason":"review","label":"needs-review"}]}'
# The $(id) below is the payload under test, not an expansion.
# shellcheck disable=SC2016
handoff b2b2b2b2b2b2 '{"run_id":"b2b2b2b2b2b2","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/x$(id)","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'
ledger poison-dots '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"c2c2c2c2c2c2","kind":"failed","issue_uid":"01REVIEW000000000000000000","branch":"kata/x","reason":"review","label":"needs-review"}]}'
handoff c2c2c2c2c2c2 '{"run_id":"c2c2c2c2c2c2","issue_uid":"01REVIEW000000000000000000","qualified_id":"demo#bq4e","reason":"review","label":"needs-review","branch":"kata/x..main","base_commit":"'"$base"'","wip_commit":null,"start_branch":"main","question":null}'
ledger poison-pr '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"d2d2d2d2d2d2","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-d2d2d2d2d2d2","commit":"'"$head"'","github":{"remote":"origin","repository":"o/r","base_branch":"main"},"pr_url":"https://evil.example/o/r/pull/12"}]}'
selected d2d2d2d2d2d2 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}'
ledger poison-id '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"f2f2f2f2f2f2","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-f2f2f2f2f2f2","commit":"'"$head"'","github":null,"pr_url":""}]}'
selected f2f2f2f2f2f2 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav; id"}'
refuse() {
  status=0
  (cd "$repo" && "$report" "$@") >"$test_root/output" 2>&1 || status=$?
  [ "$status" -eq 1 ] || fail "$*: exited $status, expected 1"
  grep -F 'unsafe' "$test_root/output" >/dev/null || fail "$*: the refusal message is missing"
  if grep -F 'git diff' "$test_root/output" >/dev/null; then fail "$*: a command was printed"; fi
}
for poison in poison-branch poison-dots poison-pr poison-id; do
  refuse "$poison"
  refuse --json "$poison"
done
printf 'ok - a record with an unsafe branch, id, or pull request URL is refused whole\n'

(cd "$repo" && "$report" -h) >"$test_root/output" 2>&1 || fail '-h failed'
grep -F 'Usage: board-report' "$test_root/output" >/dev/null || fail '-h lacks usage'
status=0
(cd "$test_root" && "$report") >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "outside a repository exited $status, expected 1"
grep -Fx 'run this from inside the target Git repository' "$test_root/output" >/dev/null || fail 'outside a repository: message is wrong'
(cd "$repo" && HOME="$pipeline_dir" "$report" newer) >"$test_root/output" 2>&1 || fail 'report failed with the pipeline under HOME'
grep -Fx '  ~/answer demo#n4vr "<your answer>"' "$test_root/output" >/dev/null || fail 'a pipeline under HOME is not printed as ~/'
printf 'ok - board-report accepts -h, refuses to run outside a repository, and shortens paths under HOME\n'

status=0
(cd "$repo" && "$report" missing) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "missing run exited $status, expected 1"
grep -F 'no board ledger' "$test_root/output" >/dev/null || fail 'missing run: message is wrong'
rm "$runs/f1f1f1f1f1f1/handoff.json"
status=0
(cd "$repo" && "$report" newer) >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "missing handoff exited $status, expected 1"
grep -F 'failed child f1f1f1f1f1f1 has no handoff record' "$test_root/output" >/dev/null || fail 'missing handoff: message is wrong'
printf 'ok - a missing ledger or handoff record is an error, not a guess\n'
```

Then point three assertions in `kata/tests/board.sh` at the new layout (line numbers are hints; anchor on the quoted text). A grep pattern that starts with `-` needs `-e`, or grep reads it as an option. In the `stacked` case (line 332), replace

```sh
grep -Fx '  fixture#fixture-item-2  kata/item-2  https://github.com/fixture/board/pull/2' "$test_root/output" >/dev/null
```

with

```sh
grep -Fx -e '- fixture#fixture-item-2 on kata/item-2' "$test_root/output" >/dev/null
grep -Fx '  https://github.com/fixture/board/pull/2' "$test_root/output" >/dev/null
```

In the handed-off case (line 380), replace

```sh
grep -F '  fixture#fixture-item-1  worker stopped; branch kata/item-1' "$test_root/output" >/dev/null
```

with

```sh
grep -F -e '- fixture#fixture-item-1: worker stopped (run ' "$test_root/output" >/dev/null
```

In the `blocked` case (line 443), replace

```sh
grep -Fx '  blocked-item  owned by another-actor' "$test_root/output" >/dev/null
```

with

```sh
grep -Fx -e '- blocked-item owned by another-actor' "$test_root/output" >/dev/null
```

Leave the line `[ "$(grep -c 'fixture#fixture-item-1' "$test_root/output")" -eq 1 ]` alone: the new layout still names a finished kata exactly once.

- [ ] **Step 2: Run both tests and watch them fail**

Run: `sh kata/tests/report.sh; printf 'exit %s\n' "$?"`
Expected: `exit 1`. The first `diff` hunk shows the expected lines against the old one-line form:

```
-- demo#5fav on kata/5fav-c1c1c1c1c1c1
-  https://github.com/o/r/pull/12
+  demo#5fav  kata/5fav-c1c1c1c1c1c1  https://github.com/o/r/pull/12
```

Run: `sh kata/tests/board.sh; printf 'exit %s\n' "$?"`
Expected: `exit 1` with no `ok -` line at all. The `stacked` case's changed grep fails silently, because Task 4 has not yet given the board assertions messages.

- [ ] **Step 3: Replace the report**

Replace the whole of `kata/board-report` with this file, then run `chmod 755 kata/board-report`:

```sh
#!/bin/sh
# ABOUTME: Prints the morning review for a board run: completed katas, katas needing a decision or review, remaining open.
# ABOUTME: Reads the board ledger, child records, and the live open list read-only; --json emits the same data for agents.
set -eu

usage() {
  printf 'Usage: board-report [--json] [BOARD_RUN_ID]\nRun from the target Git root. Without an ID it reports the newest board run under .tracker/runs.\n'
}
format=text
if [ "${1:-}" = --json ]; then
  format=json
  shift
fi
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }
command -v git >/dev/null
command -v jq >/dev/null
command -v kata >/dev/null
kata_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd -P)
top=$(git rev-parse --show-toplevel 2>/dev/null) || { printf 'run this from inside the target Git repository\n' >&2; exit 1; }
workspace=$(cd -- "$top" && pwd -P)
# Commands print as ~/... when the pipeline lives under the operator's home, so they stay short and pasteable.
home=$(CDPATH='' cd -- "${HOME:-/nonexistent}" 2>/dev/null && pwd -P || true)
runs="$workspace/.tracker/runs"
board_id=${1:-}
if [ -z "$board_id" ]; then
  # The board rewrites its ledger after every child, so the newest ledger belongs to the latest board run.
  newest=
  for ledger in "$runs"/*/board/state.json; do
    [ -f "$ledger" ] || continue
    if [ -z "$newest" ] || [ -n "$(find "$ledger" -newer "$newest")" ]; then
      newest=$ledger
    fi
  done
  [ -n "$newest" ] || { printf 'no board run found under %s\n' "$runs" >&2; exit 1; }
  board_id=$(basename "$(dirname "$(dirname "$newest")")")
fi
case "$board_id" in ''|*/*|.|..) printf 'invalid board run id: %s\n' "$board_id" >&2; exit 2 ;; esac
ledger="$runs/$board_id/board/state.json"
[ -f "$ledger" ] || { printf 'no board ledger at %s\n' "$ledger" >&2; exit 1; }
# The controller writes the ledger, but every child run id in it names a directory this script reads,
# so each id is checked before it touches a path.
jq -e '(.finished | type == "boolean") and (.runs | type == "array") and
  (.stop_reason == null or (.stop_reason | type == "string")) and
  (.stop_child == null or ((.stop_child | type == "string" and test("^[a-f0-9]{12}$")) and
    (.pipeline | type == "string" and length > 0))) and
  all(.runs[]; (.run_id | type == "string" and test("^[a-f0-9]{12}$")) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty") and
    (.kind == "empty" or (.issue_uid | type == "string" and length > 0)))' "$ledger" >/dev/null ||
  { printf 'invalid board ledger: %s\n' "$ledger" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' HUP INT TERM
kata list --workspace "$workspace" --status open --limit 0 --json >"$tmp/open.json"
jq -e '.issues | type == "array"' "$tmp/open.json" >/dev/null || { printf 'invalid open-board response\n' >&2; exit 1; }

# One item per kata, in ledger order. A board that swept more than once carries several entries
# for one kata; only its latest entry describes it. Empty attempts carry no kata.
: >"$tmp/items.jsonl"
jq -c '.runs as $runs | $runs | to_entries[] | select(.value.kind != "empty") |
  select(.key as $i | .value.issue_uid as $uid | any($runs[$i + 1:][]; .issue_uid == $uid) | not) | .value' \
  "$ledger" >"$tmp/runs.jsonl"
while IFS= read -r entry; do
  kind=$(printf '%s' "$entry" | jq -r '.kind')
  run_id=$(printf '%s' "$entry" | jq -r '.run_id')
  child="$runs/$run_id"
  case "$kind" in
    completed)
      qualified=$(jq -er '.qualified_id' "$child/selected.json" 2>/dev/null) ||
        { printf 'completed child %s has no selection record: %s\n' "$run_id" "$child/selected.json" >&2; exit 1; }
      printf '%s' "$entry" | jq -c --arg qualified "$qualified" '{group:"completed",qualified_id:$qualified,issue_uid,run_id,branch,
        base_commit:null,wip_commit:null,pr_url:(if .pr_url == "" then null else .pr_url end),reason:null,question:null}' \
        >>"$tmp/items.jsonl"
      ;;
    failed)
      [ -f "$child/handoff.json" ] ||
        { printf 'failed child %s has no handoff record: %s\n' "$run_id" "$child/handoff.json" >&2; exit 1; }
      jq -c '{group:(if .reason == "decision" then "needs_decision" else "needs_review" end),
        qualified_id,issue_uid,run_id,branch,base_commit,wip_commit,pr_url:null,reason,question}' \
        "$child/handoff.json" >>"$tmp/items.jsonl"
      ;;
  esac
done <"$tmp/runs.jsonl"

# Child records are written by the worker's run. Every field that reaches a pasteable command
# must look like what it claims to be, or the whole review is refused.
jq -se --arg qid '^[A-Za-z0-9._-]+(#[A-Za-z0-9._-]+)?$' --arg branch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' \
  --arg commit '^([0-9a-f]{40}|[0-9a-f]{64})$' --arg pr '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$' '
  def clean: type == "string" and (test("[[:cntrl:]]") | not);
  def commit_or_null: . == null or (clean and test($commit));
  all(.[]; (.qualified_id | clean and test($qid)) and
    (.branch | clean and test($branch) and (contains("..") | not)) and
    (.base_commit | commit_or_null) and (.wip_commit | commit_or_null) and
    (.pr_url == null or (.pr_url | clean and test($pr))))
' "$tmp/items.jsonl" >/dev/null ||
  { printf 'refusing to print the review: a child record under %s has a missing or unsafe id, branch, commit, or pull request URL\n' "$runs" >&2; exit 1; }

jq -n --arg board "$board_id" --arg workspace "$workspace" --arg answer "$kata_dir/answer" \
  --slurpfile state "$ledger" --slurpfile listing "$tmp/open.json" --slurpfile entries "$tmp/items.jsonl" '
  def short: if . == null then "none" else .[0:12] end;
  def next: if .group == "needs_decision" then ["\($answer) \(.qualified_id) \"<your answer>\""]
    elif .group == "needs_review" then
      (if .base_commit == null then [] else ["git diff \(.base_commit | short)..\(.branch)"] end) +
      ["\($answer) \(.qualified_id) \"<guidance>\""]
    else [] end;
  $state[0] as $ledger | $listing[0].issues as $issues |
  [$ledger.runs[] | .issue_uid // empty] as $touched |
  # Handed-off katas are still open: show their live owner and labels beside the handoff record.
  ($entries | map(. as $item | ([$issues[] | select(.uid == $item.issue_uid)] | first) as $live |
    $item + (if $item.group == "completed" then {owner:null, labels:[]}
             else {owner:($live.owner // null), labels:($live.labels // [])} end) + {next:($item | next)})) as $items |
  {board_run_id:$board, workspace:$workspace, pipeline:($ledger.pipeline // null), finished:$ledger.finished,
   stop_reason:($ledger.stop_reason // null), stop_child:($ledger.stop_child // null),
   completed:[$items[] | select(.group == "completed")],
   needs_decision:[$items[] | select(.group == "needs_decision")],
   needs_review:[$items[] | select(.group == "needs_review")],
   remaining:[$issues[] | select(.uid as $uid | any($touched[]; . == $uid) | not) |
     {qualified_id, issue_uid:.uid, run_id:null, branch:null, base_commit:null, wip_commit:null, pr_url:null,
      reason:null, question:null, owner:(.owner // null), labels:(.labels // []), next:[]}]}
  | (.completed, .needs_decision, .needs_review) |= map(del(.group))
' >"$tmp/report.json"

if [ "$format" = json ]; then
  cat "$tmp/report.json"
  exit 0
fi
# Tracker reflows this text at 76 columns and strips indentation before a person sees it, so every
# line is short, no line depends on its indent, and each command is whole on one line.
jq -r --arg kata "$kata_dir" --arg home "$home" --arg q "'" '
  def sq: $q + gsub($q; $q + "\\" + $q + $q) + $q;
  def flat: if . == null then "" else tostring | gsub("[[:cntrl:]]+"; " ") end;
  def short: if . == null then "none" else .[0:12] end;
  def path_arg: if $home != "" and startswith($home + "/") and test("^[A-Za-z0-9._/-]+$")
    then "~" + .[($home | length):] else sq end;
  def reason_text: . as $reason |
    ({decision:"needs a decision", publish:"publication failed", review:"review rejected",
      turn_limit:"turn limit reached twice", implement:"worker stopped",
      unexpected_checkout:"handoff found the wrong branch"} | .[$reason]?) //
    (if $reason == null or $reason == "" then "handed off" else ($reason | flat) end);
  def next_lines: .next[] | "  " + (if startswith($kata + "/answer ") then (($kata + "/answer") | path_arg) + ltrimstr($kata + "/answer") else . end);
  def kata_lines: "- \(.qualified_id): \(.reason | reason_text) (run \(.run_id))",
    "  branch \(.branch), base \(.base_commit | short), wip \(.wip_commit | short)";
  "Board \(.board_run_id) in \(.workspace): \(if .stop_reason != null then "stopped" elif .finished then "finished" else "in progress" end)",
  (if .stop_reason != null then "Stop reason: \(.stop_reason | flat)" else empty end),
  (if .stop_child != null then "  tracker -r \(.stop_child) \(.pipeline | path_arg)" else empty end),
  "Completed (\(.completed | length))",
  (.completed[] | "- \(.qualified_id) on \(.branch)", "  \(.pr_url // "no pull request")"),
  "Needs decision (\(.needs_decision | length))",
  (.needs_decision[] | kata_lines, "  Q: \(.question | flat)", next_lines),
  "Needs review (\(.needs_review | length))",
  (.needs_review[] | kata_lines, next_lines),
  "Remaining open (\(.remaining | length))",
  (.remaining[] | "- \(.qualified_id | flat) owned by \(.owner | flat | if . == "" then "nobody" else . end)\(if (.labels | length) > 0 then ", labels \(.labels | map(flat) | join(","))" else "" end)")
' "$tmp/report.json"
```

- [ ] **Step 4: Run both tests and watch them pass**

Run: `sh kata/tests/report.sh`
Expected: exactly these nine lines, exit 0:

```
ok - the text report picks the newest board run and groups its katas
ok - the JSON report carries every field for agents
ok - a named stopped run reports its stop reason under the header
ok - a handoff record without a reason still reports its kata
ok - a kata handed off and later finished, or handed off twice, is reported once by its latest run
ok - an inspection stop prints the resume command, and a malformed child id is refused
ok - a record with an unsafe branch, id, or pull request URL is refused whole
ok - board-report accepts -h, refuses to run outside a repository, and shortens paths under HOME
ok - a missing ledger or handoff record is an error, not a guess
```

Run: `sh kata/tests/board.sh`
Expected: every `ok -` line, exit 0.

Run: `shellcheck kata/board-report kata/tests/report.sh kata/tests/board.sh`
Expected: no output.

- [ ] **Step 5: Commit**

```sh
git status
git add kata/board-report kata/tests/report.sh kata/tests/board.sh
git commit -m 'fix(kata): validate board records and print a pasteable review'
```

### Task 3: Every stop after the ledger exists holds the morning review (C1, I2, M12)

**Files:**
- Modify: `kata/scripts/run-board.sh` (the three `:?` lines; the ledger validation `jq -e`; the functions `set_stop_reason`, `stop_child`, and `stop_board`; the three-failure block in `record_failure`; the loop's `del(.stop_reason)`; the report call and the marker `if` at the tail; every `|| stop_child` call site)
- Modify: `kata/tests/board.sh` (the helpers `must_stop`, `must_stop_without_git_status`, and `must_not_report`; the cases `three-failures`, `recovery`, `unexpected-checkout`, `handoff-guards`, `broken-list`, and `nested-failure`; new cases `preflight-stops`, `refused-record`, and `nested-stop`)

**Interfaces:**
- Consumes: from Task 2, the review's header line `Board <board-run-id> in <workspace>: stopped`, its `Stop reason: <reason>` line, its `  tracker -r <child-id> <pipeline path>` line (printed when the ledger has `stop_child`), and its stderr line `refusing to print the review: a child record under <runs dir> has a missing or unsafe id, branch, commit, or pull request URL`; from Task 1, the `fail MESSAGE [LOG]` helper in `kata/tests/board.sh` and the event idiom `sub("^[^{]*"; "") | fromjson?`.
- Produces: the ledger fields `stop_reason` (a string) and `stop_child` (12 hex characters, present only when a child needs inspection; the loop deletes both at the start of each iteration). Controller exit status 0 with `board-needs-human` as the last stdout line for every stop once the ledger exists; exit status 1 with no marker and no review for the failures before it exists (an unset Tracker variable, a missing tool, a lock held by a live controller, a ledger the controller does not trust). Stderr lines: `run-board.sh runs under tracker: TRACKER_RUN_DIR, TRACKER_RUN_ID, and TRACKER_WORKDIR must be set`; `board report failed; run board-report <board-run-id> from the target Git root`; `Recover the child in <workspace> with tracker -r <child-id> <pipeline>, then choose Sweep again at the morning review.` Shell functions in `run-board.sh`: `stop_board REASON [CHILD]`, `stop_for_inspection`, `print_review`. Test helpers in `board.sh`: `must_stop LABEL`, `must_stop_for_inspection LABEL`, `must_stop_without_git_status LABEL`, `must_refuse LABEL MESSAGE` (reads `$status`). Tasks 4, 5, and 7 edit these helpers and cases by the text this task gives them.

The name collision: `run-board.sh` has a shell function `stop_child`, and the ledger field this task adds is also `stop_child` (Task 2's report already reads the field). The function becomes `stop_for_inspection`; from this task on, `stop_child` names only the ledger field. `set_stop_reason` goes away: `stop_board` writes the reason and the child in one `write_state` call.

Facts this task relies on (probed 2026-09-18 on Tracker 0.73.1 in a disposable repository with an isolated `HOME`): a parent workflow shaped like `kata/board.dip` whose RunBoard node prints `board-needs-human` opens the gate with `gate_opened.gate_prompt` holding the prompt text followed by a fenced `## Tool Stdout` block that carries the Report node's stdout verbatim, indentation included (`Stop reason: three consecutive failed children` and `  tracker -r <child-id> <pipeline>` appear as whole lines), and `gate_resolved.gate_response` holds the choice value; piping `1` to that gate answers `done` and the run exits 0. Today an unset `TRACKER_RUN_DIR` makes `sh` print its own diagnostic of the form `<script>: line <n>: TRACKER_RUN_DIR: TRACKER_RUN_DIR is required` and exit 1. `kata/board-report` runs one Git command, `git rev-parse --show-toplevel` (its line 20), so the test's failing `git status` wrapper does not stop the review.

**Why:** Today `stop_child` and `stop_board` exit 1 and the three-failure block exits 1 after printing the review. Under Tracker, an exit 1 from RunBoard is a tool failure with no marker: the parent run fails without a checkpoint, nobody sees the review, and the child that needs inspection is named only in a `child.log` under the run directory (C1). The ledger validation accepts a `failed` or `completed` entry without `issue_uid`, which the report and the reclaim logic both depend on, and it does not know the `stop_child` field the report reads (I2). An unset Tracker variable prints the shell's `set -u` diagnostic, which names the script's internals instead of saying how the controller is meant to run (M12). After this task every stop once the ledger exists records why, prints the review, prints `board-needs-human`, and exits 0, so the parent holds at the morning review with the reason at the top of the prompt. Failures before the ledger exists still exit 1: there is nothing to record yet, and an untrusted ledger must not be written to.

- [ ] **Step 1: Write the failing tests**

Edit `kata/tests/board.sh`. Every edit below anchors on text that is in the file after Tasks 1 and 2.

Replace the three helpers from the line `must_stop() {` through the closing `}` of `must_not_report` (the block starts with the text below and ends with the line `}` that follows `printf 'FAIL: the morning review was printed after %s\n' "$1" >&2`, `cat "$test_root/output" >&2`, `exit 1`, and `fi`):

```sh
must_stop() {
  if run_board; then
    printf 'FAIL: board accepted %s\n' "$1" >&2
    exit 1
  fi
}
```

with these four helpers:

```sh
# Every stop after the ledger exists holds the parent at the morning review: exit 0, a reason in the ledger,
# the review printed, and the marker last. Callers check the reason they expect.
must_stop() {
  run_board || fail "$1: the controller exited $? instead of holding the board for a person"
  jq -e '.finished == false and (.stop_reason | type == "string" and length > 0)' "$ledger" >/dev/null ||
    fail "$1: the ledger has no stop reason"
  grep -Fx "Board $TRACKER_RUN_ID in $repo: stopped" "$test_root/output" >/dev/null || fail "$1: the review was not printed after the stop"
  expect_marker board-needs-human "$1"
}

# An inspection stop names the last claimed child, so the review can print its resume command.
must_stop_for_inspection() {
  must_stop "$1"
  inspected=$(tail -n 1 "$fixture/claims")
  jq -e --arg child "$inspected" '.stop_reason == "child \($child) needs inspection" and .stop_child == $child' "$ledger" >/dev/null ||
    fail "$1: the ledger does not name child $inspected for inspection"
  grep -F "Child run $inspected needs inspection" "$test_root/output" >/dev/null || fail "$1: the inspection message is missing"
  grep -Fx "Stop reason: child $inspected needs inspection" "$test_root/output" >/dev/null || fail "$1: the review lacks the stop reason"
  grep -F "  tracker -r $inspected " "$test_root/output" >/dev/null || fail "$1: the review lacks the child resume command"
}

# A git status the board could not run is not a clean tree. Only that one command fails; the review still
# prints, because board-report runs only git rev-parse.
must_stop_without_git_status() {
  cat >"$test_root/bin/git" <<SH
#!/bin/sh
# ABOUTME: Fails every git status so a broken status cannot pass for a clean tree.
# ABOUTME: Hands every other Git command to the real binary unchanged.
set -eu
[ "\${1:-}" != status ] || { printf 'fixture git status failure\n' >&2; exit 128; }
exec $real_git "\$@"
SH
  chmod +x "$test_root/bin/git"
  must_stop "$1"
  rm "$test_root/bin/git"
  jq -e '.stop_reason == "git status failed; inspect the checkout" and (has("stop_child") | not)' "$ledger" >/dev/null ||
    fail "$1: the ledger does not record the git status failure without a child"
  grep -Fx 'git status failed; inspect the checkout' "$test_root/output" >/dev/null || fail "$1: the git status message is missing"
  grep -Fx 'Stop reason: git status failed; inspect the checkout' "$test_root/output" >/dev/null || fail "$1: the review lacks the stop reason"
}

# Before a ledger exists nothing can hold the parent, so the controller exits 1 with a message, no review, and no marker.
must_refuse() {
  [ "$status" -ne 0 ] || fail "$1: the controller exited 0"
  grep -F "$2" "$test_root/output" >/dev/null || fail "$1: the message '$2' is missing"
  if grep -Fx 'board-needs-human' "$test_root/output" >/dev/null; then fail "$1: the controller printed the marker"; fi
  if grep -F "Board $TRACKER_RUN_ID in" "$test_root/output" >/dev/null; then fail "$1: the controller printed the review"; fi
}
```

Replace the `three-failures` case, from the line `new_case three-failures 4` through its line `printf 'ok - three consecutive failures stop the board and a parent resume claims again\n'`, with:

```sh
new_case three-failures 4
printf '1\n2\n3\n' >"$fixture/fail-implement"
must_stop 'three consecutive failed children'
jq -e '.finished == false and .stop_reason == "three consecutive failed children" and (has("stop_child") | not) and
  [.runs[].kind] == ["failed","failed","failed"]' "$ledger" >/dev/null || fail 'three-failures: the ledger does not record the streak'
[ "$(claim_count)" -eq 3 ] || fail "three-failures: claim count is $(claim_count), expected 3"
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'three-failures: the checkout is not back on main'
grep -F 'Board stopped after three consecutive failed children' "$test_root/output" >/dev/null || fail 'three-failures: the stop message is missing'
grep -Fx 'Needs review (3)' "$test_root/output" >/dev/null || fail 'three-failures: the review does not list three katas'
grep -Fx 'Stop reason: three consecutive failed children' "$test_root/output" >/dev/null || fail 'three-failures: the review lacks the stop reason'
must_succeed 'parent resume after the failure streak'
jq -e '.finished == true and (has("stop_reason") | not) and (has("stop_child") | not) and
  [.runs[].kind] == ["failed","failed","failed","completed","empty"]' "$ledger" >/dev/null || fail 'three-failures: the resume did not claim again'
[ "$(claim_count)" -eq 5 ] || fail "three-failures: claim count is $(claim_count), expected 5"
expect_marker board-needs-human 'a resume after the failure streak'
printf 'ok - three consecutive failures hold the board for a person, and a resume claims again\n'
```

Replace the `recovery` case, from the line `new_case recovery 1` through its line `printf 'ok - an integrity stop halts claims; a real child resume reconciles once without duplicate work\n'`, with:

```sh
new_case recovery 1
: >"$fixture/fail-close"
must_stop_for_inspection 'failed child'
[ "$(claim_count)" -eq 1 ] || fail "recovery: claim count is $(claim_count), expected 1"
failed_child=$(head -n 1 "$fixture/claims")
jq -e '.runs == []' "$ledger" >/dev/null || fail 'recovery: a child that needs inspection was recorded in the ledger'
jq -e '.outcome == "fail"' "$repo/.tracker/runs/$failed_child/CloseSelected/status.json" >/dev/null ||
  fail 'recovery: the child did not fail at CloseSelected'
[ ! -e "$repo/.tracker/runs/$failed_child/handoff.json" ] || fail 'recovery: a closure failure wrote a handoff record'
must_stop_for_inspection 'unrecovered child on parent resume'
[ "$(claim_count)" -eq 1 ] || fail "recovery: a parent resume claimed again; claim count is $(claim_count)"
rm "$fixture/fail-close"
tracker --git off --workdir "$repo" --json --no-tui --resume "$failed_child" "$test_root/workflow/complete.dip" \
  >"$test_root/recovery.log" 2>&1 || fail 'recovery: the real Tracker child resume failed' "$test_root/recovery.log"
[ "$(claim_count)" -eq 1 ] || fail "recovery: the child resume claimed again; claim count is $(claim_count)"
child_dir="$repo/.tracker/runs/$failed_child"
cp "$child_dir/review-scope.approved" "$test_root/scope.approved"
printf 'stale approval\n' >"$child_dir/review-scope.approved"
must_stop_for_inspection 'stale approval after child recovery'
cp "$test_root/scope.approved" "$child_dir/review-scope.approved"
printf 'unfinished work\n' >"$repo/uncommitted.txt"
must_stop_for_inspection 'dirty tree after child recovery'
rm "$repo/uncommitted.txt"
must_stop_without_git_status 'a tree it could not read after child recovery'
git -C "$repo" switch -q main
must_stop_for_inspection 'changed branch after child recovery'
git -C "$repo" switch -q kata/item-1
printf 'open\n' >"$fixture/fixture-item-1.status"
must_stop_for_inspection 'unclosed issue after child recovery'
printf 'closed\n' >"$fixture/fixture-item-1.status"
cp "$child_dir/CloseSelected/status.json" "$test_root/close-status.json"
jq '.context_updates.tool_marker="claim-ok"' "$test_root/close-status.json" >"$child_dir/CloseSelected/status.json"
must_stop_for_inspection 'missing closure marker after child recovery'
cp "$test_root/close-status.json" "$child_dir/CloseSelected/status.json"
[ "$(claim_count)" -eq 1 ] || fail "recovery: the guards claimed again; claim count is $(claim_count)"
must_succeed 'manually recovered child'
jq -e --arg child "$failed_child" '.finished == true and (has("stop_reason") | not) and (has("stop_child") | not) and
  [.runs[].kind] == ["completed","empty"] and .runs[0].run_id == $child' "$ledger" >/dev/null ||
  fail 'recovery: the recovered child was not recorded as completed once'
[ "$(claim_count)" -eq 2 ] || fail "recovery: claim count is $(claim_count), expected 2"
[ "$(git -C "$repo" rev-list --count HEAD)" -eq 2 ] || fail 'recovery: the commit count is not 2'
must_succeed 'a re-entry after the recovered child completed'
jq -e --arg child "$failed_child" '[.runs[].kind] == ["completed","empty","empty"] and .runs[0].run_id == $child' "$ledger" >/dev/null ||
  fail 'recovery: the re-entry did not add one empty sweep'
[ "$(claim_count)" -eq 3 ] || fail "recovery: claim count is $(claim_count), expected 3"
expect_marker board-clean 'a re-entry after the recovered child completed'
printf 'ok - an integrity stop holds the board; a real child resume reconciles once without duplicate work\n'
```

Replace the `unexpected-checkout` case, from the line `new_case unexpected-checkout 1` through its line `printf 'ok - a handoff from the wrong branch stops the board for inspection\n'`, with:

```sh
new_case unexpected-checkout 1
printf '1\n' >"$fixture/leave-branch"
must_stop_for_inspection 'a handoff from a worker that left the task branch'
[ "$(claim_count)" -eq 1 ] || fail "unexpected-checkout: claim count is $(claim_count), expected 1"
failed_child=$(head -n 1 "$fixture/claims")
jq -e '.runs == []' "$ledger" >/dev/null || fail 'unexpected-checkout: the handoff was recorded despite the wrong branch'
jq -e '.reason == "unexpected_checkout" and .start_branch == "main" and .wip_commit == null' \
  "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null || fail 'unexpected-checkout: the handoff record is not an unexpected_checkout'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'unexpected-checkout: the checkout is not on main'
printf 'ok - a handoff from the wrong branch holds the board for inspection\n'
```

Replace the `handoff-guards` case, from the line `new_case handoff-guards 1` through its line `printf 'ok - a failed child is recorded only when its handoff, checkout, tree, and kata all check out\n'`, with:

```sh
new_case handoff-guards 1
printf '1\n' >"$fixture/fail-implement"
: >"$fixture/lose-owner"
must_stop_for_inspection 'a handed-off kata that nobody owns'
[ "$(claim_count)" -eq 1 ] || fail "handoff-guards: claim count is $(claim_count), expected 1"
failed_child=$(head -n 1 "$fixture/claims")
child_dir="$repo/.tracker/runs/$failed_child"
jq -e '.runs == []' "$ledger" >/dev/null || fail 'handoff-guards: an unowned kata was recorded as handed off'
printf 'kata-pipeline-%s\n' "$failed_child" >"$fixture/fixture-item-1.owner"
cp "$child_dir/handoff.json" "$test_root/handoff.json"
jq 'del(.label)' "$test_root/handoff.json" >"$child_dir/handoff.json"
must_stop_for_inspection 'a handoff record without a label'
cp "$test_root/handoff.json" "$child_dir/handoff.json"
cp "$child_dir/Handoff/status.json" "$test_root/handoff-status.json"
jq '.context_updates.tool_stdout = "handoff-maybe"' "$test_root/handoff-status.json" >"$child_dir/Handoff/status.json"
must_stop_for_inspection 'a handoff that never printed its marker'
cp "$test_root/handoff-status.json" "$child_dir/Handoff/status.json"
git -C "$repo" switch -q kata/item-1
must_stop_for_inspection 'a checkout that is not the branch the child started from'
git -C "$repo" switch -q main
printf 'unfinished work\n' >"$repo/uncommitted.txt"
must_stop_for_inspection 'a dirty tree after a handoff'
rm "$repo/uncommitted.txt"
must_stop_without_git_status 'a tree it could not read after a handoff'
[ "$(claim_count)" -eq 1 ] || fail "handoff-guards: the guards claimed again; claim count is $(claim_count)"
must_succeed 'the repaired handoff of a failed child'
jq -e --arg child "$failed_child" '.finished == true and (has("stop_reason") | not) and (has("stop_child") | not) and
  [.runs[].kind] == ["failed","empty"] and .runs[0].run_id == $child' "$ledger" >/dev/null ||
  fail 'handoff-guards: the repaired handoff was not recorded once'
[ "$(claim_count)" -eq 2 ] || fail "handoff-guards: claim count is $(claim_count), expected 2"
printf 'ok - a failed child is recorded only when its handoff, checkout, tree, and kata all check out\n'
```

Replace the `broken-list` case, from the line `new_case broken-list 0` through its line `printf 'ok - a board that stops outside a child records why, and the review says it stopped\n'`, with the text below. With the `broken-list` flag set, the fixture `kata list` answers the report too, so the report refuses and the controller must say so and still print the marker; the review itself is checked after the flag is removed:

```sh
new_case broken-list 0
: >"$fixture/broken-list"
run_board || fail "broken-list: the controller exited $? instead of holding the board for a person"
jq -e '.finished == false and .runs == [] and .stop_reason == "invalid open-board response" and (has("stop_child") | not)' "$ledger" >/dev/null ||
  fail 'broken-list: the ledger does not record the stop without a child'
grep -Fx 'invalid open-board response' "$test_root/output" >/dev/null || fail 'broken-list: the stop message is missing'
grep -Fx 'board report failed; run board-report board-parent from the target Git root' "$test_root/output" >/dev/null ||
  fail 'broken-list: the controller did not say the review failed'
expect_marker board-needs-human 'an open-board response that is not a list'
rm "$fixture/broken-list"
(cd "$repo" && "$pipeline_dir/board-report" "$TRACKER_RUN_ID") >"$test_root/review" 2>&1 ||
  fail 'broken-list: the review failed after the list was repaired' "$test_root/review"
grep -Fx "Board $TRACKER_RUN_ID in $repo: stopped" "$test_root/review" >/dev/null || fail 'broken-list: the review does not say the board stopped' "$test_root/review"
grep -Fx 'Stop reason: invalid open-board response' "$test_root/review" >/dev/null || fail 'broken-list: the review lacks the stop reason' "$test_root/review"
printf 'ok - a board that stops outside a child records why, keeps its marker when the review fails, and the review says it stopped\n'

# Before a ledger exists nothing can hold the parent: an unset Tracker variable, a held lock, or a ledger the
# controller does not trust ends with exit 1, a message, no review, and no marker.
new_case preflight-stops 0
status=0
(unset TRACKER_RUN_DIR; cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
  >"$test_root/output" 2>&1 || status=$?
must_refuse 'an unset TRACKER_RUN_DIR' 'run-board.sh runs under tracker: TRACKER_RUN_DIR, TRACKER_RUN_ID, and TRACKER_WORKDIR must be set'
[ ! -e "$ledger" ] || fail 'an unset TRACKER_RUN_DIR: a ledger was written'
mkdir -p "$TRACKER_RUN_DIR/board/lock"
printf '%s\n' "$$" >"$TRACKER_RUN_DIR/board/lock/pid"
status=0
run_board || status=$?
must_refuse 'a lock held by a live process' "board controller is already running (PID $$)"
[ ! -e "$ledger" ] || fail 'a held lock: a ledger was written'
rm -r "$TRACKER_RUN_DIR/board/lock"
jq -n --arg workspace "$repo" --arg pipeline "$test_root/workflow/complete.dip" \
  '{workspace:$workspace,pipeline:$pipeline,finished:false,runs:[{run_id:"a1a1a1a1a1a1",kind:"failed",branch:"kata/item-1",reason:"implement",label:"needs-review"}]}' >"$ledger"
status=0
run_board || status=$?
must_refuse 'a failed entry without an issue uid' 'invalid board state or changed workspace/pipeline'
jq -n --arg workspace "$repo" --arg pipeline "$test_root/workflow/complete.dip" \
  '{workspace:$workspace,pipeline:$pipeline,finished:false,stop_reason:"child x needs inspection",stop_child:"not-a-run-id",runs:[]}' >"$ledger"
status=0
run_board || status=$?
must_refuse 'a stop_child that is not a run id' 'invalid board state or changed workspace/pipeline'
jq -e '.stop_child == "not-a-run-id" and .runs == []' "$ledger" >/dev/null || fail 'an invalid ledger: the controller changed it'
[ "$(claim_count)" -eq 0 ] || fail "preflight-stops: claim count is $(claim_count), expected 0"
# The same ledger with a well-formed child id is trusted, which shows the refusals above came from the fields they name.
jq '.stop_child = "a1a1a1a1a1a1"' "$ledger" >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"
must_succeed 'a ledger with a well-formed stop_child'
jq -e '.finished == true and (has("stop_reason") | not) and (has("stop_child") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null ||
  fail 'preflight-stops: the trusted ledger did not sweep once'
[ "$(claim_count)" -eq 1 ] || fail "preflight-stops: claim count is $(claim_count), expected 1"
expect_marker board-clean 'a ledger with a well-formed stop_child'
printf 'ok - a failure before a trusted ledger exists exits 1 with a message and no marker; a trusted ledger sweeps\n'

# A record the review refuses must not hide the marker: the run holds at the gate, whose Report node then fails in the open.
new_case refused-record 1
must_succeed 'one completed kata'
jq '.runs[0].pr_url = "https://evil.example/fixture/board/pull/1"' "$ledger" >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"
must_succeed 'a re-entry with a pull request URL the review refuses'
grep -F 'refusing to print the review' "$test_root/output" >/dev/null || fail 'refused-record: the review did not refuse the record'
grep -Fx 'board report failed; run board-report board-parent from the target Git root' "$test_root/output" >/dev/null ||
  fail 'refused-record: the controller did not say the review failed'
expect_marker board-needs-human 'a refused review'
printf 'ok - a review the report refuses still ends the sweep with the board-needs-human marker\n'
```

Replace the `nested-failure` case, from the line `new_case nested-failure 1` through its line `printf 'ok - real Tracker parent isolates child identity and reports a child integrity stop as failure\n'`, with these two cases:

```sh
# A child integrity stop under a real parent opens the morning review, and the review names the child to resume.
new_case nested-failure 1
: >"$fixture/fail-close"
printf '1\n' | tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-failure.log" 2>&1 ||
  fail 'a real Tracker parent did not hold the morning review after a child integrity stop' "$test_root/parent-failure.log"
[ "$(claim_count)" -eq 1 ] || fail "nested-failure: claim count is $(claim_count), expected 1"
parent_id=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent-failure.log")
case "$parent_id" in ''|null) fail 'nested-failure: the parent log has no pipeline_started event' "$test_root/parent-failure.log" ;; esac
failed_child=$(head -n 1 "$fixture/claims")
jq -e --arg child "$failed_child" '.finished == false and .runs == [] and
  .stop_reason == "child \($child) needs inspection" and .stop_child == $child' \
  "$repo/.tracker/runs/$parent_id/board/state.json" >/dev/null || fail 'nested-failure: the ledger does not name the child for inspection'
gate_prompt=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_opened") | .gate_prompt] | join("\n")' \
  <"$test_root/parent-failure.log")
printf '%s\n' "$gate_prompt" | grep -F "Board $parent_id in $repo: stopped" >/dev/null ||
  fail 'nested-failure: the gate prompt does not say the board stopped' "$test_root/parent-failure.log"
printf '%s\n' "$gate_prompt" | grep -F "Stop reason: child $failed_child needs inspection" >/dev/null ||
  fail 'nested-failure: the gate prompt lacks the stop reason' "$test_root/parent-failure.log"
printf '%s\n' "$gate_prompt" | grep -F "  tracker -r $failed_child " >/dev/null ||
  fail 'nested-failure: the gate prompt lacks the child resume command' "$test_root/parent-failure.log"
responses=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_resolved") | .gate_response] | join(",")' \
  <"$test_root/parent-failure.log")
[ "$responses" = 'done' ] || fail "nested-failure: gate responses are \"$responses\", expected done" "$test_root/parent-failure.log"
printf 'ok - a real Tracker parent holds the morning review after a child integrity stop and names the child\n'

# Three consecutive failed children under a real parent open the morning review with the reason in the prompt.
new_case nested-stop 4
printf '1\n2\n3\n' >"$fixture/fail-implement"
printf '1\n' | tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-stop.log" 2>&1 ||
  fail 'a real Tracker parent did not hold the morning review after three consecutive failed children' "$test_root/parent-stop.log"
[ "$(claim_count)" -eq 3 ] || fail "nested-stop: claim count is $(claim_count), expected 3"
parent_id=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent-stop.log")
case "$parent_id" in ''|null) fail 'nested-stop: the parent log has no pipeline_started event' "$test_root/parent-stop.log" ;; esac
jq -e '.finished == false and .stop_reason == "three consecutive failed children" and (has("stop_child") | not) and
  [.runs[].kind] == ["failed","failed","failed"]' "$repo/.tracker/runs/$parent_id/board/state.json" >/dev/null ||
  fail 'nested-stop: the ledger does not record the streak'
gate_prompt=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_opened") | .gate_prompt] | join("\n")' \
  <"$test_root/parent-stop.log")
printf '%s\n' "$gate_prompt" | grep -F 'Stop reason: three consecutive failed children' >/dev/null ||
  fail 'nested-stop: the gate prompt lacks the stop reason' "$test_root/parent-stop.log"
printf '%s\n' "$gate_prompt" | grep -F 'Needs review (3)' >/dev/null ||
  fail 'nested-stop: the gate prompt does not list the three katas' "$test_root/parent-stop.log"
responses=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_resolved") | .gate_response] | join(",")' \
  <"$test_root/parent-stop.log")
[ "$responses" = 'done' ] || fail "nested-stop: gate responses are \"$responses\", expected done" "$test_root/parent-stop.log"
printf 'ok - a real Tracker parent holds the morning review after three consecutive failed children\n'
```

Leave `stacked`, `empty`, `failing`, `stacked-failure`, `blocked`, `nested`, `nested-gate`, `nested-gate-eof`, and `nested-auto-approve` alone; Task 4 gives their bare assertions messages.

- [ ] **Step 2: Run the board tests and watch them fail**

Run: `sh kata/tests/board.sh; printf 'exit %s\n' "$?"`
Expected: the first four `ok -` lines (`stacked`, `empty`, `failing`, `stacked-failure`), then

```
FAIL: three consecutive failed children: the controller exited 1 instead of holding the board for a person
```

followed by the last 60 lines of the controller output, which end with the review's `Remaining open` block and carry no marker, then `exit 1`.

- [ ] **Step 3: Rewrite the controller's stop handling**

Edit `kata/scripts/run-board.sh`. Each edit names the exact text it replaces; the file has not changed since the branch's last commit, so the text is as quoted.

Replace the three lines

```sh
: "${TRACKER_RUN_DIR:?TRACKER_RUN_DIR is required}"
: "${TRACKER_RUN_ID:?TRACKER_RUN_ID is required}"
: "${TRACKER_WORKDIR:?TRACKER_WORKDIR is required}"
```

with

```sh
[ -n "${TRACKER_RUN_DIR:-}" ] && [ -n "${TRACKER_RUN_ID:-}" ] && [ -n "${TRACKER_WORKDIR:-}" ] || {
  printf 'run-board.sh runs under tracker: TRACKER_RUN_DIR, TRACKER_RUN_ID, and TRACKER_WORKDIR must be set\n' >&2
  exit 1
}
```

Replace the ledger validation

```sh
jq -e --arg workspace "$workspace" --arg pipeline "$pipeline" '
  .workspace == $workspace and .pipeline == $pipeline and
  (.finished | type == "boolean") and (.runs | type == "array") and
  (.stop_reason == null or (.stop_reason | type == "string")) and
  all(.runs[]; (.run_id | type == "string" and test("^[a-f0-9]{12}$")) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty")) and
  ([.runs[].run_id] | length == (unique | length))
' "$state" >/dev/null || { printf 'invalid board state or changed workspace/pipeline: %s\n' "$state" >&2; exit 1; }
```

with

```sh
jq -e --arg workspace "$workspace" --arg pipeline "$pipeline" '
  .workspace == $workspace and .pipeline == $pipeline and
  (.finished | type == "boolean") and (.runs | type == "array") and
  (.stop_reason == null or (.stop_reason | type == "string")) and
  (.stop_child == null or (.stop_child | type == "string" and test("^[a-f0-9]{12}$"))) and
  all(.runs[]; (.run_id | type == "string" and test("^[a-f0-9]{12}$")) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty") and
    (.kind == "empty" or (.issue_uid | type == "string" and length > 0))) and
  ([.runs[].run_id] | length == (unique | length))
' "$state" >/dev/null || { printf 'invalid board state or changed workspace/pipeline: %s\n' "$state" >&2; exit 1; }
```

Replace the block from the line `set_stop_reason() {` through the closing `}` of `stop_board` (it reads, in full):

```sh
set_stop_reason() {
  # $reason is a jq variable bound by --arg; ShellCheck cannot see the jq call behind write_state.
  # shellcheck disable=SC2016
  write_state --arg reason "$1" '.stop_reason = $reason'
}
stop_child() {
  set_stop_reason "child $run_id needs inspection"
  printf 'Child run %s needs inspection; no next kata was started.\nLogs: %s\n' "$run_id" "$item/child.log" >&2
  printf 'Recover the child in %s with tracker -r %s %s, then resume board %s.\n' "$workspace" "$run_id" "$pipeline" "$TRACKER_RUN_ID" >&2
  exit 1
}
# A stop outside a child belongs in the ledger too, so the morning review says the board stopped.
stop_board() {
  set_stop_reason "$1"
  printf '%s\n' "$1" >&2
  exit 1
}
```

with

```sh
# This controller prints the review for the run's record; the Report node prints it again for the gate.
# A review the report refuses must not hide the marker: the ledger keeps the reason, and the Report node
# fails where Tracker reports it.
print_review() {
  "$report" "$TRACKER_RUN_ID" && return 0
  printf 'board report failed; run board-report %s from the target Git root\n' "$TRACKER_RUN_ID" >&2
  return 1
}
# Every stop after the ledger exists ends with the board-needs-human marker, so the parent run holds at the
# morning review instead of failing. The ledger keeps the reason, and the child id when a child needs inspection.
stop_board() {
  # $reason and $child are jq variables bound by --arg; ShellCheck cannot see the jq call behind write_state.
  # shellcheck disable=SC2016
  write_state --arg reason "$1" --arg child "${2:-}" '.stop_reason = $reason | if $child == "" then del(.stop_child) else .stop_child = $child end'
  printf '%s\n' "$1" >&2
  print_review || true
  printf 'board-needs-human\n'
  exit 0
}
stop_for_inspection() {
  printf 'Child run %s needs inspection; no next kata was started.\nLogs: %s\n' "$run_id" "$item/child.log" >&2
  printf 'Recover the child in %s with tracker -r %s %s, then choose Sweep again at the morning review.\n' "$workspace" "$run_id" "$pipeline" >&2
  stop_board "child $run_id needs inspection" "$run_id"
}
```

Replace the three-failure block inside `record_failure`

```sh
  if jq -e '[.runs[-3:][].kind] == ["failed","failed","failed"]' "$state" >/dev/null; then
    set_stop_reason 'three consecutive failed children'
    printf 'Board stopped after three consecutive failed children. Ledger: %s\n' "$state" >&2
    "$report" "$TRACKER_RUN_ID"
    exit 1
  fi
```

with

```sh
  if jq -e '[.runs[-3:][].kind] == ["failed","failed","failed"]' "$state" >/dev/null; then
    printf 'Board stopped after three consecutive failed children. Ledger: %s\n' "$state" >&2
    stop_board 'three consecutive failed children'
  fi
```

Replace the loop's first statement

```sh
  # A stop reason describes the previous controller's last iteration; this one decides afresh.
  write_state 'del(.stop_reason)'
```

with

```sh
  # A stop reason and its child describe the previous controller's last iteration; this one decides afresh.
  write_state 'del(.stop_reason, .stop_child)'
```

Replace the tail

```sh
"$report" "$TRACKER_RUN_ID"
# The last line routes board.dip: a clean board ends the run; anything else opens the morning review.
if [ "$open_for_review" -eq 0 ] && [ "$remaining" -eq 0 ]; then
```

with

```sh
review_ok=true
print_review || review_ok=false
# The last line routes board.dip: a clean board ends the run; anything else opens the morning review.
# A review the report refused is something a person must see, so it never yields board-clean.
if [ "$review_ok" = true ] && [ "$open_for_review" -eq 0 ] && [ "$remaining" -eq 0 ]; then
```

Rename the 18 call sites. Every one ends its line with `|| stop_child`; `cat >` keeps the file's mode:

```sh
tmp=$(mktemp)
sed 's/|| stop_child$/|| stop_for_inspection/' kata/scripts/run-board.sh >"$tmp" && cat "$tmp" >kata/scripts/run-board.sh && rm "$tmp"
grep -c 'stop_for_inspection' kata/scripts/run-board.sh
grep -n 'stop_child' kata/scripts/run-board.sh
```

Expected: `19` (18 calls and the definition), then exactly three lines, all inside jq text: the `.stop_child` validation line, the `write_state` line in `stop_board`, and `del(.stop_reason, .stop_child)`. `set_stop_reason` must no longer appear: `grep -c set_stop_reason kata/scripts/run-board.sh` prints `0`.

- [ ] **Step 4: Run the board tests and watch them pass**

Run: `sh kata/tests/board.sh`
Expected: exactly these lines, exit 0:

```
ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry
ok - an empty board requires the full open-issue query
ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once
ok - a failure after a completion restores the stack tip and keeps the completed base
ok - three consecutive failures hold the board for a person, and a resume claims again
ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none
ok - an integrity stop holds the board; a real child resume reconciles once without duplicate work
ok - a handoff from the wrong branch holds the board for inspection
ok - a failed child is recorded only when its handoff, checkout, tree, and kata all check out
ok - a board that stops outside a child records why, keeps its marker when the review fails, and the review says it stopped
ok - a failure before a trusted ledger exists exits 1 with a message and no marker; a trusted ledger sweeps
ok - a review the report refuses still ends the sweep with the board-needs-human marker
ok - a real Tracker parent sweeps a clean board and ends without a gate
ok - a real Tracker parent holds the morning review after a child integrity stop and names the child
ok - a real Tracker parent holds the morning review after three consecutive failed children
ok - real Tracker parent opens the morning review for a handed-off kata and sweeps again on request
ok - a real Tracker parent fails at the morning review when nobody can answer it
ok - a real Tracker parent under --auto-approve ends after one sweep
```

Run: `sh kata/tests/report.sh`
Expected: its nine `ok -` lines, exit 0 (the report already knew `stop_child`).

Run: `shellcheck kata/scripts/run-board.sh kata/tests/board.sh`
Expected: no output.

- [ ] **Step 5: Commit**

```sh
git status
git add kata/scripts/run-board.sh kata/tests/board.sh
git commit -m 'fix(kata): hold the morning review on every board stop'
```

- [ ] **Step 6: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: every `ok -` line, `all kata checks passed` among the output, no ShellCheck output, exit 0.

### Task 4: Every board assertion says what it expected (I3, I6, I9)

**Files:**
- Modify: `kata/tests/board.sh` (the helpers `fail`, `run_board`, `must_succeed`, `must_stop_for_inspection`, `must_stop_without_git_status`, `must_refuse`, and `expect_marker`; the cases `stacked`, `empty`, `failing`, `stacked-failure`, `blocked`, and `nested-gate`; the stderr assertions in `three-failures`, `broken-list`, `preflight-stops`, and `refused-record`)

**Interfaces:**
- Consumes: from Task 1, the `fail MESSAGE [LOG]` helper and the `nested-gate` case; from Task 3, the helpers `must_stop`, `must_stop_for_inspection`, `must_stop_without_git_status`, and `must_refuse`, and the cases `three-failures`, `broken-list`, `preflight-stops`, and `refused-record`, all as Task 3 wrote them.
- Produces: `run_board` writes the controller's stdout to `$test_root/output` and its stderr to `$test_root/errors`; every assertion on a message the controller prints with `>&2` reads `$test_root/errors`, and every assertion on the review, the sweep summary, or the marker reads `$test_root/output`. `expect_marker MARKER LABEL` fails through `fail` unless the last line of `$test_root/output` equals `MARKER`. `fail MESSAGE` with no log tails both files. Tasks 5 and 7 add assertions with these helpers and these two files.

Facts this task relies on (probed 2026-09-18 on Tracker 0.73.1 in a disposable repository with an isolated `HOME`): a tool node with `marker_grep: "^ok$"` whose command prints `ok` on stderr and something else on stdout fails with a `tool_marker_missing` event, `pipeline_failed`, exit 1, and a `status.json` holding `"tool_marker":""`, `"tool_stdout":"not-a-marker"`, `"tool_stderr":"ok"`; the same node printing `ok` on stdout succeeds with `"tool_marker":"ok"`. Tracker matches markers on stdout alone.

**Why:** Task 1 added `fail` and used it in three cases; the eleven older cases still assert with bare `[ ... ]`, `jq -e ... >/dev/null`, and `grep ... >/dev/null` lines, so a failure prints nothing but the shell's exit (I3). `run_board` merges the controller's stderr into `$test_root/output`, and `expect_marker` reads the last line of that merged file; a marker printed on stderr passes the test and fails under Tracker (I9). The `nested-gate` case answers `Sweep again` once, so it never shows that a second `Sweep again` lands in the same ledger (I6). After this task every assertion names what it expected, the controller's two streams are kept apart, and the gate case sweeps twice.

- [ ] **Step 1: Rewrite the helpers and the bare assertions**

Edit `kata/tests/board.sh`. Every anchor below is text as Task 3 left it.

Replace the `fail` helper and its comment:

```sh
# Every assertion names what it expected; the tail of the named log (the controller output by default) follows.
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail_log=${2:-$test_root/output}
  [ ! -f "$fail_log" ] || tail -n 60 "$fail_log" >&2
  exit 1
}
```

with

```sh
# Every assertion names what it expected. The tail of the named log follows; with no log named, the tails of
# the controller's stdout and stderr follow.
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    [ ! -f "$2" ] || tail -n 60 "$2" >&2
  else
    for fail_log in "$test_root/output" "$test_root/errors"; do
      [ ! -f "$fail_log" ] || { printf -- '--- %s\n' "$fail_log" >&2; tail -n 60 "$fail_log" >&2; }
    done
  fi
  exit 1
}
```

Replace `run_board`:

```sh
run_board() {
  (cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
    >"$test_root/output" 2>&1
}
```

with

```sh
# The controller's stdout carries the review and the marker Tracker routes on; its stderr carries messages
# for a person. Tracker matches the marker on stdout alone, so the test keeps the streams apart.
run_board() {
  (cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
    >"$test_root/output" 2>"$test_root/errors"
}
```

In `must_succeed`, replace the line `    cat "$test_root/output" >&2` with `    cat "$test_root/output" "$test_root/errors" >&2`.

In `must_stop_for_inspection`, replace

```sh
  grep -F "Child run $inspected needs inspection" "$test_root/output" >/dev/null || fail "$1: the inspection message is missing"
```

with

```sh
  grep -F "Child run $inspected needs inspection" "$test_root/errors" >/dev/null || fail "$1: the inspection message is missing"
```

In `must_stop_without_git_status`, replace

```sh
  grep -Fx 'git status failed; inspect the checkout' "$test_root/output" >/dev/null || fail "$1: the git status message is missing"
```

with

```sh
  grep -Fx 'git status failed; inspect the checkout' "$test_root/errors" >/dev/null || fail "$1: the git status message is missing"
```

In `must_refuse`, replace

```sh
  grep -F "$2" "$test_root/output" >/dev/null || fail "$1: the message '$2' is missing"
```

with

```sh
  grep -F "$2" "$test_root/errors" >/dev/null || fail "$1: the message '$2' is missing"
```

Replace `expect_marker` and its comment:

```sh
# The controller's last line routes board.dip: a clean board exits, anything else opens the morning review.
expect_marker() {
  last=$(tail -n 1 "$test_root/output")
  [ "$last" = "$1" ] || {
    printf 'FAIL: %s: last controller line is "%s", expected %s\n' "$2" "$last" "$1" >&2
    exit 1
  }
}
```

with

```sh
# The controller's last stdout line routes board.dip: a clean board exits, anything else opens the morning
# review. Stderr never counts, because Tracker reads the marker from stdout alone.
expect_marker() {
  last=$(tail -n 1 "$test_root/output")
  [ "$last" = "$1" ] || fail "$2: the last controller stdout line is \"$last\", expected $1"
}
```

Replace the `stacked` case, from its comment line `# Integration coverage: Tracker and Git are real; the Kata boundary is a fixture.` through its line `printf 'ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry\n'`, with:

```sh
# Integration coverage: Tracker and Git are real; the Kata boundary is a fixture.
new_case stacked 2
must_succeed 'two stacked tasks'
jq -e --arg workspace "$repo" --arg pipeline "$test_root/workflow/complete.dip" \
  '.workspace == $workspace and .pipeline == $pipeline and .finished == true and
    (has("stop_reason") | not) and
    [.runs[].kind] == ["completed","completed","empty"] and
    ([.runs[].run_id] | unique | length) == 3 and
    all(.runs[]; .run_id != "board-parent") and
    .runs[0].branch == "kata/item-1" and .runs[1].branch == "kata/item-2" and
    .runs[1].github.base_branch == .runs[0].branch' "$ledger" >/dev/null ||
  fail 'stacked: the ledger does not show two completed katas stacked under distinct child ids'
[ "$(claim_count)" -eq 3 ] || fail "stacked: claim count is $(claim_count), expected 3"
[ "$(git -C "$repo" rev-list --count HEAD)" -eq 3 ] || fail 'stacked: the commit count is not 3'
first_commit=$(jq -r '.runs[0].commit' "$ledger")
[ "$(git -C "$repo" rev-parse HEAD^)" = "$first_commit" ] || fail 'stacked: the second kata is not stacked on the first commit'
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null || fail 'stacked: the second child did not receive the first branch as its stack base'
for slot in 000001 000002 000003; do
  [ -s "$TRACKER_RUN_DIR/board/items/$slot/child.log" ] || fail "stacked: item $slot has no child log"
done
for child in $(jq -r '.runs[].run_id' "$ledger"); do
  [ -f "$repo/.tracker/runs/$child/activity.jsonl" ] || fail "stacked: child $child has no activity log"
  jq -e '.outcome == "success"' "$repo/.tracker/runs/$child/Exit/status.json" >/dev/null || fail "stacked: child $child did not reach Exit"
done
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'stacked: the sweep summary is missing'
grep -Fx 'Completed (2)' "$test_root/output" >/dev/null || fail 'stacked: the review does not list two completed katas'
grep -Fx -e '- fixture#fixture-item-2 on kata/item-2' "$test_root/output" >/dev/null || fail 'stacked: the review does not name the second kata'
grep -Fx '  https://github.com/fixture/board/pull/2' "$test_root/output" >/dev/null || fail 'stacked: the review lacks the second pull request'
expect_marker board-clean 'two stacked tasks'
# Re-entering a finished ledger (the morning review's "Sweep again") claims again in the same ledger.
must_succeed 'a finished ledger on re-entry'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","completed","empty","empty"]' "$ledger" >/dev/null || fail 'stacked: the re-entry did not add one empty sweep'
[ "$(claim_count)" -eq 4 ] || fail "stacked: claim count is $(claim_count), expected 4"
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'stacked: the re-entry summary is missing'
expect_marker board-clean 'a finished ledger on re-entry'
printf 'ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry\n'
```

Replace the `empty` case, from `new_case empty 0` through `printf 'ok - an empty board requires the full open-issue query\n'`, with:

```sh
new_case empty 0
must_succeed 'initially empty board'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null || fail 'empty: the ledger does not show one empty sweep'
[ "$(claim_count)" -eq 1 ] || fail "empty: claim count is $(claim_count), expected 1"
grep -F 'list --status open --limit 0 --json' "$fixture/kata.log" >/dev/null || fail 'empty: the board did not query every open kata' "$fixture/kata.log"
grep -F 'Board complete: 0 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'empty: the sweep summary is missing'
expect_marker board-clean 'an empty board'
printf 'ok - an empty board requires the full open-issue query\n'
```

Replace the `failing` case, from `new_case failing 2` through `printf 'ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once\n'`, with:

```sh
new_case failing 2
printf '1\n' >"$fixture/fail-implement"
must_succeed 'a failed first kata followed by a completed one'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["failed","completed","empty"] and
  .runs[0].issue_uid == "fixture-item-1" and .runs[0].branch == "kata/item-1" and
  .runs[0].reason == "implement" and .runs[0].label == "needs-review" and
  .runs[1].branch == "kata/item-2" and .runs[1].github.base_branch == "main"' "$ledger" >/dev/null ||
  fail 'failing: the ledger does not show a handoff, a completion from main, and an empty sweep'
[ "$(claim_count)" -eq 3 ] || fail "failing: claim count is $(claim_count), expected 3"
failed_child=$(head -n 1 "$fixture/claims")
main_commit=$(git -C "$repo" rev-parse main)
wip_commit=$(git -C "$repo" rev-parse kata/item-1)
jq -e --arg child "$failed_child" --arg wip "$wip_commit" \
  '.run_id == $child and .start_branch == "main" and .wip_commit == $wip and
    .reason == "implement" and .question == null' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null ||
  fail 'failing: the handoff record does not describe the wip commit on kata/item-1'
[ "$(git -C "$repo" log -1 --format=%s kata/item-1)" = "wip(kata): fixture#fixture-item-1 handoff from run $failed_child" ] ||
  fail 'failing: the wip commit subject is wrong'
git -C "$repo" show --stat --format= kata/item-1 | grep -F 'wip-1.txt' >/dev/null || fail 'failing: the wip commit does not carry wip-1.txt'
[ "$(git -C "$repo" branch --show-current)" = kata/item-2 ] || fail 'failing: the checkout is not on kata/item-2'
[ "$(git -C "$repo" rev-parse kata/item-2^)" = "$main_commit" ] || fail 'failing: kata/item-2 does not start from main'
[ "$(cat "$fixture/fixture-item-1.status")" = open ] || fail 'failing: the handed-off kata is not open'
[ "$(cat "$fixture/fixture-item-1.labels")" = needs-review ] || fail 'failing: the handed-off kata is not labeled needs-review'
grep -Fx "label add kata-pipeline-$failed_child fixture-item-1 needs-review --agent" "$fixture/kata.log" >/dev/null ||
  fail 'failing: the label was not added as the child actor' "$fixture/kata.log"
grep -F "Branch: kata/item-1 (base $main_commit, wip $wip_commit)" "$fixture/fixture-item-1.comment" >/dev/null ||
  fail 'failing: the handoff comment does not name the branch and commits' "$fixture/fixture-item-1.comment"
[ ! -e "$fixture/stack-2.json" ] || fail 'failing: the second child received a stack base after a handoff'
grep -Fx 'Failed fixture-item-1 (implement); left open with needs-review on kata/item-1' "$test_root/output" >/dev/null ||
  fail 'failing: the handoff line is missing'
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null || fail 'failing: the sweep summary is missing'
grep -Fx 'Completed (1)' "$test_root/output" >/dev/null || fail 'failing: the review does not list one completed kata'
grep -Fx 'Needs review (1)' "$test_root/output" >/dev/null || fail 'failing: the review does not list one kata for review'
grep -F -e '- fixture#fixture-item-1: worker stopped (run ' "$test_root/output" >/dev/null || fail 'failing: the review does not describe the handoff'
expect_marker board-needs-human 'a handed-off kata'
# The morning review answered the kata; the next sweep reclaims it and finishes it from the stack tip.
printf 'fixture-item-1\n' >"$fixture/reclaim"
printf '1\n' >"$fixture/remaining"
rm "$fixture/fail-implement"
must_succeed 'a second sweep that finishes the handed-off kata'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["failed","completed","empty","completed","empty"] and
  .runs[3].issue_uid == "fixture-item-1" and .runs[3].branch == "kata/item-4" and
  .runs[3].github.base_branch == "kata/item-2"' "$ledger" >/dev/null ||
  fail 'failing: the second sweep did not finish the handed-off kata from the stack tip'
[ "$(claim_count)" -eq 5 ] || fail "failing: claim count is $(claim_count), expected 5"
[ ! -s "$fixture/reclaim" ] || fail 'failing: the reclaim list was not consumed'
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'failing: the second sweep summary is missing'
grep -Fx 'Completed (2)' "$test_root/output" >/dev/null || fail 'failing: the review does not list two completed katas'
grep -Fx 'Needs review (0)' "$test_root/output" >/dev/null || fail 'failing: the finished kata still shows under Needs review'
[ "$(grep -c 'fixture#fixture-item-1' "$test_root/output")" -eq 1 ] || fail 'failing: the finished kata is not listed exactly once'
expect_marker board-clean 'a second sweep that finishes the handed-off kata'
printf 'ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once\n'
```

Replace the `stacked-failure` case, from `new_case stacked-failure 2` through `printf 'ok - a failure after a completion restores the stack tip and keeps the completed base\n'`, with:

```sh
new_case stacked-failure 2
printf '2\n' >"$fixture/fail-implement"
must_succeed 'a completed kata followed by a failed one'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","failed","empty"] and .runs[1].branch == "kata/item-2"' "$ledger" >/dev/null ||
  fail 'stacked-failure: the ledger does not show a completion, a handoff, and an empty sweep'
[ "$(claim_count)" -eq 3 ] || fail "stacked-failure: claim count is $(claim_count), expected 3"
failed_child=$(sed -n '2p' "$fixture/claims")
jq -e '.start_branch == "kata/item-1"' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null ||
  fail 'stacked-failure: the handoff did not start from the completed branch'
first_commit=$(jq -r '.runs[0].commit' "$ledger")
[ "$(git -C "$repo" branch --show-current)" = kata/item-1 ] || fail 'stacked-failure: the checkout is not back on the stack tip'
[ "$(git -C "$repo" rev-parse HEAD)" = "$first_commit" ] || fail 'stacked-failure: HEAD is not the completed commit'
[ "$(git -C "$repo" rev-parse kata/item-2~2)" = "$first_commit" ] || fail 'stacked-failure: kata/item-2 is not stacked on the completed commit'
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null || fail 'stacked-failure: the failed child did not receive the completed branch as its base'
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null || fail 'stacked-failure: the sweep summary is missing'
expect_marker board-needs-human 'a failure after a completion'
printf 'ok - a failure after a completion restores the stack tip and keeps the completed base\n'
```

In `three-failures`, replace

```sh
grep -F 'Board stopped after three consecutive failed children' "$test_root/output" >/dev/null || fail 'three-failures: the stop message is missing'
```

with

```sh
grep -F 'Board stopped after three consecutive failed children' "$test_root/errors" >/dev/null || fail 'three-failures: the stop message is missing'
```

Replace the `blocked` case, from `new_case blocked 0` through `printf 'ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none\n'`, with:

```sh
new_case blocked 0
: >"$fixture/blocked"
must_succeed 'a queue with only owned or blocked katas'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null ||
  fail 'blocked: the ledger does not show one empty sweep'
[ "$(claim_count)" -eq 1 ] || fail "blocked: claim count is $(claim_count), expected 1"
jq -e '.issues[0].uid == "blocked-item"' "$TRACKER_RUN_DIR/board/blocked.json" >/dev/null || fail 'blocked: blocked.json does not list the blocked kata'
grep -F 'Board incomplete: 1 open katas remain, but none were ready and unowned.' "$test_root/output" >/dev/null || fail 'blocked: the incomplete line is missing'
grep -Fx 'Remaining open (1)' "$test_root/output" >/dev/null || fail 'blocked: the review does not list one remaining kata'
grep -Fx -e '- blocked-item owned by another-actor' "$test_root/output" >/dev/null || fail 'blocked: the review does not name the blocked kata and its owner'
expect_marker board-needs-human 'a blocked queue'
rm "$fixture/blocked"
must_succeed 'a re-entry after the blocked katas closed'
jq -e '.finished == true and [.runs[].kind] == ["empty","empty"]' "$ledger" >/dev/null || fail 'blocked: the re-entry did not add one empty sweep'
[ ! -e "$TRACKER_RUN_DIR/board/blocked.json" ] || fail 'blocked: blocked.json survived a sweep that found nothing blocked'
expect_marker board-clean 'a re-entry after the blocked katas closed'
printf 'ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none\n'
```

In `broken-list`, replace

```sh
grep -Fx 'invalid open-board response' "$test_root/output" >/dev/null || fail 'broken-list: the stop message is missing'
```

with

```sh
grep -Fx 'invalid open-board response' "$test_root/errors" >/dev/null || fail 'broken-list: the stop message is missing'
```

In both `broken-list` and `refused-record`, replace the line

```sh
grep -Fx 'board report failed; run board-report board-parent from the target Git root' "$test_root/output" >/dev/null ||
```

with

```sh
grep -Fx 'board report failed; run board-report board-parent from the target Git root' "$test_root/errors" >/dev/null ||
```

In `preflight-stops`, replace

```sh
(unset TRACKER_RUN_DIR; cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
  >"$test_root/output" 2>&1 || status=$?
```

with

```sh
(unset TRACKER_RUN_DIR; cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
  >"$test_root/output" 2>"$test_root/errors" || status=$?
```

In `refused-record`, replace

```sh
grep -F 'refusing to print the review' "$test_root/output" >/dev/null || fail 'refused-record: the review did not refuse the record'
```

with

```sh
grep -F 'refusing to print the review' "$test_root/errors" >/dev/null || fail 'refused-record: the review did not refuse the record'
```

Replace the `nested-gate` case, from its comment line `# A handed-off kata opens the morning-review gate; its answers (sweep again, then done) drive the parent.` through its line `printf 'ok - real Tracker parent opens the morning review for a handed-off kata and sweeps again on request\n'`, with:

```sh
# A handed-off kata opens the morning review. Two "Sweep again" answers and then "Done" drive the parent
# through three gates, and every sweep lands in the same ledger.
new_case nested-gate 1
printf '1\n' >"$fixture/fail-implement"
printf '2\n2\n1\n' | tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-gate.log" 2>&1 ||
  fail 'a real Tracker parent did not complete the morning review' "$test_root/parent-gate.log"
parent_id=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent-gate.log")
case "$parent_id" in ''|null) fail 'nested-gate: the parent log has no pipeline_started event' "$test_root/parent-gate.log" ;; esac
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["failed","empty","empty","empty"]' \
  "$repo/.tracker/runs/$parent_id/board/state.json" >/dev/null ||
  fail 'nested-gate: the ledger does not show one handoff and three empty sweeps'
[ "$(claim_count)" -eq 4 ] || fail "nested-gate: claim count is $(claim_count), expected 4"
jq -Rne '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_opened")] | length == 3' \
  <"$test_root/parent-gate.log" >/dev/null || fail 'nested-gate: the gate did not open three times' "$test_root/parent-gate.log"
# The gate prints its "Enter choice" prompt without a newline, so the resolution event shares that line.
responses=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_resolved") | .gate_response] | join(",")' \
  <"$test_root/parent-gate.log")
[ "$responses" = 'sweep,sweep,done' ] || fail "nested-gate: gate responses are \"$responses\", expected sweep,sweep,done" "$test_root/parent-gate.log"
gate_prompt=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_opened") | .gate_prompt] | join("\n")' \
  <"$test_root/parent-gate.log")
printf '%s\n' "$gate_prompt" | grep -F 'Needs review (1)' >/dev/null || fail 'nested-gate: the gate prompt does not show the review' "$test_root/parent-gate.log"
printf 'ok - a real Tracker parent opens the morning review for a handed-off kata and sweeps again as often as asked\n'
```

Check that no bare assertion is left. Run: `grep -nE '^\[ .*\]$|^jq -e .*>/dev/null$|^grep .*>/dev/null$|^  jq -e .*>/dev/null$' kata/tests/board.sh`
Expected: no output. (Lines that end in `||` or `|| fail ...` do not match.)

- [ ] **Step 2: Watch the marker check catch a marker on stderr**

The old `expect_marker` read a merged file, so a marker on stderr passed. Move the clean marker to stderr for a moment: in `kata/scripts/run-board.sh`, change the line `  printf 'board-clean\n'` to `  printf 'board-clean\n' >&2`. Do not commit this edit.

Run: `sh kata/tests/board.sh; printf 'exit %s\n' "$?"`
Expected: the `stacked` case's summary and review assertions pass, then

```
FAIL: two stacked tasks: the last controller stdout line is "Remaining open (0)", expected board-clean
```

followed by `--- <test root>/output` with the last lines of the review and `--- <test root>/errors` with `board-clean` as its last line, then `exit 1`.

Restore the controller. Run: `git checkout -- kata/scripts/run-board.sh && git diff --stat -- kata/scripts/run-board.sh`
Expected: no output. (Only this path; `git status` also shows `kata/complete.dip` and `HANDOFF.md`, which stay as they are.)

- [ ] **Step 3: Run the board tests and watch them pass**

Run: `sh kata/tests/board.sh`
Expected: exactly these lines, exit 0:

```
ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry
ok - an empty board requires the full open-issue query
ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once
ok - a failure after a completion restores the stack tip and keeps the completed base
ok - three consecutive failures hold the board for a person, and a resume claims again
ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none
ok - an integrity stop holds the board; a real child resume reconciles once without duplicate work
ok - a handoff from the wrong branch holds the board for inspection
ok - a failed child is recorded only when its handoff, checkout, tree, and kata all check out
ok - a board that stops outside a child records why, keeps its marker when the review fails, and the review says it stopped
ok - a failure before a trusted ledger exists exits 1 with a message and no marker; a trusted ledger sweeps
ok - a review the report refuses still ends the sweep with the board-needs-human marker
ok - a real Tracker parent sweeps a clean board and ends without a gate
ok - a real Tracker parent holds the morning review after a child integrity stop and names the child
ok - a real Tracker parent holds the morning review after three consecutive failed children
ok - a real Tracker parent opens the morning review for a handed-off kata and sweeps again as often as asked
ok - a real Tracker parent fails at the morning review when nobody can answer it
ok - a real Tracker parent under --auto-approve ends after one sweep
```

Run: `shellcheck kata/tests/board.sh`
Expected: no output.

- [ ] **Step 4: Commit**

```sh
git status
git add kata/tests/board.sh
git commit -m 'test(kata): name every board assertion and split the controller streams'
```

- [ ] **Step 5: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: every `ok -` line, `all kata checks passed` among the output, no ShellCheck output, exit 0.


### Task 5: An interrupt reaches the child Tracker and leaves no lock behind (I1, M1, M2, M4)

**Files:**
- Modify: `kata/scripts/run-board.sh` (the two `trap` lines after `child_pid=`; the `elif [ -f "$item/child.pid" ]` branch of the loop; the file mode becomes 755)
- Modify: `kata/tests/board.sh` (an executable check after the `for required ... done` loop; a `slow` flag in the `implement.sh` fixture; a new `interrupt` case between `refused-record` and the `nested` cases)

**Interfaces:**
- Consumes: from Task 3, `must_stop_for_inspection LABEL`, `must_succeed LABEL`, the ledger fields `stop_reason` and `stop_child`, and the inspection message `Child run <id> needs inspection`; from Task 4, `fail MESSAGE [LOG]`, `run_board` writing `$test_root/output` and `$test_root/errors`, `expect_marker MARKER LABEL`, and `claim_count`.
- Produces: the fixture flag `$fixture/slow` (while it exists, `implement.sh` backgrounds `sleep 300`, writes that PID to `$fixture/slow.pid`, and waits for it); the `interrupt` case and its line `ok - an interrupt reaches the child Tracker, clears the lock and pid file, and the child resumes into a clean board`; `run-board.sh` with mode 755; a controller that removes a `child.pid` whose process is gone before it reads the child's outcome (Task 8 documents this).

**Why:** The signal trap sends plain `kill`, so the child Tracker gets SIGTERM, which it does not handle: it dies with no checkpoint and no resume hint, its running tool lives on, and `child.pid` stays behind. The EXIT trap's `rmdir "$lock"` fails when `pid` is still inside the lock, and that failure replaces the controller's exit status. A `child.pid` left by a controller that Tracker cancelled is never removed, so a later sweep can mistake a reused PID for a running child and stop forever. The file is mode 644 while every sibling script is 755 and the controller itself demands `-x` on `board-report`.

Probed facts this task relies on (Tracker 0.73.1, verified 2026-09-18 in disposable repositories with an isolated home): a POSIX `sh` controller sent `kill -TERM` while it waits on a backgrounded Tracker child runs its signal trap; `kill -INT` to that child cancels the running tool node within seconds, kills the tool's process group (a backgrounded `sleep` started by the tool died with it), writes `checkpoint.json` under `<workdir>/.tracker/runs/<child-id>/`, prints the `tracker -r <child-id> <dip>` hint into the child log even under `--json --no-tui`, and exits 1; the controller's `wait` then returns, `exit 130` runs the EXIT trap, and a later `tracker -r <child-id>` of that child re-runs the cancelled node and completes. A Tracker parent that is itself sent SIGINT while its tool node runs kills the controller's process group outright: the controller's traps never run, `board/lock` and `child.pid` stay on disk, a worker process the child started in its own process group survives, and the child has a checkpoint only if it finished at least one node (`tracker -r` on a child with no checkpoint fails with `checkpoint not found for run <id>`).

- [ ] **Step 1: Add the executable check, the slow worker flag, and the failing `interrupt` case**

In `kata/tests/board.sh`, directly after the loop that ends with

```sh
  [ -f "$pipeline_dir/$required" ] || {
    printf 'FAIL: %s is missing\n' "$required" >&2
    exit 1
  }
done
```

add:

```sh
# Every kata script is executable; the controller demands -x on board-report and must meet its own rule.
[ -x "$pipeline_dir/scripts/run-board.sh" ] || { printf 'FAIL: scripts/run-board.sh is not executable\n' >&2; exit 1; }
```

In the `implement.sh` fixture (the heredoc that starts `cat >"$test_root/workflow/implement.sh" <<'SH'`), directly after the line below (the same line also appears in the `claim.sh` heredoc; edit the copy inside `implement.sh`)

```sh
number=$(wc -l <"$fixture/claims" | tr -d ' ')
```

add:

```sh
if [ -f "$fixture/slow" ]; then
  # A worker that runs until it is interrupted; its PID lets the test prove the cancel reached it.
  sleep 300 &
  printf '%s\n' "$!" >"$fixture/slow.pid"
  wait "$!"
fi
```

Directly after the line `printf 'ok - a review the report refuses still ends the sweep with the board-needs-human marker\n'` and before the comment that begins `# Invoke the actual parent workflow so nested tool environments and routing are real.`, add:

```sh

# A controller signalled by hand cancels its child with SIGINT, so the child writes a checkpoint and its
# resume hint; then it clears its pid file and lock. The next sweep stops for inspection and names the child;
# a real child resume finishes the kata, and the sweep after that records it once.
new_case interrupt 1
: >"$fixture/slow"
(cd "$repo" && exec sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
  >"$test_root/output" 2>"$test_root/errors" </dev/null &
controller_pid=$!
waited=0
until [ -s "$fixture/slow.pid" ]; do
  kill -0 "$controller_pid" 2>/dev/null || fail 'interrupt: the controller ended before the worker started'
  [ "$waited" -lt 60 ] || fail 'interrupt: the worker did not start within 60 seconds'
  sleep 1
  waited=$((waited + 1))
done
worker_pid=$(cat "$fixture/slow.pid")
child=$(head -n 1 "$fixture/claims")
item_dir="$TRACKER_RUN_DIR/board/items/000001"
[ -f "$item_dir/child.pid" ] || fail 'interrupt: the controller did not record the child pid'
kill -TERM "$controller_pid"
status=0
wait "$controller_pid" || status=$?
[ "$status" -eq 130 ] || fail "interrupt: the controller exited $status, expected 130"
[ ! -e "$TRACKER_RUN_DIR/board/lock" ] || fail 'interrupt: the lock survived the interrupt'
[ ! -e "$item_dir/child.pid" ] || fail 'interrupt: child.pid survived the interrupt'
waited=0
while kill -0 "$worker_pid" 2>/dev/null; do
  [ "$waited" -lt 10 ] || fail "interrupt: the worker $worker_pid outlived the cancelled child"
  sleep 1
  waited=$((waited + 1))
done
[ -f "$repo/.tracker/runs/$child/checkpoint.json" ] || fail 'interrupt: the cancelled child wrote no checkpoint'
grep -F "tracker -r $child" "$item_dir/child.log" >/dev/null || fail 'interrupt: the child log lacks the resume hint' "$item_dir/child.log"
if grep -Fx 'board-needs-human' "$test_root/output" >/dev/null; then fail 'interrupt: an interrupted controller printed the marker'; fi
rm "$fixture/slow"
# A controller that Tracker cancelled never ran its traps, so its pid file names a process that is gone.
printf '%s\n' "$worker_pid" >"$item_dir/child.pid"
must_stop_for_inspection 'a resume after the interrupted child'
[ ! -e "$item_dir/child.pid" ] || fail 'interrupt: a stale child.pid was kept'
[ "$(claim_count)" -eq 1 ] || fail "interrupt: a resume claimed again; claim count is $(claim_count)"
tracker --git off --workdir "$repo" --json --no-tui --resume "$child" "$test_root/workflow/complete.dip" \
  >"$test_root/interrupt-resume.log" 2>&1 || fail 'interrupt: the real Tracker child resume failed' "$test_root/interrupt-resume.log"
[ "$(claim_count)" -eq 1 ] || fail "interrupt: the child resume claimed again; claim count is $(claim_count)"
must_succeed 'the board after the interrupted child was resumed'
jq -e --arg child "$child" '.finished == true and (has("stop_reason") | not) and (has("stop_child") | not) and
  [.runs[].kind] == ["completed","empty"] and .runs[0].run_id == $child' "$ledger" >/dev/null ||
  fail 'interrupt: the resumed child was not recorded as completed once'
[ "$(claim_count)" -eq 2 ] || fail "interrupt: claim count is $(claim_count), expected 2"
expect_marker board-clean 'the board after the interrupted child was resumed'
printf 'ok - an interrupt reaches the child Tracker, clears the lock and pid file, and the child resumes into a clean board\n'
```

- [ ] **Step 2: Run the test to see the executable check fail**

Run: `sh kata/tests/board.sh`
Expected: the first line of output is `FAIL: scripts/run-board.sh is not executable`, no `ok -` line, exit 1.

- [ ] **Step 3: Make the controller executable**

Run: `chmod 755 kata/scripts/run-board.sh`
Expected: no output; `ls -l kata/scripts/run-board.sh` starts with `-rwxr-xr-x`.

- [ ] **Step 4: Run the test to see the interrupt case fail**

Run: `sh kata/tests/board.sh`
Expected: twelve `ok -` lines through `ok - a review the report refuses still ends the sweep with the board-needs-human marker`, then `FAIL: interrupt: child.pid survived the interrupt` followed by the tails of the controller's stdout and stderr, exit 1. The old trap sends SIGTERM, which the child Tracker does not handle: it dies without cleanup, the trap never removes the pid file, and the EXIT trap still removes the lock because the pid file inside it was removed first. The worker `sleep 300` the dead child left behind ends on its own within five minutes; it holds nothing the test needs.

- [ ] **Step 5: Forward the interrupt, keep the exit status, and drop a stale pid file**

In `kata/scripts/run-board.sh`, replace

```sh
child_pid=
trap 'rm -f "$lock/pid"; rmdir "$lock"' EXIT
trap 'if [ -n "$child_pid" ]; then kill "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; fi; exit 130' HUP INT TERM
```

with

```sh
child_pid=
# rm -rf keeps the exit status: rmdir would fail on a lock that still holds pid and replace the status with its own.
trap 'rm -rf "$lock"' EXIT
# The child Tracker handles SIGINT only. On SIGINT it cancels its running node, kills that node's process group,
# writes a checkpoint, and prints its resume hint; the wait lets it finish that before the pid file goes.
trap 'if [ -n "$child_pid" ]; then kill -INT "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; rm -f "$item/child.pid"; fi; exit 130' HUP INT TERM
```

Replace

```sh
  elif [ -f "$item/child.pid" ]; then
    pending_pid=$(cat "$item/child.pid")
    case "$pending_pid" in ''|*[!0-9]*) stop_board "invalid child PID; inspect $item" ;; esac
    if kill -0 "$pending_pid" 2>/dev/null; then
      stop_board "child process $pending_pid is still running; wait before resuming the board"
    fi
  fi
```

with

```sh
  elif [ -f "$item/child.pid" ]; then
    pending_pid=$(cat "$item/child.pid")
    case "$pending_pid" in ''|*[!0-9]*) stop_board "invalid child PID; inspect $item" ;; esac
    if kill -0 "$pending_pid" 2>/dev/null; then
      stop_board "child process $pending_pid is still running; wait before resuming the board"
    fi
    # A controller that Tracker cancelled never ran its traps, and its child died with it. The pid file is
    # stale; keeping it would let a reused PID pass for a running child on a later sweep.
    rm "$item/child.pid"
  fi
```

- [ ] **Step 6: Run the test to see it pass**

Run: `sh kata/tests/board.sh`
Expected: exactly these lines, exit 0:

```
ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry
ok - an empty board requires the full open-issue query
ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once
ok - a failure after a completion restores the stack tip and keeps the completed base
ok - three consecutive failures hold the board for a person, and a resume claims again
ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none
ok - an integrity stop holds the board; a real child resume reconciles once without duplicate work
ok - a handoff from the wrong branch holds the board for inspection
ok - a failed child is recorded only when its handoff, checkout, tree, and kata all check out
ok - a board that stops outside a child records why, keeps its marker when the review fails, and the review says it stopped
ok - a failure before a trusted ledger exists exits 1 with a message and no marker; a trusted ledger sweeps
ok - a review the report refuses still ends the sweep with the board-needs-human marker
ok - an interrupt reaches the child Tracker, clears the lock and pid file, and the child resumes into a clean board
ok - a real Tracker parent sweeps a clean board and ends without a gate
ok - a real Tracker parent holds the morning review after a child integrity stop and names the child
ok - a real Tracker parent holds the morning review after three consecutive failed children
ok - a real Tracker parent opens the morning review for a handed-off kata and sweeps again as often as asked
ok - a real Tracker parent fails at the morning review when nobody can answer it
ok - a real Tracker parent under --auto-approve ends after one sweep
```

Run: `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`
Expected: no output.

- [ ] **Step 7: Commit**

```sh
git status
git add kata/scripts/run-board.sh kata/tests/board.sh
git diff --cached --summary
git commit -m 'fix(kata): forward interrupts to the child tracker and clear the board lock'
```

Expected: `git status` lists only `kata/scripts/run-board.sh` and `kata/tests/board.sh` as modified apart from the untracked files and `kata/complete.dip`, which stay unstaged; `git diff --cached --summary` prints ` mode change 100644 => 100755 kata/scripts/run-board.sh`.

- [ ] **Step 8: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: every `ok -` line, no ShellCheck output, exit 0.

### Task 6: Tests never touch the operator's configuration (I4, M2, M3, M5)

**Files:**
- Create: `kata/tests/isolate.sh` (mode 644; a snippet every test sources, never run on its own)
- Create: `kata/tests/isolation.sh` (mode 644; `kata/check` runs it first as `sh "$KATA_DIR/tests/isolation.sh"`)
- Modify: `kata/tests/approvals.sh`, `kata/tests/close.sh`, `kata/tests/publish.sh`, `kata/tests/routes.sh`, `kata/tests/preflight.sh`, `kata/tests/continue.sh`, `kata/tests/handoff.sh`, `kata/tests/answer.sh`, `kata/tests/board.sh` (the one `trap` line that follows the `test_root=` assignment)
- Modify: `kata/tests/check.sh` (the `trap` line after `TMP_ROOT=$(mktemp -d)`)
- Modify: `kata/tests/github-setup.sh` (that same `trap` line and the `export GIT_CONFIG_GLOBAL=...` line after it)
- Modify: `kata/tests/report.sh` (the comment and the three `HOME` lines after `command -v jq >/dev/null`)
- Modify: `kata/tests/tool-commands.sh` (the `pipeline_dir=` line, the `trap` line, and the `blanked=` pipeline)
- Modify: `kata/check` (the `KATA_DIR=` line, both `trap` lines, and the test list)

**Interfaces:**
- Consumes: the test headers as Tasks 1 to 5 leave them; none of those tasks changes a header line, so every anchor below is the committed text. `kata/tests/report.sh` is the Task 2 version with its four `HOME` lines. `kata/board-report` already splits its traps (`trap 'rm -rf "$tmp"' EXIT` then `trap 'exit 130' HUP INT TERM`, Task 2), so M2 needs nothing there.
- Produces: `kata/tests/isolate.sh`, sourced as `. "$pipeline_dir/tests/isolate.sh"` (or `. "$KATA_DIR/tests/isolate.sh"`) after the caller sets and exports `KATA_ISOLATE_ROOT` to a directory under its temporary root. The snippet creates `$KATA_ISOLATE_ROOT/home`, `$KATA_ISOLATE_ROOT/config/tracker`, and `$KATA_ISOLATE_ROOT/state`; sets and exports `HOME=$KATA_ISOLATE_ROOT/home`, `XDG_CONFIG_HOME=$KATA_ISOLATE_ROOT/config`, `XDG_STATE_HOME=$KATA_ISOLATE_ROOT/state`, `GIT_CONFIG_GLOBAL=$KATA_ISOLATE_ROOT/gitconfig`, `GIT_CONFIG_NOSYSTEM=1`, and `TRACKER_NO_UPDATE_CHECK=1`; writes that gitconfig with `init.defaultBranch = main`, `user.name = Kata test`, `user.email = kata-test@example.invalid`, `commit.gpgsign = false`, and no hooks path; and writes `OPENAI_API_KEY=fixture-not-a-key` to `$XDG_CONFIG_HOME/tracker/.env`. The test `kata/tests/isolation.sh` prints `ok - the isolation snippet keeps Git away from the operator hooks, config, and identity` and `ok - a Tracker run under the snippet keeps its state under the fixture directories`. Every test and `kata/check` exit 130 on HUP, INT, or TERM after the EXIT trap cleans up. `kata/tests/tool-commands.sh` fails with `scanning <dip> for expansions failed with status <n>` or `filtering the expansions of <dip> failed with status <n>` when a grep exits above 1. Task 7 edits `kata/tests/answer.sh` below this header and leaves the header alone; Task 8 records this task in the CHANGELOG.

**Why:** The suite runs against the operator's real configuration. Every fixture commit fires the operator's global Git hooks (`roborev enqueue`, `llm` in `prepare-commit-msg`), Tracker loads `~/.config/tracker/.env`, its update check reaches the network, and each suite run leaves about 95 run directories under `~/.local/state/tracker/runs` (I4). The `trap '...' EXIT HUP INT TERM` lines remove the temporary root on a signal and then let the script carry on without it, so Ctrl-C produces a cascade of unrelated failures instead of exit 130 (M2). `kata/check` and `tool-commands.sh` compute `pwd` without `-P`, which disagrees with the physical path Git and Tracker report when the checkout sits under a symlink such as `~/workspace` (M3). The `|| true` on the expansion scan in `tool-commands.sh` turns a bad grep pattern into a pass (M5).

Probed facts this task relies on (Git 2.x, Tracker 0.73.1, ShellCheck 0.11.0, bash 3.2.57 as `sh`, verified 2026-09-18 in disposable directories): a fixture `~/.gitconfig` whose `core.hooksPath` names a failing `pre-commit` hook refuses every commit in a fresh repository, and its `init.defaultBranch = trunk` names the first branch; pointing `GIT_CONFIG_GLOBAL` at another file replaces that configuration whole, and `git config --show-origin --get init.defaultBranch` then prints `file:<that file>`, a tab, and the value; `git config --global` writes into the file `GIT_CONFIG_GLOBAL` names, so the `url.<base>.insteadOf` writes in `github-setup.sh` land in the fixture file. Tracker refuses to run even a tool-only workflow without a provider key and reads `$XDG_CONFIG_HOME/tracker/.env`; with `XDG_STATE_HOME` set it writes `$XDG_STATE_HOME/tracker/runs/<run-id>/checkpoint.json` and nothing under `$HOME`; `TRACKER_NO_UPDATE_CHECK` is an environment variable the Tracker binary reads. ShellCheck 0.11.0 silences the sourced-file warning with `# shellcheck source=/dev/null` on the line before the `.` command and reads a shebang-less file when its first line is `# shellcheck shell=sh`. A `.` of a missing file ends a non-interactive `sh` with status 1, but with an EXIT trap set the status becomes 0 (bash 3.2 keeps the trap's own status), so the isolation test checks the file by name before sourcing it. BSD grep exits 2 for an unbalanced parenthesis and prints `grep: parentheses not balanced`. The whole `kata/check` passed on an exported tree with every edit below applied, including the `nested*` cases of `kata/tests/board.sh`, whose nested Tracker parents and children found the fixture key through `XDG_CONFIG_HOME`.

- [ ] **Step 1: Write the failing isolation test**

Create `kata/tests/isolation.sh` with mode 644 and this content:

```sh
#!/bin/sh
# ABOUTME: Proves the isolation snippet keeps a test away from the operator's Git hooks, Git config, home, and Tracker state.
# ABOUTME: Plants a hostile global Git configuration in a fixture home, then shows a commit and a Tracker run under the snippet never touch it.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v tracker >/dev/null
command -v jq >/dev/null
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || tail -n 40 "$test_root/output" >&2
  exit 1
}
# A sourcing failure exits a bash 3.2 sh with status 0 when an EXIT trap runs, so the file is checked by name first.
[ -f "$pipeline_dir/tests/isolate.sh" ] || fail 'kata/tests/isolate.sh is missing'

# A fixture stands in for the operator's home: a global Git configuration whose hook refuses every commit,
# whose default branch is trunk, and whose identity is not the test's.
operator_home="$test_root/operator"
mkdir -p "$operator_home/hooks" "$operator_home/xdg/tracker"
OPERATOR_HOOK_LOG="$test_root/hook.log"
export OPERATOR_HOOK_LOG
cat >"$operator_home/hooks/pre-commit" <<'SH'
#!/bin/sh
printf 'fired\n' >>"$OPERATOR_HOOK_LOG"
exit 1
SH
chmod +x "$operator_home/hooks/pre-commit"
cat >"$operator_home/.gitconfig" <<GITCONFIG
[core]
hooksPath = $operator_home/hooks
[init]
defaultBranch = trunk
[user]
name = Operator
email = operator@example.invalid
[commit]
gpgsign = false
GITCONFIG
printf 'OPENAI_API_KEY=operator-key-must-stay-unread\n' >"$operator_home/xdg/tracker/.env"

# Control: with that home in force, a fresh repository is born on trunk and the hook refuses the commit.
status=0
(
  HOME="$operator_home" XDG_CONFIG_HOME="$operator_home/xdg"
  export HOME XDG_CONFIG_HOME
  unset GIT_CONFIG_GLOBAL
  git init -q "$test_root/control"
  printf 'x\n' >"$test_root/control/file.txt"
  git -C "$test_root/control" add file.txt
  git -C "$test_root/control" commit -q -m 'control commit'
) >"$test_root/output" 2>&1 || status=$?
[ "$status" -ne 0 ] || fail 'control: the operator hook did not refuse the commit'
[ -f "$OPERATOR_HOOK_LOG" ] || fail 'control: the operator hook did not fire'
[ "$(git -C "$test_root/control" symbolic-ref --short HEAD)" = trunk ] || fail 'control: the operator default branch was not used'
rm "$OPERATOR_HOOK_LOG"

# Under the snippet, the same home is in the environment, yet nothing of it reaches Git or Tracker.
HOME="$operator_home"
XDG_CONFIG_HOME="$operator_home/xdg"
export HOME XDG_CONFIG_HOME
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
[ "$HOME" = "$KATA_ISOLATE_ROOT/home" ] || fail "HOME is $HOME, expected $KATA_ISOLATE_ROOT/home"
[ "$XDG_CONFIG_HOME" = "$KATA_ISOLATE_ROOT/config" ] || fail "XDG_CONFIG_HOME is $XDG_CONFIG_HOME, expected $KATA_ISOLATE_ROOT/config"
[ "$XDG_STATE_HOME" = "$KATA_ISOLATE_ROOT/state" ] || fail "XDG_STATE_HOME is $XDG_STATE_HOME, expected $KATA_ISOLATE_ROOT/state"
[ "$GIT_CONFIG_NOSYSTEM" = 1 ] && [ "$TRACKER_NO_UPDATE_CHECK" = 1 ] || fail 'GIT_CONFIG_NOSYSTEM or TRACKER_NO_UPDATE_CHECK is not 1'
[ "$(cat "$XDG_CONFIG_HOME/tracker/.env")" = 'OPENAI_API_KEY=fixture-not-a-key' ] || fail 'the fixture Tracker .env is wrong'
git init -q "$test_root/isolated"
printf 'x\n' >"$test_root/isolated/file.txt"
git -C "$test_root/isolated" add file.txt
git -C "$test_root/isolated" commit -q -m 'isolated commit' >"$test_root/output" 2>&1 || fail 'isolated: the commit failed under the snippet'
[ ! -e "$OPERATOR_HOOK_LOG" ] || fail 'isolated: the operator hook fired under the snippet'
[ "$(git -C "$test_root/isolated" symbolic-ref --short HEAD)" = main ] || fail 'isolated: the fixture default branch was not used'
[ "$(git -C "$test_root/isolated" log -1 --format=%an)" = 'Kata test' ] || fail 'isolated: the commit author is not the fixture identity'
[ "$(git -C "$test_root/isolated" config --show-origin --get init.defaultBranch)" = "$(printf 'file:%s\tmain' "$GIT_CONFIG_GLOBAL")" ] ||
  fail 'isolated: init.defaultBranch does not come from the fixture global config'
printf 'ok - the isolation snippet keeps Git away from the operator hooks, config, and identity\n'

# A real tool-only Tracker run finds the fixture provider key and keeps its state under the fixture directories.
cat >"$test_root/touch.dip" <<'DIP'
workflow IsolationProbe
  goal: "Prove Tracker runs on the fixture key and writes state under the fixture directories."
  start: Touch
  exit: Exit

  tool Touch
    label: "Touch"
    timeout: 1m
    marker_grep: "^touched$"
    command: printf 'touched\n'

  tool Exit
    label: "Done"
    timeout: 5s
    command: true

  edges
    Touch -> Exit  on touched
DIP
tracker --git off --workdir "$test_root/isolated" --json --no-tui "$test_root/touch.dip" >"$test_root/output" 2>&1 </dev/null ||
  fail 'the tool-only Tracker run failed under the snippet'
run_id=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "pipeline_started")][0].run_id' <"$test_root/output")
case "$run_id" in ''|null) fail 'the Tracker log has no pipeline_started event' ;; esac
[ -f "$XDG_STATE_HOME/tracker/runs/$run_id/checkpoint.json" ] || fail "Tracker kept no state under $XDG_STATE_HOME/tracker/runs/$run_id"
[ ! -e "$operator_home/.local" ] || fail 'Tracker wrote under the operator home'
[ ! -e "$KATA_ISOLATE_ROOT/home/.local" ] || fail 'Tracker wrote under the fixture home instead of XDG_STATE_HOME'
printf 'ok - a Tracker run under the snippet keeps its state under the fixture directories\n'
```

- [ ] **Step 2: Run the test to see it fail**

Run: `sh kata/tests/isolation.sh`
Expected: `FAIL: kata/tests/isolate.sh is missing`, no `ok -` line, exit 1.

- [ ] **Step 3: Write the isolation snippet**

Create `kata/tests/isolate.sh` with mode 644 and this content. The `GITCONFIG` heredoc has no indentation on purpose: Git accepts unindented keys, and the file then holds no tab a copy could lose.

```sh
# shellcheck shell=sh
# ABOUTME: Points HOME, XDG, Git, and Tracker at a fixture directory so a test never reads or writes the operator's configuration.
# ABOUTME: Sourced by every kata test after it creates its temporary root; the caller sets KATA_ISOLATE_ROOT first.
[ -n "${KATA_ISOLATE_ROOT:-}" ] || { printf 'set KATA_ISOLATE_ROOT before sourcing isolate.sh\n' >&2; exit 1; }
mkdir -p "$KATA_ISOLATE_ROOT/home" "$KATA_ISOLATE_ROOT/config/tracker" "$KATA_ISOLATE_ROOT/state"
HOME="$KATA_ISOLATE_ROOT/home"
XDG_CONFIG_HOME="$KATA_ISOLATE_ROOT/config"
XDG_STATE_HOME="$KATA_ISOLATE_ROOT/state"
GIT_CONFIG_GLOBAL="$KATA_ISOLATE_ROOT/gitconfig"
GIT_CONFIG_NOSYSTEM=1
TRACKER_NO_UPDATE_CHECK=1
export HOME XDG_CONFIG_HOME XDG_STATE_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM TRACKER_NO_UPDATE_CHECK
# No hooks path, so no operator hook runs; a fixed identity, so no test depends on the operator's.
cat >"$GIT_CONFIG_GLOBAL" <<'GITCONFIG'
[init]
defaultBranch = main
[user]
name = Kata test
email = kata-test@example.invalid
[commit]
gpgsign = false
GITCONFIG
# Tracker refuses to run even a tool-only workflow without a provider key. No test runs an agent node, so this
# value is never sent anywhere.
printf 'OPENAI_API_KEY=fixture-not-a-key\n' >"$XDG_CONFIG_HOME/tracker/.env"
```

- [ ] **Step 4: Run the test to see it pass**

Run: `sh kata/tests/isolation.sh`
Expected: exactly these lines, exit 0:

```
ok - the isolation snippet keeps Git away from the operator hooks, config, and identity
ok - a Tracker run under the snippet keeps its state under the fixture directories
```

Run: `ls ~/.local/state/tracker/runs | wc -l` before and after the test.
Expected: the same count both times; the Tracker run's state went under the test's own `XDG_STATE_HOME`, which the EXIT trap removed.

- [ ] **Step 5: Source the snippet in every test and make the signal traps exit**

In each of `kata/tests/approvals.sh`, `kata/tests/close.sh`, `kata/tests/publish.sh`, `kata/tests/routes.sh`, `kata/tests/preflight.sh`, `kata/tests/continue.sh`, `kata/tests/handoff.sh`, `kata/tests/answer.sh`, and `kata/tests/board.sh`, replace the one line

```sh
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
```

with

```sh
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
```

Each of those nine files defines `pipeline_dir` before that line and has exactly one such `trap` line. In `kata/tests/check.sh`, replace

```sh
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
```

with

```sh
trap 'rm -rf "$TMP_ROOT"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$TMP_ROOT/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$KATA_DIR/tests/isolate.sh"
```

In `kata/tests/github-setup.sh`, replace the two lines

```sh
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
export GIT_CONFIG_GLOBAL="$TMP_ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
```

with

```sh
trap 'rm -rf "$TMP_ROOT"' EXIT
trap 'exit 130' HUP INT TERM
# The snippet points GIT_CONFIG_GLOBAL at a fixture file; every git config --global write below lands there.
KATA_ISOLATE_ROOT="$TMP_ROOT/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$KATA_DIR/tests/isolate.sh"
```

The later `git config --global --add`, `--unset-all`, and plain `git config --global` calls in that file stay as they are; they now write into the snippet's gitconfig, which already holds the fixture identity and default branch.

In `kata/tests/report.sh`, replace the four lines

```sh
# The report prints commands as ~/... under the operator's home; a fixture home keeps the expected text fixed.
HOME="$test_root/home"
mkdir -p "$HOME"
export HOME
```

with

```sh
# The report prints commands as ~/... under the operator's home; the snippet's fixture home keeps the expected text fixed.
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
```

The line `(cd "$repo" && HOME="$pipeline_dir" "$report" newer) >"$test_root/output" 2>&1 || fail 'report failed with the pipeline under HOME'` later in that file stays: it overrides `HOME` for one command to prove the `~/` shortening.

- [ ] **Step 6: Physical paths, honest grep statuses, and the runner**

In `kata/tests/tool-commands.sh`, replace the three lines

```sh
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
```

with

```sh
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
```

and replace the one line

```sh
  blanked=$(grep -noE '\$\{[^}]*\.[^}]*\}' "$test_root/effective" | grep -vE ':\$\{(ctx|params|graph|inputs)\.' || true)
```

with

```sh
  # grep exits 1 when nothing matches and 2 on a bad pattern or an unreadable file; only the first is a clean scan.
  status=0
  grep -noE '\$\{[^}]*\.[^}]*\}' "$test_root/effective" >"$test_root/expansions" || status=$?
  [ "$status" -le 1 ] || fail "scanning $name for expansions failed with status $status"
  status=0
  blanked=$(grep -vE ':\$\{(ctx|params|graph|inputs)\.' "$test_root/expansions") || status=$?
  [ "$status" -le 1 ] || fail "filtering the expansions of $name failed with status $status"
```

The `[ -z "$blanked" ] || fail ...` lines after it stay.

In `kata/check`, replace

```sh
KATA_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
```

with

```sh
KATA_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd -P)
```

replace

```sh
trap 'rm -f "$simulation_log"' EXIT HUP INT TERM
```

with

```sh
trap 'rm -f "$simulation_log"' EXIT
trap 'exit 130' HUP INT TERM
```

replace

```sh
trap 'rm -f "$simulation_log" "$tracker_log"' EXIT HUP INT TERM
```

with (the signal trap set above stays in force; a second `EXIT HUP INT TERM` here would replace it with a handler that cleans up and carries on)

```sh
trap 'rm -f "$simulation_log" "$tracker_log"' EXIT
```

and replace

```sh
"$KATA_DIR/tests/routes.sh"
```

with

```sh
sh "$KATA_DIR/tests/isolation.sh"
"$KATA_DIR/tests/routes.sh"
```

`kata/check` itself does not source the snippet: it is the runner, it creates only two `mktemp` files, and every test it starts isolates itself. The shellcheck line at its end already covers `tests/*.sh`, so both new files are checked without an edit.

- [ ] **Step 7: Prove a bad pattern now fails the expansion test**

Run, from the repository root:

```sh
d=$(mktemp -d) && cp -R kata "$d/kata" &&
  git show HEAD:kata/tests/tool-commands.sh | sed 's/graph|inputs)/graph|inputs/' >"$d/kata/tests/old-broken.sh" &&
  sed 's/graph|inputs)/graph|inputs/' kata/tests/tool-commands.sh >"$d/kata/tests/new-broken.sh" &&
  { sh "$d/kata/tests/old-broken.sh"; printf 'old status %s\n' "$?"; sh "$d/kata/tests/new-broken.sh"; printf 'new status %s\n' "$?"; } ; rm -rf "$d"
```

Expected: the old copy prints `grep: parentheses not balanced` twice, then both `ok -` lines and `old status 0`; the new copy prints `grep: parentheses not balanced` once, then `FAIL: filtering the expansions of board.dip failed with status 2` and `new status 1`. (`board.dip` sorts before `complete.dip`, so it is the first DIP the loop scans.)

- [ ] **Step 8: Run every test on the live tree and ShellCheck**

Run, from the repository root:

```sh
for t in isolation routes tool-commands continue handoff github-setup approvals preflight close publish board answer report; do
  sh "kata/tests/$t.sh" || { printf 'FAILED: %s\n' "$t"; break; }
done
```

Expected: only `ok -` lines from each test, no `FAILED:` line, and the two `isolation` lines from Step 4 first. `kata/tests/board.sh` takes a few minutes in its `nested*` and `interrupt` cases; wait for it. `kata/tests/check.sh` is not in that list because it fails on the live tree for the uncommitted `kata/complete.dip` model swap (pre-existing, see Global Constraints); Step 10 runs it on the exported tree.

Run: `ls ~/.local/state/tracker/runs | wc -l` before and after the loop.
Expected: the same count both times.

Run: `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`
Expected: no output.

- [ ] **Step 9: Commit**

```sh
git status
git add kata/check kata/tests/isolate.sh kata/tests/isolation.sh kata/tests/approvals.sh kata/tests/close.sh kata/tests/publish.sh kata/tests/routes.sh kata/tests/preflight.sh kata/tests/check.sh kata/tests/github-setup.sh kata/tests/continue.sh kata/tests/handoff.sh kata/tests/answer.sh kata/tests/board.sh kata/tests/report.sh kata/tests/tool-commands.sh
git commit -m "test(kata): isolate every test from the operator's Git and Tracker configuration"
```

Expected: `git status` lists `kata/check` and the thirteen existing test files as modified and the two new files as untracked, apart from `kata/complete.dip`, `HANDOFF.md`, and the plan and spec documents, which stay unstaged.

- [ ] **Step 10: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: every `ok -` line, the two `isolation` lines first among them, `all kata checks passed` among the output (printed by `kata/tests/check.sh`), no ShellCheck output, exit 0.

### Task 7: answer says what it did, and the controller stops contradicting itself (I12, I13, M6, M7)

**Files:**
- Modify: `kata/answer` (whole file; the new content is below)
- Modify: `kata/scripts/run-board.sh` (the `printf 'Board complete: ...'` line after the `open_for_review=` assignment)
- Modify: `kata/tests/answer.sh` (the success block, the post-release failure block, and the usage block at the end)
- Modify: `kata/tests/board.sh` (the six `Board complete:` greps Task 4 wrote)

`kata/tests/tool-commands.sh` needs no change: it scans DIP files and the scripts they inline, and nothing in this task touches a DIP or an inlined script. The file map lists it under Task 6 only.

**Interfaces:**
- Consumes: `kata/tests/answer.sh` as Task 6 leaves it (its header sources the isolation snippet; every anchor below sits under that header and is unchanged since Task 2); `kata/tests/board.sh` with Task 4's `fail MESSAGE [LOG]`, `run_board` writing `$test_root/output`, and the six summary greps quoted below; `kata/scripts/run-board.sh` as Task 5 leaves it, where the `printf 'Board complete: ...'` line still stands two lines above the `review_ok=true` that Task 3 added; the fixture `kata` in `answer.sh`, whose `show` exits 92 for any reference but `demo#5fav` and its uid, and which logs every call to `$fixture/kata.log`.
- Produces: `kata/answer` prints `Released <qualified id>` (the reference as typed when the record has no `qualified_id`) right after the claim is released and before `Owner:` and `Labels:`; on an unknown reference it prints `kata show <ref> failed with status <n>; check the reference and the workspace binding` to stderr and exits 1; outside a Git repository it prints `run this from inside the target Git repository` to stderr and exits 1; `-h` and `--help` both print the usage, which now ends `so the next board sweep can claim it.`; the controller's last summary line is `Sweep finished: <n> katas completed and <m> left open for review so far in this board run. Ledger: <path>`; the `Board incomplete: <n> open katas remain, but none were ready and unowned. See <path>` line is unchanged. Task 8 documents every one of these strings.

**Why:** `kata/answer` runs `kata show` under `set -e`, so an unknown reference ends the script with kata's own exit status and no line from `answer`; success prints only `Owner:` and `Labels:`, so the operator never reads that the claim was released (I12). The controller prints `Board incomplete:` for a blocked queue and then `Board complete:` a few lines later; the last line names the sweep, not the board, and the usage text of `answer` says "next board run" where the board sweeps again inside one run (I13). `answer -h` falls into the arity error (M6). Outside a repository, `git rev-parse` prints its raw `fatal: not a git repository` and the script dies with status 128 (M7).

Probed facts this task relies on (verified 2026-09-18): `git rev-parse --show-toplevel` outside a repository prints `fatal: not a git repository (or any of the parent directories): .git` to stderr and exits 128, so the script must redirect it and print its own line; in `var=$(cmd) || { ... "$?" ... }` the `$?` inside the group is the exit status of `cmd` (POSIX: a command with no name completes with the status of its last command substitution), which the dry run showed as `92` from the fixture; `kata/tests/answer.sh` as written below passed against the new `kata/answer` and failed against the old one at `FAIL: released line is missing`; `kata/tests/board.sh` passed with the renamed line.

- [ ] **Step 1: Extend the answer test and rename the summary in the board test**

In `kata/tests/answer.sh`, replace the two lines

```sh
grep -Fx 'Labels: needs-decision,task' "$test_root/output" >/dev/null || fail 'labels line is missing'
printf 'ok - answer comments the reply, releases the pipeline claim, and reports owner and labels\n'
```

with

```sh
grep -Fx 'Labels: needs-decision,task' "$test_root/output" >/dev/null || fail 'labels line is missing'
grep -Fx 'Released demo#5fav' "$test_root/output" >/dev/null || fail 'released line is missing'
printf 'ok - answer comments the reply, releases the pipeline claim, and reports the release, owner, and labels\n'
```

Replace the one line

```sh
grep -F 'unassign' "$fixture/kata.log" >/dev/null || fail 'claim was not released before the failed show'
```

with

```sh
grep -F 'unassign' "$fixture/kata.log" >/dev/null || fail 'claim was not released before the failed show'
grep -Fx 'Released demo#5fav' "$test_root/output" >/dev/null || fail 'released line is missing after a failed show'
```

Replace the seven lines at the end of the file

```sh
run_answer --help
[ "$status" -eq 0 ] || fail "--help exited $status"
grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail '--help lacks usage'
run_answer demo#5fav
[ "$status" -eq 2 ] || fail "missing text exited $status, expected 2"
grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail 'missing text lacks usage'
printf 'ok - answer prints usage for --help and wrong arguments\n'
```

with

```sh
reset_fixture open kata-pipeline-abc
run_answer demo#nope 'Ship it'
[ "$status" -eq 1 ] || fail "unknown reference exited $status, expected 1"
grep -Fx 'kata show demo#nope failed with status 92; check the reference and the workspace binding' "$test_root/output" >/dev/null ||
  fail 'unknown reference: message is missing'
if grep -F 'unassign' "$fixture/kata.log" >/dev/null; then fail 'unknown reference: unassign was called'; fi
status=0
(cd "$test_root" && "$answer" demo#5fav 'Ship it') >"$test_root/output" 2>&1 || status=$?
[ "$status" -eq 1 ] || fail "outside a repository exited $status, expected 1"
grep -Fx 'run this from inside the target Git repository' "$test_root/output" >/dev/null || fail 'outside a repository: message is wrong'
printf 'ok - answer names an unknown reference and refuses to run outside a repository\n'

for flag in -h --help; do
  run_answer "$flag"
  [ "$status" -eq 0 ] || fail "$flag exited $status"
  grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail "$flag lacks usage"
  grep -F 'next board sweep' "$test_root/output" >/dev/null || fail "$flag usage does not say next board sweep"
  if grep -F 'next board run' "$test_root/output" >/dev/null; then fail "$flag usage still says next board run"; fi
done
run_answer demo#5fav
[ "$status" -eq 2 ] || fail "missing text exited $status, expected 2"
grep -F 'Usage: answer' "$test_root/output" >/dev/null || fail 'missing text lacks usage'
printf 'ok - answer prints usage for -h, --help, and wrong arguments\n'
```

In `kata/tests/board.sh`, replace each of these six lines (they sit in the `stacked`, `empty`, `failing`, and `stacked-failure` cases, in this order)

```sh
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'stacked: the sweep summary is missing'
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'stacked: the re-entry summary is missing'
grep -F 'Board complete: 0 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'empty: the sweep summary is missing'
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null || fail 'failing: the sweep summary is missing'
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null || fail 'failing: the second sweep summary is missing'
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null || fail 'stacked-failure: the sweep summary is missing'
```

with, in the same places,

```sh
grep -F 'Sweep finished: 2 katas completed and 0 left open for review so far in this board run.' "$test_root/output" >/dev/null || fail 'stacked: the sweep summary is missing'
grep -F 'Sweep finished: 2 katas completed and 0 left open for review so far in this board run.' "$test_root/output" >/dev/null || fail 'stacked: the re-entry summary is missing'
grep -F 'Sweep finished: 0 katas completed and 0 left open for review so far in this board run.' "$test_root/output" >/dev/null || fail 'empty: the sweep summary is missing'
grep -F 'Sweep finished: 1 katas completed and 1 left open for review so far in this board run.' "$test_root/output" >/dev/null || fail 'failing: the sweep summary is missing'
grep -F 'Sweep finished: 2 katas completed and 0 left open for review so far in this board run.' "$test_root/output" >/dev/null || fail 'failing: the second sweep summary is missing'
grep -F 'Sweep finished: 1 katas completed and 1 left open for review so far in this board run.' "$test_root/output" >/dev/null || fail 'stacked-failure: the sweep summary is missing'
```

- [ ] **Step 2: Run the answer test to see it fail**

Run: `sh kata/tests/answer.sh`
Expected: `ok - answer refuses blank text, person-owned, unowned, and closed katas`, then `FAIL: released line is missing` followed by the old output `Owner: nobody` and `Labels: needs-decision,task`, exit 1. Running `sh kata/tests/board.sh` now would stop at `FAIL: stacked: the sweep summary is missing`; skip it until Step 5.

- [ ] **Step 3: Rewrite `kata/answer` and rename the controller's summary line**

Replace the whole of `kata/answer` with this content (mode stays 755):

```sh
#!/bin/sh
# ABOUTME: Answers a kata the board handed off: comments the reply and releases the pipeline claim.
# ABOUTME: Refuses katas owned by anyone but a pipeline actor so it never takes a person's claim.
set -eu

usage() {
  printf 'Usage: answer <issue-ref> "<text>"\nRun from the target Git root. Comments the text on the kata and releases the pipeline claim so the next board sweep can claim it.\n'
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ "$#" -eq 2 ] || { usage >&2; exit 2; }
ref=$1
text=$2
[ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || { printf 'answer text is empty\n' >&2; exit 2; }
command -v git >/dev/null
command -v jq >/dev/null
command -v kata >/dev/null
top=$(git rev-parse --show-toplevel 2>/dev/null) || { printf 'run this from inside the target Git repository\n' >&2; exit 1; }
workspace=$(cd -- "$top" && pwd -P)
# kata prints its own error for an unknown reference; this line says which command failed and for what.
issue=$(kata show --workspace "$workspace" "$ref" --json) ||
  { printf 'kata show %s failed with status %s; check the reference and the workspace binding\n' "$ref" "$?" >&2; exit 1; }
uid=$(printf '%s' "$issue" | jq -er '.issue.uid')
qualified=$(printf '%s' "$issue" | jq -r '.issue.qualified_id // empty')
status=$(printf '%s' "$issue" | jq -er '.issue.status')
owner=$(printf '%s' "$issue" | jq -r '.issue.owner // ""')
[ "$status" = open ] || { printf '%s is %s, not open\n' "$ref" "$status" >&2; exit 1; }
case "$owner" in
  '') printf '%s is unowned; nothing to hand back\n' "$ref" >&2; exit 1 ;;
  kata-pipeline-*) ;;
  *) printf '%s is owned by %s, not a pipeline actor; refusing to take a claim\n' "$ref" "$owner" >&2; exit 1 ;;
esac
kata unassign --workspace "$workspace" "$uid" --expect-owner "$owner" --comment "$text" --json >/dev/null
# The claim is gone from here on; say so before the queries below, which can fail on their own.
printf 'Released %s\n' "${qualified:-$ref}"
released=$(kata show --workspace "$workspace" "$uid" --json)
open_issues=$(kata list --workspace "$workspace" --status open --limit 0 --json)
owner=$(printf '%s' "$released" | jq -r '.issue.owner // "nobody"')
labels=$(printf '%s' "$open_issues" |
  jq -r --arg uid "$uid" '[.issues[] | select(.uid == $uid) | (.labels // [])[]] | if length == 0 then "none" else join(",") end')
printf 'Owner: %s\n' "$owner"
printf 'Labels: %s\n' "$labels"
```

In `kata/scripts/run-board.sh`, replace the one line

```sh
printf 'Board complete: %s katas finished, %s left open for review. Ledger: %s\n' \
```

with

```sh
# Every earlier exit is a stop or a refusal; only a sweep that reached the end of its queue prints this line.
printf 'Sweep finished: %s katas completed and %s left open for review so far in this board run. Ledger: %s\n' \
```

The continuation line `  "$(jq '[.runs[] | select(.kind == "completed")] | length' "$state")" "$open_for_review" "$state"` under it stays.

- [ ] **Step 4: Run the answer test to see it pass**

Run: `sh kata/tests/answer.sh`
Expected: exactly these lines, exit 0:

```
ok - answer refuses blank text, person-owned, unowned, and closed katas
ok - answer comments the reply, releases the pipeline claim, and reports the release, owner, and labels
ok - answer fails loudly when the post-release show or list fails
ok - answer names an unknown reference and refuses to run outside a repository
ok - answer prints usage for -h, --help, and wrong arguments
```

- [ ] **Step 5: Run the board test and ShellCheck**

Run: `sh kata/tests/board.sh`
Expected: exactly these lines, exit 0 (the same nineteen lines Task 5 ends with; this task changes no case name):

```
ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry
ok - an empty board requires the full open-issue query
ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once
ok - a failure after a completion restores the stack tip and keeps the completed base
ok - three consecutive failures hold the board for a person, and a resume claims again
ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none
ok - an integrity stop holds the board; a real child resume reconciles once without duplicate work
ok - a handoff from the wrong branch holds the board for inspection
ok - a failed child is recorded only when its handoff, checkout, tree, and kata all check out
ok - a board that stops outside a child records why, keeps its marker when the review fails, and the review says it stopped
ok - a failure before a trusted ledger exists exits 1 with a message and no marker; a trusted ledger sweeps
ok - a review the report refuses still ends the sweep with the board-needs-human marker
ok - an interrupt reaches the child Tracker, clears the lock and pid file, and the child resumes into a clean board
ok - a real Tracker parent sweeps a clean board and ends without a gate
ok - a real Tracker parent holds the morning review after a child integrity stop and names the child
ok - a real Tracker parent holds the morning review after three consecutive failed children
ok - a real Tracker parent opens the morning review for a handed-off kata and sweeps again as often as asked
ok - a real Tracker parent fails at the morning review when nobody can answer it
ok - a real Tracker parent under --auto-approve ends after one sweep
```

Run: `grep -rn 'Board complete' kata/scripts kata/tests kata/answer kata/board-report`
Expected: no output.

Run: `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`
Expected: no output.

- [ ] **Step 6: Commit**

```sh
git status
git add kata/answer kata/scripts/run-board.sh kata/tests/answer.sh kata/tests/board.sh
git commit -m 'fix(kata): report what answer released and name the sweep result'
```

Expected: `git status` lists only those four files as modified apart from `kata/complete.dip`, `HANDOFF.md`, and the plan and spec documents, which stay unstaged.

- [ ] **Step 7: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: every `ok -` line, `all kata checks passed` among the output, no ShellCheck output, exit 0.

### Task 8: The docs describe the gate, its stops, and the review (C4, I8, I11, I14, I15, M10, M11, M23, M24; the C2 and C3 wording)

**Files:**
- Modify: `kata/README.md` (the gate paragraph after the `board.dip` command; the fail-forward and routing paragraphs; the ledger paragraph; the nested-Tracker paragraph; the `## Morning review` section; the `## Check` section)
- Modify: `CHANGELOG.md` (the `kata/board.dip` entry under `## [Unreleased]` / `### Changed`)
- Modify: `gotchas.md` (the fail-forward entry, the `command_file:` entry, and the human-gate entry)
- Modify: `kata/BOARD-PLAN.md` (the checkbox list and the validation notes)
- Modify: `kata/PLAN.md` (the branch rule and the 2026-09-14 branch note)
- Modify: `docs/superpowers/plans/2026-09-18-kata-board-gate-review-fixes.md` (the `## Status` section)

No script changes. Tasks 1 to 7 touch none of these documents (the Task 1 and 2 commits changed only `kata/board.dip`, `kata/check`, `kata/board-report`, and tests), so every anchor below is the text in the files today.

**Interfaces:**
- Consumes: the strings the documents quote, each produced by an earlier task. Task 1: the gate labels `Done` and `Sweep again`, no `default:`, `max_restarts: 50`. Task 2: the review header `Board <board-run-id> in <workspace>: finished|stopped|in progress`, the `Stop reason:` and `  tracker -r <child-id> <pipeline>` lines, the section headings `Completed (n)`, `Needs decision (n)`, `Needs review (n)`, `Remaining open (n)`, the item lines `- <qualified id>: <reason text> (run <child-id>)` and `  branch <branch>, base <12 hex>, wip <12 hex>`, the reason texts `needs a decision`, `review rejected`, `publication failed`, `turn limit reached twice`, `worker stopped`, `handoff found the wrong branch`, the `~/...` path form, `no pull request`, `board-report -h`, and the stderr lines `run this from inside the target Git repository` and `refusing to print the review: a child record under <runs dir> has a missing or unsafe id, branch, commit, or pull request URL`. Task 3: `stop_reason`, `stop_child`, `board-needs-human` after every stop once the ledger exists, exit 1 with no marker before it, the stop reasons `three consecutive failed children`, `child <child-id> needs inspection`, `git status failed; inspect the checkout`, `invalid open-board response`, `child repeated an already completed kata: <uid>`. Task 5: `kill -INT` to the child, `child.pid` removal, exit 130, mode 755, the stop reasons `invalid child PID; inspect <item>` and `child process <pid> is still running; wait before resuming the board`. Task 6: `kata/tests/isolate.sh`, `kata/tests/isolation.sh`, `exit 130` traps. Task 7: `Sweep finished: <n> katas completed and <m> left open for review so far in this board run. Ledger: <path>`, `Released <qualified id>`, `kata show <ref> failed with status <n>; check the reference and the workspace binding`, `answer -h`, `next board sweep`.
- Produces: nothing a script reads. The plan's `## Status` section names the next step after this task.

**Why:** The documents describe the board as it was before this branch. The README says the gate reads a number from stdin and that `--auto-approve` answers with the default (there is no default now, and the console takes the choice text too), that the controller exits 1 on every early stop and prints the review itself (Tracker discards that output, and every stop after the ledger exists now reaches the gate), and that the board holds the gate unconditionally (a clean sweep ends the run). Nothing describes the terminal modal, its Escape key, or its clipping (C4), the restart budget (I8), the `Report` node recovery (I11), the `TRACKER_PASS_ENV` hole and the trust level of run-directory records (I15), the clean-board condition and `blocked.json` removal (M23), or whose restart budget it is (M24). The CHANGELOG entry omits half the branch, two `gotchas.md` entries have no heading, BOARD-PLAN ticks every box with no gate, and PLAN.md lacks the `.kata.toml` precondition (M10, M11). The board.dip prompt from Task 1 already tells the operator how to answer; the README has to agree with it.

Facts this task relies on (probed 2026-09-18 on Tracker 0.73.1 in a disposable repository with an isolated `HOME`): a first tool node that prints to stderr and exits 1 with no marker leaves `.tracker/runs/<run-id>/<Node>/status.json` with `.context_updates.tool_stderr` holding the stderr text and `.context_updates.tool_stdout` the stdout, and no `checkpoint.json`; a tool node that succeeds with a marker leaves the same file with its whole stdout under `.context_updates.tool_stdout`; `TRACKER_PASS_ENV=1` in `<workdir>/.env` or in the environment makes `OPENAI_API_KEY` visible inside a tool command, while without it the key is absent; a choice gate with no default under `</dev/null` fails with `human gate choice selection failed for node "MorningReview": no input received` after `checkpoint_saved`, and `tracker --json --no-tui -r <run-id> <dip>` with `1` on stdin opens the same gate again, resolves `done`, and completes; the piped console prints `  1) Done`, `  2) Sweep again`, and `Enter choice: `, accepts `Done`, `done`, `Sweep again`, and `2`, and rejects `sweep` and a blank line with `invalid choice`; a `Report` tool node that exits 1 fails the run with `node "Report" failed with no conditional edges to handle failure`, prints the resume hint, and `tracker -r` runs `Report` again. The modal surface (arrow keys, Escape, clipping) comes from the review's reading of Tracker's `tui/modal.go`; no probe here has a terminal.

- [ ] **Step 1: List the stale claims**

A documentation task has no unit test; this sweep is its failing check. Run, from the repository root:

```sh
grep -n -F -e 'reads the choice number from stdin' -e 'answers every gate with its default' -e 'The controller exits 0 at the end of the queue' -e 'The board run holds at its `Morning review` gate' -e "is one of the run's 50 restarts" kata/README.md
grep -n -F 'expect a run without stdin to fail at the' CHANGELOG.md
grep -n -F -e 'three consecutive failures stop it' -e 'reads the choice NUMBER' gotchas.md
grep -c -F '.kata.toml' kata/PLAN.md
grep -c '^## ' gotchas.md
grep -c '^- \[x\]' kata/BOARD-PLAN.md
```

Expected, in this order (the first three commands print the stale lines; the counts are `0`, `2`, `5`):

```
81:reads the choice number from stdin. Run the board in a terminal that stays
83:gate; `tracker --auto-approve` answers every gate with its default, which ends
107:is included. The controller exits 0 at the end of the queue and 1 on every
208:person working that inbox. The board run holds at its `Morning review` gate with
235:when that sweep ends. Each `Sweep again` is one of the run's 50 restarts.
208:  in a terminal that stays open, and expect a run without stdin to fail at the
69:and the board claims the next one; three consecutive failures stop it. A queue
105:and `Enter choice [default]:`, which reads the choice NUMBER (not the letter)
0
2
5
```

- [ ] **Step 2: Rewrite the README's board sections**

Edit `kata/README.md`. Each edit anchors on the text quoted; the quoted text appears exactly once.

Replace

```
below. When a sweep ends with katas that need you, the run holds at the
`Morning review` gate: Tracker prints the review with two numbered choices and
reads the choice number from stdin. Run the board in a terminal that stays
open, such as a tmux window. A run without a terminal on stdin fails at the
gate; `tracker --auto-approve` answers every gate with its default, which ends
the run after one sweep (verified 2026-09-18).
```

with

```
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
```

Replace

```
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
```

with

```
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
last stdout line is a marker that routes the parent run. `board-clean` ends
the run: the queue was empty, no kata's latest ledger entry is a handoff, no
untouched open kata remains, and the review printed. `board-needs-human` runs
`board-report` and opens the `Morning review` gate with that review. Once the
ledger exists, every stop ends the same way: three consecutive failed
children, a child that needs inspection, a `git status` the controller could
not run, an open-board listing it could not read, a child that closed a kata
the ledger already lists as completed, and a `child.pid` whose process is
still running or is not a PID. The controller records the stop in the
ledger's `stop_reason`, prints the review, which repeats the reason under its
header, and prints `board-needs-human`, so the gate opens for exactly the
runs that need a person. Before the ledger exists (Tracker variables unset, a
missing tool, a lock held by a live controller, a ledger the controller does
not trust) the controller exits 1 with no marker: Tracker fails the run
without a checkpoint, and the message is in
`.tracker/runs/<board-run-id>/RunBoard/status.json` under
`.context_updates.tool_stderr` (verified 2026-09-18). Fix the cause and start
a new board run. The controller's whole output for the latest sweep, its
summary line `Sweep finished: <n> katas completed and <m> left open for
review so far in this board run` included, is in the same file under
`.context_updates.tool_stdout`.
```

Replace

```
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
```

with

```
The parent run's `board/state.json` records every child: `completed` entries
carry the commit and PR URL, `failed` entries carry the branch, reason, and
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
the same stack base on the next `Sweep again`. A finished ledger sweeps again
on re-entry: `Sweep again` at the gate claims the katas released since and
records them in the same ledger. A run that ended with `Done` is over. So is
a run that took its 51st `Sweep again`: the restart budget (`max_restarts: 50`
in `board.dip`) belongs to the run, not to a kata or a repository, and never
resets, so the 51st fails the run with a restart-limit error. Start a new
board run to sweep again. Keep the checkout on the last task branch with a
clean working tree. Runs claimed before the handoff recorded a starting branch
stop for inspection at handoff.
```

Insert after the line

```
aggregate child processes. Review each child run's usage separately.
```

the following text, blank line first:

```

That key filter has an off switch inside the target repository: Tracker also
reads `<workspace>/.env`, and `TRACKER_PASS_ENV=1` there, or in the
environment, passes every provider key into each tool command (verified
2026-09-18 on Tracker 0.73.1). A `.env` in the target repository persists
across sweeps and a worker can write one, so check that file before a board
run. The records a child writes under `.tracker/runs/<child-id>` (the
selection, the handoff, the review approvals) come from the worker's own run.
`board-report` validates every id, branch, commit, and PR URL it pastes into a
command and refuses the whole review when one is unsafe; the controller checks
both approvals against the child's final commit before it records a
completion. Those checks defend against model error, not against a worker
that sets out to forge its records.
```

Replace

```
person working that inbox. The board run holds at its `Morning review` gate with
the review on screen. To print it again, or after the run ended, from the target
Git root:
```

with

```
person working that inbox. A sweep that leaves such katas, or that stops, holds
the board run at its `Morning review` gate with the review in the prompt; a
clean sweep ends the run without a gate. To print the review again, when the
gate clipped it, or after the run ended, from the target Git root:
```

Replace

```
prints the newest board run: completed katas with branches and PR URLs, katas
that need a decision with their questions, katas that need review with their
branches, and open katas the board never touched. A kata the board swept more
than once appears once, as its latest run left it. `board-report --json
<board-run-id>` prints the same for one run as JSON.
```

with

````
prints the newest board run. `board-report --json <board-run-id>` prints the
same for one run as JSON; `board-report -h` prints the usage, and outside a Git
repository both print `run this from inside the target Git repository`. The
text review is laid out to survive Tracker's prompt reflow (76 columns,
indentation dropped): short lines, and every command whole on one line.

```
Board <board-run-id> in <workspace>: stopped
Stop reason: three consecutive failed children
  tracker -r <child-id> ~/src/pipelines/kata/complete.dip
Completed (1)
- demo#1abc on kata/1abc-<child-id>
  https://github.com/org/repo/pull/12
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
decision`, `review rejected`, `publication failed`, `turn limit reached
twice`, `worker stopped`, or `handoff found the wrong branch`. A completed
kata without a PR prints `no pull request`. A kata the board swept more than
once appears once, as its latest run left it. Paths print as `~/...` when the
pipeline lives under your home directory and single-quoted otherwise. Every
id, branch, commit, and PR URL that reaches a pasteable command is checked
against a fixed character set first; when a child record fails that check,
`board-report` prints `refusing to print the review: a child record under
<runs dir> has a missing or unsafe id, branch, commit, or pull request URL`
and exits 1. Inside a board run that failure fails the `Report` node
(`node "Report" failed with no conditional edges to handle failure`) after a
checkpoint; read `.tracker/runs/<board-run-id>/Report/status.json`, fix or
remove the record, and resume with
`tracker --no-tui -r <board-run-id> /path/to/pipelines/kata/board.dip`, which
runs the report again and opens the gate (verified 2026-09-18).
````

Replace

```
can finish it. Merge the PR stack oldest first. Then choose `Sweep again` at
the gate: the board claims the katas you released and holds the review again
when that sweep ends. Each `Sweep again` is one of the run's 50 restarts.
Choose `Done` to end the run; start a new board run to sweep again later.
```

with

```
can finish it. Merge the PR stack oldest first. Then choose `Sweep again` at
the gate (arrow keys and Enter in a terminal; `2` or `Sweep again` on piped
stdin): the board claims the katas you released and holds the review again
when that sweep ends, or ends the run when the sweep is clean. Each `Sweep
again` spends one of the run's 50 restarts, and the budget never resets.
Choose `Done` (`1`, or Escape in a terminal) to end the run; start a new board
run to sweep again later.
```

Replace

```
`kata/answer` comments the text on the kata and releases the pipeline's claim,
so the next sweep can claim it. It refuses katas owned by anyone other than
a pipeline actor. The label stays until the next claim removes it. The next
sweep reads the comment thread and reuses the branch's work. Both commands run
from another shell in the target Git root and change nothing else.
```

with

```
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
```

Insert after the line

```
records and run directories.
```

the following text:

```
Every test sources `kata/tests/isolate.sh` first. It points `HOME`, the XDG
directories, Git's global configuration, and Tracker's state at a fixture
directory, so no test runs the operator's Git hooks, reads the operator's
Tracker configuration, or writes under `~/.local/state/tracker`;
`kata/tests/isolation.sh` proves that against a planted hook and config.
```

- [ ] **Step 3: Rewrite the CHANGELOG entry**

Edit `CHANGELOG.md` under `## [Unreleased]`, `### Changed`.

Replace

```
- `kata/board.dip`: the board no longer ends silently with katas left open. The
  controller's last line routes the run: `board-clean` exits, and
  `board-needs-human` prints the morning review and holds a `Morning review`
  human gate whose choices are `Sweep again` (run the controller again in the
  same ledger, up to 50 times) and `Done`. Tracker never prints a tool node's
  output in `--no-tui`, so the gate is the board's only console output; run it
  in a terminal that stays open, and expect a run without stdin to fail at the
  gate. `kata/scripts/run-board.sh` re-enters a finished ledger as a new sweep
  and drops `board/blocked.json` once a sweep finds nothing blocked;
  `kata/board-report` describes each kata by its latest ledger entry, so a
  handoff a later sweep finished no longer shows under `Needs review`.
  `kata/tests/board.sh` covers the markers, the second-sweep finish, blocked
  re-entry, and a real Tracker parent answering the gate (`Sweep again`, then
  `Done`); `kata/tests/report.sh` covers the latest-entry view.
```

with

```
- `kata/board.dip`: the board no longer ends silently with katas left open. The
  controller's last line routes the run: `board-clean` exits, and
  `board-needs-human` prints the morning review and holds a `Morning review`
  human gate whose choices are `Done` and `Sweep again` (run the controller
  again in the same ledger, up to 50 times; the budget never resets). The gate
  has no default: a closed stdin fails it with a checkpoint that `tracker -r`
  reopens, and `--auto-approve` takes `Done`, the unattended answer. Tracker
  never prints a tool node's output in `--no-tui`, so the gate is the board's
  only console output; run it in a terminal that stays open. Once the ledger
  exists, every controller stop (three consecutive failed children, a child
  that needs inspection, a failed `git status`, an unreadable open-board
  listing, a `child.pid` whose process still runs) records `stop_reason` and
  `stop_child` in the ledger, prints the review, and ends with
  `board-needs-human`, so the gate opens for exactly the runs that need a
  person; only failures before the ledger exists exit 1 without a marker. The
  controller's summary line is `Sweep finished: ...`, it validates `issue_uid`
  on every non-empty ledger entry, and a HUP, INT, or TERM to it interrupts
  the child Tracker, waits for the child's checkpoint, and removes the lock
  and `child.pid` before exiting 130. `kata/scripts/run-board.sh` (now mode
  755) re-enters a finished ledger as a new sweep and drops
  `board/blocked.json` once a sweep finds nothing blocked. `kata/board-report`
  describes each kata by its latest ledger entry, prints the stop reason and
  the child's resume command under its header, validates every id, branch,
  commit, and PR URL it pastes into a command and refuses the review
  otherwise, flattens agent-written text, lays the review out to survive
  Tracker's 76-column reflow, accepts `-h`, and names a run outside a Git
  repository. `kata/answer` prints `Released <kata>`, names an unknown
  reference, accepts `-h`, and says "next board sweep". `kata/tests/isolate.sh`
  points every test's `HOME`, XDG directories, Git configuration, and Tracker
  state at a fixture directory, and every test exits 130 on a signal.
  `kata/tests/board.sh` covers the markers, every stop, the second-sweep
  finish, blocked re-entry, an interrupt, and real Tracker parents at the gate
  (`Sweep again` twice then `Done`, closed stdin, `--auto-approve`, a
  three-failure stop, a child integrity stop); `kata/tests/report.sh` covers
  the latest-entry view, the stop lines, and the record validation;
  `kata/tests/isolation.sh` proves the isolation against a planted hook;
  `kata/tests/answer.sh` covers the new messages. `kata/README.md`,
  `gotchas.md`, `kata/BOARD-PLAN.md`, and `kata/PLAN.md` describe the gate's
  two surfaces and accepted inputs, the unattended mode, the restart budget,
  the stops and where their messages land, the review layout, `Report` node
  recovery with `tracker -r`, the trust level of run-directory records, and
  the `.kata.toml` base precondition.
```

- [ ] **Step 4: Head and correct the gotchas entries**

Edit `gotchas.md`. The headings match the two headed entries that follow them; the earlier entries in the file stay unheaded, as they are.

Replace

```
Doctor Biz chose fail-forward boards with a morning review (2026-09-16): a failed
child hands its kata off (label, comment, WIP commit, starting branch restored)
and the board claims the next one; three consecutive failures stop it. A queue
with only owned or blocked katas finishes the board. `kata/board-report`
summarizes a board run and `kata/answer` comments a reply and releases the
pipeline claim. Implement gets one automatic warm continue (450 turns) after a
steady turn-limit breach; the second breach hands off.
```

with

```
## Boards fail forward into a morning review (decided 2026-09-16)

Doctor Biz chose fail-forward boards with a morning review (2026-09-16): a failed
child hands its kata off (label, comment, WIP commit, starting branch restored)
and the board claims the next one; three consecutive failures stop the sweep. A
queue with only owned or blocked katas finishes the sweep. Since 2026-09-18
every stop after the ledger exists (three failures, a child needing inspection,
a failed `git status`, an unreadable open-board listing) records `stop_reason`
in `board/state.json` and still ends with `board-needs-human`, so the parent
holds the `Morning review` gate with the reason under the review's header; only
failures before the ledger exists (Tracker variables unset, a missing tool, a
held lock, an untrusted ledger) exit 1 with no marker, and their message is in
`.tracker/runs/<board-run-id>/RunBoard/status.json`. `kata/board-report`
summarizes a board run and `kata/answer` comments a reply and releases the
pipeline claim. Implement gets one automatic warm continue (450 turns) after a
steady turn-limit breach; the second breach hands off.
```

Replace

```
Tracker inlines a `command_file:` script into the tool command and runs its
```

with

```
## Tracker blanks dotted expansions in command_file scripts (verified 2026-09-17)

Tracker inlines a `command_file:` script into the tool command and runs its
```

Replace

```
word. A `human` node does print: its label, the prompt with `${ctx.tool_stdout}`
rendered as a fenced `## Tool Stdout` block, the choices numbered in edge order,
and `Enter choice [default]:`, which reads the choice NUMBER (not the letter)
from stdin. Closed stdin fails the gate and the run; `--auto-approve` picks the
default. Under `--json --no-tui` the prompt still prints among the event lines,
```

with

```
word. A `human` node does print: its label, the prompt with `${ctx.tool_stdout}`
rendered as a fenced `## Tool Stdout` block, the choices numbered in edge order
(`1) Done`), and `Enter choice:` (the default in brackets when the gate has
one), which reads the choice number or the choice text from stdin: `1`, `Done`,
and `done` all pick Done, `2` and `Sweep again` pick the sweep, while `sweep` or
a blank line fails the gate with `invalid choice`. Closed stdin fails it with
`no input received`. Either failure saves a checkpoint, and `tracker -r` reopens
the gate. `--auto-approve` picks the default, else the first choice;
`kata/board.dip` sets no default, so its unattended answer is the first choice,
`Done`, and Escape in the terminal modal picks the same. Under `--json --no-tui`
the prompt still prints among the event lines,
```

- [ ] **Step 5: Record the gate in BOARD-PLAN and the base precondition in PLAN**

Edit `kata/BOARD-PLAN.md`.

Insert after the line

```
- [x] Run kata/check, fresh-eyes review, document usage/limits, and commit.
```

the following text:

```
- [x] Hold a `Morning review` gate with no default after every sweep that leaves katas open or stops; validate the records the review pastes; isolate the tests from the operator's Git and Tracker configuration (2026-09-18).
```

Insert after the line

```
ShellCheck. `git diff --check` passed. No live kata-to-GitHub board run was made.
```

the following text, blank line first:

```

Gate validation (2026-09-18): real Tracker parents answer the gate both ways
(`Sweep again` twice, then `Done`), fail it on closed stdin with a checkpoint,
end after one sweep under `--auto-approve`, and hold it after a three-failure
stop and after a child integrity stop with the child's resume command in the
prompt. Every stop after the ledger exists reaches the gate; the review refuses
a child record with an unsafe id, branch, commit, or PR URL. An interrupt to the
controller reaches the child Tracker and leaves no lock or `child.pid`. The test
suite runs under a fixture `HOME`, Git configuration, and Tracker state.
`./kata/check` passes on an exported tree. No live board run was made.
```

Edit `kata/PLAN.md`.

Replace

```
Create a fresh task branch for each claimed item. For GitHub repositories,
start from the fetched default branch and publish a PR after review, before
closing the kata. For other repositories, start from current HEAD and finish
```

with

```
Create a fresh task branch for each claimed item. For GitHub repositories,
start from the fetched default branch, which must carry the committed
`.kata.toml` binding (`claim-next.sh` refuses a base without it: the checkout
would drop the binding and strand the claim), and publish a PR after review,
before closing the kata. For other repositories, start from current HEAD and finish
```

Replace

```
Branch and PR update (2026-09-14): every confirmed claim creates a fresh kata
branch. GitHub repositories start from their fetched default branch; other
repositories start from current HEAD. GitHub identity and base are saved before
```

with

```
Branch and PR update (2026-09-14): every confirmed claim creates a fresh kata
branch. GitHub repositories start from their fetched default branch, after a
check that it carries `.kata.toml` (added 2026-09-17: a binding that exists
only locally vanishes from the checkout and strands the claim); other
repositories start from current HEAD. GitHub identity and base are saved before
```

- [ ] **Step 6: Run the sweep again**

Run the Step 1 commands again.
Expected: the first three print nothing and exit 1; the counts are `2`, `4`, `6`.

Run:

```sh
grep -c -F -e 'Sweep finished:' -e 'Released <kata>' -e 'TRACKER_PASS_ENV=1' -e 'no input received' -e 'RunBoard/status.json' -e 'Report/status.json' -e 'kata/tests/isolate.sh' kata/README.md
grep -c -F -e 'has no default' -e 'Sweep finished' -e 'Released <kata>' -e 'isolate.sh' CHANGELOG.md
```

Expected:

```
7
4
```

Run: `git diff --check`
Expected: no output.

- [ ] **Step 7: Update the plan's Status section**

In `docs/superpowers/plans/2026-09-18-kata-board-gate-review-fixes.md`, replace everything between the line `## Status` and the line `## Global Constraints` (both stay) with the block below, with the day this task lands in place of the second date:

```markdown

- 2026-09-18: plan written. Doctor Biz chose option 1 of the review menu ("Fix criticals and importants as planned, then merge to main locally"), so execution and the local merge are authorized. Pushing `main` is not.
- Branch: `fix/kata-scripts-by-path` (forked from `main` at 1aeddf7; `main` has not moved). Commits before the plan: 686ee42, 09ff603, 0b23d91. Tasks 1 and 2: ce116d9, 1cfa83e, 72a0b3a. Tasks 3 to 8: one commit each, in order, on the same branch.
- Task order differs from the review menu on purpose: the gate fix (C2, C3) lands before the stop-handling fix (C1) because the tests for C1 assert what a real Tracker parent does at a gate with no default.
- 2026-09-18: Tasks 1 to 8 landed and the exported-tree check passed after the last commit. Next step: merge `fix/kata-scripts-by-path` into `main` locally, without pushing, then hand the Tracker bugs listed under "Not in this plan" to Doctor Biz to file upstream. The auto-memory note that mirrors the `gotchas.md` human-gate entry is the controller's to fix.

```

- [ ] **Step 8: Commit**

```sh
git status
git add kata/README.md CHANGELOG.md gotchas.md kata/BOARD-PLAN.md kata/PLAN.md docs/superpowers/plans/2026-09-18-kata-board-gate-review-fixes.md
git commit -m 'docs(kata): describe the morning review gate, its stops, and the review'
```

Expected: `git status` lists those six files as modified and nothing else staged; `kata/complete.dip` and `HANDOFF.md` stay unstaged.

- [ ] **Step 9: Run the exported-tree check**

Run: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`
Expected: every `ok -` line, `all kata checks passed` among the output, no ShellCheck output, exit 0. This is the last task; with it green, the branch is ready for the local merge named in the Status section.

---

## Not in this plan

- I10, a clean board ending without a word: a design call for Doctor Biz (an acknowledge gate on clean boards, or `board-report` as the answer). Deferred.
- I15's code change: refusing to claim when `<workspace>/.env` exists would break ordinary repositories. Task 8 documents the hole instead.
- I16, a handoff the operator closed by hand staying under `Needs review`: backlog unless it is hit.
- M13 to M22 and M25 to M32: backlog. (M1 to M12, M23, and M24 are in Tasks 2 to 8.)
- D1 to D9: outside this branch. Task 8 carries D1's README sentence on the trust level of approvals.
- The twelve Tracker bugs in the spec's "Tracker bugs to file upstream" list: flagged in the final report for Doctor Biz to file, never patched here. Probes in this plan add one detail to bug 7: `TRACKER_PASS_ENV=1` in the environment has the same effect as in `<workdir>/.env`.
- The controller's auto-memory note `project_tracker_human_gate_console.md` still says the gate reads a number only and that `--auto-approve` picks the default; Task 8 corrects the `gotchas.md` entry it was rendered into, and the memory file lives outside the repository.
