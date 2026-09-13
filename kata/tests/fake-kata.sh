#!/bin/sh
# ABOUTME: Supplies fixed kata CLI responses for shell unit tests.
# ABOUTME: Records selection and claim calls so tests can detect retry loops.
set -eu

printf '%s\n' "$1" >>.fake-kata-log
case "$1:${FAKE_KATA_MODE:-ready}" in
  next:ready|next:conflict)
    printf '%s\n' '{"kata_api_version":1,"issue":{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","short_id":"5fav","qualified_id":"demo#5fav","title":"Fix one thing","body":"Acceptance text","status":"open"}}'
    ;;
  next:empty)
    printf '%s\n' '{"kata_api_version":1,"issue":null}'
    ;;
  claim:ready)
    printf 'claim %s\n' '01ARZ3NDEKTSV4RRFFQ69G5FAV' >.fake-kata-log
    printf '%s\n' '{"kata_api_version":1,"issue":{"uid":"01ARZ3NDEKTSV4RRFFQ69G5FAV","short_id":"5fav","owner":"kata-pipeline-test"}}'
    ;;
  claim:conflict)
    printf 'claim %s\n' '01ARZ3NDEKTSV4RRFFQ69G5FAV' >>.fake-kata-log
    printf '%s\n' 'claim failed: already owned' >&2
    exit 5
    ;;
  *) printf 'unexpected fake kata call: %s\n' "$*" >&2; exit 2 ;;
esac
