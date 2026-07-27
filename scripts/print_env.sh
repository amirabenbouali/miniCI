#!/usr/bin/env bash
set -euo pipefail

printf 'APP_ENV=%s\n' "${APP_ENV:-missing}"
printf 'LOG_LEVEL=%s\n' "${LOG_LEVEL:-missing}"
printf 'SHARED_VALUE=%s\n' "${SHARED_VALUE:-missing}"
