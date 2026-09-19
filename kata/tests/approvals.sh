#!/bin/sh
# ABOUTME: Tests SHA and workspace approval guards against real Git repositories.
# ABOUTME: Rejects missing, stale, and cross-workspace review records.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
repo="$test_root/repo"
state_dir="$test_root/state"
mkdir -p "$state_dir"
git init -q -b kata/approval "$repo"
git -C "$repo" config user.name 'Pipeline check'
git -C "$repo" config user.email 'pipeline-check@example.invalid'
printf 'initial\n' >"$repo/file"
git -C "$repo" add file
git -C "$repo" commit -qm 'test: seed approval repository'
jq -n --arg workspace "$repo" '{workspace:$workspace}' >"$state_dir/selected.json"
head=$(git -C "$repo" rev-parse HEAD)
check() {
  TRACKER_RUN_DIR="$state_dir" TRACKER_WORKDIR="$repo" "$pipeline_dir/scripts/check-approvals.sh"
}
reject() {
  if check >"$test_root/output" 2>&1; then
    printf 'FAIL: accepted %s\n' "$1" >&2
    exit 1
  fi
}
reject 'missing approvals'
printf '%s\n' "$head" >"$state_dir/review-correctness.approved"
reject 'one approval'
printf 'stale\n' >"$state_dir/review-scope.approved"
reject 'stale approval'
printf '%s\n' "$head" >"$state_dir/review-scope.approved"
check >/dev/null
if TRACKER_RUN_DIR="$state_dir" TRACKER_WORKDIR="$test_root" \
  "$pipeline_dir/scripts/check-approvals.sh" >"$test_root/output" 2>&1; then
  printf 'FAIL: accepted another workspace\n' >&2
  exit 1
fi
printf 'ok - approval guards reject missing, stale, and cross-workspace records\n'
