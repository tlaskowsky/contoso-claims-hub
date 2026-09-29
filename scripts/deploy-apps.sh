#!/usr/bin/env bash
# Deploy the three applications from ready-built packages.
#   ./scripts/deploy-apps.sh dev                  # learners: packages downloaded from the latest GitHub release
#   ./scripts/deploy-apps.sh dev --from-source    # instructor: build from src/ first (needs Node 22)
# Package source can be overridden with PACKAGES_URL=<base URL> or local files in ./packages/.
source "$(dirname "$0")/common.sh" "${1:-dev}"

PACKAGES_URL="${PACKAGES_URL:-https://github.com/tlaskowsky/contoso-claims-hub/releases/latest/download}"
PKG_DIR="$REPO_ROOT/packages"

API_APP=$(output apiAppName);                 require "$API_APP" "API App Service"
VAL_APP=$(output validationFunctionAppName);  require "$VAL_APP" "validation Function app"
PROC_APP=$(output processingFunctionAppName); require "$PROC_APP" "processing Function app"

# --- Get the packages ---------------------------------------------------------------
if [[ "${2:-}" == "--from-source" ]]; then
  "$REPO_ROOT/scripts/build-packages.sh"
elif [[ ! -f "$PKG_DIR/api.zip" || ! -f "$PKG_DIR/functions-validation.zip" || ! -f "$PKG_DIR/functions-processing.zip" ]]; then
  step "Downloading application packages"
  mkdir -p "$PKG_DIR"
  for f in api.zip functions-validation.zip functions-processing.zip; do
    curl -fsSL -o "$PKG_DIR/$f" "$PACKAGES_URL/$f" || { fail "Could not download $f from $PACKAGES_URL"; exit 1; }
    ok "$f"
  done
fi

# Retry helper: a brand-new app sometimes times out (HTTP 504) on its first deployment.
retry() { # <description> <command...>
  local what=$1; shift
  for attempt in 1 2 3; do
    if "$@"; then return 0; fi
    if [[ $attempt -eq 3 ]]; then fail "$what failed after 3 attempts"; exit 1; fi
    echo "   $what attempt $attempt failed; retrying in 30 seconds..."; sleep 30
  done
}

# --- Claims Intake API (App Service) ------------------------------------------------
step "Deploying Claims Intake API to $API_APP"
retry "API deployment" az webapp deploy -g "$RG" -n "$API_APP" --src-path "$PKG_DIR/api.zip" --type zip
ok "API deployed"

# --- Function apps (Flex Consumption) -----------------------------------------------
for pair in "functions-validation:$VAL_APP" "functions-processing:$PROC_APP"; do
  pkg="${pair%%:*}"; app="${pair##*:}"
  step "Deploying $pkg to $app"
  retry "$pkg deployment" az functionapp deployment source config-zip -g "$RG" -n "$app" --src "$PKG_DIR/$pkg.zip"
  ok "$app deployed"
done

step "Functions registered (may take a minute to appear)"
for app in "$VAL_APP" "$PROC_APP"; do
  for i in 1 2 3 4 5 6; do
    list=$(az functionapp function list -g "$RG" -n "$app" --query "[].name" -o tsv 2>/dev/null)
    [[ -n "$list" ]] && break
    sleep 10
  done
  echo "$app:"; echo "${list:-   (none yet - rerun: az functionapp function list -g $RG -n $app -o table)}" | sed 's/^/   /'
done
