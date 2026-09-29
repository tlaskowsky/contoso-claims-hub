# Contoso Claims Hub — Build Guide

Instructor guide for preparing a class and deploying the complete reference
solution (the end-of-course state). Not learner-facing.

Plan on about 1–1.5 hours for a first run, most of it waiting for deployments.

---

## How environments are organized

The class shares **one subscription**. Every person has a learner ID —
`s01`–`s16` for students, `i01` for the instructor — and three pre-created
resource groups:

| Resource group | Used for |
|---|---|
| `rg-claimshub-<id>-dev` | The environment built across the three days (S1, Private Endpoints) |
| `rg-claimshub-<id>-test` | The Lab 3.3 second environment (B1, no Private Endpoints) |
| `rg-claimshub-<id>-shell` | Cloud Shell storage (kept separate so teardown never touches it) |

Learners are **Owner of their own resource groups only**. They can't see each
other's environments or change anything at subscription level.

## 0. Class setup (instructor, a day or two before class)

Tools (instructor machine): Azure CLI + Bicep, Node.js 22, jq, zip, git, GitHub
CLI. Learners need nothing but a browser — Cloud Shell has the Azure CLI and Bicep.

```bash
az login --use-device-code
az account set --subscription "<training subscription>"

cp scripts/instructor/learners.example.csv learners.csv    # edit: one line per learner
./scripts/instructor/setup-class.sh learners.csv
./scripts/instructor/check-quotas.sh 17                     # learners + instructor
```

