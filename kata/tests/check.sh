#!/bin/sh
# ABOUTME: Checks the one-kata workflow graph and its real shell guards.
# ABOUTME: Runs each case in an isolated temporary Git repository.
set -eu

KATA_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$*"; }
assert_contains() { printf '%s' "$1" | grep -F "$2" >/dev/null || fail "expected [$2] in [$1]"; }

test_graph_contract() {
  graph=$KATA_DIR/complete.dip
  [ -f "$graph" ] || fail 'complete.dip is missing'
  grep -F 'parallel ReviewFreshEyes -> ReviewCorrectness, ReviewScope' "$graph" >/dev/null || fail 'two-reviewer fan-out missing'
  [ "$(grep -c 'fan_in_policy: all' "$graph")" -eq 4 ] || fail 'strict review fan-in policy missing'
  grep -F 'model: claude-sonnet-4-6' "$graph" >/dev/null || fail 'Claude reviewer missing'
  grep -F 'model: gpt-5.4' "$graph" >/dev/null || fail 'GPT reviewer missing'
  grep -F 'Repair -> ReReviewFreshEyes' "$graph" >/dev/null || fail 'single repair path missing'
  [ "$(grep -c '^  agent Repair$' "$graph")" -eq 1 ] || fail 'repair must be a single bounded node'
  pass 'graph bounds selection, repair, and two-model review'
}

new_repo() {
  repo=$1
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name tester
  : >"$repo/.seed"
  printf '.tracker/\n.fake-kata-log\n' >"$repo/.gitignore"
  git -C "$repo" add .seed .gitignore
  git -C "$repo" commit -qm init
  git -C "$repo" switch -qc feat/test
}

run_preflight() {
  repo=$1
  shift
  mkdir -p "$TMP_ROOT/test-bin"
  ln -sf "$KATA_DIR/tests/fake-kata.sh" "$TMP_ROOT/test-bin/kata"
  mkdir -p "$repo/.tracker/runs/test"
  (cd "$repo" && PATH="$TMP_ROOT/test-bin:$PATH" TRACKER_RUN_DIR="$repo/.tracker/runs/test" TRACKER_RUN_ID=test TRACKER_WORKDIR="$repo" "$KATA_DIR/scripts/claim-next.sh" "$@") 2>&1
}

test_claim_and_persist() {
  repo=$TMP_ROOT/claim
  new_repo "$repo"
  repo=$(cd "$repo" && pwd -P)
  output=$(FAKE_KATA_MODE=ready run_preflight "$repo")
  assert_contains "$output" 'claim-ok'
  jq -e --arg repo "$repo" '.issue_uid == "01ARZ3NDEKTSV4RRFFQ69G5FAV" and .short_id == "5fav" and .qualified_id == "demo#5fav" and .workspace == $repo' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'selected identity was not persisted'
  [ "$(sed -n '1p' "$repo/.fake-kata-log")" = 'claim 01ARZ3NDEKTSV4RRFFQ69G5FAV' ] || fail 'claim did not use full immutable identity'
  pass 'ready item is claimed once and its identity is persisted'
}

test_empty_queue_is_noop() {
  repo=$TMP_ROOT/empty
  new_repo "$repo"
  output=$(FAKE_KATA_MODE=empty run_preflight "$repo")
  assert_contains "$output" 'queue-empty'
  [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail 'empty queue persisted a selection'
  pass 'empty queue is a clean no-op'
}

test_claim_conflict_stops() {
  repo=$TMP_ROOT/conflict
  new_repo "$repo"
  if output=$(FAKE_KATA_MODE=conflict run_preflight "$repo"); then fail 'claim conflict succeeded'; fi
  assert_contains "$output" 'claim failed'
  [ "$(grep -c '^next$' "$repo/.fake-kata-log")" -eq 1 ] || fail 'claim conflict selected again'
  [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail 'claim conflict persisted a selection'
  pass 'claim conflict stops without reselection'
}

test_existing_selection_stops_without_reselection() {
  repo=$TMP_ROOT/existing
  new_repo "$repo"
  mkdir -p "$repo/.tracker/runs/test"
  printf '{}\n' >"$repo/.tracker/runs/test/selected.json"
  if output=$(FAKE_KATA_MODE=ready run_preflight "$repo"); then fail 'existing selection succeeded'; fi
  assert_contains "$output" 'selection already exists'
  [ ! -e "$repo/.fake-kata-log" ] || fail 'existing selection called kata'
  pass 'existing run selection cannot select a second item'
}

test_dirty_or_default_branch_stops_before_kata() {
  repo=$TMP_ROOT/dirty
  new_repo "$repo"
  : >"$repo/dirty"
  if output=$(FAKE_KATA_MODE=ready run_preflight "$repo"); then fail 'dirty tree succeeded'; fi
  assert_contains "$output" 'working tree is not clean'
  [ ! -e "$repo/.fake-kata-log" ] || fail 'dirty tree called kata'

  repo=$TMP_ROOT/main
  new_repo "$repo"
  git -C "$repo" switch -q main
  if output=$(FAKE_KATA_MODE=ready run_preflight "$repo"); then fail 'default branch succeeded'; fi
  assert_contains "$output" 'refusing default branch'
  [ ! -e "$repo/.fake-kata-log" ] || fail 'default branch called kata'
  pass 'real Git guards stop dirty and default-branch workspaces'
}

test_approvals_bind_current_commit_and_workspace() {
  repo=$TMP_ROOT/approvals
  new_repo "$repo"
  run_dir=$repo/.tracker/runs/test
  mkdir -p "$run_dir"
  jq -n --arg workspace "$repo" '{workspace:$workspace}' >"$run_dir/selected.json"
  head=$(git -C "$repo" rev-parse HEAD)
  printf '%s\n' "$head" >"$run_dir/review-correctness.approved"
  printf '%s\n' stale >"$run_dir/review-scope.approved"
  if output=$(cd "$repo" && TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$repo" "$KATA_DIR/scripts/check-approvals.sh" 2>&1); then fail 'stale approval succeeded'; fi
  assert_contains "$output" 'approval-missing-or-stale'
  printf '%s\n' "$head" >"$run_dir/review-scope.approved"
  output=$(cd "$repo" && TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$repo" "$KATA_DIR/scripts/check-approvals.sh")
  assert_contains "$output" 'approvals-ok'
  if output=$(cd "$repo" && TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$TMP_ROOT" "$KATA_DIR/scripts/check-approvals.sh" 2>&1); then fail 'wrong workspace succeeded'; fi
  assert_contains "$output" 'tracker workspace changed'
  pass 'approval guard binds both attestations to HEAD and workspace'
}

test_graph_contract
test_claim_and_persist
test_empty_queue_is_noop
test_claim_conflict_stops
test_existing_selection_stops_without_reselection
test_dirty_or_default_branch_stops_before_kata
test_approvals_bind_current_commit_and_workspace
printf 'all kata checks passed\n'
