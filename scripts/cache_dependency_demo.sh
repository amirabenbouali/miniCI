#!/usr/bin/env bash
set -euo pipefail

mkdir -p tmp/dependencies

if [[ -f tmp/dependencies/demo-package.txt ]]; then
  echo "Using cached dependency"
else
  echo "Installing demo dependency"
  printf "installed\n" > tmp/dependencies/demo-package.txt
fi

