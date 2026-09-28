#!/usr/bin/env bash
# Delete one environment and purge soft-deleted Key Vault / App Configuration
# so the same names can be reused on the next deployment.
# Works even if the last deployment failed (does not rely on deployment outputs).
#   ./scripts/teardown.sh dev
source "$(dirname "$0")/common.sh" "${1:-dev}"

RG="rg-claimshub-${ENV_NAME}"

if [[ "$(az group exists -n "$RG")" != "true" ]]; then
  echo "   Resource group $RG does not exist - nothing to delete."
else
  # Record names and region BEFORE deleting, for the purge step.
  KVS=$(az keyvault list -g "$RG" --query "[].{n:name,l:location}" -o tsv)
  APPCSS=$(az appconfig list -g "$RG" --query "[].{n:name,l:location}" -o tsv)

  step "Deleting resource group $RG (takes several minutes)"
  az group delete -n "$RG" --yes
  ok "Resource group deleted"

  while read -r name loc; do
    [[ -z "$name" ]] && continue
    step "Purging soft-deleted Key Vault $name"
    az keyvault purge --name "$name" --location "$loc" 2>/dev/null && ok "purged" || echo "   (nothing to purge)"
  done <<< "$KVS"

  while read -r name loc; do
    [[ -z "$name" ]] && continue
    step "Purging soft-deleted App Configuration $name"
    az appconfig purge --name "$name" --location "$loc" --yes 2>/dev/null && ok "purged" || echo "   (nothing to purge)"
  done <<< "$APPCSS"
fi

az deployment sub delete -n "$DEPLOYMENT_NAME" >/dev/null 2>&1 || true
ok "Environment $ENV_NAME removed"
