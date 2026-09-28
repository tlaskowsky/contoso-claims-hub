# Contoso Claims Hub — Build Guide

Instructor guide for deploying and verifying the complete reference solution
(the end-of-course state) in a single environment. Not learner-facing.

Plan on about 1–1.5 hours for a first run, most of it waiting for deployments.

---

## 0. Prerequisites

Run everything from **bash** (macOS, Linux, WSL, or a Linux code-server instance).

| Tool | Check |
|---|---|
| Azure CLI (latest) + Bicep | `az version`, `az bicep version` |
| Node.js 22 LTS | `node -v` |
| Azure Functions Core Tools v4 | `func --version` |
| jq, zip, curl, git | `jq --version` |

Optional, so the Azure CLI installs extensions without prompting:

```bash
az config set extension.use_dynamic_install=yes_without_prompt
```

Sign in and register the resource providers (once per subscription):

```bash
az login --use-device-code
az account set --subscription "<subscription name or ID>"

for p in Microsoft.App Microsoft.Web Microsoft.DocumentDB Microsoft.ServiceBus \
         Microsoft.EventGrid Microsoft.KeyVault Microsoft.AppConfiguration \
         Microsoft.Storage Microsoft.Network Microsoft.Insights \
         Microsoft.OperationalInsights Microsoft.ManagedIdentity \
         Microsoft.PolicyInsights; do
  az provider register --namespace $p
done
```

`Microsoft.PolicyInsights` is needed for policy **compliance reporting**
(enforcement works without it, but the Compliance view stays empty).

### Region and quota

The parameter files use **Central US** and App Service **S1**. Before deploying
in any region, check two things:

```bash
# 1. Flex Consumption is offered
az functionapp list-flexconsumption-locations --query "[].name" -o tsv | grep -ix centralus
```

2. **App Service quota.** New subscriptions can have **zero** App Service quota
   in some regions. Portal → **Quotas** → **App Service** → filter by
   subscription and region → check the **S1 VMs** row. You need at least 1
   (3 if you want autoscale to be able to scale out). If it's 0, request an
   increase or choose a region where it isn't.

To change region or tier, edit `location` / `appServicePlanSku` in both files
under `infra/parameters/`.

---

## 1. Deploy infrastructure — pass 1 (about 10–15 minutes)

```bash
export ALERT_EMAIL="you@example.com"      # optional: receives alert emails
./scripts/deploy-infra.sh dev
```

Creates everything except the Event Grid subscription, with the data plane
already locked behind Private Endpoints.

**If it fails:**

| Error | Cause | Action |
|---|---|---|
| `Forbidden` on App Configuration `keyValues` | The deployer's App Configuration Data Owner role hasn't propagated yet (first run in a new resource group) | Wait 3–5 minutes, rerun |
| `PrincipalNotFound` on a role assignment | A new managed identity hasn't replicated in Entra ID yet | Rerun |
| `SubscriptionIsOverQuotaForSku` | No App Service quota for that tier in the region | See *Region and quota* above |
| "Virtual network resource not found" on a DNS zone link | Stale state from a recently deleted environment with the same names | Wait a few minutes, rerun |
| Key Vault name exists / soft-deleted | Previous environment not purged | Run `teardown.sh` first, or `export NAME_SEED=2` |

The deployment is idempotent: rerunning is always safe.

## 2. Deploy the applications (about 10 minutes)

```bash
./scripts/deploy-apps.sh dev
```

Builds and zip-deploys the API, then builds and publishes both Function apps
with their production dependencies packaged (Flex Consumption publishes
without a remote build). It ends by listing the registered functions:

```
validateDocument
approvalOrchestrator  checkAutoApproval  coverageCheck  documentationCheck  fraudCheck
getWorkflowStatus  processClaim  recordAssessment  recordDecision  submitApproval
```

If a Function app lists **no functions**, its package is missing dependencies —
check the publish output: the upload should be several MB, not a few KB.

## 3. Deploy infrastructure — pass 2 (Event Grid subscription)

Event Grid validates that `validateDocument` exists, so this runs after step 2:

```bash
./scripts/deploy-infra.sh dev --with-event-subscription
```

## 4. Run the end-to-end test (about 8 minutes)

```bash
./scripts/e2e-test.sh dev
```

| Scenario | Expected result |
|---|---|
| 1. Dependency health | cosmosDb, keyVault, appConfiguration, blobStorage all `OK` |
| 2. Happy path | Submitted → DocumentsValidated → Processing → **PendingApproval**; history lists the activities |
| 3. Human approval | **Approved** |
| 4. Invalid document | **DocumentRejected** — "file content does not match its declared content type" |
| 5. Poison message | Dead-letter count increases by 1 |

The first run takes a little longer while the Flex Consumption apps cold-start.

## 5. Verify the remaining lab outcomes

**Policy (Lab 1.1).** At least 30 minutes after the first deployment:

```bash
az vm create -g rg-claimshub-dev -n vm-policytest --image Ubuntu2204 --size Standard_B1s \
  --generate-ssh-keys --only-show-errors 2>&1 | grep -i -E "policy|disallowed" | head -3
az resource list -g rg-claimshub-dev --query "[?contains(name,'policytest')].name" -o tsv   # expect nothing
```

The CLI may print a traceback while formatting the error; the policy message
is what matters. In class, the Portal (*Create → Virtual machine*) shows the
denial more clearly. Portal → **Policy → Compliance** should show the four
assignments as compliant once the first evaluation has run.

