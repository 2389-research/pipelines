#!/bin/sh
# ABOUTME: Leaves a failed claimed kata open and reviewable: label, comment, WIP commit, starting branch restored.
# ABOUTME: Classifies the failure from run artifacts and records it in handoff.json for the board.
set -eu

test -n "${TRACKER_RUN_DIR:-}" || { printf 'TRACKER_RUN_DIR is required\n' >&2; exit 1; }
test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
run_id=${TRACKER_RUN_ID:-unknown}
state="$TRACKER_RUN_DIR/selected.json"
[ -f "$state" ] || { printf 'no claimed kata exists to hand off\n' >&2; exit 1; }
workspace=$(jq -er '.workspace' "$state")
uid=$(jq -er '.issue_uid' "$state")
qualified_id=$(jq -er '.qualified_id' "$state")
actor=$(jq -er '.actor' "$state")
branch=$(jq -er '.branch' "$state")
base_commit=$(jq -er '.base_commit' "$state")
start_branch=$(jq -er '.start_branch' "$state") || {
  printf 'selected.json has no start_branch; this run predates the branch restore and needs manual inspection\n' >&2
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
  # Later evidence outranks earlier: a question, then a publication failure, then any review, then a turn limit.
  if [ -s "$TRACKER_RUN_DIR/question.md" ]; then
    reason=decision
    question=$(cat "$TRACKER_RUN_DIR/question.md")
  elif jq -e '.outcome == "fail"' "$TRACKER_RUN_DIR/CloseSelected/status.json" >/dev/null 2>&1; then
    reason=publish
  else
    for review in ReviewCorrectness ReviewScope ReReviewCorrectness ReReviewScope; do
      [ ! -f "$TRACKER_RUN_DIR/$review/status.json" ] || reason=review
    done
    if [ "$reason" = implement ] &&
      jq -e '.outcome == "fail" and .context_updates.turn_breach_class == "operator_decision"' \
        "$TRACKER_RUN_DIR/Implement/status.json" >/dev/null 2>&1; then
      reason=turn_limit
    fi
  fi
  dirty=$(git status --porcelain --untracked-files=normal)
  if [ -n "$dirty" ]; then
    git add -A
    git commit -q -m "wip(kata): $qualified_id handoff from run $run_id"
    wip_commit=$(git rev-parse HEAD)
  fi
  git switch -q "$start_branch"
else
  reason=unexpected_checkout
fi

label=needs-review
[ "$reason" != decision ] || label=needs-decision
if [ ! -s "$TRACKER_RUN_DIR/handoff.md" ]; then
  printf 'Attempted the selected kata on branch %s. The bounded run did not earn both SHA-bound approvals. Inspect tracker run %s and the branch diff; unresolved review or test findings remain.\n' "$branch" "$run_id" >"$TRACKER_RUN_DIR/handoff.md"
fi
comment="$TRACKER_RUN_DIR/handoff-comment.md"
{
  cat "$TRACKER_RUN_DIR/handoff.md"
  printf '\nBranch: %s (base %s, wip %s)\nRun: %s\n' "$branch" "$base_commit" "${wip_commit:-none}" "$run_id"
  [ -z "$question" ] || printf 'Question: %s\n' "$question"
} >"$comment"
kata label add --workspace "$workspace" --as "$actor" "$uid" "$label" --agent
kata comment --workspace "$workspace" --as "$actor" "$uid" --body-file "$comment" --agent
jq -n --arg run "$run_id" --arg uid "$uid" --arg qualified "$qualified_id" --arg reason "$reason" --arg label "$label" \
  --arg branch "$branch" --arg base "$base_commit" --arg wip "$wip_commit" --arg start "$start_branch" --arg question "$question" \
  '{run_id:$run,issue_uid:$uid,qualified_id:$qualified,reason:$reason,label:$label,branch:$branch,base_commit:$base,
    wip_commit:(if $wip == "" then null else $wip end),start_branch:$start,
    question:(if $question == "" then null else $question end)}' >"$TRACKER_RUN_DIR/handoff.json.tmp"
mv "$TRACKER_RUN_DIR/handoff.json.tmp" "$TRACKER_RUN_DIR/handoff.json"
# The warm-continue override belongs to this run's worker; the next run starts from the base budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
printf 'handoff-ok\n'
exit 1
