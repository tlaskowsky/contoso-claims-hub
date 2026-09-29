#!/usr/bin/env bash
# Instructor: check that the subscription can hold N learner environments.
#   ./scripts/instructor/check-quotas.sh 17        (16 learners + instructor)
# Each learner has a dev environment (S1, Private Endpoints) and, during Lab 3.3,
# a test environment (B1, no Private Endpoints).
set -uo pipefail
N="${1:?Usage: check-quotas.sh <number of learners incl. instructor>}"
LOCATION="${LOCATION:-centralus}"
SUB=$(az account show --query id -o tsv)
pass() { printf '\033[1;32m   PASS\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m   WARN\033[0m %s\n' "$*"; }
failm(){ printf '\033[1;31m   FAIL\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0
echo "== Quota check for $N learners in $LOCATION (subscription $(az account show --query name -o tsv))"

# --- App Service instances (the tight one) ------------------------------------------
echo; echo "App Service (instances per tier, region $LOCATION)"
USAGE=$(az rest --method get --only-show-errors \
  --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Web/locations/$LOCATION/providers/Microsoft.Quota/usages?api-version=2023-02-01" 2>/dev/null)
LIMITS=$(az rest --method get --only-show-errors \
  --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Web/locations/$LOCATION/providers/Microsoft.Quota/quotas?api-version=2023-02-01" 2>/dev/null)
check_tier() { # <tier> <needed>
  local used limit
  used=$(echo "$USAGE"  | jq -r --arg t "$1" '[.value[]? | select(.properties.name.value==$t or .properties.name.localizedValue==($t+" VMs"))][0].properties.usages.value // empty')
  limit=$(echo "$LIMITS" | jq -r --arg t "$1" '[.value[]? | select(.properties.name.value==$t or .properties.name.localizedValue==($t+" VMs"))][0].properties.limit.value // empty')
  if [[ -z "$limit" ]]; then
    warn "$1: could not read the quota automatically. Portal > Quotas > App Service > $LOCATION > '$1 VMs' must allow $2 more."
  elif (( limit - ${used:-0} >= $2 )); then pass "$1: need $2, available $((limit - ${used:-0})) (limit $limit, used ${used:-0})"
  else failm "$1: need $2, available $((limit - ${used:-0})) (limit $limit). Request an increase."; fi
}
check_tier S1 "$N"
check_tier B1 "$N"
echo "   (Autoscale can add up to $N more S1 instances only if CPU stays above 70%; lab traffic does not.)"

# --- Counted resources ---------------------------------------------------------------
echo; echo "Resource counts (current + needed <= limit)"
count() { az resource list --resource-type "$1" --query "length(@)" -o tsv 2>/dev/null || echo 0; }
check_count() { # <label> <current> <needed> <limit>
  if (( $2 + $3 <= $4 )); then pass "$1: $2 existing + $3 needed <= $4"; else failm "$1: $2 existing + $3 needed > $4"; fi
}
check_count "Cosmos DB accounts (subscription)"      "$(count Microsoft.DocumentDB/databaseAccounts)" $((N*2)) 50
check_count "Service Bus namespaces"                  "$(count Microsoft.ServiceBus/namespaces)"      $((N*2)) 1000
check_count "Event Grid system topics"                "$(count Microsoft.EventGrid/systemTopics)"     $((N*2)) 100
check_count "Storage accounts"                        "$(count Microsoft.Storage/storageAccounts)"    $((N*5)) 250
check_count "Private endpoints"                       "$(count Microsoft.Network/privateEndpoints)"   $((N*6)) 1000
RA=$(az role assignment list --all --query "length(@)" -o tsv 2>/dev/null || echo 0)
check_count "Role assignments (subscription)"         "$RA" $((N*2*25 + N*5)) 4000

# --- Flex Consumption memory (runtime quota, not checkable in advance) ----------------
echo; echo "Flex Consumption (regional memory quota: 512,000 MB)"
pass "at 512 MB per instance, $((N*2*2)) Function apps averaging 2 running instances use $((N*2*2*2*512)) MB"

# --- Providers -----------------------------------------------------------------------
echo; echo "Resource providers"
for p in Microsoft.App Microsoft.Web Microsoft.DocumentDB Microsoft.ServiceBus Microsoft.EventGrid Microsoft.KeyVault \
         Microsoft.AppConfiguration Microsoft.Storage Microsoft.Network Microsoft.Insights Microsoft.OperationalInsights \
         Microsoft.ManagedIdentity Microsoft.PolicyInsights; do
  st=$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null)
  [[ "$st" == "Registered" ]] && pass "$p" || failm "$p is '$st'"
done

echo
if (( FAILED )); then echo "== Some checks FAILED - fix them before class."; exit 1; else echo "== All automatic checks passed."; fi