**Lockdown (Lab 2.4).** From outside the VNet, with your own identity — which
holds the right data roles — every data-plane call is refused by the network:

```bash
nslookup <cosmos-account>.documents.azure.com        # CNAME via privatelink.documents.azure.com

az storage blob list --account-name <documents-storage-account> -c claim-documents \
  --auth-mode login -o tsv 2>&1 | head -3             # blocked by network rules

az keyvault secret show --vault-name <key-vault> --name PolicyAdminApiKey \
  --query name -o tsv 2>&1 | head -3                  # "Public network access is disabled…"

TOKEN=$(az account get-access-token --resource https://<cosmos-account>.documents.azure.com --query accessToken -o tsv)
curl -s -H "Authorization: type%3Daad%26ver%3D1.0%26sig%3D$TOKEN" -H "x-ms-version: 2018-12-31" \
  -H "x-ms-date: $(date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
  https://<cosmos-account>.documents.azure.com/dbs | jq -r '.code, .message' | head -c 300   # Forbidden … public internet
```

The resource names are in the deployment outputs
(`az deployment sub show -n claimshub-dev --query properties.outputs`).
Service Bus and App Configuration stay reachable from outside by design
(Microsoft Entra ID only).

**Dead-letter recovery (Lab 3.2).**

```bash
./scripts/set-appconfig.sh dev key "ClaimsHub:LegacyPolicySystemOnline" true    # fix the root cause first
```

Then Portal → Service Bus namespace → Queues → `claims-processing` →
**Service Bus Explorer**:

1. Click **Switch to Microsoft Entra authentication** (access keys are disabled).
2. **Dead-letter** tab → **Peek from start** → select the message →
   **Re-send selected messages**. The claim reaches **PendingApproval**.
3. Re-send **copies** the message; the original stays in the dead-letter queue.
   Remove it: **Receive mode** → **Receive messages** → **ReceiveAndDelete**
   (or PeekLock, then **Complete** within the lock period).

Set the key back to `false` afterwards.

**Feature flag (Module 3).**

```bash
./scripts/set-appconfig.sh dev flag AutoApproveLowValue true
```

Submit `tests/sample-claims/low-value-claim.json` with a valid document: it goes
straight to **Approved** with `decision.approver = system:auto-approval`. Set
the flag back to `false`.

**Observability (Lab 3.1).**

- Alert rules: `alert-validation-failure-rate` and `alert-dlq-accumulation`
  (`az monitor scheduled-query list` / `az monitor metrics alert list`).
- Application Insights → **Logs** (turn the *Agent* toggle off for the plain
  KQL editor): run the queries in `queries/`.
- Application Insights → **Workbooks** → **+ New** → the workbook-level
  **`</>`** (Advanced Editor, with *Gallery Template* / *ARM Template* tabs) →
  paste `monitoring/claimshub-workbook.json` → **Apply** → **Save**.
  (The `</>` inside an individual tile edits only that tile.)

**Autoscale (Lab 3.2).** Portal → App Service plan → **Scale out**: CPU rule,
1–3 instances. Cosmos DB → `claims` container → **Scale**: autoscale, max
1,000 RU/s.

## 6. Second environment (Lab 3.3, optional during build)

```bash
./scripts/deploy-infra.sh test
./scripts/deploy-apps.sh test
./scripts/deploy-infra.sh test --with-event-subscription
./scripts/e2e-test.sh test
./scripts/teardown.sh test
```

`test` differs only by its parameter file (name, no Cosmos DB free tier).

## 7. Teardown between work sessions

```bash
./scripts/teardown.sh dev
```

Deletes the resource group and purges the soft-deleted Key Vault and App
Configuration store, so the next deployment can reuse the same names. The saved
workbook is deleted too; re-import it from `monitoring/` when needed.

---

## Design notes

Deliberate choices in the reference solution, and the reasons behind them.

- **Service Bus stays public (Standard tier).** Private Endpoints require the
  Premium tier, which isn't cost-justified for a training environment. Access is
  Microsoft Entra ID only (SAS keys disabled). Production: Premium with a Private
  Endpoint.
- **App Configuration stays public (Entra ID only).** Azure Resource Manager
  can't deploy key-values into a private-only store unless the deployment runs
  through Resource Management Private Link. Production: deploy configuration
  from a pipeline agent inside the network.
- **Two Function apps:** validation, and processing + Durable approval.
- **Documents are uploaded through the API**, not directly to Storage, so
  uploads keep working after the data plane is locked down.
- **Managed-identity access is verified through the API's
  `/health/dependencies` endpoint** — a managed identity can't be exercised
  from a laptop CLI.
- **Cosmos DB Data Explorer stops working after lockdown.** From then on,
  claims are inspected through the API — a teaching point, not a defect.
- **Dead-letter recovery includes a root-cause fix.** A simulated legacy policy
  system is "offline" until a configuration key is changed.
- **The API answers App Service platform probes** (`GET /` for Always On, the
  container warm-up probe) so they don't appear as failed requests, and names
  request telemetry by route (`GET /claims/:claimId`).
- **Flex Consumption apps report no `defaultHostName`** through
  `az functionapp show`; scripts build the hostname from the app name.

## Not included yet

- The capstone reference solution
- The app registration demo script
- Learner `start/` versions and the lab guides
