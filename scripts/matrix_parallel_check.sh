#!/usr/bin/env bash
set -euo pipefail

job="${MATRIX_JOB:-unknown}"
delay="${MATRIX_DELAY:-1}"

printf 'Starting %s with delay %s\n' "$job" "$delay"
sleep "$delay"
printf 'Finished %s\n' "$job"
