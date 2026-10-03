#!/usr/bin/env bash
# Deploy (or update) the infrastructure into your pre-created resource group.
#   export LEARNER_ID=s01
#   ./scripts/deploy-infra.sh dev                             # first pass
#   ./scripts/deploy-infra.sh dev --with-event-subscription   # after the apps are deployed
# Optional env vars: ALERT_EMAIL, NAME_SEED
source "$(dirname "$0")/common.sh" "${1:-dev}"

EVENT_SUB=false
[[ "${2:-}" == "--with-event-subscription" ]] && EVENT_SUB=true

exists=$(az group exists -n "$RG" 2>/tmp/claimshub-az-err)
if [[ -z "$exists" ]]; then
  if grep -qiE "token|credential|login|authenticat" /tmp/claimshub-az-err; then
    fail "Azure sign-in problem (not a missing resource group). Run the command again; if it repeats, reload the portal page or restart Cloud Shell."
  else
    fail "Could not check resource group $RG: $(head -c 300 /tmp/claimshub-az-err)"
  fi
  exit 1
fi
if [[ "$exists" != "true" ]]; then
  fail "Resource group $RG not found. Check LEARNER_ID ($LEARNER_ID) and the subscription (az account show), or ask the instructor."
  exit 1
fi
[[ -f "$PARAM_FILE" ]] || { fail "Parameter file not found: $PARAM_FILE"; exit 1; }

# Pass only the parameters this lab's template declares.
PARAMS=$(az bicep build --file "$INFRA_DIR/main.bicep" --stdout 2>/dev/null | jq -r '.parameters | keys[]') || true
if [[ -z "$PARAMS" ]]; then
  fail "main.bicep does not compile - fix the TODOs first:  az bicep build --file $INFRA_DIR/main.bicep"
  exit 1
fi
has() { grep -qx "$1" <<< "$PARAMS"; }
EXTRA=(learnerId="$LEARNER_ID" nameSeed="${NAME_SEED:-}")
has adminPrincipalId        && EXTRA+=(adminPrincipalId="$(az ad signed-in-user show --query id -o tsv)")
has deployEventSubscription && EXTRA+=(deployEventSubscription="$EVENT_SUB")
has alertEmail              && EXTRA+=(alertEmail="${ALERT_EMAIL:-}")

step "Deploying $DEPLOYMENT_NAME into $RG from ${INFRA_DIR#$REPO_ROOT/} (event subscription: $EVENT_SUB)"
az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$INFRA_DIR/main.bicep" \
  --parameters "@$PARAM_FILE" \
  --parameters "${EXTRA[@]}" \
  --query "properties.outputs" -o json
ok "Infrastructure deployed"
