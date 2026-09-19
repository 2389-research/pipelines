# Kata Land On Close Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land each approved kata task on the trunk it was claimed from as part of the close step — fast-forward the trunk ref to the reviewed commit, close the kata, delete the task branch — with no remote Git or GitHub actions anywhere in the pipeline.

**Architecture:** `claim-next.sh` records the branch checked out at claim time as `trunk` in `selected.json` and refuses to start on a detached HEAD or a `kata/*` task branch. After both SHA-bound approvals, `close-selected.sh` fast-forwards `refs/heads/<trunk>` to the approved commit with `git update-ref`, closes the kata, switches to the trunk, and deletes the task branch; it refuses when the trunk moved, is missing, or is checked out in another worktree. `handoff-selected.sh` restores the trunk on failure and stops if the close step already landed the kata. `run-board.sh` records `landed` completions and `land` failures and no longer carries a stack base forward; every GitHub node, PR-stacking path, and remote command is removed, and `kata/check` grows a guard that fails if any kata script runs a remote Git or `gh` command.

**Tech Stack:** POSIX `sh`, `jq` 1.8.2, `git` 2.50.1, Tracker 0.73.1, Dippin 0.72.0, ShellCheck 0.11.0. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-kata-land-on-close-design.md` (the binding design; this plan argues from it). Line numbers in the tasks below are hints taken at `d722317` on `fix/kata-scripts-by-path`; this branch is cut from `main` after that branch merges, so `main` may have moved every anchor by a line or two. Verify each anchor with `git grep -n` before editing; edit by matching quoted text, not by line number.

## Status

- 2026-09-19 execution: Doctor Biz authorized reviewing and merging the prerequisite branch locally, then executing this plan; no push. Doctor Biz approved grouping Tasks 4–6 into one integration commit so their shared state-format changes pass the full suite together, followed by the documentation work required by the binding spec (Task 7 below).
- Prerequisite complete: `da6b07f` fixes failed Kata command routing with three regressions; fresh-eyes review and 77 canonical check cases passed. Main advanced concurrently with tracker-claw; local merge `d966275` preserves both projects and passes `./kata/check` and `sh tracker-claw/check`. Landing branch starts at `d966275`; no remote commands were run.
- Task 1 complete: `e750610`, graph-contract red/green verified, ShellCheck and controller-captured `./kata/check` exit 0, independent spec/code review clean. Next: Task 2.
- Execution corrections: the binding spec governs code examples. Task 3 scans live runtime files (including untracked files), includes `git remote`, and refuses scan errors; it preserves existing close refusal coverage. Task 5 requires a non-null valid commit for completed items. Task 6 validates selected fields and keeps guarded Kata lookups so malformed state or failed commands reach inspection rather than escaping through `set -e`.
- 2026-09-18: spec approved ("ok cool. let's go") and committed at `ab9cebb`. Doctor Biz chose "Land inside the close step", "let's skip remote git actions altogether", and "commit the swap first".
- Branch: `feat/kata-land-on-close`, cut from `main` **after** `fix/kata-scripts-by-path` (the gate-review fixes) merges to `main` locally. Do not start this plan until that merge has landed; the anchors below assume the gate-review work is in `main`.
- The uncommitted `kata/complete.dip` model swap that rode along on the gate-review branch is committed here by Task 1. If the working tree arrives without it (the stash did not carry over), Task 1 recreates it from the six `model:` values before committing — Task 1 is self-contained either way.
- Pushing `main` or any branch is not authorized. This pipeline performs no `git fetch`, `git push`, `git ls-remote`, or `gh` command; Task 3 adds a check that enforces that.

## Global Constraints

- Every script is POSIX `sh` with `set -eu`, a shebang, then two `# ABOUTME:` lines, and ShellCheck clean. The one sourced snippet (`kata/tests/isolate.sh`) already exists; do not add a shebang to it.
- "Tests never contact a real kata daemon or model provider. Every test puts a fixture `kata` on `PATH` and works in a disposable Git repository under `mktemp -d`. Never create practice issues in a real workspace. Do not touch the `mux` or `todo-test-2` workspaces or their kata state."
- "Only the pipelines repository changes. Tracker and kata bugs are flagged in the final report, never patched here."
- "Never print `~/.config/tracker/.env` values."
- "Every path comparison uses `pwd -P`."
- "Never bypass hooks: `--no-verify`, `--no-hooks`, and `--no-pre-commit-hook` are forbidden."
- "Run `git status` before every `git add`; never `git add -A` in this repository."
- Never stage `HANDOFF.md` (a stale untracked root note). Name every file in each `git add`. After Task 1 there is no uncommitted `kata/complete.dip`; if any other file is dirty at a task boundary, stop and inspect rather than staging it.
- Conventional commits, imperative, present tense, scope `kata` (Task 1 uses `chore(kata)`).
- The pipeline never contacts a remote: no `git fetch`, `git push`, `git ls-remote`, `git remote`, or `gh`. The trunk it lands on is the branch checked out when the kata was claimed; it moves refs only with `git update-ref` and `git branch`/`git switch` locally.
- Tracker facts every task relies on (verified 2026-09-18 on Tracker 0.73.1 / Dippin 0.72.0): a tool node runs its `command_file` script by path and Tracker passes `HOME`, `PATH`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM`, `TRACKER_NO_UPDATE_CHECK`, `TRACKER_RUN_DIR`, `TRACKER_RUN_ID`, and `TRACKER_WORKDIR` into it while dropping provider keys; `selected.json`, `verification.txt`, `completion.md`, and the two `review-*.approved` files live under `$TRACKER_RUN_DIR`; the first line of each `.approved` file is the SHA it approves. The board runs `complete.dip` as a nested child Tracker per claimed kata and records each child's run id.
- The canonical check is `./kata/check`, run on the live tree. Task 1 commits the model swap that `complete.dip` currently carries uncommitted and flips `check.sh`'s expected model to match, so from Task 1's commit onward the working tree equals `HEAD` and `./kata/check` passes directly. To check an intermediate state while the swap is still uncommitted, run it on an exported tree: `d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && "$d/kata/check" && rm -rf "$d"`. Individual test files run fine on the live tree: `sh kata/tests/board.sh`, `sh kata/tests/close.sh`, `sh kata/tests/handoff.sh`, `sh kata/tests/report.sh`.
- Never type Unicode escapes such as backslash-u sequences into shell commands; use `[[:cntrl:]]` classes in grep and `([27] | implode)` in jq when a test needs a control character.

## File map

| File | Responsibility | Tasks |
|------|----------------|-------|
| `kata/complete.dip` | Model swap; CloseSelected node label | 1, 3 |
| `kata/tests/check.sh` | Model expectation flip; `trunk` in `selected.json`; existing-branch trunk assertion | 1, 2 |
| `kata/README.md`, `kata/PLAN.md`, `CHANGELOG.md` | Model text (the swap) | 1 |
| `kata/scripts/claim-next.sh` | Record `trunk`; refuse detached HEAD and task branches; drop the GitHub block | 2 |
| `kata/tests/preflight.sh` | Real-Tracker detached-HEAD and task-branch refusals | 2 |
| `kata/tests/github-setup.sh` | Deleted | 2 |
| `kata/check` | Drop the `github-setup.sh` and `publish.sh` test lines; add the remote-command guard | 2, 3 |
| `kata/scripts/close-selected.sh` | Land the approved commit on the trunk, then close | 3 |
| `kata/tests/close.sh` | Landing rewrite with a fixture `kata` on `PATH` | 3 |
| `kata/tests/publish.sh` | Deleted | 3 |
| `kata/prompts/implement.md` | Drop the push/PR sentence | 3 |
| `kata/scripts/handoff-selected.sh` | Restore the trunk; `land` failure reason; closed-kata guard | 4 |
| `kata/tests/handoff.sh` | `trunk` cases; landing-failure case; closed-kata case | 4 |
| `kata/board-report` | `commit` replaces `pr_url` in the completed group | 5 |
| `kata/tests/report.sh` | Landed lines; `commit` validation | 5 |
| `kata/scripts/run-board.sh` | Landed completions and `land` failures; drop the stack base | 6 |
| `kata/board.dip` | ABOUTME and goal reword | 6 |
| `kata/tests/board.sh` | Landing fixtures, assertions, and new cases | 6 |
| `kata/README.md`, `README.md`, `kata/BOARD-PLAN.md`, `kata/PLAN.md`, `CHANGELOG.md`, `gotchas.md` | Landing behavior docs; retire the remote-base memory | 7 |

## Verifying a task

Each task ends with the same three checks unless it says otherwise:

Execution sequencing: Tasks 4–6 are one integration unit approved by Doctor Biz on 2026-09-19. Run each focused red/green cycle in order; run the full suite and commit after all three agree on the new state shape. Preserve the prerequisite review fix for failed Kata lookups when replacing controller blocks.

1. The task's own test files on the live tree, for example `sh kata/tests/close.sh`; each must print only `ok - ...` lines and exit 0.
2. `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh` prints nothing.
3. `./kata/check` on the live tree exits 0 after the commit (from Task 1 onward the tree matches `HEAD`).

`kata/tests/board.sh` runs real Tracker parents in its nested cases and `kata/tests/preflight.sh` runs a real Tracker child; both take a few minutes. Run them in the foreground and wait.

---

### Task 1: Commit the review-model swap (prerequisite)

`kata/complete.dip` currently carries an uncommitted model swap: scope reviews move to `glm-5.3`, and the worker, repair, and correctness reviews move to `deepseek-4.1-flash`. This task commits it so the working tree matches `HEAD` for every later task, and flips the check and the docs to match. It is self-contained: if the swap did not survive the branch switch, Step 1 recreates it.

**Files:**
- Modify: `kata/complete.dip` (the six `model:` lines)
- Modify: `kata/tests/check.sh:33` (the expected-model expression)
- Modify: `kata/README.md` (the model bullets and the "worker and repair agent also use" line, near l.16-19)
- Modify: `kata/PLAN.md` (the provider-update model sentence, near l.47-48)
- Modify: `CHANGELOG.md` (a `### Changed` bullet under `## [Unreleased]`)

**Interfaces:**
- Produces: the committed model mapping — `ReviewScope` and `ReReviewScope` use `glm-5.3`; `Implement`, `ReviewCorrectness`, `Repair`, and `ReReviewCorrectness` use `deepseek-4.1-flash`. Task 3 edits the `CloseSelected` node label in the same file and relies on the model lines already being committed.

- [x] **Step 1: Put `complete.dip` in the target state**

