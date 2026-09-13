#!/bin/sh
# ABOUTME: Exercises closure refusal using real Git history and run evidence files.
# ABOUTME: Stops before kata access, so these tests cannot mutate a real issue.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
repo="$test_root/repo"
run_dir="$repo/.tracker/runs/test"
git init -q -b kata/close "$repo"
git -C "$repo" config user.name 'Pipeline check'
git -C "$repo" config user.email 'pipeline-check@example.invalid'
printf '.tracker/\n' >"$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -qm 'test: seed closure repository'
base=$(git -C "$repo" rev-parse HEAD)
mkdir -p "$run_dir"
jq -n --arg workspace "$repo" --arg base "$base" \
  '{workspace:$workspace,base_commit:$base,branch:"kata/close",issue_uid:"unused",actor:"unused"}' \
  >"$run_dir/selected.json"
reject() {
  if TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$repo" \
    "$pipeline_dir/scripts/close-selected.sh" >"$test_root/output" 2>&1; then
    printf 'FAIL: closure accepted %s\n' "$1" >&2
    exit 1
  fi
  if ! grep -F "$1" "$test_root/output" >/dev/null; then
    printf 'FAIL: wrong refusal for %s\n' "$1" >&2
    cat "$test_root/output" >&2
    exit 1
  fi
}
reject 'no task commit'
printf 'change\n' >"$repo/file"
reject 'working tree is not clean'
git -C "$repo" add file
git -C "$repo" commit -qm 'test: task change'
reject 'verification evidence is missing'
printf 'test command\n' >"$run_dir/verification.txt"
reject 'completion summary is missing'
printf 'Implemented the selected behavior and verified its acceptance checks.\n' >"$run_dir/completion.md"
reject 'does not approve current commit'
printf '%s\n' "$base" >"$run_dir/review-correctness.approved"
reject 'does not approve current commit'
git -C "$repo" switch -qc kata/other
reject 'task branch changed'
git -C "$repo" switch -q kata/close
jq --arg workspace "$test_root" '.workspace = $workspace' \
  "$run_dir/selected.json" >"$test_root/wrong-state"
cp "$run_dir/selected.json" "$test_root/saved-state"
cp "$test_root/wrong-state" "$run_dir/selected.json"
reject 'tracker workspace changed'
cp "$test_root/saved-state" "$run_dir/selected.json"
printf 'ok - closure rejects uncommitted, unverified, stale, or displaced work\n'
