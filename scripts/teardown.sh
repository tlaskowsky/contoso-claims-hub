#!/usr/bin/env bash
# Remove everything from one of your environments, keeping the (pre-created)
# resource group and your access to it.
#   ./scripts/teardown.sh test
# Deleted Key Vaults and App Configuration stores stay soft-deleted; the
# instructor purges them at the end of the course. If you need to redeploy the
# same environment afterwards, set a new name seed first: export NAME_SEED=2
source "$(dirname "$0")/common.sh" "${1:-dev}"

if [[ "$(az group exists -n "$RG")" != "true" ]]; then
  echo "   Resource group $RG does not exist - nothing to delete."; exit 0
fi

step "Deleting all resources in $RG (the resource group itself is kept)"
for pass in 1 2 3 4 5 6; do
  ids=$(az resource list -g "$RG" --query "[].id" -o tsv)
  [[ -z "$ids" ]] && break
  echo "   pass $pass: $(echo "$ids" | wc -l) resources"
  # Delete in parallel; dependent resources fail on early passes and succeed later.
  echo "$ids" | xargs -P 8 -I{} sh -c 'az resource delete --ids "{}" --only-show-errors >/dev/null 2>&1 || true'
done

left=$(az resource list -g "$RG" --query "length(@)" -o tsv)
if [[ "$left" == "0" ]]; then ok "$RG is empty"; else fail "$left resources could not be deleted - check the portal"; fi

# Purging needs subscription-level rights: works for the instructor, skipped for learners.
for kv in $(az keyvault list-deleted --query "[?contains(name, '-${LEARNER_ID}-${ENV_NAME}-')].name" -o tsv 2>/dev/null); do
  az keyvault purge --name "$kv" 2>/dev/null && ok "purged Key Vault $kv" || true
done
az deployment group delete -g "$RG" -n "$DEPLOYMENT_NAME" >/dev/null 2>&1 || true
