#!/bin/sh
# ABOUTME: Checks board orchestration with real Tracker child runs and disposable Git repositories.
# ABOUTME: Uses a local Kata CLI fixture; never claims real issues or contacts model providers.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
[ -f "$pipeline_dir/scripts/run-board.sh" ] || {
  printf 'FAIL: board controller is missing\n' >&2
  exit 1
}

test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/bin" "$test_root/workflow"
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Supplies only read-only board records from a disposable repository.
# ABOUTME: Rejects unexpected commands so no real Kata daemon can be contacted.
set -eu
verb=$1
shift
[ "$1" = --workspace ] || exit 91
workspace=$2
shift 2
fixture="$workspace/.tracker/board-fixture"
printf '%s %s\n' "$verb" "$*" >>"$fixture/kata.log"
case "$verb" in
  show)
    [ "$#" -eq 2 ] && [ "$2" = --json ] || exit 92
    jq -n --arg uid "$1" --arg status "$(cat "$fixture/$1.status")" \
      '{issue:{uid:$uid,status:$status}}'
    ;;
  list)
    [ "$*" = '--status open --limit 0 --json' ] || exit 93
    if [ -f "$fixture/blocked" ]; then
      printf '%s\n' '{"issues":[{"uid":"blocked-item","status":"open","owner":"another-actor"}]}'
    else
      printf '%s\n' '{"issues":[]}'
    fi
    ;;
  *) printf 'unexpected fixture kata command: %s\n' "$verb" >&2; exit 94 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"
cat >"$test_root/workflow/complete.dip" <<'DIP'
# ABOUTME: Exercises board child identity and artifacts without model nodes.
# ABOUTME: Performs real local commits and records a disposable issue lifecycle.
workflow BoardFixture
  goal: "Exercise real child orchestration"
  start: ClaimNext
  exit: Exit

  tool ClaimNext
    marker_grep: "^(claim-ok|queue-empty)$"
    command_file: claim.sh

  tool CloseSelected
    marker_grep: "^close-ok$"
    command_file: close.sh

  tool Exit
    command:
      true

  edges
    ClaimNext -> CloseSelected  on claim-ok
    ClaimNext -> Exit  on queue-empty
    CloseSelected -> Exit  when ctx.outcome = success
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
uid="fixture-item-$number"
base=$(git rev-parse HEAD)
base_branch=main
if [ "$number" -eq 1 ]; then
  [ -z "${KATA_STACK_BASE_FILE:-}" ] || {
    printf 'first child unexpectedly received a stack base\n' >&2; exit 31;
  }
else
  [ -n "${KATA_STACK_BASE_FILE:-}" ] || {
    printf 'later child did not receive a stack base\n' >&2; exit 32;
  }
  jq -e --arg base "$base" --arg branch "$(git branch --show-current)" \
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
jq -n --arg workspace "$TRACKER_WORKDIR" --arg uid "$uid" --arg branch "$branch" \
  --arg base "$base" --arg base_branch "$base_branch" \
  '{workspace:$workspace,issue_uid:$uid,branch:$branch,base_commit:$base,
    github:{remote:"origin",repository:"fixture/board",base_branch:$base_branch}}' \
  >"$TRACKER_RUN_DIR/selected.json"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-correctness.approved"
