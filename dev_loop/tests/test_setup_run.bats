#!/usr/bin/env bats
# test_setup_run.bats — covers setup-ok, setup-resume-required, setup-failed.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  # Move into a fresh workdir + stage a .tracker/runs/<runID>/ dir to mimic
  # tracker's normal startup. setup_run.sh now requires this to be present.
  WORKDIR="${TMPDIR}/workdir"
  mkdir -p "${WORKDIR}/.tracker/runs/trk-$$"
  cd "${WORKDIR}"
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

@test "second run after cleanup allocates a fresh rid" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid_a="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  # Mimic the pipeline reaching CleanupWorktree (releases the concurrency
  # lock + .current_rid). Then a second invocation starts fresh.
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  sh -c "$(cat "${CLEANUP}")" > /dev/null
  sleep 1
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_b="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ "${rid_a}" != "${rid_b}" ]
}

@test "concurrent setup_run (lock held) rejects the second invocation" {
  # First setup_run claims the lock and exits successfully; the lock dir
  # remains because cleanup_worktree has not run yet (this is the very
  # early-phase window the lock exists to protect).
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_a="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ -d "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.dev_loop.lock" ]
  # A second setup_run starting in this window must fail closed and leave
  # rid_a as the active rid so the first run can keep going.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid_after="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ "${rid_after}" = "${rid_a}" ]
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

@test "missing .tracker/runs (no tracker artifact dir) routes to setup-failed" {
  # Without staged .tracker/runs/<id>/, tracker_run_dir resolves empty.
  # setup_run.sh must catch this and emit setup-failed with a clear message —
  # NOT write an env file with TRACKER_RUN_DIR unset and emit setup-ok (which
  # would later trip every persist_*.sh's env-present-but-TRACKER_RUN_DIR-
  # missing fail-closed gate).
  rm -rf "${WORKDIR}/.tracker"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  grep -q "no tracker run dir" \
    "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/setup_error.txt"
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
