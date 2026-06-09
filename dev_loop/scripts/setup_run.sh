#!/bin/sh
# setup_run.sh — initialize the per-run state directory and verify prereqs.
# Emits: setup-ok | setup-resume-required | setup-failed
#
# Runs under dash (tracker invokes via `sh -c <content>` — the shebang is
# advisory). POSIX `sh` style (no bash arrays, no `trap ERR`, no `[[ ]]`),
# augmented with a few Linux-only utilities where they read clearly
# (`find -mmin`, GNU stat). dev_loop already requires Linux for the
# writable_paths Landlock jail, so the Linux pin is not a new constraint.
#
# State layout:
#   $DIP_ROOT/.current_rid               — sentinel pointing at the active run
#   $DIP_ROOT/runs/<rid>/rid.txt         — the run id (idempotent record)
#   $DIP_ROOT/runs/<rid>/started_at.txt  — UTC ISO 8601 timestamp
#   $DIP_ROOT/runs/<rid>/env             — KEY=VALUE pairs downstream scripts source
#   $DIP_ROOT/runs/<rid>/setup_error.txt — populated only on setup-failed
set -eu
umask 077

# Best-effort early peek at YAML.runtime_state_root so DIP_ROOT can honor
# the 3-layer precedence env > YAML > default (spec §4.6). The full YAML
# resolver runs later with strict parse-error handling; this peek is
# silently lenient — if yq isn't installed yet, or the YAML is malformed,
# the variant probe + full resolver will catch it downstream.
yaml_state_root=""
if [ -f "dev_loop/config/dev_loop.config.yaml" ] && command -v yq >/dev/null 2>&1; then
  yaml_state_root=$(yq -r '.runtime_state_root // ""' dev_loop/config/dev_loop.config.yaml 2>/dev/null || true)
  # Newline/CR rejection (reject_special is defined later; inline this minimal check):
  case ${yaml_state_root} in *"$(printf '\n_')"*|*"$(printf '\r_')"*) yaml_state_root="" ;; esac
fi

if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
  src_state_root='env'
elif [ -n "${yaml_state_root}" ]; then
  DIP_ROOT="${yaml_state_root}/dev_loop"
  src_state_root='yaml'
else
  DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
  src_state_root='default'
fi
mkdir -p "${DIP_ROOT}/runs"

# Resume detection: if a prior run still has a worktree, signal the operator
# to invoke `tracker --resume`. We do NOT auto-resume from setup_run — the
# upstream pipeline routes the marker straight to Exit.
if [ -f "${DIP_ROOT}/.current_rid" ]; then
  prev_rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
  if [ -n "${prev_rid}" ] && [ -d "${DIP_ROOT}/runs/${prev_rid}/worktree" ]; then
    printf 'setup-resume-required'
    exit 0
  fi
fi

rid="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="${DIP_ROOT}/runs/${rid}"

emit_failure() {
  mkdir -p "${run_dir}" 2>/dev/null || true
  printf '%s\n' "$1" > "${run_dir}/setup_error.txt" 2>/dev/null || true
  # Publish .current_rid so downstream cleanup/ratchet can find this run_dir.
  # Atomic via mv -Tf to keep the partial-state invariant.
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid.tmp" 2>/dev/null || true
  mv -Tf "${DIP_ROOT}/.current_rid.tmp" "${DIP_ROOT}/.current_rid" 2>/dev/null || true
  printf 'setup-failed'
  exit 0
}

# EXIT trap as a safety net for unexpected non-zero exits. Records the rc
# into setup_error.txt so post-mortems can find that it tripped — the
# explicit `emit_failure` paths still produce richer per-mode messages.
#
# `LINENO` is intentionally NOT referenced here: dash does not guarantee it
# is set, and under `set -u` an unset `${LINENO}` would error inside the
# trap itself, suppressing the setup-failed marker and leaving the pipeline
# with no routable outcome. The rc alone is enough breadcrumb.
# shellcheck disable=SC2154  # rc is assigned inside the single-quoted trap body
trap 'rc=$?
      # Unlink any orphan .tmp files from a partial run; harmless when none exist.
      rm -f "${DIP_ROOT}/.current_rid.tmp" 2>/dev/null || true
      [ -n "${run_dir:-}" ] && rm -f "${run_dir}/env.tmp" 2>/dev/null || true
      if [ "${rc}" -ne 0 ]; then
        mkdir -p "${run_dir}" 2>/dev/null || true
        printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
          > "${run_dir}/setup_error.txt" 2>/dev/null || true
        printf "setup-failed"
        exit 0
      fi' EXIT

