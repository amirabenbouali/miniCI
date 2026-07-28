#!/usr/bin/env bash
set -euo pipefail

rm -rf logs
mkdir -p logs
printf 'failure log for %s\n' "${MATRIX_JOB:-single}" > logs/failure.log
echo "Generated failure log"
exit 1