Confirm the swap is present. If `git diff --stat kata/complete.dip` prints nothing, the swap did not carry over — set each agent node's `model:` line by hand so the mapping is exactly:

| Node | Model |
|------|-------|
| `Implement` | `deepseek-4.1-flash` |
| `ReviewCorrectness` | `deepseek-4.1-flash` |
| `ReviewScope` | `glm-5.3` |
| `Repair` | `deepseek-4.1-flash` |
| `ReReviewCorrectness` | `deepseek-4.1-flash` |
| `ReReviewScope` | `glm-5.3` |

- [x] **Step 2: Verify the mapping**

Run:

```sh
awk '/^  agent /{a=$2} /^    model:/{print a, $2}' kata/complete.dip
```

Expected, in this order:

```
Implement deepseek-4.1-flash
ReviewCorrectness deepseek-4.1-flash
ReviewScope glm-5.3
Repair deepseek-4.1-flash
ReReviewCorrectness deepseek-4.1-flash
ReReviewScope glm-5.3
```

- [x] **Step 3: Run the graph-contract check and watch it fail**

Run: `sh kata/tests/check.sh`
Expected: FAIL with `all six agents must use the configured Lunaroute models, provider, and turn limits` — `check.sh:33` still expects the old mapping (`Scope` → `deepseek-4.1-flash`, everything else → `glm-5.3`), which no longer matches the graph.

- [x] **Step 4: Flip the expected-model expression**

In `kata/tests/check.sh`, change the line (near l.33):

```awk
        expected = name ~ /Scope$/ ? "deepseek-4.1-flash" : "glm-5.3"
```

to:

```awk
        expected = name ~ /Scope$/ ? "glm-5.3" : "deepseek-4.1-flash"
```

- [x] **Step 5: Run the check and watch it pass**

Run: `sh kata/tests/check.sh`
Expected: PASS (`ok - ...` lines only).

- [x] **Step 6: Match the docs to the mapping**

In `kata/README.md` (near l.16-19), the two review bullets and the worker/repair sentence name the models. Set them to:

```markdown
- **Correctness (`deepseek-4.1-flash`):** acceptance criteria, regressions, error paths, and tests.
- **Scope (`glm-5.3`):** unnecessary changes, maintainability, and relevant security risks.
```

and change `The worker and repair agent also use \`glm-5.3\`.` to `The worker and repair agent also use \`deepseek-4.1-flash\`.` (leave the rest of that sentence — "All six agent nodes use tracker's `openai-compat` provider through Lunaroute." — unchanged).

In `kata/PLAN.md` (near l.47-48), change `Worker, repair, and correctness reviews use \`glm-5.3\`; scope reviews use \`deepseek-4.1-flash\`.` to `Worker, repair, and correctness reviews use \`deepseek-4.1-flash\`; scope reviews use \`glm-5.3\`.`

- [x] **Step 7: Add a CHANGELOG note**

Under `## [Unreleased]`, in the `### Changed` list, add:

```markdown
- Kata review models swapped: scope reviews now run on `glm-5.3` and the
  worker, repair, and correctness reviews on `deepseek-4.1-flash`.
```

- [x] **Step 8: Verify and commit**

Run: `./kata/check` (live tree — it now matches `HEAD` after this commit) and `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`. Both clean.

```sh
git status
git add kata/complete.dip kata/tests/check.sh kata/README.md kata/PLAN.md CHANGELOG.md
git commit -m "chore(kata): move scope review to glm-5.3 and the rest to deepseek-4.1-flash"
```

---

### Task 2: `claim-next` records the trunk (drops GitHub)

The claim step records the branch checked out at claim time as `trunk` in `selected.json`, refuses to start on a detached HEAD or a `kata/*` task branch, and no longer discovers a GitHub remote, fetches a base, or writes a `github` object. `selected.json` loses `github` and `start_branch` and gains `trunk`.

**Files:**
- Modify: `kata/scripts/claim-next.sh` (the trunk guard near l.30; delete the GitHub/stack block l.82-185; the state `jq` near l.207-211; the ABOUTME lines)
- Modify: `kata/tests/check.sh` (two assertions, near l.86 and l.167)
- Modify: `kata/tests/preflight.sh` (append two real-Tracker refusal cases)
- Modify: `kata/check` (delete the `github-setup.sh` line, near l.60)
- Delete: `kata/tests/github-setup.sh`

**Interfaces:**
- Produces: `selected.json` now carries `trunk` (a string, the branch checked out at claim), and no longer carries `github` or `start_branch`. Task 3 (`close-selected.sh`), Task 4 (`handoff-selected.sh`), and Task 6 (`run-board.sh`) read `.trunk` from it.
- Note: `claim-next.sh` stops reading `KATA_STACK_BASE_FILE` here; Task 6 removes the code in `run-board.sh` that exports it. Between the two tasks the export is harmless dead weight.

- [ ] **Step 1: Update the existing-branch assertion (red first)**

In `kata/tests/check.sh`, the claim-and-persist case near l.86 asserts the persisted trunk. Change:

```sh
  jq -e '.start_branch == "main"' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'starting branch was not persisted'
```

to:

```sh
  jq -e '.trunk == "main"' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'trunk was not persisted'
```

The existing-feature-branch case near l.167 asserts the base and the (absent) GitHub decision. Change:

```sh
  jq -e --arg base "$old_head" '.base_commit == $base and has("github") and .github == null' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'non-GitHub base and publication decision not saved'
```

to:

```sh
  jq -e --arg base "$old_head" '.base_commit == $base and .trunk == "feat/already-here" and (has("github") | not) and (has("start_branch") | not)' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'trunk and base were not saved'
```

- [ ] **Step 2: Run check.sh and watch the claim cases fail**

Run: `sh kata/tests/check.sh`
Expected: FAIL — `trunk was not persisted` (the real `claim-next.sh` still writes `start_branch`, not `trunk`).

- [ ] **Step 3: Record the trunk and refuse task branches**

In `kata/scripts/claim-next.sh`, replace the `start_branch` line (near l.30):

```sh
start_branch=$(git symbolic-ref --quiet --short HEAD) || { printf 'detached HEAD cannot be prepared automatically\n' >&2; exit 1; }
```

with:

```sh
trunk=$(git symbolic-ref --quiet --short HEAD) || { printf 'detached HEAD; check out the branch this work should land on\n' >&2; exit 1; }
case "$trunk" in
  kata/*) printf '%s is a task branch; check out the branch this work should land on\n' "$trunk" >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Delete the GitHub and stack-base block**

Delete `kata/scripts/claim-next.sh` lines from `github=null` (near l.82) through the closing `fi` of the `if [ -n "$github_remote" ]; then` block that ends `github=$(jq -n ... )` (near l.185). That removes the stack-base validation, the `github_repository` helper, the remote scan, the `gh repo view` lookup, the `git fetch`, and the `.kata.toml` base check — every remote command in the claim step. The line `base_commit=$(git rev-parse HEAD)` (near l.81) stays; `actor="kata-pipeline-$TRACKER_RUN_ID"` (near l.186) now follows it directly.

- [ ] **Step 5: Write `trunk` into the state file**

In the state-writing `jq` near l.207-211, drop the GitHub and start-branch arguments and add `trunk`. Change:

```sh
jq -n --arg uid "$uid" --arg short "$short_id" --arg qualified "$qualified_id" \
  --arg workspace "$workspace" --arg branch "$branch" --arg base "$base_commit" --arg actor "$actor" --argjson github "$github" \
  --arg start "$start_branch" \
  --argjson issue "$(printf '%s' "$claim_json" | jq '.issue')" \
  '{issue_uid:$uid,short_id:$short,qualified_id:$qualified,workspace:$workspace,branch:$branch,base_commit:$base,actor:$actor,start_branch:$start,github:$github,issue:$issue}' >"$state_tmp"
```

to:

```sh
jq -n --arg uid "$uid" --arg short "$short_id" --arg qualified "$qualified_id" \
  --arg workspace "$workspace" --arg branch "$branch" --arg base "$base_commit" --arg actor "$actor" \
  --arg trunk "$trunk" \
  --argjson issue "$(printf '%s' "$claim_json" | jq '.issue')" \
  '{issue_uid:$uid,short_id:$short,qualified_id:$qualified,workspace:$workspace,branch:$branch,base_commit:$base,actor:$actor,trunk:$trunk,issue:$issue}' >"$state_tmp"
```

- [ ] **Step 6: Reword the ABOUTME**

`kata/scripts/claim-next.sh` line 3 mentions publication or a starting branch. Set the two ABOUTME lines to describe the local-only trunk model, for example:

```sh
# ABOUTME: Guards the target tree, claims one ready unowned kata, and binds its identity.
# ABOUTME: Records the trunk to land on later and writes run state only after a confirmed claim.
```

- [ ] **Step 7: Run check.sh and watch it pass**

Run: `sh kata/tests/check.sh`
Expected: PASS.

- [ ] **Step 8: Append the trunk-guard cases to preflight.sh**

`kata/tests/preflight.sh` ends after the dirty-tree case with its `ok -` line. The dirty guard runs before the trunk guard, so commit the formerly dirty files first, then exercise a detached HEAD and a task branch on a clean tree. Append after the existing `ok -` line:

```sh
git -C "$repo" add uncommitted.txt .gitignore .kata.toml
git -C "$repo" commit -qm 'test: commit the formerly dirty files'

git -C "$repo" switch -q --detach
if tracker --git off --workdir "$repo" --artifact-dir "$test_root/artifacts-detached" --json --no-tui \
  "$pipeline_dir/complete.dip" >"$test_root/detached.log" 2>&1; then
  printf 'FAIL: tracker accepted a detached HEAD\n' >&2
  cat "$test_root/detached.log" >&2
  exit 1
fi
set -- "$test_root"/artifacts-detached/*/ClaimNext/status.json
if [ "$#" -ne 1 ] || [ ! -f "$1" ] || ! jq -e \
  '.outcome == "fail" and (.context_updates.tool_stderr |
    contains("detached HEAD; check out the branch this work should land on"))' \
  "$1" >/dev/null; then
  printf 'FAIL: detached HEAD did not stop at the trunk guard\n' >&2
  cat "$test_root/detached.log" >&2
  exit 1
fi
for agent_prompt in "$test_root"/artifacts-detached/*/Implement/prompt.md; do
  if [ -f "$agent_prompt" ]; then
    printf 'FAIL: detached HEAD entered an agent stage\n' >&2
    exit 1
  fi
done
printf 'ok - real tracker refuses a detached HEAD before selection\n'

