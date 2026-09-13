#!/bin/sh
# ABOUTME: Simulates concrete approval and rejection routes through the Dippin graph.
# ABOUTME: Checks single selection and repair bounds without running commands or models.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
scenario() {
  repairs=$1 closes=$2 handoffs=$3
  shift 3
  dippin simulate "$pipeline_dir/complete.dip" \
    --scenario ClaimNext.tool_marker=claim-ok "$@" >"$test_root/events" 2>"$test_root/summary"
  jq -se --argjson repairs "$repairs" --argjson closes "$closes" --argjson handoffs "$handoffs" '
    [.[] | select(.event == "node_enter") | .node] as $nodes |
    ($nodes | map(select(. == "ClaimNext")) | length) == 1 and
    ($nodes | map(select(. == "Repair")) | length) == $repairs and
    ($nodes | map(select(. == "CloseSelected")) | length) == $closes and
    ($nodes | map(select(. == "Handoff")) | length) == $handoffs
  ' "$test_root/events" >/dev/null
}
scenario 0 1 0
scenario 1 1 0 --scenario CheckApprovals.outcome=fail
scenario 1 0 1 --scenario CheckApprovals.outcome=fail --scenario ReCheckApprovals.outcome=fail
scenario 0 0 1 --scenario Implement.outcome=fail
dippin simulate "$pipeline_dir/complete.dip" --scenario ClaimNext.tool_marker=queue-empty \
  >"$test_root/events" 2>"$test_root/summary"
jq -se '[.[] | select(.event == "node_enter") | .node] == ["ClaimNext", "Exit"]' \
  "$test_root/events" >/dev/null
printf 'ok - simulated success, repair, rejection, worker failure, and empty queue routes\n'
