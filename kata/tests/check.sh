#!/bin/sh
# ABOUTME: Checks the one-kata workflow graph and its real shell guards.
# ABOUTME: Runs each case in an isolated temporary Git repository.
set -eu

KATA_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$*"; }
assert_contains() { printf '%s' "$1" | grep -F -- "$2" >/dev/null || fail "expected [$2] in [$1]"; }

test_graph_contract() {
  graph=$KATA_DIR/complete.dip
  [ -f "$graph" ] || fail 'complete.dip is missing'
  grep -F 'parallel ReviewFreshEyes -> ReviewCorrectness, ReviewScope' "$graph" >/dev/null || fail 'two-reviewer fan-out missing'
  [ "$(grep -c 'fan_in_policy: all' "$graph")" -eq 4 ] || fail 'strict review fan-in policy missing'
  awk '
    /^  agent / { agent = $2; agents[agent] = 1; next }
    /^  [^ ]/ { agent = "" }
    agent && $1 == "provider:" { providers[agent] = $2 }
    agent && $1 == "model:" { models[agent] = $2; distinct[$2] = 1 }
    agent && $1 == "max_turns:" { limits[agent] = $2 }
    END {
      for (name in agents) {
        count++
        expected = name ~ /Scope$/ ? "deepseek-4.1-flash" : "glm-5.3"
        if (providers[name] != "openai-compat" || models[name] != expected) exit 1
        expected_limit = name == "Implement" ? 300 : (name == "Repair" ? 150 : 100)
        if (limits[name] != expected_limit) {
          printf "%s must allow %d turns (found %s)\n", name, expected_limit, limits[name] > "/dev/stderr"
          exit 1
        }
      }
      for (model in distinct) model_count++
      if (count != 6 || model_count != 2) exit 1
    }
  ' "$graph" || fail 'all six agents must use the configured Lunaroute models, provider, and turn limits'
  grep -F 'Repair -> ReReviewFreshEyes' "$graph" >/dev/null || fail 'single repair path missing'
  [ "$(grep -c '^  agent Repair$' "$graph")" -eq 1 ] || fail 'repair must be a single bounded node'
  pass 'graph bounds selection, repair, and two-model review'
}

new_repo() {
  repo=$1
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name tester
  : >"$repo/.seed"
  printf '.fake-kata-log\n' >"$repo/.gitignore"
  git -C "$repo" add .seed .gitignore
  git -C "$repo" commit -qm init
  printf 'keep-me' >"$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)"
}

run_preflight() {
  repo=$1
  shift
  mkdir -p "$TMP_ROOT/test-bin"
  ln -sf "$KATA_DIR/tests/fake-kata.sh" "$TMP_ROOT/test-bin/kata"
  mkdir -p "$repo/.tracker/runs/test"
  (cd "$repo" && PATH="$TMP_ROOT/test-bin:$PATH" TRACKER_RUN_DIR="$repo/.tracker/runs/test" TRACKER_RUN_ID="${TEST_RUN_ID:-test}" TRACKER_WORKDIR="$repo" sh -c "$(cat "$KATA_DIR/scripts/claim-next.sh")" sh "$@") 2>&1
}

test_claim_and_persist() {
  repo=$TMP_ROOT/claim
  new_repo "$repo"
  repo=$(cd "$repo" && pwd -P)
  output=$(FAKE_KATA_MODE=ready run_preflight "$repo")
  assert_contains "$output" 'claim-ok'
  [ "$(git -C "$repo" branch --show-current)" = 'kata/5fav-test' ] || fail 'ready item did not create its deterministic task branch'
  git -C "$repo" check-ignore -q .tracker/runs/test || fail 'runtime directory was not added to the local Git exclude'
  [ "$(cat "$repo/.gitignore")" = '.fake-kata-log' ] || fail 'source ignore file changed'
  grep -Fx '/.tracker/' "$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)" >/dev/null || fail 'root-anchored local exclude is missing'
  grep -Fx 'keep-me' "$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)" >/dev/null || fail 'existing local exclude entry changed'
  jq -e --arg repo "$repo" '.issue_uid == "01ARZ3NDEKTSV4RRFFQ69G5FAV" and .short_id == "5fav" and .qualified_id == "demo#5fav" and .workspace == $repo' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'selected identity was not persisted'
  grep -F -- '--if-unowned 01ARZ3NDEKTSV4RRFFQ69G5FAV --json' "$repo/.fake-kata-log" >/dev/null || fail 'claim did not use full immutable identity'
  pass 'ready item is claimed once and its identity is persisted'
}