git -C "$repo" switch -q main
git -C "$repo" switch -qc kata/leftover
if tracker --git off --workdir "$repo" --artifact-dir "$test_root/artifacts-task-branch" --json --no-tui \
  "$pipeline_dir/complete.dip" >"$test_root/task-branch.log" 2>&1; then
  printf 'FAIL: tracker accepted a task branch\n' >&2
  cat "$test_root/task-branch.log" >&2
  exit 1
fi
set -- "$test_root"/artifacts-task-branch/*/ClaimNext/status.json
if [ "$#" -ne 1 ] || [ ! -f "$1" ] || ! jq -e \
  '.outcome == "fail" and (.context_updates.tool_stderr |
    contains("kata/leftover is a task branch; check out the branch this work should land on"))' \
  "$1" >/dev/null; then
  printf 'FAIL: a kata task branch did not stop at the trunk guard\n' >&2
  cat "$test_root/task-branch.log" >&2
  exit 1
fi
for agent_prompt in "$test_root"/artifacts-task-branch/*/Implement/prompt.md; do
  if [ -f "$agent_prompt" ]; then
    printf 'FAIL: a task branch entered an agent stage\n' >&2
    exit 1
  fi
done
printf 'ok - real tracker refuses a kata task branch before selection\n'
```

- [ ] **Step 9: Delete the GitHub-setup test and its check line**

```sh
git rm kata/tests/github-setup.sh
```

In `kata/check`, delete the line (near l.60):

```sh
sh "$KATA_DIR/tests/github-setup.sh"
```

Confirm nothing else references it: `git grep -n github-setup` prints nothing.

- [ ] **Step 10: Verify and commit**

Run: `sh kata/tests/preflight.sh` (real Tracker, foreground, a couple of minutes), `sh kata/tests/check.sh`, `./kata/check`, and `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`. All clean.

```sh
git status
git add kata/scripts/claim-next.sh kata/tests/check.sh kata/tests/preflight.sh kata/check
git commit -m "feat(kata): record the trunk to land on and drop GitHub from the claim"
```

(`git rm` already staged the deletion; name the other files explicitly.)

---

### Task 3: The close step lands on trunk (drops GitHub PR publication)

`close-selected.sh` keeps every check through "selected kata is no longer open and owned by this run", then fast-forwards trunk to the approved commit with a compare-and-swap, closes the kata, returns to trunk, and deletes the task branch. No remote command survives. The GitHub PR publication block is deleted. `kata/check` gains a guard that fails if any remote Git or `gh` command reappears in the pipeline runtime.

**Files:**
- Modify: `kata/scripts/close-selected.sh` (ABOUTME l.2-3; delete the GitHub block l.39-113; insert the landing block; reword the re-check l.117; append the landing report)
- Modify: `kata/complete.dip:104` (CloseSelected label)
- Modify: `kata/prompts/implement.md:17-18` (stale PR/push sentence)
- Rewrite: `kata/tests/close.sh`
- Modify: `kata/check` (delete the `publish.sh` line near l.64; add the remote-command guard before the `shellcheck` line)
- Delete: `kata/tests/publish.sh`

**Interfaces:**
- Consumes: `selected.json.trunk` and `.qualified_id` (from Task 2); `.workspace`, `.branch`, `.base_commit`, `.actor`, `.issue_uid` (unchanged).
- Produces: on success, `refs/heads/<trunk>` fast-forwarded to the approved commit, the kata closed, the task branch deleted, the checkout back on trunk; stdout carries `Landed <qualified id> on <trunk> at <head>` then the `close-ok` marker. Task 4 (handoff) relies on `CloseSelected/status.json` still recording `fail` on any refusal; Task 6 (board) relies on the completed child ending on trunk, clean, branch gone, kata closed, and on the `close-ok` marker.
- Depends on Task 2 having already removed the `gh`/`git fetch` calls from `claim-next.sh`; the guard added here scans the whole runtime and would fail otherwise.

- [ ] **Step 1: Rewrite close.sh for the landing behavior (red first)**

Replace `kata/tests/close.sh` entirely with:

```sh
#!/bin/sh
# ABOUTME: Exercises the close step: pre-landing refusals, the trunk fast-forward, and landing refusals.
# ABOUTME: Uses a fixture kata on PATH and disposable Git repositories; never touches a real daemon.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
script="$pipeline_dir/scripts/close-selected.sh"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
command -v jq >/dev/null

mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Fixture kata for close tests: answers show and records the close call.
# ABOUTME: Fails close once when a fail-close file exists so a rerun can be observed.
set -eu
verb=$1
shift
[ "$1" = --workspace ] || { printf 'fixture kata: expected --workspace, got %s\n' "$1" >&2; exit 91; }
fixture="$2/.tracker/close-fixture"
shift 2
printf '%s %s\n' "$verb" "$*" >>"$fixture/kata.log"
case "$verb" in
  show)
    jq -n --arg uid "$1" '{issue:{uid:$uid,status:"open",owner:"kata-pipeline-test"}}'
    ;;
  close)
    if [ -e "$fixture/fail-close" ]; then
      rm -f "$fixture/fail-close"
      printf 'fixture kata: close failed once\n' >&2
      exit 7
    fi
    printf '%s\n' "$*" >"$fixture/close.args"
    ;;
  *) printf 'fixture kata: unexpected call %s %s\n' "$verb" "$*" >&2; exit 2 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

run_close() {
  (cd "$repo" && TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$repo" sh "$script") \
    >"$test_root/output" 2>&1
}

reject() {
  if run_close; then fail "close accepted: $1"; fi
  grep -F "$1" "$test_root/output" >/dev/null || fail "wrong refusal, wanted: $1"
}

new_repo() {
  repo="$test_root/$1"
  git init -q -b main "$repo"
  repo=$(cd "$repo" && pwd -P)
  git -C "$repo" config user.name 'Pipeline check'
  git -C "$repo" config user.email 'pipeline-check@example.invalid'
  git -C "$repo" config commit.gpgsign false
  printf '.tracker/\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -qm 'test: seed closure repository'
  base=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" switch -qc kata/5fav-test
  run_dir="$repo/.tracker/runs/test"
  fixture="$repo/.tracker/close-fixture"
  mkdir -p "$run_dir" "$fixture" "$repo/.tracker/turn_overrides"
  printf '450\n' >"$repo/.tracker/turn_overrides/Implement"
  jq -n --arg workspace "$repo" --arg base "$base" \
    '{workspace:$workspace,issue_uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",short_id:"5fav",
      qualified_id:"demo#5fav",branch:"kata/5fav-test",base_commit:$base,
      actor:"kata-pipeline-test",trunk:"main"}' >"$run_dir/selected.json"
}

add_evidence() {
  printf 'change\n' >"$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -qm 'test: task change'
  head=$(git -C "$repo" rev-parse HEAD)
  printf 'test command\n' >"$run_dir/verification.txt"
  printf 'Implemented the selected behavior and verified its acceptance checks.\n' >"$run_dir/completion.md"
  printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
  printf '%s\n' "$head" >"$run_dir/review-scope.approved"
}

# --- pre-landing refusals (kata is never called) ---
new_repo refusals
reject 'no task commit'
printf 'change\n' >"$repo/file"
reject 'working tree is not clean'
git -C "$repo" add file
git -C "$repo" commit -qm 'test: task change'
head=$(git -C "$repo" rev-parse HEAD)
reject 'verification evidence is missing'
printf 'test command\n' >"$run_dir/verification.txt"
reject 'completion summary is missing'
printf 'Implemented the selected behavior and verified its acceptance checks.\n' >"$run_dir/completion.md"
reject 'does not approve current commit'
printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
reject 'does not approve current commit'
printf '%s\n' "$head" >"$run_dir/review-scope.approved"
git -C "$repo" switch -qc kata/other
reject 'task branch changed'
git -C "$repo" switch -q kata/5fav-test
cp "$run_dir/selected.json" "$test_root/saved-state"
jq --arg w "$test_root" '.workspace = $w' "$run_dir/selected.json" >"$test_root/wrong-state"
cp "$test_root/wrong-state" "$run_dir/selected.json"
reject 'tracker workspace changed'
cp "$test_root/saved-state" "$run_dir/selected.json"
[ ! -e "$fixture/kata.log" ] || fail 'refusals: kata was called before evidence was complete'
printf 'ok - close rejects uncommitted, unverified, unapproved, stale, or displaced work\n'

# --- land (happy path) ---
new_repo land
add_evidence
run_close || fail 'land: close-selected exited non-zero'
[ "$(git -C "$repo" rev-parse refs/heads/main)" = "$head" ] || fail 'land: main was not fast-forwarded to head'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = main ] || fail 'land: checkout did not return to trunk'
if git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test; then fail 'land: task branch survived'; fi
grep -F -- "--commit $head" "$fixture/close.args" >/dev/null || fail 'land: close call lacks --commit head'
grep -F 'Landed on main' "$fixture/close.args" >/dev/null || fail 'land: completion message lacks the Landed line'
grep -Fx "Landed demo#5fav on main at $head" "$test_root/output" >/dev/null || fail 'land: stdout lacks the Landed line'
grep -Fx 'close-ok' "$test_root/output" >/dev/null || fail 'land: close-ok was not printed'
[ ! -e "$repo/.tracker/turn_overrides/Implement" ] || fail 'land: turn override survived'
printf 'ok - a fully approved task fast-forwards trunk, closes the kata, and deletes the branch\n'

# --- trunk moved after the claim ---
new_repo moved
add_evidence
git -C "$repo" switch -q main
printf 'later\n' >"$repo/later.txt"
git -C "$repo" add later.txt
git -C "$repo" commit -qm 'test: trunk moved after the claim'
moved_tip=$(git -C "$repo" rev-parse main)
git -C "$repo" switch -q kata/5fav-test
reject 'trunk main moved from'
[ "$(git -C "$repo" rev-parse main)" = "$moved_tip" ] || fail 'moved: main changed despite the refusal'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail 'moved: checkout changed'
git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail 'moved: task branch was deleted'
[ ! -e "$fixture/close.args" ] || fail 'moved: kata close ran despite the refusal'
printf 'ok - a trunk that moved after the claim is refused before any change\n'

