#!/usr/bin/env bash
set -euo pipefail

workspace="tmp/mini_ci_hooks"

rm -f "$workspace/marker.txt"
rmdir "$workspace" 2>/dev/null || true
echo "Cleaned example workspace at $workspace"
