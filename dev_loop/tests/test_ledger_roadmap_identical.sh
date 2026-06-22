#!/bin/sh
# test_ledger_roadmap_identical.sh — assert the ledger/roadmap state-machine
# shell blocks that are MEANT to be byte-identical stay identical across the
# sprint pipeline family. Issue #109 flagged this logic as duplicated; the
# audit in docs/ledger-roadmap-state-machine-audit.md records why a single
# shared source is not viable (packed .dipx inlines tool-node `command:` shell
# and does not ship dev_loop/scripts/lib; subgraphs compose whole workflows,
# not snippets — the #107/#108 precedent) and keeps the inline copies. This
# gate is the drift guard those copies need (mirroring
# test_bootstrap_identical.sh / test_persist_verdict_identical.sh).
#
# SCOPE: only the clusters whose members are byte-identical AND intended to
# stay so are checked. Per-node-intent variation the audit explicitly waives
# (the Group-A vs Group-B scanner wrappers, megaplan's distinct ops, the
# iter_dev grep -c path-arg/subset differences, the architect_only enclosing
# node) is NOT asserted here — only the shared block bodies are.
#
# Mechanism: each block is extracted by content anchors (no markers are added
# to the .dip files, so tracker's shell/coverage parsing is untouched), then
# every member of a cluster is compared against the first member with `cmp`.
set -eu

# Run from the repo root regardless of invocation cwd (this script lives two
# levels down at dev_loop/tests/).
cd "$(dirname "$0")/../.."

tmp_ref=$(mktemp)
tmp_cur=$(mktemp)
trap 'rm -f "${tmp_ref}" "${tmp_cur}"' EXIT INT TERM

fail=0

# extract_node_block FILE END_ANCHOR
# Prints the lines of a tool node's `command:` body: from the line after the
# nearest preceding `    command:` up to and including the line containing
# END_ANCHOR. END_ANCHOR must occur exactly once in FILE (asserted by caller).
extract_node_block() {
  awk -v anchor="$2" '
    { lines[NR] = $0 }
    index($0, anchor) { endln = NR }
    END {
      if (!endln) { exit 3 }
      start = 0
      for (i = endln; i >= 1; i--) {
        if (lines[i] ~ /^    command:[[:space:]]*$/) { start = i + 1; break }
      }
      if (!start) { exit 4 }
      for (i = start; i <= endln; i++) print lines[i]
    }
  ' "$1"
}

# extract_range FILE START_ANCHOR END_ANCHOR
# Prints the inclusive run from the first line containing START_ANCHOR through
# the first subsequent line containing END_ANCHOR. Used for a sub-block that
# does not span a whole node body. Exits non-zero (4) if END_ANCHOR is never
# seen at or after START_ANCHOR, so a coordinated rename of the end anchor
# across every member fails loud instead of silently overrunning to EOF.
extract_range() {
  awk -v s="$2" -v e="$3" '
    index($0, s) { grab = 1 }
    grab { print }
    grab && index($0, e) { saw_end = 1; exit 0 }
    END { if (!saw_end) exit 4 }
  ' "$1"
}

# count_anchor FILE ANCHOR -> echoes the number of lines containing ANCHOR.
count_anchor() {
  grep -cF "$2" "$1" 2>/dev/null || true
}

# check_node_cluster NAME END_ANCHOR FILES...
# Extracts each file's node block and cmp's each against the first. A file
# whose anchor count is not exactly 1 is a hard FAIL (a node was added, removed,
# or renamed and the gate's assumption no longer holds — fail loud, never pass
# silently).
check_node_cluster() {
  name=$1; anchor=$2; shift 2
  first=""
  for f in "$@"; do
    n=$(count_anchor "$f" "$anchor")
    if [ "$n" != "1" ]; then
      printf '[%s] expected exactly 1 occurrence of anchor in %s, found %s\n' "$name" "$f" "$n" >&2
      fail=1
      continue
    fi
    if [ -z "$first" ]; then
      first=$f
      rc=0; extract_node_block "$f" "$anchor" > "$tmp_ref" || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf '[%s] could not extract reference block from %s (rc=%s)\n' "$name" "$f" "$rc" >&2
        fail=1
        first=""   # don't compare later members against a failed extraction
      fi
      continue
    fi
    rc=0; extract_node_block "$f" "$anchor" > "$tmp_cur" || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf '[%s] could not extract block from %s (rc=%s)\n' "$name" "$f" "$rc" >&2
      fail=1
      continue
    fi
    if ! cmp -s "$tmp_ref" "$tmp_cur"; then
      printf '[%s] block drift in %s (differs from reference %s)\n' "$name" "$f" "$first" >&2
      fail=1
    fi
  done
}

