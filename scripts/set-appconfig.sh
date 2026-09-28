#!/usr/bin/env bash
# Change an App Configuration key-value or feature flag through Azure Resource
# Manager (Pass-through auth: your App Configuration Data Owner role is used).
#   ./scripts/set-appconfig.sh dev key  "ClaimsHub:LegacyPolicySystemOnline" true
#   ./scripts/set-appconfig.sh dev flag AutoApproveLowValue true
source "$(dirname "$0")/common.sh" "${1:-dev}"
KIND="${2:?key|flag}"; NAME="${3:?name}"; VALUE="${4:?value}"

RG=$(output resourceGroupName)
STORE=$(output appConfigName); require "$STORE" "App Configuration store"
STORE_ID=$(az appconfig show -g "$RG" -n "$STORE" --query id -o tsv)

encode() { local s="$1"; s="${s//\//~2F}"; s="${s//:/~3A}"; printf '%s' "$s"; }

if [[ "$KIND" == "flag" ]]; then
  KEY=".appconfig.featureflag/$NAME"
  CONTENT_TYPE="application/vnd.microsoft.appconfig.ff+json;charset=utf-8"
  FLAG_VALUE=$(jq -cn --arg id "$NAME" --argjson on "$VALUE" '{id:$id, description:"", enabled:$on, conditions:{client_filters:[]}}')
  BODY=$(jq -cn --arg v "$FLAG_VALUE" --arg ct "$CONTENT_TYPE" '{properties:{value:$v, contentType:$ct}}')
else
  KEY="$NAME"
  BODY=$(jq -cn --arg v "$VALUE" '{properties:{value:$v, contentType:"text/plain"}}')
fi

step "Setting $KEY = $VALUE (via Azure Resource Manager)"
az rest --method put \
  --url "https://management.azure.com${STORE_ID}/keyValues/$(encode "$KEY")?api-version=2024-05-01" \
  --body "$BODY" --query "properties.{key:key, value:value}" -o table
ok "Updated. Apps pick up the change within ~30 seconds."
