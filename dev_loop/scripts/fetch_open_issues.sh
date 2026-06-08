#!/bin/sh
# fetch_open_issues.sh — pull open issues for the locked repo.
# Emits: fetched-ok | fetch-failed
#
# Outputs:
#   $RUN_DIR/issues.json        — gh JSON list (sorted newest first)
#   $RUN_DIR/issues_count.txt   — integer count of fetched issues
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'fetch-failed'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/fetch_error.txt" 2>/dev/null || true
  printf 'fetch-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "fetch-failed"; exit 0; fi' EXIT

# Re-export env so gh stays repo-locked regardless of how this is invoked.
if [ -f "${RUN_DIR}/env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${RUN_DIR}/env"
  set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

gh issue list \
  --limit 200 \
  --state open \
  --json number,title,url,labels,author,createdAt,body \
  > "${RUN_DIR}/issues.json.tmp" \
  || emit_failure "gh issue list failed"

# Fail closed when gh returned 0 but the JSON is malformed/truncated; the
# silent `|| printf '0'` fallback would otherwise route to fetched-ok with
# an empty issues list, and the planner would proceed on bogus data.
if ! count=$(jq 'length' "${RUN_DIR}/issues.json.tmp" 2>"${RUN_DIR}/fetch_error.txt"); then
  printf 'jq could not parse issues.json.tmp\n' >> "${RUN_DIR}/fetch_error.txt"
  emit_failure "jq parse failed: see fetch_error.txt"
fi

mv "${RUN_DIR}/issues.json.tmp" "${RUN_DIR}/issues.json"
printf '%s' "${count}" > "${RUN_DIR}/issues_count.txt"

printf 'fetched-ok'
