#!/usr/bin/env bash
set -euo pipefail

test "${APP_ENV:-}" = "test"
test -n "${MATRIX_TRACK:-}"
printf 'checks passed for %s\n' "$MATRIX_TRACK"
