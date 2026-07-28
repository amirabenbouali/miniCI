#!/usr/bin/env bash
set -euo pipefail

job="${MATRIX_JOB:-single}"
output_dir="matrix-artifacts/${job}"

rm -rf "$output_dir"
mkdir -p "$output_dir/reports" "$output_dir/logs"

printf '<testsuite job="%s"></testsuite>\n' "$job" > "$output_dir/reports/results.xml"
printf 'job=%s\n' "$job" > "$output_dir/logs/job.log"

echo "Generated matrix artifacts for $job"
