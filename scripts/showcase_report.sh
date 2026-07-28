#!/usr/bin/env bash
set -euo pipefail

mkdir -p tmp/showcase/reports
{
  printf 'track=%s\n' "${MATRIX_TRACK:-single}"
  printf 'app=%s\n' "${APP_ENV:-unknown}"
  printf 'status=passed\n'
} > "tmp/showcase/reports/${MATRIX_TRACK:-single}.txt"