test_empty_queue_is_noop() {
  repo=$TMP_ROOT/empty
  new_repo "$repo"
  output=$(FAKE_KATA_MODE=empty run_preflight "$repo")
  assert_contains "$output" 'queue-empty'
  [ "$(git -C "$repo" branch --show-current)" = 'main' ] || fail 'empty queue changed branch'
  [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail 'empty queue persisted a selection'
  pass 'empty queue is a clean no-op'
}

test_claim_conflict_stops() {
  repo=$TMP_ROOT/conflict
  new_repo "$repo"
  if output=$(FAKE_KATA_MODE=conflict run_preflight "$repo"); then fail 'claim conflict succeeded'; fi
  assert_contains "$output" 'claim failed'
  [ "$(git -C "$repo" branch --show-current)" = main ] || fail 'claim conflict left a task branch checked out'
  [ "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads | wc -l | tr -d ' ')" = 1 ] || fail 'claim conflict created a branch'
  [ "$(grep -c '^ready ' "$repo/.fake-kata-log")" -eq 1 ] || fail 'claim conflict selected again'
  [ "$(grep -c '^claim ' "$repo/.fake-kata-log")" -eq 1 ] || fail 'claim conflict attempted another claim'
  [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail 'claim conflict persisted a selection'
  pass 'claim conflict stops without reselection'
}

test_unsafe_run_id_stops_before_branch_or_claim() {
  repo=$TMP_ROOT/unsafe-run-id
  new_repo "$repo"
  if output=$(TEST_RUN_ID='../unsafe' FAKE_KATA_MODE=ready run_preflight "$repo"); then fail 'unsafe run ID succeeded'; fi
  assert_contains "$output" 'TRACKER_RUN_ID is unsafe'
  [ "$(git -C "$repo" branch --show-current)" = 'main' ] || fail 'unsafe run ID changed branch'
  [ "$(wc -l <"$repo/.fake-kata-log" | tr -d ' ')" -eq 1 ] || fail 'unsafe run ID reached claim'
  pass 'unsafe branch identifiers stop before branch creation or claim'
}

test_existing_selection_stops_without_reselection() {
  repo=$TMP_ROOT/existing
  new_repo "$repo"
  mkdir -p "$repo/.tracker/runs/test"
  printf '{}\n' >"$repo/.tracker/runs/test/selected.json"
  exclude=$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)
  before=$(cat "$exclude")
  if output=$(FAKE_KATA_MODE=ready run_preflight "$repo"); then fail 'existing selection succeeded'; fi
  assert_contains "$output" 'selection already exists'
  [ "$(cat "$exclude")" = "$before" ] || fail 'existing selection mutated local excludes'
  [ ! -e "$repo/.fake-kata-log" ] || fail 'existing selection called kata'
  pass 'existing run selection cannot select a second item'
}

test_dirty_work_and_existing_branch() {
  repo=$TMP_ROOT/dirty
  new_repo "$repo"
  : >"$repo/.kata.toml"
  : >"$repo/.gitignore.local"
  : >"$repo/uncommitted.txt"
  if output=$(FAKE_KATA_MODE=ready run_preflight "$repo"); then fail 'dirty tree succeeded'; fi
  assert_contains "$output" 'working tree is not clean'
  assert_contains "$output" '.kata.toml'
  assert_contains "$output" '.gitignore.local'
  assert_contains "$output" 'uncommitted.txt'
  assert_contains "$output" 'commit, stash, or remove'
  [ "$(git -C "$repo" branch --show-current)" = 'main' ] || fail 'dirty preflight changed branch'
  git -C "$repo" check-ignore -q .tracker/runs/test || fail 'dirty preflight did not exclude tracker artifacts'
  [ ! -e "$repo/.fake-kata-log" ] || fail 'dirty tree called kata'

  repo=$TMP_ROOT/existing-branch
  new_repo "$repo"
  git -C "$repo" switch -qc feat/already-here
  output=$(FAKE_KATA_MODE=ready run_preflight "$repo")
  assert_contains "$output" 'claim-ok'
  [ "$(git -C "$repo" branch --show-current)" = 'feat/already-here' ] || fail 'existing task branch changed'
  pass 'preflight reports all dirty paths and preserves an existing task branch'
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

test_parent_selection() {
  repo=$TMP_ROOT/parent-selection
  new_repo "$repo"
  response='{"issues":[{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAA","short_id":"5faa","qualified_id":"demo#5faa","priority":0,"child_counts":{"open":2,"total":2}},{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","short_id":"5fav","qualified_id":"demo#5fav","priority":2}]}'
  output=$(FAKE_READY_JSON="$response" run_preflight "$repo") || fail "$output"
  assert_contains "$output" 'claim-ok'
  jq -e '.issue_uid == "01ARZ3NDEKTSV4RRFFQ69G5FAV"' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail 'claimed higher-priority parent instead of ready leaf'
  [ "$(grep -c '^claim ' "$repo/.fake-kata-log")" -eq 1 ] || fail 'selection claimed more than once'
  assert_contains "$(cat "$repo/.fake-kata-log")" '--unowned --limit 0 --json'
  pass 'parent with open children is skipped before claiming a ready leaf'
}

test_ineligible_or_malformed_queue() {
  for case_name in parents malformed-count negative-count fractional-count missing-count invalid-envelope empty-response multiple-responses malformed-json malformed-priority; do
    repo=$TMP_ROOT/$case_name
    new_repo "$repo"
    case "$case_name" in
      parents) response='{"issues":[{"priority":0,"child_counts":{"open":1,"total":1}}]}' ;;
      malformed-count) response='{"issues":[{"child_counts":{"open":"1","total":1}}]}' ;;
      negative-count) response='{"issues":[{"child_counts":{"open":-1,"total":1}}]}' ;;
      fractional-count) response='{"issues":[{"child_counts":{"open":0.5,"total":1}}]}' ;;
      missing-count) response='{"issues":[{"child_counts":{"total":1}}]}' ;;
      invalid-envelope) response='{"issue":null}' ;;
      empty-response) response='' ;;
      multiple-responses) response='{"issues":[]} {"issues":[]}' ;;
      malformed-json) response='{"issues":[' ;;
      malformed-priority) response='{"issues":[{"priority":"0"}]}' ;;
    esac
    if output=$(FAKE_READY_JSON="$response" run_preflight "$repo"); then
      [ "$case_name" = parents ] || fail "$case_name succeeded"
      assert_contains "$output" 'queue-empty'
    else
      [ "$case_name" != parents ] || fail 'parents-only queue failed'
      assert_contains "$output" 'invalid response'
    fi
    [ "$(git -C "$repo" branch --show-current)" = main ] || fail "$case_name changed branch"
    [ ! -e "$repo/.tracker/runs/test/selected.json" ] || fail "$case_name persisted selection"
    [ "$(wc -l <"$repo/.fake-kata-log" | tr -d ' ')" -eq 1 ] || fail "$case_name attempted a claim"
  done
  pass 'parents-only queue is a no-op and malformed queues stop before claiming'
}

