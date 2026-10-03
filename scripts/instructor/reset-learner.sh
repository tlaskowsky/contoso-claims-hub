#!/usr/bin/env bash
# Reset a learner's environment, KEEPING the App Service plans, the resource
# group, the learner's access and the governance policy assignments.
#   ./scripts/instructor/reset-learner.sh s03 all
set -uo pipefail
ID="${1:?Usage: reset-learner.sh <learnerId> <dev|test|all>}"
WHICH="${2:?Usage: reset-learner.sh <learnerId> <dev|test|all>}"
case "$WHICH" in all) ENVS="dev test";; dev|test) ENVS="$WHICH";; *) echo "dev, test or all"; exit 1;; esac

# Resource types are reported with varying case (serverFarms / serverfarms): compare case-insensitively.
non_plans() { az resource list -g "$1" --query "[].[type, id]" -o tsv | grep -viE '^Microsoft\.Web/serverfarms' | cut -f2; }
apps()      { az resource list -g "$1" --query "[].[type, id]" -o tsv | grep -iE '^Microsoft\.Web/sites\b' | grep -viE '/slots/' | cut -f2; }
plans()     { az resource list -g "$1" --query "[].[type, name]" -o tsv | grep -iE '^Microsoft\.Web/serverfarms' | cut -f2 | tr '\n' ' '; }

for ENV in $ENVS; do
  RG="rg-claimshub-$ID-$ENV"
  echo; echo "== Resetting $RG (keeping App Service plans)"
  if [[ "$(az group exists -n "$RG")" != "true" ]]; then echo "   $RG does not exist - skipped"; continue; fi
  echo "   plans before: $(plans "$RG")"

  # 1. Apps first, one at a time (parallel deletes of apps cause lock conflicts).
  for app in $(apps "$RG"); do
    echo "   deleting app ${app##*/}"
    az resource delete --ids "$app" --only-show-errors >/dev/null 2>&1 || true
  done

  # 2. Everything else except plans, in passes.
  for pass in 1 2 3 4 5 6 7 8; do
    ids=$(non_plans "$RG")
    [[ -z "$ids" ]] && break
    echo "   pass $pass: $(echo "$ids" | wc -l) resources"
    echo "$ids" | xargs -P 8 -I{} sh -c 'az resource delete --ids "{}" --only-show-errors >/dev/null 2>&1 || true'
    sleep 20
  done

  left=$(non_plans "$RG" | wc -l)
  kept=$(plans "$RG")
  if [[ "$left" == "0" ]]; then echo "   OK emptied; plans kept: ${kept:-none}"; else echo "   FAIL $left resources remain - rerun"; fi

  for kv in $(az keyvault list-deleted --query "[?contains(name, '-$ID-$ENV-')].name" -o tsv 2>/dev/null); do
    az keyvault purge --name "$kv" >/dev/null 2>&1 && echo "   OK purged Key Vault $kv"
  done
  for cs in $(az appconfig list-deleted --query "[?contains(name, '-$ID-$ENV-')].name" -o tsv 2>/dev/null); do
    az appconfig purge --name "$cs" --yes >/dev/null 2>&1 && echo "   OK purged App Configuration $cs"
  done
  for d in $(az deployment group list -g "$RG" --query "[].name" -o tsv); do
    az deployment group delete -g "$RG" -n "$d" >/dev/null 2>&1
  done
  echo "   OK deployment history cleared"
done
