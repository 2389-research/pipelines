#!/bin/sh
# ABOUTME: Checks that the text tracker expands for each kata DIP contains no expansion it would blank.
# ABOUTME: Tracker inlines command_file and prompt_file text and turns any unknown ${a.b} into an empty string.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
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
  blanked=$(grep -noE '\$\{[^}]*\.[^}]*\}' "$test_root/effective" | grep -vE ':\$\{(ctx|params|graph|inputs)\.' || true)
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