# --- close fails once, then a rerun lands nothing twice and closes ---
new_repo failonce
add_evidence
: >"$fixture/fail-close"
reject 'fixture kata: close failed once'
[ "$(git -C "$repo" rev-parse refs/heads/main)" = "$head" ] || fail 'failonce: main was not landed before the failed close'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail 'failonce: checkout left the task branch'
git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail 'failonce: task branch was deleted after the failed close'
if grep -Fx 'close-ok' "$test_root/output" >/dev/null; then fail 'failonce: close-ok printed despite the failed close'; fi
run_close || fail 'failonce: rerun did not succeed'
[ "$(git -C "$repo" rev-parse refs/heads/main)" = "$head" ] || fail 'failonce: rerun changed main'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = main ] || fail 'failonce: rerun did not return to trunk'
if git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test; then fail 'failonce: rerun left the task branch'; fi
grep -Fx 'close-ok' "$test_root/output" >/dev/null || fail 'failonce: rerun did not print close-ok'
printf 'ok - a close that fails once leaves trunk landed and a rerun finishes without landing twice\n'

# --- trunk checked out in another worktree ---
new_repo worktree
add_evidence
git -C "$repo" worktree add "$test_root/wt-main" main >/dev/null 2>&1
reject 'trunk main is checked out in another worktree'
[ "$(git -C "$repo" rev-parse refs/heads/main)" = "$base" ] || fail 'worktree: main changed despite the refusal'
git -C "$repo" show-ref --quiet --verify refs/heads/kata/5fav-test || fail 'worktree: task branch was deleted'
[ ! -e "$fixture/close.args" ] || fail 'worktree: kata close ran despite the refusal'
printf 'ok - a trunk checked out in another worktree is refused\n'

# --- trunk branch missing ---
new_repo missingtrunk
add_evidence
jq '.trunk = "release"' "$run_dir/selected.json" >"$run_dir/selected.json.tmp"
mv "$run_dir/selected.json.tmp" "$run_dir/selected.json"
reject 'trunk release is missing'
[ ! -e "$fixture/close.args" ] || fail 'missingtrunk: kata close ran despite the refusal'
printf 'ok - a missing trunk branch is refused\n'

# --- selected.json without trunk (predates landing on close) ---
new_repo predates
add_evidence
jq 'del(.trunk)' "$run_dir/selected.json" >"$run_dir/selected.json.tmp"
mv "$run_dir/selected.json.tmp" "$run_dir/selected.json"
reject 'predates landing on close'
[ "$(git -C "$repo" rev-parse refs/heads/main)" = "$base" ] || fail 'predates: main changed'
[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" = kata/5fav-test ] || fail 'predates: checkout changed'
[ ! -e "$fixture/close.args" ] || fail 'predates: kata close ran'
printf 'ok - a run claimed before landing on close is refused for inspection\n'
```

- [ ] **Step 2: Run close.sh and watch the landing cases fail**

Run: `sh kata/tests/close.sh`
Expected: FAIL — the `land` case fails first (the current `close-selected.sh` reaches the GitHub block, which finds no `github` key and refuses with "GitHub setup state is missing" rather than landing).

- [ ] **Step 3: Reword the ABOUTME**

In `kata/scripts/close-selected.sh`, replace lines 2-3:

```sh
# ABOUTME: Publishes the approved task commit to a GitHub PR before closing its bound kata.
# ABOUTME: Checks saved repository identity and review evidence before any publication.
```

with:

```sh
# ABOUTME: Lands the approved task commit on its trunk branch, then closes the bound kata.
# ABOUTME: Fast-forwards trunk with a compare-and-swap and touches no remote.
```

- [ ] **Step 4: Replace the GitHub block with the landing block**

Delete `kata/scripts/close-selected.sh` lines 39 to 113 (from `jq -e 'has("github")' "$state" >/dev/null || {` through the closing `fi` of the `if jq -e '.github != null' ...` block). In their place insert, keeping the same order as the spec:

```sh
trunk=$(jq -er '.trunk' "$state") || {
  printf 'selected.json has no trunk; this run predates landing on close and needs manual inspection\n' >&2
  exit 1
}
qualified_id=$(jq -r '.qualified_id // .issue_uid' "$state")
trunk_commit=$(git rev-parse --quiet --verify "refs/heads/$trunk") || { printf 'trunk %s is missing\n' "$trunk" >&2; exit 1; }
if git worktree list --porcelain | grep -qxF "branch refs/heads/$trunk"; then
  printf 'trunk %s is checked out in another worktree\n' "$trunk" >&2; exit 1
fi
git merge-base --is-ancestor "$trunk_commit" "$head" || {
  printf 'trunk %s moved from %s to %s since the claim; rebase the task branch on it and rerun the reviews\n' \
    "$trunk" "$base" "$trunk_commit" >&2
  exit 1
}
completion=$(printf '%s\n\nLanded on %s' "$completion" "$trunk")
git update-ref -m "kata: land $qualified_id" "refs/heads/$trunk" "$head" "$trunk_commit"
```

The `jq -er '.trunk'` refuses a `null` or absent `trunk` (its non-zero exit drives the `|| { ... }`). `git update-ref <ref> <new> <old>` is a compare-and-swap: if trunk moved between the ancestor check and here, it fails and changes nothing. No checkout runs, so the tree stays on the task branch.

- [ ] **Step 5: Reword the re-check and add the landing report**

The re-check just before the close call (now near the end of the file, `printf 'task branch or working tree changed during publication\n'`) changes `during publication` to `during landing`:

```sh
[ "$(git rev-parse HEAD)" = "$head" ] &&
  [ "$(git symbolic-ref --quiet --short HEAD)" = "$branch" ] &&
  [ -z "$(git status --porcelain --untracked-files=normal)" ] || {
  printf 'task branch or working tree changed during landing\n' >&2; exit 1
}
```

The `kata close ...` call, the `rm -f "$workspace/.tracker/turn_overrides/Implement"` line, and the final `printf 'close-ok\n'` stay. Between the `rm` and the `close-ok`, add the return to trunk and the report:

```sh
git switch --quiet "$trunk"
git branch --quiet --delete "$branch"
printf 'Landed %s on %s at %s\n' "$qualified_id" "$trunk" "$head"
printf 'close-ok\n'
```

Trunk now equals head, so the switch changes no file and the safe `--delete` (the branch is merged into trunk) succeeds.

- [ ] **Step 6: Run close.sh and watch it pass**

Run: `sh kata/tests/close.sh`
Expected: PASS (every `ok -` line prints).

- [ ] **Step 7: Update the node label, the prompt, and delete publish.sh**

In `kata/complete.dip:104`:

```
    label: "Publish the approved task and close the kata"
```

becomes:

```
    label: "Land the approved task and close the kata"
```

In `kata/prompts/implement.md`, the sentence spanning lines 17-18:

```
After both reviews approve, the pipeline pushes this branch and opens a PR when GitHub
is configured, then closes the issue. Merging remains the operator's job. Extract this
```

becomes:

```
After both reviews approve, the pipeline lands this branch on the trunk it was claimed
from and closes the issue. Nothing is pushed; the operator pushes when ready. Extract this
```

(Leave line 19-20 "item's requirements ... branch-switch, push, or merge steps yourself." unchanged; it still forbids the worker from running those steps itself.)

Delete the publication test:

```sh
git rm kata/tests/publish.sh
```

- [ ] **Step 8: Drop the publish.sh line and add the remote-command guard to kata/check**

In `kata/check`, delete the line near l.64:

```sh
sh "$KATA_DIR/tests/publish.sh"
```

Immediately before the final `shellcheck ...` line, add:

```sh
# No remote Git or gh command may appear in the pipeline runtime; pushing is the operator's job.
if git -C "$KATA_DIR/.." grep -nE 'git[[:space:]]+(fetch|push|ls-remote)|(^|[^[:alnum:]_.-])gh[[:space:]]' -- \
  'kata/scripts/*.sh' kata/board-report kata/answer 'kata/*.dip'; then
  printf 'kata/check: a remote Git or gh command is present in the pipeline runtime\n' >&2
  exit 1
fi
```

`git grep` exits 0 when it prints a match, so a hit fails the check and shows the offending lines. The guard scans the runtime scripts, the report and answer helpers, and the DIP files — not the tests, which may still name these commands in fixture prose. It relies on Task 2 having removed `claim-next.sh`'s `gh`/`git fetch`; if any runtime file (comments included) still contains the tokens `git push`, `git fetch`, `git ls-remote`, or a ` gh ` command, reword it.

- [ ] **Step 9: Verify and commit**

Run: `sh kata/tests/close.sh`, `./kata/check`, and `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`. All clean.

```sh
git status
git add kata/scripts/close-selected.sh kata/complete.dip kata/prompts/implement.md kata/tests/close.sh kata/check
git commit -m "feat(kata): land the approved task on trunk at close instead of opening a PR"
```

(`git rm` already staged the `publish.sh` deletion; name the other files explicitly.)

---

### Task 4: The handoff restores the trunk and stops if the close already landed

`handoff-selected.sh` reads `trunk` instead of `start_branch`, restores the checkout with `git switch -q <trunk>`, and renames the close-failure reason from `publish` to `land`. Its `handoff.json` carries `trunk` in place of `start_branch`. Before it labels or comments, it checks that the kata is still open; a kata the close step already closed (it landed the commit but failed a later step) stops the handoff for inspection instead of relabeling a closed kata.

**Files:**
- Modify: `kata/scripts/handoff-selected.sh` (trunk read l.17-20; the "later evidence" comment l.30; reason l.35; branch restore l.52; the open-kata guard before l.68; the `handoff.json` build l.70-74)
- Modify: `kata/tests/handoff.sh` (fixture `show` verb; `trunk` in `selected.json`; the `implement` keys assertion; rename the `publish` case to `land`; a new closed-kata case; the `legacy` case)

**Interfaces:**
- Consumes: `selected.json.trunk` (from Task 2); `CloseSelected/status.json` outcome (from Task 3, which still records `fail` on any close refusal); `kata show --workspace <ws> <uid> --json` returning `{issue:{uid,status,...}}`.
- Produces: `handoff.json` shaped `{run_id, issue_uid, qualified_id, reason, label, branch, base_commit, wip_commit, trunk, question}`, consumed by Task 5 (board-report) and Task 6 (board). On a closed kata it writes no `handoff.json` and exits 1, so Task 6's failed-child path finds no valid record and stops the sweep with `child <id> needs inspection`.

- [ ] **Step 1: Teach the fixture kata `show` and move the cases onto trunk (red first)**

In `kata/tests/handoff.sh`, the fixture kata answers only `label` and `comment` today. `kata show` carries no `--as`, so it must be handled before the `--as` check. After the line

```sh
[ ! -e "$fixture/fail-$verb" ] || exit 95
```

insert:

```sh
if [ "$verb" = show ]; then
  status=open
  [ ! -e "$fixture/closed" ] || status=closed
  jq -n --arg uid "$1" --arg status "$status" '{issue:{uid:$uid,status:$status,owner:"kata-pipeline-test"}}'
  exit 0
fi
```

In `new_repo`, the `selected.json` builder ends with `start_branch:"main",github:null`. Replace those two keys with `trunk:"main"`:

```sh
  jq -n --arg workspace "$repo" --arg base "$base" '{workspace:$workspace,issue_uid:"01ARZ3NDEKTSV4RRFFQ69G5FAV",
    short_id:"5fav",qualified_id:"demo#5fav",branch:"kata/5fav-test",base_commit:$base,actor:"kata-pipeline-test",
    trunk:"main"}' >"$run_dir/selected.json"
```

- [ ] **Step 2: Move the `implement` keys assertion onto trunk**

In the `implement` case, the `handoff.json` assertion pins `start_branch` and the full key list. Replace `.start_branch == "main"` with `.trunk == "main"` and swap `start_branch` for `trunk` in the sorted `keys`:

```sh
jq -e --arg base "$base" --arg wip "$wip" '.run_id == "test" and .issue_uid == "01ARZ3NDEKTSV4RRFFQ69G5FAV" and
  .qualified_id == "demo#5fav" and .branch == "kata/5fav-test" and .base_commit == $base and .wip_commit == $wip and
  .trunk == "main" and .question == null and
  keys == ["base_commit","branch","issue_uid","label","qualified_id","question","reason","run_id","trunk","wip_commit"]' \
  "$run_dir/handoff.json" >/dev/null || fail 'implement: handoff.json fields are wrong'
```

- [ ] **Step 3: Rename the `publish` case to `land` and add the closed-kata case**

Replace the whole `new_repo publish` block (from `new_repo publish` through its `printf 'ok - ...'`) with a `land` case plus a new closed-kata case:

```sh
new_repo land
mkdir -p "$run_dir/CloseSelected" "$run_dir/ReviewCorrectness"
printf '{"outcome":"fail"}\n' >"$run_dir/CloseSelected/status.json"
printf '{"outcome":"success"}\n' >"$run_dir/ReviewCorrectness/status.json"
printf 'Trunk moved after the claim; rebase and rerun the reviews.\n' >"$run_dir/handoff.md"
handoff land
expect_record land needs-review
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'land: trunk was not restored'
[ "$(sed -n '1p' "$fixture/comment.md")" = 'Trunk moved after the claim; rebase and rerun the reviews.' ] ||
  fail 'land: custom handoff text does not lead the comment'
printf 'ok - a landing failure that left the kata open outranks reviews and keeps the custom handoff text\n'

new_repo closed-after-land
mkdir -p "$run_dir/CloseSelected"
printf '{"outcome":"fail"}\n' >"$run_dir/CloseSelected/status.json"
: >"$fixture/closed"
handoff closed-after-land
grep -F 'kata demo#5fav is closed; the close step landed it but did not finish' "$test_root/output" >/dev/null ||
  fail 'closed-after-land: message is missing'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'closed-after-land: trunk was not restored'
[ ! -e "$run_dir/handoff.json" ] || fail 'closed-after-land: handoff.json was written for a closed kata'
[ ! -e "$fixture/labels" ] || fail 'closed-after-land: a label was added for a closed kata'
[ ! -e "$fixture/comment.md" ] || fail 'closed-after-land: a comment was written for a closed kata'
if grep -Fx 'handoff-ok' "$test_root/output" >/dev/null; then fail 'closed-after-land: handoff-ok was printed'; fi
printf 'ok - a kata the close step already closed stops the handoff for inspection\n'
```

The `land` case leaves no `closed` marker, so the fixture reports the kata open and the handoff records `land` as before. The `closed-after-land` case sets the marker, so the open-kata guard (added in Step 6) fires after the branch restore and before any label.

- [ ] **Step 4: Move the `legacy` case onto trunk**

The `legacy` case strips the field the script refuses to run without. Change it from `start_branch` to `trunk`:

```sh
new_repo legacy
jq 'del(.trunk)' "$run_dir/selected.json" >"$run_dir/selected.json.tmp"
mv "$run_dir/selected.json.tmp" "$run_dir/selected.json"
handoff legacy
grep -F 'selected.json has no trunk' "$test_root/output" >/dev/null || fail 'legacy: message is missing'
[ ! -e "$fixture/kata.log" ] || fail 'legacy: kata was called'
[ "$(git -C "$repo" branch --show-current)" = kata/5fav-test ] || fail 'legacy: checkout changed'
printf 'ok - a run claimed before the trunk was recorded stops for inspection\n'
```

- [ ] **Step 5: Run handoff.sh and watch the trunk cases fail**

Run: `sh kata/tests/handoff.sh`
Expected: FAIL — the `implement` case fails first, because the live script still writes `start_branch` and the assertion now demands `trunk`.

- [ ] **Step 6: Move the script onto trunk and add the open-kata guard**

In `kata/scripts/handoff-selected.sh`, replace the `start_branch` read (lines 17-20):

```sh
start_branch=$(jq -er '.start_branch' "$state") || {
  printf 'selected.json has no start_branch; this run predates the branch restore and needs manual inspection\n' >&2
  exit 1
}
```

with a `trunk` read:

```sh
trunk=$(jq -er '.trunk' "$state") || {
  printf 'selected.json has no trunk; this run predates landing on close and needs manual inspection\n' >&2
  exit 1
}
```

Reword the "later evidence" comment (line 30) so it stays truthful:

```sh
  # Later evidence outranks earlier: a question, then a landing failure, then any review, then a turn limit.
```

Rename the close-failure reason (line 35) from `publish` to `land`:

```sh
  elif jq -e '.outcome == "fail"' "$TRACKER_RUN_DIR/CloseSelected/status.json" >/dev/null 2>&1; then
    reason=land
```

Restore the trunk (line 52):

```sh
  git switch -q "$trunk"
```

Immediately before the `kata label add ...` line, insert the open-kata guard:

```sh
issue=$(kata show --workspace "$workspace" "$uid" --json)
printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "open"' >/dev/null || {
  printf 'kata %s is closed; the close step landed it but did not finish; inspect %s\n' "$qualified_id" "$workspace" >&2
  exit 1
}
```

The guard runs after the branch restore and before any label, comment, or `handoff.json`. A closed kata means the close step landed and closed it but failed a later step; relabeling it would be wrong, so the handoff stops and the board treats the missing `handoff.json` as a child needing inspection.

- [ ] **Step 7: Move the `handoff.json` build onto trunk**

Replace the `handoff.json` builder (lines 70-74):

```sh
jq -n --arg run "$run_id" --arg uid "$uid" --arg qualified "$qualified_id" --arg reason "$reason" --arg label "$label" \
  --arg branch "$branch" --arg base "$base_commit" --arg wip "$wip_commit" --arg start "$start_branch" --arg question "$question" \
  '{run_id:$run,issue_uid:$uid,qualified_id:$qualified,reason:$reason,label:$label,branch:$branch,base_commit:$base,
    wip_commit:(if $wip == "" then null else $wip end),start_branch:$start,
    question:(if $question == "" then null else $question end)}' >"$TRACKER_RUN_DIR/handoff.json.tmp"
