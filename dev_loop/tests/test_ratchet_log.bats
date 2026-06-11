#!/usr/bin/env bats
# test_ratchet_log.bats

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/ratchet_log.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "first run writes header + one record" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'fix/42-x' > "${RUN_DIR}/branch_name.txt"
  printf '2' > "${RUN_DIR}/iter.txt"
  printf '{"outcome":"approved"}' > "${RUN_DIR}/synthesis.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ratcheted" ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  [ -f "${RATCHET}" ]
  [ "$(awk 'NR==1' "${RATCHET}")" = "rid	ts	issue	branch	outcome	iters_used	notes" ]
  line2="$(awk 'NR==2' "${RATCHET}")"
  echo "${line2}" | grep -q "42"
  echo "${line2}" | grep -q "approved"
}

@test "ratchet picks up merge-blocked outcome" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'fix/42-x' > "${RUN_DIR}/branch_name.txt"
  printf 'protected' > "${RUN_DIR}/merge_block_reason.txt"
  run sh -c "$(cat "${SCRIPT}")"
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "merge-blocked-protected" "${RATCHET}"
}

@test "ratchet writes 'unknown' when no synthesis exists" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  run sh -c "$(cat "${SCRIPT}")"
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "unknown" "${RATCHET}"
}

@test "ratchet sanitizes tab/newline control chars in note fields (TSV contract)" {
  # gates_error.txt commonly contains the raw output of dippin check /
  # tracker validate, which may include tabs and newlines. Untouched, those
  # bytes would shift downstream columns and corrupt the TSV. The ratchet
  # must replace them with spaces.
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'fix/42-x' > "${RUN_DIR}/branch_name.txt"
  # Tab + newline + carriage return inside the gates error.
  printf 'dippin\tcheck\tfailed\nat\tline 3\r\n' > "${RUN_DIR}/gates_error.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "ratcheted" ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  # Exactly two lines should be present: header + one record. Any extra
  # newlines from gates_error.txt leaking into the row would push this
  # higher.
  [ "$(wc -l < "${RATCHET}")" = "2" ]
  # Every data row must have exactly 7 tab-separated fields.
  awk -F '\t' 'NR>1 && NF != 7 {fail=1} END {exit fail}' "${RATCHET}"
}

@test "persist_*_error.txt → outcome=persist-failed in ratchet (#48)" {
  # When any persist_*.sh script trips its post-bootstrap failure path it
  # writes $RUN_DIR/persist_<flavor>_error.txt and emits ctx.tool_marker=
  # persist-failed (routed to CleanupWorktree -> RatchetLog by the .dip).
  # The ratchet must surface the failure class so post-mortems can find it.
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'fix/42-x' > "${RUN_DIR}/branch_name.txt"
  printf 'response missing at /tmp/x\n' > "${RUN_DIR}/persist_pragmatism_error.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ratcheted" ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "persist-failed" "${RATCHET}"
}

@test "synthesis sidecar alone does NOT misclassify as persist-failed (#48 review)" {
  # persist_synthesis.sh writes persist_synthesis_error.txt at every failure
  # site but emits ctx.tool_marker=synthesized-abandoned, NOT persist-failed.
  # The .dip routes synthesized-abandoned via the synth_abandoned cleanup
  # edge with that intent. The ratchet's persist_*_error.txt detection must
  # NOT swallow synthesis-abandoned runs into outcome=persist-failed; that
  # mismatches the marker the workflow actually emitted.
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'fix/42-x' > "${RUN_DIR}/branch_name.txt"
  printf 'response missing\n' > "${RUN_DIR}/persist_synthesis_error.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ratcheted" ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  ! grep -q "persist-failed" "${RATCHET}"
}

@test "setup-failed wins when both setup_error.txt and persist_*_error.txt exist" {
  # Defense in depth: a setup failure is more upstream than a persist failure,
  # so the ratchet's outcome label should resolve to setup-failed when both
  # files are present. (Shouldn't happen in practice — setup_run's own failure
  # path halts before any persist node fires — but order matters in the
  # elif-chain.)
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'setup hit a brick wall\n' > "${RUN_DIR}/setup_error.txt"
  printf 'response missing\n'       > "${RUN_DIR}/persist_blocker_error.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "setup-failed" "${RATCHET}"
  ! grep -q "persist-failed" "${RATCHET}"
}

@test "persist-failed → cleanup_worktree → ratchet_log completes (#48 end-to-end)" {
  # End-to-end proof for #48: a missing tracker artifact during a persist
  # node must trip the EXIT trap (emit persist-failed, exit 0) so the .dip
  # can route through CleanupWorktree -> RatchetLog -> Exit. Without the
  # trap the persist script would exit 1 and halt the pipeline mid-flight.
  PERSIST="${BATS_TEST_DIRNAME}/../scripts/persist_pragmatism_verdict.sh"
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  # Wipe .tracker so DIP_ARTIFACT_DIR (set by stage_run) points at a now-gone
  # dir — the script's first post-bootstrap check fails -> trap fires.
  rm -rf "${WORKDIR}/.tracker"
  run sh -c "$(cat "${PERSIST}")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  [ -f "${RUN_DIR}/persist_pragmatism_error.txt" ]
  # Follow persist-failed -> CleanupWorktree edge.
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
  # Follow CleanupWorktree -> RatchetLog edge.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ratcheted" ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "persist-failed" "${RATCHET}"
}

@test "setup-failed → cleanup_worktree → ratchet_log completes (#52 end-to-end)" {
  # End-to-end proof that the full failure-routing chain in dev_loop.dip
  # progresses: setup-failed → CleanupWorktree → RatchetLog → Exit. Each
  # downstream's bootstrap preamble requires $RUN_DIR/env; emit_failure
  # must have written it.
  SETUP="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  # Wipe the stage_run-staged rid/env so we observe ONLY what setup_run's
  # failure path produces.
  rm -rf "${DIP_ROOT}/runs" "${DIP_ROOT}/.current_rid"
  mkdir -p "${DIP_ROOT}/runs"
  # No GH_REPO env, no YAML → "no repo configured" emit_failure path.
  run sh -c "$(cat "${SETUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Follow setup-failed → CleanupWorktree edge.
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
  # Follow CleanupWorktree → RatchetLog edge.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ratcheted" ]
  # The ratchet must record a row for this failed run with outcome=setup-failed.
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  [ -f "${RATCHET}" ]
  grep -q "setup-failed" "${RATCHET}"
}

@test "missing .current_rid exits non-zero (canonical bootstrap contract)" {
  # Today's pipeline contract: cleanup_worktree intentionally KEEPS
  # .current_rid so ratchet_log can find run_dir (see test_worktree.bats
  # "cleanup_worktree retains .current_rid"). This test simulates the
  # degraded case where .current_rid is missing anyway (e.g. an operator
  # manually nuked $DIP_ROOT) and asserts the bootstrap fails-closed
  # rather than silently writing to the wrong place.
  rm "${DIP_ROOT}/.current_rid"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
}
