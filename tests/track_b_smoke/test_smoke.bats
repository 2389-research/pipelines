#!/usr/bin/env bats
# ABOUTME: Bats tests for smoke.sh's workdir lifecycle. Uses a PATH shim to
# ABOUTME: stand in for `tracker`, so these tests run without any LLM calls.
# ABOUTME: Focused on the cleanup-on-failure contract: a failing assertion
# ABOUTME: must leave the temp workdir behind for operator inspection.

setup() {
  SMOKE="${BATS_TEST_DIRNAME}/smoke.sh"
  TMPDIR="$(mktemp -d -t track_b_smoke_test.XXXXXX)"
  export TMPDIR
  SHIM="${TMPDIR}/bin"
  mkdir -p "${SHIM}"
  export PATH="${SHIM}:${PATH}"
  # Smoke harness creates its own workdir under the system temp dir; capture
  # the tree before/after so we can identify the workdir it produced.
  SYS_TMP=$(dirname "$(mktemp -u -t track_b_smoke.XXXXXX)")
  export SYS_TMP
}

teardown() {
  # Best-effort cleanup of any smoke harness workdirs left behind on failure.
  find "${SYS_TMP}" -maxdepth 1 -name 'track_b_smoke.*' -type d -mmin -5 \
    -exec rm -rf {} + 2>/dev/null || true
  rm -rf "${TMPDIR}"
}

# write_tracker_shim <body> -- emit a fake `tracker` on PATH whose body runs
# inside the workdir smoke.sh cd'd into.
write_tracker_shim() {
  cat > "${SHIM}/tracker" <<EOF
#!/bin/sh
${1}
EOF
  chmod +x "${SHIM}/tracker"
}

# latest_smoke_workdir -- echo the most recently created track_b_smoke.* dir.
# Uses `-exec ls -1dt` for portability (BSD/macOS `find` lacks `-printf`),
# matching the discipline used by `track_b_run_dir` in lib.sh.
latest_smoke_workdir() {
  # shellcheck disable=SC2012
  find "${SYS_TMP}" -maxdepth 1 -name 'track_b_smoke.*' -type d -mmin -5 \
    -exec ls -1dt {} + 2>/dev/null | head -1
}

@test "smoke.sh removes workdir on success" {
  # Fake tracker emits a clean activity.jsonl + response.md — all assertions pass.
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Exit
printf "agent text without tool calls\n" > ./.tracker/runs/r1/Exit/response.md
printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}" \
  > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  run "${SMOKE}" verify
  [ "${status}" -eq 0 ]
  # The smoke harness should have removed its workdir on success. Probe the
  # system temp dir for any track_b_smoke.* tree younger than this test —
  # there should be none.
  wd=$(latest_smoke_workdir)
  [ -z "${wd}" ]
}

@test "smoke.sh preserves workdir on assertion failure" {
  # Fake tracker emits an activity.jsonl with a tool_call_start event — the
  # no-tool-events assertion must fail.
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Exit
printf "agent text\n" > ./.tracker/runs/r1/Exit/response.md
{
  printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}"
  printf "%s\n" "{\"type\":\"tool_call_start\",\"node_id\":\"Exit\",\"tool\":\"finish\"}"
} > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  run "${SMOKE}" verify
  [ "${status}" -ne 0 ]
  # The workdir must still exist for the operator.
  wd=$(latest_smoke_workdir)
  [ -n "${wd}" ]
  [ -d "${wd}" ]
  # The workdir path should appear in smoke.sh's stderr so the operator
  # knows where to look.
  case "${output}" in
    *"${wd}"*) ;;
    *) printf 'expected workdir path in output: %s\n' "${output}" >&2; return 1 ;;
  esac
  # Tracker stdout/stderr should still be on disk for diagnosis.
  [ -f "${wd}/tracker.stdout" ]
  [ -f "${wd}/tracker.stderr" ]
  # Clean it up explicitly so the next test starts fresh.
  rm -rf "${wd}"
}

