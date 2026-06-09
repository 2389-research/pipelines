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