`setup-class.sh` registers the resource providers, invites each learner as a
guest, creates their three resource groups, and assigns **Owner** plus
**App Configuration Data Owner** (granted in advance so the first deployment
doesn't hit a role-propagation `Forbidden`). Learners must accept the
invitation email before class. Keep `learners.csv` out of the repository.

`check-quotas.sh` checks App Service S1/B1 headroom, resource counts, and
provider registration. The App Service tiers are the tight ones: every dev
environment needs 1 S1 instance, every test environment 1 B1 instance.

**Pre-create the App Service plans — the day before class:**

```bash
./scripts/instructor/precreate-plans.sh learners.csv      # ~2.5 hours for 17 learners (dev + test)
```

Azure **throttles App Service plan creation** per subscription and region
(stricter for new subscriptions; a throttle can last up to 48 hours). Seventeen
learners each deploying three plans at once would hit it. The script creates
every plan in advance, one at a time with a pause between each, and waits out
any throttle. Learners' deployments then only *update* existing plans.
Flex Consumption plans cost nothing idle; S1/B1 plans are billed from
creation — hence the day before. If Azure throttles anyway, open a support
ticket (Service and subscription limits → App Service) describing the class.

Avoid repeated build/teardown cycles in the training subscription in the days
before class — every plan created counts toward the throttle.

**Publish the application packages** (after any code change):

```bash
./scripts/build-packages.sh --release     # builds packages/*.zip and publishes a GitHub release
```

Learners' `deploy-apps.sh` downloads these ready-built packages, so nobody
needs Node.js or Functions Core Tools in class.

## 1. Deploy infrastructure — pass 1 (about 10–15 minutes)

Every person, in their own shell:

```bash
export LEARNER_ID=s01                     # your ID; add to ~/.bashrc to keep it
./scripts/deploy-infra.sh dev
```

**If it fails:**

| Error | Cause | Action |
|---|---|---|
| `Resource group rg-claimshub-… not found` | Wrong `LEARNER_ID`, or class setup not run | Check the ID |
| `Forbidden` on App Configuration `keyValues` | Data Owner role not yet effective | Wait 3–5 minutes, rerun |
| `PrincipalNotFound` on a role assignment | A new managed identity hasn't replicated yet | Rerun |
| `SubscriptionIsOverQuotaForSku` | App Service quota exhausted | Instructor: `check-quotas.sh` |
| Plans stay "Running" for many minutes; `App Service Plan Create operation is throttled` | Plan-creation throttle | Plans should have been pre-created (`precreate-plans.sh`); otherwise wait, don't retry repeatedly |
| "Virtual network resource not found" on a DNS link | Stale state from a recently deleted environment | Wait a few minutes, rerun |

Reruns are always safe.

## 2. Deploy the applications (about 5 minutes)

```bash
./scripts/deploy-apps.sh dev                  # uses the published packages
./scripts/deploy-apps.sh dev --from-source    # instructor: build locally instead
```

It deploys the API (retrying automatically if a new App Service times out)
and both Function apps, then lists the registered functions:

```
validateDocument
approvalOrchestrator  checkAutoApproval  coverageCheck  documentationCheck  fraudCheck
getWorkflowStatus  processClaim  recordAssessment  recordDecision  submitApproval
```

## 3. Deploy infrastructure — pass 2 (Event Grid subscription)

Event Grid validates that `validateDocument` exists, so this runs after step 2:

```bash
./scripts/deploy-infra.sh dev --with-event-subscription
```

Run each step only after the previous one succeeded.

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
az vm create -g rg-claimshub-$LEARNER_ID-dev -n vm-policytest --image Ubuntu2204 --size Standard_B1s \
  --generate-ssh-keys --only-show-errors 2>&1 | grep -i -E "policy|disallowed" | head -3
az resource list -g rg-claimshub-$LEARNER_ID-dev --query "[?contains(name,'policytest')].name" -o tsv   # expect nothing
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
(`az deployment group show -g rg-claimshub-$LEARNER_ID-dev -n claimshub-$LEARNER_ID-dev --query properties.outputs`).
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

## 6. Second environment (Lab 3.3)

```bash
./scripts/deploy-infra.sh test
./scripts/deploy-apps.sh test
./scripts/deploy-infra.sh test --with-event-subscription
./scripts/e2e-test.sh test
./scripts/teardown.sh test
```

`test.parameters.json` differs from dev: B1 instead of S1, no autoscale, no
Private Endpoints. Its plans are pre-created too (`precreate-plans.sh`).
**Fallback:** if a learner's test deployment is still running after 20
minutes, move them on to the capstone — the point of the lab (same code,
different parameter file) is made either way. It's deliberately cheaper — a realistic non-production
pattern, and it keeps the shared S1 quota free.

## 7. Teardown

**Learners / between sessions:** `./scripts/teardown.sh <env>` deletes every
resource in that environment but keeps the resource group and your access.
Deleted Key Vaults and App Configuration stores stay soft-deleted; to redeploy
the same environment afterwards, `export NAME_SEED=2` first.

**Instructor, after the course:**

```bash
./scripts/instructor/course-teardown.sh learners.csv --remove-guests
```

Deletes every `rg-claimshub-*` group, purges soft-deleted Key Vaults and App
Configuration stores, and removes the guest accounts.

---

## Quota design (shared subscription)

| Resource | Per person | Choice |
|---|---|---|
| App Service (dev) | 1 × S1 | Autoscale 1–2 instances (`autoscaleMaxInstances`) |
| App Service (test) | 1 × B1 | Separate quota from S1; no autoscale |
| Function apps | 2 per environment | 512 MB instances (regional Flex memory quota is 512,000 MB) |
| Cosmos DB | 1 account per environment | No free tier (one per subscription) |
| App Configuration | Developer tier | No per-subscription store limit |

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
- **Incremental states run cleanly:** the API reports services added in later
  labs as "not configured yet"; validated claims wait in DocumentsValidated
  until Service Bus exists (Lab 2.2); the approval workflow stays off until
  `APPROVAL_WORKFLOW_ENABLED` is set (Lab 2.3); telemetry starts in Lab 3.1.
- **Cosmos DB starts on manual 400 RU/s**; Lab 3.2 migrates the container to
  autoscale (`az cosmosdb sql container throughput migrate`) *before* the Bicep
  switches to `autoscaleSettings` — ARM can't change the throughput type itself.
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
- **Autoscale reacts only to sustained load** (CPU > 80% over 15 minutes).
  A new plan's provisioning spike otherwise triggered a scale-out to 2
  instances, doubling S1 quota use.
- **The first document upload can take up to a minute** while the validation
  Function app cold-starts from zero; later ones take seconds.
- **Flex Consumption apps report no `defaultHostName`** through
  `az functionapp show`; scripts build the hostname from the app name.

## Not included yet

- The capstone reference solution
- The app registration demo script
- Learner `start/` versions and the lab guides