# check_range_cluster NAME START_ANCHOR END_ANCHOR FILES...
check_range_cluster() {
  name=$1; start=$2; end=$3; shift 3
  first=""
  for f in "$@"; do
    n=$(count_anchor "$f" "$start")
    if [ "$n" != "1" ]; then
      printf '[%s] expected exactly 1 occurrence of start-anchor in %s, found %s\n' "$name" "$f" "$n" >&2
      fail=1
      continue
    fi
    # End anchor must also be unique: a duplicate end anchor inserted before the
    # real one would truncate extract_range's output and could pass silently if
    # done identically across members. Requiring exactly 1 forecloses that.
    m=$(count_anchor "$f" "$end")
    if [ "$m" != "1" ]; then
      printf '[%s] expected exactly 1 occurrence of end-anchor in %s, found %s\n' "$name" "$f" "$m" >&2
      fail=1
      continue
    fi
    if [ -z "$first" ]; then
      first=$f
      rc=0; extract_range "$f" "$start" "$end" > "$tmp_ref" || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf '[%s] end-anchor not found after start in reference %s (rc=%s)\n' "$name" "$f" "$rc" >&2
        fail=1
        first=""   # don't compare later members against a failed extraction
      fi
      continue
    fi
    rc=0; extract_range "$f" "$start" "$end" > "$tmp_cur" || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf '[%s] end-anchor not found after start in %s (rc=%s)\n' "$name" "$f" "$rc" >&2
      fail=1
      continue
    fi
    if ! cmp -s "$tmp_ref" "$tmp_cur"; then
      printf '[%s] block drift in %s (differs from reference %s)\n' "$name" "$f" "$first" >&2
      fail=1
    fi
  done
}

# Cluster 1 — Group-A next-sprint scanner (3-tier fallback, writes
# current_sprint_id.txt, emits `current-<id>`). SetCurrentSprint node.
check_node_cluster "scanner-A" "printf 'current-%s' \"\$target\"" \
  sprint/sprint_exec.dip \
  sprint/sprint_exec-cheap.dip

# Cluster 2 — Group-B next-sprint scanner (no_ledger/all_done guards, emits
# `next-<id>`). check_ledger node.
check_node_cluster "scanner-B" "printf 'next-%s' \"\$target\"" \
  sprint/sprint_runner.dip \
  sprint/sprint_runner-cheap.dip \
  local_code_gen/sprint_runner_qwen.dip

# Cluster 3 — row-status in_progress update (awk rewrite $3 + mv .tmp).
check_node_cluster "row-in_progress" "printf 'in_progress-%s' \"\$target\"" \
  sprint/sprint_exec.dip \
  sprint/sprint_exec-cheap.dip \
  sprint/sprint_runner-cheap.dip \
  local_code_gen/sprint_runner_qwen.dip

# Cluster 4 — row-status completed update (awk rewrite $3 + mv .tmp), the
# CompleteSprint/mark_complete twin of cluster 3 across the same four files.
check_node_cluster "row-completed" "printf 'completed-%s' \"\$target\"" \
  sprint/sprint_exec.dip \
  sprint/sprint_exec-cheap.dip \
  sprint/sprint_runner-cheap.dip \
  local_code_gen/sprint_runner_qwen.dip

# Cluster 5 — ledger progress counter (total + completed||skipped).
# report_progress node.
check_node_cluster "progress-counter" "printf 'progress-%s-of-%s-%spct'" \
  sprint/sprint_runner.dip \
  sprint/sprint_runner-cheap.dip \
  local_code_gen/sprint_runner_qwen.dip

# Cluster 6 — validate_output ledger/JSONL three-way consistency sub-block.
# The enclosing nodes differ (architect_only carries a distinct label and exit
# contract; see the audit), but this sub-block is shared verbatim.
# The start anchor is a single-quoted fixed string: it is matched literally
# (grep -F / awk index), so the `$(` must NOT expand — SC2016 is the intent.
# shellcheck disable=SC2016
check_range_cluster "validate-jsonl" \
  'ledger_ids=$(awk -F' \
  "ledger-file-mismatch" \
  local_code_gen/spec_to_sprints.dip \
  local_code_gen/spec_to_sprints_lowreason.dip \
  local_code_gen/architect_only.dip

exit ${fail}
