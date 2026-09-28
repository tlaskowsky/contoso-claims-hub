#!/usr/bin/env bash
# Deploy (or update) the infrastructure for one environment.
#   ./scripts/deploy-infra.sh dev                             # first pass
#   ./scripts/deploy-infra.sh dev --with-event-subscription   # after code is published
# Optional env vars: ALERT_EMAIL, NAME_SEED, LOCKDOWN=false (keep data plane public)
source "$(dirname "$0")/common.sh" "${1:-dev}"

EVENT_SUB=false
[[ "${2:-}" == "--with-event-subscription" ]] && EVENT_SUB=true

ADMIN_ID=$(az ad signed-in-user show --query id -o tsv)
LOCATION=$(jq -r '.parameters.location.value' "$PARAM_FILE")

step "Deploying $DEPLOYMENT_NAME to $LOCATION (event subscription: $EVENT_SUB)"
az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$REPO_ROOT/infra/main.bicep" \
  --parameters "@$PARAM_FILE" \
  --parameters adminPrincipalId="$ADMIN_ID" \
               deployEventSubscription="$EVENT_SUB" \
               lockDownDataPlane="${LOCKDOWN:-true}" \
               alertEmail="${ALERT_EMAIL:-}" \
               nameSeed="${NAME_SEED:-}" \
  --query "properties.outputs" -o json
ok "Infrastructure deployed"