# Newline / carriage-return sentinels used by both sh_single_quote (below)
# and reject_special (further down) to keep structural-hygiene checks aligned.
# NUL isn't covered: POSIX `printf` can't emit a NUL byte so the case pattern
# would degenerate to `*""*` (matches everything, incl. empty string).
NL="$(printf '\n_')"; NL="${NL%_}"
CR="$(printf '\r_')"; CR="${CR%_}"

# Shell-safe single-quote escape for env-file values. The '\''-trick is POSIX
# and works under dash. Refuses values containing newline / CR — upstream
# reject_special already catches these on YAML scalars, but emit_env defends
# in depth for env-precedence and autodetect values.
sh_single_quote() {
  case $1 in
    *"${NL}"*|*"${CR}"*) return 1 ;;
  esac
  printf "'%s'\n" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# emit_env KEY VALUE — writes `KEY='shell-escaped-value'\n` to fd 3 (opened
# by the atomic env.tmp block below). Fails closed via emit_failure if the
# value would smuggle a newline / CR.
emit_env() {
  esc=$(sh_single_quote "$2") || emit_failure "env value contains newline/CR (key=$1)"
  printf '%s=%s\n' "$1" "${esc}" >&3
}

# Concurrency lock — atomic mkdir is the POSIX-portable pattern. Without
# this, a second `tracker dev_loop/dev_loop.dip` started in the same workdir
# during the early window (after setup_run but before CreateWorktree)
# overwrites .current_rid and corrupts the first run's RUN_DIR resolution.
# cleanup_worktree.sh releases the lock at pipeline exit.
#
# Staleness check: PID-based liveness is the primary signal. At lock acquire
# we walk up the process tree to find the tracker pid (our grandparent: sh →
# tracker) and persist it as ${LOCK_DIR}/holder_pid. A second invocation
# checks `kill -0 <holder_pid>` to see if the holder is still alive. mtime
# is the fallback when the PID file is missing (e.g., from an older lock
# format) — set to 4 hours since any well-behaved run reaches
# CleanupWorktree well before then, but `kill -0` is the real authority.
LOCK_DIR="${DIP_ROOT}/.dev_loop.lock"
LOCK_STALE_MIN=240
lock_holder_alive() {
  pid_file="${LOCK_DIR}/holder_pid"
  if [ ! -f "${pid_file}" ]; then
    # No PID file (older lock format or crash before write). Fall back
    # to the mtime heuristic.
    [ -z "$(find "${LOCK_DIR}" -maxdepth 0 -mmin "+${LOCK_STALE_MIN}" 2>/dev/null)" ]
    return $?
  fi
  pid=$(cat "${pid_file}" 2>/dev/null || true)
  [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null
}
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  if ! lock_holder_alive; then
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
    mkdir "${LOCK_DIR}"
  else
    holder=$(cat "${LOCK_DIR}/rid" 2>/dev/null || printf '<unknown>')
    mkdir -p "${run_dir}"
    {
      printf 'another dev_loop run is active (rid=%s)\n' "${holder}"
      printf 'release the lock if it is stale: rm -rf %s\n' "${LOCK_DIR}"
    } > "${run_dir}/setup_error.txt"
    printf 'setup-failed'
    exit 0
  fi
fi
printf '%s' "${rid}" > "${LOCK_DIR}/rid"
# Persist the tracker pid for the next invocation's `kill -0` liveness
# check. tracker invokes scripts via `sh -c <content>`, so from inside
# this script $PPID IS the tracker process (sh's parent). The earlier
# version read /proc/${PPID}/status to walk up one more level — that was
# wrong, it gave tracker's parent (typically the operator's shell), which
# stays alive after tracker exits and made the lock look held forever.
printf '%s' "${PPID}" > "${LOCK_DIR}/holder_pid"

mkdir -p "${run_dir}"
printf '%s\n' "${rid}" > "${run_dir}/rid.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "${run_dir}/started_at.txt"

# Verify prerequisite tooling.
missing=""
for cmd in gh jq git tracker yq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    missing="${missing}${missing:+ }${cmd}"
  fi
done
if [ -n "${missing}" ]; then
  emit_failure "missing required commands: ${missing} (install yq from https://github.com/mikefarah/yq/releases)"
fi

# Probe yq variant. The Python kislyuk/yq and the Go mikefarah/yq diverge in
# syntax; we require mikefarah v4+. The --version output contains the URL.
yq_ver=$(yq --version 2>&1)
if ! printf '%s' "${yq_ver}" | grep -qF 'github.com/mikefarah/yq'; then
  emit_failure "yq must be mikefarah/yq v4+; got: ${yq_ver} — install from https://github.com/mikefarah/yq/releases"
fi

# Discover tracker's per-invocation artifact dir NOW (at pipeline start) so
# downstream persist scripts can address it explicitly rather than via
# ls -dt mtime — which would clash with any concurrent tracker run in the
# same workdir. tracker creates <workdir>/.tracker/runs/<runID>/ when it
# starts, so by the time SetupRun executes the dir already exists and is
# the newest under .tracker/runs.
TRACKER_ROOT="$(pwd)/.tracker/runs"
# shellcheck disable=SC2012
tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
# Strip the trailing slash for cleaner env-file output.
tracker_run_dir=${tracker_run_dir%/}

# Fail fast if we couldn't pin TRACKER_RUN_DIR. The persist_*.sh scripts
# now treat an env file present + TRACKER_RUN_DIR missing as a hard error
# (they refuse the mtime fallback when an env exists), so emitting setup-ok
# without TRACKER_RUN_DIR would just defer the failure to the first persist
# node with a less actionable message. Catch it here instead.
if [ -z "${tracker_run_dir}" ] || [ ! -d "${tracker_run_dir}" ]; then
  emit_failure "no tracker run dir found under ${TRACKER_ROOT}; is this being invoked through tracker?"
fi

# --- YAML config resolver -------------------------------------------------
# Allow-list (canonical home for both setup_run's emit and test_helpers.bash's
# unset list — keep these two in sync):
#   GH_REPO BASE_BRANCH DEV_LOOP_RUN_ID DEV_LOOP_RUN_DIR TRACKER_RUN_DIR
#   ALLOW_NO_CI
# --------------------------------------------------------------------------
CFG="dev_loop/config/dev_loop.config.yaml"
yaml_repo=""
yaml_base_branch=""
yaml_allow_no_ci=""
if [ -f "${CFG}" ]; then
  if ! yaml_repo=$(yq -r '.repo // ""' "${CFG}" 2>"${run_dir}/setup_error.txt"); then
    emit_failure "yq parse failed; see setup_error.txt"
  fi
  # base_branch and allow_no_ci are resolved + validated here.
  yaml_base_branch=$(yq -r '.base_branch // ""' "${CFG}")
  # allow_no_ci is a boolean in YAML; `// ""` would collapse a literal `false`
  # to the default (jq treats false as a fallback trigger). Emit the raw value
  # and normalize the absent sentinel "null" to empty here.
  yaml_allow_no_ci=$(yq -r '.allow_no_ci' "${CFG}")
  if [ "${yaml_allow_no_ci}" = "null" ]; then
    yaml_allow_no_ci=""
  fi
fi

# Reject newline/CR in any scalar (structural hygiene per spec §3.5).
# NL / CR sentinels are defined near the top of the script alongside
# sh_single_quote — same alphabet, two enforcement points.
reject_special() {
  case $1 in
    *"${NL}"*|*"${CR}"*)
      emit_failure "config value contains newline/CR (key=$2)" ;;
  esac
}
reject_special "${yaml_repo}" repo
reject_special "${yaml_base_branch}" base_branch
reject_special "${yaml_allow_no_ci}" allow_no_ci