```

with the `trunk` form:

```sh
jq -n --arg run "$run_id" --arg uid "$uid" --arg qualified "$qualified_id" --arg reason "$reason" --arg label "$label" \
  --arg branch "$branch" --arg base "$base_commit" --arg wip "$wip_commit" --arg trunk "$trunk" --arg question "$question" \
  '{run_id:$run,issue_uid:$uid,qualified_id:$qualified,reason:$reason,label:$label,branch:$branch,base_commit:$base,
    wip_commit:(if $wip == "" then null else $wip end),trunk:$trunk,
    question:(if $question == "" then null else $question end)}' >"$TRACKER_RUN_DIR/handoff.json.tmp"
```

- [ ] **Step 8: Run handoff.sh and watch it pass**

Run: `sh kata/tests/handoff.sh`
Expected: PASS (every `ok -` line prints).

- [ ] **Step 9: Verify and commit**

Run: `sh kata/tests/handoff.sh`, `./kata/check`, and `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`. All clean.

```sh
git status
git add kata/scripts/handoff-selected.sh kata/tests/handoff.sh
git commit -m "feat(kata): restore the trunk on handoff and stop when the close already landed"
```

---

### Task 5: The board report shows the landed commit instead of a PR URL

`kata/board-report` stops carrying `pr_url`. A completed item records the landed `commit` (validated as a full hex SHA, like the other commit fields) and prints as `- <qualified id>: landed <12 hex> (run <child id>)`. The pull-request URL regex and its clause in the safe-list refusal go, and the `land` failure reason reads "landing failed".

**Files:**
- Modify: `kata/board-report` (completed item builder l.71-72; failed item builder l.79-80; safe-list `--arg`, body, and refusal l.88-97; remaining item l.119; reason text l.137; completed text line l.147-148)
- Modify: `kata/tests/report.sh` (completed ledger fixtures; expected text; JSON assertions; the poison case; handoff-fixture field name)

**Interfaces:**
- Consumes: a completed ledger entry `{run_id, kind:"completed", issue_uid, branch, commit}` (Task 6 writes this) and its `selected.json.qualified_id`; a failed child's `handoff.json` (Task 4) with `reason == "land"`.
- Produces: the text and `--json` report. No later task depends on it.

- [ ] **Step 1: Drop github and pr_url from the completed ledger fixtures (red first)**

In `kata/tests/report.sh`, four completed ledger entries carry `github` and `pr_url`; a landed ledger entry carries neither. Trim each to `{run_id, kind, issue_uid, branch, commit}`.

The `newer` ledger entry (line 84):

```sh
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'"},
```

The two `resweep` completed entries (lines 159 and 161):

```sh
  {"run_id":"c1c1c1c1c1c1","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-c1c1c1c1c1c1","commit":"'"$head"'"},
```

```sh
  {"run_id":"a2a2a2a2a2a2","kind":"completed","issue_uid":"01REVIEW000000000000000000","branch":"kata/bq4e-a2a2a2a2a2a2","commit":"'"$wip"'"},
```

The `poison-id` completed entry (line 245):

```sh
  {"run_id":"f2f2f2f2f2f2","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-f2f2f2f2f2f2","commit":"'"$head"'"}]}'
