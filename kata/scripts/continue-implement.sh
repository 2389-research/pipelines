#!/bin/sh
# ABOUTME: Grants Implement one warm continue after a steady-progress turn-limit breach.
# ABOUTME: Writes the tracker turn override once per run and reports exhaustion on the second call.
set -eu

: "${TRACKER_RUN_DIR:?TRACKER_RUN_DIR is required}"
: "${TRACKER_WORKDIR:?TRACKER_WORKDIR is required}"
command -v jq >/dev/null
# Both values are turn counts. The base must match Implement's max_turns in complete.dip;
# tracker honors an override only when it exceeds that base and stays at or under 1000.
implement_max_turns=300
continue_turns=150
marker="$TRACKER_RUN_DIR/continue-implement.json"
if [ -e "$marker" ]; then
  printf 'continue-exhausted\n'
  exit 1
fi
workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
override_dir="$workspace/.tracker/turn_overrides"
mkdir -p "$override_dir"
max_turns=$((implement_max_turns + continue_turns))
printf '%s\n' "$max_turns" >"$override_dir/Implement.tmp"
mv "$override_dir/Implement.tmp" "$override_dir/Implement"
jq -n --argjson max "$max_turns" --arg run "${TRACKER_RUN_ID:-unknown}" \
  '{attempt:1,max_turns:$max,run_id:$run}' >"$marker.tmp"
mv "$marker.tmp" "$marker"
printf 'continue-ok\n'
