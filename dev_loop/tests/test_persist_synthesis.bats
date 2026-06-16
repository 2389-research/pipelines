#!/usr/bin/env bats
# test_persist_synthesis.bats — covers synthesized-approved | _changes_requested | _abandoned
# routing markers + synthesis.json / feedback.json persistence.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  mkdir -p "${DIP_ARTIFACT_DIR}/SquadSynthesizer"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_synthesis.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

teardown() {
  rm -rf "${TMPDIR}"
}

stage() {
  cp "${FIXTURES}/$1" "${DIP_ARTIFACT_DIR}/SquadSynthesizer/response.md"
}

@test "approved synthesis emits synthesized-approved" {
  stage synthesis_approved.json
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "synthesized-approved" ]
  [ -f "${RUN_DIR}/synthesis.json" ]
  [ -f "${RUN_DIR}/feedback.json" ]
  feedback_count="$(jq 'length' "${RUN_DIR}/feedback.json")"
  [ "${feedback_count}" -eq 0 ]
}

@test "changes_requested synthesis emits synthesized-changes_requested + non-empty feedback" {
  stage synthesis_changes_requested.json
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "synthesized-changes_requested" ]
  [ -f "${RUN_DIR}/feedback.json" ]
  feedback_count="$(jq 'length' "${RUN_DIR}/feedback.json")"
  [ "${feedback_count}" -ge 1 ]
}

@test "missing response.md falls back to synthesized-abandoned + exit 0" {
  rm -f "${DIP_ARTIFACT_DIR}/SquadSynthesizer/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  # Routing tools MUST exit 0 even on the fallback path. A non-zero exit can
  # bypass marker_grep routing in the .dip and halt the pipeline mid-flight.
  [ "${status}" -eq 0 ]
  [ "${output}" = "synthesized-abandoned" ]
  [ -f "${RUN_DIR}/persist_synthesis_error.txt" ]
}

@test "missing DIP_ARTIFACT_DIR also trips the trap (synthesized-abandoned)" {
  # Issue #48 parity: every post-bootstrap exit-1 site in persist_synthesis.sh
  # must trip the EXIT trap and emit synthesized-abandoned. Wipe the entire
  # .tracker tree so DIP_ARTIFACT_DIR (set by stage_run) points at a now-gone
  # directory.
  rm -rf "${WORKDIR}/.tracker"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "synthesized-abandoned" ]
}

@test "unset DIP_ARTIFACT_DIR writes fail_class=unset (#90)" {
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ -f "${RUN_DIR}/persist_synthesis_fail_class.txt" ]
  [ "$(cat "${RUN_DIR}/persist_synthesis_fail_class.txt")" = "unset" ]
}

@test "stale DIP_ARTIFACT_DIR writes fail_class=stale (#90)" {
  stale="${WORKDIR}/.tracker/runs/trk-was-here-yesterday"
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
DIP_ARTIFACT_DIR='${stale}'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ -f "${RUN_DIR}/persist_synthesis_fail_class.txt" ]
  [ "$(cat "${RUN_DIR}/persist_synthesis_fail_class.txt")" = "stale" ]
}

@test "missing response writes fail_class=response-missing (#90)" {
  rm -f "${DIP_ARTIFACT_DIR}/SquadSynthesizer/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ -f "${RUN_DIR}/persist_synthesis_fail_class.txt" ]
  [ "$(cat "${RUN_DIR}/persist_synthesis_fail_class.txt")" = "response-missing" ]
}

@test "jq parse failure writes fail_class=jq-parse (#90)" {
  printf 'not valid json {{{\n' > "${DIP_ARTIFACT_DIR}/SquadSynthesizer/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ -f "${RUN_DIR}/persist_synthesis_fail_class.txt" ]
  [ "$(cat "${RUN_DIR}/persist_synthesis_fail_class.txt")" = "jq-parse" ]
}

@test "missing rid sentinel exits non-zero" {
  # The canonical bootstrap fails closed before the trap installs that would
  # otherwise emit synthesized-abandoned. Missing rid means setup_run did not
  # run; the pipeline should not have routed here.
  rm "${DIP_ROOT}/.current_rid"
  stage synthesis_approved.json
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
}