```

(The `poison-pr` entry on line 242 is replaced whole in Step 4.)

- [ ] **Step 2: Rewrite the expected completed text**

The `newer` expected block (lines 96-99) drops the PR line and prints the landed commit. Replace:

```
Board newer in $repo: finished
Completed (1)
- demo#5fav on kata/5fav-c1c1c1c1c1c1
  https://github.com/o/r/pull/12
```

with:

```
Board newer in $repo: finished
Completed (1)
- demo#5fav: landed 9abcdef09abc (run c1c1c1c1c1c1)
```

The `resweep` expected block (lines 166-170) becomes two landed lines. Replace:

```
Completed (2)
- demo#5fav on kata/5fav-c1c1c1c1c1c1
  https://github.com/o/r/pull/12
- demo#bq4e on kata/bq4e-a2a2a2a2a2a2
  no pull request
```

with:

```
Completed (2)
- demo#5fav: landed 9abcdef09abc (run c1c1c1c1c1c1)
- demo#bq4e: landed 5678ef015678 (run a2a2a2a2a2a2)
```

(`$head` is `9abcdef0...`, so its 12-char prefix is `9abcdef09abc`; `$wip` is `5678ef01...`, prefix `5678ef015678`.)

- [ ] **Step 3: Move the JSON assertions onto commit**

Add `--arg head "$head"` to the JSON-shape `jq` (line 119):

```sh
jq -e --arg repo "$repo" --arg answer "$pipeline_dir/answer" --arg base "$base" --arg wip "$wip" --arg short "$short_base" --arg head "$head" '
```

Replace the `pr_url` assertion (line 123):

```sh
  .completed[0].commit == $head and .completed[0].next == [] and
```

Replace `pr_url` with `commit` in the keys list (line 134), keeping it sorted:

```sh
    all(keys == ["base_commit","branch","commit","issue_uid","labels","next","owner","qualified_id","question","reason","run_id","wip_commit"]))
```

- [ ] **Step 4: Replace the PR-poison case with a landed-commit poison case**

The `poison-pr` case (lines 241-243) proved an unsafe PR URL was refused. With `pr_url` gone, poison the landed `commit` instead. Replace those three lines:

```sh
ledger poison-landed '{"workspace":"'"$repo"'","pipeline":"/p/complete.dip","finished":true,"runs":[
  {"run_id":"d2d2d2d2d2d2","kind":"completed","issue_uid":"01COMPLETED000000000000000","branch":"kata/5fav-d2d2d2d2d2d2","commit":"deadbeef; rm -rf /"}]}'
selected d2d2d2d2d2d2 '{"issue_uid":"01COMPLETED000000000000000","qualified_id":"demo#5fav"}'
```

Update the refuse loop (line 263) to name the renamed case:

```sh
for poison in poison-branch poison-dots poison-landed poison-id poison-commit poison-ctrl; do
```

And drop "or pull request URL" from its summary (line 267):

```sh
printf 'ok - a record with an unsafe branch, commit, or id is refused whole\n'
```

- [ ] **Step 5: Rename the handoff fixtures' start_branch to trunk (fidelity)**

`board-report` ignores this field, but Task 4 renamed it in the real `handoff.json`, so the fixtures should match. `start_branch` appears only in the nine handoff fixtures:

```sh
sed -i '' 's/start_branch/trunk/g' kata/tests/report.sh
```

Confirm nothing else changed: `grep -n start_branch kata/tests/report.sh` prints nothing, and `grep -c '"trunk":"main"\|trunk:"main"' kata/tests/report.sh` counts nine.

- [ ] **Step 6: Run report.sh and watch the completed cases fail**

Run: `sh kata/tests/report.sh`
Expected: FAIL — the first `ok` check fails because the live `board-report` still prints `- demo#5fav on kata/5fav-c1c1c1c1c1c1` and a PR line, not the landed line.

- [ ] **Step 7: Record the landed commit in board-report's item builders**

In `kata/board-report`, the completed item builder (lines 71-72) reads `pr_url` from the entry. Read `commit` instead:

```sh
      printf '%s' "$entry" | jq -c --arg qualified "$qualified" '{group:"completed",qualified_id:$qualified,issue_uid,run_id,branch,
        base_commit:null,wip_commit:null,commit:.commit,reason:null,question:null}' \
        >>"$tmp/items.jsonl"
```

The failed item builder (lines 79-80) carries `pr_url:null` for a uniform shape. Carry `commit:null`:

```sh
      jq -c --arg run "$run_id" '{group:(if .reason == "decision" then "needs_decision" else "needs_review" end),
        qualified_id,issue_uid,run_id:$run,branch,base_commit,wip_commit,commit:null,reason,question}' \
        "$child/handoff.json" >>"$tmp/items.jsonl"
```

- [ ] **Step 8: Drop the PR URL from the safe-list and validate the commit**

Replace the safe-list (lines 88-97). Drop the `--arg pr ...`, drop the `pr_url` clause, add a `commit` clause, and reword the refusal to name "id, branch, or commit":

```sh
jq -se --arg qid '^[A-Za-z0-9._-]+(#[A-Za-z0-9._-]+)?$' --arg branch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' \
  --arg commit '^([0-9a-f]{40}|[0-9a-f]{64})$' '
  def clean: type == "string" and (test("[[:cntrl:]]") | not);
  def commit_or_null: . == null or (clean and test($commit));
  all(.[]; (.qualified_id | clean and test($qid)) and
    (.branch | clean and test($branch) and (contains("..") | not)) and
    (.base_commit | commit_or_null) and (.wip_commit | commit_or_null) and
    (.commit | commit_or_null))
' "$tmp/items.jsonl" >/dev/null ||
  { printf 'refusing to print the review: a child record under %s has a missing or unsafe id, branch, or commit\n' "$runs" >&2; exit 1; }
```

A landed commit is a full 40-hex SHA, so `commit_or_null` accepts it and rejects the `deadbeef; rm -rf /` payload from Step 4. Failed and remaining items carry `commit:null`, which `commit_or_null` also accepts.

- [ ] **Step 9: Move the remaining item, reason text, and completed line onto commit**

The remaining item (line 119) carries `pr_url:null`; carry `commit:null`:

```sh
   remaining:[$issues[] | select(.uid as $uid | any($touched[]; . == $uid) | not) |
     {qualified_id, issue_uid:.uid, run_id:null, branch:null, base_commit:null, wip_commit:null, commit:null,
      reason:null, question:null, owner:(.owner // null), labels:(.labels // []), next:[]}]}
```

The reason text (line 137) maps the close-failure reason; rename `publish` to `land`:

```sh
    ({decision:"needs a decision", land:"landing failed", review:"review rejected",
      turn_limit:"turn limit reached twice", implement:"worker stopped",
      unexpected_checkout:"handoff found the wrong branch"} | .[$reason]?) //
```

The completed text line (lines 147-148) prints a PR URL on a second line; print the landed commit on one:

```sh
  "Completed (\(.completed | length))",
  (.completed[] | "- \(.qualified_id): landed \(.commit | short) (run \(.run_id))"),
```

`short` (defined earlier in the same filter) takes the 12-char prefix; a completed commit is never null.

- [ ] **Step 10: Run report.sh and watch it pass**

Run: `sh kata/tests/report.sh`
Expected: PASS (every `ok -` line prints).

- [ ] **Step 11: Verify and commit**

Run: `sh kata/tests/report.sh`, `./kata/check`, and `shellcheck kata/check kata/board-report kata/answer kata/scripts/*.sh kata/tests/*.sh`. All clean.

```sh
git status
git add kata/board-report kata/tests/report.sh
git commit -m "feat(kata): report the landed commit instead of a pull request URL"
```

---

### Task 6: The board lands each kata on trunk instead of stacking

`kata/scripts/run-board.sh` stops carrying a stack base. Each child claims from trunk's current tip (its `HEAD` at start), the close step lands the task on trunk, and the controller verifies the post-land tree: on trunk, clean, the task branch gone, the kata closed. The ledger records `{run_id, kind:"completed", issue_uid, branch, commit}` and the board prints `Landed <qualified id> on <trunk> at <commit>`. `kata/board.dip`'s copy stops mentioning stacked PRs. `kata/tests/board.sh` is an integration test — real Tracker, real Git, a fixture `kata` and fixture child scripts. Its stacked cases become trunk cases, and a new `fresh-board` case proves a second board run claims from a trunk a previous run advanced.

This task is one TDD cycle for an integration test: change the fixtures and every case first (Steps 1-8), watch the whole file go red (Step 9), then change the runtime — `run-board.sh` and `board.dip` — to land (Steps 10-13), and watch it go green (Step 14).

**Design note (ruling):** `close.sh` in `board.sh` stays a fixture (not the real `close-selected.sh`), rewritten to simulate the land. The controller tests inject a close failure through `fail-close` (the `recovery` and `nested-failure` cases), which only a fixture supports; `handoff.sh` stays the real `handoff-selected.sh`, exactly as today, because it is exercised as-is when a node fails. `close-selected.sh`'s own landing logic is covered whole by `kata/tests/close.sh` (Task 3); `board.sh` covers the controller's orchestration and post-land verification, for which a fixture that produces the real post-land git state is enough.

**Files:**
- Rewrite: `kata/tests/board.sh` fixture `claim.sh` (l.114-173), fixture `close.sh` (l.207-223), and the `implement.sh` leave-branch handler (l.189-191)
- Modify: `kata/tests/board.sh` cases (stacked→lands-on-trunk, failing, stacked-failure→landed-then-failure, recovery, unexpected-checkout, refused-record) and add a `fresh-board` case
- Modify: `kata/scripts/run-board.sh` (stack block l.138-144; `record_failure` l.100, l.107, l.110-112; completed block l.184-210)
- Modify: `kata/board.dip` (ABOUTME l.2; goal l.4)

**Interfaces:**
- Consumes: `selected.json` with `trunk` and `qualified_id` (Task 2), the landed post-close git state (Task 3), `handoff.json` with `trunk` (Task 4), and `board-report`'s landed-commit output (Task 5).
- Produces: the ledger completed entry `{run_id, kind:"completed", issue_uid, branch, commit}` that `board-report` reads (Task 5). No later task consumes run-board.

- [ ] **Step 1: Rewrite the claim fixture to cut from trunk and drop the stack**

Replace the `claim.sh` heredoc body (`kata/tests/board.sh` l.114-173, between `cat >"$test_root/workflow/claim.sh" <<'SH'` and its closing `SH`) with:

