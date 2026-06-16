#!/usr/bin/env bats
# test_ratchet_log_persist_class.bats — pins ratchet_log's read of the
# persist_<flavor>_fail_class.txt sidecar (#90). Each persist_*.sh script
# writes a structured failure class before exit 1; ratchet_log surfaces it
# as outcome=persist-failed-<class> so post-mortems can distinguish failure
# modes at the marker layer without grepping individual error sidecars.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/ratchet_log.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "persist_plan_fail_class=jq-parse surfaces as persist-failed-jq-parse" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'fix/42-x' > "${RUN_DIR}/branch_name.txt"
  printf 'jq: parse error\n' > "${RUN_DIR}/persist_plan_error.txt"
  printf 'jq-parse' > "${RUN_DIR}/persist_plan_fail_class.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ratcheted" ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "persist-failed-jq-parse" "${RATCHET}"
}

@test "persist_selected_fail_class=unset surfaces as persist-failed-unset" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'response missing\n' > "${RUN_DIR}/persist_selected_error.txt"
  printf 'unset' > "${RUN_DIR}/persist_selected_fail_class.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "persist-failed-unset" "${RATCHET}"
}

@test "persist_pragmatism_fail_class=stale surfaces as persist-failed-stale" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'stale\n' > "${RUN_DIR}/persist_pragmatism_error.txt"
  printf 'stale' > "${RUN_DIR}/persist_pragmatism_fail_class.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "persist-failed-stale" "${RATCHET}"
}

@test "persist_plan_fail_class=validation surfaces as persist-failed-validation" {
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'branch_name null\n' > "${RUN_DIR}/persist_plan_error.txt"
  printf 'validation' > "${RUN_DIR}/persist_plan_fail_class.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -q "persist-failed-validation" "${RATCHET}"
}

@test "missing fail_class sidecar falls back to bare persist-failed" {
  # Older runs / partial cleanup: persist_*_error.txt present but no
  # fail_class sidecar. ratchet must still record persist-failed so we
  # don't lose the failure entirely.
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'response missing\n' > "${RUN_DIR}/persist_blocker_error.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  grep -qE 'persist-failed($|[^-])' "${RATCHET}"
}

@test "stale fail_class from another flavor does not leak into outcome" {
  # If partial cleanup or operator edits leave a stale persist_X_fail_class.txt
  # from an earlier run alongside a fresh persist_Y_error.txt, the outcome must
  # reflect the flavor that actually tripped THIS run's branch — never the
  # leftover flavor's class. ratchet must pair the fail_class to the same
  # flavor's error.txt, not glob fail_class files blindly.
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  # Stale class from a previous selected run (no error.txt for selected).
  printf 'validation' > "${RUN_DIR}/persist_selected_fail_class.txt"
  # Fresh error from blocker — no fresh fail_class sidecar (e.g. crash before
  # the write, or the sidecar got lost to partial cleanup).
  printf 'response missing\n' > "${RUN_DIR}/persist_blocker_error.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  # Must NOT pick up the stale `validation` class from selected.
  ! grep -q "persist-failed-validation" "${RATCHET}"
  # Falls back to bare persist-failed because blocker has no fresh sidecar.
  grep -qE 'persist-failed($|[^-])' "${RATCHET}"
}

@test "synthesis fail_class sidecar alone does NOT misclassify as persist-failed" {
  # persist_synthesis.sh emits synthesized-abandoned, NOT persist-failed.
  # If only the synthesis sidecar exists, ratchet must NOT swallow the run
  # into outcome=persist-failed-<class>; that mismatches the marker the
  # workflow actually emitted (mirrors the existing synthesis exclusion in
  # the persist-failed elif chain).
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"
  printf 'response missing\n' > "${RUN_DIR}/persist_synthesis_error.txt"
  printf 'response-missing' > "${RUN_DIR}/persist_synthesis_fail_class.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  RATCHET="${DIP_ROOT}/ratchet.tsv"
  ! grep -q "persist-failed" "${RATCHET}"
}
