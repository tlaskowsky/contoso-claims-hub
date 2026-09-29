# Contoso Claims Hub — final solution

Reference implementation of the end-of-course state for a 3-day Azure
Solution Architect course. Instructor material — not learner-facing.

## Architecture

```
               ┌───────────────────────── VNet (Private Endpoints, private DNS) ─────────────────────────┐
 curl / client │                                                                                         │
      │        │   Key Vault      App Configuration      Cosmos DB (claims, /claimId)     Storage x2     │
      ▼        │       ▲                ▲                     ▲        ▲        ▲          ▲      ▲      │
 Claims Intake API ────┴────────────────┴─────────────────────┘        │        │          │      │      │
 (App Service) ──── uploads document ──────────────────────────────────┼────────┼──► claim-documents     │
               │                                                       │        │          │             │
               │        Event Grid (BlobCreated) ◄─────────────────────┼────────┼──────────┘             │
               │               │                                       │        │                        │
               │               ▼                                       │        │                        │
               │   validateDocument (Flex Function) ──────────────────►┘        │                        │
               │               │ ClaimReadyForProcessing                        │                        │
               └───────────────┼────────────────────────────────────────────────┼────────────────────────┘
                               ▼                                                │
                Service Bus queue: claims-processing (DLQ after 3 deliveries)   │
                  (Standard tier - public endpoint, Entra ID only)               │
                               │                                                │
                               ▼                                                │
               processClaim ──► approvalOrchestrator (Durable) ─────────────────┘
                                 fan-out: fraud | coverage | documentation
                                 wait: ApprovalDecision event (HTTP) or 72 h timeout

 Observability: Application Insights (Entra-only ingestion) + Log Analytics, 2 alerts
 Governance:    tag-inheritance policies + deny VMs/VMSS/AKS on the resource group
 Public by design (Entra ID only): Service Bus (Standard tier), App Configuration (ARM deploys key-values)
```

## Repository

| Path | Contents |
|---|---|
| `infra/` | Annotated single source of truth: the complete final solution, with lab markers |
| `labs/lab-X.Y/{start,solution}/infra/` | Generated per-lab versions (do not edit - regenerate with `tools/generate-labs.py`) |
| `tools/generate-labs.py` | Generates every lab from `infra/` and checks each solution compiles |
| `infra/modules/` | One module per service |
| `infra/parameters/` | `dev` (S1, Private Endpoints) and `test` (B1, public) parameter files |
| `src/api/` | Claims Intake API (Express, TypeScript) |
| `src/functions-validation/` | `validateDocument` — Event Grid trigger, Service Bus output |
| `src/functions-processing/` | `processClaim`, Durable `approvalOrchestrator` + activities, approval HTTP endpoints |
| `scripts/` | Deploy, test, App Configuration change, teardown, package build |
| `scripts/instructor/` | Class setup (guests, resource groups, roles), quota check, course teardown |
| `tests/` | Sample claims (auto, home, health, commercial, low-value, legacy) and documents |
| `queries/` | KQL: trace one claim, DLQ accumulation, stage latency |

`LAB-BLANK(x.y)` comments mark candidate blanks for the learner start versions.

## Working through the labs

```bash
export LEARNER_ID=s01
./scripts/start-lab.sh 1.1          # copies the lab's start version (with TODOs) to workspace/infra
# ...complete the TODOs, following the lab guide...
./scripts/deploy-infra.sh dev       # deploys workspace/infra
./scripts/solution-lab.sh 1.1       # (only if you need to catch up)
```

## Quick start (complete solution, no workspace)

```bash
export LEARNER_ID=s01                               # your learner ID
./scripts/deploy-infra.sh dev
./scripts/deploy-apps.sh dev
./scripts/deploy-infra.sh dev --with-event-subscription
./scripts/e2e-test.sh dev
```

Each learner deploys into resource groups prepared by the instructor
(`rg-claimshub-<id>-dev` / `-test`). See `BUILD-GUIDE.md` for class setup.