```sh
#!/bin/sh
# ABOUTME: Creates the next local fixture task and records its actual child identity.
# ABOUTME: Cuts the task branch from the trunk tip so the close step can land it back.
set -eu
cd "$TRACKER_WORKDIR"
mkdir -p "$TRACKER_RUN_DIR"
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
printf '%s\n' "$TRACKER_RUN_ID" >>"$fixture/claims"
remaining=$(cat "$fixture/remaining")
if [ "$remaining" -eq 0 ]; then
  printf 'queue-empty\n'
  exit 0
fi
number=$(wc -l <"$fixture/claims" | tr -d ' ')
# A reclaim names a kata an earlier child handed off; this claim takes it instead of a new one.
if [ -s "$fixture/reclaim" ]; then
  uid=$(cat "$fixture/reclaim")
  : >"$fixture/reclaim"
else
  uid="fixture-item-$number"
fi
actor="kata-pipeline-$TRACKER_RUN_ID"
base=$(git rev-parse HEAD)
trunk=$(git branch --show-current)
branch="kata/item-$number"
git switch -qc "$branch"
printf 'task %s\n' "$number" >"task-$number.txt"
git add "task-$number.txt"
git commit -qm "test: complete fixture task $number"
head=$(git rev-parse HEAD)
jq -n --arg workspace "$TRACKER_WORKDIR" --arg uid "$uid" --arg actor "$actor" --arg branch "$branch" \
  --arg base "$base" --arg trunk "$trunk" \
  '{workspace:$workspace,issue_uid:$uid,short_id:$uid,qualified_id:("fixture#" + $uid),actor:$actor,
    branch:$branch,base_commit:$base,trunk:$trunk}' \
  >"$TRACKER_RUN_DIR/selected.json"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-correctness.approved"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-scope.approved"
printf 'open\n' >"$fixture/$uid.status"
printf '%s\n' "$actor" >"$fixture/$uid.owner"
printf 'claim-ok\n'
```

The stack-base verification, the `github` object, the `base_branch` variable, and `pr-url.txt` all go; `trunk` (the branch checked out when the child starts) replaces `start_branch`.

- [ ] **Step 2: Rewrite the close fixture to land the task on trunk**

Replace the `close.sh` heredoc body (`kata/tests/board.sh` l.207-223) with:

```sh
#!/bin/sh
# ABOUTME: Records a fixture closure after landing the task branch on its trunk.
# ABOUTME: Mirrors the real close step's local land so the controller sees a real post-land tree.
set -eu
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
if [ -f "$fixture/fail-close" ]; then
  printf 'deliberate fixture close failure\n' >&2
  exit 33
fi
cd "$TRACKER_WORKDIR"
trunk=$(jq -r '.trunk' "$TRACKER_RUN_DIR/selected.json")
branch=$(jq -r '.branch' "$TRACKER_RUN_DIR/selected.json")
uid=$(jq -r '.issue_uid' "$TRACKER_RUN_DIR/selected.json")
head=$(git rev-parse HEAD)
git update-ref "refs/heads/$trunk" "$head"
git switch -q "$trunk"
git branch -d "$branch"
printf 'closed\n' >"$fixture/$uid.status"
printf '%s\n' "$uid" >>"$fixture/completed"
remaining=$(cat "$fixture/remaining")
printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
printf 'close-ok\n'
```

The `fail-close` hook stays first, so a forced close failure happens before any land. `git branch -d` safe-deletes the task branch, which succeeds because trunk now points at the same commit.

- [ ] **Step 3: Point the leave-branch worker at the trunk**

In the `implement.sh` fixture's leave-branch handler (l.189-191), read `trunk` instead of `start_branch`. Change:

```sh
  start_branch=$(jq -r '.start_branch' "$TRACKER_RUN_DIR/selected.json")
  git switch -q "$start_branch"
```

to:

```sh
  trunk=$(jq -r '.trunk' "$TRACKER_RUN_DIR/selected.json")
  git switch -q "$trunk"
```

The worker still wanders off the task branch (now onto the trunk), which the handoff records as an `unexpected_checkout` — the `unexpected-checkout` case still holds.

- [ ] **Step 4: Turn the stacked case into a lands-on-trunk case**

Rename the case and drop every stack/PR assertion. Change the header (l.351-352):

```sh
new_case stacked 2
must_succeed 'two stacked tasks'
```

to:

```sh
new_case lands-on-trunk 2
must_succeed 'two tasks landing on trunk'
```

Replace the ledger assertion's last two lines (l.360-361):

```sh
    .runs[1].github.base_branch == .runs[0].branch' "$ledger" >/dev/null ||
  fail 'stacked: the ledger does not show two completed katas stacked under distinct child ids'
```

with:

```sh
    (.runs[0].commit | test("^[0-9a-f]{40}$")) and (.runs[1].commit | test("^[0-9a-f]{40}$")) and
    .runs[0].commit != .runs[1].commit and (.runs[0] | has("github") | not) and (.runs[0] | has("pr_url") | not)' "$ledger" >/dev/null ||
  fail 'lands-on-trunk: the ledger does not show two completed katas with distinct landed commits and no GitHub fields'
```

The commit-count and stacking-history checks (l.362-365) stay as they are — after both lands `main` holds three commits and `HEAD^` is the first landed commit — but rename their `stacked:` prefixes to `lands-on-trunk:`. Delete the stack-base assertion (l.366-367):

```sh
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null || fail 'stacked: the second child did not receive the first branch as its stack base'
```

The child-log and activity checks (l.368-376) stay; rename their `stacked:` prefixes to `lands-on-trunk:`. Replace the second-kata review line and the pull-request line (l.377-378):

```sh
grep -Fx -e '- fixture#fixture-item-2 on kata/item-2' "$test_root/output" >/dev/null || fail 'stacked: the review does not name the second kata'
grep -Fx '  https://github.com/fixture/board/pull/2' "$test_root/output" >/dev/null || fail 'stacked: the review lacks the second pull request'
```

with the landed-commit lines the controller and the report now print:

```sh
commit2=$(jq -r '.runs[1].commit' "$ledger")
short2=$(printf '%s' "$commit2" | cut -c1-12)
child2=$(jq -r '.runs[1].run_id' "$ledger")
grep -Fx "Landed fixture#fixture-item-2 on main at $commit2" "$test_root/output" >/dev/null || fail 'lands-on-trunk: the controller did not log the second land'
grep -Fx "- fixture#fixture-item-2: landed $short2 (run $child2)" "$test_root/output" >/dev/null || fail 'lands-on-trunk: the review does not name the second landed kata'
```

Rename the remaining `stacked:` prefixes in the re-entry block (l.379-386) to `lands-on-trunk:`, and replace the closing summary (l.387):

```sh
printf 'ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry\n'
```

with:

```sh
printf 'ok - real Tracker children use distinct IDs and land on trunk, and a finished ledger sweeps again on re-entry\n'
```

- [ ] **Step 5: Add a fresh-board case that claims from the advanced trunk**

After the `lands-on-trunk` case (before `new_case empty 0`), add a case that runs one board to a landing, then starts a brand-new board run in the same repository and proves its child cuts from the trunk the first run advanced:

```sh
# A brand-new board run in the same workspace claims from the trunk a previous run advanced.
new_case fresh-board 1
must_succeed 'a first board landing one kata'
first_landed=$(git -C "$repo" rev-parse main)
[ "$(jq -r '.runs[0].commit' "$ledger")" = "$first_landed" ] || fail 'fresh-board: main is not at the first landed commit'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'fresh-board: the first board did not end on the trunk'
# A fresh board run: a new parent id and ledger, the same repository and its advanced trunk.
export TRACKER_RUN_ID=board-parent-again
export TRACKER_RUN_DIR="$repo/.tracker/runs/$TRACKER_RUN_ID"
mkdir -p "$TRACKER_RUN_DIR"
ledger="$TRACKER_RUN_DIR/board/state.json"
: >"$fixture/claims"
: >"$fixture/completed"
printf '1\n' >"$fixture/remaining"
must_succeed 'a fresh board run from the advanced trunk'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["completed","empty"]' "$ledger" >/dev/null ||
  fail 'fresh-board: the second board did not land one kata'
second_landed=$(git -C "$repo" rev-parse main)
[ "$(git -C "$repo" rev-parse main^)" = "$first_landed" ] || fail 'fresh-board: the second kata did not land on the first board commit'
[ "$(jq -r '.runs[0].commit' "$ledger")" = "$second_landed" ] || fail 'fresh-board: the ledger commit is not the new trunk tip'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'fresh-board: the second board did not end on the trunk'
expect_marker board-clean 'a fresh board run from the advanced trunk'
printf 'ok - a fresh board run claims from the trunk tip a previous run advanced\n'
```

- [ ] **Step 6: Migrate the failing case to trunk landing**

In the `failing` case, replace the completed-run clause of the ledger assertion (l.405-406):

```sh
  .runs[1].branch == "kata/item-2" and .runs[1].github.base_branch == "main"' "$ledger" >/dev/null ||
  fail 'failing: the ledger does not show a handoff, a completion from main, and an empty sweep'
```

with:

```sh
  .runs[1].branch == "kata/item-2" and (.runs[1].commit | test("^[0-9a-f]{40}$"))' "$ledger" >/dev/null ||
  fail 'failing: the ledger does not show a handoff, a completion, and an empty sweep'
```

Delete the `main_commit` capture (l.409) — the reworked checks below read the ledger directly:

```sh
main_commit=$(git -C "$repo" rev-parse main)
```

In the handoff-record assertion (l.411-413), read `trunk` instead of `start_branch`:

```sh
  '.run_id == $child and .start_branch == "main" and .wip_commit == $wip and
```

becomes:

```sh
  '.run_id == $child and .trunk == "main" and .wip_commit == $wip and
```

Replace the two checkout/stacking checks (l.418-419):

```sh
[ "$(git -C "$repo" branch --show-current)" = kata/item-2 ] || fail 'failing: the checkout is not on kata/item-2'
[ "$(git -C "$repo" rev-parse kata/item-2^)" = "$main_commit" ] || fail 'failing: kata/item-2 does not start from main'
```

with checks that the completed task landed on `main` and its branch is gone:

```sh
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'failing: the checkout is not back on main'
! git -C "$repo" rev-parse --verify --quiet kata/item-2 >/dev/null 2>&1 || fail 'failing: the landed task branch was not deleted'
[ "$(git -C "$repo" rev-parse HEAD)" = "$(jq -r '.runs[1].commit' "$ledger")" ] || fail 'failing: main is not at the landed commit'
```

Delete the stack-base absence check (l.426):

```sh
[ ! -e "$fixture/stack-2.json" ] || fail 'failing: the second child received a stack base after a handoff'
```

Update the reclaim comment (l.434) from "the stack tip" to "the trunk tip", and replace the second-sweep clause (l.442-443):

