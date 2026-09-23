#!/bin/sh
# ABOUTME: Leaves a failed claimed kata open and reviewable: label, comment, WIP commit, trunk restored.
# ABOUTME: Classifies the failure from run artifacts and records it in handoff.json for the board.
set -eu

test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
# Standalone complete.dip supplies TRACKER_RUN_DIR and TRACKER_RUN_ID. As a board subgraph body only
# TRACKER_WORKDIR is set, so run state lives in the workspace and identity comes from the board's run-id file.
workspace_dir=$(cd "$TRACKER_WORKDIR" && pwd -P)
base="${TRACKER_RUN_DIR:-$workspace_dir}"
# Tracker blanks any ${...} holding a literal dot in command_file text (even ${VAR:-DEFAULT} with VAR set),
# and the .tracker path has one, so read it into a plain variable and fall back to that dot-free default.
board_run_id=$(cat "$workspace_dir/.tracker/kata-board-run-id" 2>/dev/null || echo unknown)
run_id="${TRACKER_RUN_ID:-$board_run_id}"
state="$base/selected.json"
[ -f "$state" ] || { printf 'no claimed kata exists to hand off\n' >&2; exit 1; }
workspace=$(jq -er '.workspace' "$state")
uid=$(jq -er '.issue_uid' "$state")
qualified_id=$(jq -er '.qualified_id' "$state")
actor=$(jq -er '.actor' "$state")
branch=$(jq -er '.branch' "$state")
base_commit=$(jq -er '.base_commit' "$state")
trunk=$(jq -er '.trunk' "$state") || {
  printf 'selected.json has no trunk; this run predates landing on close and needs manual inspection\n' >&2
  exit 1
}
workspace=$(cd "$workspace" && pwd -P)
[ "$workspace" = "$(cd "$TRACKER_WORKDIR" && pwd -P)" ] || { printf 'tracker workspace changed\n' >&2; exit 1; }
cd "$workspace"

reason=implement
question=
wip_commit=
current_branch=$(git symbolic-ref --quiet --short HEAD || true)
if [ "$current_branch" = "$branch" ]; then
  # Later evidence outranks earlier: a question, then a landing failure, then any review, then a turn limit.
  if [ -s "$base/question.md" ]; then
    reason=decision
    question=$(cat "$base/question.md")
  elif jq -e '.outcome == "fail"' "$base/CloseSelected/status.json" >/dev/null 2>&1; then
    reason=land
  else
    for review in ReviewCorrectness ReviewScope ReReviewCorrectness ReReviewScope; do
      [ ! -f "$base/$review/status.json" ] || reason=review
    done
    if [ "$reason" = implement ] &&
      jq -e '.outcome == "fail" and .context_updates.turn_breach_class == "operator_decision"' \
        "$base/Implement/status.json" >/dev/null 2>&1; then
      reason=turn_limit
    fi
  fi
  dirty=$(git status --porcelain --untracked-files=normal)
  if [ -n "$dirty" ]; then
    git add -A
    git commit -q -m "wip(kata): $qualified_id handoff from run $run_id"
    wip_commit=$(git rev-parse HEAD)
  fi
  git switch -q "$trunk"
else
  reason=unexpected_checkout
fi

label=needs-review
[ "$reason" != decision ] || label=needs-decision
if [ ! -s "$base/handoff.md" ]; then
  printf 'Attempted the selected kata on branch %s. The bounded run did not earn both SHA-bound approvals. Inspect tracker run %s and the branch diff; unresolved review or test findings remain.\n' "$branch" "$run_id" >"$base/handoff.md"
fi
comment="$base/handoff-comment.md"
{
  cat "$base/handoff.md"
  printf '\nBranch: %s (base %s, wip %s)\nRun: %s\n' "$branch" "$base_commit" "${wip_commit:-none}" "$run_id"
  [ -z "$question" ] || printf 'Question: %s\n' "$question"
} >"$comment"
issue=$(kata show --workspace "$workspace" "$uid" --json)
printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "open"' >/dev/null || {
  printf 'kata %s is closed; the close step landed it but did not finish; inspect %s\n' "$qualified_id" "$workspace" >&2
  exit 1
}
kata label add --workspace "$workspace" --as "$actor" "$uid" "$label" --agent
kata comment --workspace "$workspace" --as "$actor" "$uid" --body-file "$comment" --agent
jq -n --arg run "$run_id" --arg uid "$uid" --arg qualified "$qualified_id" --arg reason "$reason" --arg label "$label" \
  --arg branch "$branch" --arg base "$base_commit" --arg wip "$wip_commit" --arg trunk "$trunk" --arg question "$question" \
  '{run_id:$run,issue_uid:$uid,qualified_id:$qualified,reason:$reason,label:$label,branch:$branch,base_commit:$base,
    wip_commit:(if $wip == "" then null else $wip end),trunk:$trunk,
    question:(if $question == "" then null else $question end)}' >"$base/handoff.json.tmp"
mv "$base/handoff.json.tmp" "$base/handoff.json"
# The warm-continue override belongs to this run's worker; the next run starts from the base budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
printf 'handoff-ok\n'
exit 1
