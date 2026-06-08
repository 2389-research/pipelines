#!/usr/bin/env bats
# test_persist_verdict.bats — covers all 5 Persist*Verdict scripts.
# Builds a fake $(pwd)/.tracker/runs/<rid>/Squad<Persona>/response.md and
# verifies the persister copies the verdict JSON to $RUN_DIR/verdict_<persona>.json.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"

  # Fake tracker workdir under TMPDIR.
  WORKDIR="${TMPDIR}/workdir"
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"
  TRACKER_RID="trk-$$"
  TRACKER_RUN="${WORKDIR}/.tracker/runs/${TRACKER_RID}"
  mkdir -p "${TRACKER_RUN}"

  SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

teardown() {
  rm -rf "${TMPDIR}"
}

stage_response() {
  # $1 = NodeID (e.g. SquadPragmatism), $2 = fixture filename
  mkdir -p "${TRACKER_RUN}/$1"
  cp "${FIXTURES}/$2" "${TRACKER_RUN}/$1/response.md"
}

@test "persist_pragmatism_verdict copies the verdict JSON" {
  stage_response SquadPragmatism verdict_pass.json
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "persisted-pragmatism" ]
  [ -f "${RUN_DIR}/verdict_pragmatism.json" ]
  persona="$(jq -r '.persona' "${RUN_DIR}/verdict_pragmatism.json")"
  [ "${persona}" = "pragmatism" ]
}

@test "persist_yagni_verdict reads SquadYagni's response" {
  stage_response SquadYagni verdict_block.json
  run sh -c "$(cat "${SCRIPTS}/persist_yagni_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "persisted-yagni" ]
  [ "$(jq -r '.verdict' "${RUN_DIR}/verdict_yagni.json")" = "BLOCK" ]
}

@test "persist_blocker_verdict reads SquadBlocker's ATTEST response" {
  stage_response SquadBlocker verdict_attest_valid.json
  run sh -c "$(cat "${SCRIPTS}/persist_blocker_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "persisted-blocker" ]
  attestation_len="$(jq '.attestation | length' "${RUN_DIR}/verdict_blocker.json")"
  [ "${attestation_len}" -ge 3 ]
}

@test "persist_testability_verdict and persist_holistic_verdict work" {
  stage_response SquadTestability verdict_pass.json
  stage_response SquadHolistic    verdict_pass.json
  run sh -c "$(cat "${SCRIPTS}/persist_testability_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "persisted-testability" ]
  run sh -c "$(cat "${SCRIPTS}/persist_holistic_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "persisted-holistic" ]
}

@test "TRACKER_RUN_DIR env var takes precedence over mtime fallback" {
  # Stage TWO tracker run dirs; the older one carries the verdict, the newer
  # one is empty. Without explicit TRACKER_RUN_DIR the mtime heuristic would
  # pick the newer (wrong) dir. Set env to point at the older one and verify
  # the persister reads from there.
  older="${WORKDIR}/.tracker/runs/trk-older"
  newer="${WORKDIR}/.tracker/runs/trk-newer"
  mkdir -p "${older}/SquadPragmatism"
  cp "${FIXTURES}/verdict_pass.json" "${older}/SquadPragmatism/response.md"
  sleep 1
  mkdir -p "${newer}"
  printf 'TRACKER_RUN_DIR=%s\n' "${older}" > "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "persisted-pragmatism" ]
  # Verify it read from the explicitly-pinned older dir, not the mtime-newer one.
  persona="$(jq -r '.persona' "${RUN_DIR}/verdict_pragmatism.json")"
  [ "${persona}" = "pragmatism" ]
}

@test "missing response.md exits non-zero with error file" {
  # No stage_response call -> response.md missing.
  mkdir -p "${TRACKER_RUN}/SquadPragmatism"   # keep tracker_run_dir resolvable
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -ne 0 ]
  grep -q "response missing" "${RUN_DIR}/persist_pragmatism_error.txt"
}

@test "missing tracker run dir exits non-zero" {
  rm -rf "${WORKDIR}/.tracker"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -ne 0 ]
}

@test "missing rid sentinel exits non-zero" {
  rm "${DIP_ROOT}/.current_rid"
  stage_response SquadPragmatism verdict_pass.json
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -ne 0 ]
}
