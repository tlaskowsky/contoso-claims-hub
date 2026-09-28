#!/usr/bin/env bash
# Shared helpers. Usage in other scripts: source "$(dirname "$0")/common.sh" <env>
set -euo pipefail

ENV_NAME="${1:-dev}"
DEPLOYMENT_NAME="claimshub-${ENV_NAME}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARAM_FILE="$REPO_ROOT/infra/parameters/${ENV_NAME}.parameters.json"
RG="rg-claimshub-${ENV_NAME}"

# Look up a deployed resource by type and name prefix in the environment's
# resource group. This does not depend on the deployment record, so it works
# even when the last deployment failed.
find_resource() { # <resource type> <name prefix>
  az resource list -g "$RG" --resource-type "$1" \
    --query "[?starts_with(name, '$2')].name | [0]" -o tsv 2>/dev/null
}

# Names and endpoints used by the scripts (same keys as the Bicep outputs).
output() {
  case "$1" in
    resourceGroupName)            echo "$RG" ;;
    apiAppName)                   find_resource Microsoft.Web/sites "app-claimshub-api-" ;;
    apiUrl)                       echo "https://$(output apiAppName).azurewebsites.net" ;;
    validationFunctionAppName)    find_resource Microsoft.Web/sites "func-claimshub-val-" ;;
    processingFunctionAppName)    find_resource Microsoft.Web/sites "func-claimshub-proc-" ;;
    serviceBusNamespaceName)      find_resource Microsoft.ServiceBus/namespaces "sbns-claimshub-" ;;
    processingQueueName)          echo "claims-processing" ;;
    cosmosAccountName)            find_resource Microsoft.DocumentDB/databaseAccounts "cosmos-claimshub-" ;;
    keyVaultName)                 find_resource Microsoft.KeyVault/vaults "kv-claimshub-" ;;
    appConfigName)                find_resource Microsoft.AppConfiguration/configurationStores "appcs-claimshub-" ;;
    documentsStorageAccountName)  find_resource Microsoft.Storage/storageAccounts "stdocs" ;;
    logAnalyticsWorkspaceName)    find_resource Microsoft.OperationalInsights/workspaces "log-claimshub-" ;;
    appInsightsName)              find_resource Microsoft.Insights/components "appi-claimshub-" ;;
    *) echo "unknown output: $1" >&2; return 1 ;;
  esac
}

# Fail fast with a clear message if a lookup comes back empty.
require() { # <value> <description>
  if [[ -z "$1" ]]; then
    printf '\033[1;31m   FAIL\033[0m %s not found in %s. Has the infrastructure been deployed?\n' "$2" "$RG" >&2
    exit 1
  fi
}

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   OK\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m   FAIL\033[0m %s\n' "$*"; }
