#!/bin/sh
# pre_filter_issues.sh — deterministic filter applied to the fetched issue list.
# Emits: filter-ok | filter-empty | filter-failed
#
# Filter rules (mirror config/dev_loop.config.yaml):
#   - drop excluded_labels (default: survey, question, tracking, blocked)
#   - drop authors matching '*[bot]' glob
#   - drop excluded title patterns (default: dev_loop / dippin meta / tracker meta)
#   - sort by priority_label (P0 > P1 > P2 > P3 > unlabeled) then issue_number ASC
#
# Outputs:
#   $RUN_DIR/filtered_issues.json   — survivors, sorted by descending priority
#   $RUN_DIR/filter_count.txt       — integer count
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
DIP_ROOT="${DEV_LOOP_STATE_ROOT:-${STATE_ROOT_DEFAULT}}"
if [ -n "${DEV_LOOP_RUN_DIR:-}" ]; then
  RUN_DIR="${DEV_LOOP_RUN_DIR}"
else
  rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
  [ -n "${rid}" ] || { printf 'no .current_rid; was setup_run executed?\n' >&2; exit 1; }
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
fi
[ -f "${RUN_DIR}/env" ] || { printf 'missing env at %s\n' "${RUN_DIR}/env" >&2; exit 1; }
[ ! -L "${RUN_DIR}/env" ] || { printf 'env is a symlink; refusing\n' >&2; exit 1; }
set -a
# shellcheck disable=SC1091
. "${RUN_DIR}/env"
set +a
# ---end-bootstrap-reference---

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/filter_error.txt" 2>/dev/null || true
  printf 'filter-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "filter-failed"; exit 0; fi' EXIT

if [ ! -f "${RUN_DIR}/issues.json" ]; then
  emit_failure "issues.json missing"
fi

# Filter knobs: read directly from YAML (no env round-trip) per spec §4.6.
CFG="dev_loop/config/dev_loop.config.yaml"
if [ -f "${CFG}" ]; then
  EXCLUDED_LABELS=$(yq -o=json '.issue_filter.excluded_labels // ["survey","question","tracking","blocked"]' "${CFG}")
  EXCLUDED_TITLE_RE=$(yq -r '.issue_filter.excluded_title_regex // "(dev_loop|dippin meta|tracker meta)"' "${CFG}")
else
  EXCLUDED_LABELS='["survey","question","tracking","blocked"]'
  EXCLUDED_TITLE_RE='(dev_loop|dippin meta|tracker meta)'
fi

jq --argjson excluded "${EXCLUDED_LABELS}" \
   --arg title_re "${EXCLUDED_TITLE_RE}" '
  # Match SelectNextIssue prompt: accept P0/P1/P2/P3 and variants
  # priority/P0, priority:P0, "P0 - critical", "P0: ...". Compare on a
  # normalized form (lowercased, leading "priority[/:] " stripped) and
  # check whether it starts with "p0".."p3".
  def priority_rank:
    ((.labels // []) | map(.name)) as $names
    | ($names | map(
        ascii_downcase
        | sub("^priority[/:][[:space:]]*"; "")
        | sub("^prio[/:][[:space:]]*"; "")
      )) as $norm
    | if   ($norm | map(startswith("p0")) | any) then 0
      elif ($norm | map(startswith("p1")) | any) then 1
      elif ($norm | map(startswith("p2")) | any) then 2
      elif ($norm | map(startswith("p3")) | any) then 3
      else 4
      end;
  map(select(
    (((.labels // []) | map(.name)) as $names
       | ($names | map(. as $l | $excluded | index($l)) | all(. == null)))
    and ((.author.login // "") | test("\\[bot\\]$") | not)
    and ((.title // "") | test($title_re; "i") | not)
  ))
  | sort_by(priority_rank, .number)
' "${RUN_DIR}/issues.json" > "${RUN_DIR}/filtered_issues.json.tmp" \
  || emit_failure "jq filter failed"

count=$(jq 'length' "${RUN_DIR}/filtered_issues.json.tmp")
mv "${RUN_DIR}/filtered_issues.json.tmp" "${RUN_DIR}/filtered_issues.json"
printf '%s' "${count}" > "${RUN_DIR}/filter_count.txt"

if [ "${count}" -eq 0 ]; then
  printf 'filter-empty'
  exit 0
fi

# Emit marker first; SelectNextIssue agent (tool_access: none) reads the
# filtered issue list via ctx.last_response (auto-injected into its prompt).
# Anthropic/Gemini prompt guidance both recommend XML tags over text fences
# for parser reliability with long-context structured inputs.
printf 'filter-ok'
issues_text=$(cat "${RUN_DIR}/filtered_issues.json")
cat <<DATA

<filtered_issues>
${issues_text}
</filtered_issues>
DATA
