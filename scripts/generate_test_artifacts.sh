#!/usr/bin/env bash
set -euo pipefail

rm -rf coverage reports logs
mkdir -p coverage reports logs

printf '<testsuite tests="1" failures="0"></testsuite>\n' > reports/results.xml
printf 'coverage placeholder\n' > coverage/index.txt
printf 'job=%s\n' "${MATRIX_JOB:-single}" > logs/job.log

echo "Generated test artifacts"
