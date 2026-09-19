#!/bin/sh
# ABOUTME: Checks board orchestration with real Tracker child runs and disposable Git repositories.
# ABOUTME: Uses a local Kata CLI fixture; never claims real issues or contacts model providers.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
for required in scripts/run-board.sh scripts/handoff-selected.sh board-report board.dip; do
  [ -f "$pipeline_dir/$required" ] || {
    printf 'FAIL: %s is missing\n' "$required" >&2
    exit 1
  }
done

test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/bin" "$test_root/workflow/scripts"

cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Supplies board records from a disposable repository and records handoff labels and comments.
# ABOUTME: Rejects unexpected commands so no real Kata daemon can be contacted.
set -eu
verb=$1
shift
action=
if [ "$verb" = label ]; then
  action=$1
  shift
fi
[ "$1" = --workspace ] || exit 91
workspace=$2
shift 2
actor=
if [ "${1:-}" = --as ]; then
  actor=$2
  shift 2
fi
fixture="$workspace/.tracker/board-fixture"
printf '%s %s\n' "$verb${action:+ $action}${actor:+ $actor}" "$*" >>"$fixture/kata.log"
case "$verb" in
  show)
    [ "$#" -eq 2 ] && [ "$2" = --json ] && [ -f "$fixture/$1.status" ] || exit 92
    owner=$(cat "$fixture/$1.owner" 2>/dev/null || true)
    jq -n --arg uid "$1" --arg status "$(cat "$fixture/$1.status")" --arg owner "$owner" \
      '{issue:{uid:$uid,status:$status,owner:(if $owner == "" then null else $owner end)}}'
    ;;
  list)
    [ "$*" = '--status open --limit 0 --json' ] || exit 93
    if [ -f "$fixture/broken-list" ]; then
      printf '%s\n' '{"issues":"every open kata"}'
    elif [ -f "$fixture/blocked" ]; then
      printf '%s\n' '{"issues":[{"uid":"blocked-item","qualified_id":"blocked-item","status":"open","owner":"another-actor","labels":null}]}'
    else
      printf '%s\n' '{"issues":[]}'
    fi
    ;;
  label)
    [ "$action" = add ] && [ "$#" -eq 3 ] && [ "$3" = --agent ] || exit 95
    printf '%s\n' "$2" >>"$fixture/$1.labels"
    ;;
  comment)
    [ "$#" -eq 4 ] && [ "$2" = --body-file ] && [ "$4" = --agent ] || exit 96
    cp "$3" "$fixture/$1.comment"
    ;;
  *) printf 'unexpected fixture kata command: %s\n' "$verb" >&2; exit 94 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"
# Captured before any Git fixture joins PATH, for the case that fails a single git status.
real_git=$(command -v git)
cat >"$test_root/workflow/complete.dip" <<'DIP'
# ABOUTME: Exercises board child identity, fail-forward handoffs, and artifacts without model nodes.
# ABOUTME: Performs real local commits and records a disposable issue lifecycle.
workflow BoardFixture
  goal: "Exercise real child orchestration"
  start: ClaimNext
  exit: Exit

  tool ClaimNext
    marker_grep: "^(claim-ok|queue-empty)$"
    command_file: claim.sh

  tool Implement
    command_file: implement.sh

  tool CloseSelected
    marker_grep: "^close-ok$"
    command_file: close.sh

  tool Handoff
    command_file: handoff.sh

  tool Exit
    command:
      true

  edges
    ClaimNext -> Implement  on claim-ok
    ClaimNext -> Exit  on queue-empty
    Implement -> CloseSelected  when ctx.outcome = success
    Implement -> Handoff  when ctx.outcome = fail
    CloseSelected -> Exit  when ctx.outcome = success
    Handoff -> Exit
DIP
cat >"$test_root/workflow/claim.sh" <<'SH'
#!/bin/sh
# ABOUTME: Creates the next local fixture task and records its actual child identity.
# ABOUTME: Checks the board's stack-base input against the checked-out Git history.
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
start_branch=$(git branch --show-current)
base_branch=main
# Only verified completions move the stack tip, so a stack base appears after the first closure.
if [ ! -s "$fixture/completed" ]; then
  [ -z "${KATA_STACK_BASE_FILE:-}" ] || {
    printf 'child before any completion unexpectedly received a stack base\n' >&2; exit 31;
  }
