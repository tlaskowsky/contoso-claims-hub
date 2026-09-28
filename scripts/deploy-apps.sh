#!/usr/bin/env bash
# Build and deploy the three applications.
#   ./scripts/deploy-apps.sh dev
source "$(dirname "$0")/common.sh" "${1:-dev}"

RG=$(output resourceGroupName)
API_APP=$(output apiAppName)
VAL_APP=$(output validationFunctionAppName)
PROC_APP=$(output processingFunctionAppName)

# --- Claims Intake API (App Service): build locally, zip-deploy dist + prod deps
step "Building Claims Intake API"
pushd "$REPO_ROOT/src/api" >/dev/null
npm install --no-audit --no-fund
npm run build
STAGE=$(mktemp -d)
cp -r dist package.json "$STAGE/"
(cd "$STAGE" && npm install --omit=dev --no-audit --no-fund >/dev/null && zip -qr api.zip .)
step "Deploying Claims Intake API to $API_APP"
az webapp deploy -g "$RG" -n "$API_APP" --src-path "$STAGE/api.zip" --type zip
rm -rf "$STAGE"
popd >/dev/null
ok "API deployed"

# --- Function apps (Flex Consumption): Core Tools publish.
# Flex publishes without a remote build, so production dependencies are
# packaged locally (node_modules is included; dev tools are pruned).
for pair in "functions-validation:$VAL_APP" "functions-processing:$PROC_APP"; do
  dir="${pair%%:*}"; app="${pair##*:}"
  step "Building and publishing $dir to $app"
  pushd "$REPO_ROOT/src/$dir" >/dev/null
  # Core Tools reads the worker runtime from local.settings.json (git-ignored).
  if [[ ! -f local.settings.json ]]; then
    printf '%s\n' '{' '  "IsEncrypted": false,' '  "Values": {' '    "FUNCTIONS_WORKER_RUNTIME": "node",' '    "AzureWebJobsStorage": ""' '  }' '}' > local.settings.json
  fi
  npm install --no-audit --no-fund
  npm run build
  npm prune --omit=dev
  func azure functionapp publish "$app"
  popd >/dev/null
  ok "$app published"
done

step "Functions registered"
for app in "$VAL_APP" "$PROC_APP"; do
  az functionapp function list -g "$RG" -n "$app" --query "[].name" -o tsv
done
