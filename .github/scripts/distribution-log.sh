#!/bin/bash
# Only the stage reporter writes to the original output stream.
exec 3>&1 >/dev/null 2>&1

distribution_phase=
distribution_error=

distribution_finish() {
  local result="$1"
  if [[ -n "$distribution_phase" ]]; then
    if [[ "$result" == 0 ]]; then
      printf 'Distribution %s: succeeded\n' "$distribution_phase" >&3 || :
    else
      printf 'Distribution %s: failed (%s)\n' "$distribution_phase" "$distribution_error" >&3 || :
    fi
    distribution_phase=
  fi
}

distribution_stage() {
  distribution_finish 0
  distribution_phase="$1"
  distribution_error="$2"
  printf 'Distribution %s: started\n' "$distribution_phase" >&3 || :
}

trap 'distribution_finish "$?"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
