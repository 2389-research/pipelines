#!/bin/sh
# test_branch_model_ids.sh — enumerate every per-branch `model:` declaration
# in dev_loop.dip and reject any that isn't on the tracker-known allowlist.
#
# dippin's `checkNodeModelProvider` does not inspect per-branch overrides
# (review finding M3 on issue #40), so DIP108 silently passes typos. This
# script is the smoke-CI backstop.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIP="${DIR}/dev_loop.dip"

# Allowlist mirrors tracker's known-models hint (see `tracker validate <file>`
# output's "known models for <provider>" lines). Keep in sync.
ALLOWLIST="
claude-opus-4-7 claude-opus-4-6 claude-opus-4-5 claude-opus-4-1 claude-opus-4-0
claude-sonnet-4-6 claude-sonnet-4-5 claude-sonnet-4-0
claude-haiku-4-5 claude-haiku-3-5
gpt-5 gpt-5-mini gpt-5-nano gpt-5-pro
gpt-5.1 gpt-5.2 gpt-5.2-pro gpt-5.3-codex
gpt-5.4 gpt-5.4-mini gpt-5.4-nano gpt-5.4-pro
gpt-5.5 gpt-5.5-pro
gpt-4.1 gpt-4.1-mini gpt-4.1-nano gpt-4o gpt-4o-mini
o3 o3-mini o3-pro o4-mini
gemini-2.0-flash gemini-2.5-flash gemini-2.5-flash-lite gemini-2.5-pro
gemini-3-flash-preview
gemini-3.1-flash-lite gemini-3.1-flash-lite-preview gemini-3.1-pro-preview
gemini-3.1-pro-preview-customtools
"

# Extract every `model: <id>` line (node-level or branch-level).
models=$(grep -oE '^[[:space:]]*model:[[:space:]]*[A-Za-z0-9._-]+' "${DIP}" \
         | sed 's/.*model:[[:space:]]*//' | sort -u)

rc=0
for m in ${models}; do
  hit=0
  for ok in ${ALLOWLIST}; do
    if [ "${m}" = "${ok}" ]; then
      hit=1
      break
    fi
  done
  if [ "${hit}" -eq 0 ]; then
    printf 'FAIL: model %s is not on the tracker-known allowlist\n' "${m}" >&2
    rc=1
  fi
done

if [ "${rc}" -eq 0 ]; then
  count=$(printf '%s\n' "${models}" | wc -l)
  printf 'OK: %d unique model id(s) all on the tracker allowlist\n' "${count}"
fi

exit "${rc}"