# Resolve with precedence env > YAML > default. Track source for the log.
if [ -n "${GH_REPO:-}" ]; then
  resolved_repo="${GH_REPO}"; src_repo='env'
elif [ -n "${yaml_repo}" ]; then
  resolved_repo="${yaml_repo}"; src_repo='yaml'
else
  emit_failure "no repo configured (set GH_REPO env var or populate ${CFG} with: repo: owner/name)"
fi

# Resolve BASE_BRANCH with precedence env > YAML > autodetect via gh.
if [ -n "${DEV_LOOP_BASE_BRANCH:-}" ]; then
  resolved_base="${DEV_LOOP_BASE_BRANCH}"; src_base='env'
elif [ -n "${yaml_base_branch}" ]; then
  resolved_base="${yaml_base_branch}"; src_base='yaml'
else
  # Autodetect via gh; timeout caps network hang.
  autodetect=$(timeout 5s gh repo view "${resolved_repo}" \
    --json defaultBranchRef -q .defaultBranchRef.name 2>"${run_dir}/setup_error.txt")
  if [ -z "${autodetect}" ]; then
    emit_failure "base_branch autodetect failed; set DEV_LOOP_BASE_BRANCH or YAML base_branch (gh stderr in setup_error.txt)"
  fi
  resolved_base="${autodetect}"; src_base='autodetect'
