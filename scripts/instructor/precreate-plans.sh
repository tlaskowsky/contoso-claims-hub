#!/usr/bin/env bash
# Instructor: pre-create every learner's App Service / Flex Consumption plans,
# slowly, before class. Azure throttles App Service plan *creation* per
# subscription and region (new subscriptions especially; the throttle can last
# up to 48 hours). When learners deploy, their plans already exist, so the
# deployment only *updates* them.
#
#   ./scripts/instructor/precreate-plans.sh learners.csv            # dev + test plans
#   ./scripts/instructor/precreate-plans.sh learners.csv dev        # dev plans only
#   DELAY=120 ./scripts/instructor/precreate-plans.sh learners.csv  # seconds between creations (default 90)
#
# Cost: Flex Consumption plans cost nothing while idle. S1 (dev) and B1 (test)
# plans are billed from creation, so run this the DAY BEFORE class.
# Safe to re-run: plans that already exist are skipped.
#
# Names, SKUs and properties must match infra/modules/appservice.bicep and
# functionapp.bicep, and infra/main.bicep's naming (asp-claimshub-<role>-<id>-<env>).
set -uo pipefail
CSV="${1:?Usage: precreate-plans.sh learners.csv [dev|test|all]}"
WHICH="${2:-all}"
DELAY="${DELAY:-90}"
SUB=$(az account show --query id -o tsv)
API="2024-04-01"
ok()   { printf '\033[1;32m   OK\033[0m %s\n' "$*"; }
skip() { printf '   --  %s\n' "$*"; }
warn() { printf '\033[1;33m   WARN\033[0m %s\n' "$*"; }

case "$WHICH" in dev) ENVS="dev" ;; test) ENVS="test" ;; *) ENVS="dev test" ;; esac
sku_for() { [[ "$1" == "dev" ]] && echo S1 || echo B1; }   # matches infra/parameters/*.json

create_plan() { # <rg> <name> <json body>
  local url="https://management.azure.com/subscriptions/$SUB/resourceGroups/$1/providers/Microsoft.Web/serverfarms/$2?api-version=$API"
  if az rest --method get --url "$url" -o none 2>/dev/null; then skip "$2 exists"; return 0; fi
  for attempt in 1 2 3 4 5 6; do
    out=$(az rest --method put --url "$url" --headers "Content-Type=application/json" --body "$3" -o none 2>&1) && { ok "$2 created"; sleep "$DELAY"; return 0; }
    if [[ "$out" == *"throttled"* || "$out" == *"429"* ]]; then
      warn "$2: creation throttled (attempt $attempt); waiting 10 minutes"; sleep 600
    else
      warn "$2: $out"; return 1
    fi
  done
  warn "$2: still throttled after 6 attempts - stop here, rerun later (existing plans are skipped)"; return 1
}

while IFS=, read -r id _; do
  id=$(echo "$id" | tr -d '[:space:]')
  [[ -z "$id" || "$id" == \#* || "$id" == "learnerId" ]] && continue
  for env in $ENVS; do
    rg="rg-claimshub-$id-$env"
    loc=$(az group show -n "$rg" --query location -o tsv 2>/dev/null) || { warn "$rg not found - run setup-class.sh first"; continue; }
    tags="{\"workload\":\"claimshub\",\"environment\":\"$env\",\"owner\":\"$id\",\"learner\":\"$id\",\"managedBy\":\"bicep\"}"
    echo "== $id $env ($loc)"
    create_plan "$rg" "asp-claimshub-api-$id-$env" \
      "{\"location\":\"$loc\",\"kind\":\"linux\",\"sku\":{\"name\":\"$(sku_for $env)\"},\"properties\":{\"reserved\":true},\"tags\":$tags}" || exit 1
    for role in val proc; do
      create_plan "$rg" "asp-claimshub-$role-$id-$env" \
        "{\"location\":\"$loc\",\"kind\":\"functionapp\",\"sku\":{\"name\":\"FC1\",\"tier\":\"FlexConsumption\"},\"properties\":{\"reserved\":true},\"tags\":$tags}" || exit 1
    done
  done
done < "$CSV"
echo; echo "== Done. Learners' deployments will now update these plans instead of creating them."
