#!/bin/sh
# ABOUTME: Simulates concrete approval and rejection routes through the Dippin graph.
# ABOUTME: Checks single selection, repair bounds, and the one-time continue without running commands or models.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
scenario() {
  repairs=$1 closes=$2 handoffs=$3 continues=$4
  shift 4
  dippin simulate "$pipeline_dir/complete.dip" \
    --scenario ClaimNext.tool_marker=claim-ok "$@" >"$test_root/events" 2>"$test_root/summary"
  jq -se --argjson repairs "$repairs" --argjson closes "$closes" --argjson handoffs "$handoffs" \
    --argjson continues "$continues" '
    [.[] | select(.event == "node_enter") | .node] as $nodes |
    ($nodes | map(select(. == "ClaimNext")) | length) == 1 and
    ($nodes | map(select(. == "Repair")) | length) == $repairs and
    ($nodes | map(select(. == "CloseSelected")) | length) == $closes and
    ($nodes | map(select(. == "Handoff")) | length) == $handoffs and
    ($nodes | map(select(. == "ContinueImplement")) | length) == $continues
  ' "$test_root/events" >/dev/null
}
scenario 0 1 0 0
scenario 1 1 0 0 --scenario CheckApprovals.outcome=fail
scenario 1 0 1 0 --scenario CheckApprovals.outcome=fail --scenario ReCheckApprovals.outcome=fail
scenario 0 0 1 0 --scenario Implement.outcome=fail
scenario 0 1 1 0 --scenario CloseSelected.outcome=fail
# A steady breach that still ends in success never needs the continue.
scenario 0 1 0 0 --scenario Implement.turn_breach_class=operator_decision
# Simulation cannot grant the continue (its scenarios are sticky), so this covers the exhausted route only;
# tests/continue.sh drives the granted restart through the real tracker.
scenario 0 0 1 1 --scenario Implement.outcome=fail --scenario Implement.turn_breach_class=operator_decision \
  --scenario ContinueImplement.outcome=fail
jq -se '[.[] | select(.event == "node_enter") | .node] == ["ClaimNext", "Implement", "ContinueImplement", "Handoff", "Exit"]' \
  "$test_root/events" >/dev/null
dippin simulate "$pipeline_dir/complete.dip" --scenario ClaimNext.tool_marker=queue-empty \
  >"$test_root/events" 2>"$test_root/summary"
jq -se '[.[] | select(.event == "node_enter") | .node] == ["ClaimNext", "Exit"]' \
  "$test_root/events" >/dev/null
printf 'ok - simulated success, repair, rejection, worker/publication failure, exhausted continue, and empty queue routes\n'
