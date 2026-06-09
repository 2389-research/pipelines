#!/usr/bin/env bats
# test_setup_run.bats — covers setup-ok, setup-resume-required, setup-failed.

setup() {
  load 'test_helpers'
  setup_env
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "first run emits setup-ok and seeds .current_rid (from YAML)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  [ -f "${DIP_ROOT}/.current_rid" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -n "${rid}" ]
  [ -f "${DIP_ROOT}/runs/${rid}/env" ]
  grep -q "^GH_REPO='fixture-org/fixture-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=fixture-org/fixture-repo (source=yaml)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "second run after cleanup allocates a fresh rid" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid_a="$(cat "${DIP_ROOT}/.current_rid")"
  # Mimic the pipeline reaching CleanupWorktree (releases the concurrency
  # lock). .current_rid persists; the next setup_run overwrites it atomically.
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
  sh -c "$(cat "${CLEANUP}")" > /dev/null
  sleep 1
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_b="$(cat "${DIP_ROOT}/.current_rid")"
  [ "${rid_a}" != "${rid_b}" ]
}

@test "concurrent setup_run (lock held) rejects the second invocation" {
  # First setup_run claims the lock and exits successfully; the lock dir
  # remains because cleanup_worktree has not run yet (this is the very
  # early-phase window the lock exists to protect).
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid_a="$(cat "${DIP_ROOT}/.current_rid")"
  LOCK_DIR="${DIP_ROOT}/.dev_loop.lock"
  [ -d "${LOCK_DIR}" ]
  # bats's `run` uses a transient subshell, so the PID setup_run.sh wrote to
  # holder_pid (its $PPID, which IS that subshell) has already exited by now.
  # To model a real concurrent invocation — where tracker is still running —
  # overwrite holder_pid with the bats main process's PID, which IS guaranteed
  # alive for the duration of this test.
  printf '%s' "$$" > "${LOCK_DIR}/holder_pid"

  # A second setup_run starting in this window must fail closed and leave
  # rid_a as the active rid so the first run can keep going.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid_after="$(cat "${DIP_ROOT}/.current_rid")"
  [ "${rid_after}" = "${rid_a}" ]
}

@test "prior worktree triggers setup-resume-required" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  mkdir -p "${DIP_ROOT}/runs/${rid}/worktree"
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
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
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
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -q "no tracker run dir" "${run_dir%/}/setup_error.txt"
}

@test "missing tools route to setup-failed" {
  # Stage a PATH that contains the POSIX utilities setup_run.sh needs for its
  # own work (mkdir, cat, date, printf, ls, find, awk, kill, etc.) but
  # deliberately omits the dev_loop-required commands (gh, jq, git, tracker, yq).
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
      DEV_LOOP_STATE_ROOT="${DEV_LOOP_STATE_ROOT}" \
      PATH="${sysbin}" /bin/sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -q "missing required commands" "${run_dir%/}/setup_error.txt"
}

@test "wrong-variant yq (kislyuk) routes to setup-failed" {
  # Stage a yq shim that mimics kislyuk/yq's --version output (no "mikefarah" string).
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/yq" <<'YQ'
#!/bin/sh
case $1 in
  --version) printf 'yq 3.4.3\n'; exit 0 ;;
  *) exit 1 ;;
esac
YQ
  chmod +x "${shim}/yq"
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -q "mikefarah" "${run_dir%/}/setup_error.txt"
}

@test "YAML repo loads when no env override" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='test-org/test-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=test-org/test-repo (source=yaml)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "env GH_REPO beats YAML" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: yaml-org/yaml-repo
base_branch: main
YAML
  GH_REPO=env-org/env-repo run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='env-org/env-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=env-org/env-repo (source=env)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "no repo configured (no env, no YAML) routes to setup-failed" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  err="${run_dir%/}/setup_error.txt"
  grep -q "no repo configured" "${err}"
  grep -q "GH_REPO" "${err}"
  grep -q "dev_loop.config.yaml" "${err}"
}

@test "BASE_BRANCH autodetect via gh shim" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
YAML
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  # Mock gh repo view to return a non-default branch.
  cat > "${shim}/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "repo view")
    if printf '%s\n' "$@" | grep -q defaultBranchRef; then
      printf 'develop\n'
      exit 0
    fi ;;
esac
exit 1
GH
  chmod +x "${shim}/gh"
  # Real yq/jq/git/tracker passthrough so prereq check passes.
  ln -sf "$(command -v yq)" "${shim}/yq" 2>/dev/null || true
  ln -sf "$(command -v jq)" "${shim}/jq" 2>/dev/null || true
  ln -sf "$(command -v git)" "${shim}/git" 2>/dev/null || true
  ln -sf "$(command -v tracker)" "${shim}/tracker" 2>/dev/null || true
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^BASE_BRANCH='develop'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "BASE_BRANCH=develop (source=autodetect)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}

