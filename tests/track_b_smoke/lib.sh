# ABOUTME: Shared assertion helpers for Track B smoke tests (issue #19).
# ABOUTME: POSIX sh. Sourced by smoke.sh and exercised by test_lib.bats.

# track_b_run_dir <workdir> -- echo the latest tracker run dir under <workdir>/.tracker/runs/.
# Track B runs are smoke runs; we always want the most-recent run for the assertions
# below. Fails (exit 1) if no run dir exists.
track_b_run_dir() {
  workdir=$1
  runs_root=${workdir}/.tracker/runs
  if [ ! -d "$runs_root" ]; then
    printf 'no-tracker-runs: %s\n' "$runs_root" >&2
    return 1
  fi
  # Newest real (non-symlink) run dir by mtime. `find -type d` filters out
  # symlinks-to-dirs (defense-in-depth for the operator-extension flow where
  # the caller may point us at a runs/ they did not create). `-exec ls -1dt`
  # lets us sort by mtime portably (BSD find lacks `-printf`).
  # shellcheck disable=SC2012
  latest=$(find "${runs_root}" -mindepth 1 -maxdepth 1 -type d -exec ls -1dt {} + 2>/dev/null | head -1)
  if [ -z "$latest" ]; then
    printf 'no-run-subdir: %s\n' "$runs_root" >&2
    return 1
  fi
  # Strip any trailing slash for downstream path joining.
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
  # `grep -q` for presence; capture count only on the FAIL branch.
  if grep -q '^TOOL CALL:' "$resp"; then
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
  # Match the JSON object shape tracker emits. Both alternations:
  # - escape ERE metacharacters in node_id so operator-supplied IDs like
  #   "Exit.Default" don't regex-match unrelated nodes;
  # - use `[^{]*` (not `.*`) between the two fields so we never cross a
  #   nested-object boundary — this stops a sibling node's tool_call_start
  #   from false-matching when its payload happens to contain a nested
  #   `"node_id":"<converted>"` substring.
  esc=$(printf '%s' "${node_id}" | sed 's/[][\\.*+?(){}|^$]/\\&/g')
  pat="\"type\":\"tool_call_start\"[^{]*\"node_id\":\"${esc}\""
  alt="\"node_id\":\"${esc}\"[^{]*\"type\":\"tool_call_start\""
  if grep -qE -e "$pat" -e "$alt" "$act"; then
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
  # Same escape + `[^{]*` discipline as the tool-event check above: keep the
  # match top-level and tolerant of field-ordering.
  esc=$(printf '%s' "${node_id}" | sed 's/[][\\.*+?(){}|^$]/\\&/g')
  pat="\"type\":\"stage_started\"[^{]*\"node_id\":\"${esc}\""
  alt="\"node_id\":\"${esc}\"[^{]*\"type\":\"stage_started\""
  if ! grep -qE -e "$pat" -e "$alt" "$act"; then
    printf 'FAIL: node %s never started in %s\n' "$node_id" "$act" >&2
    return 1
  fi
  return 0
}
