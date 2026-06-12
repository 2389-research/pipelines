# ABOUTME: Shared assertion helpers for Track B smoke tests (issue #19).
# ABOUTME: POSIX sh. Sourced by smoke.sh and exercised by test_lib.bats.

# track_b_run_dir <workdir> -- echo the latest tracker run dir under <workdir>/.tracker/runs/.
# Track B runs are smoke runs; we always want the most-recent run for the assertions
# below. Fails (exit 1) if no run dir exists.
track_b_run_dir() {
  workdir=$1
  runs_root=${workdir}/.tracker/runs
  if [ ! -d "$runs_root" ]; then
    printf 'no-tracker-runs\n' >&2
    return 1
  fi
  # Newest run dir by mtime. tracker run IDs are 12-char hex so glob-safe;
  # `ls -1dt` is the most portable cross-platform sort-by-mtime (BSD `find`
  # lacks `-printf`, GNU `stat` lacks `-f`). shellcheck SC2012 noted but
  # accepted for this constrained input shape.
  # shellcheck disable=SC2012
  latest=$(ls -1dt "${runs_root}"/*/ 2>/dev/null | head -1)
  if [ -z "$latest" ]; then
    printf 'no-run-subdir\n' >&2
    return 1
  fi
  # Strip the trailing slash for downstream path joining.
  printf '%s' "${latest%/}"
}

# track_b_assert_response_exists <run_dir> <node_id> -- exit 0 iff
# <run_dir>/<node_id>/response.md exists and is non-empty.
track_b_assert_response_exists() {
  run_dir=$1
  node_id=$2
  resp=${run_dir}/${node_id}/response.md
  if [ ! -s "$resp" ]; then
    printf 'FAIL: %s missing or empty\n' "$resp" >&2
    return 1
  fi
  return 0
}

# track_b_assert_no_tool_calls_in_response <run_dir> <node_id> -- exit 0 iff
# the agent's response.md contains zero `TOOL CALL:` markers. tracker writes
# this exact prefix to response.md for every tool invocation the agent
# performed (see tracker/agent transcript layout). For a `tool_access: none`
# agent there must be zero.
track_b_assert_no_tool_calls_in_response() {
  run_dir=$1
  node_id=$2
  resp=${run_dir}/${node_id}/response.md
  if [ ! -f "$resp" ]; then
    printf 'FAIL: %s missing\n' "$resp" >&2
    return 1
  fi
  # `grep -c` exit 0 when matches > 0; we want the inverse.
  if grep -c '^TOOL CALL:' "$resp" >/dev/null 2>&1; then
    count=$(grep -c '^TOOL CALL:' "$resp" 2>/dev/null || printf '0')
    printf 'FAIL: %s contains %s TOOL CALL line(s); expected 0 under tool_access: none\n' \
      "$resp" "$count" >&2
    return 1
  fi
  return 0
}

# track_b_assert_no_tool_events_in_activity <run_dir> <node_id> -- exit 0 iff
# activity.jsonl has zero `tool_call_start` events for <node_id>. This is the
# stricter check: even if the LLM emitted a tool call that tracker dropped,
# `tool_call_start` fires only when tracker actually dispatched it. Under
# `tool_access: none` the dispatch must not fire.
track_b_assert_no_tool_events_in_activity() {
  run_dir=$1
  node_id=$2
  act=${run_dir}/activity.jsonl
  if [ ! -f "$act" ]; then
    printf 'FAIL: %s missing\n' "$act" >&2
    return 1
  fi
  # Match the JSON object shape tracker emits — both fields anchored to avoid
  # an accidental substring match in a different node's tool result.
  pat="\"type\":\"tool_call_start\".*\"node_id\":\"${node_id}\""
  alt="\"node_id\":\"${node_id}\".*\"type\":\"tool_call_start\""
  if grep -E -e "$pat" -e "$alt" "$act" >/dev/null 2>&1; then
    n=$(grep -cE -e "$pat" -e "$alt" "$act" 2>/dev/null || printf '0')
    printf 'FAIL: %s has %s tool_call_start event(s) on node %s under tool_access: none\n' \
      "$act" "$n" "$node_id" >&2
    return 1
  fi
  return 0
}

# track_b_assert_node_reached <run_dir> <node_id> -- exit 0 iff activity.jsonl
# shows the node was executed (a `stage_started` event with node_id). This
# catches the case where a pipeline error skipped the converted agent
# entirely (in which case the no-tool-calls check would vacuously pass).
track_b_assert_node_reached() {
  run_dir=$1
  node_id=$2
  act=${run_dir}/activity.jsonl
  if [ ! -f "$act" ]; then
    printf 'FAIL: %s missing\n' "$act" >&2
    return 1
  fi
  pat="\"type\":\"stage_started\".*\"node_id\":\"${node_id}\""
  alt="\"node_id\":\"${node_id}\".*\"type\":\"stage_started\""
  if ! grep -E -e "$pat" -e "$alt" "$act" >/dev/null 2>&1; then
    printf 'FAIL: node %s never started in %s\n' "$node_id" "$act" >&2
    return 1
  fi
  return 0
}