else
  [ -n "${KATA_STACK_BASE_FILE:-}" ] || {
    printf 'child after a completion did not receive a stack base\n' >&2; exit 32;
  }
  jq -e --arg base "$base" --arg branch "$start_branch" \
    '.commit == $base and .branch == $branch and .github.repository == "fixture/board"' \
    "$KATA_STACK_BASE_FILE" >/dev/null
  cp "$KATA_STACK_BASE_FILE" "$fixture/stack-$number.json"
  base_branch=$(jq -r '.branch' "$KATA_STACK_BASE_FILE")
fi
branch="kata/item-$number"
git switch -qc "$branch"
printf 'task %s\n' "$number" >"task-$number.txt"
git add "task-$number.txt"
git commit -qm "test: complete fixture task $number"
head=$(git rev-parse HEAD)
jq -n --arg workspace "$TRACKER_WORKDIR" --arg uid "$uid" --arg actor "$actor" --arg branch "$branch" \
  --arg base "$base" --arg start "$start_branch" --arg base_branch "$base_branch" \
  '{workspace:$workspace,issue_uid:$uid,short_id:$uid,qualified_id:("fixture#" + $uid),actor:$actor,
    branch:$branch,base_commit:$base,start_branch:$start,
    github:{remote:"origin",repository:"fixture/board",base_branch:$base_branch}}' \
  >"$TRACKER_RUN_DIR/selected.json"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-correctness.approved"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-scope.approved"
printf 'https://github.com/fixture/board/pull/%s\n' "$number" >"$TRACKER_RUN_DIR/pr-url.txt"
printf 'open\n' >"$fixture/$uid.status"
printf '%s\n' "$actor" >"$fixture/$uid.owner"
printf 'claim-ok\n'
SH
cat >"$test_root/workflow/implement.sh" <<'SH'
#!/bin/sh
# ABOUTME: Stands in for the worker: succeeds unless the fixture lists this attempt as a failure.
# ABOUTME: A failing attempt leaves uncommitted work behind, or wanders off the task branch.
set -eu
cd "$TRACKER_WORKDIR"
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
number=$(wc -l <"$fixture/claims" | tr -d ' ')
if [ -f "$fixture/leave-branch" ] && grep -qx "$number" "$fixture/leave-branch"; then
  # The worker wandered back to the branch it started on, so the handoff touches no Git state.
  start_branch=$(jq -r '.start_branch' "$TRACKER_RUN_DIR/selected.json")
  git switch -q "$start_branch"
  remaining=$(cat "$fixture/remaining")
  printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
  printf 'deliberate fixture worker failure off the task branch\n' >&2
  exit 35
fi
if [ -f "$fixture/fail-implement" ] && grep -qx "$number" "$fixture/fail-implement"; then
  # A kata released behind the pipeline's back: the board must refuse to record the failure.
  [ ! -f "$fixture/lose-owner" ] || rm -f "$fixture/fixture-item-$number.owner"
  printf 'partial work %s\n' "$number" >"wip-$number.txt"
  remaining=$(cat "$fixture/remaining")
  printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
  printf 'deliberate fixture worker failure\n' >&2
  exit 34
fi
SH
cat >"$test_root/workflow/close.sh" <<'SH'
#!/bin/sh
# ABOUTME: Records a fixture closure after optional deliberate failure.
# ABOUTME: Leaves selected state intact so a real Tracker resume can complete it.
set -eu
fixture="$TRACKER_WORKDIR/.tracker/board-fixture"
if [ -f "$fixture/fail-close" ]; then
  printf 'deliberate fixture close failure\n' >&2
  exit 33
