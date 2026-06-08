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

@test "stale lock with dead holder_pid is reclaimed (not blocked on mtime)" {
  # Stage a lock dir whose holder_pid points at a process that has been dead
  # for a long time. The PID-based liveness check must let the next
  # setup_run reclaim the lock — even though the lock's mtime is fresh
  # (so the mtime fallback would have wrongly rejected). PID 1 (init) is
  # always alive, so we use a guaranteed-dead PID: a fresh `false` subshell.
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  mkdir -p "${DIP_ROOT}/.dev_loop.lock"
  # Spawn a short-lived child and capture its PID after it exits — that PID
  # is guaranteed dead by the time we check it.
  ( exec true ) &
  dead_pid=$!
  wait "${dead_pid}" 2>/dev/null || true
  printf '%s' "${dead_pid}" > "${DIP_ROOT}/.dev_loop.lock/holder_pid"
  printf 'stale-rid' > "${DIP_ROOT}/.dev_loop.lock/rid"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ "${rid}" != "stale-rid" ]
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
  # Stage a PATH that contains the POSIX utilities setup_run.sh needs for its
  # own work (mkdir, cat, date, printf, ls, find, awk, kill, etc.) but
  # deliberately omits the dev_loop-required commands (gh, jq, git, tracker).
  # This is deterministic regardless of where the host installs each tool —
  # the prior `PATH=/usr/bin:/bin` was brittle: those four are commonly in
  # /usr/bin on Linux, so the test only "worked" when at least one happened
  # to be absent.
  sysbin="${TMPDIR}/sysbin-only"
  mkdir -p "${sysbin}"
  for cmd in mkdir cat date printf ls find awk kill chmod rm cp mv tr \
             head sort uniq tail sed grep dash sh true false; do
    src=""
    if [ -x "/bin/${cmd}" ]; then src="/bin/${cmd}"
    elif [ -x "/usr/bin/${cmd}" ]; then src="/usr/bin/${cmd}"
    fi
    [ -n "${src}" ] && ln -sf "${src}" "${sysbin}/${cmd}"
  done

  run env -i HOME="${HOME}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
      PATH="${sysbin}" /bin/sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/2389-research-pipelines/.current_rid")"
  [ -n "${rid}" ]
  grep -q "missing required commands" \
    "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/setup_error.txt"
}
