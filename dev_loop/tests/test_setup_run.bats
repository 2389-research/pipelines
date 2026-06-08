#!/usr/bin/env bats
# test_setup_run.bats — covers setup-ok, setup-resume-required, setup-failed.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "first run emits setup-ok and seeds .current_rid" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  [ -f "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ -n "${rid}" ]
  [ -f "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/env" ]
  grep -q "^GH_REPO=2389-research/pipelines$" \
    "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/env"
}

@test "second run with no worktree allocates a fresh rid" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid_a="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  # Sleep 1s so the timestamp-based rid differs.
  sleep 1
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_b="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ "${rid_a}" != "${rid_b}" ]
}

@test "prior worktree triggers setup-resume-required" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  mkdir -p "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/worktree"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-resume-required" ]
}

@test "missing tools route to setup-failed" {
  # Strip $PATH down so gh/jq/git/tracker aren't found.
  run env -i HOME="${HOME}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" PATH=/usr/bin:/bin sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ -n "${rid}" ]
  grep -q "missing required commands" \
    "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/setup_error.txt"
}
