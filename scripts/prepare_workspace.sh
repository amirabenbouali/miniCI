#!/usr/bin/env bash
set -euo pipefail

workspace="tmp/mini_ci_hooks"

mkdir -p "$workspace"
printf 'prepared\n' > "$workspace/marker.txt"
echo "Prepared example workspace at $workspace"