```sh
  .runs[3].github.base_branch == "kata/item-2"' "$ledger" >/dev/null ||
  fail 'failing: the second sweep did not finish the handed-off kata from the stack tip'
```

with:

```sh
  (.runs[3].commit | test("^[0-9a-f]{40}$"))' "$ledger" >/dev/null ||
  fail 'failing: the second sweep did not finish the handed-off kata from the trunk tip'
```

- [ ] **Step 7: Turn the stacked-failure case into a landed-then-failure case**

Rename the case (l.453):

```sh
new_case stacked-failure 2
```

to:

```sh
new_case landed-then-failure 2
```

Replace the handoff-trunk assertion (l.461-462):

```sh
jq -e '.start_branch == "kata/item-1"' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null ||
  fail 'stacked-failure: the handoff did not start from the completed branch'
```

with:

```sh
jq -e '.trunk == "main"' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null ||
  fail 'landed-then-failure: the handoff trunk is not main'
```

Replace the checkout check (l.464):

```sh
[ "$(git -C "$repo" branch --show-current)" = kata/item-1 ] || fail 'stacked-failure: the checkout is not back on the stack tip'
```

with:

```sh
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'landed-then-failure: the checkout is not back on the trunk'
```

The two commit checks (l.465-466) stay — `HEAD` is the landed commit, and the failed `kata/item-2` still sits two commits above it (its base, the landed commit, then its task commit, then its wip commit) — but rename their prefixes and reword l.466's message from "is not stacked on the completed commit" to "does not sit on the landed commit". Delete the stack-base assertion (l.467-468):

```sh
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null || fail 'stacked-failure: the failed child did not receive the completed branch as its base'
```

Rename the sweep-summary prefix (l.469) and the `expect_marker` label (l.470) to `landed-then-failure`, and replace the closing summary (l.471):

```sh
printf 'ok - a failure after a completion restores the stack tip and keeps the completed base\n'
```

with:

```sh
printf 'ok - a failure after a landing restores the trunk and keeps the landed commit\n'
```

- [ ] **Step 8: Migrate the recovery, unexpected-checkout, and refused-record cases**

In the `recovery` case, the wrong-checkout guard (l.532-534) currently switches to `main` and back to `kata/item-1`. After a land the child ends on `main` with `kata/item-1` gone, so switching to `main` no longer trips the guard. Replace:

```sh
git -C "$repo" switch -q main
must_stop_for_inspection 'changed branch after child recovery'
git -C "$repo" switch -q kata/item-1
```

with two guards that exercise the new checks — a checkout off the trunk, and a resurrected task branch:

```sh
git -C "$repo" switch -qc off-trunk
must_stop_for_inspection 'a checkout that is not the trunk after child recovery'
git -C "$repo" switch -q main
git -C "$repo" branch -D off-trunk
git -C "$repo" branch kata/item-1 HEAD
must_stop_for_inspection 'a resurrected task branch after child recovery'
git -C "$repo" branch -D kata/item-1
```

The unclosed-issue and missing-marker guards that follow (l.535-541) stay unchanged.

In the `unexpected-checkout` case, read `trunk` in the handoff assertion (l.562):

```sh
jq -e '.reason == "unexpected_checkout" and .start_branch == "main" and .wip_commit == null' \
```

becomes:

```sh
jq -e '.reason == "unexpected_checkout" and .trunk == "main" and .wip_commit == null' \
```

In the `refused-record` case, poison the landed commit instead of a pull-request URL (l.655-656):

```sh
jq '.runs[0].pr_url = "https://evil.example/fixture/board/pull/1"' "$ledger" >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"
must_succeed 'a re-entry with a pull request URL the review refuses'
```

becomes:

```sh
jq '.runs[0].commit = "deadbeef; rm -rf /"' "$ledger" >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"
must_succeed 'a re-entry with a landed commit the review refuses'
```

The refusal greps (l.657-660) stay: `board-report` still prints `refusing to print the review` and the controller still prints the review-failed line.

- [ ] **Step 9: Run the board test and watch it fail**

Run: `sh kata/tests/board.sh`
Expected: FAIL. The fixtures now land the task and delete its branch, but the unchanged `run-board.sh` still expects a stack and a `github` field on `selected.json`, so the first completed child trips `stop_for_inspection` (its `has("github")` check and its `HEAD == branch` check both fail against a landed tree). The `lands-on-trunk` case is the first to break.

- [ ] **Step 10: Drop the stack block from the controller**

In `kata/scripts/run-board.sh`, delete lines 138-144 (the comment through `export KATA_STACK_BASE_FILE`):

```sh
    # Empty and failed attempts do not change the stack tip. Only verified child completions do.
    jq '[.runs[] | select(.kind == "completed")] | last' "$state" >"$item/base.json"
    KATA_STACK_BASE_FILE=
    if jq -e '. != null' "$item/base.json" >/dev/null; then
      KATA_STACK_BASE_FILE="$item/base.json"
    fi
    export KATA_STACK_BASE_FILE
```

Leave `index`/`item`/`mkdir -p "$item"` (l.135-137) and the child-launch block (l.145+) in place.

- [ ] **Step 11: Read trunk in record_failure and drop the frozen-stack check**

In `record_failure`, change the handoff-shape assertion (l.99-101) to require `.trunk`:

```sh
  jq -e --arg run "$run_id" '.run_id == $run and
    all(.issue_uid, .reason, .label, .branch, .trunk; type == "string" and length > 0)' \
    "$handoff" >/dev/null 2>&1 || stop_for_inspection
```

Change the checkout check (l.107) to read `.trunk`:

```sh
  [ "$(git symbolic-ref --quiet --short HEAD)" = "$(jq -r '.trunk' "$handoff")" ] || stop_for_inspection
```

Delete the frozen-stack HEAD check (l.110-112):

```sh
  if [ -n "$KATA_STACK_BASE_FILE" ]; then
    [ "$(git rev-parse HEAD)" = "$(jq -r '.commit' "$KATA_STACK_BASE_FILE")" ] || stop_for_inspection
  fi
```

- [ ] **Step 12: Verify the landed tree and record the landed commit**

Replace the completed block (l.184-210) with the trunk-aware version. The `has("github")` check becomes `has("trunk")`; the checkout must be on trunk with the task branch gone; the `pr_url` block goes; the ledger entry drops `github`/`pr_url`; the board line becomes the `Landed` line:

```sh
    jq -e --arg workspace "$workspace" '.workspace == $workspace and
      (.issue_uid | type == "string" and length > 0) and has("trunk")' "$selected" >/dev/null || stop_for_inspection
    jq -e '.outcome == "success" and .context_updates.tool_marker == "close-ok"' \
      "$child/CloseSelected/status.json" >/dev/null 2>&1 || stop_for_inspection
    uid=$(jq -r '.issue_uid' "$selected")
    qualified=$(jq -er '.qualified_id' "$selected")
    branch=$(jq -er '.branch' "$selected")
    trunk=$(jq -er '.trunk' "$selected")
    head=$(git rev-parse HEAD)
    [ "$(git symbolic-ref --quiet --short HEAD)" = "$trunk" ] || stop_for_inspection
    # The close step landed the work and deleted the task branch; a surviving branch means it did not finish.
    if git rev-parse --quiet --verify "refs/heads/$branch" >/dev/null 2>&1; then stop_for_inspection; fi
    dirty=$(git status --porcelain --untracked-files=normal) || stop_board 'git status failed; inspect the checkout'
    [ -z "$dirty" ] || stop_for_inspection
    for approval in review-correctness.approved review-scope.approved; do
      [ "$(sed -n '1p' "$child/$approval" 2>/dev/null || true)" = "$head" ] || stop_for_inspection
    done
    issue=$(kata show --workspace "$workspace" "$uid" --json)
    printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "closed"' >/dev/null || stop_for_inspection
    if jq -e --arg uid "$uid" 'any(.runs[]; .kind == "completed" and .issue_uid == $uid)' "$state" >/dev/null; then
      stop_board "child repeated an already completed kata: $uid"
    fi
    result=$(jq --arg run "$run_id" --arg head "$head" \
      '{run_id:$run,kind:"completed",issue_uid,branch,commit:$head}' "$selected")
    append_run
    printf 'Landed %s on %s at %s\n' "$qualified" "$trunk" "$head"
```

- [ ] **Step 13: Retitle board.dip for landing**

In `kata/board.dip`, replace the second ABOUTME line (l.2):

```
# ABOUTME: Lands each reviewed task on its trunk, then holds the morning review until the operator sweeps again or stops.
```

and the goal (l.4):

```
  goal: "Complete all ready unowned katas sequentially, landing each on its trunk, then hold the morning review until the operator sweeps again or stops."
```

The `RunBoard`/`Report`/`MorningReview`/`Exit` nodes and every edge stay.

- [ ] **Step 14: Run the board test to green, then the full suite, then commit**

Run: `sh kata/tests/board.sh`
Expected: PASS — every case, including `lands-on-trunk`, `fresh-board`, `landed-then-failure`, and `recovery`.

Then run the whole kata suite and ShellCheck:

Run: `./kata/check`
Expected: PASS.

Run: `shellcheck kata/scripts/run-board.sh kata/tests/board.sh`
Expected: no findings.

Commit only these three files (together with Tasks 4–5 under the approved integration grouping):

```bash
git add kata/scripts/run-board.sh kata/board.dip kata/tests/board.sh
git commit -m "feat(kata): land the approved task on trunk at close in the board"
```

(`board.dip` and `run-board.sh` and `board.sh` are the whole change; `git status` first to confirm nothing else is staged.)

---

### Task 7: Reconcile the operator documentation with landing on close

The binding spec's Docs section defines the required changes. Update `kata/README.md`, the `README.md` board row, `kata/BOARD-PLAN.md`, `kata/PLAN.md`, `CHANGELOG.md`, and the affected entries in `gotchas.md`. Document claim-time trunk selection, local landing and task-branch deletion, landing failures and legacy-run refusal, the commit-based morning review, and operator-controlled pushing. Remove current instructions for GitHub publication and stacked bases; preserve historical changelog entries.

- [ ] Update the documents and superseded gotchas entries, including the committed model mapping.
- [ ] Search current operator instructions for stale GitHub publication, stacking, `start_branch`, and PR-report claims; inspect each result rather than rewriting historical plans or changelog records.
- [ ] Record task completion, review evidence, and known limitations in this plan.
- [ ] Run `./kata/check`, review the documentation against the final scripts, and commit named files only. No remote action.