fi
reject_special "${resolved_base}" base_branch

# Resolve allow_no_ci with precedence env > YAML > "false".
if [ -n "${DEV_LOOP_ALLOW_NO_CI:-}" ]; then
  resolved_allow_no_ci="${DEV_LOOP_ALLOW_NO_CI}"; src_allow='env'
elif [ -n "${yaml_allow_no_ci}" ]; then
  resolved_allow_no_ci="${yaml_allow_no_ci}"; src_allow='yaml'
else
  resolved_allow_no_ci='false'; src_allow='default'
fi

# Build env file atomically: write to env.tmp inside RUN_DIR, then mv -f to
# env. umask 077 (set at the top of the script) ensures env.tmp inherits
# mode 600 by default; the explicit chmod is belt-and-suspenders in case a
# downstream change to umask slips in.
env_tmp="${run_dir}/env.tmp"
exec 3>"${env_tmp}"
emit_env GH_REPO          "${resolved_repo}"
emit_env BASE_BRANCH      "${resolved_base}"
emit_env ALLOW_NO_CI      "${resolved_allow_no_ci}"
emit_env DEV_LOOP_RUN_ID  "${rid}"
emit_env DEV_LOOP_RUN_DIR "${run_dir}"
emit_env TRACKER_RUN_DIR  "${tracker_run_dir}"
exec 3>&-
chmod 600 "${env_tmp}"
# Reject a pre-existing symlink at the destination (operator's UID is trusted
# per spec §3.5; this guards against an accidental operator symlink left
# behind by a botched cleanup).
[ ! -L "${run_dir}/env" ] || emit_failure "${run_dir}/env is a symlink; refusing"
mv -f "${env_tmp}" "${run_dir}/env"

# Per-run config resolution log — operator-readable line per knob.
cat > "${run_dir}/config_resolution.txt" <<EOF
GH_REPO=${resolved_repo} (source=${src_repo})
BASE_BRANCH=${resolved_base} (source=${src_base})
ALLOW_NO_CI=${resolved_allow_no_ci} (source=${src_allow})
DIP_ROOT=${DIP_ROOT} (source=${src_state_root})
EOF
chmod 600 "${run_dir}/config_resolution.txt"

# Publish .current_rid atomically AFTER env + config_resolution are in place.
# Order matters: downstream scripts that source $RUN_DIR/env via the bootstrap
# preamble must never see a published rid pointing at an incomplete RUN_DIR.
printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid.tmp"
if ! mv -Tf "${DIP_ROOT}/.current_rid.tmp" "${DIP_ROOT}/.current_rid"; then
  emit_failure "atomic publish of .current_rid failed (mv -Tf returned $?)"
fi

printf 'setup-ok'
