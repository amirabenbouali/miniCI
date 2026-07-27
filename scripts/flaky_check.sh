#!/usr/bin/env bash
set -euo pipefail

state_file="${MINI_CI_STATE_FILE:?MINI_CI_STATE_FILE is required}"
failures_before_success="${FAILURES_BEFORE_SUCCESS:?FAILURES_BEFORE_SUCCESS is required}"

if [[ -f "$state_file" ]]; then
  attempt_count="$(cat "$state_file")"
else
  attempt_count="0"
fi

attempt_count="$((attempt_count + 1))"
printf '%s\n' "$attempt_count" > "$state_file"

echo "Flaky check attempt ${attempt_count}"

if (( attempt_count <= failures_before_success )); then
  echo "Flaky check failing"
  exit 1
fi

echo "Flaky check passed"
