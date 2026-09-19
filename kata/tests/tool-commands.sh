#!/bin/sh
# ABOUTME: Checks that the text tracker expands for each kata DIP contains no expansion it would blank.
# ABOUTME: Tracker inlines command_file and prompt_file text and turns any unknown ${a.b} into an empty string.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Tracker expands ${namespace.key} in tool commands and prompts. Its namespaces are ctx, params,
# graph, and inputs; any other dotted ${...} becomes an empty string with no warning, so a shell
# script inlined through command_file loses every ${var#pattern.with.dots} it contains.
for dip in "$pipeline_dir"/*.dip; do
  dip_dir=$(dirname "$dip")
  name=$(basename "$dip")
  cat "$dip" >"$test_root/effective"
  sed -nE 's/^[[:space:]]*(command_file|prompt_file|system_prompt_file):[[:space:]]*//p' "$dip" >"$test_root/inlined"
  while IFS= read -r file; do
    [ -f "$dip_dir/$file" ] || fail "$name names a missing file $file"
    cat "$dip_dir/$file" >>"$test_root/effective"
  done <"$test_root/inlined"
  # grep exits 1 when nothing matches and 2 on a bad pattern or an unreadable file; only the first is a clean scan.
  status=0
  grep -noE '\$\{[^}]*\.[^}]*\}' "$test_root/effective" >"$test_root/expansions" || status=$?
  [ "$status" -le 1 ] || fail "scanning $name for expansions failed with status $status"
  status=0
  blanked=$(grep -vE ':\$\{(ctx|params|graph|inputs)\.' "$test_root/expansions") || status=$?
  [ "$status" -le 1 ] || fail "filtering the expansions of $name failed with status $status"
  [ -z "$blanked" ] || fail "$name feeds tracker text it would blank (line:expansion):
$blanked"
done
printf 'ok - no kata DIP feeds tracker an expansion it would blank\n'

# A script run by path never meets the expander, but the path must exist relative to the DIP.
for dip in "$pipeline_dir"/*.dip; do
  dip_dir=$(dirname "$dip")
  grep -oE '\$\{graph\.workflow_dir\}/[^"[:space:]]+' "$dip" | sed -E 's|^\$\{graph\.workflow_dir\}/||' >"$test_root/run-by-path"
  while IFS= read -r file; do
    [ -f "$dip_dir/$file" ] || fail "$(basename "$dip") runs a missing file $file"
  done <"$test_root/run-by-path"
done
printf 'ok - every workflow_dir path a kata DIP runs exists\n'
