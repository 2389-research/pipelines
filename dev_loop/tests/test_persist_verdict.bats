#!/usr/bin/env bats
# test_persist_verdict.bats — covers all 5 Persist*Verdict scripts.
# Builds a fake $(pwd)/.tracker/runs/<rid>/Squad<Persona>/response.md and
# verifies the persister copies the verdict JSON to $RUN_DIR/verdict_<persona>.json.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  # stage_run set DIP_ARTIFACT_DIR; reuse it as the persister's artifact root.
  SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

teardown() {
  rm -rf "${TMPDIR}"
}

stage_response() {
  # $1 = NodeID (e.g. SquadPragmatism), $2 = fixture filename
  mkdir -p "${DIP_ARTIFACT_DIR}/$1"
  cp "${FIXTURES}/$2" "${DIP_ARTIFACT_DIR}/$1/response.md"
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

@test "DIP_ARTIFACT_DIR env var pins exact dip executor artifact dir" {
  # Stage TWO artifact dirs; the explicitly-pinned one carries the verdict,
  # the other is empty. Setting DIP_ARTIFACT_DIR in env points the persister
  # at the right dir regardless of mtime.
  older="${WORKDIR}/.tracker/runs/trk-older"
  newer="${WORKDIR}/.tracker/runs/trk-newer"
  mkdir -p "${older}/SquadPragmatism"
  cp "${FIXTURES}/verdict_pass.json" "${older}/SquadPragmatism/response.md"
  mkdir -p "${newer}"
  # Overwrite the env file with DIP_ARTIFACT_DIR pointing at the older dir.
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
DIP_ARTIFACT_DIR='${older}'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-pragmatism" ]
  persona="$(jq -r '.persona' "${RUN_DIR}/verdict_pragmatism.json")"
  [ "${persona}" = "pragmatism" ]
}

@test "env file present with missing/invalid DIP_ARTIFACT_DIR emits persist-failed" {
  # The contract: when setup_run.sh has written an env file, we MUST honor
  # DIP_ARTIFACT_DIR from it. If it's missing or points at a non-existent dir,
  # emit `persist-failed` (issue #48) so the .dip routes through
  # CleanupWorktree + RatchetLog rather than halting the pipeline. We do NOT
  # fall back to mtime — that would defeat concurrency isolation.
  # #61: the error breadcrumb names DIP_ARTIFACT_DIR (the actionable knob), not
  # the executor's on-disk layout.
  stage_response SquadPragmatism verdict_pass.json
  # Rewrite env without DIP_ARTIFACT_DIR.
  cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
EOF
  chmod 600 "${RUN_DIR}/env"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  grep -q "DIP_ARTIFACT_DIR is unset" "${RUN_DIR}/persist_pragmatism_error.txt"
  ! grep -q "tracker/runs" "${RUN_DIR}/persist_pragmatism_error.txt"
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

@test "missing response.md emits persist-failed (status 0) with error file" {
  # Post-bootstrap exit-1 sites now route through ctx.tool_marker=persist-failed
  # (issue #48) so the .dip can cleanup + ratchet rather than halt mid-flight.
  # No stage_response call -> response.md missing.
  mkdir -p "${DIP_ARTIFACT_DIR}/SquadPragmatism"   # keep dip_artifact_dir resolvable
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  grep -q "response missing" "${RUN_DIR}/persist_pragmatism_error.txt"
}

@test "missing dip artifact dir emits persist-failed (status 0)" {
  rm -rf "${WORKDIR}/.tracker"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
}

@test "malformed response.md emits persist-failed with jq stderr in sidecar" {
  # jq's parse failure on the response is a post-bootstrap failure; emit
  # persist-failed so the .dip routes to CleanupWorktree.
  mkdir -p "${DIP_ARTIFACT_DIR}/SquadPragmatism"
  printf 'this is not valid JSON {{{\n' > "${DIP_ARTIFACT_DIR}/SquadPragmatism/response.md"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  # The sidecar must contain jq's stderr (a parse-error breadcrumb).
  [ -s "${RUN_DIR}/persist_pragmatism_error.txt" ]
}

@test "trap writes fallback sidecar on unexpected exit (#48 review)" {
  # When the script exits non-zero AFTER the success path (e.g., `mv` failing
  # under set -e between jq success and the success printf), the trap fires
  # but no exit-1-path sidecar was written -- ratchet_log would then record
  # outcome=unknown instead of persist-failed. The trap must write a fallback
  # breadcrumb so the ratchet can find it. Mirrors setup_run.sh's EXIT trap.
  stage_response SquadPragmatism verdict_pass.json
  # Stage a fake `mv` that always fails. The atomic-write step
  # (`mv "${target}.tmp" "${target}"`) trips set -e -> trap fires AFTER jq
  # succeeded -- exactly the unexpected-failure window.
  fake_bin="${TMPDIR}/fake_bin"
  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/mv" <<'SH'
#!/bin/sh
exit 1
SH
  chmod +x "${fake_bin}/mv"
  export PATH="${fake_bin}:${PATH}"
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | grep -q "persist-failed"
  [ -s "${RUN_DIR}/persist_pragmatism_error.txt" ]
  grep -q "unexpected non-zero exit" "${RUN_DIR}/persist_pragmatism_error.txt"
}

@test "missing rid sentinel exits non-zero (bootstrap preamble unchanged)" {
  # The bootstrap-preamble exit-1s are deliberately preserved: by the time a
  # persist script runs, setup_run.sh has had its chance to write the
  # emergency env. If env is genuinely missing now, the run state is so
  # corrupted that emitting persist-failed would just defer the failure to
  # CleanupWorktree's own bootstrap (which would re-trip the same missing-env
  # error). test_bootstrap_identical.sh also enforces byte-identical preamble.
  rm "${DIP_ROOT}/.current_rid"
  stage_response SquadPragmatism verdict_pass.json
  run sh -c "$(cat "${SCRIPTS}/persist_pragmatism_verdict.sh")"
  [ "${status}" -ne 0 ]
}