fi
uid=$(jq -r '.issue_uid' "$TRACKER_RUN_DIR/selected.json")
printf 'closed\n' >"$fixture/$uid.status"
printf '%s\n' "$uid" >>"$fixture/completed"
remaining=$(cat "$fixture/remaining")
printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
printf 'close-ok\n'
SH
# The handoff under test is the production script. The parent workflow resolves its
# controller and report beside itself, so the nested cases get copies of both.
cp "$pipeline_dir/scripts/handoff-selected.sh" "$test_root/workflow/handoff.sh"
cp "$pipeline_dir/board.dip" "$test_root/workflow/board.dip"
cp "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/scripts/run-board.sh"
cp "$pipeline_dir/board-report" "$test_root/workflow/board-report"
chmod +x "$test_root/workflow/board-report"

# Every assertion names what it expected; the tail of the named log (the controller output by default) follows.
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail_log=${2:-$test_root/output}
  [ ! -f "$fail_log" ] || tail -n 60 "$fail_log" >&2
  exit 1
}

new_case() {
  repo="$test_root/$1 repository"
  git init -q -b main "$repo"
  repo=$(cd "$repo" && pwd -P)
  git -C "$repo" config user.name 'Board integration'
  git -C "$repo" config user.email 'board-check@example.invalid'
  git -C "$repo" config commit.gpgsign false
  printf '.tracker/\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -qm 'test: seed board repository'
  fixture="$repo/.tracker/board-fixture"
  mkdir -p "$fixture"
  printf '%s\n' "$2" >"$fixture/remaining"
  : >"$fixture/claims"
  : >"$fixture/completed"
  export TRACKER_WORKDIR="$repo" TRACKER_RUN_ID=board-parent
  export TRACKER_RUN_DIR="$repo/.tracker/runs/$TRACKER_RUN_ID"
  mkdir -p "$TRACKER_RUN_DIR"
  ledger="$TRACKER_RUN_DIR/board/state.json"
}

run_board() {
  (cd "$repo" && sh "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/complete.dip") \
    >"$test_root/output" 2>&1
}