@test "smoke.sh preserves workdir when track_b_run_dir fails" {
  # Fake tracker exits without ever creating .tracker/runs — the run_dir
  # lookup must fail and the workdir must be preserved.
  write_tracker_shim '
printf "tracker shim: no runs dir created\n" >&2
exit 0
'
  run "${SMOKE}" verify
  [ "${status}" -ne 0 ]
  wd=$(latest_smoke_workdir)
  [ -n "${wd}" ]
  [ -d "${wd}" ]
  # tracker.stderr should be retained too.
  [ -f "${wd}/tracker.stderr" ]
  rm -rf "${wd}"
}

@test "verify-sprint-exec fast-fails with exit 2 when yq is missing" {
  # Mask yq off PATH by pointing PATH at only the shim dir + a curated minimal
  # path. The shim dir has no `yq`, so `command -v yq` returns non-zero and
  # the preflight should exit 2 with a setup-error message.
  write_tracker_shim 'exit 0'
  # Provide the basic POSIX utilities smoke.sh needs but omit yq.
  for tool in mktemp cp basename dirname sed printf find ls head cat rm mkdir chmod cd; do
    : # built-ins or already on PATH via /bin /usr/bin below
  done
  PATH="${SHIM}:/usr/bin:/bin" run "${SMOKE}" verify-sprint-exec
  [ "${status}" -eq 2 ]
  case "${output}" in
    *"setup error: yq not installed"*) ;;
    *) printf 'expected setup-error message, got: %s\n' "${output}" >&2; return 1 ;;
  esac
}

@test "verify-sprint-runner fast-fails with exit 2 when yq is missing" {
  write_tracker_shim 'exit 0'
  PATH="${SHIM}:/usr/bin:/bin" run "${SMOKE}" verify-sprint-runner
  [ "${status}" -eq 2 ]
  case "${output}" in
    *"setup error: yq not installed"*) ;;
    *) printf 'expected setup-error message, got: %s\n' "${output}" >&2; return 1 ;;
  esac
}

@test "verify-sprint-exec invokes tracker shim when yq is present" {
  # Provide a fake yq on PATH (just `exit 0` is enough for `command -v`).
  cat > "${SHIM}/yq" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "${SHIM}/yq"
  # Tracker shim emits clean Start + Exit artifacts so both converted nodes
  # pass the 4-assertion battery.
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Start ./.tracker/runs/r1/Exit
printf "start agent text\n" > ./.tracker/runs/r1/Start/response.md
printf "exit agent text\n"  > ./.tracker/runs/r1/Exit/response.md
{
  printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Start\"}"
  printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}"
} > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  run "${SMOKE}" verify-sprint-exec
  [ "${status}" -eq 0 ]
  # Multi-node assertion: PASS line should name both converted nodes.
  case "${output}" in
    *"Start Exit"*) ;;
    *) printf 'expected both Start and Exit in PASS line: %s\n' "${output}" >&2; return 1 ;;
  esac
}

@test "multi-node family fails if only one converted node has artifacts" {
  # Provide yq so the preflight passes; then drop only Start's artifacts. The
  # Exit assertions must fail, proving the loop actually runs the battery for
  # *every* node in converted_nodes (not just the first).
  cat > "${SHIM}/yq" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "${SHIM}/yq"
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Start
printf "start agent text\n" > ./.tracker/runs/r1/Start/response.md
printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Start\"}" \
  > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  run "${SMOKE}" verify-sprint-exec
  [ "${status}" -ne 0 ]
}

@test "TRACK_B_SMOKE_KEEP=1 retains workdir even on success" {
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Exit
printf "agent text without tool calls\n" > ./.tracker/runs/r1/Exit/response.md
printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}" \
  > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  TRACK_B_SMOKE_KEEP=1 run "${SMOKE}" verify
  [ "${status}" -eq 0 ]
  wd=$(latest_smoke_workdir)
  [ -n "${wd}" ]
  [ -d "${wd}" ]
  rm -rf "${wd}"
}
