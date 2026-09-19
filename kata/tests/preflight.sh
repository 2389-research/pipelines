#!/bin/sh
# ABOUTME: Exercises the real tracker pipeline's dirty-tree guard without model calls.
# ABOUTME: Creates a disposable Git repository and checks that no agent stage runs.
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
git init -q -b main "$repo"
git -C "$repo" config user.name 'Pipeline check'
git -C "$repo" config user.email 'pipeline-check@example.invalid'
printf 'Fixture repository\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm 'test: seed preflight repository'
printf 'preserve this work\n' >"$repo/uncommitted.txt"
printf '.kata.local.toml\n' >"$repo/.gitignore"
printf 'version = 1\n' >"$repo/.kata.toml"
if tracker --git off --workdir "$repo" --artifact-dir "$test_root/artifacts" --json --no-tui \
  "$pipeline_dir/complete.dip" >"$test_root/run.log" 2>&1; then
  printf 'FAIL: tracker accepted a dirty target repository\n' >&2
  cat "$test_root/run.log" >&2
  exit 1
fi
set -- "$test_root"/artifacts/*/ClaimNext/status.json
if [ "$#" -ne 1 ] || [ ! -f "$1" ] || ! jq -e \
  '.outcome == "fail" and (.context_updates.tool_stderr |
    contains("working tree is not clean") and contains("uncommitted.txt") and
    contains(".gitignore") and contains(".kata.toml"))' \
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
for stop_status in "$test_root"/artifacts/*/Stop/status.json; do
  if [ -f "$stop_status" ]; then
    printf 'FAIL: generic Stop node replaced the preflight failure\n' >&2
    exit 1
  fi
done
[ "$(cat "$repo/uncommitted.txt")" = 'preserve this work' ]
[ "$(git -C "$repo" rev-list --count HEAD)" = 1 ]
[ "$(git -C "$repo" branch --show-current)" = main ]
git -C "$repo" check-ignore -q .tracker/
printf 'ok - real tracker rejects dirty work before selection or model execution\n'