printf '%s\n' "$head" >"$TRACKER_RUN_DIR/review-scope.approved"
printf 'https://github.com/fixture/board/pull/%s\n' "$number" >"$TRACKER_RUN_DIR/pr-url.txt"
printf 'open\n' >"$fixture/$uid.status"
printf 'claim-ok\n'
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
remaining=$(cat "$fixture/remaining")
printf '%s\n' "$((remaining - 1))" >"$fixture/remaining"
printf 'close-ok\n'
SH

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
    for status in "$repo"/.tracker/runs/*/ClaimNext/status.json; do
      [ ! -f "$status" ] || cat "$status" >&2
    done
    exit 1
  fi
}

must_stop() {
  if run_board; then
    printf 'FAIL: board accepted %s\n' "$1" >&2
    exit 1
  fi
}

claim_count() {
  wc -l <"$fixture/claims" | tr -d ' '
}

# Integration coverage: Tracker and Git are real; the Kata read boundary is a fixture.
new_case stacked 2
must_succeed 'two stacked tasks'
jq -e --arg workspace "$repo" --arg pipeline "$test_root/workflow/complete.dip" \
  '.workspace == $workspace and .pipeline == $pipeline and .finished == true and
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
cp "$ledger" "$test_root/completed-ledger.json"
must_succeed 'already-finished parent resume'
cmp "$ledger" "$test_root/completed-ledger.json"
[ "$(claim_count)" -eq 3 ]
printf 'ok - real Tracker children use distinct IDs and stack commits without duplicate parent resume\n'

new_case empty 0
must_succeed 'initially empty board'
jq -e '.finished == true and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 1 ]
grep -F 'list --status open --limit 0 --json' "$fixture/kata.log" >/dev/null
printf 'ok - an empty board requires the full open-issue query\n'

new_case blocked 0
: >"$fixture/blocked"
must_stop 'open owned or blocked issues'
jq -e '.finished == false and [.runs[].kind] == ["empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 1 ]
rm "$fixture/blocked"
must_succeed 'board unblocked before parent resume'
jq -e '.finished == true and [.runs[].kind] == ["empty","empty"]' "$ledger" >/dev/null
[ "$(claim_count)" -eq 2 ]
printf 'ok - a blocked board stops and can query again on parent resume\n'

new_case recovery 1
: >"$fixture/fail-close"
must_stop 'failed child'
[ "$(claim_count)" -eq 1 ]
jq -e '.finished == false and .runs == []' "$ledger" >/dev/null
failed_child=$(head -n 1 "$fixture/claims")
jq -e '.outcome == "fail"' "$repo/.tracker/runs/$failed_child/CloseSelected/status.json" >/dev/null
must_stop 'unrecovered child on parent resume'
[ "$(claim_count)" -eq 1 ]
rm "$fixture/fail-close"
if ! tracker --git off --workdir "$repo" --json --no-tui --resume "$failed_child" \
  "$test_root/workflow/complete.dip" >"$test_root/recovery.log" 2>&1; then
  printf 'FAIL: real Tracker child resume failed\n' >&2
  cat "$test_root/recovery.log" >&2
  exit 1
fi
[ "$(claim_count)" -eq 1 ]
child_dir="$repo/.tracker/runs/$failed_child"
cp "$child_dir/review-scope.approved" "$test_root/scope.approved"
printf 'stale approval\n' >"$child_dir/review-scope.approved"
must_stop 'stale approval after child recovery'
cp "$test_root/scope.approved" "$child_dir/review-scope.approved"
printf 'unfinished work\n' >"$repo/uncommitted.txt"
must_stop 'dirty tree after child recovery'
rm "$repo/uncommitted.txt"
git -C "$repo" switch -q main
must_stop 'changed branch after child recovery'
git -C "$repo" switch -q kata/item-1
printf 'open\n' >"$fixture/fixture-item-1.status"
must_stop 'unclosed issue after child recovery'
printf 'closed\n' >"$fixture/fixture-item-1.status"
cp "$child_dir/CloseSelected/status.json" "$test_root/close-status.json"
jq '.context_updates.tool_marker="claim-ok"' "$test_root/close-status.json" \
  >"$child_dir/CloseSelected/status.json"
must_stop 'missing closure marker after child recovery'
cp "$test_root/close-status.json" "$child_dir/CloseSelected/status.json"
[ "$(claim_count)" -eq 1 ]
must_succeed 'manually recovered child'
jq -e --arg child "$failed_child" \
  '.finished == true and [.runs[].kind] == ["completed","empty"] and
    .runs[0].run_id == $child' "$ledger" >/dev/null
[ "$(claim_count)" -eq 2 ]
[ "$(git -C "$repo" rev-list --count HEAD)" -eq 2 ]
must_succeed 'completed recovered parent resume'
[ "$(claim_count)" -eq 2 ]
printf 'ok - failure stops claims; a real child resume reconciles once without duplicate work\n'

# Invoke the actual parent workflow so nested tool environments and failure routing are real.
mkdir -p "$test_root/workflow/scripts"
cp "$pipeline_dir/board.dip" "$test_root/workflow/board.dip"
cp "$pipeline_dir/scripts/run-board.sh" "$test_root/workflow/scripts/run-board.sh"
new_case nested 1
if ! tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent.log" 2>&1; then
  printf 'FAIL: real Tracker parent did not complete its child workflow\n' >&2
  tail -n 20 "$test_root/parent.log" >&2
  exit 1
fi
parent_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started")][0].run_id' \
  <"$test_root/parent.log")
parent_ledger="$repo/.tracker/runs/$parent_id/board/state.json"
jq -e --arg parent "$parent_id" '.finished == true and
  [.runs[].kind] == ["completed","empty"] and all(.runs[]; .run_id != $parent)' "$parent_ledger" >/dev/null
[ "$(claim_count)" -eq 2 ]
new_case nested-failure 0
: >"$fixture/blocked"
if tracker --git off --workdir "$repo" --json --no-tui "$test_root/workflow/board.dip" \
  >"$test_root/parent-failure.log" 2>&1; then
  printf 'FAIL: real Tracker parent hid an incomplete board failure\n' >&2
  tail -n 20 "$test_root/parent-failure.log" >&2
  exit 1
fi
[ "$(claim_count)" -eq 1 ]
printf 'ok - real Tracker parent isolates child identity and reports an incomplete board as failure\n'
