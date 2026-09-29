#!/usr/bin/env bash
# Deploy (or update) the infrastructure into your pre-created resource group.
#   export LEARNER_ID=s01
#   ./scripts/deploy-infra.sh dev                             # first pass
#   ./scripts/deploy-infra.sh dev --with-event-subscription   # after the apps are deployed
# Optional env vars: ALERT_EMAIL, NAME_SEED
source "$(dirname "$0")/common.sh" "${1:-dev}"

EVENT_SUB=false
[[ "${2:-}" == "--with-event-subscription" ]] && EVENT_SUB=true

if [[ "$(az group exists -n "$RG")" != "true" ]]; then
  fail "Resource group $RG not found. Check LEARNER_ID ($LEARNER_ID) or ask the instructor."
  exit 1
fi
ADMIN_ID=$(az ad signed-in-user show --query id -o tsv)

step "Deploying $DEPLOYMENT_NAME into $RG (event subscription: $EVENT_SUB)"
az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$REPO_ROOT/infra/main.bicep" \
  --parameters "@$PARAM_FILE" \
  --parameters learnerId="$LEARNER_ID" \
               adminPrincipalId="$ADMIN_ID" \
               deployEventSubscription="$EVENT_SUB" \
               alertEmail="${ALERT_EMAIL:-}" \
               nameSeed="${NAME_SEED:-}" \
  --query "properties.outputs" -o json
ok "Infrastructure deployed"
