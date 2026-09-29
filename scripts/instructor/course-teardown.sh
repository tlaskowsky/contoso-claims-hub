#!/usr/bin/env bash
# Instructor: remove every learner environment after the course.
#   ./scripts/instructor/course-teardown.sh                      # delete resource groups + purge
#   ./scripts/instructor/course-teardown.sh learners.csv --remove-guests
set -uo pipefail
step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

RGS=$(az group list --query "[?starts_with(name, 'rg-claimshub-')].name" -o tsv)
echo "Resource groups to delete:"; echo "$RGS" | sed 's/^/   /'
read -r -p "Delete ALL of these? Type 'yes': " answer
[[ "$answer" == "yes" ]] || { echo "Cancelled."; exit 1; }

step "Deleting resource groups (in parallel)"
for rg in $RGS; do az group delete -n "$rg" --yes --no-wait; done
for i in $(seq 1 60); do
  left=$(az group list --query "length([?starts_with(name, 'rg-claimshub-')])" -o tsv)
  [[ "$left" == "0" ]] && break
  echo "   $left remaining..."; sleep 30
done

step "Purging soft-deleted Key Vaults and App Configuration stores"
for kv in $(az keyvault list-deleted --query "[?starts_with(name, 'kv-')].name" -o tsv); do
  az keyvault purge --name "$kv" --no-wait 2>/dev/null && echo "   purging $kv"
done
az appconfig list-deleted --query "[?starts_with(name, 'appcs-claimshub-')].[name, location]" -o tsv 2>/dev/null |
while read -r name loc; do az appconfig purge --name "$name" --location "$loc" --yes 2>/dev/null && echo "   purged $name"; done

if [[ "${2:-}" == "--remove-guests" && -n "${1:-}" ]]; then
  step "Removing guest users"
  while IFS=, read -r id email; do
    email=$(echo "${email:-}" | tr -d '[:space:]')
    [[ -z "$email" || "$email" == "self" || "$id" == \#* || "$id" == "learnerId" ]] && continue
    oid=$(az ad user list --filter "mail eq '$email'" --query "[0].id" -o tsv)
    [[ -n "$oid" ]] && az ad user delete --id "$oid" && echo "   removed $email"
  done < "$1"
fi
step "Done"