must_succeed() {
  if ! run_board; then
    printf 'FAIL: board did not complete %s\n' "$1" >&2
    cat "$test_root/output" >&2
    for child_log in "$TRACKER_RUN_DIR"/board/items/*/child.log; do
      [ ! -f "$child_log" ] || tail -n 12 "$child_log" >&2
    done
    for status in "$repo"/.tracker/runs/*/ClaimNext/status.json "$repo"/.tracker/runs/*/Handoff/status.json; do
      [ ! -f "$status" ] || cat "$status" >&2
    done
    exit 1
  fi
}

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

claim_count() {
  wc -l <"$fixture/claims" | tr -d ' '
}

# The controller's last line routes board.dip: a clean board exits, anything else opens the morning review.
expect_marker() {
  last=$(tail -n 1 "$test_root/output")
  [ "$last" = "$1" ] || {
    printf 'FAIL: %s: last controller line is "%s", expected %s\n' "$2" "$last" "$1" >&2
    exit 1
  }
}

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
    .runs[1].github.base_branch == .runs[0].branch' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
[ "$(git -C "$repo" rev-list --count HEAD)" -eq 3 ]
first_commit=$(jq -r '.runs[0].commit' "$ledger")
[ "$(git -C "$repo" rev-parse HEAD^)" = "$first_commit" ]
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null
for slot in 000001 000002 000003; do
  [ -s "$TRACKER_RUN_DIR/board/items/$slot/child.log" ]
done
jq -r '.runs[].run_id' "$ledger" | while IFS= read -r child; do
  [ -f "$repo/.tracker/runs/$child/activity.jsonl" ]
  jq -e '.outcome == "success"' "$repo/.tracker/runs/$child/Exit/status.json" >/dev/null
done
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null
grep -Fx 'Completed (2)' "$test_root/output" >/dev/null
grep -Fx -e '- fixture#fixture-item-2 on kata/item-2' "$test_root/output" >/dev/null
grep -Fx '  https://github.com/fixture/board/pull/2' "$test_root/output" >/dev/null
expect_marker board-clean 'two stacked tasks'
# Re-entering a finished ledger (the morning review's "Sweep again") claims again in the same ledger.
must_succeed 'a finished ledger on re-entry'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","completed","empty","empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 4 ]
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null
expect_marker board-clean 'a finished ledger on re-entry'
printf 'ok - real Tracker children use distinct IDs and stack commits, and a finished ledger sweeps again on re-entry\n'

new_case empty 0
must_succeed 'initially empty board'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 1 ]
grep -F 'list --status open --limit 0 --json' "$fixture/kata.log" >/dev/null
grep -F 'Board complete: 0 katas finished, 0 left open for review.' "$test_root/output" >/dev/null
expect_marker board-clean 'an empty board'
printf 'ok - an empty board requires the full open-issue query\n'

new_case failing 2
printf '1\n' >"$fixture/fail-implement"
must_succeed 'a failed first kata followed by a completed one'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["failed","completed","empty"] and
  .runs[0].issue_uid == "fixture-item-1" and .runs[0].branch == "kata/item-1" and
  .runs[0].reason == "implement" and .runs[0].label == "needs-review" and
  .runs[1].branch == "kata/item-2" and .runs[1].github.base_branch == "main"' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
failed_child=$(head -n 1 "$fixture/claims")
main_commit=$(git -C "$repo" rev-parse main)
wip_commit=$(git -C "$repo" rev-parse kata/item-1)
jq -e --arg child "$failed_child" --arg wip "$wip_commit" \
  '.run_id == $child and .start_branch == "main" and .wip_commit == $wip and
    .reason == "implement" and .question == null' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null
[ "$(git -C "$repo" log -1 --format=%s kata/item-1)" = "wip(kata): fixture#fixture-item-1 handoff from run $failed_child" ]
git -C "$repo" show --stat --format= kata/item-1 | grep -F 'wip-1.txt' >/dev/null
[ "$(git -C "$repo" branch --show-current)" = kata/item-2 ]
[ "$(git -C "$repo" rev-parse kata/item-2^)" = "$main_commit" ]
[ "$(cat "$fixture/fixture-item-1.status")" = open ]
[ "$(cat "$fixture/fixture-item-1.labels")" = needs-review ]
grep -Fx "label add kata-pipeline-$failed_child fixture-item-1 needs-review --agent" "$fixture/kata.log" >/dev/null
grep -F "Branch: kata/item-1 (base $main_commit, wip $wip_commit)" "$fixture/fixture-item-1.comment" >/dev/null
[ ! -e "$fixture/stack-2.json" ]
grep -Fx 'Failed fixture-item-1 (implement); left open with needs-review on kata/item-1' "$test_root/output" >/dev/null
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null
grep -Fx 'Completed (1)' "$test_root/output" >/dev/null
grep -Fx 'Needs review (1)' "$test_root/output" >/dev/null
grep -F -e '- fixture#fixture-item-1: worker stopped (run ' "$test_root/output" >/dev/null
expect_marker board-needs-human 'a handed-off kata'
# The morning review answered the kata; the next sweep reclaims it and finishes it from the stack tip.
printf 'fixture-item-1\n' >"$fixture/reclaim"
printf '1\n' >"$fixture/remaining"
rm "$fixture/fail-implement"
must_succeed 'a second sweep that finishes the handed-off kata'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["failed","completed","empty","completed","empty"] and
  .runs[3].issue_uid == "fixture-item-1" and .runs[3].branch == "kata/item-4" and
  .runs[3].github.base_branch == "kata/item-2"' "$ledger" >/dev/null
[ "$(claim_count)" -eq 5 ]
[ ! -s "$fixture/reclaim" ]
grep -F 'Board complete: 2 katas finished, 0 left open for review.' "$test_root/output" >/dev/null
grep -Fx 'Completed (2)' "$test_root/output" >/dev/null
grep -Fx 'Needs review (0)' "$test_root/output" >/dev/null
[ "$(grep -c 'fixture#fixture-item-1' "$test_root/output")" -eq 1 ]
expect_marker board-clean 'a second sweep that finishes the handed-off kata'
printf 'ok - a clean worker failure is handed off, and the next sweep finishes the answered kata once\n'

new_case stacked-failure 2
printf '2\n' >"$fixture/fail-implement"
must_succeed 'a completed kata followed by a failed one'
jq -e '.finished == true and (has("stop_reason") | not) and
  [.runs[].kind] == ["completed","failed","empty"] and .runs[1].branch == "kata/item-2"' "$ledger" >/dev/null
[ "$(claim_count)" -eq 3 ]
failed_child=$(sed -n '2p' "$fixture/claims")
jq -e '.start_branch == "kata/item-1"' "$repo/.tracker/runs/$failed_child/handoff.json" >/dev/null
first_commit=$(jq -r '.runs[0].commit' "$ledger")
[ "$(git -C "$repo" branch --show-current)" = kata/item-1 ]
[ "$(git -C "$repo" rev-parse HEAD)" = "$first_commit" ]
[ "$(git -C "$repo" rev-parse kata/item-2~2)" = "$first_commit" ]
jq -e --arg commit "$first_commit" '.branch == "kata/item-1" and .commit == $commit' \
  "$fixture/stack-2.json" >/dev/null
grep -F 'Board complete: 1 katas finished, 1 left open for review.' "$test_root/output" >/dev/null
expect_marker board-needs-human 'a failure after a completion'
printf 'ok - a failure after a completion restores the stack tip and keeps the completed base\n'

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

new_case blocked 0
: >"$fixture/blocked"
must_succeed 'a queue with only owned or blocked katas'
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 1 ]
jq -e '.issues[0].uid == "blocked-item"' "$TRACKER_RUN_DIR/board/blocked.json" >/dev/null
grep -F 'Board incomplete: 1 open katas remain, but none were ready and unowned.' "$test_root/output" >/dev/null
grep -Fx 'Remaining open (1)' "$test_root/output" >/dev/null
grep -Fx -e '- blocked-item owned by another-actor' "$test_root/output" >/dev/null
expect_marker board-needs-human 'a blocked queue'
rm "$fixture/blocked"
must_succeed 'a re-entry after the blocked katas closed'
jq -e '.finished == true and [.runs[].kind] == ["empty","empty"]' "$ledger" >/dev/null
[ ! -e "$TRACKER_RUN_DIR/board/blocked.json" ]
expect_marker board-clean 'a re-entry after the blocked katas closed'
printf 'ok - a blocked queue finishes the board and lists the untouched katas until a later sweep finds none\n'

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

# Each guard on a failed child, tripped one at a time against the same real handoff.
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

# A handed-off kata opens the morning-review gate; its answers (sweep again, then done) drive the parent.
new_case nested-gate 1
printf '1\n' >"$fixture/fail-implement"
if ! printf '2\n1\n' | tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-gate.log" 2>&1; then
  printf 'FAIL: real Tracker parent did not complete the morning review\n' >&2
  tail -n 20 "$test_root/parent-gate.log" >&2
  exit 1
fi
gate_fail() {
  printf 'FAIL: nested gate: %s\n' "$1" >&2
  tail -n 30 "$test_root/parent-gate.log" >&2
  exit 1
}
parent_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent-gate.log")
jq -e '.finished == true and (has("stop_reason") | not) and [.runs[].kind] == ["failed","empty","empty"]' \
  "$repo/.tracker/runs/$parent_id/board/state.json" >/dev/null ||
  gate_fail 'the ledger does not show one handoff and two empty sweeps'
[ "$(claim_count)" -eq 3 ] || gate_fail "claim count is $(claim_count), expected 3"
# The gate prints its "Enter choice" prompt without a newline, so the resolution event shares that line.
responses=$(jq -Rnr '[inputs | sub("^[^{]*"; "") | fromjson? | select(.type == "gate_resolved") | .gate_response] | join(",")' \
  <"$test_root/parent-gate.log")
[ "$responses" = 'sweep,done' ] || gate_fail "gate responses are \"$responses\", expected sweep,done"
grep -Fx 'Needs review (1)' "$test_root/parent-gate.log" >/dev/null || gate_fail 'the gate prompt does not show the review'
printf 'ok - real Tracker parent opens the morning review for a handed-off kata and sweeps again on request\n'

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
[ "$responses" = 'done' ] || fail "nested-auto-approve: gate responses are \"$responses\", expected done" "$test_root/parent-auto.log"
[ "$(claim_count)" -eq 2 ] || fail "nested-auto-approve: claim count is $(claim_count), expected 2"
printf 'ok - a real Tracker parent under --auto-approve ends after one sweep\n'
