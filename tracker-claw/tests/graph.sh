#!/bin/sh
# ABOUTME: Verifies the tracker-claw workflow's parsed routes and bounded agent configuration.
# ABOUTME: Proves execution needs explicit approval and every human choice fails safe.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
workflow="$pipeline_dir/agent.dip"
test_root=$(mktemp -d)
cleanup() {
  cleanup_status=$1
  if [ "$cleanup_status" -eq 0 ]; then
    rm -rf "$test_root"
  else
    printf 'graph test logs retained at %s\n' "$test_root" >&2
  fi
}
trap 'cleanup $?' EXIT
trap 'exit 130' HUP INT TERM

dippin validate "$workflow"
check_json=$(dippin check --format json "$workflow")
printf '%s' "$check_json" | jq -e '
  .valid == true and .errors == 0 and .warnings == 0
' >/dev/null
tracker validate "$workflow" >"$test_root/tracker-validate" 2>&1

dippin simulate "$workflow" --all-paths >"$test_root/events" 2>"$test_root/paths"

# Inspect the parsed graph events: Execute has one incoming edge, the explicit Approve choice.
jq -se '
  [.[] | select(.event == "edge_traverse" and .to == "Execute")]
  | length > 0 and all(.from == "Approval" and .label == "Approve")
' "$test_root/events" >/dev/null

# Failure, revision, and next-task edges keep every retry or new task behind a fresh approval.
for edge in \
  '"from":"Propose","to":"Problem","condition":"ctx.outcome = fail"' \
  '"from":"RevisePlan","to":"Problem","condition":"ctx.outcome = fail"' \
  '"from":"Execute","to":"Remember","condition":"ctx.outcome = fail"' \
  '"from":"Remember","to":"Problem","condition":"ctx.outcome = fail"' \
  '"from":"Approval","to":"Feedback","label":"Revise"' \
  '"from":"Feedback","to":"RevisePlan"' \
  '"from":"RevisePlan","to":"Approval","condition":"ctx.outcome = success","restart":true' \
  '"from":"Review","to":"Request","label":"Next task","restart":true' \
  '"from":"Request","to":"Propose"'; do
  grep -F "$edge" "$test_root/events" >/dev/null || {
    printf 'parsed workflow lacks edge %s\n' "$edge" >&2
    exit 1
  }
done

grep -E '^[[:space:]]*Problem -> Stop .*label: Stop .*override: true$' "$workflow" >/dev/null
grep -E '^[[:space:]]*Problem -> Request .*label: "New request" .*restart: true .*override: true$' "$workflow" >/dev/null

# Every choice gate lists Stop first. Tracker and Dippin choose the declared default on automation.
for gate in Approval Review Problem; do
  first=$(jq -sr --arg gate "$gate" '
    [.[] | select(.event == "edge_traverse" and .from == $gate)][0].label
  ' "$test_root/events")
  [ "$first" = Stop ] || {
    printf '%s lists %s first, want Stop\n' "$gate" "$first" >&2
    exit 1
  }
done

# Agent entries expose inherited planning identity and Execute's explicit worker override.
if ! jq -se '
  [.[] | select(.event == "node_enter" and .kind == "agent")]
  | (map(.node) | unique | length) == 4
  and all(.provider == "openai-compat")
  and all(if .node == "Execute" then .model == "glm-5.3"
          else .model == "deepseek-4.1-flash" end)
' "$test_root/events" >/dev/null; then
  printf 'parsed agents must use deepseek-4.1-flash except glm-5.3 Execute, all via openai-compat\n' >&2
  exit 1
fi

# Dippin's event format does not expose these safety attrs, so check their authored declarations.
agent_count=$(awk '$1 == "agent" { count++ } END { print count + 0 }' "$workflow")
native_count=$(awk '$1 == "backend:" && $2 == "native" { count++ } END { print count + 0 }' "$workflow")
turn_count=$(awk '$1 == "max_turns:" && $2 ~ /^[1-9][0-9]*$/ { count++ } END { print count + 0 }' "$workflow")
[ "$agent_count" -eq 4 ]
[ "$native_count" -eq "$agent_count" ]
[ "$turn_count" -eq "$agent_count" ]

tool_free=$(awk '
  $1 == "agent" { agent = $2 }
  $1 == "tool_access:" && $2 == "none" { safe[agent] = 1 }
  END {
    planners = safe["Propose"] + safe["RevisePlan"] + safe["Remember"]
    print planners ":" (safe["Execute"] + 0)
  }
' "$workflow")
[ "$tool_free" = 3:0 ]

grep -Eq '^[[:space:]]*retry_policy:[[:space:]]*none$' "$workflow"
if grep -Eq '^[[:space:]]*max_retries:' "$workflow"; then
  printf 'agent.dip must not override the no-retry policy with max_retries\n' >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*fallback(_retry)?_target:' "$workflow"; then
  printf 'agent.dip must not add an execution fallback or retry target\n' >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*Review ->.*override:[[:space:]]*true' "$workflow"; then
  printf 'Review cannot override the multi-hop Execute goal gate\n' >&2
  exit 1
fi

max_restarts=$(awk '$1 == "max_restarts:" && $2 ~ /^[1-9][0-9]*$/ { print $2 }' "$workflow")
[ -n "$max_restarts" ]

grep -F "\${ctx.response.Remember}" "$workflow" >/dev/null
grep -F "\${ctx.response.Feedback}" "$workflow" >/dev/null
grep -F "\${ctx.response.Execute}" "$workflow" >/dev/null

goal_gates=$(awk '
  $1 == "agent" { agent = $2 }
  $1 == "goal_gate:" && $2 == "true" { gated[agent] = 1 }
  END {
    print (gated["Propose"] + 0) ":" (gated["RevisePlan"] + 0) ":" \
      (gated["Execute"] + 0) ":" (gated["Remember"] + 0)
  }
' "$workflow")
[ "$goal_gates" = 1:1:1:0 ] || {
  printf 'goal gates Propose:RevisePlan:Execute:Remember = %s, want 1:1:1:0\n' "$goal_gates" >&2
  exit 1
}

[ "$(grep -Fc 'Keep the proposal under 200 words' "$workflow")" -eq 2 ]
grep -F 'model: glm-5.3' "$workflow" >/dev/null
grep -F 'approved objective, actions, and targets' "$workflow" >/dev/null
grep -F 'Treat the original request as historical context' "$workflow" >/dev/null
grep -F "execution report's approved scope is authoritative" "$workflow" >/dev/null
grep -F 'revised away' "$workflow" >/dev/null
grep -F 'under 500 words' "$workflow" >/dev/null

for gate in Approval Review Problem; do
  awk -v gate="$gate" '
    $1 == "human" { in_gate = ($2 == gate) }
    in_gate && $1 == "default:" && $2 == "Stop" { found = 1 }
    END { exit !found }
  ' "$workflow"
done

printf 'ok - parsed routes, safe defaults, and agent bounds\n'
