#!/bin/sh
# ABOUTME: Exercises the real tracker pipeline's dirty-tree guard without model calls.
# ABOUTME: Creates a disposable Git repository and checks that no agent stage runs.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
repo="$test_root/repo"
git init -q -b kata/preflight "$repo"
git -C "$repo" config user.name 'Pipeline check'
git -C "$repo" config user.email 'pipeline-check@example.invalid'
printf '.tracker/\n' >"$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -qm 'test: seed preflight repository'
printf 'preserve this work\n' >"$repo/uncommitted.txt"
if tracker --git off --workdir "$repo" --artifact-dir "$test_root/artifacts" --json --no-tui \
  "$pipeline_dir/complete.dip" >"$test_root/run.log" 2>&1; then
  printf 'FAIL: tracker accepted a dirty target repository\n' >&2
  cat "$test_root/run.log" >&2
  exit 1
fi
set -- "$test_root"/artifacts/*/ClaimNext/status.json
if [ "$#" -ne 1 ] || [ ! -f "$1" ] || ! jq -e \
  '.outcome == "fail" and (.context_updates.tool_stderr | contains("working tree is not clean"))' \
  "$1" >/dev/null; then
  printf 'FAIL: tracker stopped before exercising the dirty-tree guard\n' >&2
  cat "$test_root/run.log" >&2
  exit 1
fi
for agent_prompt in "$test_root"/artifacts/*/Implement/prompt.md; do
  if [ -f "$agent_prompt" ]; then
    printf 'FAIL: tracker entered an agent stage after failed preflight\n' >&2
    exit 1
  fi
done
[ "$(cat "$repo/uncommitted.txt")" = 'preserve this work' ]
[ "$(git -C "$repo" rev-list --count HEAD)" = 1 ]
printf 'ok - real tracker rejects dirty work before selection or model execution\n'