test_selection_priority_contract() {
  for selection_case in zero null ties closed; do
    repo=$TMP_ROOT/priority-$selection_case
    new_repo "$repo"
    case "$selection_case" in
      zero) rows='[{"short_id":"5faa"},{"short_id":"5fab","priority":1},{"short_id":"5fav","priority":0}]' ;;
      null) rows='[{"short_id":"5fav"},{"short_id":"5faa","priority":null}]' ;;
      ties) rows='[{"short_id":"5fav","priority":2},{"short_id":"5faa","priority":2}]' ;;
      closed) rows='[{"short_id":"5fav","priority":1,"child_counts":{"open":0,"total":2}},{"short_id":"5faa","priority":2}]' ;;
    esac
    response=$(printf '%s' "$rows" | jq '{issues:map(. + {uid:("01ARZ3NDEKTSV4RRFFQ69G" + (.short_id | ascii_upcase)),qualified_id:("demo#" + .short_id)})}')
    output=$(FAKE_READY_JSON="$response" run_preflight "$repo") || fail "$output"
    assert_contains "$output" 'claim-ok'
    jq -e '.short_id == "5fav"' "$repo/.tracker/runs/test/selected.json" >/dev/null || fail "$selection_case selection disagrees with kata next"
  done
  pass 'selection keeps canonical priority, unprioritized order, ties, and closed-child parents'
}

test_parent_selection
test_ineligible_or_malformed_queue
test_selection_priority_contract
test_graph_contract
test_claim_and_persist
test_empty_queue_is_noop
test_claim_conflict_stops
test_unsafe_run_id_stops_before_branch_or_claim
test_existing_selection_stops_without_reselection
test_dirty_work_and_existing_branch
test_approvals_bind_current_commit_and_workspace
printf 'all kata checks passed\n'
