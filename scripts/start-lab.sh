#!/usr/bin/env bash
# Put a lab's START version (with TODOs) into your workspace.
#   ./scripts/start-lab.sh 1.3
# Your previous workspace is kept in workspace.bak-<time>. Starting a lab
# always gives you a clean, known-good base - the previous lab's solution
# plus this lab's new pieces - even if you didn't finish the last one.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${1:?Usage: start-lab.sh <lab number, e.g. 1.3>}"
SRC="$REPO_ROOT/labs/lab-$LAB/${MODE:-start}/infra"
[[ -d "$SRC" ]] || { echo "No such lab: $LAB  (available: $(ls "$REPO_ROOT/labs" | sed 's/lab-//' | tr '\n' ' '))"; exit 1; }
if [[ -d "$REPO_ROOT/workspace/infra" ]]; then
  mv "$REPO_ROOT/workspace" "$REPO_ROOT/workspace.bak-$(date +%H%M%S)"
fi
mkdir -p "$REPO_ROOT/workspace"
cp -r "$SRC" "$REPO_ROOT/workspace/infra"
echo "Lab $LAB (${MODE:-start}) is in workspace/infra"
if [[ "${MODE:-start}" == "start" ]]; then
  echo "Your TODOs:"
  grep -rn "TODO (Lab $LAB)" "$REPO_ROOT/workspace/infra" | sed "s#$REPO_ROOT/##; s/^/   /" || echo "   (none - see the lab guide)"
fi