@test "DEV_LOOP_BASE_BRANCH env beats YAML" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: master
YAML
  DEV_LOOP_BASE_BRANCH=feature/foo run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^BASE_BRANCH='feature/foo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
}

@test "atomic env write: env file mode 600, RUN_DIR mode 700, config_resolution.txt format" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
allow_no_ci: false
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  run_dir="${DIP_ROOT}/runs/${rid}"
  [ "$(stat -c %a "${run_dir}")" = "700" ]
  [ "$(stat -c %a "${run_dir}/env")" = "600" ]
  grep -qE '^GH_REPO=test-org/test-repo \(source=yaml\)$' "${run_dir}/config_resolution.txt"
  grep -qE '^BASE_BRANCH=main \(source=yaml\)$' "${run_dir}/config_resolution.txt"
  grep -qE '^ALLOW_NO_CI=false \(source=yaml\)$' "${run_dir}/config_resolution.txt"
}

@test "env file rejects YAML values containing newlines" {
  # YAML's double-quoted scalar `"foo\nbar"` decodes to a literal newline —
  # use the printf-literal `\\n` so YAML (not printf) does the escape.
  mkdir -p "${WORKDIR}/dev_loop/config"
  printf 'repo: "test/test"\nbase_branch: "foo\\nbar"\n' \
    > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # Failure paths publish .current_rid so downstream cleanup/ratchet can find run_dir.
  run_dir="$(ls -d "${DIP_ROOT}/runs/"*/ | head -1)"
  grep -qi "newline" "${run_dir%/}/setup_error.txt"
}

@test "env file single-quotes values containing \$(...) and backticks" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: 'test/test'
base_branch: '$(rm -rf $HOME)'
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  ( set -a; . "${DIP_ROOT}/runs/${rid}/env"; set +a
    [ "${BASE_BRANCH}" = '$(rm -rf $HOME)' ] )
}

@test ".current_rid points at a complete env file (atomic publish)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  run_dir="${DIP_ROOT}/runs/${rid}"
  # If .current_rid exists, env must exist and be a regular file.
  [ -f "${run_dir}/env" ]
  [ ! -L "${run_dir}/env" ]
  # No orphan tmp files.
  ! [ -e "${DIP_ROOT}/.current_rid.tmp" ]
  ! [ -e "${run_dir}/env.tmp" ]
}

@test "env file emits only allow-listed keys (drift guard vs comment block)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"

  # Read the canonical allow-list from setup_run.sh's comment block.
  # The block is delimited by "Allow-list" header until the next `-----` line.
  allow=$(awk '/^# Allow-list/,/^# -+$/' "${SCRIPT}" \
    | tr -d '#' | tr -s ' \n' ' ' | tr ' ' '\n' \
    | grep -E '^[A-Z][A-Z0-9_]+$' | sort -u)
  [ -n "${allow}" ]

  # Every key emitted to env must be in the allow-list.
  emitted=$(awk -F= '/^[A-Z]/ {print $1}' "${DIP_ROOT}/runs/${rid}/env" | sort -u)
  for key in ${emitted}; do
    printf '%s\n' "${allow}" | grep -qx "${key}" \
      || { printf 'env emitted forbidden key: %s\n' "${key}" >&2; return 1; }
  done
}

@test "malformed YAML routes to setup-failed with yq parse error" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  # Syntactically invalid YAML — unclosed flow sequence.
  printf 'repo: [unclosed\n' > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -f "${DIP_ROOT}/runs/${rid}/setup_error.txt" ]
  # The error must point at the YAML somewhere (either yq's stderr or our
  # wrapping message that says "yq parse failed; see setup_error.txt").
  grep -qiE 'yq|parse|yaml' "${DIP_ROOT}/runs/${rid}/setup_error.txt"
}

@test "setup-failed publishes .current_rid so cleanup/ratchet can find run_dir" {
  # No YAML, no env → "no repo configured" path.
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  # .current_rid must be published even on failure.
  [ -f "${DIP_ROOT}/.current_rid" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -n "${rid}" ]
  # setup_error.txt is at the published run_dir.
  [ -f "${DIP_ROOT}/runs/${rid}/setup_error.txt" ]
  grep -q "no repo configured" "${DIP_ROOT}/runs/${rid}/setup_error.txt"
}
