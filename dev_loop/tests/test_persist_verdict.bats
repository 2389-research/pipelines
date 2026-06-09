#!/usr/bin/env bats
# test_persist_verdict.bats — covers all 5 Persist*Verdict scripts.
# Builds a fake $(pwd)/.tracker/runs/<rid>/Squad<Persona>/response.md and
# verifies the persister copies the verdict JSON to $RUN_DIR/verdict_<persona>.json.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  # stage_run set TRACKER_RUN_DIR; reuse it as the persister's tracker root.
  SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

teardown() {
  rm -rf "${TMPDIR}"
}

stage_response() {
  # $1 = NodeID (e.g. SquadPragmatism), $2 = fixture filename
  mkdir -p "${TRACKER_RUN_DIR}/$1"
  cp "${FIXTURES}/$2" "${TRACKER_RUN_DIR}/$1/response.md"
}

@test "persist_pragmatism_verdict copies the verdict JSON" {
  stage_response SquadPragmatism verdict_pass.json
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-pragmatism" ]
  [ -f "${RUN_DIR}/verdict_pragmatism.json" ]
  persona="$(jq -r '.persona' "${RUN_DIR}/verdict_pragmatism.json")"
  [ "${persona}" = "pragmatism" ]
}

@test "persist_yagni_verdict reads SquadYagni's response" {
  stage_response SquadYagni verdict_block.json
  run sh -c "$(cat "${SCRIPTS}/persist_yagni_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-yagni" ]
  [ "$(jq -r '.verdict' "${RUN_DIR}/verdict_yagni.json")" = "BLOCK" ]
}

@test "persist_blocker_verdict reads SquadBlocker's ATTEST response" {
  stage_response SquadBlocker verdict_attest_valid.json
  run sh -c "$(cat "${SCRIPTS}/persist_blocker_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-blocker" ]
  attestation_len="$(jq '.attestation | length' "${RUN_DIR}/verdict_blocker.json")"
  [ "${attestation_len}" -ge 3 ]
}

@test "persist_testability_verdict and persist_holistic_verdict work" {
  stage_response SquadTestability verdict_pass.json
  stage_response SquadHolistic    verdict_pass.json
  run sh -c "$(cat "${SCRIPTS}/persist_testability_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-testability" ]
  run sh -c "$(cat "${SCRIPTS}/persist_holistic_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-holistic" ]
}

@test "TRACKER_RUN_DIR env var pins exact tracker run dir" {
  # Stage TWO tracker run dirs; the explicitly-pinned one carries the verdict,
  # the other is empty. Setting TRACKER_RUN_DIR in env points the persister at
  # the right dir regardless of mtime.
  older="${WORKDIR}/.tracker/runs/trk-older"
  newer="${WORKDIR}/.tracker/runs/trk-newer"
  mkdir -p "${older}/SquadPragmatism"
  cp "${FIXTURES}/verdict_pass.json" "${older}/SquadPragmatism/response.md"
  mkdir -p "${newer}"
  # Overwrite the env file with TRACKER_RUN_DIR pointing at the older dir.
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
TRACKER_RUN_DIR='${older}'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-pragmatism" ]
  persona="$(jq -r '.persona' "${RUN_DIR}/verdict_pragmatism.json")"
  [ "${persona}" = "pragmatism" ]
}

@test "env file present with missing/invalid TRACKER_RUN_DIR fails closed" {
  # The contract: when setup_run.sh has written an env file, we MUST honor
  # TRACKER_RUN_DIR from it. If it's missing or points at a non-existent dir,
  # fail closed rather than fall back to mtime (which would route to whichever
  # .tracker/runs/ dir is newest — defeating concurrency isolation).
  stage_response SquadPragmatism verdict_pass.json
  # Rewrite env without TRACKER_RUN_DIR.
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -ne 0 ]
}

@test "persist embeds <verdict_*> XML block for the Synthesizer" {
  stage_response SquadPragmatism verdict_block.json
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-pragmatism" ]
  # The verdict JSON must appear inside a <verdict_pragmatism> block so the
  # SquadSynthesizer (immediately downstream of the fan_in) sees it via the
  # merged ctx.last_response. Without this, the synthesizer would only see
  # "persisted-pragmatism" and have no verdict data to fuse.
  printf '%s\n' "${output}" | grep -q -- "<verdict_pragmatism>"
  printf '%s\n' "${output}" | grep -q -- "</verdict_pragmatism>"
  # Sanity: a field from verdict_block.json must be present inside the block.
  printf '%s\n' "${output}" | grep -q -- "BLOCK"
}

@test "missing response.md exits non-zero with error file" {
  # No stage_response call -> response.md missing.
  mkdir -p "${TRACKER_RUN_DIR}/SquadPragmatism"   # keep tracker_run_dir resolvable
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
