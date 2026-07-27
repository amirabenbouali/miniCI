#!/usr/bin/env bash
set -euo pipefail

ruby_version="${MATRIX_RUBY:-missing}"
database="${MATRIX_DATABASE:-missing}"

printf 'Ruby: %s\n' "$ruby_version"
printf 'Database: %s\n' "$database"

if [[ "$ruby_version" == "3.2" && "$database" == "postgres" ]]; then
  echo "Intentional matrix failure"
  exit 1
fi

echo "Matrix combination passed"
