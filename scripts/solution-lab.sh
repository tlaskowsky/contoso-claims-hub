#!/usr/bin/env bash
# Put a lab's SOLUTION into your workspace (to catch up, or to compare).
#   ./scripts/solution-lab.sh 1.3
# Your current workspace is kept in workspace.bak-<time>.
MODE=solution exec "$(dirname "$0")/start-lab.sh" "$@"
