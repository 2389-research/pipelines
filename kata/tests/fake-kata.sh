#!/bin/sh
# ABOUTME: Supplies fixed kata CLI responses for shell unit tests.
# ABOUTME: Records selection and claim calls so tests can detect retry loops.
set -eu

printf '%s\n' "$*" >>.fake-kata-log
if [ "$1" = ready ] && [ "${FAKE_READY_JSON+x}" = x ]; then
  printf '%s\n' "$FAKE_READY_JSON"
  exit
fi
case "$1:${FAKE_KATA_MODE:-ready}" in
  ready:ready|ready:conflict)
    printf '%s\n' '{"issues":[{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","short_id":"5fav","qualified_id":"demo#5fav","status":"open"}]}'
    ;;
  ready:empty)
    printf '%s\n' '{"issues":[]}'
    ;;
  claim:ready)
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '--if-unowned' ]; then shift; uid=$1; break; fi
      shift
    done
    jq -n --arg uid "$uid" '{issue:{uid:$uid,owner:"kata-pipeline-test"}}'
    ;;
  claim:conflict)
    printf '%s\n' 'claim failed: already owned' >&2
    exit 5
    ;;
  *) printf 'unexpected fake kata call: %s\n' "$*" >&2; exit 2 ;;
esac
