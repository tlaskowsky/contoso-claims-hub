#!/usr/bin/env bash
# Shared helpers. Usage in other scripts: source "$(dirname "$0")/common.sh" <env>
set -euo pipefail

ENV_NAME="${1:-dev}"
DEPLOYMENT_NAME="claimshub-${ENV_NAME}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARAM_FILE="$REPO_ROOT/infra/parameters/${ENV_NAME}.parameters.json"

# Read one output of the subscription-scope deployment.
output() {
  az deployment sub show -n "$DEPLOYMENT_NAME" --query "properties.outputs.$1.value" -o tsv
}

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   OK\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m   FAIL\033[0m %s\n' "$*"; }
