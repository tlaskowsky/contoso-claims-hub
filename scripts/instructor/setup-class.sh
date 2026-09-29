#!/usr/bin/env bash
# Instructor: prepare the shared training subscription for a class.
# Run once, a day or two before class, as a subscription Owner who can invite guests.
#   ./scripts/instructor/setup-class.sh learners.csv
#
# For each learner (learnerId,email) it:
#   - invites the email address as a guest user (unless "self")
#   - creates rg-claimshub-<id>-dev, -test and -shell (Cloud Shell storage)
#   - makes the learner Owner of those three resource groups only
#   - grants App Configuration Data Owner on dev and test in advance
#     (avoids the first-deployment "Forbidden" on App Configuration key-values)
# Safe to re-run: existing groups, users and assignments are left as they are.
set -euo pipefail
CSV="${1:?Usage: setup-class.sh learners.csv}"
LOCATION="${LOCATION:-centralus}"
SUB=$(az account show --query id -o tsv)
step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   OK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m   WARN\033[0m %s\n' "$*"; }

step "Registering resource providers"
for p in Microsoft.App Microsoft.Web Microsoft.DocumentDB Microsoft.ServiceBus Microsoft.EventGrid \
         Microsoft.KeyVault Microsoft.AppConfiguration Microsoft.Storage Microsoft.Network \
         Microsoft.Insights Microsoft.OperationalInsights Microsoft.ManagedIdentity \
         Microsoft.PolicyInsights Microsoft.Quota Microsoft.CloudShell; do
  az provider register --namespace "$p" --only-show-errors >/dev/null
done
ok "registration requested (completes in the background)"

assign() { # <objectId> <role> <scope>
  for attempt in 1 2 3 4 5; do
    out=$(az role assignment create --assignee-object-id "$1" --assignee-principal-type User \
          --role "$2" --scope "$3" --only-show-errors 2>&1) && return 0
    [[ "$out" == *"RoleAssignmentExists"* || "$out" == *"already exists"* ]] && return 0
    sleep 15   # a newly invited guest can take a moment to replicate
  done
  warn "could not assign $2 on $3: $out"
}

resolve_user() { # <email> -> object id (invites a guest if needed)
  local email=$1 oid
  oid=$(az ad user list --filter "mail eq '$email'" --query "[0].id" -o tsv 2>/dev/null)
  if [[ -z "$oid" ]]; then
    oid=$(az rest --method POST --url "https://graph.microsoft.com/v1.0/invitations" \
      --headers "Content-Type=application/json" \
      --body "{\"invitedUserEmailAddress\":\"$email\",\"inviteRedirectUrl\":\"https://portal.azure.com\",\"sendInvitationMessage\":true}" \
      --query "invitedUser.id" -o tsv)
  fi
  echo "$oid"
}

SUMMARY=()
while IFS=, read -r id email; do
  id=$(echo "$id" | tr -d '[:space:]'); email=$(echo "${email:-}" | tr -d '[:space:]')
  [[ -z "$id" || "$id" == \#* || "$id" == "learnerId" ]] && continue
  if [[ ! "$id" =~ ^[a-z][0-9]{2}$ ]]; then warn "skipping invalid learner ID '$id'"; continue; fi

  step "Learner $id ($email)"
  if [[ "$email" == "self" ]]; then oid=$(az ad signed-in-user show --query id -o tsv)
  else oid=$(resolve_user "$email"); fi
  [[ -z "$oid" ]] && { warn "could not resolve $email"; continue; }
  ok "user object ID $oid"

  for env in dev test shell; do
    rg="rg-claimshub-$id-$env"
    az group create -n "$rg" -l "$LOCATION" --tags workload=claimshub environment="$env" owner="$id" learner="$id" \
      --only-show-errors -o none
    assign "$oid" "Owner" "/subscriptions/$SUB/resourceGroups/$rg"
    [[ "$env" != "shell" ]] && assign "$oid" "App Configuration Data Owner" "/subscriptions/$SUB/resourceGroups/$rg"
  done
  ok "rg-claimshub-$id-{dev,test,shell} ready"
  SUMMARY+=("$id  $email  $oid")
done < "$CSV"

step "Summary"
printf '   %s\n' "${SUMMARY[@]}"
echo
echo "   Next: run ./scripts/instructor/check-quotas.sh ${#SUMMARY[@]}"
echo "   Guests must accept their invitation email before class (they sign in to https://portal.azure.com)."
